import Foundation
import AppKit
import Darwin
import os

enum DeleteMode: String, CaseIterable, Identifiable {
    case trash, permanent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: return "Move to Trash"
        case .permanent: return "Delete permanently (fast)"
        }
    }
    /// Verb for buttons: "Move to Trash…" / "Delete Permanently…"
    var actionLabel: String { self == .trash ? "Move to Trash…" : "Delete Permanently…" }
    var symbol: String { self == .trash ? "trash" : "flame" }
    var shortNote: String { self == .trash ? "Deleted items go to the Trash (recoverable)" : "Deleted items are removed immediately (no undo)" }
}

struct DeleteResult {
    var removedFiles = 0
    var removedDirectories = 0
    var freedBytes: Int64 = 0
    var errors: [(path: String, message: String)] = []
}

final class DeleteCounters: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (done: 0, total: 0, bytes: Int64(0)))
    func setTotal(_ n: Int) { lock.withLock { $0.total = n } }
    func tick(bytes: Int64, count: Int = 1) { lock.withLock { $0.done += count; $0.bytes += bytes } }
    var snapshot: (done: Int, total: Int, bytes: Int64) { lock.withLock { $0 } }
}

/// Fast recursive remover.
///
/// 1. Each selected root is atomically renamed to a hidden sibling (`.disktree-rm-<id>`),
///    so from the user's point of view it vanishes instantly (rimraf's "move-remove" idea).
/// 2. Every directory in the subtree opens its own dirfd and unlinks its files with
///    `unlinkat(dirfd, name)` — no path walk per file. Directories are processed in
///    parallel across all cores (like rimraf's async posix strategy).
/// 3. Empty directories are removed deepest-first, each level in parallel.
struct Deleter {
    let mode: DeleteMode
    let counters: DeleteCounters

    func delete(_ nodes: [FileNode]) async -> DeleteResult {
        switch mode {
        case .trash: return await trash(nodes)
        case .permanent: return await remove(nodes)
        }
    }

    // MARK: Trash

