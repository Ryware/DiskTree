import Foundation

/// How to name a scanned root for people. A bare "/" means nothing to someone who isn't
/// used to Unix paths, so volumes go by their volume name and the home folder by "Home".
struct ScanLocation: Equatable {
    enum Kind: Equatable { case startupDisk, volume, home, folder }

    let kind: Kind
    /// Headline: "Macintosh HD", "Home (ilya)", or the folder name.
    let name: String
    let path: String

    var symbol: String {
        switch kind {
        case .startupDisk: return "internaldrive"
        case .volume: return "externaldrive"
        case .home: return "house"
        case .folder: return "folder"
        }
    }

    var isVolume: Bool { kind == .startupDisk || kind == .volume }

    /// Second line under the name; the path itself when it says more than the name does.
    var detail: String {
        switch kind {
        case .startupDisk: return "Whole startup disk"
        case .volume: return "Whole volume · \(path)"
        case .home: return path
        case .folder: return (path as NSString).abbreviatingWithTildeInPath
        }
    }

    /// One line for headers: the path for folders, the name for disks and home.
    var summary: String { kind == .folder ? detail : "\(name) · \(detail)" }

    /// Short single name: "Macintosh HD", "Home (ilya)", "~/Downloads".
    var title: String { kind == .folder ? detail : name }

    /// "Find duplicate files on Macintosh HD" but "in Downloads".
    var phrase: String { (isVolume ? "on " : "in ") + name }

    init(kind: Kind, name: String, path: String) {
        self.kind = kind
        self.name = name
        self.path = path
    }

    /// Pure classification, so it can be tested without real volumes.
    init(path: String, isVolumeRoot: Bool, volumeName: String?, homePath: String = NSHomeDirectory(),
         userName: String = NSUserName()) {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if path == "/" {
            self.init(kind: .startupDisk, name: volumeName ?? "Startup Disk", path: path)
        } else if isVolumeRoot {
            self.init(kind: .volume, name: volumeName ?? (path as NSString).lastPathComponent, path: path)
        } else if path == homePath {
            self.init(kind: .home, name: "Home (\(userName))", path: path)
        } else {
            let last = (path as NSString).lastPathComponent
            self.init(kind: .folder, name: last.isEmpty ? path : last, path: path)
        }
    }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeLocalizedNameKey, .volumeNameKey])
        self.init(path: url.standardizedFileURL.path, isVolumeRoot: values?.isVolume ?? false,
                  volumeName: values?.volumeLocalizedName ?? values?.volumeName)
    }
}
