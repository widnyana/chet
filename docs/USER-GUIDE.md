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

Home names the state it is in:

- **Never scanned**: the disk capacity bar and a **Scan** button.
- **Scanning**: the step list, a linear progress bar, **Pause**, and **Resume**. No result
  sentence appears until the scan finishes.
- **Finished, not everything readable**: **Not everything was read**, with what to grant.
- **Finished and empty**: **Nothing to reclaim**, `This Mac is tidy.` This appears only after a
  scan that finished and read the folders it measures.
- **Finished with findings**: the Safe to remove and Check first ledgers, the total space, and
  the command bar.

The incomplete-results banner names how many folders a measured category could not read. Folder
problems outside what a category measures, such as macOS-protected paths or files in your home
folder, do not raise it.

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

Right-click anywhere on a row for **Reveal in Finder**, **Quick Look**, and **Copy Path**. The
whole row takes the click, including the blank space after the name.

Large files rows also name the file kind, such as Image, PDF document, or Archive.

The clean sheet then shows progress and ends with a summary. It cannot be dismissed while
cleaning. The summary lists what moved, what was skipped, and the space recovered.

Every cleanup is written to `~/Library/Logs/chet/clean.log`, one JSON line per item with its
category, path, size, mode, and result.

A refused item names one reason: an excluded folder, a protected folder, a git repository, an
app bundle, a Photos library, a symlink, a mounted volume, or a path outside your home folder.
The summary and the audit row carry the same reason.

The last 10 Trash operations can be restored from the Storage page or from the clean summary.
Restore is offered only when the Trash copy and the original folder both still exist.

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
| Project build files | `target`, `node_modules`, `vendor`, `.build`, `.gradle`, DerivedData, Pods, `.vite`, `.next`, `.turbo`, `build`, `.dart_tool`, `.terraform`, `.terragrunt-cache`, and Python virtual environments | Check first | Move to Trash |
| Duplicate files | Files with the same bytes (1 MB and larger) | Check first | Move to Trash |
| Large files | Over 500 MB, or over 50 MB and untouched for a year | Check first | Move to Trash |
| Leftover app files | Library data of apps that are no longer installed | Check first | Move to Trash |
| Similar photos | Resized or recompressed copies of the same photo | Check first | Move to Trash |
| Blurry photos | Photos with very little sharp detail | Check first | Move to Trash |
| Similar videos | Re-encoded copies of the same video | Check first | Move to Trash |
| Time Machine snapshots | Snapshots on the startup disk | Check first | Delete with `tmutil` |
| System caches | `/Library/Caches`, one item per folder | Check first | Delete with administrator |
| System logs | `/Library/Logs`, one item per folder | Check first | Delete with administrator |

App caches holds one folder per app under `~/Library/Caches`. Most are derived data and are
pre-selected for permanent deletion. Folders that hold account, purchase, wallet, pass, or session
state are shown as Review and are never pre-selected: App Store, StoreKit, PassKit, GameKit, Screen
Time, Family, Apple Account, and their siblings. A cache folder whose name is a running app's bundle
identifier is skipped while that app runs.

A folder that appears on more than one page is judged once, by the stricter verdict, and every page
shows that verdict.

Project build files follow strict rules so a folder name alone is never enough:

- `vendor` counts only when its parent holds `composer.json`; a vendor folder of hand-written
  exports stays out.
- A Python virtual environment counts when the folder holds `pyvenv.cfg`, whatever the folder is
  called. It appears once, under Project build files, not under Tagged cache folders.
- Nothing inside a package manager store counts as a project build file. A pnpm store is skipped,
  and its space is measured under Developer caches instead.
- Every row names the tool behind it: `Rust target`, `Node modules`, `PHP vendor`, `Swift build`,
  `Gradle`, `Xcode DerivedData`, `CocoaPods`, `Vite`, `Next.js`, `Turborepo`, `Build output`,
  `Dart tool`, `Terraform`, `Terragrunt cache`, or `Python venv`.

Similar photos groups only images that are alike. Two images join a group when their hashes and
their shapes agree, a group never chains past that bound, and a flat or blank image never joins one.
The largest image in a group is kept. Similar videos follows the same tile layout.

Similar photos and Similar videos show each image in a square card: the image fits inside the box
instead of being cropped, cards keep a visible gap, and the grid holds a gutter from the divider.

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
find Go. A Go installed by mise is found through the same data folder, so the page works when
Chet is opened from Finder.

**Remove module cache…** runs `go clean -modcache`. The next build downloads the modules
again, so the first build after removal is slower and needs network access. Chet runs the Go
command and never deletes cache files itself.

With `DRY_RUN` set, the action is a preview. Chet reports the command it would run and removes
nothing.

## mise tools

The **mise** page lists every installed version of every tool, plus any version the config
declares that is not installed. Each row names the tool and one version, and whether that
version is active, inactive, or not installed. The version the config requests carries a
`declared` mark, so a tool with several installed versions shows all of them and you can see
which one is in use. A tool that is installed but not declared still appears. Installed rows
show their install path. **Locations** shows the config file and mise's cache folder.

The page only reads. Chet asks mise for its tool list and cache path, and never installs,
removes, switches, or prunes a version. Nothing on the page changes your setup.

Chet shows the page only when the config declares at least one tool and a mise binary is
available at `~/.local/bin/mise` or on your `PATH`. Without both, the page stays out of the
sidebar.

Opened from Finder, Chet finds your mise data folder the way your shell does: the
`MISE_DATA_DIR` variable, a `data_dir` setting in the mise config, or an `export` in
`~/.zshrc`, `~/.zprofile`, `~/.bashrc`, or `~/.bash_profile`. Installed tools therefore read as
installed without launching Chet from a terminal.

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

Each tweak row states the value macOS ships with. Rows that differ from it carry a tinted body, so a
changed setting is visible without opening it. `Not set` means the key is absent by default.

A rule runs a tweak when a chosen app is running. Add a rule from a tweak's details sheet: pick
the app, pick on or off, and add. The `Automated` filter lists every tweak with a rule. The
Settings window counts the rules and can revert every automated change at once.

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
- Chet has no network access, no telemetry, and no crash reporter. Nothing leaves this Mac.

Each app row states when you last used it, from Spotlight. Apps Spotlight has not seen launch read
`Last used: not recorded`. Sort by last used to bring the newest to the top.

Outdated Homebrew packages can be upgraded one at a time from their row, or all at once from the
toolbar. Both ask for the same confirmation, and a dry run prints the command instead of running it.

About states the build date and the commit the build came from. `Unknown` means the build did not
stamp them.

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

Download the installer and run it:

```sh
curl -fsSL https://raw.githubusercontent.com/widnyana/chet/main/scripts/install-chet.sh -o /tmp/install-chet.sh
bash /tmp/install-chet.sh
```

It needs bash, curl, and the macOS tools, not mise or Xcode. It finds the latest GitHub
release, downloads the app asset, copies `chet.app` to `/Applications`, and clears the
quarantine flag, in that order. `--user` installs into `~/Applications` instead, and
`--target <dir>` installs into a folder you name. With no release published the script says so
and installs nothing.

From a checkout, run the script directly (no mise needed):

```sh
bash scripts/install-chet.sh
```

With mise installed, `mise run install-chet` does the same.

The app is ad-hoc signed and not notarized. If you copy it by hand, macOS blocks it at first
launch. Right-click the app and choose **Open**, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/chet.app
```

## Not covered

- Removing app languages or thinning app binaries. It breaks code signatures.
- Docker or OrbStack images. Use `docker system prune`.
- Tweaks outside the catalog. Chet changes only the preferences it can read back and verify.
