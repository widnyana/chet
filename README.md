# Mackit

Mackit finds and removes junk on Apple Silicon Macs: caches, logs, developer build data, old installers, duplicate files, similar photos and videos, leftovers of deleted apps, and more. It removes only data that apps can rebuild, or files you confirm one by one.

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
| `mise run test` | Run the MackitCore tests. Filter with `mise run test -- --filter Cleaner` |
| `mise run check` | Tests, debug build, and a check that the binary is arm64 only |
| `mise run release` | Release build, arm64 check, and `dist/Mackit.zip` |
| `mise run bench` | Compare GPU and SHA-256 hashing speed (writes 1 GB of temp files) |
| `mise run fmt` / `mise run lint` | Format Swift code, or only check the format |
| `mise run xcode` | Open the generated project in Xcode |
| `mise run log` | Follow the clean audit log |
| `mise run clean` | Remove build output, the generated project and `dist/` |

The Xcode project is generated from `project.yml` by XcodeGen and is not committed. `mise run gen` regenerates it; the build tasks do this for you.

## Full Disk Access

macOS hides caches, Mail downloads and browser data from apps without Full Disk Access. On first launch Mackit shows a screen with a button that opens **System Settings > Privacy & Security > Full Disk Access**. Turn on Mackit there and switch back; the screen closes by itself. You can also continue without it. Categories that miss data then show a lock icon.

## What Mackit cleans

"Safe" items are selected after a scan. "Review" items are never selected for you.

| Category | What | Risk | Removal |
|---|---|---|---|
| Trash | Files already in the Trash | Safe | Deleted |
| User caches | `~/Library/Caches`, one item per app | Safe | Deleted |
| Logs and crash reports | `~/Library/Logs` | Safe | Deleted |
| Xcode build data | DerivedData, simulator caches, old device support files | Safe | Deleted |
| Package manager caches | Homebrew, npm, Yarn, pnpm, pip, uv, Cargo, Go, Gradle, SwiftPM, CocoaPods | Safe | Deleted |
| Browser caches | Safari, Chrome, Brave, Edge, Firefox, Arc (cache only, never history or profiles) | Safe | Deleted |
| Mail downloads | Attachments Mail saved to open them | Safe | Deleted |
| Xcode archives | `~/Library/Developer/Xcode/Archives` | Review | Moved to Trash |
| Old installers | `.dmg`, `.pkg`, `.xip`, `.iso` in Downloads, older than 30 days | Review | Moved to Trash |
| iOS device backups | Finder backups of iPhone and iPad | Review | Moved to Trash |
| Duplicates | Files with the same bytes (1 MB and larger) | Review | Moved to Trash |
| Large and old files | Over 500 MB, or over 50 MB and untouched for a year | Review | Moved to Trash |
| App leftovers | Library data of apps that are no longer installed | Review | Moved to Trash |
| Similar photos | Resized or recompressed copies of the same photo | Review | Moved to Trash |
| Blurry photos | Photos with very little sharp detail | Review | Moved to Trash |
| Similar videos | Re-encoded copies of the same video | Review | Moved to Trash |
| Time Machine local snapshots | Snapshots on the startup disk | Review | Deleted with `tmutil` |

The **Disk map** shows which folders in your home folder take the most space. Click a folder to look inside.

## How Mackit protects your data

- A single safety check runs for every item, at scan time and again right before removal. It refuses system folders, app bundles, iCloud Drive, Keychains, Mail and Messages data, Photos libraries, `.git` folders, symlinks and other volumes.
- Before removal Mackit compares each file with what the scan saw (inode, size, modification time). If anything changed, the file is left alone.
- Caches of a running app are skipped. The summary tells you which app to quit.
- For duplicates and similar media, one copy is always kept. Exact duplicates are compared byte for byte before they are shown.
- Every action is written to `~/Library/Logs/Mackit/clean.log`, one JSON line per item.

## Metal

Mackit uses the GPU through Metal for the heavy work: perceptual hashes and blur scores for photos, frame hashes for videos, pair matching, an optional GPU hash for exact duplicates, and drawing the disk map. Every GPU kernel has a CPU version, and the tests check that both give the same result.

## Running on another Mac

The app is ad-hoc signed and not notarized. Copied to another Mac, macOS blocks it at first launch. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Mackit.app
```

## Project layout

```
Mackit/        SwiftUI app (views and the scan model)
MackitCore/    Swift package with all scanning, safety and cleaning logic, Metal shaders, and tests
project.yml    XcodeGen spec for the app
mise.toml      Tool versions and development tasks
```

## Not covered

- Caches and logs owned by root (`/Library/Caches`, system logs). This needs a privileged helper.
- Removing app languages or thinning app binaries. It breaks code signatures.
- Docker or OrbStack images. Use `docker system prune`.
