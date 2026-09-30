import Foundation

/// One entry in the scanned tree. Reference type so a multi-million node tree
/// isn't copied around; treated as immutable once the scan finishes.
final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let isPackage: Bool          // .app / .framework etc. – shown as a leaf
    let modified: Date?
    weak var parent: FileNode?

    /// Bytes actually allocated on disk (what df sees). Falls back to logical size.
    private(set) var allocatedSize: Int64
    /// Logical byte count.
    private(set) var logicalSize: Int64
    private(set) var fileCount: Int
    private(set) var directoryCount: Int
    /// Category for files; for directories, a category forced on every descendant
    /// (e.g. everything under node_modules is "Dependencies").
    let category: FileCategory?
    private(set) var children: [FileNode] = []

    init(url: URL, name: String, isDirectory: Bool, isSymlink: Bool, isPackage: Bool,
         allocatedSize: Int64, logicalSize: Int64, modified: Date?, category: FileCategory?, parent: FileNode?) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.modified = modified
        self.category = category
        self.parent = parent
        self.fileCount = isDirectory ? 0 : 1
        self.directoryCount = 0
    }

    var path: String { url.path }
    var displaySize: Int64 { allocatedSize }
    var effectiveCategory: FileCategory {
        if let category { return category }
        var p = parent
        while let node = p {
            if let c = node.category { return c }
            p = node.parent
        }
        return isDirectory ? .other : FileCategory.forFile(named: name)
    }

    /// Called once by the scanner after all children are known.
    func finalize(children: [FileNode]) {
        var alloc: Int64 = 0, logical: Int64 = 0, files = 0, dirs = 0
        for c in children {
            alloc += c.allocatedSize
            logical += c.logicalSize
            files += c.fileCount
            dirs += c.directoryCount + (c.isDirectory ? 1 : 0)
        }
        self.children = children.sorted { $0.allocatedSize > $1.allocatedSize }
        self.allocatedSize += alloc
        self.logicalSize += logical
        self.fileCount += files
        self.directoryCount += dirs
    }

    /// Sort generation this node's children were last ordered for (see `ensureSorted`).
    private var sortedGeneration = 0

    /// Lazily re-sort just this folder's children (table header clicks). Sorting the whole
    /// tree eagerly froze the UI on multi-million-node scans; folders are now sorted only
    /// when the outline view first asks for them after a header click.
    func ensureSorted(generation: Int, using comparators: [KeyPathComparator<FileNode>]) {
        guard sortedGeneration != generation else { return }
        sortedGeneration = generation
        if children.count > 1 { children.sort(using: comparators) }
    }

    /// Detach a deleted child and propagate the size change up the tree.
    func removeChild(_ child: FileNode) {
        guard let idx = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: idx)
        var node: FileNode? = self
        while let n = node {
            n.allocatedSize -= child.allocatedSize
            n.logicalSize -= child.logicalSize
            n.fileCount -= child.fileCount
            n.directoryCount -= child.directoryCount + (child.isDirectory ? 1 : 0)
            node = n.parent
        }
    }

    /// Ratio of this node's size to its parent's (for the inline size bar).
    var shareOfParent: Double {
        guard let parent, parent.allocatedSize > 0 else { return 1 }
        return Double(allocatedSize) / Double(parent.allocatedSize)
    }

    // MARK: Traversal helpers

    func walk(_ body: (FileNode) -> Void) {
        body(self)
        for c in children { c.walk(body) }
    }

    /// Category totals across the subtree.
    func categoryTotals() -> [FileCategory: Int64] {
        var totals: [FileCategory: Int64] = [:]
        func visit(_ n: FileNode, inherited: FileCategory?) {
            let forced = n.category ?? inherited
            if n.isDirectory && !n.isPackage {
                if n.children.isEmpty {
                    return
                }
                for c in n.children { visit(c, inherited: forced) }
            } else {
                let cat = forced ?? FileCategory.forFile(named: n.name)
                totals[cat, default: 0] += n.allocatedSize
            }
        }
        visit(self, inherited: nil)
        return totals
    }

    /// Largest leaves (files and packages) in the subtree.
    func largestItems(limit: Int) -> [FileNode] {
        var heap: [FileNode] = []
        heap.reserveCapacity(limit * 2)
        walk { n in
            guard !n.isDirectory || n.isPackage else { return }
            heap.append(n)
            if heap.count > limit * 4 {
                heap.sort { $0.allocatedSize > $1.allocatedSize }
                heap.removeLast(heap.count - limit)
            }
        }
        heap.sort { $0.allocatedSize > $1.allocatedSize }
        return Array(heap.prefix(limit))
    }

    // MARK: Hashable

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
