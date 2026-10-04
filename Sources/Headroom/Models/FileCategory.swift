import Foundation
import SwiftUI

/// Storage category used for the "what is eating my disk" breakdown.
enum FileCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case images, video, audio, documents, archives, code, apps, packages, caches, logs, diskImages, virtualMachines, aiModels, databases, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .code: return "Source Code"
        case .apps: return "Applications"
        case .packages: return "Dependencies"
        case .caches: return "Caches"
        case .logs: return "Logs"
        case .diskImages: return "Disk Images"
        case .virtualMachines: return "Virtual Machines"
        case .aiModels: return "AI Models"
        case .databases: return "Databases"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .images: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .apps: return "app.badge"
        case .packages: return "shippingbox"
        case .caches: return "memorychip"
        case .logs: return "list.bullet.rectangle"
        case .diskImages: return "externaldrive"
        case .virtualMachines: return "desktopcomputer"
        case .aiModels: return "brain"
        case .databases: return "cylinder.split.1x2"
        case .other: return "questionmark.folder"
        }
    }

    /// Muted, desaturated palette shared by the chart, treemap and icons.
    var color: Color {
        switch self {
        case .images: return Color(red: 0.80, green: 0.52, blue: 0.62)          // rose
        case .video: return Color(red: 0.62, green: 0.50, blue: 0.76)           // plum
        case .audio: return Color(red: 0.48, green: 0.50, blue: 0.78)           // periwinkle
        case .documents: return Color(red: 0.42, green: 0.60, blue: 0.80)       // steel blue
        case .archives: return Color(red: 0.66, green: 0.54, blue: 0.42)        // walnut
        case .code: return Color(red: 0.48, green: 0.68, blue: 0.52)            // sage
        case .apps: return Color(red: 0.40, green: 0.66, blue: 0.72)            // teal
        case .packages: return Color(red: 0.84, green: 0.62, blue: 0.40)        // amber
        case .caches: return Color(red: 0.80, green: 0.48, blue: 0.44)          // terracotta
        case .logs: return Color(red: 0.60, green: 0.62, blue: 0.66)            // gray
        case .diskImages: return Color(red: 0.44, green: 0.62, blue: 0.66)      // slate teal
        case .virtualMachines: return Color(red: 0.52, green: 0.70, blue: 0.64) // seafoam
        case .aiModels: return Color(red: 0.82, green: 0.72, blue: 0.42)        // ochre
        case .databases: return Color(red: 0.58, green: 0.46, blue: 0.70)       // mauve
        case .other: return Color(red: 0.55, green: 0.56, blue: 0.60)           // neutral
        }
    }

    // MARK: - Classification

    private static let byExtension: [String: FileCategory] = {
        var m: [String: FileCategory] = [:]
        func add(_ cat: FileCategory, _ exts: [String]) { exts.forEach { m[$0] = cat } }
        add(.images, ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "svg", "cr2", "nef", "arw", "dng", "psd", "ai", "sketch", "icns"])
        add(.video, ["mp4", "mov", "m4v", "mkv", "avi", "wmv", "webm", "flv", "mpg", "mpeg", "hevc", "ts"])
        add(.audio, ["mp3", "aac", "m4a", "wav", "flac", "aiff", "aif", "ogg", "wma", "opus"])
        add(.documents, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md", "csv", "epub", "odt", "ods", "odp"])
        add(.archives, ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "lz4", "zst", "jar", "war", "nupkg", "whl", "gem", "crate"])
        add(.code, ["swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "cs", "java", "kt", "kts", "go", "rs", "py", "rb", "js", "jsx", "ts", "tsx", "mjs", "cjs", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sh", "zsh", "sql", "proto", "graphql", "tf", "dart", "php", "lua", "r", "scala", "ex", "exs", "hs"])
        add(.apps, ["app", "bundle", "pkg", "ipa", "apk", "exe", "msi", "dylib", "so", "framework", "xcframework"])
        add(.logs, ["log", "crash", "diag", "ips", "trace"])
        add(.diskImages, ["dmg", "iso", "img", "raw", "sparseimage", "sparsebundle", "vhd", "vhdx", "vdi", "vmdk", "qcow2"])
        add(.virtualMachines, ["vmwarevm", "pvm", "utm", "vbox"])
        add(.databases, ["db", "sqlite", "sqlite3", "vscdb", "realm", "mdb", "ldb", "sst", "db-wal", "db-shm", "sqlite-wal", "duckdb", "parquet"])
        add(.aiModels, ["gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel", "mlmodelc", "mlpackage", "tflite", "npz"])
        return m
    }()

    /// Directory names that mark everything beneath them as a category.
    private static let byDirectoryName: [String: FileCategory] = [
        "node_modules": .packages, ".pnpm-store": .packages, ".npm": .packages, ".yarn": .packages,
        ".cargo": .packages, ".gradle": .packages, ".m2": .packages, ".nuget": .packages, "Pods": .packages,
        ".swiftpm": .packages, ".build": .packages, "target": .packages, "vendor": .packages,
        "site-packages": .packages, ".venv": .packages, "venv": .packages, ".conda": .packages, ".gem": .packages,
        "Caches": .caches, ".cache": .caches, "DerivedData": .caches, "cache": .caches,
        "CachedData": .caches, "Cache": .caches, "tmp": .caches, "temp": .caches, ".Trash": .caches,
        "Logs": .logs, "logs": .logs, "DiagnosticReports": .logs, "CrashReporter": .logs,
        "Virtual Machines.localized": .virtualMachines, "Parallels": .virtualMachines,
        "Applications": .apps,
        "com.docker.docker": .virtualMachines, "Virtual Machines": .virtualMachines, ".vmware": .virtualMachines,
        ".ollama": .aiModels, "huggingface": .aiModels, ".lmstudio": .aiModels,
    ]

    static func forDirectory(named name: String) -> FileCategory? {
        byDirectoryName[name]
    }

    static func forFile(named name: String) -> FileCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return .other }
        return byExtension[ext] ?? .other
    }
}
