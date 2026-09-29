import Foundation
import SwiftUI

enum ScanPhase: Equatable {
    case idle, scanning, done, failed(String)
}

struct ScanProgress {
    var files = 0
    var directories = 0
    var bytes: Int64 = 0
    var errors = 0
    var current = ""
    var started = Date()
    var finished: Date?
    var elapsed: TimeInterval { (finished ?? Date()).timeIntervalSince(started) }
}

struct DeleteProgress {
    var done = 0
    var total = 0
    var bytes: Int64 = 0
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

@MainActor
final class AppState: ObservableObject {
    @Published var root: FileNode?
    @Published var rootURL: URL?
    @Published var phase: ScanPhase = .idle
    @Published var progress = ScanProgress()
    @Published var selection: Set<FileNode.ID> = [] {
        didSet {
            // Inspector follows the most recently added selected item.
            if let id = selection.subtracting(oldValue).first ?? selection.first, let n = index[id] {
                selectedNode = n
            }
        }
    }
    @Published var selectedNode: FileNode?
    @Published var deleteMode: DeleteMode = .trash
    @Published var deleting: DeleteProgress?
    @Published var lastDeleteResult: DeleteResult?
    @Published var cleanupCandidates: [CleanupCandidate] = []
    @Published var knownLocationCandidates: [CleanupCandidate] = []
    @Published var scanningKnownLocations = false
    @Published var categoryTotals: [FileCategory: Int64] = [:]
    @Published var largest: [FileNode] = []
    @Published var treeVersion = 0
    /// Installed by the outline view so deletions animate rows out instead of reloading.
    var treeRemovalHandler: (([FileNode]) -> Bool)?
    @Published var recentScans: [String] = (UserDefaults.standard.stringArray(forKey: "recentScans") ?? []).filter { FileManager.default.fileExists(atPath: $0) }

    private var scanTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var counters = ScanCounters()

    /// Map from id to node for selection lookups.
    private var index: [FileNode.ID: FileNode] = [:]

    var isScanning: Bool { phase == .scanning }

    // MARK: Scanning

    func scan(_ url: URL) {
        cancelScan()
        rootURL = url
        recentScans.removeAll { $0 == url.path }
        recentScans.insert(url.path, at: 0)
        recentScans = Array(recentScans.prefix(5))
        UserDefaults.standard.set(recentScans, forKey: "recentScans")
        root = nil
        selection = []
        selectedNode = nil
        cleanupCandidates = []
        categoryTotals = [:]
        largest = []
        index = [:]
        counters = ScanCounters()
        progress = ScanProgress()
        phase = .scanning

        let counters = self.counters
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pullCounters() }
        }

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = DiskScanner(counters: counters, options: ScanOptions())
            do {
                let node = try await scanner.scan(root: url)
                await self?.finishScan(node)
            } catch is CancellationError {
                await self?.setPhase(.idle)
            } catch {
                await self?.setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func rescan() {
        if let rootURL { scan(rootURL) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func setPhase(_ p: ScanPhase) { phase = p }
    private func setKnownLocations(_ c: [CleanupCandidate]) {
        knownLocationCandidates = c
        scanningKnownLocations = false
    }

    private func pullCounters() {
        let s = counters.snapshot
        progress.files = s.files
        progress.directories = s.directories
        progress.bytes = s.bytes
        progress.errors = s.errors
        progress.current = s.current
    }

    private func finishScan(_ node: FileNode) {
        pollTimer?.invalidate()
        pollTimer = nil
        pullCounters()
        progress.finished = Date()
        root = node
        selectedNode = node
        phase = .done
        treeVersion += 1
        rebuildDerived()
    }

    func rebuildDerived() {
        guard let root else { return }
        var idx: [FileNode.ID: FileNode] = [:]
        root.walk { idx[$0.id] = $0 }
        index = idx
        categoryTotals = root.categoryTotals()
        largest = root.largestItems(limit: 100)
        cleanupCandidates = CleanupFinder.candidates(in: root)
    }

    func node(for id: FileNode.ID) -> FileNode? { index[id] }

    var selectedNodes: [FileNode] {
        selection.compactMap { index[$0] }
    }

    // MARK: Known junk locations (independent of the open folder)

    func scanKnownLocations() {
        guard !scanningKnownLocations else { return }
        scanningKnownLocations = true
        knownLocationCandidates = []
        Task.detached(priority: .utility) { [weak self] in
            var found: [CleanupCandidate] = []
            let scanner = DiskScanner(counters: ScanCounters(), options: ScanOptions())
            for loc in CleanupFinder.knownLocations {
                if let node = try? await scanner.scan(root: URL(fileURLWithPath: loc.path)), node.allocatedSize > 0 {
                    found.append(CleanupCandidate(kind: loc.kind, node: node, contentsOnly: true))
                }
            }
            let sorted = found.sorted { $0.size > $1.size }
            await self?.setKnownLocations(sorted)
        }
    }

    // MARK: Deleting

    func delete(_ nodes: [FileNode]) async {
        guard !nodes.isEmpty, deleting == nil else { return }
        let counters = DeleteCounters()
        deleting = DeleteProgress()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let s = counters.snapshot
            Task { @MainActor in self?.deleting = DeleteProgress(done: s.done, total: s.total, bytes: s.bytes) }
        }
        let deleter = Deleter(mode: deleteMode, counters: counters)
        let result = await Task.detached(priority: .userInitiated) { await deleter.delete(nodes) }.value
        timer.invalidate()

        // Drop removed nodes from the in-memory tree instead of rescanning.
        let removed = nodes.filter { n in !result.errors.contains(where: { $0.path.hasPrefix(n.path) }) }
        for n in removed {
            selection.remove(n.id)
            if selectedNode === n { selectedNode = n.parent }
        }
        if !(treeRemovalHandler?(removed) ?? false) {
            for n in removed { n.parent?.removeChild(n) }
            treeVersion += 1
        }
        knownLocationCandidates.removeAll { c in nodes.contains { $0 === c.node } }
        deleting = nil
        rebuildDerived()
        if let root {
            progress.files = root.fileCount
            progress.directories = root.directoryCount
            progress.bytes = root.allocatedSize
        }
        // Let the progress sheet finish dismissing before presenting the summary alert.
        try? await Task.sleep(for: .milliseconds(350))
        lastDeleteResult = result
    }

    // MARK: Folder picking

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            scan(url)
        }
    }

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
}
