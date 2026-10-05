import XCTest
@testable import Headroom

final class DuplicateFinderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws { dir = try TestSupport.makeTempDir("dups") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func writeContent(_ rel: String, _ content: Data) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
    }

    private func find(minimum: Int64 = 0) async throws -> DuplicateScanResult {
        let (root, _) = try await TestSupport.scan(dir)
        var finder = DuplicateFinder(counters: DuplicateCounters())
        finder.options.minimumSize = minimum
        return try await finder.find(in: root)
    }

    private func blob(_ seed: UInt8, _ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: Int(seed) &+ $0 &* 7) })
    }

    func testFindsIdenticalFilesAcrossFolders() async throws {
        let a = blob(1, 200_000)
        try writeContent("x/one.bin", a)
        try writeContent("y/deep/two.bin", a)
        try writeContent("z/three.bin", a)
        try writeContent("unique.bin", blob(9, 200_000))

        let r = try await find()
        XCTAssertEqual(r.groups.count, 1)
        let g = try XCTUnwrap(r.groups.first)
        XCTAssertEqual(g.count, 3)
        XCTAssertEqual(g.size, 200_000)
        XCTAssertEqual(g.wasted, 400_000)
        XCTAssertEqual(Set(g.files.map(\.name)), ["one.bin", "two.bin", "three.bin"])
        XCTAssertEqual(r.wasted, 400_000)
    }

    func testSameSizeDifferentContentIsNotADuplicate() async throws {
        try writeContent("a.bin", blob(1, 100_000))
        try writeContent("b.bin", blob(2, 100_000))
        let r = try await find()
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testSamePrefixDifferentTailIsNotADuplicate() async throws {
        var a = blob(1, 300_000)
        var b = a
        b[b.count - 1] ^= 0xFF              // identical first 64 KB, differs in the last byte
        try writeContent("a.bin", a)
        try writeContent("b.bin", b)
        a.removeAll(); b.removeAll()
        let r = try await find()
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testMinimumSizeFiltersSmallFiles() async throws {
        let small = blob(3, 1_000)
        try writeContent("s1.bin", small)
        try writeContent("s2.bin", small)
        let filtered = try await find(minimum: 10_000)
        XCTAssertTrue(filtered.groups.isEmpty)
        let all = try await find(minimum: 0)
        XCTAssertEqual(all.groups.count, 1)
    }

    func testFilesInsidePackagesAreSkipped() async throws {
        let a = blob(4, 50_000)
        try writeContent("Tool.app/Contents/Resources/a.bin", a)
        try writeContent("Other.app/Contents/Resources/a.bin", a)
        try writeContent("loose.bin", a)
        let r = try await find()
        XCTAssertTrue(r.groups.isEmpty, "only one copy is outside a bundle")
    }

    func testGroupsAreSortedByWastedSpaceAndFilesNewestFirst() async throws {
        let big = blob(5, 400_000), small = blob(6, 50_000)
        try writeContent("small1.bin", small); try writeContent("small2.bin", small)
        try writeContent("old.bin", big)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
                                              ofItemAtPath: dir.appendingPathComponent("old.bin").path)
        try writeContent("new.bin", big)
        let r = try await find()
        XCTAssertEqual(r.groups.map(\.size), [400_000, 50_000])
        XCTAssertEqual(r.groups.first?.files.first?.name, "new.bin")
    }

    func testEmptyTree() async throws {
        let r = try await find()
        XCTAssertTrue(r.groups.isEmpty)
        XCTAssertEqual(r.filesConsidered, 0)
    }

    func testCountersAdvance() async throws {
        let a = blob(7, 150_000)
        try writeContent("a.bin", a); try writeContent("b.bin", a)
        let (root, _) = try await TestSupport.scan(dir)
        let counters = DuplicateCounters()
        _ = try await DuplicateFinder(counters: counters, options: DuplicateOptions(minimumSize: 0)).find(in: root)
        let s = counters.snapshot
        XCTAssertGreaterThanOrEqual(s.done, 2)   // last phase: 2 full hashes
        XCTAssertGreaterThan(s.bytes, 0)
    }

    func testSamplesCatchMiddleDifference() async throws {
        var a = blob(8, 2_000_000)
        var b = a
        b[b.count / 2] ^= 0xFF              // same head, same tail, differs in the middle
        try writeContent("a.bin", a); try writeContent("b.bin", b)
        a.removeAll(); b.removeAll()
        let (root, _) = try await TestSupport.scan(dir)
        let counters = DuplicateCounters()
        let r = try await DuplicateFinder(counters: counters, options: DuplicateOptions(minimumSize: 0)).find(in: root)
        XCTAssertTrue(r.groups.isEmpty)
        XCTAssertEqual(r.filesHashed, 0, "the sampling pass must eliminate the pair before any full read")
    }

    func testHashHelper() throws {
        let url = dir.appendingPathComponent("h.bin")
        try Data("hello".utf8).write(to: url)
        XCTAssertEqual(DuplicateFinder.hash(path: url.path, full: true),
                       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertNil(DuplicateFinder.hash(path: url.path + ".missing", full: true))
    }
}
