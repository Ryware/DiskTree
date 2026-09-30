# Changelog

## 0.2.0 — September 30, 2026

DiskTree now watches your disk from the menu bar. Still 100% free, with every feature unlocked.

### New

- **Menu bar monitor** with a ring showing how much of the startup disk is free. It turns amber, then red, as space runs low. Optionally show the free space as text next to the ring.
- **Popover** with free / used / total space, a Healthy / Getting low / Low status, and a 7-day free-space chart.
- **Reclaimable now**: adds up safe caches, logs and build output and lets you clean them in one click. Only items rated Safe are included, and they go to the Trash, so it is recoverable.
- **Alerts** (local notifications): low free space (default below 10 GB) and fast drops (default 5 GB within an hour). Both thresholds are adjustable. Tapping an alert opens DiskTree.
- **Dashboard trend card** with the 7-day free-space history and the change over the last 24 hours.
- **Settings** (⌘,):
  - Show DiskTree in the menu bar
  - Show free space next to the icon
  - Keep running when the window is closed
  - Show in the Dock (turn off for a menu-bar-only app)
  - Open at login (starts quietly in the menu bar)
  - Alert toggles and thresholds
  - Deleting mode (Trash or permanent)
- Popover shortcuts: **Open DiskTree**, **Scan Home**, Settings and Quit.

### Fixed

- Sorting by Size, Name, Files or Modified no longer freezes the app on very large scans. Folders are now sorted only when they are displayed.
- **Open DiskTree** from the menu bar (and tapping an alert) reliably brings the window forward, including after the window was closed or when the app is running without a Dock icon.

### Also in this release

- Version 0.2.0 (build 2). Existing users see the What's New page of the intro tour.
- Direct-download builds are universal (Apple silicon and Intel), signed with a Developer ID certificate and notarized by Apple.
- The Mac App Store build stays sandboxed: it scans and cleans only folders you choose. Home, Startup Disk, and one-click cleanup of known caches stay in the direct-download app.
- Unit tests cover the scanner, deleter, safety rules, cleanup finder, and disk monitor. GitHub Actions runs them on every push.

### Privacy

Free-space history (at most 7 days) is stored only on your Mac in Application Support. Alerts are local notifications. Nothing is uploaded.

---

## 0.1.0

DiskTree 0.1.0 is the first public release of a fast, free, native macOS disk space analyzer.

### Highlights

- Fast parallel scanning built on `getattrlistbulk(2)`
- Virtualized folder tree for very large directories
- Interactive treemap colored by category, age, or deletion safety
- Storage breakdown by category
- Largest-file and app-bundle discovery
- Safety explanations for recognized macOS and developer-tool locations
- Developer cleanup candidates including DerivedData, package caches, build output, and dependencies
- Recoverable Trash mode and explicit permanent-delete mode
- Fully local operation with no account, ads, subscription, or tracking

### Requirements

- macOS 14 Sonoma or newer
- Apple silicon or Intel Mac (universal binary)

The DMG is signed with a Developer ID certificate and notarized by Apple.

SHA-256 `DiskTree-0.1.0.dmg`: `6361fea6d58dd6c0d07e03201a3eb9cd4c18272a917e481ae2b1469af592c097`
