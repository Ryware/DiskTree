import SwiftUI

/// Bump when "What's new" changes; the intro re-opens on the What's New page for existing users.
let currentIntroVersion = 2

struct IntroStep: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let bullets: [(symbol: String, text: String)]
    let art: Art
    enum Art { case hero, scan, tree, treemap, safety, clean, whatsNew }
}

private let steps: [IntroStep] = [
    IntroStep(id: 0, eyebrow: "WELCOME", title: "DiskTree",
              bullets: [("bolt.fill", "Scans a million files in seconds"),
                        ("square.grid.3x3.square", "Shows where the space goes, by folder, type and age"),
                        ("checkmark.shield.fill", "Tells you what is safe to delete — and what isn't")],
              art: .hero),
    IntroStep(id: 1, eyebrow: "STEP 1", title: "Scan",
              bullets: [("folder.badge.plus", "Pick any folder or a whole volume — ⌘O"),
                        ("house", "\"Home\" is the right start for most Macs"),
                        ("stop.circle", "Stop any time; results stay in memory, Rescan is ⌘R")],
              art: .scan),
    IntroStep(id: 2, eyebrow: "STEP 2", title: "Understand",
              bullets: [("list.bullet.indent", "Folder Tree: sizes on disk, bars show share of parent"),
                        ("square.grid.3x3.square", "Treemap: big tiles are big files. Double-click to zoom"),
                        ("chart.pie", "By Category and Largest Files answer \"what is this?\"")],
              art: .treemap),
    IntroStep(id: 3, eyebrow: "STEP 3", title: "Is it safe?",
              bullets: [("checkmark.shield.fill", "Green: regenerates itself (caches, node_modules, build output)"),
                        ("exclamationmark.triangle.fill", "Orange: app or user data — read the note in the Inspector"),
                        ("xmark.octagon.fill", "Red: never delete (Keychains, Mail, Photos library)")],
              art: .safety),
    IntroStep(id: 4, eyebrow: "STEP 4", title: "Clean",
              bullets: [("sparkles", "Cleanup finds junk inside the scan and in known caches"),
                        ("trash", "Trash mode: recoverable from the Trash, frees space later"),
                        ("flame", "Permanent mode: parallel delete, instant, no undo")],
              art: .clean),
    IntroStep(id: 5, eyebrow: "WHAT'S NEW", title: "Version 0.2",
              bullets: [("square.grid.3x3.square", "Treemap with category / age / safety coloring"),
                        ("questionmark.circle", "Inspector with delete-safety verdicts for 160+ known locations"),
                        ("bolt.fill", "getattrlistbulk scanner and dirfd-based parallel deletion"),
                        ("app.badge", "New icon, welcome screen, recent scans, this tour")],
              art: .whatsNew),
]

