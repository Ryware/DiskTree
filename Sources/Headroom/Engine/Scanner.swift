import Foundation
import Darwin
import os

/// Lock-protected counters the UI polls while a scan runs.
final class ScanCounters: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private struct State {
        var files = 0
        var directories = 0
        var bytes: Int64 = 0
        var errors = 0
        var current = ""
    }

    func add(files: Int = 0, directories: Int = 0, bytes: Int64 = 0, errors: Int = 0, current: String? = nil) {
        lock.withLock {
            $0.files += files
            $0.directories += directories
            $0.bytes += bytes
            $0.errors += errors
            if let current { $0.current = current }
        }
    }

    var snapshot: (files: Int, directories: Int, bytes: Int64, errors: Int, current: String) {
        lock.withLock { ($0.files, $0.directories, $0.bytes, $0.errors, $0.current) }
    }
}

struct ScanOptions {
    /// Absolute paths never descended into (virtual filesystems and other volumes).
    var excludedPaths: Set<String> = ["/dev", "/System/Volumes", "/Volumes", "/private/var/vm", "/.vol", "/Network"]
    /// Stay on the volume the root lives on (skips mount points and firmlinks).
    var oneFileSystem = true
}

/// Extensions macOS treats as opaque bundles. Shown as one item in the UI.
private let packageExtensions: Set<String> = [
    "app", "bundle", "framework", "xcframework", "pkg", "mpkg", "kext", "plugin", "appex", "prefpane",
    "qlgenerator", "xpc", "playground", "xcodeproj", "xcworkspace", "photoslibrary", "musiclibrary",
    "tvlibrary", "sparsebundle", "vmwarevm", "pvm", "utm", "rtfd", "pages", "numbers", "key", "scptd",
    "band", "logicx", "fcpbundle", "imovielibrary", "dmgpart", "lproj", "nib", "storyboardc",
]

/// One raw directory entry decoded from a getattrlistbulk buffer.
private struct RawEntry {
    var name: String
    var type: UInt32          // VREG / VDIR / VLNK …
    var modified: Date?
    var dataLength: Int64
    var allocSize: Int64
    var devID: UInt32
}

/// Concurrent directory walker built on getattrlistbulk(2): a single syscall returns
/// a whole batch of entries with name, type, mtime and sizes, so there is no
/// per-file stat. Every directory is scanned as its own child task, so the walk
/// fans out across all cores; the cooperative thread pool bounds it.
struct DiskScanner {
    let counters: ScanCounters
    let options: ScanOptions

    func scan(root: URL) async throws -> FileNode {
        var st = stat()
        let rootDev: UInt32 = lstat(root.path, &st) == 0 ? UInt32(bitPattern: st.st_dev) : 0
        var isDir = true
        if lstat(root.path, &st) == 0 { isDir = (st.st_mode & S_IFMT) == S_IFDIR }
        let node = FileNode(
            url: root,
            name: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent,
            isDirectory: isDir,
            isSymlink: false,
            isPackage: false,
            allocatedSize: isDir ? 0 : Int64(st.st_blocks) * 512,
            logicalSize: isDir ? 0 : Int64(st.st_size),
            modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
            category: FileCategory.forDirectory(named: root.lastPathComponent),
            parent: nil
        )
        if isDir {
            try await scanDirectory(node, rootDev: rootDev)
        }
        return node
    }

    private func scanDirectory(_ dir: FileNode, rootDev: UInt32) async throws {
        try Task.checkCancellation()
        counters.add(directories: 1, current: dir.path)

        let entries: [RawEntry]
        do {
            entries = try Self.readDirectory(dir.path)
        } catch {
            counters.add(errors: 1)
            dir.finalize(children: [])
            return
        }

        var files: [FileNode] = []
        var subdirs: [FileNode] = []
        files.reserveCapacity(entries.count)

        for e in entries {
            let isDir = e.type == UInt32(VDIR.rawValue)
            let isSymlink = e.type == UInt32(VLNK.rawValue)
            let ext = (e.name as NSString).pathExtension.lowercased()
            let isPackage = isDir && !ext.isEmpty && packageExtensions.contains(ext)
            let url = dir.url.appendingPathComponent(e.name, isDirectory: isDir)

            if isDir {
                if options.oneFileSystem && rootDev != 0 && e.devID != rootDev { continue }
                if !options.excludedPaths.isEmpty && options.excludedPaths.contains(url.path) { continue }
            }

            let node = FileNode(
                url: url, name: e.name,
                isDirectory: isDir, isSymlink: isSymlink, isPackage: isPackage,
                allocatedSize: isDir ? 0 : e.allocSize,
                logicalSize: isDir ? 0 : e.dataLength,
                modified: e.modified,
                category: isDir ? (isPackage ? .apps : FileCategory.forDirectory(named: e.name)) : nil,
                parent: dir
            )
            if isDir {
                subdirs.append(node)
            } else {
                files.append(node)
                counters.add(files: 1, bytes: e.allocSize)
            }
        }

        // Fan out: each subdirectory becomes its own task.
        if !subdirs.isEmpty {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for sub in subdirs {
                    group.addTask { try await scanDirectory(sub, rootDev: rootDev) }
                }
                try await group.waitForAll()
            }
        }

