# Chet user guide

Chet scans a Mac for files that can be removed and shows the result in one ledger. Nothing is
removed until you confirm it. This guide covers permissions, the categories, the limits,
Tweaks, Apps, and the logs.

## First launch

macOS hides caches, Mail downloads, and browser data from apps without Full Disk Access. On
first launch Chet shows a screen with a button that opens **System Settings > Privacy &
Security > Full Disk Access**.

1. Press **Open System Settings**.
2. Turn on Chet in the Full Disk Access list.
3. Switch back to Chet. The screen closes by itself when the system allows the probe file to
   be read.

macOS can keep a stale denial for a process that is already running. If the screen stays after
the grant, quit Chet and launch it again. A rebuild changes the signature, so a fresh build can
land on the permission screen again.

You can also press **Continue with limited results**. Chet is then fully usable, but protected
folders stay hidden:

- The top strip says `Limited access. Some folders are hidden.` with **Open Settings** and
  **Hide until the next launch**.
- A category whose scan hit a denied path carries a lock icon. Its tooltip says some folders
  need Full Disk Access.
- Home can say `Some folders could not be read. Results may be incomplete.`
- Skipping lasts for the session only. The screen returns on the next launch.

Nothing is removed automatically, with or without access. Review categories stay review, and
every removal still needs a selection and a confirmation. Tweaks is unaffected: preferences
are user-level and need no Full Disk Access.

## Scan

Home has three states:

- **Never scanned**: the disk capacity bar and a **Scan** button.
- **Scanning**: the step list, a linear progress bar, **Pause**, and **Resume**.
- **Finished**: the Safe to remove and Check first ledgers, the total space, and the command
  bar.

Start a scan from the toolbar, from **Scan** on Home, or with Command-R. The toolbar control
stays available on every destination except Apps and Tweaks.

The status strip appears for limited access, or for four seconds after a scan finishes.

### Partial scans

**Scope…** on the command bar opens the scope sheet. Turn off the categories you do not
want, add folders with **Choose…**, and start the scan. Chet reads only what you picked.

- No category selected means every category. No folder means your home folders, without
  Library.
- The scope narrows what Chet reads. Every protection, the excluded folders list, and the
  dry-run gate still apply.
- A folder outside your home needs **Other disks** in Settings.
- A partial result says so on Home: `Partial scan: 4 categories`. **Scan everything** puts
  the scope back to the whole Mac.
- **Remember this scope** keeps the selection for the next launch. It is off by default.

The scope belongs to one scan. Settings holds the permanent opt-outs; the scope sheet holds
the scan you are about to start.

## Review and remove

Safe to remove rows are selected after a scan. Check first rows are never selected for you.

1. Open a category from the sidebar or from a ledger row on Home.
2. Select the items to remove. Command-A selects all, Command-Shift-A selects none, and
   Command-Option-I inverts the selection.
3. Press **Remove selected**.
4. Read the confirmation and confirm.

The clean sheet then shows progress and ends with a summary. It cannot be dismissed while
cleaning. The summary lists what moved, what was skipped, and the space recovered.

Every cleanup is written to `~/Library/Logs/chet/clean.log`, one JSON line per item with its
category, path, size, mode, and result.

## What Chet cleans

Safe to remove items are selected after a scan. Check first items are never selected for you.
Delete means the item is removed permanently; Move to Trash means it can be restored.

| Category | What | Group | Removal |
|---|---|---|---|
| Trash | Files already in the Trash | Safe to remove | Delete |
| App caches | `~/Library/Caches`, one item per app | Safe to remove | Delete |
| Logs | `~/Library/Logs` | Safe to remove | Delete |
| Xcode files | DerivedData, simulator caches, old device support files | Safe to remove | Delete |
| Developer caches | Homebrew, npm, Yarn, pnpm, pip, uv, Cargo, Go, Gradle, SwiftPM, CocoaPods, Nix | Safe to remove | Delete |
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
| System caches | `/Library/Caches`, one item per folder | Check first | Delete with administrator |
| System logs | `/Library/Logs`, one item per folder | Check first | Delete with administrator |

## Settings

Settings holds the scan toggles, size limits, folder rules, tweak preferences, and the
administrator switch. The size limits you can change are the duplicate size, the large-file
size, and the large-file age. The other limits are fixed. The **Administrator** panel at the
bottom of **Folders** turns system cleanup on or off and sets how long each approval lasts.

## Storage

The **Storage** page shows which folders in your home folder take the most space. Click a
folder to look inside. Pause and resume the scan from the page while it builds the map.

## Go module cache

The **Go** page shows the module cache that Go keeps for downloaded dependencies. The cache
lives at the path Go reports for `GOMODCACHE`, usually `~/go/pkg/mod`. The page shows its
location, size, module count, and the Go toolchain it found. Chet hides the page when it cannot
find Go.

**Remove module cache…** runs `go clean -modcache`. The next build downloads the modules
again, so the first build after removal is slower and needs network access. Chet runs the Go
command and never deletes cache files itself.

With `DRY_RUN` set, the action is a preview. Chet reports the command it would run and removes
nothing.

## mise tools

The **mise** page lists the tools declared in `~/.config/mise/config.toml`. Each row names a
tool, the version the config requests, and whether that version is active, inactive, or not
installed. A tool that mise has installed shows its install path. **Locations** shows the
config file and mise's cache folder.

The page only reads. Chet asks mise for its tool list and cache path, and never installs,
removes, switches, or prunes a version. Nothing on the page changes your setup.

