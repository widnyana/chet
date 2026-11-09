# Chet project notes

Notes for working on the app. The design rules are in `docs/DESIGN.md`, the architecture is
in `DEVELOPMENT.md`, and the user guide is `docs/USER-GUIDE.md`. This file covers how to run,
drive, and test the app while you change it.

## Run it

```sh
mise run dev      # build, one LaunchServices registration, open the debug app
mise run test     # ChetCore tests
mise run lint     # format check
```

The main window remembers its frame. Keep it at `960 x 632`, the supported minimum, instead
of full screen. The design is checked at that size.

## Testing rule

Every UI test runs with `DRY_RUN=1`. No test writes a preference, removes a file, empties the
Trash, or restarts an app. Build the gate into the test, not around it:

- Launch the test copy with `open -n --env DRY_RUN=1 <app>`. Do not rely on the repo `.env`:
  a copied app outside the repo does not walk up to it.
- Expect `Preview only. Nothing will be removed.` on Home and
  `Preview only. No tweak is changed.` on Tweaks.
- Every tweak control must report `enabled: false`. A press on a disabled control is a no-op;
  verify the underlying key did not change.
- The confirmation sheet and `Revert last change` stay disabled under the gate. Render them
  with the preview hook; engine refusal is covered by `ChetCore` tests. Do not launch without
  `DRY_RUN=1`.
- A `DEBUG` build with `CHET_TWEAK_PREVIEW=confirm` opens the confirmation sheet for the first
  medium-risk tweak after load. `CHET_TWEAK_PREVIEW=revert` opens the revert dialog when a
  tweak detail sheet appears. Both change no preference. Release builds do not contain the
  hook. Start the preview directly:
  `DRY_RUN=1 CHET_TWEAK_PREVIEW=confirm /tmp/ChetUITest.app/Contents/MacOS/chet &`.
  `open --env` with two flags did not carry the second variable.

## Administrator cleanup

Root cleanup is one gated path. `ChetCore` owns the contract: `ChetHelperProtocol`,
`HelperGuard.refusal`, `HelperSession`, `PrivilegedClient`. The daemon target is `chet-helper`,
embedded at `Contents/MacOS/chet-helper` with its plist in `Contents/Library/LaunchDaemons`.

- Removal is permanent (`removeItem`), never the Trash. With no helper, an admin item is a
  policy skip and its control reports `enabled: false`.
- The approval is bounded: the daemon starts on the first request and exits at the deadline,
  so a later request starts a new one. Lifetime is 1...60 minutes, 10 by default.
- `HelperGuard` bounds the damage: absolute paths only, no `..`, no symlink in any parent, no
  protected tree, and only children of `/Library/Caches`, `/Library/Logs`,
  `/Library/Application Support`, `/Library/Preferences`, `/Library/LaunchAgents`,
  `/Library/LaunchDaemons`.
- `DRY_RUN=1` never registers the daemon, never calls it, and never changes a file.
- Never install, approve, or exercise the daemon in an automated check. Registration and a
  real removal are manual, from a copy in `/Applications`, with the user's consent.
- `mise run build` builds `chet-helper` first; the app's post-build script copies and signs it
  before Xcode signs the app, so the final signature covers both.

## Tweaks coverage

The catalog has 55 entries: Finder 11, Dock 8, Keyboard 10, Trackpad 2, Screenshots 5,
Appearance 6, Windows 5, Security 4 read-only checks, Developer 4 read-only checks.

Absent because they need root, a private format, or an unverified key: power, network,
notifications and focus, security and developer entries beyond the four read-only checks
each, pointer speed and acceleration, Dock bounce and lock, screenshot selection and
recording location, window tiling, appearance accent/highlight/automatic/date format/font
rendering, and keyboard emoji substitution.

## First launch

`ContentView` decides between the permission gate and the app:

```swift
if model.access == .denied && !model.accessSkipped {
    OnboardingView()
} else {
    NavigationSplitView { SidebarView(...) } detail: { ... }
}
```

### Without Full Disk Access

Only `OnboardingView` is visible. No sidebar, no scan toolbar, no command bar.

Top to bottom:

| Element | Identifier | Kind |
|---|---|---|
| Padlock icon | none | `AXImage`, label `lock.shield` |
| `Chet needs Full Disk Access` | `gate.title` | `AXStaticText` |
| One-sentence explanation | none | `AXStaticText` |
| Three numbered steps | none | `AXStaticText` |
| `Open System Settings` | `gate.openSettings` | `AXButton` |
| `Continue with limited results` | `gate.continue` | `AXLink` |
| `Without access, Chet finds less...` | none | `AXStaticText` |
| `Checking for access` with spinner | none | `AXStaticText` + progress |

