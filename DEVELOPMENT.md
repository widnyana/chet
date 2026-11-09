# Chet development

Chet is a SwiftUI app with a Swift package for scanning, safety, and cleaning. This file covers
the build, the project layout, the engines, and the tests. The product copy is in
[README.md](README.md). The user guide is [docs/USER-GUIDE.md](docs/USER-GUIDE.md). The design
direction is [docs/DESIGN.md](docs/DESIGN.md). Work notes for coding agents are in
[AGENTS.md](AGENTS.md).

## Requirements

- A Mac with Apple Silicon (M1 or newer). The app is built for arm64 only and does not run on
  Intel Macs.
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
| `mise run gen` | Generate `chet.xcodeproj` from `project.yml` |
| `mise run build` | Debug build into `.build/xc` |
| `mise run dev` | Build the debug app and launch it |
| `mise run test` | Run the ChetCore tests. Filter with `mise run test -- --filter Cleaner` |
| `mise run check` | Tests, debug build, and a check that the binary is arm64 only |
| `mise run release` | Release build, arm64 check, and `dist/chet.zip` |
| `mise run bench` | Compare GPU and SHA-256 hashing speed (writes 1 GB of temp files) |
| `mise run fmt` / `mise run lint` | Format Swift code, or only check the format |
| `mise run layout` | Check the persistent chrome against the registry in `docs/DESIGN.md` |
| `mise run xcode` | Open the generated project in Xcode |
| `mise run log` | Follow the clean audit log |
| `mise run clean` | Remove build output, the generated project, and `dist/` |

The Xcode project is generated from `project.yml` by XcodeGen and is not committed.
`mise run gen` regenerates it; the build tasks do this for you.

## Project layout

```
Chet/        SwiftUI app (views and the scan model)
ChetCore/    Swift package with all scanning, safety and cleaning logic, Metal shaders, and tests
project.yml  XcodeGen spec for the app
mise.toml    Tool versions and development tasks
```

## Engines

Chet removes things through three engines. They share filesystem primitives and nothing else:
identification and the removal decision belong to one engine each.

| Engine | Identification | Removal | Shared primitives |
|---|---|---|---|
| Disk cleaner | `RuleScanner`, `Rules`, `LargeFiles`, `Leftovers` | `Cleaner`, one item at a time, after re-checking the stamp and the policy | `FileWalker`, `FileIndex`, `SizeProbe`, `SafetyPolicy`, `AuditLog` |
| Application uninstaller | `AppUninstaller.components(for:)` and its match rules | `AppUninstaller.uninstall`, its own loop, the app bundle last | `SafetyPolicy.isProtectedPath`, `FileStamp`, the Trash |
| Duplicate finder | `DuplicateFinder`, `SimilarPhotos`, `SimilarVideos` | none; the engine picks the keeper, then the group becomes a Trash item that `Cleaner` executes | `GPUHasher`, `PerceptualHash`, `FileWalker` |

Tweaks follows the same shape. `TweakCatalog` identifies preferences, `TweakEngine` writes and
verifies one value, and the shared pieces are `Subprocess` and the append-only change record.

Rules for new code:

- An engine's identification code never moves into a shared primitive.
- A shared primitive never decides what is junk. It measures, walks, hashes, moves files to
  the Trash, or answers a path question.
- `SafetyPolicy` is the single answer to "may this path be removed at all": system trees,
  protected home folders, excluded folders, app bundles, Photos libraries.

## Metal

Chet uses the GPU through Metal for the heavy work: perceptual hashes and blur scores for
photos, frame hashes for videos, pair matching, an optional GPU hash for exact duplicates, and
drawing the disk map. Every GPU kernel has a CPU version, and the tests check that both give the
same result.

## Testing

- `mise run test` runs the ChetCore tests.
- `mise run check` runs the tests, a debug build, and the arm64-only check.
- `mise run bench` compares GPU and SHA-256 hashing speed. It writes 1 GB of temp files.
- UI work is checked at the 960 x 632 minimum window size. `mise run layout` checks the
  persistent chrome against the registry in `docs/DESIGN.md`.
- [AGENTS.md](AGENTS.md) covers driving the built app through accessibility selectors and the
  `DRY_RUN=1` rule for UI tests.

## Release

`mise run release` builds the app, checks that the binary is arm64 only, and writes
`dist/chet.zip`. The app is ad-hoc signed and not notarized. The quarantine step for another
Mac is in the [user guide](docs/USER-GUIDE.md#install-on-another-mac).

## Boundaries

Root-owned caches and logs, app thinning, Docker images, administrator-only removals, and
tweaks outside the catalog are out of scope. The reasons are in the
[user guide](docs/USER-GUIDE.md#not-covered).
