## DiskTree 0.2.0 — watch your disk from the menu bar

Still 100% free. No account, no tracking, every feature unlocked.

### 🚀 New feature

- **Menu bar monitor.** A ring shows how much of the startup disk is free, turning amber and then red as space runs low. Optionally show the free space as text beside the ring.
- **Popover** with free, used, and total space, a Healthy / Getting low / Low status, and a 7-day free-space chart.
- **Reclaimable now.** One click cleans safe caches, logs, and build output. Only items rated Safe are included, and they go to the Trash, so you can put them back.
- **Alerts** for low free space (default below 10 GB) and fast drops (default 5 GB within an hour). Both thresholds are adjustable. Alerts are local notifications. Tap one to open DiskTree.
- **Dashboard trend** with the 7-day free-space history and the change over the last 24 hours.
- **Settings** (⌘,): menu bar on or off, free-space text, keep running when the window is closed, show in the Dock, open at login, alert thresholds, and Trash or permanent delete.

### 🔥 Bug fix

- Sorting by Size, Name, Files, or Modified no longer freezes the app on very large scans. Folders are sorted only when they are displayed.
- **Open DiskTree** from the menu bar, and tapping an alert, brings the window forward even after it was closed or when the app is running without a Dock icon.

### ⚙️ Chore

- macOS 14 Sonoma or newer. Apple silicon or Intel (universal binary).
- Download `DiskTree-0.2.0.dmg`, open it, and drag DiskTree to Applications.

### 🔒 Privacy

Free-space history (at most 7 days) stays on your Mac in Application Support. Nothing is uploaded.

The Mac App Store build is sandboxed and only scans folders you select. The menu bar monitor, alerts, and dashboard trend are in both builds. One-click cleanup of known caches is in the direct-download app.
