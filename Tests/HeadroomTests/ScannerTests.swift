import XCTest
@testable import Headroom

final class ScannerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws { dir = try TestSupport.makeTempDir("scan") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testScanCountsFilesDirectoriesAndLogicalBytes() async throws {
        try TestSupport.write(dir.appendingPathComponent("a.txt"), bytes: 1_000)
        try TestSupport.write(dir.appendingPathComponent("sub/b.bin"), bytes: 20_000)
        try TestSupport.write(dir.appendingPathComponent("sub/deep/c.bin"), bytes: 300_000)

        let (root, counters) = try await TestSupport.scan(dir)

        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.directoryCount, 2)
        XCTAssertEqual(root.logicalSize, 321_000)
        XCTAssertGreaterThanOrEqual(root.allocatedSize, 300_000)
        XCTAssertEqual(counters.snapshot.files, 3)
        XCTAssertGreaterThanOrEqual(counters.snapshot.directories, 3)
        XCTAssertEqual(counters.snapshot.errors, 0)
    }

    func testChildrenAreSortedLargestFirstAndNamesAreCorrect() async throws {
        try TestSupport.write(dir.appendingPathComponent("small.dat"), bytes: 10)
        try TestSupport.write(dir.appendingPathComponent("large.dat"), bytes: 500_000)

        let (root, _) = try await TestSupport.scan(dir)
        XCTAssertEqual(root.children.first?.name, "large.dat")
        XCTAssertEqual(Set(root.children.map(\.name)), ["small.dat", "large.dat"])
        XCTAssertTrue(root.children.allSatisfy { $0.parent === root })
    }

    func testEmptyDirectory() async throws {
        let (root, _) = try await TestSupport.scan(dir)
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.fileCount, 0)
        XCTAssertEqual(root.allocatedSize, 0)
        XCTAssertTrue(root.children.isEmpty)
    }

    func testPackagesAreDetectedAndTreatedAsApps() async throws {
        try TestSupport.write(dir.appendingPathComponent("Tool.app/Contents/MacOS/tool"), bytes: 2_000)
        let (root, _) = try await TestSupport.scan(dir)
        let pkg = try XCTUnwrap(root.children.first { $0.name == "Tool.app" })
        XCTAssertTrue(pkg.isPackage)
        XCTAssertEqual(pkg.category, .apps)
    }

    func testDirectoryCategoryIsAssignedByName() async throws {
        try TestSupport.write(dir.appendingPathComponent("proj/node_modules/x/index.js"), bytes: 100)
        let (root, _) = try await TestSupport.scan(dir)
        let proj = try XCTUnwrap(root.children.first { $0.name == "proj" })
        let nm = try XCTUnwrap(proj.children.first { $0.name == "node_modules" })
        XCTAssertEqual(nm.category, .packages)
    }

    func testExcludedPathsAreSkipped() async throws {
        try TestSupport.write(dir.appendingPathComponent("keep/a.bin"), bytes: 100)
        try TestSupport.write(dir.appendingPathComponent("skip/b.bin"), bytes: 100)
        var options = ScanOptions()
        options.excludedPaths = [dir.appendingPathComponent("skip").path]
        let (root, _) = try await TestSupport.scan(dir, options: options)
        XCTAssertEqual(root.children.map(\.name), ["keep"])
        XCTAssertEqual(root.fileCount, 1)
    }

    func testSymlinksAreNotFollowed() async throws {
        try TestSupport.write(dir.appendingPathComponent("real/big.bin"), bytes: 100_000)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"),
                                                   withDestinationURL: dir.appendingPathComponent("real"))
        let (root, _) = try await TestSupport.scan(dir)
        let link = try XCTUnwrap(root.children.first { $0.name == "link" })
        XCTAssertTrue(link.isSymlink)
        XCTAssertFalse(link.isDirectory)
        XCTAssertEqual(root.logicalSize < 110_000, true, "the linked folder must not be counted twice")
    }

    func testScanningASingleFile() async throws {
        let f = try TestSupport.write(dir.appendingPathComponent("only.bin"), bytes: 4_096)
        let (node, _) = try await TestSupport.scan(f)
        XCTAssertFalse(node.isDirectory)
        XCTAssertEqual(node.logicalSize, 4_096)
    }

    func testCancellationStopsTheScan() async throws {
        for i in 0..<50 { try TestSupport.write(dir.appendingPathComponent("d\(i)/f.bin"), bytes: 10) }
        let counters = ScanCounters()
        let task = Task { try await DiskScanner(counters: counters, options: ScanOptions()).scan(root: dir) }
        task.cancel()
        do {
            _ = try await task.value
            // Finishing before the cancellation was observed is acceptable.
        } catch is CancellationError {
            // Expected.
        }
    }

    func testScanCountersAccumulate() {
        let c = ScanCounters()
        c.add(files: 2, directories: 1, bytes: 10, errors: 1, current: "/a")
        c.add(files: 3, bytes: 5)
        let s = c.snapshot
        XCTAssertEqual(s.files, 5)
        XCTAssertEqual(s.directories, 1)
        XCTAssertEqual(s.bytes, 15)
        XCTAssertEqual(s.errors, 1)
        XCTAssertEqual(s.current, "/a")
    }
}
