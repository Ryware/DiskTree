import Foundation
import CryptoKit
import os

/// A set of files with identical content.
struct DuplicateGroup: Identifiable, Hashable {
    let id: String              // content hash
    let size: Int64             // size of one copy
    let files: [FileNode]       // every copy, newest first
    var count: Int { files.count }
    /// Space that would come back if all but one copy were removed.
    var wasted: Int64 { size * Int64(count - 1) }

    static func == (l: DuplicateGroup, r: DuplicateGroup) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct DuplicateScanResult {
    var groups: [DuplicateGroup] = []
    var filesConsidered = 0
    var filesHashed = 0
    var bytesHashed: Int64 = 0
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
}

/// Progress the UI polls while a duplicate scan runs.
final class DuplicateCounters: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (done: 0, total: 0, bytes: Int64(0), current: "", phase: ""))
    func start(phase: String, total: Int) { lock.withLock { $0.phase = phase; $0.total = total; $0.done = 0 } }
    func tick(bytes: Int64, current: String) { lock.withLock { $0.done += 1; $0.bytes += bytes; $0.current = current } }
    var snapshot: (done: Int, total: Int, bytes: Int64, current: String, phase: String) { lock.withLock { $0 } }
}

struct DuplicateOptions {
    /// Files smaller than this are ignored. Small duplicates are everywhere (configs, icons) and reclaim nothing.
    var minimumSize: Int64 = 1 << 20
    /// Files inside app bundles and other packages are skipped: bundles legitimately share resources.
    var skipPackages = true
    /// Symlinks are never content.
    var skipSymlinks = true
}

/// Finds files with identical content in a scanned tree.
///
/// Three passes, each cheaper than the next would be:
/// 1. group by size (free — the scan already knows every size);
/// 2. for sizes shared by 2+ files, hash the first 64 KB and regroup;
/// 3. for candidates still matching, hash the whole file (SHA-256, streamed) and regroup.
/// Only pass 3 reads whole files, and it runs only on files that already agree on size and prefix.
struct DuplicateFinder {
    let counters: DuplicateCounters
    var options = DuplicateOptions()

    private static let prefixBytes = 64 * 1024

    func find(in root: FileNode) async throws -> DuplicateScanResult {
        var result = DuplicateScanResult()

        // Pass 1: size buckets. Free: the scan already knows every size.
        counters.start(phase: "Grouping by size", total: 0)
        var bySize: [Int64: [FileNode]] = [:]
        root.walk { n in
            guard !n.isDirectory, !(options.skipSymlinks && n.isSymlink),
                  n.logicalSize >= options.minimumSize else { return }
            if options.skipPackages && Self.isInsidePackage(n) { return }
            result.filesConsidered += 1
            bySize[n.logicalSize, default: []].append(n)
        }
        var groups = bySize.values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return result }
        try Task.checkCancellation()

        // Pass 2: first 64 KB. Pass 3: 64 KB from the middle and the end (big files only).
        // Pass 4: full SHA-256 of whatever still matches. Each pass only reads files that
        // survived the previous one, so large files that merely share a size are never read in full.
        groups = try await Self.refine(groups, mode: .head, phase: "Comparing file headers", counters: counters).groups
        try Task.checkCancellation()
        groups = try await Self.refine(groups, mode: .samples, phase: "Sampling large files", counters: counters).groups
        try Task.checkCancellation()
        let survivors = groups.flatMap { $0 }
        result.filesHashed = survivors.count
        result.bytesHashed = survivors.reduce(0) { $0 + $1.logicalSize }
        let final = try await Self.refine(groups, mode: .full, phase: "Verifying byte for byte", counters: counters)

