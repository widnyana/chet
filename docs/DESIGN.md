# Chet UI design

Status: canonical design direction.
Detailed references: [design/README.md](design/README.md),
[design/principles.md](design/principles.md),
[design/tokens.md](design/tokens.md),
[design/components.md](design/components.md),
[design/screens.md](design/screens.md),
[design/copy.md](design/copy.md),
[design/references.md](design/references.md),
[design/composition.md](design/composition.md),
[design/ui-guidelines.md](design/ui-guidelines.md).

## The design read

Reading this as: a native macOS utility for people who want to reclaim disk
space, in a quiet paper-and-ink ledger language, dial ENERGY 1 / RHYTHM 2 /
MOTION 1.

Chet is a ledger for disk space. It shows what is there, what can be
reclaimed, and what will happen when you act. It does not decorate the act of
cleaning. The interface is quiet because the decision is serious.

## Navigation

```
NavigationSplitView
  Sidebar
    Home
    Safe to remove
      App caches
      Logs
      Xcode files
      ...
    Check first
      Duplicate files
      Large files
      ...
    Configure
      Tweaks
    Tools
      Apps
      Homebrew
      Storage
  Detail
    one destination at a time
```

- The sidebar is the route. The detail pane shows one destination.
- Apps uses its own `NavigationStack` for the inventory and one app.
- The toolbar carries Scan / Stop on every destination except Home, Apps,
  Homebrew, and Tweaks.
- Apps owns Search, Layout, and Reload. Homebrew owns Search and Reload.
  Tweaks owns Search and Read again.
- Tools has three destinations: Apps, Homebrew, and Storage. Configure has one,
  Tweaks.
- There are no mode tabs. Apps is a destination, not a mode.
- About is not a destination. `Chet > About Chet` opens one fixed window,
  separate from the main window.

## Visual language

Paper and ink, one accent, hairlines, tabular numbers.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#F6F4EF` | `#121316` | Content background |
| `paperRaised` | `#FCFBF8` | `#191B1E` | Table header, inset, sheet body |
| `ink` | `#1B1C1E` | `#F2F0EA` | Primary text |
| `inkSecondary` | `#63635F` | `#A3A19A` | Supporting text |
| `inkTertiary` | `#8B8A83` | `#74746F` | Disabled text |
| `hairline` | `#DDD9D0` | `#2C2E32` | 1 px rules |
| `accent` | `#244C9A` | `#8FA8E8` | Action, selection, focus, reclaimable |
| `accentSoft` | `#E8EDF8` | `#1B2436` | Selected row |
| `onAccent` | `#FFFFFF` | `#101114` | Text on accent |
| `amber` | `#9A5B00` | `#E0A458` | Review, running, attention |
| `red` | `#A3231B` | `#F08A82` | Destructive, protected |
| `capacityUsed` | `#D6D2C8` | `#3A3C41` | Used segment |
| `capacityFree` | `#E9E6DE` | `#222428` | Free segment |

Rules:

- No category colors. Category identity is a monochrome SF Symbol and a name.
- No green. A safe state is a neutral checkmark and plain text.
- No gradient in the content. The app icon is the only gradient asset.
- No custom glass, no custom shadow, no glow.
- The native sidebar material and system sheets are the only materials.
- Every colour value lives in `Chet/Views/Palette.swift`: the `Theme` tokens,
  the map label colours, and the treemap ramp. No other file builds a colour
  from an `NSColor`, `Color`, or `SIMD4` literal.

## Type

System font, SF Pro. Numbers use `.monospacedDigit()`.

| Token | Size | Weight | Use |
|---|---|---|---|
| display | 34 | semibold | Reclaimable total, app size |
| title | 24 | semibold | Page title |
| section | 16 | semibold | Section heading |
| body | 15 | regular | Paragraphs |
| row | 14 | regular | Table cells |
| caption | 12 | regular | Locations, metadata |
| metric | 18 | medium, tabular | Selection total, page header |

No rounded design. No all-caps tracking. No monospace family. The largest text
on a screen is 34 pt. Caption is the smallest text at 12 pt. Use the system
leading; do not set `lineSpacing` or a custom line height.

