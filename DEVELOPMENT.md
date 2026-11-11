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
| `mise run build` | Debug build into `.build/xc`: `chet-helper` first, then the app |
| `mise run dev` | Build the debug app and launch it |
| `mise run test` | Run the ChetCore tests. Filter with `mise run test -- --filter Cleaner` |
| `mise run check` | Tests, debug build, and a check that the binary is arm64 only |
| `mise run release` | Release build, arm64 check, and `dist/chet.zip` |
| `mise run dmg` | The release build in `dist/chet.dmg`, with an `Applications` symlink |
| `mise run publish` | Build, tag `v<version>`, push, and upload `dist/chet.dmg` and `dist/chet.zip` |
| `mise run install-chet` | Install the latest GitHub release into `/Applications` |
| `mise run bench` | Compare GPU and SHA-256 hashing speed (writes 1 GB of temp files) |
| `mise run fmt` / `mise run lint` | Format Swift code, or only check the format |
| `mise run layout` | Check the persistent chrome against the registry in `docs/DESIGN.md` |
| `mise run xcode` | Open the generated project in Xcode |
| `mise run log` | Follow the clean audit log |
| `mise run devlog` | Follow the dev activity log (Debug builds only) |
| `mise run clean` | Remove build output, the generated project, and `dist/` |

The Xcode project is generated from `project.yml` by XcodeGen and is not committed.
`mise run gen` regenerates it; the build tasks do this for you.

`mise run build` and `mise run release` each increment `CFBundleVersion` in `Chet/Info.plist` before their build, so every built bundle carries a new number. `mise run dev` inherits the bump through its `build` dependency, and `mise run dmg` inherits it through `release`. No other task writes that key, and the bumped plist is committed with the change that produced it.

The app ships a privileged helper, `chet-helper`, as a second target. `mise run build` and
`mise run release` build it before the app, and the app's post-build script copies it to
`Contents/MacOS/chet-helper` with its launchd plist in `Contents/Library/LaunchDaemons` and
signs it, so Xcode's final app signature covers both. It is off until the user registers it in
Settings; nothing in the build registers or launches it.

## Dev activity log

`mise run dev` builds the Debug app and launches it with `CHET_VERBOSE=1`, which turns on the
verbose activity log. A launch without the variable, with `0` or `yes`, or any Release build
has no writer and creates no file.

The file is `~/Library/Logs/chet/application-debug.log`. The writer keeps two names at most,
that file and `application-debug.1.log`, at 1 MiB each, and prunes older names at launch.

Read it with `mise run devlog`, which follows the file by name through rotation and names the
missing directory, the missing file, an unreadable file, an unwritable directory, an empty
file, and more than one running instance. Plain
`tail -F ~/Library/Logs/chet/application-debug.log` works too.

Each line is one JSON object, keys sorted:

```
{"category":"launch","fields":[{"key":"sawCrash","value":{"status":0}},{"key":"rotationsKept","value":{"count":1}}],"level":"info","message":"launch.started","session":"<uuid>","time":"2026-11-11T09:00:00Z"}
```

The keys are `time`, `session`, `level`, `category`, `message`, and `fields`. `level` is one of
`debug`, `info`, `warn`, `error`. `fields` holds typed extras such as counts, byte totals, and
relative paths.

### What it never records

- Absolute paths.
- File names longer than 128 bytes.
- Command-line arguments and environment values.
- Tweak payloads, raw bundle ids, and raw tweak ids.

### Why the file can look empty

- A Release build, or a Debug launch without `CHET_VERBOSE=1`, has no writer. A file from an
  earlier session can still be there.
- A launch with the writer on can leave a zero-byte file until the first flush.
- If the writer cannot open the file, it disables itself instead of failing the app and posts
  one Console notice in the `devlog` category.

### Why this is not crash.txt

The crash writer appends to `crash.txt` from a signal handler and rotates the previous report
to `crash-<ms>.txt` at the next launch, keeping five. The activity log never reads or writes
those files, and nothing in it runs from a signal handler. Read `crash.txt` when the app died
by a signal, and the activity log when the app survived and misbehaved.

## Project layout

```
Chet/        SwiftUI app (views and the scan model)
ChetHelper/  Privileged helper daemon: the XPC listener, one bounded removal session
ChetCore/    Swift package with all scanning, safety and cleaning logic, Metal shaders, and tests
project.yml  XcodeGen spec for the app and the helper
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

A root-owned item takes one more step. `Cleaner` and `AppUninstaller` hand it to an injected
`privileged` closure instead of removing it themselves. The app builds that closure from
`PrivilegedClient`, and the daemon applies `HelperGuard.refusal` before `removeItem`. With the
closure absent, a root-owned item is a policy skip, so no engine can remove one on its own.
The removal is permanent, never the Trash. The daemon removes children of the six `/Library`
trees and one direct `.app` bundle in `/Applications`; it never removes `chet.app`.

Rules for new code:

- An engine's identification code never moves into a shared primitive.
- A shared primitive never decides what is junk. It measures, walks, hashes, moves files to
  the Trash, or answers a path question.
- `SafetyPolicy` is the single answer to "may this path be removed at all": system trees,
  protected home folders, excluded folders, app bundles, Photos libraries.
- A privileged removal is always a request through `ChetHelperProtocol`. No engine gains a
  second root path, and `HelperGuard` is the only place that decides what root may touch.

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
`dist/chet.zip`. `mise run dmg` runs the same build and writes `dist/chet.dmg`, a compressed
read-only image holding `chet.app` and an `Applications` symlink; the mount carries no custom
volume icon.

Releases are built on this laptop, not in CI. `mise run publish` runs `mise run dmg`, with
`--clean` removing the build output first, stops when the build number did not change, commits
`Chet/Info.plist`, tags `v<version>` from `CFBundleShortVersionString`, pushes the branch and
the annotated tag, and runs `gh release create` with `dist/chet.dmg` and `dist/chet.zip`.
`--dry-run` prints the version, the tag, the artifacts, and every command instead of changing
anything. `--skip-build` reuses the files in `dist/` and skips the build and the plist commit.

`mise run install-chet` reads the latest GitHub release, so a release must be published before
it can install one. That task is for a checkout: the installer is a standalone script, and end
users need bash, curl, and the macOS tools, not mise.

While the repository is private, both the script download and the release asset need a token:
`curl -H "Authorization: Bearer $GITHUB_TOKEN" ...` for the raw file, and
`GITHUB_TOKEN=... bash scripts/install-chet.sh` for the installer. Without it the API answers
404 and the installer reports no published release.

The app is ad-hoc signed and not notarized, and the image is unsigned for the same reason. The
helper needs a Team ID: `SMAppService` records an ad-hoc daemon and then refuses to start it,
so Settings reports the build as unsupported and disables the administrator switch. The
quarantine step for another Mac is in the
[user guide](docs/USER-GUIDE.md#install-on-another-mac).

## Boundaries

App thinning, Docker images, and tweaks outside the catalog are out of scope. Root-owned data
is in scope only through the registered helper and only under `/Library/Caches`,
`/Library/Logs`, and the app remnant roots in `HelperGuard`, plus one direct `.app` bundle in
`/Applications`; removal is permanent, never the Trash. The reasons for the rest are in the
[user guide](docs/USER-GUIDE.md#not-covered).
