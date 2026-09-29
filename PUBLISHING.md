# DiskTree 0.1.0 — Publishing Kit

## Positioning

**Product name:** DiskTree  
**Category:** macOS Utilities / Disk Space Analyzer  
**Price:** Free  
**Primary promise:** See what is using your Mac's disk and reclaim space safely.

DiskTree is for Mac users and developers who want the speed and visual clarity of a modern disk analyzer without a subscription, account, ads, or data collection.

## Short descriptions

### Tagline

See what is eating your disk. Reclaim the space safely.

### One-line description

A fast, free, privacy-friendly macOS disk space analyzer with an interactive treemap, safety guidance, and developer-aware cleanup.

### GitHub repository description

Free native macOS disk analyzer with a folder tree, treemap, file categories, safety guidance, and fast cleanup.

### Social post

Meet DiskTree: a free native disk space analyzer for macOS. Scan huge folders quickly, explore an interactive treemap, find giant files and developer caches, and understand what is safe to remove. No subscription, ads, account, or tracking.

## Full product description

DiskTree is a fast, native disk space analyzer and cleanup utility for macOS 14 and newer.

Scan your home folder, startup disk, or any directory and immediately see where the space went. Browse a responsive folder tree, explore a colorful interactive treemap, compare storage by category, and find the largest files and app bundles.

DiskTree is especially useful for developers. It recognizes common build output, package stores, dependency folders, virtual machines, caches, and logs from Xcode, npm, pnpm, pip, Gradle, NuGet, Cargo, and other tools.

Before removing anything, DiskTree explains what the item is and provides a safety verdict. Use recoverable Trash mode for everyday cleanup, or opt into permanent parallel deletion when you explicitly need it.

Everything runs locally on your Mac. DiskTree is free and includes no subscription, ads, account system, analytics, or in-app purchases.

## Suggested release title

DiskTree 0.1.0 — Free native disk analyzer for macOS

## GitHub release body

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
- Apple silicon or Intel Mac

### Install

Download `DiskTree-0.1.0.dmg`, open it, and drag DiskTree to Applications.

DiskTree may request Full Disk Access only when you choose to scan protected locations such as Mail, Messages, or Safari data.

## Discovery metadata

Suggested topics:

`macos`, `swift`, `swiftui`, `disk-usage`, `disk-space`, `disk-cleaner`, `storage-analyzer`, `treemap`, `developer-tools`, `free-mac-app`

Natural search phrases to use in launch posts and landing pages:

- free disk space analyzer for Mac
- macOS storage visualizer
- find large files on Mac
- Mac disk cleanup utility
- treemap disk usage for macOS
- clean Xcode DerivedData and developer caches
- free alternative to subscription disk cleaners

Avoid keyword stuffing; use one or two phrases per paragraph and lead with the user benefit.

## Screenshot order

1. Dashboard — establishes trust and gives a complete overview.
2. Treemap — strongest visual and clearest differentiator.
3. Folder Tree — demonstrates depth and professional utility.
4. Categories — shows explainable storage breakdown.
5. Welcome — communicates polish and ease of use.

The prepared 1920-pixel-wide images are in `Screenshots/`.

## Publication checklist

- [x] Xcode build succeeds without errors.
- [x] Release-mode app build script is available.
- [x] README includes benefit-led copy, install steps, privacy, safety, performance, and screenshots.
- [x] Screenshot set is optimized for web publication.
- [x] License the public source under the MIT License.
- [ ] Create a Developer ID Application certificate for team `W9J3HSY24R`.
- [ ] Store the `DiskTree` notarization profile with `notarytool`.
- [ ] Run `./release.sh` and verify the notarized DMG.
- [x] Create the public `Ryware/DiskTree` repository.
- [x] Configure GitHub Actions release-build verification.
- [x] Create the draft GitHub release for `v0.1.0`.
- [ ] Upload `dist/DiskTree-0.1.0.dmg` with the release body above.
- [ ] Publish a SHA-256 checksum.
- [ ] Test the downloaded DMG on a Mac that did not build the app.