The screen polls `FullDiskAccess.status()` once a second and leaves by itself when the probe
file becomes readable. macOS can keep a stale denial for an already running process; if the
gate stays after the grant, relaunch the app. A rebuild changes the signature, so a fresh
build can land on the gate again.

### With Full Disk Access

The window becomes the split view:

- Sidebar, top to bottom: `Home` (`sidebar.overview`), then after a scan the category rows
  split into `Safe to remove` and `Check first` (`sidebar.<category id>`), then
  `Configure > Tweaks` (`sidebar.tweaks`), then `Tools > Apps` (`sidebar.applications`) and
  `Storage` (`sidebar.disk-map`). The footer holds the startup disk capacity and the Trash.
- Detail: Home (`OverviewView`). It has three states:
  - never scanned: capacity bar, `Scan` (`home.scan`), empty state `No scan yet` (`home.empty`);
  - scanning: the step list, linear progress, `Pause` (`home.pause`) and `Resume`
    (`home.resume`);
  - finished: `Safe to remove` and `Check first` ledgers, total metric, command bar. While
    items are selected the bar holds `Clean selected` as the primary and `Scan again`
    (`home.rescan`) beside it; with nothing selected `Scan again` is the primary (`home.scan`).
- Toolbar: the scan control (`toolbar.scan`, or `toolbar.scanStop` while scanning) on every
  destination except Apps and Tweaks. Apps owns search, layout, and reload. Tweaks owns
  search and `Read again` (`tweaks.reload`).
- Status strip: absent by default. It appears for `DRY_RUN` (`Preview only. Nothing will be
  removed.`), for limited access, or for four seconds after a scan finishes. Tweaks hides the
  cleaning strip and shows its own preview gate.

### Skipping the gate

Yes, skipping exists. It is a text link, not a button:

- Control: `Continue with limited results`, identifier `gate.continue`, role `AXLink`.
- Code: `OnboardingView` sets `model.accessSkipped = true`.
- Session only: `ScanModel.accessSkipped` is a plain `var` with no `UserDefaults` write. The
  gate returns on the next launch until access is granted.
- Command: `axdrv press id=gate.continue`.

Impact while skipped:

- The app is fully usable, but folders macOS protects stay unreadable.
- The top strip says `Limited access. Some folders are hidden.` with `Open Settings` and
  `Hide until the next launch` (dismissal is session-only; `ScanModel.bannerDismissed`).
- A category whose scan hit a denied path carries a lock icon; its tooltip says some folders
  need Full Disk Access (`RuleScanner` sets `needsFullDiskAccess`, `SidebarView` draws
  `lock.fill`).
- Home can show `Some folders could not be read. Results may be incomplete.`
  (`model.readErrors`).
- Nothing is removed automatically. Review categories stay review, and every removal still
  needs a selection and a confirmation.
- Tweaks is unaffected: preferences are user-level and need no Full Disk Access.
- After a second `Open Settings`, the strip adds `Chet may be listed twice in Full Disk
  Access. Remove the old entry.`

### Screen flow

| Trigger | Result |
|---|---|
| Launch, access denied, not skipped | Permission gate |
| Launch, access granted | Sidebar + Home |
| Gate: `Continue with limited results` | Sidebar + Home, access banner |
| Gate: `Open System Settings` | System Settings, gate stays |
| Grant lands (or relaunch) | Sidebar + Home, no gate |
| Scan (toolbar, `home.scan`, Cmd-R) | Home scanning state, then ledgers; sidebar gains category rows |
| Sidebar category row | Category detail for that category |
| Home ledger row | Category detail (same destination) |
| Sidebar `snapshots`, when local snapshots exist | Time Machine snapshots |
| Sidebar `Tweaks` | Tweaks catalog |
| Sidebar `Apps` | App inventory |
| App row chevron (`Show files left by <app>`) or double-click | App detail, pushed |
| Sidebar `Storage` | Storage map |
| Category command bar `Remove selected` | Clean sheet: confirm, progress, summary |
| Snapshot command bar | Clean sheet with snapshots |
| Footer `Empty` on Trash | Trash confirmation dialog |
| Cmd-, or Chet > Settings… | Settings window, four panes |
| Chet > About Chet | About window |
| Sidebar toggle in the toolbar | Hide or show the sidebar |

