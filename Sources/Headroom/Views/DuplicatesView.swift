import SwiftUI

/// Groups of byte-identical files. Pick which copies to remove; one copy per group always stays
/// unless the user explicitly unchecks that protection.
struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.requestDelete) private var requestDelete
    @State private var checked: Set<FileNode.ID> = []
    @State private var expanded: Set<String> = []
    @State private var filter = ""
    @State private var keepOneCopy = true
    @State private var shown = 150

    private var groups: [DuplicateGroup] {
        guard let d = state.duplicates else { return [] }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return d.groups }
        return d.groups.filter { g in g.files.contains { $0.path.lowercased().contains(q) } }
    }
    private var checkedNodes: [FileNode] {
        groups.flatMap(\.files).filter { checked.contains($0.id) }
    }
    private var checkedBytes: Int64 { checkedNodes.reduce(0) { $0 + $1.allocatedSize } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.root == nil {
                placeholder("Scan a folder first, then look for duplicates inside it.", symbol: "folder.badge.questionmark")
            } else if let p = state.duplicateProgress {
                progress(p)
            } else if let d = state.duplicates {
                if d.groups.isEmpty {
                    placeholder("No duplicate files of 1 MB or more \(state.rootLocation?.phrase ?? "in this folder").", symbol: "checkmark.circle")
                } else {
                    list
                }
            } else {
                start
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate files").font(.headline)
                if let d = state.duplicates, !d.groups.isEmpty {
                    Text("\(d.wasted.humanBytes) reclaimable · \(d.groups.count.formatted()) groups · files of 1 MB and more, compared byte for byte")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Files that exist more than once with identical content.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.duplicates != nil && state.duplicateProgress == nil {
                TextField("Filter by path", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
                Menu("Select") {
                    Button("Keep newest copy, select the rest") { select(keep: .newest) }
                    Button("Keep oldest copy, select the rest") { select(keep: .oldest) }
                    Button("Keep the copy highest in the tree, select the rest") { select(keep: .shallowest) }
                    Divider()
                    Button("Clear selection") { checked = [] }
                }
                .menuStyle(.borderedButton).fixedSize()
                Button { state.findDuplicates() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                Button(role: .destructive) {
                    requestDelete(checkedNodes)
                    checked = []
                } label: {
                    Label(checked.isEmpty ? state.deleteMode.actionLabel : "\(state.deleteMode.actionLabel.replacingOccurrences(of: "…", with: "")) \(checkedBytes.humanBytes)",
                          systemImage: state.deleteMode.symbol)
                }
                .tint(state.deleteMode == .permanent ? .red : nil)
                .disabled(checked.isEmpty)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: States

    private var start: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.doc").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            Text("Find duplicate files \(state.rootLocation?.phrase ?? "in the scanned folder")").font(.title3.weight(.semibold))
            Text("Files are grouped by size, then compared by content hash, so only true byte-for-byte copies are listed. Files inside app bundles and files under 1 MB are skipped.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Button("Find duplicates") { state.findDuplicates() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ p: DuplicateProgress) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: p.fraction).frame(width: 320)
            Text(p.phase.isEmpty ? "Preparing…" : p.phase).font(.headline)
            Text(p.total > 0 ? "\(p.done.formatted()) of \(p.total.formatted()) candidate files · \(p.bytes.humanBytes) read" : "\(p.bytes.humanBytes) read")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            Text(p.current).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 480)
            Button("Cancel") { state.cancelDuplicateScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(groups.prefix(shown)) { g in
                Section {
                    ForEach(g.files) { f in row(f, in: g) }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: g.files.first?.iconName ?? "doc")
                            .foregroundStyle(g.files.first?.effectiveCategory.color ?? .secondary)
                        Text(g.files.first?.name ?? "").lineLimit(1)
                        Text("· \(g.count) copies · \(g.size.humanBytes) each").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(g.wasted.humanBytes) reclaimable").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            if groups.count > shown {
                Section {
                    HStack {
                        Spacer()
                        Button("Show \(min(200, groups.count - shown)) more of \(groups.count.formatted()) groups") { shown += 200 }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: filter) { _, _ in shown = 150 }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Toggle("Always keep at least one copy of each file", isOn: $keepOneCopy)
                    .toggleStyle(.checkbox)
                Spacer()
                if !checked.isEmpty {
                    Text("\(checked.count) selected · \(checkedBytes.humanBytes)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
        }
        .onChange(of: keepOneCopy) { _, on in if on { enforceKeepOne() } }
    }

    private func row(_ f: FileNode, in g: DuplicateGroup) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { checked.contains(f.id) },
                set: { on in
                    if on {
                        if keepOneCopy && g.files.filter({ checked.contains($0.id) }).count >= g.count - 1 { return }
                        checked.insert(f.id)
                    } else { checked.remove(f.id) }
                }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(f.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(f.name).foregroundStyle(.secondary)
                    if let m = f.modified {
                        Text("· \(m.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                    }
                    if f.id == g.files.first?.id { tag("newest") }
                }
                .font(.caption)
            }
            Spacer()
            SafetyBadge(info: SafetyKB.info(for: f))
            Button { state.revealInFinder(f) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") { state.revealInFinder(f) }
            Button("Keep this one, select the other \(g.count - 1)") {
                for o in g.files where o.id != f.id { checked.insert(o.id) }
                checked.remove(f.id)
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
            .background(.secondary.opacity(0.18), in: Capsule())
    }

    // MARK: Selection helpers

    private enum Keep { case newest, oldest, shallowest }

    private func select(keep: Keep) {
        var next = checked
        for g in groups {
            let keeper: FileNode?
            switch keep {
            case .newest: keeper = g.files.first                       // sorted newest first
            case .oldest: keeper = g.files.last
            case .shallowest: keeper = g.files.min { $0.url.pathComponents.count < $1.url.pathComponents.count }
            }
            for f in g.files { if f.id == keeper?.id { next.remove(f.id) } else { next.insert(f.id) } }
        }
        checked = next
    }

    private func enforceKeepOne() {
        for g in groups where g.files.allSatisfy({ checked.contains($0.id) }) {
            if let first = g.files.first { checked.remove(first.id) }
        }
    }
}
