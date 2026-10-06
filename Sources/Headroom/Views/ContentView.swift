import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case dashboard, tree, treemap, categories, largest, duplicates, cleanup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .tree: return "Folder Tree"
        case .treemap: return "Treemap"
        case .categories: return "By Category"
        case .largest: return "Largest Files"
        case .duplicates: return "Duplicates"
        case .cleanup: return "Cleanup"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .tree: return "folder"
        case .treemap: return "square.grid.3x3.square"
        case .categories: return "chart.pie"
        case .largest: return "arrow.up.doc"
        case .duplicates: return "doc.on.doc"
        case .cleanup: return "sparkles"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var pane: Pane = .dashboard
    @State private var showInspector = false
    @State private var pendingDelete: [FileNode] = []
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                ZStack { detail }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBar()
            }
            .frame(minWidth: 520, minHeight: 420)
            .task {
                // Present the inspector after the first layout pass; presenting it during the
                // initial constraint update can trip AppKit's split-view min-size race.
                try? await Task.sleep(for: .milliseconds(300))
                showInspector = true
            }
            .inspector(isPresented: $showInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 240, ideal: 290, max: 400)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: Binding(get: { state.deleting != nil }, set: { _ in })) {
            DeleteProgressSheet()
        }
        .alert("Delete \(pendingDelete.count) item\(pendingDelete.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirm) {
            Button(state.deleteMode == .trash ? "Move to Trash" : "Delete Permanently", role: .destructive) {
                let items = pendingDelete
                pendingDelete = []
                Task { await state.delete(items) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            let total = pendingDelete.reduce(0) { $0 + $1.allocatedSize }
            Text(state.deleteMode == .trash
                 ? "\(total.humanBytes) will be moved to the Trash."
                 : "\(total.humanBytes) will be removed permanently. This cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let r = state.lastDeleteResult {
                DeleteToast(result: r, mode: state.deleteMode) {
                    withAnimation(.spring(duration: 0.4)) { state.lastDeleteResult = nil }
                }
                .padding(.bottom, 44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: state.lastDeleteResult?.freedBytes)
        .environment(\.requestDelete, RequestDeleteAction { nodes in
            guard !nodes.isEmpty else { return }
            pendingDelete = nodes
            showDeleteConfirm = true
        })
    }

    private var sidebar: some View {
        List(selection: Binding<Pane?>(get: { pane }, set: { if let p = $0 { pane = p } })) {
            ForEach(Pane.allCases) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            if let root = state.root {
                Spacer().frame(height: 8)
                Section("Scanned") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(root.name).font(.headline).lineLimit(1)
                        Text(root.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        Text("\(root.allocatedSize.humanBytes) · \(root.fileCount.formatted()) files")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
    }

    @ViewBuilder
    private var detail: some View {
        if state.isScanning && state.root == nil {
            ScanningView()
        } else if state.root == nil && pane != .cleanup {
            WelcomeView()
        } else {
            switch pane {
            case .dashboard: DashboardView(pane: $pane)
            case .tree: TreeView()
            case .treemap: TreemapView()
            case .categories: CategoriesView()
            case .largest: LargestFilesView()
            case .duplicates: DuplicatesView()
            case .cleanup: CleanupView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { state.pickFolder() } label: { Label("Scan Folder", systemImage: "folder.badge.plus") }
                .help("Choose a folder or volume to scan (⌘O)")
            Button { state.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .disabled(state.rootURL == nil || state.isScanning)
                .help("Rescan (⌘R)")
            if state.isScanning {
                Button { state.cancelScan(); state.phase = .idle } label: { Label("Stop", systemImage: "stop.circle") }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Delete mode", selection: $state.deleteMode) {
                ForEach(DeleteMode.allCases) { Text($0 == .trash ? "Trash" : "Permanent").tag($0) }
            }
            .pickerStyle(.segmented)
            .help(state.deleteMode.shortNote)
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                .help("Show what the selected item is and whether it's safe to delete")
        }
    }
}

/// Injected action so any subview can ask for a confirmed delete.
struct RequestDeleteAction {
    let run: ([FileNode]) -> Void
    func callAsFunction(_ nodes: [FileNode]) { run(nodes) }
}

private struct RequestDeleteKey: EnvironmentKey {
    static let defaultValue = RequestDeleteAction { _ in }
}

extension EnvironmentValues {
    var requestDelete: RequestDeleteAction {
        get { self[RequestDeleteKey.self] }
        set { self[RequestDeleteKey.self] = newValue }
    }
}

struct DeleteSummary: Identifiable {
    let id = UUID()
    let freed: String
    let detail: String
    init(_ r: DeleteResult) {
        freed = r.freedBytes.humanBytes
        var d = "\(r.removedFiles.formatted()) files, \(r.removedDirectories.formatted()) folders removed."
        if !r.errors.isEmpty {
            d += "\n\(r.errors.count) item(s) could not be removed:\n" + r.errors.prefix(5).map { "• \($0.path): \($0.message)" }.joined(separator: "\n")
        }
        detail = d
    }
}

struct StatusBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            switch state.phase {
            case .idle:
                Text("Ready").foregroundStyle(.secondary)
            case .scanning:
                ProgressView().controlSize(.small)
                Text("\(state.progress.files.formatted()) files · \(state.progress.directories.formatted()) folders · \(state.progress.bytes.humanBytes)")
                Text(state.progress.current).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            case .done:
                Text("\(state.progress.files.formatted()) files · \(state.progress.directories.formatted()) folders · \(state.progress.bytes.humanBytes) in \(String(format: "%.1fs", state.progress.elapsed))")
                if state.progress.errors > 0 {
                    Text("· \(state.progress.errors) unreadable").foregroundStyle(.orange)
                }
            case .failed(let msg):
                Text("Scan failed: \(msg)").foregroundStyle(.red)
            }
            Spacer()
            if !state.selection.isEmpty {
                let total = state.selectedNodes.reduce(0) { $0 + $1.allocatedSize }
                Text("\(state.selection.count) selected · \(total.humanBytes)").foregroundStyle(.secondary)
            }
            Label(state.deleteMode == .trash ? "Trash mode" : "Permanent mode", systemImage: state.deleteMode.symbol)
                .foregroundStyle(state.deleteMode == .permanent ? .red : .secondary)
                .help(state.deleteMode.shortNote)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct DeleteProgressSheet: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 14) {
            let p = state.deleting ?? DeleteProgress()
            Text(state.deleteMode == .trash ? "Moving to Trash…" : "Deleting…").font(.headline)
            ProgressView(value: p.fraction)
            Text("\(p.done.formatted()) / \(p.total.formatted()) · \(p.bytes.humanBytes) freed")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            if !p.current.isEmpty {
                Text(p.current).font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
            }
            if state.deleteMode == .permanent {
                Button("Cancel") { state.cancelDelete() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