## Navigating back

- **App detail** is the only pushed screen. `NavigationStack` supplies the back control; it is
  an `AXButton` whose description is `Back` and whose identifier is `chevron.backward`. Press
  it and the app inventory returns. No custom back control is needed or present.
- **Every sidebar destination** (Home, a category, snapshots, Tweaks, Apps, Storage) is a
  destination, not a stack entry. The way back is the sidebar: select another row, including
  `Home`. This is the macOS split-view convention; a history stack would fight the sidebar.
- **When the sidebar is hidden**, the toolbar button `Hide Sidebar` becomes `Show Sidebar`.
  Press it to bring the sidebar back.
- **Sheets** close with their own control: `Cancel` or `Close`, and `Escape` on the uninstall
  sheets. The clean sheet cannot be dismissed while cleaning; it ends at the summary.
- **Settings and About** are separate windows. Close them with Cmd-W or the red button; they
  do not replace the detail pane.

No back control is missing, so none was added. If a future screen is pushed outside a
`NavigationStack`, add the same automatic back affordance rather than a custom button.

## What goes where and why

- `Home` answers one question: what can be removed, and what do I do next. It holds the total,
  the capacity bar, the scan state, and the two ledgers. It is the sidebar's default.
- Categories are split by decision, not by data source: `Safe to remove` is selected for you,
  `Check first` never is. That split is why the sidebar groups them under those headings.
- `Configure > Tweaks` is configuration, not cleanup. It stays out of the clean ledger and
  does not appear in the scan steps.
- `Tools > Apps` and `Tools > Storage` are tools, not findings. Apps is a destination with its
  own `NavigationStack`; Storage is a map of the same disk data.
- The footer holds machine state that is always true, not a scan result: capacity, purgeable
  space, and the Trash.
- The status strip holds global, transient state in flow: dry run, limited access, scan
  finished. It never floats over content.
- Sheets hold a decision or an operation: clean confirmation and progress, uninstall
  confirmation and summary, tweak details and confirmation.
- Settings and About are separate windows because they are not destinations and can stay
  open while the ledger runs.

## States to test

| Axis | Values |
|---|---|
| Access | granted, denied, denied and skipped, skipped and banner dismissed |
| Scan | never scanned, scanning, paused, finished with results, finished empty |
| Dry run | off, on (`DRY_RUN=1` in `.env` or the process environment) |
| Sidebar | shown, hidden |
| Window | 960 x 632 minimum, wider |
| Tweaks | supported, unknown, unsupported, unchanged, changed, failed, pending restart, pending confirmation |
| Sheets | open, closed with Cancel, closed with Escape, non-dismissible while cleaning |

## Buttons

Every button comes from `DesignSystem.swift`: `PrimaryActionButton`,
`DestructiveActionButton`, `SecondaryActionButton`, `QuietActionButton`, `IconActionButton`.
They share the 6 pt control radius, the regular control size, the label style, the help and
accessibility wiring, and an optional keyboard shortcut. Do not style a `Button` where it is
used; a hand-styled toolbar button is how the scan control became an unlabeled glyph.

Native styles stay for things that are not buttons: menu items, file pickers, the layout
picker, and the text link on the permission screen.

## Reuse the components

Read [docs/design/composition.md](docs/design/composition.md) before adding a page,
layout, or component. It is the short decision tree and review gate.

A screen composes shared components. It does not rebuild a pattern, and it does not set
spacing on a call site.

- One component per pattern. Settings uses `SettingsPaneSwitcher`, `SettingsPanel`,
  `SettingsRow`, `SettingsActionRow`, `SettingsNote`, and `SettingsDivider`; nothing else
  draws a settings pane or a settings row. Tweaks uses `PreferenceRow` and `DefinitionRow`;
  do not hand-build a preference row in a screen.
- Geometry lives in the component. `SettingsGrid` owns the row height and the row padding,
  and each panel's `Grid` sizes the control column to its widest control. `PreferenceRow`
  owns its 150 pt control column and the 8 pt row padding. A pane or a list adds rows, never
  its own `padding` or `frame` around them.
- A variant is a parameter, not a copy. `SettingsRow` takes an optional `detail`;
  `PreferenceRow` takes notes and an accessory; neither needs a second row type.
- Tokens only. Sizes come from `Spacing`, `Metrics`, and `Typography`. A literal number next
  to a view is a design change that skipped the token table.
