# Screens

## Navigation map

```
Sidebar
  Home
  Safe to remove
    <category rows>
  Check first
    <category rows>
  Configure
    Tweaks
  Tools
    Apps
    Homebrew
    Storage
```

The sidebar selection is the route. The detail pane shows one destination. The
Apps destination uses its own `NavigationStack` for the app detail, so the
sidebar does not change while the user moves between the inventory and one
app.

The scan button is in the toolbar on every destination except Home, Apps,
Homebrew, and Tweaks. Home owns the scan action in its command bar. The Apps
destination owns its own toolbar: search, layout, reload. Homebrew owns
search and Reload. Tweaks uses the toolbar search field only.

`Chet > About Chet` opens a separate fixed window. It is not a sidebar
destination and it does not replace the detail pane.

## Home

Job: answer "what can I reclaim, and what should I do next?".

Top to bottom:

1. `PageHeader`: title `Clean up your Mac`; subtitle `A clear account of this
   disk` before the first scan, `N categories. Pick one to review.` after a
   scan; metric: the reclaimable total, or `Not measured`.
2. `CapacityBar`: volume name, capacity, three segments, text legend.
3. Scan state:
   - never scanned: a plain `EmptyState` with `No scan yet` and a sentence; the
     command bar carries `Scan this Mac`;
   - scanning: `ScanProgressSection`; Pause and Stop live in the command bar;
   - finished: `SectionHeader("Safe to remove")` and `SectionHeader("Check first")`, each over its category rows.
4. Category ledger: one row per category with a monochrome symbol, name, item
   count, and size, in those two groups. The rows are sorted largest first.
   Clicking a row opens the category. No chart.
5. `CommandBar`:
   - never scanned: primary `Scan this Mac`;
   - scan running: `Stop scan`;
   - scan finished with a selection: summary, `Clean selected` as the primary, and
     `Scan again` beside it, so a settings change never strands the user on stale
     results;
   - scan finished with nothing selected: `Scan again`.

Home does not contain an uninstall card. Apps is a sidebar destination.

States:

- Empty (never scanned): capacity bar plus a short message; the command bar
  carries `Scan this Mac`.
- Loading (scanning): progress section plus the categories that have already
  arrived. The ledger grows in place.
- Partial access: the top status strip explains which folders are hidden.
- Error (no readable volume): the capacity bar shows `Capacity unavailable` and
  the action is disabled with a reason.
- Tidy (nothing found): `Nothing to reclaim`; the command bar carries `Scan
  again`.

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

- Empty: `No entries in this category` and a back link to Home.
- Loading: the table header remains; rows arrive in place.
- Filtered to nothing: `No entries match this filter` and a clear action.
- Partial access: the amber strip inside the page, the top status strip, and the
  lock on the sidebar row. Readable rows carry no lock mark.

## Snapshots

Job: answer "which Time Machine local snapshots can I remove?".

Top to bottom:

1. `PageHeader`: `Local snapshots`, subtitle
   `macOS reports size only when deleted.`, metric: the snapshot count.
2. `LedgerTable`: checkbox, date, relative age, and a `Local` label. There is no
   size column because macOS does not provide one before deletion.
3. `CommandBar`: selected count and `Clean selected`.

The sort control is a small text button in the section header: `Newest first`
or `Oldest first`. No toolbar icon.

States: empty, loading, error from `tmutil` with a retry action (the raw command
output stays in a disclosure), and partial access.

## Apps

Job: answer "which app should I remove?".

Top to bottom:

1. Toolbar: search field, layout picker (list or grid), Reload.
2. `PageHeader`: `Apps`, subtitle `N installed, M marked`.
3. Inventory:
   - list: header row and rows with checkbox, icon, name and bundle ID,
     location, version, size, status;
   - grid: flat cells with checkbox, icon, name, publisher, size and location.
4. `CommandBar`: present on the screen, disabled until an app is marked; then
   marked count and bytes, `Clear`, `Remove`.
5. During a bulk pass: the command bar becomes `Removing 3 of 7` with the
   current app name, its primary control disabled, and the inventory stays
   interactive.

The list is the default. The grid is for visual recognition. The choice persists
in `UserDefaults`.

States:

- Loading: `Reading applications` with a native spinner.
- Empty: `No applications found` with a `Full Disk Access` action when access is
  the likely cause, or `Reload` otherwise.
- Error: the applications folder could not be read. Show the cause sentence and
  `Reload` or `Open System Settings`. Never render a read failure as an empty
  inventory.
