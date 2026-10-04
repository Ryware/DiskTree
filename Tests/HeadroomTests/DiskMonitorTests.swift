import XCTest
@testable import Headroom

final class DiskMonitorTests: XCTestCase {
    func testVolumeSnapshotReadsStartupDisk() throws {
        let s = try XCTUnwrap(VolumeSnapshot.read(path: "/"))
        XCTAssertGreaterThan(s.total, 0)
        XCTAssertGreaterThanOrEqual(s.free, 0)
        XCTAssertLessThanOrEqual(s.free, s.total)
        XCTAssertEqual(s.used, s.total - s.free)
        XCTAssertTrue((0...1).contains(s.freeFraction))
        XCTAssertFalse(s.name.isEmpty)
    }

    func testVolumeSnapshotMath() {
        let s = VolumeSnapshot(name: "Test", total: 1_000, free: 250)
        XCTAssertEqual(s.used, 750)
        XCTAssertEqual(s.freeFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(VolumeSnapshot(name: "Empty", total: 0, free: 0).freeFraction, 0)
    }

    func testUnknownPathReturnsNil() {
        XCTAssertNil(VolumeSnapshot.read(path: "/definitely/not/a/real/path/\(UUID().uuidString)"))
    }

    func testFreeSpaceSampleCodableRoundTrip() throws {
        let sample = FreeSpaceSample(t: Date(timeIntervalSince1970: 1_700_000_000), free: 42_000_000_000)
        let data = try JSONEncoder().encode([sample])
        let back = try JSONDecoder().decode([FreeSpaceSample].self, from: data)
        XCTAssertEqual(back, [sample])
        XCTAssertEqual(sample.id, sample.t)
    }

    func testPrefFallbacks() {
        let key = "headroom.tests.\(UUID().uuidString)"
        XCTAssertTrue(Pref.bool(key, true))
        XCTAssertFalse(Pref.bool(key, false))
        XCTAssertEqual(Pref.double(key, 7.5), 7.5)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(Pref.bool(key, true))
        UserDefaults.standard.set(3.0, forKey: key + ".d")
        XCTAssertEqual(Pref.double(key + ".d", 9), 3.0)
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key + ".d")
    }

    @MainActor
    func testRefreshPublishesASnapshotAndAStatus() throws {
        let monitor = DiskMonitor.shared
        monitor.refresh()
        let snap = try XCTUnwrap(monitor.snapshot)
        XCTAssertGreaterThan(snap.total, 0)
        XCTAssertGreaterThanOrEqual(monitor.lowGB, 1)
        XCTAssertTrue([DiskStatus.ok, .warning, .critical].contains(monitor.status))
    }

    @MainActor
    func testRingIconIsSmallAndTemplateOnlyWhenHealthy() {
        let ok = RingIcon.image(free: 0.5, status: .ok)
        XCTAssertEqual(ok.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(ok.isTemplate)
        XCTAssertFalse(RingIcon.image(free: 0.05, status: .critical).isTemplate)
        XCTAssertFalse(RingIcon.image(free: 0.2, status: .warning).isTemplate)
    }

    @MainActor
    func testCompactLabel() {
        XCTAssertEqual(MenuBarLabel.compact(42_000_000_000), "42 GB")
        XCTAssertEqual(MenuBarLabel.compact(1_234_000_000_000), "1234 GB")
    }
}