- Copy has one source. Category names come from `CategoryCopy`, step names from
  `ScanStepCopy`, app parts and skip reasons from `AppCopy`, tweak words from `TweakCopy`.
  Do not retype them in a view.
- When a pattern appears a third time, extract it into `DesignSystem.swift` (generic UI) or
  the feature's own parts file. Do not copy the third one.

## Drive it by selector

Screenshots and pixel clicks are slow and brittle. The app exposes accessibility identifiers,
and the accessibility tree is the closest thing it has to a DOM.

Build the driver once:

```sh
swiftc -O scripts/axdrv.swift -o /tmp/axdrv
```

The terminal needs Accessibility permission. The driver prints `AX NOT TRUSTED` and exits if
it is missing.

| Command | What it does |
|---|---|
| `/tmp/axdrv apps` | every regular app with pid, bundle, name |
| `/tmp/axdrv --pid <pid> windows` | the target's window ids and bounds |
| `/tmp/axdrv dump [selector]` | role, id, description, title, value, state, frame |
| `/tmp/axdrv dump --json [selector]` | the same as one JSON document |
| `/tmp/axdrv dump --all [selector]` | every node, not only actionable or named ones |
| `/tmp/axdrv texts [selector]` | static text values |
| `/tmp/axdrv press <selector>` | `AXPress` on exactly one match |
| `/tmp/axdrv select <selector>` | `AXSelectedRows` on the row containing one match |
| `/tmp/axdrv click <selector>` | real mouse click at the center of one match |
| `/tmp/axdrv frame <selector>` | `x,y,w,h` in global screen points |
| `/tmp/axdrv activate` | bring the target app forward |
| `/tmp/axdrv type <text>` | activate, then type |
| `/tmp/axdrv key <keycode> [cmd]` | activate, then press a key |

Target is `--pid`, `--app <bundle or name>`, `AXDRV_PID`, or the frontmost app. `apps` needs
no target and no Accessibility trust.

Selectors are `key=value` terms, ANDed: `id=gate.continue`, `role=AXButton desc=Back`,
`enabled=true`. A bare term is a case-insensitive substring over id, description, title, and
value, so the older `press gate.continue` still resolves. A selector must match exactly one
element; several matches exit 6 and print the candidates.

Use `press` for buttons and links, `select` for sidebar rows, and `click` only for controls
with no press action. A press on a disabled control can report success and do nothing.

### How selectors map from SwiftUI

| SwiftUI control | AX role | How to match |
|---|---|---|
| `Button` from `DesignSystem` | `AXButton` | identifier; description carries the accessibility label |
| Link-style `Button` (the gate) | `AXLink` | identifier; `press` works |
| `Toggle` with `.switch` | `AXCheckBox` | identifier; `press` toggles |
| `Toggle` with `.checkbox` (rows) | `AXCheckBox` | description, e.g. `Select to remove` |
| `Picker` with `.menu` | `AXPopUpButton` | identifier; description carries the label |
| Segmented `Picker` | `AXRadioGroup` + `AXRadioButton` | description, e.g. `All`, `Changed` |
| `Slider` | `AXSlider` | identifier; drag or set `AXValue`, then end editing to commit |
| `TextField` or `.searchable` | `AXTextField` | identifier or description; focus it first |
| `List` sidebar | `AXOutline` > `AXRow` > `AXCell` | identifier sits on the `AXStaticText`; select the row, do not press it |
| `NavigationSplitView` sidebar toggle | `AXButton` | description `Hide Sidebar` / `Show Sidebar` |
| Push back control | `AXButton` | description `Back`, identifier `chevron.backward` |
| Sheet | `AXSheet` | its controls keep their identifiers |

SwiftUI propagates an identifier down to descendants. An identifier on a wrapper replaces the
identifiers of the controls inside it. Put the identifier on the control you will press.

### Identifiers in place

