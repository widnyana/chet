# Developing Chet

Notes for working on the app. The design rules are in `docs/DESIGN.md`, the architecture is
in `README.md`. This file covers how to run and drive the app while you change it.

## Run it

```sh
mise run dev      # build, one LaunchServices registration, open the debug app
mise run test     # ChetCore tests
mise run lint     # format check
```

The main window remembers its frame. Keep it at `960 x 632`, the supported minimum, instead
of full screen. The design is checked at that size.

## The first screen is the permission gate

`ContentView` shows only `OnboardingView` while Full Disk Access is denied and the user has
not skipped it. There is no sidebar and no toolbar on that screen.

Two exits:

- **Open System Settings** opens the pane and leaves the app on the gate. macOS expects a
  restart after the grant, so the gate is normal even right after granting.
- **Continue with limited results** sets `accessSkipped`, which lasts one launch. The gate
  returns on the next start until access is granted.

Any UI run that assumes a sidebar has to click through the gate first, or grant Full Disk
Access and restart. A rebuild also changes the code signature, so a fresh build can land on
the gate again.

Status strip precedence: `DryRun.enabled` wins over the access banner. With `DRY_RUN=1` in
`.env`, Home shows `Preview only. No files will be moved.` and never `Limited access`.
Remove the flag to see the access banner.

## Drive it by selector

Screenshots and pixel clicks are slow and brittle. The app exposes accessibility identifiers,
and `scripts/axdrv.swift` reads the accessibility tree directly.

```sh
swiftc -O scripts/axdrv.swift -o /tmp/axdrv
```

The terminal running it needs Accessibility permission. The tool prints `AX NOT TRUSTED` and
exits if it does not have it.

| Command | What it does |
|---|---|
| `/tmp/axdrv texts` | prints every static text on screen |
| `/tmp/axdrv dump` | prints role, identifier, title, value for every element |
| `/tmp/axdrv press gate.continue` | performs `AXPress` on the element with that identifier |
| `/tmp/axdrv clickid apps.header` | posts a real mouse click at that element's center |
| `/tmp/axdrv click Apps` | posts a real mouse click on the element with that exact text value |

`press` is the right choice for buttons that keep their identifier. `click` covers anything
that does not: SwiftUI `List` rows wrap their content, so a sidebar row identifier lands on a
child the driver cannot press. Clicking the row's text value works.

Do not drive the app with AppleScript's `entire contents`. For this app it returns an empty
list, which looks exactly like a screen with no elements. The AX API behind `axdrv` returns
the full tree, around 230 elements on Home.

### Identifiers in place

| Identifier | Element |
|---|---|
| `gate.title`, `gate.openSettings`, `gate.continue` | permission screen |
| `sidebar.<category id>`, `sidebar.apps`, `sidebar.storage`, `sidebar.home` | sidebar rows |
| `toolbar.scan`, `toolbar.scanStop` | toolbar scan control |
| `home.header`, `home.empty` | Home |
| `apps.header` | Apps |
| `storage.header` | Storage |
| `settings.tabs` | Settings pane switcher |

Add a new one with `.accessibilityIdentifier("screen.thing")` on the control, next to its
`.accessibilityLabel`. Name it `screen.element`, lowercase, one dot.

### Recipe

```sh
open .build/xc/Build/Products/Debug/chet.app && sleep 5
/tmp/axdrv press gate.continue          # leave the permission gate
sleep 2
/tmp/axdrv texts | grep "Clean up your Mac"
/tmp/axdrv click Apps                   # sidebar row, click by text
sleep 2
/tmp/axdrv texts | head -18             # app rows: name, vendor, size
/tmp/axdrv click Home
osascript -e 'tell application "chet" to quit'
```

Quit with `osascript -e 'tell application "chet" to quit'` after the last assertion. Leaving
the window open blocks whoever else shares the machine.