struct IntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State var page: Int = 0
    @State private var revealed = 0            // bullets shown on the current page
    @State private var artTick = 0             // drives per-page art animation

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 0) {
                HStack(spacing: 36) {
                    artView.frame(width: 260, height: 260)
                    textView.frame(width: 340, alignment: .leading)
                }
                .padding(.horizontal, 40).padding(.top, 36)
                .frame(maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 760, height: 460)
        .onAppear { reveal() }
        .onChange(of: page) { _, _ in reveal() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                artTick += 1
            }
        }
    }

    private var step: IntroStep { steps[page] }

    // MARK: text

    private var textView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.eyebrow).font(.caption.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.65))
            Text(step.title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(step.bullets.enumerated()), id: \.offset) { i, b in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: b.symbol).frame(width: 20).foregroundStyle(.white)
                        Text(b.text).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(i < revealed ? 1 : 0)
                    .offset(x: i < revealed ? 0 : 24)
                    .animation(.spring(duration: 0.45, bounce: 0.2).delay(Double(i) * 0.12), value: revealed)
                }
            }
        }
        .id(page)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func reveal() {
        revealed = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { revealed = step.bullets.count }
    }

    // MARK: art

    @ViewBuilder
    private var artView: some View {
        ZStack {
            switch step.art {
            case .hero:
                HeroLoader()
            case .scan:
                BentoLoader().frame(width: 220, height: 220)
            case .tree, .treemap:
                TreemapArt(tick: artTick).frame(width: 240, height: 220)
            case .safety:
                SafetyArt(tick: artTick).frame(width: 240, height: 220)
            case .clean:
                CleanArt(tick: artTick).frame(width: 240, height: 220)
            case .whatsNew:
                Image(systemName: "sparkles").font(.system(size: 120, weight: .light)).foregroundStyle(.white)
                    .rotationEffect(.degrees(artTick % 2 == 0 ? -6 : 6))
                    .animation(.easeInOut(duration: 0.8), value: artTick)
            }
        }
        .id(page)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button("Skip") { dismiss() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps) { s in
                    Capsule().fill(.white.opacity(s.id == page ? 0.95 : 0.35))
                        .frame(width: s.id == page ? 22 : 8, height: 8)
                        .animation(.spring(duration: 0.35), value: page)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if page > 0 {
                    Button("Back") { withAnimation(.spring(duration: 0.45)) { page -= 1 } }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Button(page == steps.count - 1 ? "Get Started" : "Next") {
                    if page == steps.count - 1 { dismiss() } else { withAnimation(.spring(duration: 0.45)) { page += 1 } }
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color(red: 0.35, green: 0.25, blue: 0.9))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Art pieces

private struct TreemapArt: View {
    let tick: Int
    private let rects: [(CGRect, Color)] = [
        (CGRect(x: 0, y: 0, width: 0.55, height: 0.6), .yellow), (CGRect(x: 0.57, y: 0, width: 0.43, height: 0.35), .pink),
        (CGRect(x: 0.57, y: 0.37, width: 0.43, height: 0.23), .mint), (CGRect(x: 0, y: 0.62, width: 0.3, height: 0.38), .blue),
        (CGRect(x: 0.32, y: 0.62, width: 0.38, height: 0.38), .purple), (CGRect(x: 0.72, y: 0.62, width: 0.28, height: 0.38), .orange),
    ]
    var body: some View {
        GeometryReader { g in
            ForEach(Array(rects.enumerated()), id: \.offset) { i, r in
                let rect = r.0
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(r.1.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: tick % rects.count == i ? 2.5 : 0))
                    .frame(width: rect.width * g.size.width - 4, height: rect.height * g.size.height - 4)
                    .position(x: (rect.midX) * g.size.width, y: rect.midY * g.size.height)
                    .scaleEffect(tick % rects.count == i ? 1.04 : 1)
                    .animation(.easeInOut(duration: 0.4), value: tick)
            }
        }
    }
}

private struct SafetyArt: View {
    let tick: Int
    private let rows: [(String, String, SafetyLevel)] = [
        ("node_modules", "shippingbox", .safe), ("DerivedData", "hammer", .safe), ("Application Support", "folder", .caution),
        ("Photos Library", "photo", .never),
    ]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    Image(systemName: r.1).frame(width: 18)
                    Text(r.0).lineLimit(1)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: r.2.symbol)
                        Text(r.2.short)
                    }
                    .font(.caption.bold()).foregroundStyle(r.2.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(r.2.color.opacity(0.28), in: Capsule())
                    .overlay(Capsule().strokeBorder(r.2.color.opacity(0.6), lineWidth: 0.5))
                    .scaleEffect(tick % rows.count == i ? 1.12 : 1)
                    .animation(.spring(duration: 0.4, bounce: 0.4), value: tick)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            }
        }
    }
}

private struct CleanArt: View {
    let tick: Int
    var body: some View {
        let phase = tick % 4   // 0-1: tiles present, 2: shrinking, 3: gone
        VStack(spacing: 14) {
            ZStack {
                BentoTiles(lit: 5)
                    .scaleEffect(phase >= 2 ? 0.2 : 1)
                    .opacity(phase >= 2 ? 0 : 1)
                    .animation(.easeIn(duration: 0.5), value: phase)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 90)).foregroundStyle(.white)
                    .opacity(phase == 3 ? 1 : 0).scaleEffect(phase == 3 ? 1 : 0.5)
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: phase)
            }
            .frame(width: 170, height: 170)
            Text(phase == 3 ? "Freed 23.6 GB" : "node_modules · 23.6 GB")
                .font(.headline).foregroundStyle(.white).contentTransition(.opacity)
        }
    }
}


/// App icon with an orbiting light — reads as "working", not a static picture.
private struct HeroLoader: View {
    @State private var spin = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(colors: [.clear, .white.opacity(0.9), .clear], center: .center), lineWidth: 6)
                .frame(width: 236, height: 236)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.2).repeatForever(autoreverses: false), value: spin)
            Circle().fill(.white).frame(width: 12, height: 12).shadow(color: .white, radius: 8)
                .offset(y: -118)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.2).repeatForever(autoreverses: false), value: spin)
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                .frame(width: 190, height: 190)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        }
        .onAppear { spin = true }
    }
}
