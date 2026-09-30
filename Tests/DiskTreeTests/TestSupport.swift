import Foundation
@testable import DiskTree

enum TestSupport {
    /// Fresh temp directory (symlinks resolved so paths match what the scanner reports).
    static func makeTempDir(_ label: String = "tree") throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let dir = base.appendingPathComponent("disktree-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func write(_ url: URL, bytes: Int) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    static func scan(_ root: URL, options: ScanOptions = ScanOptions()) async throws -> (FileNode, ScanCounters) {
        let counters = ScanCounters()
        let node = try await DiskScanner(counters: counters, options: options).scan(root: root)
        return (node, counters)
    }

    // MARK: Synthetic (in-memory) nodes

    static func file(_ name: String, size: Int64, parent: FileNode? = nil, modified: Date? = nil) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/fake/\(name)"), name: name, isDirectory: false, isSymlink: false,
                 isPackage: false, allocatedSize: size, logicalSize: size, modified: modified, category: nil, parent: parent)
    }

    static func dir(_ name: String, path: String? = nil, category: FileCategory? = nil,
                    package: Bool = false, parent: FileNode? = nil) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path ?? "/fake/\(name)", isDirectory: true), name: name, isDirectory: true,
                 isSymlink: false, isPackage: package, allocatedSize: 0, logicalSize: 0, modified: nil,
                 category: category, parent: parent)
    }

    /// Builds `dir(name)` whose children are finalized, with correct parent links.
    static func tree(_ name: String, path: String? = nil, category: FileCategory? = nil,
                     parent: FileNode? = nil, _ build: (FileNode) -> [FileNode]) -> FileNode {
        let d = dir(name, path: path, category: category, parent: parent)
        d.finalize(children: build(d))
        return d
    }
}
