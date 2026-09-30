import XCTest
@testable import DiskTree

final class FileNodeTests: XCTestCase {
    func testFinalizeAggregatesSizesAndCounts() {
        let root = TestSupport.dir("root")
        let sub = TestSupport.dir("sub", parent: root)
        sub.finalize(children: [TestSupport.file("a", size: 100, parent: sub), TestSupport.file("b", size: 300, parent: sub)])
        root.finalize(children: [sub, TestSupport.file("c", size: 50, parent: root)])

        XCTAssertEqual(root.allocatedSize, 450)
        XCTAssertEqual(root.logicalSize, 450)
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.directoryCount, 1)
        XCTAssertEqual(sub.fileCount, 2)
    }

    func testFinalizeSortsChildrenLargestFirst() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.file("small", size: 1, parent: r), TestSupport.file("big", size: 999, parent: r),
             TestSupport.file("mid", size: 50, parent: r)]
        }
        XCTAssertEqual(root.children.map(\.name), ["big", "mid", "small"])
    }

    func testEnsureSortedIsLazyPerFolderAndRunsOncePerGeneration() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.file("b", size: 10, parent: r), TestSupport.file("c", size: 30, parent: r), TestSupport.file("a", size: 20, parent: r)]
        }
        let byName = [KeyPathComparator(\FileNode.name, comparator: .localizedStandard, order: .forward)]
        root.ensureSorted(generation: 1, using: byName)
        XCTAssertEqual(root.children.map(\.name), ["a", "b", "c"])

        // Same generation again: must not re-sort, even with different comparators.
        let bySizeAsc = [KeyPathComparator(\FileNode.allocatedSize, order: .forward)]
        root.ensureSorted(generation: 1, using: bySizeAsc)
        XCTAssertEqual(root.children.map(\.name), ["a", "b", "c"])

        // A new generation re-sorts.
        root.ensureSorted(generation: 2, using: bySizeAsc)
        XCTAssertEqual(root.children.map(\.name), ["b", "a", "c"])
    }

    func testEnsureSortedDoesNotTouchDescendants() {
        let inner = TestSupport.dir("inner")
        inner.finalize(children: [TestSupport.file("z", size: 5, parent: inner), TestSupport.file("y", size: 9, parent: inner)])
        let root = TestSupport.dir("root")
        root.finalize(children: [inner])
        let byName = [KeyPathComparator(\FileNode.name, order: .forward)]
        root.ensureSorted(generation: 1, using: byName)
        // Sorting the parent must not touch the child folder: it keeps largest-first (y=9 before z=5).
        XCTAssertEqual(inner.children.map(\.name), ["y", "z"])
    }

    func testRemoveChildPropagatesUpTheTree() {
        let root = TestSupport.dir("root")
        let sub = TestSupport.dir("sub", parent: root)
        let a = TestSupport.file("a", size: 100, parent: sub)
        let b = TestSupport.file("b", size: 300, parent: sub)
        sub.finalize(children: [a, b])
        root.finalize(children: [sub])

        sub.removeChild(b)
        XCTAssertEqual(sub.allocatedSize, 100)
        XCTAssertEqual(root.allocatedSize, 100)
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertEqual(sub.children.count, 1)
    }

    func testRemoveChildIgnoresUnknownNode() {
        let root = TestSupport.tree("root") { r in [TestSupport.file("a", size: 10, parent: r)] }
        root.removeChild(TestSupport.file("stranger", size: 999))
        XCTAssertEqual(root.allocatedSize, 10)
        XCTAssertEqual(root.children.count, 1)
    }

    func testShareOfParent() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.file("a", size: 25, parent: r), TestSupport.file("b", size: 75, parent: r)]
        }
        XCTAssertEqual(root.children[0].shareOfParent, 0.75, accuracy: 0.0001)
        XCTAssertEqual(root.children[1].shareOfParent, 0.25, accuracy: 0.0001)
        XCTAssertEqual(root.shareOfParent, 1)
    }

    func testCategoryTotalsUsesForcedDirectoryCategory() {
        let root = TestSupport.tree("root") { r in
            let nm = TestSupport.tree("node_modules", category: .packages, parent: r) { n in
                [TestSupport.file("lib.js", size: 400, parent: n)]   // would be code, but forced to packages
            }
            return [nm, TestSupport.file("photo.jpg", size: 200, parent: r), TestSupport.file("notes.txt", size: 10, parent: r)]
        }
        let totals = root.categoryTotals()
        XCTAssertEqual(totals[.packages], 400)
        XCTAssertEqual(totals[.images], 200)
        XCTAssertEqual(totals[.documents], 10)
        XCTAssertNil(totals[.code])
    }

    func testLargestItemsReturnsBiggestLeavesInOrder() {
        let root = TestSupport.tree("root") { r in
            (1...20).map { TestSupport.file("f\($0)", size: Int64($0) * 10, parent: r) }
        }
        let top = root.largestItems(limit: 3)
        XCTAssertEqual(top.map(\.name), ["f20", "f19", "f18"])
    }

    func testLargestItemsTreatsPackagesAsLeaves() {
        let root = TestSupport.dir("root")
        let pkg = FileNode(url: URL(fileURLWithPath: "/fake/Big.app", isDirectory: true), name: "Big.app", isDirectory: true,
                           isSymlink: false, isPackage: true, allocatedSize: 5000, logicalSize: 5000, modified: nil, category: .apps, parent: root)
        root.finalize(children: [pkg, TestSupport.file("x", size: 1, parent: root)])
        XCTAssertEqual(root.largestItems(limit: 1).first?.name, "Big.app")
    }

    func testEffectiveCategoryInheritsFromAncestor() {
        let root = TestSupport.dir("root")
        var leaf: FileNode!
        let nm = TestSupport.tree("node_modules", category: .packages, parent: root) { n in
            leaf = TestSupport.file("index.js", size: 1, parent: n)
            return [leaf]
        }
        root.finalize(children: [nm])
        XCTAssertEqual(leaf.effectiveCategory, .packages)
        XCTAssertEqual(TestSupport.file("movie.mp4", size: 1).effectiveCategory, .video)
    }

    func testWalkVisitsEveryNode() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.tree("a", parent: r) { a in [TestSupport.file("1", size: 1, parent: a)] }, TestSupport.file("2", size: 1, parent: r)]
        }
        var names: [String] = []
        root.walk { names.append($0.name) }
        XCTAssertEqual(Set(names), ["root", "a", "1", "2"])
    }
}