- Filtered empty: `No application matches "query"` and a `Clear search` action.
- Running app: `Running` status label. The app can still be marked, but the
  confirmation and the core skip it.
- Admin-only app: `Needs administrator` status label with a lock.

## Homebrew

Job: answer "which Homebrew package should I remove?".

Top to bottom:

1. Toolbar: `Search packages` (filters the installed inventory), `Reload`,
   `Install packages…`, and the action menu. No scan control. The install sheet
   carries its own `Search formulae and casks`, which searches the catalog.
2. `PageHeader`: `Homebrew`, subtitle `N packages, M marked`.
3. Inventory: checkbox, 22 pt package icon, package name, kind (`formula` or
   `cask`), version, size, and status. Columns use the Apps widths. The list is
   the only layout.
4. `CommandBar`: present and disabled until a package is marked; then the marked
   count and bytes, `Deselect`, and `Uninstall`.
5. The uninstall confirmation uses the same grammar and 520 pt width as the app
   uninstall sheet.
6. `Remove old versions…` in the action menu opens a 520 pt sheet listing
   `Old package versions` and `Download cache`, with Cancel as the default and a
   red `Remove`.

States:

- Loading: `Reading Homebrew packages` with a native spinner.
- Empty: `No Homebrew packages` and `Reload`. This is different from "brew is
  not installed"; that state names `brew` and opens Homebrew's site.
- Error: the `brew` read failed. Name the failing command and offer `Reload`.
- Outdated packages: a text label `Outdated`, never a colored pill.
- Dry run: the top status strip shows `Preview only. Nothing will be removed.`
  The install sheet keeps `Preview only. Nothing will be installed.`

## App detail

Job: answer "what belongs to this app, and what will move?".

Top to bottom:

1. `PageHeader`: 44 pt app icon, app name, subtitle `Version X, bundle ID`,
   metric: the app bundle size. The path is a separate selectable row. A
   `Reveal in Finder` secondary button sits with the path.
2. If running: an amber `StatusLabel` `Running`, then one sentence: `Quit the
   app before removing it`. If admin-only: `Needs administrator`, then
   `Chet cannot move this app.`
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

## Storage

Job: answer "which child of this folder is using the space, and what will I
move?".

Top to bottom:

1. `PageHeader`: `Storage`, subtitle `Where your space goes.`, metric: the
   current folder size with `in this folder` when one is open.
2. `StorageLocationBar`: `Home` crumb, the path, the volume line
   `Used 236 GB of 245 GB`, and `Size on disk` when the tree measured allocated
   bytes. `Capacity unavailable` when the volume cannot be read.
3. `StorageMetricsRow`: three flat blocks. `Free space` shows the free bytes and
   `N% used`. `Cleanable` shows `model.totalBytes` after a scan and links to
   Home; before a scan it shows `-` and `Scan for junk`. `Large files` shows the
   large-files category bytes and count and links to that category; before a
   scan it offers `Scan to measure`.
4. Body: treemap canvas and `StorageLedger`.
5. While scanning: the detailed scan strip: phase, linear progress, current
   folder, files and bytes, folder trail, Pause and Stop.
6. Empty (never scanned): `The disk map appears after a scan.` with a primary
   scan action.
7. Hover: a plain label with folder name and size, and the ledger row uses
   `accentSoft`.
8. Click a block: open that folder. Right-click: `Collect` or
   `Reveal in Finder`.
9. `CommandBar`: collected bytes, count and the hint, `Clear`, and
   `Move to Trash...`.

`StorageLedger` is 288 pt wide, with a header of folder name, size, path, and
child count, then one row per child sorted largest first: checkbox, 10 x 10 ramp
swatch, name, size. The swatch is `TreemapPalette.colorShare` with the same
share the canvas lays out. Selected and hovered rows use `accentSoft`.

The map uses one encoding: size share as a neutral ramp. Darker means a larger
share in light mode; lighter means a larger share in dark mode. The labels use
the ink that contrasts with the block. The map does not encode categories.
Collected blocks carry the accent border; the hovered block carries the ink
border.

The collection is cleared by `Clear`, by a new scan, and after a trash pass. It
survives drill-down and drill-out. While a scan runs the collection controls are
disabled with the reason `Wait for the scan to finish.`; opening folders and the
breadcrumb stay available.

