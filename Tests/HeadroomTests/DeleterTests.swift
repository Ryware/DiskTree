import XCTest
@testable import Headroom

final class DeleterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws { dir = try TestSupport.makeTempDir("delete") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func permanentDelete(_ nodes: [FileNode]) async -> DeleteResult {
        await Deleter(mode: .permanent, counters: DeleteCounters()).delete(nodes)
    }

    func testPermanentDeleteRemovesWholeTree() async throws {
        let victim = dir.appendingPathComponent("victim")
        try TestSupport.write(victim.appendingPathComponent("a.bin"), bytes: 1_000)
        try TestSupport.write(victim.appendingPathComponent("x/b.bin"), bytes: 2_000)
        try TestSupport.write(victim.appendingPathComponent("x/y/z/c.bin"), bytes: 3_000)
        let keeper = try TestSupport.write(dir.appendingPathComponent("keep.txt"), bytes: 10)

        let (root, _) = try await TestSupport.scan(dir)
        let node = try XCTUnwrap(root.children.first { $0.name == "victim" })
        let result = await permanentDelete([node])

        XCTAssertFalse(FileManager.default.fileExists(atPath: victim.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.path))
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertEqual(result.removedFiles, 3)
        XCTAssertEqual(result.removedDirectories, 4)   // victim, x, y, z
        XCTAssertGreaterThan(result.freedBytes, 0)
    }

    func testPermanentDeleteOfSingleFile() async throws {
        let f = try TestSupport.write(dir.appendingPathComponent("lonely.bin"), bytes: 5_000)
        let (root, _) = try await TestSupport.scan(dir)
        let node = try XCTUnwrap(root.children.first)
        let result = await permanentDelete([node])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
        XCTAssertEqual(result.removedFiles, 1)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testPermanentDeleteLeavesNoHiddenStashBehind() async throws {
        try TestSupport.write(dir.appendingPathComponent("gone/a.bin"), bytes: 100)
        let (root, _) = try await TestSupport.scan(dir)
        _ = await permanentDelete([try XCTUnwrap(root.children.first)])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(leftovers.isEmpty, "unexpected leftovers: \(leftovers)")
    }

    func testPermanentDeleteOfSeveralRootsAtOnce() async throws {
        for name in ["one", "two", "three"] {
            try TestSupport.write(dir.appendingPathComponent("\(name)/f.bin"), bytes: 100)
        }
        let (root, _) = try await TestSupport.scan(dir)
        let result = await permanentDelete(root.children)
        XCTAssertEqual(result.removedFiles, 3)
        XCTAssertEqual(result.removedDirectories, 3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
    }

    func testMissingTargetReportsErrorInsteadOfCrashing() async throws {
        try TestSupport.write(dir.appendingPathComponent("temp/a.bin"), bytes: 100)
        let (root, _) = try await TestSupport.scan(dir)
        let node = try XCTUnwrap(root.children.first)
        try FileManager.default.removeItem(at: node.url)     // vanish behind the scanner's back
        let result = await permanentDelete([node])
        XCTAssertEqual(result.removedFiles, 0)
    }

    func testCountersReachTheTotal() async throws {
        try TestSupport.write(dir.appendingPathComponent("t/a.bin"), bytes: 100)
        try TestSupport.write(dir.appendingPathComponent("t/b.bin"), bytes: 100)
        let (root, _) = try await TestSupport.scan(dir)
        let counters = DeleteCounters()
        _ = await Deleter(mode: .permanent, counters: counters).delete(root.children)
        let s = counters.snapshot
        XCTAssertEqual(s.done, s.total)
        XCTAssertGreaterThan(s.total, 0)
    }

    func testDeleteModeLabels() {
        XCTAssertEqual(DeleteMode.allCases.count, 2)
        XCTAssertTrue(DeleteMode.trash.actionLabel.contains("Trash"))
        XCTAssertTrue(DeleteMode.permanent.actionLabel.contains("Permanently"))
        XCTAssertNotEqual(DeleteMode.trash.symbol, DeleteMode.permanent.symbol)
        XCTAssertNotEqual(DeleteMode.trash.shortNote, DeleteMode.permanent.shortNote)
        XCTAssertEqual(DeleteMode(rawValue: "trash"), .trash)
    }
}
