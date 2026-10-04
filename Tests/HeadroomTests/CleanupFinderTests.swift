import XCTest
@testable import Headroom

final class CleanupFinderTests: XCTestCase {
    private let mb: Int64 = 1 << 20

    func testFindsNodeModulesAsDependencies() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.tree("proj", parent: r) { p in
                [TestSupport.tree("node_modules", parent: p) { n in [TestSupport.file("big.js", size: 5 * mb, parent: n)] },
                 TestSupport.file("index.js", size: 10, parent: p)]
            }]
        }
        let found = CleanupFinder.candidates(in: root)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .dependencies)
        XCTAssertEqual(found.first?.node.name, "node_modules")
        XCTAssertEqual(found.first?.size, 5 * mb)
    }

    func testNestedCandidatesAreNotDoubleCounted() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.tree("node_modules", parent: r) { n in
                [TestSupport.tree("pkg", parent: n) { p in
                    [TestSupport.tree("node_modules", parent: p) { i in [TestSupport.file("x", size: 4 * mb, parent: i)] }]
                }]
            }]
        }
        XCTAssertEqual(CleanupFinder.candidates(in: root).count, 1)
    }

    func testSmallCandidatesAreIgnored() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.tree("node_modules", parent: r) { n in [TestSupport.file("tiny", size: 100, parent: n)] }]
        }
        XCTAssertTrue(CleanupFinder.candidates(in: root).isEmpty)
        XCTAssertEqual(CleanupFinder.candidates(in: root, minimumSize: 50).count, 1)
    }

    func testGenericBuildFolderNeedsProjectMarker() {
        func project(withMarker marker: String?) -> FileNode {
            TestSupport.tree("root") { r in
                [TestSupport.tree("proj", parent: r) { p in
                    var kids = [TestSupport.tree("build", parent: p) { b in [TestSupport.file("out", size: 3 * mb, parent: b)] }]
                    if let marker { kids.append(TestSupport.file(marker, size: 5, parent: p)) }
                    return kids
                }]
            }
        }
        XCTAssertTrue(CleanupFinder.candidates(in: project(withMarker: nil)).isEmpty)
        XCTAssertEqual(CleanupFinder.candidates(in: project(withMarker: "package.json")).first?.kind, .buildOutput)
        XCTAssertEqual(CleanupFinder.candidates(in: project(withMarker: "Makefile")).count, 1)
    }

    func testCargoTargetNeedsCargoToml() {
        func project(_ marker: String?) -> FileNode {
            TestSupport.tree("root") { r in
                var kids = [TestSupport.tree("target", parent: r) { t in [TestSupport.file("bin", size: 2 * mb, parent: t)] }]
                if let marker { kids.append(TestSupport.file(marker, size: 5, parent: r)) }
                return kids
            }
        }
        // The scanned root itself is never a candidate, so nest one level deeper.
        let without = TestSupport.tree("top") { _ in [project(nil)] }
        let with = TestSupport.tree("top") { _ in [project("Cargo.toml")] }
        XCTAssertTrue(CleanupFinder.candidates(in: without).isEmpty)
        XCTAssertEqual(CleanupFinder.candidates(in: with).count, 1)
    }

    func testScannedRootItselfIsNeverACandidate() {
        let root = TestSupport.tree("node_modules") { r in [TestSupport.file("big", size: 9 * mb, parent: r)] }
        XCTAssertTrue(CleanupFinder.candidates(in: root).isEmpty)
    }

    func testCandidatesSortedLargestFirst() {
        let root = TestSupport.tree("root") { r in
            [TestSupport.tree("a", parent: r) { a in [TestSupport.tree("node_modules", parent: a) { n in [TestSupport.file("f", size: 2 * mb, parent: n)] }] },
             TestSupport.tree("b", parent: r) { b in [TestSupport.tree("node_modules", parent: b) { n in [TestSupport.file("f", size: 9 * mb, parent: n)] }] }]
        }
        XCTAssertEqual(CleanupFinder.candidates(in: root).map(\.size), [9 * mb, 2 * mb])
    }

    func testContentsOnlyCandidateDeletesChildren() {
        let node = TestSupport.tree("Caches") { c in [TestSupport.file("a", size: 1, parent: c), TestSupport.file("b", size: 2, parent: c)] }
        var candidate = CleanupCandidate(kind: .caches, node: node)
        XCTAssertEqual(candidate.deletableNodes.count, 1)
        candidate.contentsOnly = true
        XCTAssertEqual(candidate.deletableNodes.count, 2)
    }

    func testKindsHaveDisplayText() {
        for k in CleanupCandidate.Kind.allCases {
            XCTAssertFalse(k.title.isEmpty); XCTAssertFalse(k.symbol.isEmpty); XCTAssertFalse(k.note.isEmpty)
        }
    }

    func testKnownLocationsExistOnDisk() {
        for loc in CleanupFinder.knownLocations {
            XCTAssertTrue(FileManager.default.fileExists(atPath: loc.path), loc.path)
        }
    }
}