## Spacing and shape

Base unit 4 pt. Layout spacing uses 4, 8, 12, 16, 24, 32, 40, 48. Inside a
single component, 0, 1, and 2 are allowed for hairline alignment and optical
pairs; they are never page rhythm. Page side margin is 24 pt at the minimum
window, 32 pt at wide widths. The minimum window is 960 x 632. Content max
width 880 pt.

Radius:

- 0: pages, sections, tables, command bars.
- 6: native buttons and fields.
- 8: media thumbnails and Settings panels.
- No pill shapes created by the app.

No elevation in the content. Sheets use the system shape and shadow. The command
bar is a real bar with a 1 px top rule, not a floating capsule.

## Motion

160 ms ease-out for the top status strip, 200 ms for a small state change.
Nothing else. No bounce, pulse, float, shimmer, or symbol effect. Respect
Reduce Motion. `ProgressView` is the only continuous motion, and only while a
real operation runs.

## Screen rules

### Home

One focal point: the reclaimable total and the capacity bar.

Top to bottom:

1. Page header: `Clean up your Mac`, a one-line subtitle, the amount that can be reclaimed.
2. Capacity bar: volume name, capacity, used, reclaimable, free, text legend.
3. Scan state:
   - never scanned: an empty state, `No scan yet`, with the action in the
     command bar;
   - scanning: the phase list and a linear progress;
   - finished: the category ledger in two groups, `Safe to remove` and
     `Check first`.
4. Category ledger: monochrome symbol, name, item count, size. Largest first.
   Clicking a row opens the category.
5. Command bar: `Scan this Mac`, `Scan again`, `Stop scan`, or `Clean selected` with
   `Scan again` beside it, one primary per state.

No chart. The ledger is the chart. No uninstall card. Apps is in the
sidebar.

### Category

Page header with the category total and the risk sentence. Then the selection
header, the ledger table, and the command bar. Safe data says `Apps rebuild this
data.` Review data says `Review each item. Removed items go to the Trash.`

### Clean progress

The clean flow is one sheet, not three separate sheets:

1. **Confirm** shows what will move and what will be deleted.
2. **Progress** replaces the confirm content as soon as `isCleaning` is true.
3. **Summary** replaces the progress content when `isCleaning` is false and the
   report exists.

The progress surface has a loading indicator on top and a bordered details box
below it:

```
[spinner] Cleaning                     42%
Item 12 of 34
[================== linear progress ==================]

+-----------------------------------------------------+
| Items      11 of 34                                 |
| Bytes      2.4 GB of 10.4 GB                        |
| [============== byte progress ==============]       |
| Freed      2.3 GB                                   |
| Skipped    1                                        |
| Current    ~/Library/Caches/com.example.app/...     |
|            Folder - Deleting - 18 MB                |
+-----------------------------------------------------+

Each item is checked again before it is removed. An item can be a file or a folder.
```

Rules:

- The count and byte progress use the same `CleanProgress` sample. They cannot
  disagree.
- The current row names the item being processed and the action: deleting or
  moving to Trash. It also says whether the item is a file or a folder.
- Dry run changes the title to `Simulating clean`, `Freed` to `Would free`, the
  current action to `Would delete` or `Would move to Trash`, and the skipped and
  failed labels to `Would skip` and `Would fail`.
- The sheet cannot be dismissed while cleaning. The summary is the exit.
- The box is a temporary operation panel, not a card in the normal surface
  language. It exists because the operation is a foreground, destructive task.
- No per-item animation. The linear bars and the current path update in place.

### Tweaks

A preference list, not a card grid. The page answers what a setting does, what it
is now, and how to put it back.

1. Page header: `Tweaks`, one sentence, no metric.
2. Filter row: `All` / `Changed`, the visible count, `Read again`.
3. Gate: a set `DRY_RUN` shows `Preview only. No tweak is changed.` and disables
   every control. The states stay readable.
4. Sections by part of macOS: Finder, Dock, Keyboard, Screenshots, Appearance,
   Windows. The section header carries the row count.
5. A row is `PreferenceRow`: name, one-line explanation, current value and impact,
   notes (`Restart Finder`), the control, and an info button. Hairlines, not cards.
