# Headroom — App Store Connect Metadata

## New app record

| Field | Value |
|---|---|
| Platform | macOS |
| Name | Headroom |
| Subtitle | Disk space analyzer & cleanup |
| Primary language | English (U.S.) |
| Bundle ID | `dev.ryware.disktree` |
| SKU | `SKU_REDACTED` |
| User access | Full Access |

The bundle ID and SKU become difficult or impossible to change after record creation. The bundle ID `dev.ryware.disktree` is already registered under team `TEAM_ID_REDACTED` (created automatically during the first archive export), so it appears in the Bundle ID dropdown when creating the record.

## App information

| Field | Value |
|---|---|
| Subtitle | Disk space analyzer & cleanup |
| Primary category | Utilities |
| Secondary category | Developer Tools |
| Content rights | Does not contain, show, or access third-party content |
| Copyright | 2026 Ryware |
| Privacy policy URL | `https://github.com/Ryware/Headroom/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/Ryware/Headroom/issues` |
| Marketing URL | `https://github.com/Ryware/Headroom` |

## Naming rules (learned from the 0.1.0 rejection)

- The App Store name and subtitle must not contain **"Free"** (Guideline 2.3.7: a price reference) or **"Mac"** (Guideline 5.2.5: Apple trademark). Say both in the description instead.
- The app was renamed from DiskTree to Headroom because another "DiskTree" disk analyzer is on the store (Guideline 4.3(a) similarity). The bundle id `dev.ryware.disktree` stays.

## Version 1.0.0

### What’s New

DiskTree is now Headroom. First stable release. New: a duplicate finder that lists files existing more than once with identical content, ranked by reclaimable space, with one-click selection and keep-one-copy protection. The Dashboard shows duplicate space at a glance. Includes the menu bar monitor from 0.2 (free-space ring, 7-day trend, local alerts).

### Promotional text

See what is eating your disk, find duplicates and developer junk, and clean up safely. No subscription, no tracking, no cloud.

### Description

Headroom is a fast, native disk space analyzer and cleanup utility for macOS.

Choose a folder and Headroom turns its contents into a clear, interactive view: a responsive folder tree, a colorful treemap, storage by category, and the largest files and app bundles.

FIND DUPLICATES
Headroom finds files that exist more than once with identical content, compared byte for byte, and groups them by how much space one copy would give back. Keep the newest, the oldest, or pick by hand; Headroom always keeps one copy unless you say otherwise.

WATCH FREE SPACE FROM THE MENU BAR
A ring in the menu bar shows how much of your startup disk is free, with a 7-day trend and local alerts when space runs low or drops quickly.

BUILT FOR DEVELOPERS
Headroom recognizes dependencies, build output, package stores, virtual machines, caches and logs from Xcode, npm, pnpm, pip, Gradle, NuGet, Cargo and more.

DELETE WITH CONFIDENCE
Before removing anything, Headroom explains what a recognized item is and gives a safety verdict. Use recoverable Trash mode for everyday cleanup, or permanent deletion when you are certain.

PRIVACY BY DESIGN
• Scanning, hashing and categorization happen entirely on your Mac.
• No account, advertising, analytics or tracking.
• The App Store version accesses only folders you explicitly select.
• No file names, paths or usage information leave your Mac.

Headroom is free, with every feature included.

### Review notes

Formerly submitted as "DiskTree - Free Mac Analyzer" (rejected: 2.3.7, 5.2.5, 4.3(a)). Renamed to Headroom; "Free" and "Mac" removed from name and subtitle. Original code, open source at https://github.com/Ryware/Headroom (full commit history). The duplicate finder, menu bar monitor and safety knowledge base are unique to this app.

## Version 0.2.0

### What’s New

Headroom can now watch your startup disk from the menu bar: a free-space ring, a 7-day trend, and local alerts when space runs low or drops quickly. Sorting a large scan no longer freezes the window, and Open Headroom brings the window forward reliably. This App Store build still scans only folders you choose.

### Promotional text

Find the files, folders, dependencies, caches, and build output consuming your Mac’s storage—without subscriptions, tracking, or cloud uploads. Watch free space from the menu bar.

## Version 0.1.0

### Promotional text

Find the files, folders, dependencies, caches, and build output consuming your Mac’s storage—without subscriptions, tracking, or cloud uploads.

### Description

Headroom is a fast, native disk space analyzer and cleanup utility for macOS.

Choose a folder and Headroom turns its contents into a clear, interactive view. Browse a responsive folder tree, explore a colorful treemap, compare storage by category, and find the largest files and app bundles.

Headroom is especially useful for developers. It recognizes common dependencies, build output, package stores, virtual machines, caches, and logs from tools such as Xcode, npm, pnpm, pip, Gradle, NuGet, and Cargo.

Before removing anything, Headroom explains what a recognized item is and provides a safety verdict. Use recoverable Trash mode for everyday cleanup, or choose permanent deletion only when you are certain an item is disposable.

PRIVACY BY DESIGN

• Scanning and categorization happen entirely on your Mac.
• Headroom has no account, advertising, analytics, or tracking.
• The App Store version accesses only folders you explicitly select.
• No file names, paths, or usage information leave your Mac.

COMPLETELY FREE

Headroom has no subscription, in-app purchases, or paid upgrade.

Requires macOS 14 Sonoma or newer.

### Keywords

`disk,storage,cleanup,treemap,files,folders,space,analyzer,developer,cache`

### What’s New

Initial release of Headroom for macOS, including fast folder scanning, an interactive treemap, category analysis, largest-file discovery, safety guidance, and cleanup tools.

## Pricing and availability

- Price: Free
- Availability: All territories where the Mac App Store is available
- Pre-order: No
- In-app purchases: None

## App privacy

Select **No, we do not collect data from this app**.

Headroom performs all analysis locally, includes no third-party SDKs, and has no network entitlement. The privacy policy URL is required even though no data is collected.

## Export compliance

The app does not implement non-exempt encryption. `ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`.

## Age rating

Answer **No** or **None** for all content descriptors. Headroom contains no user-generated content, web browsing, gambling, simulated gambling, violence, sexual content, profanity, drugs, contests, or advertising. App Store Connect should assign the lowest applicable age rating.

## App Review notes

Headroom is a local disk space analyzer. On first use, select **Scan Folder…** and choose any folder containing files and subfolders. The app uses the macOS system folder picker and App Sandbox user-selected read/write access.

Suggested review flow:

1. Choose a folder with nested files.
2. Wait for the scan to complete.
3. Review Dashboard, Folder Tree, Treemap, By Category, and Largest Files.
4. Open Cleanup to see candidates inside the selected folder.
5. Select an expendable test item and use Trash mode to verify deletion.

No sign-in, server, special account, demo credentials, hardware, or network connection is required. Headroom does not attempt to scan outside the folder selected by the reviewer.

## Submission assets

- App icon: `Assets/AppIcon-1024.png`
- Mac screenshots: `AppStore/Screenshots/` at 1440 × 900 pixels
- Version: `0.2.0`
- Build: `2`
