import SwiftUI
import Charts
import AppKit

// MARK: - Menu bar icon

enum RingIcon {
    /// A small ring: the arc is the share of the disk that is still free.
    static func image(free: Double, status: DiskStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let color: NSColor
        switch status {
        case .ok: color = .black
        case .warning: color = NSColor(red: 0.96, green: 0.70, blue: 0.34, alpha: 1)
        case .critical: color = NSColor(red: 0.93, green: 0.42, blue: 0.42, alpha: 1)
        }
        let img = NSImage(size: size, flipped: false) { _ in
            let c = NSPoint(x: 9, y: 9)
            let r: CGFloat = 6.5
            let track = NSBezierPath()
            track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
            track.lineWidth = 2.6
            color.withAlphaComponent(0.28).setStroke()
            track.stroke()

            let f = min(1, max(0.04, free))
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * CGFloat(f), clockwise: true)
            arc.lineWidth = 2.6
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            return true
        }
        img.isTemplate = (status == .ok)
        return img
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor = DiskMonitor.shared
    let showText: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: RingIcon.image(free: monitor.snapshot?.freeFraction ?? 0.5, status: monitor.status))
            if showText, let s = monitor.snapshot {
                Text(Self.compact(s.free))
            }
        }
        .onAppear { AppWindows.opener = { openWindow(id: "main") } }
    }

    static func compact(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1e9
        return gb >= 100 ? "\(Int(gb.rounded())) GB" : String(format: "%.0f GB", gb)
    }
}

// MARK: - Sparkline used by the popover and the Dashboard

struct FreeSpaceChart: View {
    let samples: [FreeSpaceSample]
    var showAxes = false
    var color: Color = .purple

    var body: some View {
        Chart(samples) { s in
            AreaMark(x: .value("Time", s.t), y: .value("Free GB", Double(s.free) / 1e9))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", s.t), y: .value("Free GB", Double(s.free) / 1e9))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .accessibilityLabel("Free disk space over the last 7 days")
    }
}

/// Dashboard card: startup-disk free space over the last 7 days.
struct FreeSpaceTrendCard: View {
    @ObservedObject var monitor = DiskMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Free space trend", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                Spacer()
                if let d = monitor.delta(hours: 24) {
                    Text("\(d >= 0 ? "+" : "−")\(abs(d).humanBytes) in 24 h")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(d >= 0 ? Color(red: 0.38, green: 0.78, blue: 0.54) : Color(red: 0.93, green: 0.42, blue: 0.42))
                }
            }
            if monitor.history.count >= 3 {
                FreeSpaceChart(samples: monitor.history, showAxes: true).frame(height: 110)
            } else {
                Text("Headroom records free space on your startup disk while it runs. The trend appears after a little while.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            Text("Startup disk · last 7 days · stored only on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}

// MARK: - Popover

struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var monitor = DiskMonitor.shared
    @State private var safeNodes: [FileNode] = []
    @State private var confirming = false
    @State private var cleaning = false
    @State private var lastResult: String?

    private var safeBytes: Int64 { safeNodes.reduce(0) { $0 + $1.allocatedSize } }
    private var trashBytes: Int64 {
        state.knownLocationCandidates.filter { $0.kind == .trash }.reduce(0) { $0 + $1.size }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .ok: return Color(red: 0.38, green: 0.78, blue: 0.54)
        case .warning: return Color(red: 0.96, green: 0.70, blue: 0.34)
        case .critical: return Color(red: 0.93, green: 0.42, blue: 0.42)
        }
    }
    private var statusText: String {
        switch monitor.status {
        case .ok: return "Healthy"
        case .warning: return "Getting low"
        case .critical: return "Low"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            diskSection
            Divider()
            trendSection
#if !APP_STORE
            Divider()
            reclaimSection
#endif
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
        .task {
            monitor.refresh()
#if !APP_STORE
            if state.knownLocationCandidates.isEmpty && !state.scanningKnownLocations { state.scanKnownLocations() }
#endif
        }
        .onChange(of: state.scanningKnownLocations) { _, scanning in
            if !scanning { recomputeSafe() }
        }
        .onAppear {
            AppWindows.opener = { openWindow(id: "main") }
            recomputeSafe()
        }
    }

    // MARK: Sections

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(monitor.snapshot?.name ?? "Startup Disk", systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(statusText).font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            if let s = monitor.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(s.free.humanBytes).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("free").foregroundStyle(.secondary)
                    Spacer()
                    Text("of \(s.total.humanBytes)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: Double(s.used), total: Double(s.total)).tint(statusColor)
                Text("\(Int((s.freeFraction * 100).rounded()))% free · warns below \(Int(monitor.lowGB)) GB")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Disk information is unavailable.").foregroundStyle(.secondary)
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last 7 days").font(.subheadline.weight(.semibold))
                Spacer()
                if let d = monitor.delta(hours: 24) {
                    Text("\(d >= 0 ? "+" : "−")\(abs(d).humanBytes) / 24 h")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if monitor.history.count >= 3 {
                FreeSpaceChart(samples: monitor.history, color: statusColor).frame(height: 54)
            } else {
                Text("Collecting data. The trend appears after a little while.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

#if !APP_STORE
    private var reclaimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reclaimable now").font(.subheadline.weight(.semibold))
                Spacer()
                if state.scanningKnownLocations {
                    ProgressView().controlSize(.small)
                } else {
                    Button { state.scanKnownLocations() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Look again")
                }
            }
            if cleaning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Moving to Trash…").font(.callout) }
            } else if confirming {
                Text("Move \(safeBytes.humanBytes) of safe caches, logs and build output to the Trash?")
                    .font(.callout)
                HStack {
                    Button("Move to Trash") { clean() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { confirming = false }
                }
            } else {
                Text(safeBytes > 0
                     ? "\(safeBytes.humanBytes) that macOS and your tools recreate on their own."
                     : (state.scanningKnownLocations ? "Looking through caches, logs and build output…" : "Nothing safe to clean right now."))
                    .font(.callout).foregroundStyle(.secondary)
                if safeBytes > 0 {
                    Button("Clean \(safeBytes.humanBytes) (safe items only)") { confirming = true }
                        .buttonStyle(.borderedProminent)
                }
                if trashBytes > 0 {
                    Text("Trash holds \(trashBytes.humanBytes). Empty it in Finder to get that space back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let lastResult {
                Text(lastResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
#endif

    private var footer: some View {
        HStack(spacing: 10) {
            Button { AppWindows.showMain() } label: { Label("Open Headroom", systemImage: "macwindow") }
            Button {
                AppWindows.showMain()
                state.scan(URL(fileURLWithPath: NSHomeDirectory()))
            } label: { Label("Scan Home", systemImage: "house") }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).help("Quit Headroom")
        }
        .font(.callout)
    }

    // MARK: Actions

    private func recomputeSafe() {
#if !APP_STORE
        safeNodes = state.knownLocationCandidates
            .filter { $0.kind != .trash }
            .flatMap(\.deletableNodes)
            .filter { SafetyKB.info(for: $0).level == .safe }
#endif
    }

    private func clean() {
        let nodes = safeNodes
        guard !nodes.isEmpty else { return }
        confirming = false
        cleaning = true
        Task {
            let result = await state.delete(nodes, mode: .trash, silent: true)
            cleaning = false
            let moved = result?.freedBytes ?? 0
            lastResult = "Moved \(moved.humanBytes) to the Trash. Empty the Trash to get the space back."
            monitor.refresh()
            state.scanKnownLocations()
        }
    }
}
