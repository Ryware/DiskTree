import XCTest
@testable import Headroom

@MainActor
final class AppStateTests: XCTestCase {
    private var dir: URL!
    private var savedRecents: [String]?
    private let recentsKey = "recentScans"

    override func setUpWithError() throws {
        dir = try TestSupport.makeTempDir("appstate")
        savedRecents = UserDefaults.standard.stringArray(forKey: recentsKey)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        if let savedRecents { UserDefaults.standard.set(savedRecents, forKey: recentsKey) }
        else { UserDefaults.standard.removeObject(forKey: recentsKey) }
    }

    private func scanAndWait(_ state: AppState, timeout: TimeInterval = 15) async throws {
        state.scan(dir)
        let deadline = Date().addingTimeInterval(timeout)
        while state.phase != .done {
            if Date() > deadline { XCTFail("scan did not finish; phase = \(state.phase)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testScanPublishesTreeAndDerivedData() async throws {
        try TestSupport.write(dir.appendingPathComponent("photo.jpg"), bytes: 200_000)
        try TestSupport.write(dir.appendingPathComponent("proj/node_modules/lib.js"), bytes: 3 << 20)
        let state = AppState()
        XCTAssertEqual(state.phase, .idle)

        try await scanAndWait(state)

        let root = try XCTUnwrap(state.root)
        XCTAssertEqual(state.rootURL, dir)
        XCTAssertEqual(root.fileCount, 2)
        XCTAssertNotNil(state.progress.finished)
        XCTAssertEqual(state.progress.files, 2)
        XCTAssertEqual(state.treeVersion, 1)
        XCTAssertEqual(state.selectedNode === root, true)
        XCTAssertEqual(state.categoryTotals[.packages] ?? 0, root.categoryTotals()[.packages] ?? -1)
        XCTAssertGreaterThan(state.categoryTotals[.packages] ?? 0, 0)
        XCTAssertEqual(state.largest.first?.name, "lib.js")
        XCTAssertEqual(state.cleanupCandidates.first?.kind, .dependencies)
        XCTAssertEqual(state.recentScans.first?.path, dir.path)
    }

    func testNodeLookupAndSelectionFollowTheIndex() async throws {
        try TestSupport.write(dir.appendingPathComponent("a.bin"), bytes: 10_000)
        try TestSupport.write(dir.appendingPathComponent("b.bin"), bytes: 20_000)
        let state = AppState()
        try await scanAndWait(state)

        let root = try XCTUnwrap(state.root)
        let b = try XCTUnwrap(root.children.first { $0.name == "b.bin" })
        XCTAssertTrue(state.node(for: b.id) === b)
        state.selection = [b.id]
        XCTAssertTrue(state.selectedNode === b)
        XCTAssertEqual(state.selectedNodes.map(\.name), ["b.bin"])
    }

    func testRescanResetsAndRebuilds() async throws {
        try TestSupport.write(dir.appendingPathComponent("a.bin"), bytes: 1_000)
        let state = AppState()
        try await scanAndWait(state)
        try TestSupport.write(dir.appendingPathComponent("b.bin"), bytes: 1_000)

        state.rescan()
        XCTAssertEqual(state.phase, .scanning)
        XCTAssertNil(state.root)
        let deadline = Date().addingTimeInterval(15)
        while state.phase != .done && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(state.root?.fileCount, 2)
        XCTAssertEqual(state.treeVersion, 2)
    }

    func testPermanentDeleteUpdatesTreeSelectionAndTotals() async throws {
        try TestSupport.write(dir.appendingPathComponent("keep.bin"), bytes: 10_000)
        try TestSupport.write(dir.appendingPathComponent("junk/a.bin"), bytes: 50_000)
        try TestSupport.write(dir.appendingPathComponent("junk/b.bin"), bytes: 50_000)
        let state = AppState()
        try await scanAndWait(state)

        let root = try XCTUnwrap(state.root)
        let junk = try XCTUnwrap(root.children.first { $0.name == "junk" })
        state.selection = [junk.id]
        let sizeBefore = root.allocatedSize

        let deleted = await state.delete([junk], mode: .permanent, silent: true)
        let result = try XCTUnwrap(deleted)

        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(root.children.map(\.name), ["keep.bin"])
        XCTAssertLessThan(root.allocatedSize, sizeBefore)
        XCTAssertEqual(state.progress.files, 1)
        XCTAssertTrue(state.selection.isEmpty)
        XCTAssertNil(state.deleting)
        XCTAssertNil(state.lastDeleteResult, "silent deletes must not raise the summary alert")
    }

    func testDeleteWithNothingSelectedIsANoOp() async {
        let state = AppState()
        let result = await state.delete([])
        XCTAssertNil(result)
        XCTAssertNil(state.deleting)
    }

    func testNonSilentDeletePublishesSummary() async throws {
        try TestSupport.write(dir.appendingPathComponent("x/a.bin"), bytes: 1_000)
        let state = AppState()
        try await scanAndWait(state)
        let x = try XCTUnwrap(state.root?.children.first)
        _ = await state.delete([x], mode: .permanent)
        XCTAssertNotNil(state.lastDeleteResult)
    }

    func testProgressHelpers() {
        XCTAssertEqual(DeleteProgress().fraction, 0)
        XCTAssertEqual(DeleteProgress(done: 1, total: 4, bytes: 0).fraction, 0.25, accuracy: 0.0001)
        var p = ScanProgress()
        p.finished = p.started.addingTimeInterval(2)
        XCTAssertEqual(p.elapsed, 2, accuracy: 0.001)
    }
}