Chet shows the page only when the config declares at least one tool and a mise binary is
available at `~/.local/bin/mise` or on your `PATH`. Without both, the page stays out of the
sidebar.

## Tweaks

Tweaks changes macOS preferences that normally take a `defaults write` command or a hidden
setting. The list covers Finder, Dock, keyboard, trackpad, screenshots, windows, appearance,
and a set of read-only security and developer checks.

Each row shows the current value, labels the change low, medium, or high risk, and names what
to restart: Finder, the Dock, the menu bar, or the whole session. A change at medium risk or
higher asks for confirmation.

Chet writes one value at a time, reads it back to verify, and appends the change to
`~/Library/Application Support/Chet/tweaks.log`. The pane counts the tweaks you changed and can
reset them all to their original values.

Tweaks reports these states: supported, unknown, unsupported, unchanged, changed, failed,
pending restart, and pending confirmation.

## Uninstall apps

Pick **Apps** in the sidebar, search for an app, and select it. Chet reads the app bundle, then
looks in the user Library for data that names the app's bundle ID or its helpers: Application
Support, Preferences (including ByHost), Caches, Logs, Containers, Group Containers, Saved
Application State, Cookies, Application Scripts, Launch Agents, and WebKit.

Each row says why it matched:

- **Belongs to this app**: the bundle ID or an embedded helper ID. Selected by default.
- **Probably belongs**: the folder is named after the app or the last part of its bundle ID.
  Never selected by default; review it first.
- **Shared with another app**: a group container, or data another installed app also claims.
  Cannot be selected.
- **Needs an administrator**: an entry under `/Library` or in a folder the user cannot write.
  Unchecked until you turn on Administrator cleanup in Settings. Those files are removed
  permanently, not moved to the Trash.
- **Protected by macOS**: system folders, Keychains, Mail, Messages, and iCloud Drive. Never
  listed as removable.

The app is unchecked when it is open or cannot be written. The **Move to Trash** button is
disabled while the app or one of its helpers runs, and the core checks again before the first
move. Related files go first and the app bundle goes last, so a failed move never hides the app
itself. Files go to the Trash. An item that needed an administrator is removed permanently
instead. The app bundle goes to the Trash when macOS allows it; when macOS refuses, Chet asks
the administrator helper and the bundle is removed permanently. The confirmation says which
path applies before you act.

## How Chet protects your data

- A single safety check runs for every item, at scan time and again right before removal. It
  refuses system folders, app bundles (the Apps page has its own explicit app-bundle
  allowlist), iCloud Drive, Keychains, Mail and Messages data, Photos libraries, `.git`
  folders, symlinks, and other volumes.
- Before removal Chet compares each file with what the scan saw: inode, size, modification
  time. If anything changed, the file is left alone.
- Caches of a running app are skipped. The summary tells you which app to quit.
- For duplicates and similar media, one copy is always kept. Exact duplicates are compared
  byte for byte before they are shown.
- In Apps, only exact bundle-ID matches and embedded helper matches are selected for you.
  Name-only matches stay unchecked, shared group containers are unselectable, and
  administrator-only entries stay unchecked until you turn on Administrator cleanup. Every row
  is checked again right before it moves.
- Every cleanup is written to `~/Library/Logs/chet/clean.log`.
- Every tweak write is read back and verified, then recorded in the tweak log.

## Administrator cleanup

Caches, logs, and app remnants owned by root need an administrator. Chet ships a small helper
for that job and keeps it off until you turn it on. It never asks for an administrator by
itself.

- Turn it on in Settings, pane **Folders**, panel **Administrator**, then approve Chet when
  macOS asks. The same panel turns it off again.
- The helper lives inside the app. It starts on your first removal and exits when the approval
  runs out, so nothing privileged stays running. An approval lasts 1 to 60 minutes, 10 by
  default; change it with the **Approval lifetime** slider.
- These files are removed permanently: root-owned data has no Trash of your own. Each row is
  checked again right before it goes. The one exception is the app bundle you chose in Apps:
  the helper removes it permanently only when the Trash move was refused.
- Covered: children of `/Library/Caches`, `/Library/Logs`, `/Library/Application Support`,
  `/Library/Preferences`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`, plus one direct
  app bundle in `/Applications`. Nothing else. Chet itself is never removed.
- With the helper off, those rows stay unchecked and a cleanup skips them.
- Only a signed build can turn this on. A locally built copy is ad-hoc signed, has no Team ID,
  and macOS refuses its helper; the panel says so and keeps the switch off.

## Accessibility

- Text meets WCAG AA contrast in both themes. The dimmest body and caption pairing is amber on
  paper at 4.94:1. The third, dimmer text tier (3.15:1) is used only for disabled controls, the
  loading ellipsis, non-text glyphs, and decorative separators.
- Status is an icon plus words. Color never carries a state on its own.
- Icon-only buttons take their name from the shared button components, where the label is a
  required parameter. That label is what VoiceOver reads.
- Confirmation and uninstall sheets close with Escape. Scan is Command-R, Settings is
  Command-comma, and selection is Command-A, Command-Shift-A, and Command-Option-I.
- The interface has no custom animation. The only motion is the system progress spinner while
  a real scan or clean runs.

## Install on another Mac

The app is ad-hoc signed and not notarized. Copied to another Mac, macOS blocks it at first
launch. Right-click the app and choose **Open**, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/chet.app
```

## Not covered

- Removing app languages or thinning app binaries. It breaks code signatures.
- Docker or OrbStack images. Use `docker system prune`.
- Tweaks outside the catalog. Chet changes only the preferences it can read back and verify.
