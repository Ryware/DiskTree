import SwiftUI

struct LargestFilesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.requestDelete) private var requestDelete
    @State private var selection: Set<FileNode.ID> = []
    @State private var minimumMB: Double = 0

    private var items: [FileNode] {
        let floor = Int64(minimumMB * 1_048_576)
        return state.largest.filter { $0.allocatedSize >= floor }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Largest files & bundles").font(.headline)
                Spacer()
                HStack {
                    Text("At least").foregroundStyle(.secondary)
                    Slider(value: $minimumMB, in: 0...1024, step: 16).frame(width: 160)
                    Text("\(Int(minimumMB)) MB").monospacedDigit().frame(width: 64, alignment: .leading)
                }
                Button(role: .destructive) {
                    requestDelete(items.filter { selection.contains($0.id) })
                } label: { Label(state.deleteMode.actionLabel, systemImage: state.deleteMode.symbol) }
                .tint(state.deleteMode == .permanent ? .red : nil)
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            FileListTable(items: items, selection: $selection)
        }
    }
}
