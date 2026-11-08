# Screens

## Navigation map

```
Sidebar
  Overview
  Clean
    <category rows>
  Tools
    Applications
    Disk map
```

The sidebar selection is the route. The detail pane shows one destination. The
Applications destination uses its own `NavigationStack` for the app detail, so
the sidebar does not change while the user moves between the inventory and one
app.

The scan button is in the toolbar on every destination except Applications.
The Applications destination owns its own toolbar: Done, search, layout, reload.

`Mackit > About Mackit` opens a separate fixed window. It is not a sidebar
destination and it does not replace the detail pane.

## Overview

Job: answer "what can I reclaim, and what should I do next?".

Top to bottom:

1. `PageHeader`: title `Overview`, subtitle `A clear account of this disk`,
   metric: the reclaimable total, or `Not measured`.
2. `CapacityBar`: volume name, capacity, three segments, text legend.
3. Scan state:
   - never scanned: a plain `EmptyState` with `Scan this Mac` and a sentence;
   - scanning: `ScanProgressSection`; Pause and Stop live in the command bar;
   - finished: `SectionHeader("Reclaimable")` and the category ledger.
4. Category ledger: one row per category with a monochrome symbol, name, item
   count, and size. The rows are sorted largest first. Clicking a row opens the
   category. No chart.
5. `CommandBar`:
   - no scan: primary `Scan this Mac`;
   - scan running: `Stop scan`;
   - scan finished with a selection: summary and `Clean selected`.

The overview does not contain an uninstall card. Applications is a sidebar
destination.

States:

- Empty (never scanned): capacity bar plus a short message and one action.
- Loading (scanning): progress section plus the categories that have already
  arrived. The ledger grows in place.
- Partial access: the top status strip explains which folders are hidden.
- Error (no readable volume): the capacity bar shows `Capacity unavailable` and
  the action is disabled with a reason.
- Tidy (nothing found): `Nothing to reclaim` and a secondary `Scan again`.

## Category

Job: answer "which entries in this category should I remove?".

Top to bottom:

1. `PageHeader`: category title, subtitle with total size and risk sentence,
   metric: total size. The subtitle for safe data says `Apps rebuild this data.`
   For review data it says `Review each item. Removed items go to the Trash.`
2. `ListHeaderBar`: tri-state select, `N of M selected`, selected bytes, and the
   Select menu (All, None, Invert, Safe items only, Older than 30 days, Larger
   than 100 MB).
3. `LedgerTable`: checkbox, name and location, size, modified, risk.
4. `CommandBar`: selected count and bytes on the left, `Clean` on the right.

For duplicate and similar-media categories, step 3 is `GroupedItemsView`:
groups with the keeper first and the copies after. The keeper has a `Keep`
label in neutral ink, not a green pill. Photo and video groups use a media grid
with flat thumbnails and a checkbox overlay. The command bar is the same.

States:

- Empty: `No entries in this category` and a back link to Overview.
- Loading: the table header remains; rows arrive in place.
- Filtered to nothing: `No entries match this filter` and a clear action.
- Partial access: a row-level lock icon plus the top status strip.

## Snapshots

Job: answer "which Time Machine local snapshots can I remove?".

Top to bottom:

1. `PageHeader`: `Local snapshots`, subtitle with count and the macOS
   limitation that size is reported only on deletion.
2. `LedgerTable`: checkbox, date, relative age, and a `Local` label. There is no
   size column because macOS does not provide one before deletion.
3. `CommandBar`: selected count and `Clean selected`.

The sort control is a small text button in the section header: `Newest first`
or `Oldest first`. No toolbar icon.

States: empty, loading, error from `tmutil` (with the command output in a
disclosure), and partial access.

## Applications

Job: answer "which app should I remove?".

Top to bottom:

1. Toolbar: `Done` (back to Overview), search field, layout picker (list or
   grid), Reload.
2. `PageHeader`: `Applications`, subtitle `N installed, M marked`.
3. Inventory:
   - list: header row and rows with checkbox, icon, name and bundle ID,
     location, version, size, status;
   - grid: flat cells with checkbox, icon, name, publisher, size and location.
4. `CommandBar` when at least one app is marked: marked count and bytes, `Clear`,
   `Remove`.
5. During a bulk pass: the command bar becomes `Removing 3 of 7` with the
   current app name, and the inventory stays interactive.

The list is the default. The grid is for visual recognition. The choice persists
in `UserDefaults`.

States:

- Loading: `Reading applications` and a flat skeleton in the chosen layout.
- Empty: `No applications found` with a `Full Disk Access` action when access is
  the likely cause, or `Reload` otherwise.
- Filtered empty: `No application matches "query"` and a `Clear search` action.
- Running app: `Running` status label. The app can still be marked, but the
  confirmation and the core skip it.
