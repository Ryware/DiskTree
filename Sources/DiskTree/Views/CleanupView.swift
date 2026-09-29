import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.requestDelete) private var requestDelete
    @State private var checked: Set<UUID> = []

    private var inTree: [CleanupCandidate] { state.cleanupCandidates }
    private var known: [CleanupCandidate] { state.knownLocationCandidates }
    private var all: [CleanupCandidate] { inTree + known }
    private var checkedCandidates: [CleanupCandidate] { all.filter { checked.contains($0.id) } }
    private var checkedBytes: Int64 { checkedCandidates.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                Section {
                    if state.scanningKnownLocations {
                        HStack { ProgressView().controlSize(.small); Text("Measuring caches, build output and package stores…") }
                    } else if known.isEmpty {
                        Button("Find system-wide junk (caches, DerivedData, npm/pip/gradle stores…)") { state.scanKnownLocations() }
                    } else {
                        rows(known)
                    }
                } header: {
                    HStack {
                        Text("Known locations in your home folder")
                        Spacer()
                        if !known.isEmpty {
                            Button("Refresh") { state.scanKnownLocations() }.buttonStyle(.link).font(.caption)
                        }
                    }
                }

                Section {
                    if state.root == nil {
                        Text("Scan a folder to find node_modules, .venv, build output and caches inside it.")
                            .foregroundStyle(.secondary)
                    } else if inTree.isEmpty {
                        Text("Nothing obvious to clean in the scanned folder.").foregroundStyle(.secondary)
                    } else {
                        rows(inTree)
                    }
                } header: {
                    Text(state.root.map { "Inside \($0.name)" } ?? "Inside the scanned folder")
                }
            }
        }
        .onChange(of: state.cleanupCandidates.count) { _, _ in checked = checked.filter { id in all.contains { $0.id == id } } }
        .onChange(of: state.knownLocationCandidates.count) { _, _ in checked = checked.filter { id in all.contains { $0.id == id } } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick cleanup").font(.headline)
                Text("Regenerable folders only. Dependencies come back with the next install; caches rebuild themselves.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select All") { checked = Set(all.map(\.id)) }.disabled(all.isEmpty)
            Button("Clear") { checked = [] }.disabled(checked.isEmpty)
            Button(role: .destructive) {
                requestDelete(checkedCandidates.flatMap(\.deletableNodes))
                checked = []
            } label: {
                Label(checked.isEmpty ? "Clean" : "Clean \(checkedBytes.humanBytes)" + (state.deleteMode == .permanent ? " permanently" : " → Trash"),
                      systemImage: state.deleteMode.symbol)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.deleteMode == .permanent ? .red : .accentColor)
            .disabled(checked.isEmpty || state.deleting != nil)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func rows(_ items: [CleanupCandidate]) -> some View {
        let byKind = Dictionary(grouping: items, by: \.kind)
        ForEach(CleanupCandidate.Kind.allCases) { kind in
            if let group = byKind[kind] {
                DisclosureGroup {
                    ForEach(group) { c in row(c) }
                } label: {
                    HStack {
                        Toggle(isOn: groupBinding(group)) { EmptyView() }.toggleStyle(.checkbox)
                        Image(systemName: kind.symbol).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                            Text(kind.note).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(group.count) · \(group.reduce(0) { $0 + $1.size }.humanBytes)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func row(_ c: CleanupCandidate) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { checked.contains(c.id) },
                set: { on in if on { checked.insert(c.id) } else { checked.remove(c.id) } }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.node.name)
                Text(c.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            SafetyBadge(info: SafetyKB.info(for: c.node))
            if let m = c.node.modified {
                Text(m.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
            }
            Text(c.size.humanBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .padding(.leading, 20)
        .contextMenu {
            Button("Reveal in Finder") { state.revealInFinder(c.node) }
            Button(state.deleteMode.actionLabel, role: .destructive) { requestDelete(c.deletableNodes) }
        }
    }

    private func groupBinding(_ group: [CleanupCandidate]) -> Binding<Bool> {
        Binding(
            get: { group.allSatisfy { checked.contains($0.id) } },
            set: { on in for c in group { if on { checked.insert(c.id) } else { checked.remove(c.id) } } }
        )
    }
}
