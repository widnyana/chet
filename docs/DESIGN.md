# Mackit UI design

Status: canonical design direction.
Detailed references: [design/README.md](design/README.md),
[design/principles.md](design/principles.md),
[design/tokens.md](design/tokens.md),
[design/components.md](design/components.md),
[design/screens.md](design/screens.md),
[design/copy.md](design/copy.md),
[design/references.md](design/references.md).

## The design read

Reading this as: a native macOS utility for people who want to reclaim disk
space, in a quiet paper-and-ink ledger language, dial ENERGY 1 / RHYTHM 2 /
MOTION 1.

Mackit is a ledger for disk space. It shows what is there, what can be
reclaimed, and what will happen when you act. It does not decorate the act of
cleaning. The interface is quiet because the decision is serious.

## Navigation

```
NavigationSplitView
  Sidebar
    Overview
    Clean
      Caches and logs
      Developer build data
      Browser caches
      ...
    Tools
      Applications
      Disk map
  Detail
    one destination at a time
```

- The sidebar is the route. The detail pane shows one destination.
- Applications uses its own `NavigationStack` for the inventory and one app.
- The toolbar carries Scan / Stop on every destination except Applications.
- Applications owns Done, Search, Layout, and Reload.
- There are no mode tabs. Applications is a destination, not a mode.
- About is not a destination. `Mackit > About Mackit` opens one fixed window,
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

## Type

System font, SF Pro. Numbers use `.monospacedDigit()`.

| Token | Size / line | Weight | Use |
|---|---|---|---|
| display | 34 / 40 | semibold | Reclaimable total, app size |
| title | 22 / 28 | semibold | Page title |
| section | 15 / 20 | semibold | Section heading |
| body | 14 / 20 | regular | Paragraphs |
| row | 13 / 18 | regular | Table cells |
| caption | 11 / 14 | regular | Locations, metadata |
| metric | 17 / 22 | medium, tabular | Row size |

No rounded design. No all-caps tracking. No monospace family. The largest text
on a screen is 34 pt.

## Spacing and shape

Base unit 4 pt. Tokens: 4, 8, 12, 16, 24, 32, 40, 48. Page side margin 24 pt at
the minimum window, 32 pt at wide widths. Content max width 880 pt.

Radius:

- 0: pages, sections, tables, command bars.
- 6: native buttons and fields.
- 8: media thumbnails.
- No pill shapes created by the app.

No elevation in the content. Sheets use the system shape and shadow. The command
bar is a real bar with a 1 px top rule, not a floating capsule.

## Motion

160 ms ease-out for the top status strip, 200 ms for a small state change.
Nothing else. No bounce, pulse, float, shimmer, or symbol effect. Respect
Reduce Motion. `ProgressView` is the only continuous motion, and only while a
real operation runs.

## Screen rules

### Overview

One focal point: the reclaimable total and the capacity bar.

Top to bottom:

1. Page header: `Overview`, a one-line subtitle, the reclaimable total.
2. Capacity bar: volume name, capacity, used, reclaimable, free, text legend.
3. Scan state:
   - never scanned: an empty state with `Scan this Mac`;
   - scanning: the phase list and a linear progress;
   - finished: `Reclaimable` and the category ledger.
4. Category ledger: monochrome symbol, name, item count, size. Largest first.
   Clicking a row opens the category.
5. Command bar: Scan, Stop, or Clean selected.

No chart. The ledger is the chart. No uninstall card. Applications is in the
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

### Applications

A searchable inventory: list first, grid second. Every row and cell has a mark
checkbox, name, publisher or bundle ID, location, version, size, and a text
status for running or admin. The command bar appears only when apps are marked.
Opening an app is separate from marking it.

### App detail

Document header: icon, name, bundle ID, path, version, app size. The app bundle
row is the only control that targets the app. Related files are grouped by
component kind and show a plain status label. The command bar reports selected
count and bytes and opens the confirmation.

### Disk map

One encoding: size share as a neutral ramp. Plain breadcrumb, four-step legend,
canvas, hover label. The detailed scan strip lives here and nowhere else. The
map is readable in both modes.

### Snapshots

A date ledger with a checkbox and a text sort control. No size column, because
macOS reports the size only when the snapshot is deleted.

### Settings

A settings page, not a report. Three panes, one question each, selected from the toolbar:
`Scan`, `Sizes`, `Folders`. The window title follows the active pane, the macOS preference
convention. Scan results are not repeated here; the Overview already reports them.

- `Scan`: caption `Rules and folder index always run.`, then the six step switches, then
  `Speed` with `Threads` as a pop-up menu and the caption `Auto uses one thread per core.`
- `Sizes`: sliders `Duplicate size`, `Large file size`, `Old file age`, plus the duplicate
  scope switch `Search caches and build folders`. Labels are nouns; no `at least` and no
  threshold arithmetic in prose.
