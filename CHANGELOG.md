# Changelog

## Unreleased

### 🚀 New feature

- **MCP server for AI agents.** `Headroom --mcp` serves the Model Context Protocol on stdio, so Claude Code, Claude Desktop, Cursor and other MCP clients can check free space, scan folders, find cleanup candidates and duplicates, and ask whether a path is safe to delete, using the same engine and safety rules as the app. The only write is `move_to_trash`, which is recoverable and refuses items marked *Do not delete*. See [Use with AI agents](README.md#use-with-ai-agents-mcp-and-command-line).
- **Command line tool for agents.** The app binary takes commands (`Headroom status`, `scan`, `cleanup`, `duplicates`, `explain`, `trash` and more) and prints JSON, for agents that run shell commands. The app carries instructions for agents in `Contents/Resources/AGENTS.md`, so an agent asked to use Headroom finds out how by itself.
- **Agent work shows in the window.** When the window is empty or shows the same folder, an agent's scan and duplicate search run there, so you see their progress and results.

## 1.0.3 — October 6, 2026

### 🐛 Fixed

- **Duplicate finder no longer eats all memory.** Hashing read files through `FileHandle`, and every chunk it returned stayed alive until the whole worker finished, so a scan held every byte it had compared in memory (tens of GB on a big tree) until macOS started killing other apps. Hashing now uses `pread(2)` into one reusable 1 MB buffer per worker: a 7.9 GB verification pass runs in 7 MB and about three times faster.
- **Permanent delete no longer grinds for hours when a security product blocks it.** An antivirus or ransomware shield with an Endpoint Security extension can hold every `unlinkat` for seconds and then refuse it. Headroom now stops after a few consecutive held refusals, renames any hidden folder back to its real name, and explains what happened in the result instead of showing "0 KB freed" with no reason. A refused removal is also no longer retried unless the file actually carried an immutable flag, which halved the time wasted per file.
- The result toast shows the reason for a failure inline; the Details button is no longer needed to learn that nothing was removed.
- A late progress tick could re-open the delete sheet after the delete had finished.

### ✨ Changed

- **Cancel button** on the permanent-delete sheet. Files already removed stay removed, everything else is left untouched.
- Delete progress advances per file and shows the current path, so a slow delete is visibly moving instead of looking frozen.
- Progress for deletes and duplicate scans is published only when it changes; the window no longer re-renders ten times a second for the length of a delete.

### 🧰 Chores

- 83 unit tests: multi-chunk hashing against CryptoKit, locked-file deletion, the stall rule, and cancel.

## 1.0.2 — October 5, 2026

### ✨ Changed

- **New landing page** at [headroom-app.org](https://headroom-app.org/): an interactive treemap demo in the hero that scans sample data, shows verdicts on hover, zooms on click and lets you clean the safe items; native CSS, self-hosted Geist, a bento feature grid with real screenshots, a scroll-driven explainer that walks through the duplicate finder's four passes on a mock group of files, and light and dark modes with a toggle. Motion is native CSS and respects Reduce Motion. No frameworks. The site uses Google Analytics for visit and download counts; the app still sends nothing.
- README and site documentation cover the duplicate finder's four comparison passes and the menu bar popover.

### 🧹 Chores

- Removed all signing and App Store identifiers from the repository and its history. `ExportOptions.plist` is now a gitignored local file generated from `ExportOptions.example.plist`; the release script reads the team id and App Store Connect keys from the keychain and environment only.

## 1.0.1 — October 5, 2026 · First stable release

DiskTree is now **Headroom**, and this is the first stable release. The name describes what the app gives you, and it no longer clashes with another disk analyzer on the App Store. The bundle id is unchanged, so 0.x installs update in place and the free-space history carries over. (1.0.0 was tagged internally and never published; everything below is new since 0.2.0.)

### 🚀 New feature

- **Duplicate finder.** Finds files that exist more than once with identical content, grouped and sorted by how much space one copy would give back. Files are bucketed by size, then compared by a 64 KB header hash, then by samples from the middle and the end, then by a full SHA-256, so only true byte-for-byte copies are listed and large files are read in full only when every cheaper check says they match. Files under 1 MB and files inside app bundles are skipped. Select with one click (keep newest / oldest / highest in the tree), keep-one-copy protection on by default, delete to the Trash or permanently.
- **Dashboard card** showing reclaimable duplicate space with a jump to the new Duplicates pane.
- **Progress by phase** for the duplicate scan ("Comparing file headers", "Sampling large files", "Verifying byte for byte") and a paged results list, so huge scans neither look stuck nor stall the window.

### ✨ Changed

- Renamed to Headroom everywhere: app, menu bar, GitHub repository, landing page, DMG name (`Headroom-1.0.1.dmg`).
- The What's New tour explains the duplicate finder and the new name.
- Landing page redesign: scroll reveals, live free-space ring, animated duplicate-finder demo, menu bar screenshot.

### 🧰 Chores

- 79 unit tests (duplicate finder added), CI coverage and badges updated for the new name.
- Release workflow publishes `Headroom-<version>.dmg`.
- Removed Apple team id, App Store Connect ids, SKU and contact email from the repository and its history; `ExportOptions.plist` and the App Store tooling are local-only. The signing identity is discovered from the keychain.

## 0.2.0 — September 30, 2026

Headroom now watches your disk from the menu bar. Still 100% free, with every feature unlocked.

### 🚀 New feature

- **Menu bar monitor** with a ring showing how much of the startup disk is free. It turns amber, then red, as space runs low. Optionally show the free space as text next to the ring.
- **Popover** with free / used / total space, a Healthy / Getting low / Low status, and a 7-day free-space chart.
- **Reclaimable now**: adds up safe caches, logs and build output and lets you clean them in one click. Only items rated Safe are included, and they go to the Trash, so it is recoverable.
- **Alerts** (local notifications): low free space (default below 10 GB) and fast drops (default 5 GB within an hour). Both thresholds are adjustable. Tapping an alert opens Headroom.
- **Dashboard trend card** with the 7-day free-space history and the change over the last 24 hours.
- **Settings** (⌘,):
  - Show Headroom in the menu bar
  - Show free space next to the icon
  - Keep running when the window is closed
  - Show in the Dock (turn off for a menu-bar-only app)
  - Open at login (starts quietly in the menu bar)
  - Alert toggles and thresholds
  - Deleting mode (Trash or permanent)
- Popover shortcuts: **Open Headroom**, **Scan Home**, Settings and Quit.

### 🔥 Bug fix

- Sorting by Size, Name, Files or Modified no longer freezes the app on very large scans. Folders are now sorted only when they are displayed.
- **Open Headroom** from the menu bar (and tapping an alert) reliably brings the window forward, including after the window was closed or when the app is running without a Dock icon.

### ⚙️ Chore

- Version 0.2.0 (build 2). Existing users see the What's New page of the intro tour.
- Direct-download builds are universal (Apple silicon and Intel), signed with a Developer ID certificate and notarized by Apple.
- The Mac App Store build stays sandboxed: it scans and cleans only folders you choose. Home, Startup Disk, and one-click cleanup of known caches stay in the direct-download app.
- Unit tests cover the scanner, deleter, safety rules, cleanup finder, and disk monitor. GitHub Actions runs them on every push.

### 🔒 Privacy

Free-space history (at most 7 days) is stored only on your Mac in Application Support. Alerts are local notifications. Nothing is uploaded.

---

## 0.1.0

Headroom 0.1.0 is the first public release of a fast, free, native macOS disk space analyzer.

### 🚀 New feature

- Fast parallel scanning built on `getattrlistbulk(2)`
- Virtualized folder tree for very large directories
- Interactive treemap colored by category, age, or deletion safety
- Storage breakdown by category
- Largest-file and app-bundle discovery
- Safety explanations for recognized macOS and developer-tool locations
- Developer cleanup candidates including DerivedData, package caches, build output, and dependencies
- Recoverable Trash mode and explicit permanent-delete mode
- Fully local operation with no account, ads, subscription, or tracking

### ⚙️ Chore

- macOS 14 Sonoma or newer. Apple silicon or Intel (universal binary).
- The DMG is signed with a Developer ID certificate and notarized by Apple.

SHA-256 `Headroom-0.1.0.dmg`: `6361fea6d58dd6c0d07e03201a3eb9cd4c18272a917e481ae2b1469af592c097`