        dir.finalize(children: files + subdirs)
    }

    // MARK: - getattrlistbulk

    private struct ScanError: Error { let errno: Int32 }

    // attrgroup_t bit values from <sys/attr.h>, spelled out so the mixed-width C macros don't fight Swift.
    private static let cmnReturnedAttrs: attrgroup_t = 0x8000_0000
    private static let cmnError: attrgroup_t = 0x2000_0000
    private static let cmnName: attrgroup_t = 0x0000_0001
    private static let cmnDevID: attrgroup_t = 0x0000_0002
    private static let cmnObjType: attrgroup_t = 0x0000_0008
    private static let cmnModTime: attrgroup_t = 0x0000_0400
    private static let fileTotalSize: attrgroup_t = 0x0000_0002
    private static let fileAllocSize: attrgroup_t = 0x0000_0004
    private static let optPackInvalAttrs: UInt64 = 0x8

    /// Reads every entry of one directory with getattrlistbulk. Requested attributes,
    /// in the order the kernel packs them: RETURNED_ATTRS, [ERROR], NAME, DEVID,
    /// OBJTYPE, MODTIME, then FILE_TOTALSIZE, FILE_ALLOCSIZE.
    private static func readDirectory(_ path: String) throws -> [RawEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ScanError(errno: errno) }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = cmnReturnedAttrs | cmnError | cmnName | cmnDevID | cmnObjType | cmnModTime
        attrs.fileattr = fileTotalSize | fileAllocSize

        let bufSize = 256 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        var out: [RawEntry] = []
        while true {
            let n = getattrlistbulk(fd, &attrs, buf, bufSize, optPackInvalAttrs)
            if n < 0 { throw ScanError(errno: errno) }
            if n == 0 { break }

            var p = buf
            for _ in 0..<Int(n) {
                let entryStart = p
                let length = Int(p.loadUnaligned(as: UInt32.self))
                p += 4
                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p += MemoryLayout<attribute_set_t>.size

                var entry = RawEntry(name: "", type: 0, modified: nil, dataLength: 0, allocSize: 0, devID: 0)
                var failed = false

                if returned.commonattr & cmnError != 0 {
                    let err = p.loadUnaligned(as: UInt32.self)
                    p += 4
                    if err != 0 { failed = true }
                }
                if returned.commonattr & cmnName != 0 {
                    let ref = p.loadUnaligned(as: attrreference_t.self)
                    let namePtr = (p + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    entry.name = String(cString: namePtr)
                    p += MemoryLayout<attrreference_t>.size
                }
                if returned.commonattr & cmnDevID != 0 {
                    entry.devID = UInt32(bitPattern: p.loadUnaligned(as: Int32.self))
                    p += 4
                }
                if returned.commonattr & cmnObjType != 0 {
                    entry.type = p.loadUnaligned(as: UInt32.self)
                    p += 4
                }
                if returned.commonattr & cmnModTime != 0 {
                    let ts = p.loadUnaligned(as: timespec.self)
                    entry.modified = Date(timeIntervalSince1970: TimeInterval(ts.tv_sec))
                    p += MemoryLayout<timespec>.size
                }
                if returned.fileattr & fileTotalSize != 0 {
                    entry.dataLength = p.loadUnaligned(as: Int64.self)
                    p += 8
                }
                if returned.fileattr & fileAllocSize != 0 {
                    entry.allocSize = p.loadUnaligned(as: Int64.self)
                    p += 8
                }

                if !failed && !entry.name.isEmpty && entry.name != "." && entry.name != ".." {
                    out.append(entry)
                }
                p = entryStart + length
            }
        }
        return out
    }
}