6. The details sheet shows the explanation, current state, impact, risk, when it
   applies, the preference key, the last recorded change, and `Reset to Default`,
   `Revert last change`, a restart when pending, and `Turn On` / `Turn Off`.

The catalog is plain data in `TweakCatalog`; every entry is one preference key or
one file flag. `TweakEngine` reads, writes, verifies by reading back, restores on a
failed verification, and records to `~/Library/Application Support/Chet/tweaks.log`.
An unknown value is shown with its reason and is never drawn as Off.

### Apps

A searchable inventory: list first, grid second. Every row and cell has a mark
checkbox, name, publisher or bundle ID, location, version, size, and a text
status for running or admin. The command bar is present on the screen and
disabled until an app is marked. Opening an app is separate from marking it.

### Homebrew

A searchable inventory of installed Homebrew packages. No scan control; the
page owns Reload. Page header `Homebrew`, subtitle `N packages, M marked`.
Rows carry a checkbox, a package icon, package name, kind (formula or cask),
version, size, and status. The columns use the same widths as Apps so the two
inventories align. The command bar is disabled until a package is
marked, then reports marked count and `Uninstall`. The confirmation sheet uses
the same grammar and 520 pt width as the app sheets. A `brew` read failure is an
error state with a retry, never an empty list. The dry-run gate on this page is
`Preview only. Nothing will be removed.` The action menu's `Remove old versions…`
opens a 520 pt sheet that lists `Old package versions` and `Download cache`, with
Cancel as the default and a red `Remove`.

### App detail

Document header: icon, name, bundle ID, path, version, app size. The app bundle
row is the only control that targets the app. Related files are grouped by
component kind and show a plain status label. The command bar reports selected
count and bytes and opens the confirmation.

### Storage

Job: read the folder map, collect what should go, and move it to the Trash.

Top to bottom:

1. Page header: `Storage`, `Where your space goes.`, the current folder size.
2. Location bar: `Home` crumb, the path, the volume line `Used X of Y`, and
   `Size on disk` when the tree measured allocated bytes.
3. Metric row: three flat blocks separated by hairlines, `Free space`,
   `Cleanable`, `Large files`. No card fills. `Cleanable` opens Home, `Large
   files` opens that category, and before a scan each block offers the scan.
4. Body: treemap canvas and a 288 pt child ledger.
5. Command bar: collected bytes, the count and the gesture hint, `Clear`, and
   `Move to Trash...`.

One encoding: size share as a neutral ramp. The ledger swatch uses the same
ramp value as its block, so chart and list read as one surface. A collected
block carries the accent border; the hovered block carries an ink border. No
category colours, in any state.

Click a block to open that folder. Collection is the ledger checkbox, or
`Collect` in the block's context menu. A ledger row with children carries a
chevron that opens it. The same collection survives drill-down, and the map,
the ledger, and the bar never disagree.

The breadcrumb keeps one button per ancestor, `Home` first. Clicking a crumb
returns to that folder and removes the deeper entries from the path.

Moving to the Trash is the only destructive action here. It confirms first, it
re-checks every path through `SafetyPolicy` and the app-folder allow-list, and
after the move the screen asks for a rescan instead of inventing new sizes.

The detailed scan strip stays at the bottom of the page while a scan runs. The
map is readable in both modes.

### Snapshots

A date ledger with a checkbox and a text sort control. No size column, because
macOS reports the size only when the snapshot is deleted.

### Settings

A settings window in the macOS preference shape: a system `TabView` with an icon and a word
per pane, then grouped panels on `paperRaised` with the label on the left and its control on
the right. The window is fixed at 560 x 560. The words are for someone who has never opened
a terminal: no cache jargon, no "duplicate scope".

- `What to find` tab: panel `What to look for` with the note `Chet always checks the usual
  places and measures your folders.`, then the six optional checks as switches. Panel `Speed`
  holds `Threads` as a pop-up with the note `Auto uses one thread per core.`
- `Limits` tab: panel `Duplicate files` with `Smallest file to compare` and the switch
  `Look inside temporary app files`, panel `Large files` with `Large file size`, panel
  `Old files` with `Unchanged for`. Every note states the effect in one line.
