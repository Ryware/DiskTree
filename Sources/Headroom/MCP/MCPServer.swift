import Foundation
import AppKit
import Darwin

/// Model Context Protocol server over stdio, so AI agents (Claude Code, Cursor, …) can use
/// Headroom's scanner, cleanup finder and safety rules. Started with `Headroom --mcp`.
///
/// Transport is newline-delimited JSON-RPC 2.0 on stdin/stdout; nothing else may write to stdout.
/// Everything is read-only except `move_to_trash`, which only ever uses the recoverable Trash
/// and refuses items the safety rules mark "Do not delete".
enum MCPServer {
    static let protocolVersion = "2025-06-18"

    /// Reads requests until stdin closes, then exits. Never returns.
    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        Task.detached {
            do {
                for try await line in FileHandle.standardInput.bytes.lines {
                    guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                    guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        write(error(id: NSNull(), code: -32700, message: "Parse error"))
                        continue
                    }
                    if let response = await handle(message) { write(response) }
                }
            } catch {}
            exit(0)
        }
        // Keep the main queue running: moving to the Trash goes through NSWorkspace on main.
        dispatchMain()
    }

    private static func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }

    // MARK: JSON-RPC

    /// Handles one JSON-RPC message. Returns nil for notifications.
    static func handle(_ message: [String: Any]) async -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        guard let id = message["id"] else { return nil }   // notification (e.g. notifications/initialized)
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return result(id: id, [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "headroom", "version": appVersion],
                "instructions": "Headroom analyzes disk usage on this Mac. Start with disk_status, then scan_folder or find_cleanup. Check explain_path before suggesting deletions; move_to_trash is recoverable and refuses items marked 'never'.",
            ])
        case "ping":
            return result(id: id, [:])
        case "tools/list":
            return result(id: id, ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let payload = try await call(name, args)
                return result(id: id, [
                    "content": [["type": "text", "text": json(payload)]],
                    "isError": false,
                ])
            } catch let e as ToolError {
                if case .unknownTool = e { return error(id: id, code: -32602, message: e.description) }
                return result(id: id, ["content": [["type": "text", "text": e.description]], "isError": true])
            } catch {
                return result(id: id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: Tools

    enum ToolError: Error, CustomStringConvertible {
        case unknownTool(String)
        case invalid(String)

        var description: String {
            switch self {
            case .unknownTool(let name): return "Unknown tool: \(name)"
            case .invalid(let message): return message
            }
        }
    }

    static let tools: [[String: Any]] = [
        tool("disk_status", "Free, used and total space on the volume holding a path (the startup disk by default).",
             ["path": ["type": "string", "description": "Any path on the volume. Defaults to /."]],
             readOnly: true),
        tool("scan_folder", "Scan a folder and summarize what takes space: total size, largest subfolders, largest files and bundles, and space by category.",
             ["path": ["type": "string", "description": "Folder to scan. ~ is expanded."],
              "limit": ["type": "integer", "description": "How many entries to list in each section (default 15, max 200)."]],
             required: ["path"], readOnly: true),
        tool("find_cleanup", "Find regenerable clutter (caches, node_modules, DerivedData, build output, logs, Trash) with sizes and safety advice. Without a path, checks Headroom's list of well-known cache locations in the home folder.",
             ["path": ["type": "string", "description": "Folder to search. Omit to check the well-known locations."],
              "min_size_mb": ["type": "number", "description": "Ignore candidates smaller than this (default 1)."]],
             readOnly: true),
        tool("explain_path", "Explain what a file or folder is and whether it is safe to delete, using Headroom's safety rules.",
             ["path": ["type": "string", "description": "File or folder. ~ is expanded."]],
             required: ["path"], readOnly: true),
        tool("find_duplicates", "Find byte-for-byte identical files in a folder (size, then header, sampled and full SHA-256 hashes), ranked by space wasted.",
             ["path": ["type": "string", "description": "Folder to search. ~ is expanded."],
              "min_size_mb": ["type": "number", "description": "Ignore files smaller than this (default 1)."],
              "limit": ["type": "integer", "description": "Maximum groups to return (default 20, max 200)."]],
             required: ["path"], readOnly: true),
        tool("move_to_trash", "Move files or folders to the Trash (recoverable from Finder). Refuses items Headroom marks 'Do not delete' and top-level system or home folders. Always confirm with the user first.",
             ["paths": ["type": "array", "items": ["type": "string"], "description": "Absolute paths (or ~) to move to the Trash."]],
             required: ["paths"], readOnly: false),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any],
                             required: [String] = [], readOnly: Bool) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
            "annotations": ["readOnlyHint": readOnly, "destructiveHint": !readOnly, "openWorldHint": false],
        ]
    }

    static func call(_ name: String, _ args: [String: Any]) async throws -> Any {
        switch name {
        case "disk_status": return try diskStatus(args)
        case "scan_folder": return try await scanFolder(args)
        case "find_cleanup": return try await findCleanup(args)
        case "explain_path": return try explainPath(args)
        case "find_duplicates": return try await findDuplicates(args)
        case "move_to_trash": return try await moveToTrash(args)
        default: throw ToolError.unknownTool(name)
        }
    }

    // MARK: Tool implementations

    private static func diskStatus(_ args: [String: Any]) throws -> Any {
        let path = try optionalPath(args) ?? "/"
        guard let v = VolumeSnapshot.read(path: path) else { throw ToolError.invalid("Cannot read volume for \(path)") }
        return [
            "volume": v.name,
            "total": sizeJSON(v.total),
            "used": sizeJSON(v.used),
            "free": sizeJSON(v.free),
            "free_percent": percent(v.freeFraction),
        ]
    }

    private static func scanFolder(_ args: [String: Any]) async throws -> Any {
        let root = try await scan(try requiredPath(args))
        let limit = clamp(args["limit"], default: 15)
        let categories = root.categoryTotals()
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { ["category": $0.key.title, "size": $0.value.humanBytes, "bytes": $0.value] as [String: Any] }
        return [
            "path": root.path,
            "size": sizeJSON(root.allocatedSize),
            "files": root.fileCount,
            "folders": root.directoryCount,
            "largest_children": root.children.prefix(limit).map { nodeJSON($0, parentSize: root.allocatedSize) },
            "largest_items": root.largestItems(limit: limit).map { nodeJSON($0, parentSize: root.allocatedSize) },
            "categories": categories,
        ]
    }

    private static func findCleanup(_ args: [String: Any]) async throws -> Any {
        let minimum = Int64((args["min_size_mb"] as? Double ?? 1) * 1_048_576)
        var candidates: [CleanupCandidate] = []
        if let path = try optionalPath(args) {
            let root = try await scan(path)
            candidates = CleanupFinder.candidates(in: root, minimumSize: max(minimum, 1))
        } else {
#if APP_STORE
            throw ToolError.invalid("The App Store build only scans folders you pass explicitly. Provide a path.")
#else
            let scanner = DiskScanner(counters: ScanCounters(), options: ScanOptions())
            for loc in CleanupFinder.knownLocations {
                if let node = try? await scanner.scan(root: URL(fileURLWithPath: loc.path)), node.allocatedSize >= minimum {
                    candidates.append(CleanupCandidate(kind: loc.kind, node: node, contentsOnly: true))
                }
            }
            candidates.sort { $0.size > $1.size }
#endif
        }
        let total = candidates.reduce(Int64(0)) { $0 + $1.size }
        return [
            "total_reclaimable": sizeJSON(total),
            "candidates": candidates.map { c -> [String: Any] in
                let safety = SafetyKB.info(for: c.node)
                return [
                    "path": c.path,
                    "kind": c.kind.rawValue,
                    "size": c.size.humanBytes,
                    "bytes": c.size,
                    "contents_only": c.contentsOnly,
                    "note": c.kind.note,
                    "safety": safetyJSON(safety),
                ]
            },
        ]
    }

    private static func explainPath(_ args: [String: Any]) throws -> Any {
        let path = try requiredPath(args)
        guard let node = chain(to: path).last else { throw ToolError.invalid("No such file or folder: \(path)") }
        var out = safetyJSON(safety(of: path) ?? .unknown)
        out["path"] = node.path
        out["is_directory"] = node.isDirectory
        out["is_package"] = node.isPackage
        return out
    }

    private static func findDuplicates(_ args: [String: Any]) async throws -> Any {
        let root = try await scan(try requiredPath(args))
        var options = DuplicateOptions()
        if let mb = args["min_size_mb"] as? Double { options.minimumSize = max(1, Int64(mb * 1_048_576)) }
        let result = try await DuplicateFinder(counters: DuplicateCounters(), options: options).find(in: root)
        let limit = clamp(args["limit"], default: 20)
        return [
            "files_considered": result.filesConsidered,
            "groups": result.groups.count,
            "total_wasted": sizeJSON(result.wasted),
            "top_groups": result.groups.prefix(limit).map { g -> [String: Any] in
                [
                    "size_each": g.size.humanBytes,
                    "copies": g.count,
                    "wasted": g.wasted.humanBytes,
                    "files_newest_first": g.files.map(\.path),
                ]
            },
        ]
    }

    private static func moveToTrash(_ args: [String: Any]) async throws -> Any {
        guard let raw = args["paths"] as? [String], !raw.isEmpty else { throw ToolError.invalid("'paths' must be a non-empty array of paths.") }
        var nodes: [FileNode] = []
        var refused: [[String: Any]] = []
        for p in raw.map(expand) {
            if let reason = refusal(for: p) {
                refused.append(["path": p, "reason": reason])
                continue
            }
            guard let node = chain(to: p).last, let safety = safety(of: p) else {
                refused.append(["path": p, "reason": "No such file or folder"])
                continue
            }
            if safety.level == .never {
                refused.append(["path": p, "reason": "Headroom marks this 'Do not delete': \(safety.advice)"])
                continue
            }
            // Measure it so the response can report what was freed.
            nodes.append((try? await scan(p)) ?? node)
        }
        let result = nodes.isEmpty ? DeleteResult() : await Deleter(mode: .trash, counters: DeleteCounters()).delete(nodes)
        let failed = Set(result.errors.map(\.path))
        return [
            "moved_to_trash": nodes.map(\.path).filter { !failed.contains($0) },
            "freed": sizeJSON(result.freedBytes),
            "errors": result.errors.map { ["path": $0.path, "message": $0.message] },
            "refused": refused,
        ]
    }

    // MARK: Helpers

    /// Paths that are never deleted through MCP, whatever the rules say.
    static func refusal(for path: String) -> String? {
        let home = NSHomeDirectory()
        let protected: Set<String> = ["/", home, "/System", "/Library", "/Applications", "/Users", "/private", "/usr", "/bin", "/sbin", "/etc", "/var", "/opt",
                                      home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Pictures", home + "/Movies", home + "/Music"]
        if protected.contains(path) { return "Top-level system or home folder" }
        return nil
    }

    private static func scan(_ path: String) async throws -> FileNode {
        var st = stat()
        guard lstat(path, &st) == 0 else { throw ToolError.invalid("No such file or folder: \(path)") }
        let scanner = DiskScanner(counters: ScanCounters(), options: ScanOptions())
        return try await scanner.scan(root: URL(fileURLWithPath: path))
    }

    /// Safety verdict for a path that may not have been scanned.
    static func safety(of path: String) -> SafetyInfo? {
        let nodes = chain(to: path)
        guard let leaf = nodes.last else { return nil }
        return withExtendedLifetime(nodes) { SafetyKB.info(for: leaf) }
    }

    /// Builds parent-linked nodes from / down to `path` without scanning, so the safety rules
    /// can inherit from known ancestors (a file deep inside ~/Library/Caches is still "safe").
    /// Returned root first; keep the array alive while using the leaf (`FileNode.parent` is weak).
    static func chain(to path: String) -> [FileNode] {
        var st = stat()
        guard lstat(path, &st) == 0 else { return [] }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        var parent: FileNode?
        var url = URL(fileURLWithPath: "/")
        var nodes: [FileNode] = []
        for (i, comp) in components.enumerated() {
            if i > 0 { url.appendPathComponent(comp) }
            let isLast = i == components.count - 1
            let isDir = isLast ? (st.st_mode & S_IFMT) == S_IFDIR : true
            let isPackage = isDir && NSWorkspace.shared.isFilePackage(atPath: url.path)
            let node = FileNode(
                url: url, name: comp, isDirectory: isDir, isSymlink: isLast && (st.st_mode & S_IFMT) == S_IFLNK,
                isPackage: isPackage,
                allocatedSize: isLast && !isDir ? Int64(st.st_blocks) * 512 : 0,
                logicalSize: isLast && !isDir ? Int64(st.st_size) : 0,
                modified: nil, category: nil, parent: parent
            )
            nodes.append(node)
            parent = node
        }
        return nodes
    }

    private static func requiredPath(_ args: [String: Any]) throws -> String {
        guard let path = try optionalPath(args) else { throw ToolError.invalid("'path' is required.") }
        return path
    }

    private static func optionalPath(_ args: [String: Any]) throws -> String? {
        guard let raw = args["path"] else { return nil }
        guard let s = raw as? String, !s.isEmpty else { throw ToolError.invalid("'path' must be a non-empty string.") }
        return expand(s)
    }

    static func expand(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func clamp(_ value: Any?, default fallback: Int) -> Int {
        min(200, max(1, (value as? Int) ?? fallback))
    }

    /// One decimal, serialized exactly ("49.9", not "49.899999999999999").
    private static func percent(_ fraction: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), fraction * 100))
    }

    private static func sizeJSON(_ bytes: Int64) -> [String: Any] {
        ["human": bytes.humanBytes, "bytes": bytes]
    }

    private static func nodeJSON(_ n: FileNode, parentSize: Int64) -> [String: Any] {
        var out: [String: Any] = [
            "path": n.path,
            "size": n.allocatedSize.humanBytes,
            "bytes": n.allocatedSize,
            "kind": n.isPackage ? "bundle" : (n.isDirectory ? "folder" : "file"),
        ]
        if parentSize > 0 { out["percent"] = percent(Double(n.allocatedSize) / Double(parentSize)) }
        return out
    }

    private static func safetyJSON(_ s: SafetyInfo) -> [String: Any] {
        let level: String
        switch s.level {
        case .safe: level = "safe"
        case .usuallySafe: level = "usually_safe"
        case .caution: level = "caution"
        case .never: level = "never"
        case .unknown: level = "unknown"
        }
        return ["level": level, "verdict": s.level.title,
         "what": s.what, "advice": s.advice, "rule": s.source]
    }
}
