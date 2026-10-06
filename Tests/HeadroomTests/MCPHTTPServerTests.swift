import XCTest
@testable import Headroom

final class MCPHTTPServerTests: XCTestCase {
    func testOnlyLoopbackHostsAndOriginsAreAllowed() {
        XCTAssertTrue(MCPHTTPServer.isAllowed(host: "127.0.0.1:47120", origin: nil))
        XCTAssertTrue(MCPHTTPServer.isAllowed(host: "localhost:47120", origin: nil))
        XCTAssertTrue(MCPHTTPServer.isAllowed(host: "[::1]:47120", origin: nil))
        XCTAssertTrue(MCPHTTPServer.isAllowed(host: nil, origin: nil))
        XCTAssertTrue(MCPHTTPServer.isAllowed(host: "127.0.0.1:47120", origin: "http://localhost:3000"))
        // DNS rebinding: a page on evil.com resolving to 127.0.0.1 still sends its own Host and Origin.
        XCTAssertFalse(MCPHTTPServer.isAllowed(host: "evil.com:47120", origin: nil))
        XCTAssertFalse(MCPHTTPServer.isAllowed(host: "127.0.0.1:47120", origin: "https://evil.com"))
        XCTAssertFalse(MCPHTTPServer.isAllowed(host: "127.0.0.1:47120", origin: "null"))
    }

    func testParsesRequestOnceComplete() throws {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let raw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:47120\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        XCTAssertNil(HTTPRequest.parse(data.prefix(data.count - 5)), "body not complete yet")
        let request = try XCTUnwrap(HTTPRequest.parse(data))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["host"], "127.0.0.1:47120")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), body)
    }

    func testRawMessagesRoundTrip() async throws {
        let response = await MCPServer.handle(Data(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(response)) as? [String: Any])
        XCTAssertEqual(object["id"] as? Int, 7)
        let notification = await MCPServer.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        XCTAssertNil(notification)
        let garbage = await MCPServer.handle(Data("nope".utf8))
        let error = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(garbage)) as? [String: Any])
        XCTAssertEqual((error["error"] as? [String: Any])?["code"] as? Int, -32700)
    }
}

final class HeadroomCLITests: XCTestCase {
    private func args(_ command: String, _ argv: [String]) throws -> [String: Any] {
        try HeadroomCLI.arguments(for: XCTUnwrap(HeadroomCLI.tool(named: command)), argv)
    }

    func testEveryCommandMapsToATool() {
        for (command, tool) in HeadroomCLI.commands {
            XCTAssertEqual(HeadroomCLI.tool(named: command)?["name"] as? String, tool)
            XCTAssertTrue(HeadroomCLI.usage.contains("  \(command) "), command)
        }
        XCTAssertEqual(HeadroomCLI.commands.count, MCPServer.tools.count)
    }

    func testOptionsAreTypedFromTheSchema() throws {
        let a = try args("duplicates", ["~/Downloads", "--limit", "5", "--min-size-mb=2.5", "--refresh"])
        XCTAssertEqual(a["path"] as? String, "~/Downloads")
        XCTAssertEqual(a["limit"] as? Int, 5)
        XCTAssertEqual(a["min_size_mb"] as? Double, 2.5)
        XCTAssertEqual(a["refresh"] as? Bool, true)
        XCTAssertEqual(try args("largest_files", ["/", "--category", "video"])["category"] as? String, "video")
    }

    func testTrashTakesSeveralPaths() throws {
        XCTAssertEqual(try args("trash", ["/a", "/b", "--yes"])["paths"] as? [String], ["/a", "/b"])
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try args("scan", ["/a", "/b"]))
        XCTAssertThrowsError(try args("scan", ["/a", "--nope"]))
        XCTAssertThrowsError(try args("scan", ["/a", "--limit", "many"]))
        XCTAssertThrowsError(try args("largest", ["/a", "--category", "nope"]))
        XCTAssertThrowsError(try args("state", ["/a"]))
    }

    func testOnlyCommandsLeaveTheAppMode() {
        XCTAssertTrue(HeadroomCLI.handles(["status"]))
        XCTAssertTrue(HeadroomCLI.handles(["--help"]))
        XCTAssertTrue(HeadroomCLI.handles(["scna"]), "a typo must not open the window")
        XCTAssertFalse(HeadroomCLI.handles([]))
        XCTAssertFalse(HeadroomCLI.handles(["-NSDocumentRevisionsDebugMode", "YES"]))
    }
}