- `Folders` tab: panel `Folders Chet should not touch` with `Skip a Folder…`, panel
  `Folders you want checked` with `Add a Folder…` and a per-folder `Keep…` button that marks
  items the scan must never remove (shown as `Keeping N items`), panel `Other disks`. Empty
  states `No folders are skipped.` and `No folders added yet.`
- `Tweaks` tab: panel `Changes Chet made` with the count of preferences that differ from the
  macOS default and the change record path with `Show`; panel `Reset` with `Reset All…`, which
  asks once and puts every changed tweak back. The pane reads the same `TweaksModel` as the
  Tweaks page, so the count cannot disagree.
- A set `DRY_RUN` shows one amber label above the panes: `Preview only. Nothing will be
  removed.`

Panels are the app's only raised surface: radius 8, `paperRaised`, hairline border. Every
other page stays flat, so Settings cannot be mistaken for a second Home.

Inside a pane the row shape repeats, because a preference list is scanned, not read. One grid
owns that shape: a 40 pt minimum row height, 8 pt of vertical padding per row, a 4 pt gap
between a label and its detail, and a control column sized by the widest control in the panel.
A rule between rows, and any note, spans both columns. Rows never set their own padding, so a
pane cannot drift into an uneven rhythm.

### Permission page

A sentence, three plain steps, one primary button, one link, and a native
spinner while checking. No glass card and no pulsing dot.

### About

One fixed 560 x 620 window, opened from `Chet > About Chet`. It is a
ledger of app facts, not a landing page and not a system report. The window
title is `About Chet`; the page header names the app.

Top to bottom:

1. Page header: app icon, `Chet`, one sentence, the version.
2. This build: build number, minimum macOS.
3. Status: Full Disk Access with `Open Settings` when denied, last scan.
4. Logs: selectable audit log and logs folder paths with `Show` and `Open`.

Rules:

- Every missing read says `Unknown`. Never a zero standing in for a value.
- The window reads the app bundle and its own log paths only. It does not
  inventory the machine.
- Paths truncate in the middle and keep the full path in the tooltip.
- No animation. The only motion is the native spinner while the build facts
  load.

## Components

- `PageHeader`: title, subtitle, optional metric, hairline.
- `SectionHeader`: sentence-case title, optional text action, hairline.
- `CapacityBar`: used, reclaimable, free, text legend.
- `LedgerTable`: checkbox, name and location, size, modified, risk.
- `CommandBar`: full width, native Liquid Glass bar, selection summary, one primary action.
- `StatusLabel`: icon plus text, semantic color, no pill.
- `EmptyState`: title, cause, next action.
- `PageScreen`: one page frame. Margin, header position, scroll rhythm, bottom bar.
- `TopStatusStrip`: access and scan result. In flow, below the toolbar. Dry run is
  one line at the foot of the page frame, not a strip.
- `AppCell` and `AppRow`: flat surface, hairline, text statuses.
- `OwnershipRow`: checkbox, name, location, plain ownership label.
- `ConfirmationSheet` and `SummarySheet`: ledger sheets, no celebration.
- `CleanProgressSheet`: spinner, item and byte progress, a bordered verbose box
  held for at least 0.45 s so a fast pass cannot flash past
  with items, bytes, freed, skipped, failed, current path, and action.
- `PermissionPage`: plain page, one action.
- `AboutInfoRow` and `AboutPathRow`: label, value or selectable path, optional
  status icon, detail, and secondary action.
- `PreferenceRow` and `DefinitionRow`: the preference list row and the detail sheet's
  label/value row. Geometry lives in the component.
- `SettingsPanel`, `SettingsRow`, `SettingsActionRow`, `SettingsNote`,
  `SettingsDivider`: the settings pattern. `SettingsGrid` owns the row height and the row
  padding, and each panel's `Grid` sizes the control column. No pane styles a row.

Detailed anatomy and states are in [design/components.md](design/components.md).

Components own their geometry. A screen composes them and passes content and
variants; it does not wrap a row in its own padding to fix a look. A component
that needs different spacing gets a token or a parameter, and the change lands
for every use at once.

