import XCTest
@testable import DiskTree

final class FileCategoryTests: XCTestCase {
    func testKnownExtensions() {
        let expected: [(String, FileCategory)] = [
            ("photo.jpg", .images), ("clip.mov", .video), ("song.mp3", .audio), ("paper.pdf", .documents),
            ("backup.zip", .archives), ("main.swift", .code), ("Tool.app", .apps), ("app.log", .logs),
            ("installer.dmg", .diskImages), ("vm.utm", .virtualMachines), ("data.sqlite", .databases),
            ("llama.gguf", .aiModels),
        ]
        for (name, category) in expected {
            XCTAssertEqual(FileCategory.forFile(named: name), category, name)
        }
    }

    func testExtensionMatchingIsCaseInsensitive() {
        XCTAssertEqual(FileCategory.forFile(named: "IMG_0001.JPG"), .images)
        XCTAssertEqual(FileCategory.forFile(named: "Movie.MP4"), .video)
    }

    func testUnknownOrMissingExtensionIsOther() {
        XCTAssertEqual(FileCategory.forFile(named: "Makefile"), .other)
        XCTAssertEqual(FileCategory.forFile(named: "weird.zzzzz"), .other)
    }

    func testDirectoryNameRules() {
        XCTAssertEqual(FileCategory.forDirectory(named: "node_modules"), .packages)
        XCTAssertEqual(FileCategory.forDirectory(named: "DerivedData"), .caches)
        XCTAssertEqual(FileCategory.forDirectory(named: "Logs"), .logs)
        XCTAssertEqual(FileCategory.forDirectory(named: ".ollama"), .aiModels)
        XCTAssertNil(FileCategory.forDirectory(named: "Documents"))
    }

    func testEveryCategoryHasUniqueTitleAndSymbol() {
        let titles = FileCategory.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(FileCategory.allCases.allSatisfy { !$0.symbol.isEmpty && !$0.title.isEmpty })
    }

    func testRawValueRoundTripsThroughCodable() throws {
        for c in FileCategory.allCases {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(FileCategory.self, from: data), c)
        }
    }
}