        result.groups = final.groups.compactMap { nodes -> DuplicateGroup? in
            guard nodes.count > 1, let first = nodes.first else { return nil }
            let sorted = nodes.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            let id = final.keys[ObjectIdentifier(first)] ?? "\(first.logicalSize):\(first.id.uuidString)"
            return DuplicateGroup(id: id, size: first.logicalSize, files: sorted)
        }
        .sorted { $0.wasted == $1.wasted ? $0.id < $1.id : $0.wasted > $1.wasted }
        return result
    }

    enum HashMode { case head, samples, full }

    /// Hashes every file of every group with `mode` and splits the groups by the result.
    /// Groups that end up with a single member are dropped. Files too small for `mode`
    /// (samples on a file shorter than three chunks) keep their group untouched.
    private static func refine(_ groups: [[FileNode]], mode: HashMode, phase: String,
                               counters: DuplicateCounters) async throws -> (groups: [[FileNode]], keys: [ObjectIdentifier: String]) {
        let needsWork = groups.filter { g in mode != .samples || (g.first?.logicalSize ?? 0) > Int64(3 * prefixBytes) }
        let untouched = groups.filter { g in mode == .samples && (g.first?.logicalSize ?? 0) <= Int64(3 * prefixBytes) }
        let nodes = needsWork.flatMap { $0 }
        guard !nodes.isEmpty else { return (groups, [:]) }
        counters.start(phase: phase, total: nodes.count)
        let keyed = try await hashAll(nodes, counters: counters, mode: mode)
        var byKey: [String: [FileNode]] = [:]
        var keys: [ObjectIdentifier: String] = [:]
        for (node, key) in keyed {
            byKey[key, default: []].append(node)
            keys[ObjectIdentifier(node)] = key
        }
        return (byKey.values.filter { $0.count > 1 } + untouched, keys)
    }

    // MARK: - Helpers

    private static func isInsidePackage(_ node: FileNode) -> Bool {
        var p = node.parent
        while let n = p {
            if n.isPackage { return true }
            p = n.parent
        }
        return false
    }

    /// Hashes files in parallel. Keys are "size:hex" so two different sizes can never collide.
    /// A file that cannot be read gets a unique key and so never matches anything.
    private static func hashAll(_ nodes: [FileNode], counters: DuplicateCounters, mode: HashMode) async throws -> [(FileNode, String)] {
        let results = OSAllocatedUnfairLock(initialState: [(FileNode, String)]())
        results.withLock { $0.reserveCapacity(nodes.count) }
        // Bound parallel I/O: hashing is disk-bound, and hundreds of concurrent large reads thrash.
        let width = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
        let stride = max(1, (nodes.count + width - 1) / width)
        await Task.detached(priority: .userInitiated) {
            DispatchQueue.concurrentPerform(iterations: width) { lane in
                let lo = lane * stride, hi = min(nodes.count, lo + stride)
                guard lo < hi else { return }
                // One reusable read buffer per lane: hashing never allocates per chunk, so a lane
                // that reads hundreds of gigabytes stays at a few megabytes of memory.
                let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkBytes, alignment: 16)
                defer { buffer.deallocate() }
                for i in lo..<hi {
                    if Task.isCancelled { return }
                    // concurrentPerform blocks only drain their autorelease pool when the whole
                    // lane returns; drain per file so nothing Foundation hands back piles up.
                    autoreleasepool {
                        let node = nodes[i]
                        let key: String
                        if let digest = hash(path: node.path, mode: mode, size: node.logicalSize, buffer: buffer) {
                            key = "\(node.logicalSize):\(digest)"
                        } else {
                            key = "unreadable:\(node.id.uuidString)"
                        }
                        let read: Int64
                        switch mode {
                        case .head: read = Int64(min(prefixBytes, Int(node.logicalSize)))
                        case .samples: read = Int64(2 * prefixBytes)
                        case .full: read = node.logicalSize
                        }
                        counters.tick(bytes: read, current: node.path)
                        results.withLock { $0.append((node, key)) }
                    }
                }
            }
        }.value
        try Task.checkCancellation()
        return results.withLock { $0 }
    }

    /// Size of one read: 1 MB. Head and sample reads are 64 KB, full reads stream 1 MB at a time.
    private static let chunkBytes = 1 << 20

    /// SHA-256 of the first 64 KB (head), of 64 KB from the middle plus the last 64 KB (samples),
    /// or of the whole file streamed in 1 MB chunks (full).
    ///
    /// Reads with pread(2) into `buffer` (at least `chunkBytes` long) and feeds the hasher
    /// directly. `FileHandle.read` returned a fresh autoreleased `Data` per chunk, and inside a
    /// GCD lane those were only released when the lane finished, so a scan held every byte it
    /// had hashed in memory (tens of GB on a big tree) and the machine started paging and
    /// killing other processes.
    static func hash(path: String, mode: HashMode, size: Int64, buffer: UnsafeMutableRawBufferPointer) -> String? {
        precondition(buffer.count >= chunkBytes)
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var hasher = SHA256()

        /// Feeds up to `limit` bytes starting at `offset`. Returns false on a read error.
        func feed(from offset: Int64, upTo limit: Int) -> Bool {
            var position = off_t(offset)
            var remaining = limit
            while remaining > 0 {
                let n = pread(fd, buffer.baseAddress, min(chunkBytes, remaining), position)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if n == 0 { break }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
                position += off_t(n)
                remaining -= n
            }
            return true
        }

        switch mode {
        case .head:
            guard feed(from: 0, upTo: prefixBytes) else { return nil }
        case .samples:
            let mid = max(0, size / 2 - Int64(prefixBytes / 2))
            let tail = max(0, size - Int64(prefixBytes))
            for offset in [mid, tail] {
                guard feed(from: offset, upTo: prefixBytes) else { return nil }
            }
        case .full:
            guard feed(from: 0, upTo: Int.max) else { return nil }
        }
        return hex(hasher.finalize())
    }

    /// Hashes with a buffer of its own. Use the `buffer:` overload when hashing many files.
    static func hash(path: String, mode: HashMode, size: Int64) -> String? {
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkBytes, alignment: 16)
        defer { buffer.deallocate() }
        return hash(path: path, mode: mode, size: size, buffer: buffer)
    }

    /// Lowercase hex without going through `String(format:)` (an NSString round trip per byte).
    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        let table: [UInt8] = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(64)
        for byte in digest {
            out.append(table[Int(byte >> 4)])
            out.append(table[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Convenience used by tests and tooling.
    static func hash(path: String, full: Bool) -> String? {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        return hash(path: path, mode: full ? .full : .head, size: size)
    }
}