## Copy

Verb first. Say what will happen. One sentence per idea. No em dash. No
sparkle, magic, AI, seamless, powerful, or revolutionary. No invented numbers
or claims. Empty and error states name the cause and the next action.

Each noun has one source in code: `CategoryCopy` for category names and
reasons, `ScanStepCopy` for scan steps, `AppCopy` for app parts, ownership, and
skip reasons, `TweakCopy` for tweak state, risk, restart, and history words.
A view shows those strings; it does not retype them.

Full copy is in [design/copy.md](design/copy.md).

## Anti-slop commitments

- No em dash in app copy or new design documents.
- No sparkle, star, magic, or orb icon.
- No custom gradient, glow, glass, or shadow. System Liquid Glass on chrome is the only material.
- No card grid for content pages. The Apps inventory grid is the documented exception.
- No bento, no card per preference, no chart that repeats the ledger.
- No pill for every small fact.
- No decorative dot and no endless pulse.
- No invented data.
- No dead controls.
- Every empty, loading, and error state is designed.
- Light and dark mode, keyboard, and 960 x 632 are all checked.

## Rules of thumb

1. Reuse a component. Do not restyle a row in place.
2. Geometry belongs to the component. Row height, padding, and column width
   live in one grid, never at a call site.
3. A new color, radius, shadow, or motion needs a one-line reason and a token.
4. Anything countable uses tabular digits and a stable column.
5. State lives in the row it belongs to: text plus an icon, never a bare dot.
6. The command bar is always full width and always at the bottom.
7. The primary action is the only accent on the screen.
8. If a screen needs two focal points, the screen is doing two jobs. Split it.
9. The app icon is the only asset with a gradient.

## Layout registry

The registry tracks persistent chrome. It is read by `scripts/layout_check.py`
and `mise run layout`. The redesign removes floating chrome, so the entries are
in-flow or toolbar-level and cannot overlap the content.

The registry holds six entries: `top-status-strip`, `command-bar`, `scan-toolbar`,
`storage-location-bar`, `storage-metrics-row`, and `storage-ledger`. Measured at the
960 x 632 minimum, the window frame is 960 x 684 points with the 52 pt titlebar, and
the limited-access strip is present.

Rules the script enforces:

1. Nothing floats over the title bar. No `.overlay(alignment: .top)`.
2. No bottom floating capsule. The command bar is in flow.
3. The top status strip is a safe-area inset, not an overlay.
4. Every chrome entry names a real Swift file and a snippet that exists.

```layout-registry
{
  "window": {"width": 960, "height": 632, "titlebar": 52},
  "chrome": [
    {
      "id": "top-status-strip",
      "file": "Chet/Views/DesignSystem.swift",
      "mechanism": "safeAreaInset-top",
      "height": 56,
      "verify": {
        "contains": ["glassEffect(.regular, in: .rect(cornerRadius: 0))", "struct StatusStrip"],
        "not-contains": [".overlay(alignment: .top)"]
      }
    },
    {
      "id": "command-bar",
      "file": "Chet/Views/CommandBar.swift",
      "mechanism": "in-flow-bottom",
      "height": 52,
      "verify": {"contains": ["struct CommandBar", "GlassBar"]}
    },
    {
      "id": "scan-toolbar",
      "file": "Chet/Views/ScanStatusView.swift",
      "mechanism": "toolbar-inline",
      "height": 40,
      "verify": {"contains": ["struct ScanStatusView"]}
    },
    {
      "id": "storage-location-bar",
      "file": "Chet/Views/StorageComponents.swift",
      "mechanism": "in-flow-header",
      "height": 32,
      "verify": {"contains": ["StorageLocationBar"]}
    },
    {
      "id": "storage-metrics-row",
      "file": "Chet/Views/StorageComponents.swift",
      "mechanism": "in-flow",
      "height": 72,
      "verify": {"contains": ["StorageMetricsRow"]}
    },
    {
      "id": "storage-ledger",
      "file": "Chet/Views/StorageComponents.swift",
      "mechanism": "in-flow-side-pane",
      "height": 0,
      "verify": {"contains": ["StorageLedger"]}
    }
  ]
}
```
