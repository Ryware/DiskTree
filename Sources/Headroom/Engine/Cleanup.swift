import Foundation

/// A folder that is safe-ish to wipe (regenerated caches, build output, dependencies).
struct CleanupCandidate: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case dependencies, buildOutput, caches, logs, trash
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dependencies: return "Dependencies (node_modules, .venv, Pods…)"
            case .buildOutput: return "Build output (DerivedData, .build, target…)"
            case .caches: return "Caches"
            case .logs: return "Logs & crash reports"
            case .trash: return "Trash"
            }
        }
        var symbol: String {
            switch self {
            case .dependencies: return "shippingbox"
            case .buildOutput: return "hammer"
            case .caches: return "memorychip"
            case .logs: return "list.bullet.rectangle"
            case .trash: return "trash"
            }
        }
        var note: String {
            switch self {
            case .dependencies: return "Reinstalled by npm/pip/pod install. Safe to delete for projects you are not actively working on."
            case .buildOutput: return "Regenerated on the next build."
            case .caches: return "Apps rebuild these as needed. First launch after cleaning may be slower."
            case .logs: return "Diagnostic only."
            case .trash: return "Files already deleted in Finder."
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let node: FileNode
    /// Known system locations are emptied, not removed (apps expect the folder to exist).
    var contentsOnly = false
    var size: Int64 { node.allocatedSize }
    var deletableNodes: [FileNode] { contentsOnly ? node.children : [node] }
    var path: String { node.path }

    static func == (l: CleanupCandidate, r: CleanupCandidate) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum CleanupFinder {
    /// Directory names that, wherever they appear, are a cleanup candidate.
    private static let markers: [String: CleanupCandidate.Kind] = [
        "node_modules": .dependencies, ".venv": .dependencies, "venv": .dependencies, "Pods": .dependencies,
        "vendor": .dependencies, ".pnpm-store": .dependencies, "bower_components": .dependencies,
        ".build": .buildOutput, "DerivedData": .buildOutput, "target": .buildOutput, "build": .buildOutput,
        "dist": .buildOutput, ".next": .buildOutput, ".nuxt": .buildOutput, ".turbo": .buildOutput,
        "bin": .buildOutput, "obj": .buildOutput, "__pycache__": .buildOutput, ".gradle": .buildOutput,
        "Caches": .caches, ".cache": .caches, "CachedData": .caches, ".Trash": .trash,
        "Logs": .logs, "logs": .logs, "DiagnosticReports": .logs, "CrashReporter": .logs,
    ]

    /// Well-known junk locations, scanned on demand regardless of what folder is open.
    static var knownLocations: [(kind: CleanupCandidate.Kind, path: String)] {
        let h = NSHomeDirectory()
        return [
            (.caches, "\(h)/Library/Caches"),
            (.buildOutput, "\(h)/Library/Developer/Xcode/DerivedData"),
            (.caches, "\(h)/Library/Developer/Xcode/iOS DeviceSupport"),
            (.caches, "\(h)/Library/Developer/CoreSimulator/Caches"),
            (.caches, "\(h)/Library/Developer/Xcode/Archives"),
            (.logs, "\(h)/Library/Logs"),
            (.caches, "\(h)/.cache"),
            (.caches, "\(h)/.npm/_cacache"),
            (.dependencies, "\(h)/.pnpm-store"),
            (.caches, "\(h)/.yarn/cache"),
            (.caches, "\(h)/.gradle/caches"),
            (.dependencies, "\(h)/.nuget/packages"),
            (.caches, "\(h)/.cargo/registry"),
            (.caches, "\(h)/.m2/repository"),
            (.caches, "\(h)/Library/Caches/Homebrew"),
            (.caches, "\(h)/Library/Caches/pip"),
            (.caches, "\(h)/.cocoapods/repos"),
            (.trash, "\(h)/.Trash"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Walk a scanned tree and pick out cleanup candidates. Stops descending once
    /// a candidate is found so nested node_modules aren't double counted.
    static func candidates(in root: FileNode, minimumSize: Int64 = 1 << 20) -> [CleanupCandidate] {
        var out: [CleanupCandidate] = []
        func visit(_ n: FileNode) {
            guard n.isDirectory, !n.isPackage else { return }
            if n !== root, let kind = markers[n.name], n.allocatedSize >= minimumSize, looksLikeCandidate(n, kind) {
                out.append(CleanupCandidate(kind: kind, node: n))
                return
            }
            for c in n.children where c.isDirectory { visit(c) }
        }
        visit(root)
        return out.sorted { $0.size > $1.size }
    }

    /// Guard against generic names ("build", "bin", "target") that aren't build output.
    private static func looksLikeCandidate(_ n: FileNode, _ kind: CleanupCandidate.Kind) -> Bool {
        guard kind == .buildOutput, let parent = n.parent else { return true }
        let siblings = Set(parent.children.map(\.name))
        switch n.name {
        case "target": return siblings.contains("Cargo.toml") || siblings.contains("pom.xml")
        case "build": return siblings.contains("CMakeLists.txt") || siblings.contains("build.gradle")
            || siblings.contains("package.json") || siblings.contains("Makefile") || siblings.contains("setup.py")
        case "bin", "obj": return siblings.contains { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") }
        case "dist": return siblings.contains("package.json") || siblings.contains("setup.py") || siblings.contains("pyproject.toml")
        case ".gradle": return siblings.contains("build.gradle") || siblings.contains("build.gradle.kts") || parent.name == NSHomeDirectory().split(separator: "/").last.map(String.init)
        default: return true
        }
    }
}
