# Chet project notes

Design rules: `docs/DESIGN.md`. Architecture: `DEVELOPMENT.md`. User guide: `docs/USER-GUIDE.md`.
This file covers how to run, drive, and test the app while you change it.

## Run it

```sh
mise run dev      # build, one LaunchServices registration, open the debug app
mise run test     # ChetCore tests
mise run lint     # format check
mise run gen      # regenerate chet.xcodeproj (untracked) after adding a Swift file
```

Keep the main window at `960 x 632`, the supported minimum. The design is checked at that size.

## Testing rule

Every UI test runs with `DRY_RUN=1`. No test writes a preference, removes a file, empties the
Trash, or restarts an app.

- Launch a test copy with `open -n --env DRY_RUN=1 <app>`. Do not rely on the repo `.env`: a copy
  outside the repo does not find it.
- Expect `Preview only. Nothing is changed.` on Home and `Preview only. No tweak is changed.` on
  Tweaks. Every tweak control reports `enabled: false`; verify the key did not change.
- The confirmation sheet and `Revert last change` stay disabled under the gate. Render them with
  the preview hook (DEBUG builds only): `CHET_TWEAK_PREVIEW=confirm` or `=revert`. Start it
  directly, `open --env` drops the second variable:
  `DRY_RUN=1 CHET_TWEAK_PREVIEW=confirm /tmp/ChetUITest.app/Contents/MacOS/chet &`.
- States worth covering: access (granted, denied, skipped), scan (never, running, paused, done,
  empty), dry run on/off, sidebar shown/hidden, sheets (Cancel, Escape, non-dismissible while cleaning).

## Administrator cleanup

Root cleanup is one gated path owned by `ChetCore` (`ChetHelperProtocol`, `HelperGuard.refusal`,
`HelperSession`, `PrivilegedClient`). Daemon target: `chet-helper`.

- Removal is permanent (`removeItem`), never the Trash. No helper means a policy skip and `enabled: false`.
- Empty Trash is one gated path: `SystemStatusModel` resolves the gate once and passes it to
  the engine; the footer only chooses the sentence.
- `HelperGuard`: absolute paths only, no `..`, no symlink in a parent, no protected tree, only
  children of `/Library/{Caches,Logs,Application Support,Preferences,LaunchAgents,LaunchDaemons}`.
- `DRY_RUN=1` never registers or calls the daemon.
- Never install, approve, or exercise the daemon in an automated check. Registration and real
  removal are manual, from a copy in `/Applications`, with the user's consent.
- `mise run build` builds `chet-helper` first; the post-build script copies and signs it before
  Xcode signs the app.

## UI components

Read `docs/design/composition.md` before adding a page, layout, or component.

- Buttons come from `DesignSystem.swift` only (`PrimaryActionButton`, `DestructiveActionButton`,
  `SecondaryActionButton`, `QuietActionButton`, `IconActionButton`). Do not style a `Button` at the call site.
- Compose shared components (`SettingsRow`, `PreferenceRow`, `DefinitionRow`, ...). Do not rebuild a pattern.
- Geometry lives in the component. A screen adds rows, never its own `padding` or `frame`.
- Tokens only: `Spacing`, `Metrics`, `Typography`. No literal numbers next to a view.
- Copy has one source: `CategoryCopy`, `ScanStepCopy`, `AppCopy`, `TweakCopy`. Do not retype it.
- A pattern seen a third time gets extracted, not copied.

## Drive it by selector

Use the accessibility tree, not screenshots or pixel clicks. Build the driver once (the terminal
needs Accessibility permission):

```sh
swiftc -O scripts/axdrv.swift -o /tmp/axdrv
```

Commands: `apps`, `--pid <pid> windows`, `dump [--json|--all] [sel]`, `texts [sel]`, `press <sel>`,
`select <sel>`, `click <sel>`, `frame <sel>`, `activate`, `type <text>`, `key <code> [cmd]`,
`color <sel>|--at x,y`. Target with `--pid`, `--app`, or `AXDRV_PID`. More than one Chet can run:
`pgrep -f chet.app/Contents/MacOS/chet`, then always pass `--pid`.

Selectors are ANDed `key=value` terms (`id=`, `role=`, `desc=`, `enabled=`). A bare term is a
substring match. A selector must match exactly one element; several matches exit 6.
Identifiers are `screen.element` (`.accessibilityIdentifier` next to `.accessibilityLabel`).
List them with `dump`; `python3 scripts/ui_selectors.py --pid <pid> --screen <name>` saves a map
to `docs/ui-selectors.json` (generated, gitignored, do not hand-edit). A tweak row puts
`tweak.details.<tweak id>` on the details control; the `info.circle` description match is
retired there. An app cell puts `apps.select.<id>` on its checkbox; `<id>` is the bundle
identifier, else the app file name, lowercase. Cleaner rows put `cleaner.select.<id>` on
their checkbox and grouped rows and cards put `grouped.select.<id>`; `<id>` is the path
relative to home, lowercase, with dots for `/`. The grouped list and card modes never
render the same item at once.

What costs time:

- Sidebar rows do not take `AXPress`. Use `select`, on the `AXStaticText` id.
- `gate.continue` is `AXLink`, not `AXButton`. Leave the gate with `press id=gate.continue`.
- An identifier on a wrapper overwrites the ids of its children. Put it on the control.
- `press` on a disabled control, or a failed press, exits 0. Check `enabled` first.
- System Events cannot press untitled SwiftUI buttons. Press the identifier.
- Never hard-code coordinates; window position changes. Use `frame`.
- `open -a` reuses a running instance; use `open -n`. For Cmd-, with several instances: `key 43 cmd`.
- A `.env` with `DRY_RUN=1` disables tweak controls. Remove it to test a real write.
- `mise run dev` starts with `pkill -x chet` and ends every instance. During a selector session
  launch by path and kill only your pid. Quit when done: `kill <pid>`.
- Colors: AX has no color. `axdrv color` samples pixels (needs Screen Recording). `axdrv activate`
  first: an inactive window draws different colors. Dark/light check:
  `defaults write id.web.widnyana.chet NSRequiresAquaSystemAppearance -bool YES`, relaunch,
  then `defaults delete` it.

## Another agent in the same tree

Two agents can work in this checkout at once.

- Do not delete, move, or repair a file you did not create. An untracked file that fails to
  compile is the other session's work in progress.
- Verify your own change against a clean snapshot when their WIP breaks `xcodebuild`:

```sh
rm -rf /tmp/verify && mkdir -p /tmp/verify
git archive HEAD | tar -x -C /tmp/verify
cp <each file you changed> /tmp/verify/<same path>
cd /tmp/verify && xcodegen generate --quiet
xcodebuild -project chet.xcodeproj -scheme chet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/verify/.build build
```

- Stage only your own paths. Never `git add -A`.
- `docs/plans` is gitignored; plans there stay local.

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
