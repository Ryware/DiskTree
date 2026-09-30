# DiskTree — App Store Connect Metadata

## New app record

| Field | Value |
|---|---|
| Platform | macOS |
| Name | DiskTree |
| Primary language | English (U.S.) |
| Bundle ID | `dev.ryware.disktree` |
| SKU | `SKU_REDACTED` |
| User access | Full Access |

The bundle ID and SKU become difficult or impossible to change after record creation. The bundle ID `dev.ryware.disktree` is already registered under team `TEAM_ID_REDACTED` (created automatically during the first archive export), so it appears in the Bundle ID dropdown when creating the record.

## App information

| Field | Value |
|---|---|
| Subtitle | Visual disk space analyzer |
| Primary category | Utilities |
| Secondary category | Developer Tools |
| Content rights | Does not contain, show, or access third-party content |
| Copyright | 2026 Ryware |
| Privacy policy URL | `https://github.com/Ryware/DiskTree/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/Ryware/DiskTree/issues` |
| Marketing URL | `https://github.com/Ryware/DiskTree` |

## Version 0.2.0

### What’s New

DiskTree can now watch your startup disk from the menu bar: a free-space ring, a 7-day trend, and local alerts when space runs low or drops quickly. Sorting a large scan no longer freezes the window, and Open DiskTree brings the window forward reliably. This App Store build still scans only folders you choose.

### Promotional text

Find the files, folders, dependencies, caches, and build output consuming your Mac’s storage—without subscriptions, tracking, or cloud uploads. Watch free space from the menu bar.

## Version 0.1.0

### Promotional text

Find the files, folders, dependencies, caches, and build output consuming your Mac’s storage—without subscriptions, tracking, or cloud uploads.

### Description

DiskTree is a fast, native disk space analyzer and cleanup utility for macOS.

Choose a folder and DiskTree turns its contents into a clear, interactive view. Browse a responsive folder tree, explore a colorful treemap, compare storage by category, and find the largest files and app bundles.

DiskTree is especially useful for developers. It recognizes common dependencies, build output, package stores, virtual machines, caches, and logs from tools such as Xcode, npm, pnpm, pip, Gradle, NuGet, and Cargo.

Before removing anything, DiskTree explains what a recognized item is and provides a safety verdict. Use recoverable Trash mode for everyday cleanup, or choose permanent deletion only when you are certain an item is disposable.

PRIVACY BY DESIGN

• Scanning and categorization happen entirely on your Mac.
• DiskTree has no account, advertising, analytics, or tracking.
• The App Store version accesses only folders you explicitly select.
• No file names, paths, or usage information leave your Mac.

COMPLETELY FREE

DiskTree has no subscription, in-app purchases, or paid upgrade.

Requires macOS 14 Sonoma or newer.

### Keywords

`disk,storage,cleanup,treemap,files,folders,space,analyzer,developer,cache`

### What’s New

Initial release of DiskTree for macOS, including fast folder scanning, an interactive treemap, category analysis, largest-file discovery, safety guidance, and cleanup tools.

## Pricing and availability

- Price: Free
- Availability: All territories where the Mac App Store is available
- Pre-order: No
- In-app purchases: None

## App privacy

Select **No, we do not collect data from this app**.

DiskTree performs all analysis locally, includes no third-party SDKs, and has no network entitlement. The privacy policy URL is required even though no data is collected.

## Export compliance

The app does not implement non-exempt encryption. `ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`.

## Age rating

Answer **No** or **None** for all content descriptors. DiskTree contains no user-generated content, web browsing, gambling, simulated gambling, violence, sexual content, profanity, drugs, contests, or advertising. App Store Connect should assign the lowest applicable age rating.

## App Review notes

DiskTree is a local disk space analyzer. On first use, select **Scan Folder…** and choose any folder containing files and subfolders. The app uses the macOS system folder picker and App Sandbox user-selected read/write access.

Suggested review flow:

1. Choose a folder with nested files.
2. Wait for the scan to complete.
3. Review Dashboard, Folder Tree, Treemap, By Category, and Largest Files.
4. Open Cleanup to see candidates inside the selected folder.
5. Select an expendable test item and use Trash mode to verify deletion.

No sign-in, server, special account, demo credentials, hardware, or network connection is required. DiskTree does not attempt to scan outside the folder selected by the reviewer.

## Submission assets

- App icon: `Assets/AppIcon-1024.png`
- Mac screenshots: `AppStore/Screenshots/` at 1440 × 900 pixels
- Version: `0.2.0`
- Build: `2`
