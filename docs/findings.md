# Chet codebase findings

Date: 2026-11-03

---

## Architecture

Chet splits into two Swift targets:

- `ChetCore/` - a Swift package containing all scanning, safety, and cleaning logic, the Metal shaders, and the test suite. No SwiftUI. Fully testable in isolation.
- `Chet/` - a SwiftUI app that holds the views and `ScanModel`. It has no domain logic of its own; it wires the `ChetCore` types to the UI.

`ScanModel` is `@MainActor @Observable` and acts as the single coordinator: it owns the scan task, the category list, selection state, and the clean flow. Everything below it in `ChetCore` is a value type (`struct`), marked `Sendable`, and can run concurrently. There are no third-party dependencies. The stack is Metal, CryptoKit, ImageIO, CoreGraphics, AppKit, Foundation, and Synchronization (all Apple). Swift 6.2 strict concurrency is enabled throughout.

---

## Scanning subsystems

Each subsystem is an independent struct that takes a `SafetyPolicy` and returns results. `ScanSession.run()` (in `ChetCore`) drives the steps one after another at background IO priority, emitting `ScanEvent`s into an `AsyncStream` that `ScanModel` consumes. Rule scans run inside the step in a 4-wide task group; every post-index step (large files, duplicates, photos, videos) is fed from `index.candidates` so the home folder is walked once, metadata only. `ScanModel.scan()` just starts the session task and applies events.

| Subsystem | File | Approach |
|---|---|---|
| Rule scanner | `RuleScanner.swift` | Data-driven `Rule.catalog`; each rule describes roots, risk, delete mode, and filters. Scans all rules in parallel and yields results as an `AsyncStream`. |
| Duplicate finder | `DuplicateFinder.swift` | Bucket by size, then edge hash (first+last 16 KB SHA-256), then full hash (SHA-256 or GPU), then byte-for-byte confirmation. APFS clones detected by reclaimable size. |
| Large files | `LargeFiles.swift` | Files over 500 MB, or over 50 MB and untouched for a year. Uses `FileWalker` or accepts pre-walked entries. |
| Leftovers | `Leftovers.swift` | Entries in `Library/Application Support`, `Preferences`, `Containers`, `Group Containers`, and `Saved Application State` whose reverse-DNS prefix does not match any installed app vendor. |
| Similar photos | `SimilarPhotos.swift` | dCT-based perceptual hash plus Laplacian blur score, both computed on the GPU. Pairs with Hamming distance <= threshold are clustered; blurry images are a separate category. |
| Similar videos | `SimilarVideos.swift` | Samples N frames per video, hashes each frame on the GPU, compares all pairs for overlap. |
| Snapshots | `Snapshots.swift` | Lists and deletes Time Machine local snapshots via `tmutil`. |
| File index | `FileIndex.swift` | Single-pass `getattrlistbulk` walk that produces a candidate list (files >= 1 MB or media), a folder size tree, and a list of `CACHEDIR.TAG` folders. Feeds the disk map and the newer scan paths. |

---

## Safety model

Every path goes through `SafetyPolicy.isDeletable(_:)` at scan time and again right before deletion. The same check runs twice because files can change between scan and clean.

`SafetyPolicy` denies deletion if the path is: outside the user's home folder (volume trash excepted), a container root (`Library`, `Library/Caches`, `Desktop`, etc.), inside `Library/Keychains`, `Library/Messages`, `Library/Mail`, or `Library/Mobile Documents` (iCloud Drive), inside a `.git` folder, inside an app bundle (`.app`), inside a Photos library (`.photoslibrary`), a symlink, or on a different filesystem than its parent.

`FileStamp` captures inode, size, and modification time at scan time. Before deletion, the stamp is re-read and compared. If any field differs, the file is skipped with outcome `.skipped(.changed)`. If the owner app (stored in `ScanItem.ownerBundleID`) is currently running, deletion is also skipped.

Every clean action is written to `~/Library/Logs/chet/clean.log` as JSON Lines with time, path, byte count, delete mode, and outcome.

---

## GPU (Metal) integration

Metal accelerates four operations:

1. **Content hashing** (`block_hash` kernel): 128-bit non-cryptographic hash in 64 KB blocks. Used by `DuplicateFinder` as an optional replacement for SHA-256. Falls back to SHA-256 when `GPUContext.shared` is nil.
2. **Photo features** (`photo_features` kernel): perceptual hash (dCT over 32x32 grayscale blocks) and Laplacian blur score in one pass over a batch of 256x256 thumbnails.
3. **Pair matching** (`hamming_pairs` kernel): all-pairs Hamming distance on hash arrays, dispatched in 2048x2048 tiles to keep each command buffer short.
4. **Disk map rendering**: `DiskMapView` uses Metal for the squarified treemap.

Shaders are plain `.metal` text files stored as bundle resources and compiled at runtime via `MTLDevice.makeLibrary(source:)`. This is a workaround because `swift build` does not compile `.metal` files. Each kernel has a CPU reference implementation; tests verify that GPU and CPU produce identical results for the same input.