The trash sheet lists up to six names and sizes, the total, and the sentence
`Moved items stay in the Trash until you empty it.` Under `DRY_RUN` it shows
the preview gate and the confirm button is disabled. After a pass, a notice says
what moved, what failed, and offers `Scan again`.

States: never scanned, scanning, finished, empty folder, read errors, volume
unavailable, dry run, after trash.

## Tweaks

Job: answer "what does this preference do, what is it now, and how do I put it
back?".

The page is a preference list, not a card grid:

1. Page header: `Tweaks`, one sentence, no metric.
2. Filter row: `All` / `Changed` segmented control, the visible count, `Read again`.
3. Gate: when `DRY_RUN` is set, one amber label, `Preview only. No tweak is
   changed.`, and every control is disabled while the states stay readable.
4. Sections by part of macOS: Finder, Dock, Keyboard, Screenshots, Appearance,
   Windows. Each section header carries the row count.
5. A row: name, one-line explanation, current value and impact
   (`On · Finder windows`), notes (`Restart Finder`, `Medium risk`), the control,
   and an info button. Rows are separated by hairlines, not cards.
6. The details sheet: the full explanation, current state, impact, risk, when the
   change applies, the preference key, the last recorded change, and the actions
   `Reset to Default`, `Revert last change`, a restart when one is pending, and
   `Turn On` / `Turn Off` for a switch.

States: loading (`Reading your settings.`), empty (`No tweaks match` or `No
changed tweaks`), unknown (the reason from `defaults` in the row, control
disabled), unsupported (the reason in the row, control disabled). An unknown
value is never shown as Off.

## Settings

Job: answer "what will the next scan do, and what has Chet changed?" in words a
non-technical person already uses. One fixed 560 x 560 window, panes with an icon
and a word: `What to find`, `Limits`, `Folders`, `Tweaks`. The pane name is not
repeated in the title bar.

1. `What to find`: panel `What to look for` with the note and the six switches, then
   panel `Speed` with the `Threads` pop-up.
2. `Limits`: panels with the size sliders and the readout on the right.
3. `Folders`: panels for skipped folders, added folders, and other disks; picker
   buttons sit at the panel's bottom right. Each added folder has a `Keep…` button.
   Panel `Administrator` closes the pane: one note with the helper's state, the
   `Administrator cleanup` action (`Turn On…` or `Turn Off`), an `Open System
   Settings` action while macOS waits for approval, and the `Approval lifetime`
   slider from 1 to 60 minutes with its readout on the right.
4. `Tweaks`: panel `Changes Chet made` with the count of changed preferences and the
   path of the change record with a `Show` action; panel `Reset` with `Reset All…`,
   which asks once and then puts every changed tweak back to the macOS default.

A set `DRY_RUN` adds one amber label above the panes: `Preview only. Nothing will be
removed.` The `Tweaks` pane adds `Preview only. No tweak is changed.` and disables
`Reset All…`. The Tweaks page in the main window shows its own gate and does not
repeat the cleaning strip. Under the gate the `Administrator` panel keeps its note but
disables `Turn On…`, `Turn Off`, `Open System Settings`, and the lifetime slider.

## About

Job: answer "which build is running, whether access is granted, and where are
the logs?".

`Chet > About Chet` opens one fixed 560 x 620 window. It is independent of
the main window and can stay open during a scan.

Top to bottom:

1. `PageHeader`: app icon, `Chet`, the one-sentence product line, metric: the
   version.
2. `This build`: build, minimum macOS.
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

1. Title: `Chet needs Full Disk Access`.
2. One paragraph: what macOS hides and why the app needs it.
3. Three plain rows: open Privacy & Security, turn on Chet under Full Disk
   Access, come back here. Numbers in `inkSecondary`, no circles.
4. Primary `Open System Settings`.
5. Link `Continue with limited results`.
6. Waiting state: native spinner and `Checking for access`.

The page uses a 48 pt inset and max width 520. The page polls the access probe
and dismisses itself when access lands. It does not pulse.

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
claim success before the operation completes. Cancel is the default button in
the confirmation; the destructive button never takes Return. The dry-run state
changes every verb. The Apps uninstall sheets use the same sheet grammar
and width; they do not use this clean progress.

## Error and partial states

- Top status strip for a global condition: limited access, dry run, scan result.
- Inline status label for a row condition: running, admin, protected.
- Empty state for no data: cause plus next action.
- Error state for a failed operation: cause, retry, and the audit log link.
- Never show a zero as if it were a measured result. Show `Not measured`,
  `Unavailable`, or no value.