- Admin-only app: `Needs administrator` status label with a lock.

## App detail

Job: answer "what belongs to this app, and what will move?".

Top to bottom:

1. `PageHeader`: 44 pt app icon, app name, bundle ID and path as the subtitle,
   metric: the app bundle size. A `Version` caption and a `Reveal in Finder`
   secondary button.
2. If running: an amber `StatusLabel` with `Quit the app before removing it`.
   If admin-only: an amber `StatusLabel` with the restriction.
3. App bundle row: checkbox `Remove app bundle`, size, and a note that it is the
   only row that targets the app itself.
4. Related files: `SectionHeader` with `Exact matches only`, `All selectable`,
   `None`; then grouped `OwnershipRow` sections by component kind.
5. `CommandBar`: selected count and bytes, `Remove`.

States:

- Loading: `Looking for related files` with a native spinner; the header is
  already visible.
- Empty: `No related files` with the Full Disk Access explanation when relevant.
- Running: remove disabled; the status line says to quit the app.
- Admin-only: the app bundle row disabled; related user files may still be
  removable.
- Dry run: the confirmation and summary say `would be moved`.

## Disk map

Job: answer "where is the space?".

Top to bottom:

1. `DiskMapChrome`: breadcrumb and a neutral-ramp legend, hairline.
2. Treemap canvas.
3. While scanning: the detailed scan strip: phase, linear progress, current
   folder, files and bytes, folder trail, Pause and Stop.
4. Empty (never scanned): `Scan this Mac to see where the space is` with a
   primary scan action.
5. Hover: a plain label with folder name and size.
6. Click: zoom into a folder. Right-click: Reveal in Finder.

The map uses one encoding: size share as a neutral ramp. Darker means a larger
share in light mode; lighter means a larger share in dark mode. The labels use
the ink that contrasts with the block. The map does not encode categories.

## Settings

Job: answer "which duplicate scope do I want?".

One grouped form section:

```
Include caches and build folders                 [toggle]
Search inside caches and project build folders. Off by default.
```

No other options. The window title is `Settings`.

## About

Job: answer "which build is running, whether access is granted, and where are
the logs?".

`Mackit > About Mackit` opens one fixed 560 x 680 window. It is independent of
the main window and can stay open during a scan.

Top to bottom:

1. `PageHeader`: app icon, `Mackit`, the one-sentence product line, metric: the
   version.
2. `This build`: build, bundle ID, architecture, minimum macOS.
3. `Status`: Full Disk Access with `Granted` or the amber `Not granted` plus
   `Open Settings`; last scan with its byte total and date.
4. `Logs`: audit log path with `Show` when it exists; logs folder with `Open`.

The window does not inventory the machine. No model, chip, memory, disk, or GPU
rows.

States:

- Loading: header plus `Reading this build`; no fake values.
- Partial: a missing build key says `Unknown`; other rows render.
- Empty: `No scan yet`, `No log yet`; the missing action is removed, not dead.
- Denied access: amber status, one sentence, `Open Settings`.
- Long paths truncate in the middle with the full path in the tooltip.

## Permission page

Job: get Full Disk Access or let the user continue honestly.

Top to bottom:

1. Title: `Mackit needs access to the folders it measures`.
2. One paragraph: what macOS hides and why the app needs it.
3. Three plain rows: open Privacy & Security, turn on Mackit under Full Disk
   Access, come back here. Numbers in `inkSecondary`, no circles.
4. Primary `Open System Settings`.
5. Link `Continue without access`.
6. Waiting state: native spinner and `Checking for access`.

The page polls the access probe and dismisses itself when access lands. It does
not pulse.

## Clean flow: confirmation, progress, summary

The clean flow is one sheet with three states, in order:

1. **Confirmation** repeats the count, categories, permanent versus trashed
   bytes, and the dry-run notice.
2. **Progress** starts as soon as the user confirms. It shows a spinner, an item
   bar, and a bordered box with items, bytes plus a byte bar, freed bytes,
   skipped and failed counts, and the current path with its action. Interactive
   dismissal is disabled while cleaning.
3. **Summary** replaces the progress box when the pass ends. It reports what
   was cleaned and lists skipped or failed items.

The confirmation and summary sheets follow the component specs. They never
claim success before the operation completes. The dry-run state changes every
verb. The Applications uninstall sheets use the same sheet grammar and width;
they do not use this clean progress.

## Error and partial states

- Top status strip for a global condition: limited access, dry run, scan result.
- Inline status label for a row condition: running, admin, protected.
- Empty state for no data: cause plus next action.
- Error state for a failed operation: cause, retry, and the audit log link.
- Never show a zero as if it were a measured result. Show `Not measured`,
  `Unavailable`, or no value.