    private func trash(_ nodes: [FileNode]) async -> DeleteResult {
        var result = DeleteResult()
        counters.setTotal(nodes.count)
        // NSWorkspace.recycle is the async, Finder-backed API; FileManager.trashItem can
        // block indefinitely when called off the main thread.
        let urls = nodes.map(\.url)
        let (moved, error): ([URL: URL], Error?) = await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(urls) { newURLs, err in
                    cont.resume(returning: (newURLs, err))
                }
            }
        }
        for node in nodes {
            if moved[node.url] != nil {
                result.removedFiles += node.fileCount
                result.removedDirectories += node.directoryCount + (node.isDirectory ? 1 : 0)
                result.freedBytes += node.allocatedSize
            } else {
                result.errors.append((node.path, error?.localizedDescription ?? "Could not move to Trash"))
            }
            counters.tick(bytes: node.allocatedSize)
        }
        return result
    }

    // MARK: Permanent, parallel

    /// A directory to empty: its (possibly renamed) path, file children, and depth.
    private struct DirJob {
        let path: String
        let files: [(name: String, bytes: Int64)]
        let depth: Int
    }

    private func remove(_ nodes: [FileNode]) async -> DeleteResult {
        var result = DeleteResult()
        var dirJobs: [DirJob] = []
        var looseFiles: [(path: String, bytes: Int64)] = []   // selected roots that are files
        var totalFiles = 0
        var stashed: [(work: String, original: String)] = []

        for root in nodes {
            // Step 1: hide the root immediately.
            let workPath = Self.stash(root.path) ?? root.path
            if workPath != root.path { stashed.append((workPath, root.path)) }

            if !root.isDirectory {
                looseFiles.append((workPath, root.allocatedSize))
                totalFiles += 1
                continue
            }
            // Collect directory jobs with paths rebased onto the stashed root.
            root.walk { n in
                guard n.isDirectory else { return }
                let rel = String(n.path.dropFirst(root.path.count))
                let path = workPath + rel
                let files = n.children.filter { !$0.isDirectory }.map { ($0.name, $0.allocatedSize) }
                totalFiles += files.count
                dirJobs.append(DirJob(path: path, files: files, depth: n.url.pathComponents.count))
            }
        }
        counters.setTotal(totalFiles + dirJobs.count)

        let errorLock = OSAllocatedUnfairLock(initialState: [(path: String, message: String)]())
        let counters = self.counters
        let jobs = dirJobs
        let loose = looseFiles

        // Step 2: unlink files. One dirfd per directory, directories in parallel.
        let (files, bytes) = await Task.detached(priority: .userInitiated) { () -> (Int, Int64) in
            let ok = OSAllocatedUnfairLock(initialState: (0, Int64(0)))
            DispatchQueue.concurrentPerform(iterations: jobs.count + 1) { i in
                if i == jobs.count {
                    for f in loose {
                        if Self.unlinkPath(f.path) { ok.withLock { $0.0 += 1; $0.1 += f.bytes } }
                        else { errorLock.withLock { $0.append((f.path, String(cString: strerror(errno)))) } }
                        counters.tick(bytes: f.bytes)
                    }
                    return
                }
                let job = jobs[i]
                guard !job.files.isEmpty else { return }
                let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else {
                    errorLock.withLock { $0.append((job.path, String(cString: strerror(errno)))) }
                    counters.tick(bytes: 0, count: job.files.count)
                    return
                }
                defer { close(fd) }
                var n = 0, b: Int64 = 0
                for f in job.files {
                    if Self.unlinkAt(fd, f.name, dirPath: job.path) { n += 1; b += f.bytes }
                    else { errorLock.withLock { $0.append((job.path + "/" + f.name, String(cString: strerror(errno)))) } }
                }
                let removedCount = n
                let removedBytes = b
                counters.tick(bytes: removedBytes, count: job.files.count)
                ok.withLock { $0.0 += removedCount; $0.1 += removedBytes }
            }
            return ok.withLock { $0 }
        }.value
        result.removedFiles = files
        result.freedBytes = bytes

        // Step 3: directories, deepest first; each level in parallel.
        let byDepth = Dictionary(grouping: jobs, by: \.depth)
        for depth in byDepth.keys.sorted(by: >) {
            let level = byDepth[depth]!
            let n = await Task.detached(priority: .userInitiated) { () -> Int in
                let ok = OSAllocatedUnfairLock(initialState: 0)
                DispatchQueue.concurrentPerform(iterations: level.count) { i in
                    let path = level[i].path
                    if rmdir(path) == 0 {
                        ok.withLock { $0 += 1 }
                    } else {
                        // Anything odd (leftover entries, flags) → Foundation fallback.
                        do {
                            try FileManager.default.removeItem(atPath: path)
                            ok.withLock { $0 += 1 }
                        } catch {
                            errorLock.withLock { $0.append((path, error.localizedDescription)) }
                        }
                    }
                }
                counters.tick(bytes: 0, count: level.count)
                return ok.withLock { $0 }
            }.value
            result.removedDirectories += n
        }

        // Report errors under the original names, not the hidden stash names.
        result.errors = errorLock.withLock { $0 }.map { e in
            if let m = stashed.first(where: { e.path.hasPrefix($0.work) }) {
                return (m.original + e.path.dropFirst(m.work.count), e.message)
            }
            return e
        }
        return result
    }

    /// Atomically rename `path` to a hidden sibling so it disappears at once.
    /// Returns the new path, or nil if the rename was refused (then we delete in place).
    private static func stash(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        let hidden = parent + "/.disktree-rm-" + String(UInt32.random(in: 0...UInt32.max), radix: 36)
        return rename(path, hidden) == 0 ? hidden : nil
    }

    /// unlinkat(2) relative to an open directory; clears immutable flags on EPERM.
    private static func unlinkAt(_ fd: Int32, _ name: String, dirPath: String) -> Bool {
        if unlinkat(fd, name, 0) == 0 { return true }
        if errno == EPERM || errno == EACCES {
            let full = dirPath + "/" + name
            _ = lchflags(full, 0)
            _ = fchmodat(fd, name, 0o600, AT_SYMLINK_NOFOLLOW)
            if unlinkat(fd, name, 0) == 0 { return true }
        }
        return false
    }

    private static func unlinkPath(_ path: String) -> Bool {
        if unlink(path) == 0 { return true }
        if errno == EPERM || errno == EACCES {
            _ = lchflags(path, 0)
            _ = chmod(path, 0o600)
            if unlink(path) == 0 { return true }
        }
        return false
    }
}