- `Folders`: `Excluded folders` with the list, a text `Remove`, the empty state
  `No folders are excluded.`, and `Exclude Folder…` opening the native picker; `Your rules`
  with one caption stating the effect, a text `Remove`, `No folder rules yet.`, and
  `Add Folder Rule…`; `Outside your home folder` with one switch.
- A set `DRY_RUN` shows one amber status label above the panes.

Radius 0, hairlines under section headers, no cards, and the accent tints controls only.
Every pane keeps the same shape, header then hairline then the control it needs. That is a
deliberate RHYTHM 1, the System Settings convention, so a reader learns the page once.

### Permission page

A sentence, three plain steps, one primary button, one link, and a native
spinner while checking. No glass card and no pulsing dot.

### About

One fixed 560 x 620 window, opened from `Mackit > About Mackit`. It is a
ledger of app facts, not a landing page and not a system report. The window
title is `About Mackit`; the page header names the app.

Top to bottom:

1. Page header: app icon, `Mackit`, one sentence, the version.
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
- `CommandBar`: full width, top hairline, selection summary, one primary action.
- `StatusLabel`: icon plus text, semantic color, no pill.
- `EmptyState`: title, cause, next action.
- `TopStatusStrip`: access, scan result, dry run. In flow, below the toolbar.
- `AppCell` and `AppRow`: flat surface, hairline, text statuses.
- `OwnershipRow`: checkbox, name, location, plain ownership label.
- `ConfirmationSheet` and `SummarySheet`: ledger sheets, no celebration.
- `CleanProgressSheet`: spinner, item and byte progress, a bordered verbose box
  held for at least 0.45 s so a fast pass cannot flash past
  with items, bytes, freed, skipped, failed, current path, and action.
- `PermissionPage`: plain page, one action.
- `AboutInfoRow` and `AboutPathRow`: label, value or selectable path, optional
  status icon, detail, and secondary action.

Detailed anatomy and states are in [design/components.md](design/components.md).

## Copy

Verb first. Say what will happen. One sentence per idea. No em dash. No
sparkle, magic, AI, seamless, powerful, or revolutionary. No invented numbers
or claims. Empty and error states name the cause and the next action. Full copy
is in [design/copy.md](design/copy.md).

## Anti-slop commitments

- No em dash in app copy or new design documents.
- No sparkle, star, magic, or orb icon.
- No gradient, glow, glass, or shadow as a default.
- No card grid, no bento, no chart that repeats the ledger.
- No pill for every small fact.
- No decorative dot and no endless pulse.
- No invented data.
- No dead controls.
- Every empty, loading, and error state is designed.
- Light and dark mode, keyboard, and 960 x 600 are all checked.

## Rules of thumb

1. Reuse a component. Do not restyle a row in place.
2. A new color, radius, shadow, or motion needs a one-line reason and a token.
3. Anything countable uses tabular digits and a stable column.
4. State lives in the row it belongs to: text plus an icon, never a bare dot.
5. The command bar is always full width and always at the bottom.
6. The primary action is the only accent on the screen.
7. If a screen needs two focal points, the screen is doing two jobs. Split it.
8. The app icon is the only asset with a gradient.

## Layout registry

The registry tracks persistent chrome. It is read by `scripts/layout_check.py`
and `mise run layout`. The redesign removes floating chrome, so the entries are
in-flow or toolbar-level and cannot overlap the content.

Rules the script enforces:

1. Nothing floats over the title bar. No `.overlay(alignment: .top)`.
2. No bottom floating capsule. The command bar is in flow.
3. The top status strip is a safe-area inset, not an overlay.
4. Every chrome entry names a real Swift file and a snippet that exists.

```layout-registry
{
  "window": {"width": 960, "height": 600, "titlebar": 52},
  "chrome": [
    {
      "id": "top-status-strip",
      "file": "Mackit/Views/ContentView.swift",
      "mechanism": "safeAreaInset-top",
      "height": 56,
      "verify": {
        "contains": ["safeAreaInset(edge: .top, spacing: 0) {", "TopStatusStrip()"],
        "not-contains": [".overlay(alignment: .top)"]
      }
    },
    {
      "id": "command-bar",
      "file": "Mackit/Views/CommandBar.swift",
      "mechanism": "in-flow-bottom",
      "height": 52,
      "verify": {"contains": ["struct CommandBar"]}
    },
    {
      "id": "scan-toolbar",
      "file": "Mackit/Views/ScanStatusView.swift",
      "mechanism": "toolbar-inline",
      "height": 28,
      "verify": {"contains": ["struct ScanStatusView"]}
    },
    {
      "id": "disk-map-chrome",
      "file": "Mackit/Views/DiskMapView.swift",
      "mechanism": "in-flow-header",
      "height": 44,
      "verify": {"contains": ["DiskMapChrome"]}
    }
  ]
}
```