| Identifier | Element |
|---|---|
| `gate.title`, `gate.openSettings`, `gate.continue` | permission screen |
| `sidebar.overview` | Home |
| `sidebar.applications` | Apps |
| `sidebar.disk-map` | Storage |
| `sidebar.tweaks` | Tweaks |
| `sidebar.<category id>` | category rows: `trash`, `caches`, `logs`, `xcode`, `dev-garbage`, `browser`, `duplicates`, `large-files`, `leftovers`, `snapshots`, and the rest |
| `toolbar.scan`, `toolbar.scanStop` | toolbar scan control |
| `home.header`, `home.empty`, `home.scan`, `home.rescan`, `home.pause`, `home.resume` | Home |
| `apps.header` | Apps |
| `storage.header`, `storage.pause`, `storage.resume` | Storage |
| `list.selectAll` | category table select-all |
| `tweaks.header`, `tweaks.page`, `tweaks.reload`, `tweaks.loading`, `tweaks.empty` | Tweaks page |
| `tweak.toggle.<tweak id>`, `tweak.choice.<tweak id>`, `tweak.range.<tweak id>`, `tweak.text.<tweak id>`, `tweak.folder.<tweak id>`, `tweak.inspect.<tweak id>` | tweak controls |
| `tweak.detail.<tweak id>`, `tweak.confirm.<tweak id>` | tweak sheets |
| `settings.pane.whatToFind`, `settings.pane.limits`, `settings.pane.folders`, `settings.pane.tweaks` | Settings panes |

Controls without an identifier are matched by role and description: `Back`,
`Hide Sidebar`/`Show Sidebar`, `Empty the Trash`, `Show files left by <app>`,
`Open Settings`, `All`/`Changed`.

Add a new one with `.accessibilityIdentifier("screen.thing")` on the control, next to its
`.accessibilityLabel`. Name it `screen.element`, lowercase, one dot.

### Extract the selector map to a file

`scripts/ui_selectors.py` calls `scripts/axdrv.swift` with `dump --json`, drops per-app
inventory rows, and merges the result into `docs/ui-selectors.json` under a screen name.
Positions, roles, descriptions, values, state, and actions are kept, so the file can be
diffed and reused.

```sh
python3 scripts/ui_selectors.py --pid 1234 --screen home
python3 scripts/ui_selectors.py --pid 1234 --screen tweaks
python3 scripts/ui_selectors.py --list        # summary only, writes nothing
```

- Run it once per screen you care about; each run replaces that screen's entry.
- `--pid` is required when more than one Chet process is running. Without it the tool aborts
  rather than guess.
- The extractor skips rows whose description names an installed app, and it drops the
  auto-generated `SwiftUI.WindowGroup...` identifier, so the saved file does not drift with
  the machine.
- `docs/ui-selectors.json` is generated and gitignored, so it stays local. Regenerate it
  after a UI change; do not hand-edit.
- The gate is a one-shot screen: relaunch the app, dump `gate`, then press `gate.continue`.

More than one Chet can run at once. Pick the instance explicitly:

```sh
pgrep -f chet.app/Contents/MacOS/chet
/tmp/axdrv --pid 63481 press id=gate.continue
```

`AXDRV_PID=<pid>` is still accepted when neither `--pid` nor `--app` is given, so older
scripts keep working.

Treat `mise run dev` as destructive to other test runs: it starts with `pkill -x chet` and
ends every instance. During a selector session, launch by path instead and kill only your pid.

### Pitfalls found the hard way

- **Sidebar rows do not take `AXPress`.** The identifier lands on the `AXStaticText` inside
  the row, and the row's only actions are `AXShowDefaultUI`/`AXShowAlternateUI`. Set
  `AXSelectedRows` on the outline with `axdrv select`.
- **`gate.continue` is `AXLink`, not `AXButton`.** Match the role or the identifier, not the
  button query.
- **System Events cannot press SwiftUI custom buttons.** `click button "Limits"` fails with
  `-1728` because the button has no title. Press the accessibility identifier.
- **Menu items do work**: `click menu item "Settings…" of menu 1 of menu bar item 2 of menu
  bar 1` opens the Settings window. That is a reliable way to open it after the gate.
- **The Settings window opens even while the permission gate is up.**
- **A container identifier overwrites its children.** An identifier on a wrapper replaces the
  identifiers below it, and one id can land on several elements. `frame id=tweaks.header`
  matched two static texts in Chet. Put the identifier on the control, and narrow with
  `role=` or `title=` when a wrapper already carries one.
- **Ambiguity is an error.** A selector that matches several elements exits 6 and prints the
  candidates. Narrow it with `role=`, `desc=`, or `enabled=`. Do not add a flag to pick the
  first match; that is how a test clicks the wrong control.
- **`press failed` exits 0.** The AX action returned an error; treat the printed text as the
  result, or check `enabled` first.
- **`frame` prints only `x,y,w,h`.** Use `dump <selector>` when the full element description
  is needed.
- **`screencapture -R` captures the screen, not the window.** Capture by window id from
  `CGWindowList`; a window on another Space still has a valid id.
