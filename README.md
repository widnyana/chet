# Chet

Chet finds and removes junk on Apple Silicon Macs: caches, logs, developer build data, old installers, duplicate files, similar photos and videos, leftovers of deleted apps, and more. It removes only data that apps can rebuild, or files you confirm one by one.

**Home** runs the junk scan. **Apps** in the sidebar removes an app together with the Library data that belongs to it.

## Requirements

- A Mac with Apple Silicon (M1 or newer). The app is built for arm64 only and does not run on Intel Macs.
- macOS 26 or newer.
- Xcode 26 or newer and [mise](https://mise.jdx.dev).

## Build and run

```sh
mise install     # installs the pinned xcodegen
mise run dev     # builds the debug app and launches it
```

Every development step is a mise task:

| Command | What it does |
|---|---|
| `mise run dev` | Build the debug app and launch it |
| `mise run test` | Run the ChetCore tests. Filter with `mise run test -- --filter Cleaner` |
| `mise run check` | Tests, debug build, and a check that the binary is arm64 only |
| `mise run release` | Release build, arm64 check, and `dist/chet.zip` |
| `mise run bench` | Compare GPU and SHA-256 hashing speed (writes 1 GB of temp files) |
| `mise run fmt` / `mise run lint` | Format Swift code, or only check the format |
| `mise run layout` | Check the persistent chrome against the registry in `docs/DESIGN.md` |
| `mise run xcode` | Open the generated project in Xcode |
| `mise run log` | Follow the clean audit log |
| `mise run clean` | Remove build output, the generated project and `dist/` |

The Xcode project is generated from `project.yml` by XcodeGen and is not committed. `mise run gen` regenerates it; the build tasks do this for you.

## Full Disk Access

macOS hides caches, Mail downloads and browser data from apps without Full Disk Access. On first launch Chet shows a screen with a button that opens **System Settings > Privacy & Security > Full Disk Access**. Turn on Chet there and switch back; the screen closes by itself. You can also continue without it. Categories that miss data then show a lock icon.

## What Chet cleans

"Safe" items are selected after a scan. "Review" items are never selected for you.

| Category | What | Group | Removal |
|---|---|---|---|
| Trash | Files already in the Trash | Safe to remove | Delete |
| App caches | `~/Library/Caches`, one item per app | Safe to remove | Delete |
| Logs | `~/Library/Logs` | Safe to remove | Delete |
| Xcode files | DerivedData, simulator caches, old device support files | Safe to remove | Delete |
| Developer caches | Homebrew, npm, Yarn, pnpm, pip, uv, Cargo, Go, Gradle, SwiftPM, CocoaPods | Safe to remove | Delete |
| Browser data | Safari, Chrome, Brave, Edge, Firefox, Arc (cache only, never history or profiles) | Safe to remove | Delete |
| Mail downloads | Attachments Mail saved to open them | Safe to remove | Delete |
| Xcode archives | `~/Library/Developer/Xcode/Archives` | Check first | Move to Trash |
| Old installers | `.dmg`, `.pkg`, `.xip`, `.iso` in Downloads, older than 30 days | Check first | Move to Trash |
| iPhone and iPad backups | Finder backups of iPhone and iPad | Check first | Move to Trash |
| Duplicate files | Files with the same bytes (1 MB and larger) | Check first | Move to Trash |
| Large files | Over 500 MB, or over 50 MB and untouched for a year | Check first | Move to Trash |
| Leftover app files | Library data of apps that are no longer installed | Check first | Move to Trash |
| Similar photos | Resized or recompressed copies of the same photo | Check first | Move to Trash |
| Blurry photos | Photos with very little sharp detail | Check first | Move to Trash |
| Similar videos | Re-encoded copies of the same video | Check first | Move to Trash |
| Time Machine snapshots | Snapshots on the startup disk | Check first | Delete with `tmutil` |

The **Storage** page shows which folders in your home folder take the most space. Click a folder to look inside.

The interface is a ledger: paper and ink, one accent, tabular numbers, and one command bar.
The design system and the screen specs live in `docs/DESIGN.md` and `docs/design/`.

## Uninstall apps

Pick **Apps** in the sidebar, search for an app, and select it. Chet reads the app
bundle, then looks in the user Library for data that names the app's bundle ID or its helpers:
Application Support, Preferences (including ByHost), Caches, Logs, Containers, Group
Containers, Saved Application State, Cookies, Application Scripts, Launch Agents and WebKit.

Each row says why it matched:

- **Belongs to this app**: the bundle ID or an embedded helper ID. Selected by default.
- **Probably belongs**: the folder is named after the app or the last part of its bundle ID.
  Never selected by default; review it first.
- **Shared with another app**: a group container, or data another installed app also claims.
  Cannot be selected.
- **Needs an administrator**: an entry under `/Library` or in a folder the user cannot write.
  Cannot be selected.
- **Protected by macOS**: system folders, Keychains, Mail, Messages and iCloud Drive. Never
  listed as removable.

The app is unchecked when it is open, needs an administrator, or cannot be written.
The **Move to Trash** button is disabled while the app or one of its helpers runs, and the core checks
again before the first move. Related files go first and the app bundle goes last, so a failed
move never hides the app itself. Everything goes to the Trash; nothing is deleted permanently.

## How Chet protects your data

- A single safety check runs for every item, at scan time and again right before removal. It refuses system folders, app bundles (the Apps page has its own explicit app-bundle allowlist), iCloud Drive, Keychains, Mail and Messages data, Photos libraries, `.git` folders, symlinks and other volumes.
- Before removal Chet compares each file with what the scan saw (inode, size, modification time). If anything changed, the file is left alone.
- Caches of a running app are skipped. The summary tells you which app to quit.
- For duplicates and similar media, one copy is always kept. Exact duplicates are compared byte for byte before they are shown.
- In Apps, only exact bundle-ID matches and embedded helper matches are selected for
  you. Name-only matches stay unchecked, shared group containers are unselectable, and
  administrator-only entries are shown read-only. Every row is checked again right before it
  moves.
- Every action is written to `~/Library/Logs/chet/clean.log`, one JSON line per item with its category, path, bytes, mode, and result.

## Metal

Chet uses the GPU through Metal for the heavy work: perceptual hashes and blur scores for photos, frame hashes for videos, pair matching, an optional GPU hash for exact duplicates, and drawing the disk map. Every GPU kernel has a CPU version, and the tests check that both give the same result.

## Running on another Mac

The app is ad-hoc signed and not notarized. Copied to another Mac, macOS blocks it at first launch. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/chet.app
```

## Project layout

```
Chet/        SwiftUI app (views and the scan model)
ChetCore/    Swift package with all scanning, safety and cleaning logic, Metal shaders, and tests
project.yml    XcodeGen spec for the app
mise.toml      Tool versions and development tasks
```

## Not covered

- Caches and logs owned by root (`/Library/Caches`, system logs). This needs a privileged helper.
- Removing app languages or thinning app binaries. It breaks code signatures.
- Docker or OrbStack images. Use `docker system prune`.
- Removing apps or files that need administrator rights. Apps shows those entries with a
  Needs admin status but does not move them; there is no privileged helper.
