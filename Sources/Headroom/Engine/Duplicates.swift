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
    private let lock = OSAllocatedUnfairLock(initialState: (done: 0, total: 0, bytes: Int64(0), current: ""))
    func setTotal(_ n: Int) { lock.withLock { $0.total = n } }
    func tick(bytes: Int64, current: String) { lock.withLock { $0.done += 1; $0.bytes += bytes; $0.current = current } }
    var snapshot: (done: Int, total: Int, bytes: Int64, current: String) { lock.withLock { $0 } }
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

        // Pass 1: size buckets.
        var bySize: [Int64: [FileNode]] = [:]
        root.walk { n in
            guard !n.isDirectory, !(options.skipSymlinks && n.isSymlink),
                  n.logicalSize >= options.minimumSize else { return }
            if options.skipPackages && Self.isInsidePackage(n) { return }
            result.filesConsidered += 1
            bySize[n.logicalSize, default: []].append(n)
        }
        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        counters.setTotal(candidates.count)
        guard !candidates.isEmpty else { return result }
        try Task.checkCancellation()

        // Pass 2: prefix hash. Pass 3: full hash. Both parallel over files, grouped afterwards.
        let prefixKeys = try await Self.hashAll(candidates, counters: counters, full: false)
        var byPrefix: [String: [FileNode]] = [:]
        for (node, key) in prefixKeys { byPrefix[key, default: []].append(node) }
        let stillMatching = byPrefix.values.filter { $0.count > 1 }.flatMap { $0 }
        try Task.checkCancellation()

        counters.setTotal(stillMatching.count)
        let fullKeys = try await Self.hashAll(stillMatching, counters: counters, full: true)
        var byHash: [String: [FileNode]] = [:]
        for (node, key) in fullKeys { byHash[key, default: []].append(node) }

        result.filesHashed = stillMatching.count
        result.bytesHashed = stillMatching.reduce(0) { $0 + $1.logicalSize }
        result.groups = byHash.compactMap { hash, nodes -> DuplicateGroup? in
            guard nodes.count > 1, let size = nodes.first?.logicalSize else { return nil }
            let sorted = nodes.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            return DuplicateGroup(id: hash, size: size, files: sorted)
        }
        .sorted { $0.wasted == $1.wasted ? $0.id < $1.id : $0.wasted > $1.wasted }
        return result
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
    private static func hashAll(_ nodes: [FileNode], counters: DuplicateCounters, full: Bool) async throws -> [(FileNode, String)] {
        let results = OSAllocatedUnfairLock(initialState: [(FileNode, String)]())
        results.withLock { $0.reserveCapacity(nodes.count) }
        await Task.detached(priority: .userInitiated) {
            DispatchQueue.concurrentPerform(iterations: nodes.count) { i in
                if Task.isCancelled { return }
                let node = nodes[i]
                let key: String
                if let digest = hash(path: node.path, full: full) {
                    key = "\(node.logicalSize):\(digest)"
                } else {
                    key = "unreadable:\(node.id.uuidString)"
                }
                counters.tick(bytes: full ? node.logicalSize : Int64(min(prefixBytes, Int(node.logicalSize))), current: node.path)
                results.withLock { $0.append((node, key)) }
            }
        }.value
        try Task.checkCancellation()
        return results.withLock { $0 }
    }

    /// SHA-256 of the first 64 KB (prefix) or the whole file (full), streamed in 1 MB chunks.
    static func hash(path: String, full: Bool) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        if !full {
            guard let data = try? handle.read(upToCount: prefixBytes) else { return nil }
            hasher.update(data: data)
        } else {
            let chunk = 1 << 20
            while true {
                guard let data = try? handle.read(upToCount: chunk) else { return nil }
                if data.isEmpty { break }
                hasher.update(data: data)
                if data.count < chunk { break }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
