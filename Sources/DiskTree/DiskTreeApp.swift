import SwiftUI

@main
struct DiskTreeApp: App {
    @StateObject private var state = AppState()
    @AppStorage("seenIntroVersion") private var seenIntroVersion = 0
    @State private var showIntro = false
    @State private var introPage = 0

    var body: some Scene {
        WindowGroup("DiskTree") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1120, minHeight: 680)
                .background(WindowSizing(minSize: NSSize(width: 1120, height: 680)))
                .sheet(isPresented: $showIntro, onDismiss: { seenIntroVersion = currentIntroVersion }) {
                    IntroView(page: introPage)
                }
                .task {
                    // First launch → full tour; updated app → jump to What's New.
                    try? await Task.sleep(for: .milliseconds(600))
                    if seenIntroVersion == 0 { introPage = 0; showIntro = true }
                    else if seenIntroVersion < currentIntroVersion { introPage = 5; showIntro = true }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DiskTree") {
                    let credits = NSAttributedString(string: "See what's eating your disk. Clean it in one click.\n\nScanning uses getattrlistbulk(2) and fans out across all cores; permanent deletion renames first, then unlinks in parallel.", attributes: [.font: NSFont.systemFont(ofSize: 11)])
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "DiskTree"])
                }
            }
            CommandGroup(replacing: .help) {
                Button("Welcome Tour") { introPage = 0; showIntro = true }
                Button("What's New in DiskTree") { introPage = 5; showIntro = true }
            }
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { state.pickFolder() }
                    .keyboardShortcut("o")
                Button("Rescan") { state.rescan() }
                    .keyboardShortcut("r")
                    .disabled(state.rootURL == nil || state.isScanning)
            }
        }
        Settings {
            SettingsView().environmentObject(state)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Picker("Deleting", selection: $state.deleteMode) {
                ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text("Permanent deletion unlinks every file in parallel (like rimraf) and cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
