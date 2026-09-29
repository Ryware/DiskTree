import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @Binding var pane: Pane
    @Environment(\.scenePhase) private var scenePhase
    @State private var volumeSpace: VolumeSpace?

    private struct VolumeSpace {
        let name: String
        let total: Int64
        let free: Int64
        var used: Int64 { total - free }
    }

    private struct CategoryRow: Identifiable {
        let category: FileCategory
        let bytes: Int64
        var id: FileCategory { category }
    }

    private var categories: [CategoryRow] {
        state.categoryTotals.filter { $0.value > 0 }
            .map { CategoryRow(category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes == $1.bytes ? $0.category.title < $1.category.title : $0.bytes > $1.bytes }
    }

    private var cleanupBytes: Int64 {
        state.cleanupCandidates.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        if let root = state.root {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(root)
                    diskSpaceCard
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        statistic("Size on disk", value: root.allocatedSize.humanBytes,
                                  note: "\(root.logicalSize.humanBytes) logical size", symbol: "internaldrive", color: .purple)
                        statistic("Files", value: root.fileCount.formatted(),
                                  note: "Inside the scanned folder", symbol: "doc.on.doc", color: .blue)
                        statistic("Folders", value: root.directoryCount.formatted(),
                                  note: "Excludes the scanned root", symbol: "folder", color: .orange)
                        statistic("Cleanup candidates", value: cleanupBytes.humanBytes,
                                  note: "\(state.cleanupCandidates.count.formatted()) folders to review", symbol: "sparkles", color: .mint)
                    }

                    card {
                        sectionHeader("Space by category", destination: .categories)
                        let rows = categories
                        if rows.isEmpty {
                            emptyMessage("No categorized file data in this folder.")
                        } else {
                            let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
                            Chart(rows) { row in
                                BarMark(x: .value("Size", row.bytes), y: .value("Category", row.category.title))
                                    .foregroundStyle(row.category.color)
                                    .cornerRadius(4)
                                    .accessibilityLabel(row.category.title)
                                    .accessibilityValue(row.bytes.humanBytes)
                            }
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let bytes = value.as(Int64.self) { Text(bytes.humanBytes) }
                                    }
                                }
                            }
                            .frame(height: CGFloat(rows.count) * 28 + 30)
                            ForEach(rows) { row in
                                HStack {
                                    Label(row.category.title, systemImage: row.category.symbol)
                                        .foregroundStyle(row.category.color)
                                    Spacer()
                                    Text(Double(row.bytes) / Double(max(1, total)), format: .percent.precision(.fractionLength(1)))
                                        .foregroundStyle(.secondary)
                                    Text(row.bytes.humanBytes).frame(minWidth: 80, alignment: .trailing)
                                }
                                .font(.callout).monospacedDigit()
                            }
                        }
                    }

                    card {
                        sectionHeader("Largest files & apps", destination: .largest)
                        if state.largest.isEmpty {
                            emptyMessage("No files found in this folder.")
                        } else {
                            ForEach(Array(state.largest.prefix(5))) { node in
                                Button {
                                    state.selection = [node.id]
                                    state.selectedNode = node
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: node.iconName)
                                            .foregroundStyle(node.effectiveCategory.color).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(node.name).foregroundStyle(.primary).lineLimit(1)
                                            Text(node.path).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer(minLength: 12)
                                        Text(node.allocatedSize.humanBytes).monospacedDigit().foregroundStyle(.primary)
                                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(state.selectedNode === node ? Color.accentColor.opacity(0.1) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Inspect \(node.name)")
                            }
                        }
                    }

                    card {
                        sectionHeader("Cleanup overview", destination: .cleanup)
                        Text(state.cleanupCandidates.isEmpty
                             ? "No cleanup candidates found in the scanned folder."
                             : "Review \(cleanupBytes.humanBytes) of dependencies, build output, caches and other cleanup candidates before removing anything.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("File and cleanup statistics cover the scanned folder. Disk space covers its entire volume and refreshes automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .task(id: root.id) {
                refreshDiskSpace()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                    refreshDiskSpace()
                }
            }
            .onChange(of: state.deleting == nil) { _, finished in
                if finished { refreshDiskSpace() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDiskSpace() }
            }
        }
    }

    private var diskSpaceCard: some View {
        card {
            HStack {
                Label("Disk space", systemImage: "internaldrive").font(.headline)
                Spacer()
                Button { refreshDiskSpace() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.link)
            }
            if let space = volumeSpace {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(space.free.humanBytes)
                        .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("free").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(space.total.humanBytes) total").foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: Double(space.used), total: Double(space.total))
                    .tint(.purple)
                    .accessibilityLabel("Disk space used")
                    .accessibilityValue("\(space.used.humanBytes) of \(space.total.humanBytes)")
                HStack {
                    Text(space.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(space.used.humanBytes) used · \(Int((Double(space.free) / Double(space.total) * 100).rounded()))% free")
                        .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                Text("Entire volume containing the scanned folder · refreshes every 15 seconds. Moving files to Trash does not free disk space until it is emptied.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Disk space is unavailable for this volume. Try refreshing.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshDiskSpace() {
        guard let path = state.root?.path else { volumeSpace = nil; return }
        // A fresh URL avoids cached capacity values after cleanup or external writes.
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey
        ]), let total = values.volumeTotalCapacity, total > 0,
           let free = values.volumeAvailableCapacity else {
            volumeSpace = nil
            return
        }
        volumeSpace = VolumeSpace(name: values.volumeName ?? "Scanned volume",
                                  total: Int64(total), free: min(Int64(total), max(0, Int64(free))))
    }

    private func header(_ root: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dashboard", systemImage: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(root.path).font(.callout).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            HStack(spacing: 12) {
                if let finished = state.progress.finished {
                    Text("Scanned \(finished.formatted(date: .abbreviated, time: .shortened))")
                }
                Text(String(format: "%.1fs", state.progress.elapsed))
            }
            .font(.caption).foregroundStyle(.white.opacity(0.8))
            if state.progress.errors > 0 {
                Label("\(state.progress.errors.formatted()) unreadable items · totals may be incomplete", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BrandBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statistic(_ title: String, value: String, note: String, symbol: String, color: Color) -> some View {
        card {
            Label(title, systemImage: symbol).font(.callout.weight(.medium)).foregroundStyle(color)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, destination: Pane) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("View all") { pane = destination }.buttonStyle(.link)
                .accessibilityLabel("View \(destination.title)")
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}