`GPUContext` tracks GPU time per command buffer and exposes `lastGPUSeconds` / `maxGPUSeconds`. Tests and the scan benchmark use these to catch regressions.

---

## File walking

Two walkers exist:

**`FileWalker`** uses `FileManager.enumerator` with `.skipsPackageDescendants`. It skips symlinks, cross-volume files, and dataless (iCloud placeholder) files. It calls `SafetyPolicy.isDeletable` on each file before yielding it. It deduplicates hard links by inode when counting total size. Most existing scanners use this walker.

**`FileIndexBuilder`** uses `getattrlistbulk` with `FSOPT_PACK_INVAL_ATTRS`. It reads all attributes for a full directory in one syscall (inspired by ncdu). In a single pass it produces: the candidate list (files >= 1 MB or known media extensions), a folder size tree limited to `maxDepth` levels, and a list of folders that contain a valid `CACHEDIR.TAG`. It tracks scan progress with lock-free atomics (`ScanProgress`).

Both walkers skip dataless files and deduplicate hard links by inode.

---

## Design decisions worth noting

**Rules as data.** `Rule.catalog` is a static array of structs. Adding a new junk category means adding one `Rule(...)` call with its roots, risk level, delete mode, and filters. No subclassing, no protocol conformance, no new files.

**Safety policy as a value.** `SafetyPolicy` is a struct, not a singleton. Every scanner instantiates or receives one. Tests can pass a policy with a custom home URL to isolate temporary directories.

**APFS clone detection.** `DuplicateFinder` skips duplicates where `reclaimableBytes < size / 2`. On APFS, a file copied with `cp --reflink` shares blocks with the original; deleting the copy frees almost nothing. The check avoids reporting fake savings.

**Uncached reads.** `UncachedRead.swift` wraps `fcntl(F_NOCACHE)` so reads during hashing bypass the OS page cache. Without this, hashing large files would evict useful cached data.

**`ScanSession` step shape.** The scan runs as one utility-priority task: rules in a 4-wide task group, then a single `FileIndexBuilder` pass over the user roots, then the remaining steps sequentially (index → large files → duplicates → leftovers → photos → videos → snapshots). Each step is cancelled by checking `Task.isCancelled` between steps. Disk IO is throttled process-wide with `setiopolicy_np(IOPOL_THROTTLE)` for the duration of the run.

---

## Test coverage

23 test files under `ChetCore/Tests/ChetCoreTests/`. Coverage includes:

- Every scanner (rule, duplicate, large files, leftovers, photos, videos, snapshots)
- `SafetyPolicy` with exhaustive deny-list cases
- `FileWalker` and `FileIndexBuilder` (using `TempDir` for a real filesystem sandbox)
- GPU/CPU parity for hashing, photo features, and pair matching
- `AuditLog` round-trip
- `Treemap` layout geometry
- `DisplayName` formatting
- One smoke test that runs a full scan on real user data paths (skipped if FDA is missing)

`TempDir` creates an isolated temporary directory and deletes it in `deinit`. `PhotoFixtures` and `VideoFixtures` generate test media in-process so the tests have no external data dependencies.

---

## Open observations

**`FileIndex` integration is complete.** `ScanSession.run()` builds the index once and feeds `index.candidates` into `LargeFileScanner.select(from:)`, `DuplicateFinder.find(entries:)`, `SimilarPhotos.scan(entries:)`, and `SimilarVideos.scan(entries:)`. `index.trees` goes to the disk map via `.folderTrees` and `taggedCaches` becomes its own category. The old `LargeFileScanner.scan(_ roots:)` entry point is still used by tests.

**`FolderTree` survives only as a `DiskMapView` fallback.** When `model.folderTrees` is empty (disk map opened before/during a scan, or outside the scan flow), `DiskMapView.build()` runs a full `FolderTree.build()` walk of the home folder. Once a scan has run, the map uses the `FileIndex.trees` snapshot instead. The fallback duplicates the index build and could be replaced with a spinner + "run a scan" hint, but the current behavior is harmless and offline-friendly.

**Sequential hashing in `DuplicateFinder` (measured, fine).** The full-hash and byte-for-byte stages run sequentially across all duplicate candidates. Measured 2026-11-03 with `mise run bench`: GPU 2,076 MB/s, SHA-256 1,068 MB/s — well under NVMe bandwidth for typical duplicate sets, so the `// ponytail:` parallelize-per-bucket note stays unwritten. Revisit only if real duplicate scans measure slow.

**Similar photos/videos decoding notes.** `SimilarPhotos` decodes thumbnails sequentially (`// ponytail:` at `SimilarPhotos.swift:55`); `SimilarVideos` does an O(n²) CPU pair check (`SimilarVideos.swift:62`). Both flagged as fine-until-measured.

**No root-level scanning.** `/Library/Caches`, system logs, root-owned package caches, and Docker/OrbStack images are out of scope by design. Adding any of these would require a privileged helper process. `DEVELOPMENT.md` and the user guide are explicit about this boundary.