- **`open -a` activates an existing instance.** Use `open -n <path>` to launch one more.
- **Menu clicks target a process by name.** With several Chet instances, `click menu item
  "Settings…"` can hit the wrong one. Activate the test copy by its unique bundle id and send
  Cmd-, with a key event instead:

```sh
/tmp/axdrv --pid <pid> key 43 cmd      # virtual key 43 is comma
```
- **Window position changes between launches.** Never hard-code click coordinates; read them
  with `axdrv frame` or the selector JSON.
- **A `.env` with `DRY_RUN=1` turns every removal into a preview** and disables tweak controls.
  Remove it to test a real write.

### Recipe

```sh
open -n .build/xc/Build/Products/Debug/chet.app && sleep 5
pgrep -f chet.app/Contents/MacOS/chet            # pick the pid you launched
/tmp/axdrv --pid <pid> press id=gate.continue    # leave the permission gate
sleep 2
/tmp/axdrv --pid <pid> select id=sidebar.overview
/tmp/axdrv --pid <pid> texts | grep "No scan yet"
/tmp/axdrv --pid <pid> press id=home.scan        # start a scan
sleep 2
/tmp/axdrv --pid <pid> press id=toolbar.scanStop
/tmp/axdrv --pid <pid> select id=sidebar.tweaks
sleep 2
python3 scripts/ui_selectors.py --pid <pid> --screen tweaks
python3 scripts/ui_selectors.py --list
```

Quit with `kill <pid>` or `osascript -e 'tell application id "id.web.widnyana.chet" to quit'`
after the last assertion. Leaving the window open blocks whoever else shares the machine.

## Another agent in the same tree

Two agents can work in this checkout at once. Expect untracked files from the other session,
or edits to tracked files, while you work.

- Do not delete, move, or repair a file you did not create. An untracked file that fails to
  compile is the other session's work in progress, not a broken repo.
- One broken WIP file fails the whole `xcodebuild`. Verify your own change against a clean
  snapshot instead of waiting:

```sh
rm -rf /tmp/verify && mkdir -p /tmp/verify
git archive HEAD | tar -x -C /tmp/verify
cp Chet/Views/SettingsComponents.swift /tmp/verify/Chet/Views/   # repeat for every file you changed
cd /tmp/verify && xcodegen generate --quiet
xcodebuild -project chet.xcodeproj -scheme chet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/verify/.build build
```

- Stage only your own paths. `git add -A` in a shared tree stages the other session's partial
  work.
- `chet.xcodeproj` is generated and not tracked. Run `mise run gen` after adding a Swift file;
  `mise run build` depends on it.
- `docs/plans` is gitignored. A plan written there stays local and never reaches a commit.
- `mise run dev` starts with `pkill -x chet`, which ends every running instance, including one
  the other session launched for its own test. Avoid it while they are driving the app.
- The design document is `docs/DESIGN.md`. There is no `DESIGNS.md`.

<!-- antislop:start -->
## antislop
For UI, copy, people, mobile layout, or code comments work, read these installed skill files directly (use these paths even if a same-named global skill exists):
- Core filter, always on: `antislop`: `.agents/skills/antislop/SKILL.md`
- UI / visual: `antislop-ui`: `.agents/skills/antislop-ui/SKILL.md`
- Code comments: `antislop-code`: `.agents/skills/antislop-code/SKILL.md`
- Copy & text: `antislop-copywriting`: `.agents/skills/antislop-copywriting/SKILL.md`
- People: `antislop-human`: `.agents/skills/antislop-human/SKILL.md`
- Mobile / responsive: `antislop-layoutmobile`: `.agents/skills/antislop-layoutmobile/SKILL.md`
Before starting, follow the core's "Two Usage Modes" section in strict order: explicit session instruction first, then global preference, then ask. A session instruction always wins. For a resolved mode, say `antislop active: <mode> (session override).` or `antislop active: <mode> (global preference).` once before presenting findings or making edits, using the actual mode and source. Acknowledging the user's request without naming the source does not replace this notice.
Only an explicit choice of antislop during or after selects a session mode. A request to review, audit, or avoid file edits does not select a mode; read the global preference in that case. Another skill's mode does not select antislop's mode.
If the mode is unresolved, ask during/after and end the response; wait for the answer before any UI review, planning, or concept. For read-only tasks, put the active-mode notice only at the start of the final answer, never in progress messages. For editing tasks, announce before the first edit and omit it from the final answer.
To update antislop later: `npx antislop-ai --update`, or run `npx antislop-ai` and pick Overwrite them.
<!-- antislop:end -->
