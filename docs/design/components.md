# Components

Every component uses the tokens in [tokens.md](tokens.md). A component owns its
spacing, states, and typography. A screen composes components and does not
reimplement them.

## PageHeader

Anatomy:

```
[icon 44] title (title)
          subtitle (body, inkSecondary)               metric (display, right)
hairline
```

Rules:

- One page title. It names the job, not the category ID.
- The icon is optional and only for an object page: an app. It is
  44 pt and uses the page's own asset.
- The subtitle is one sentence. It may name the risk or the count.
- The metric is the number the page is about. It is optional; when present it
  is right-aligned and tabular.
- The header sits 24 pt from the top. Its side inset is the page margin: 24 pt
  at the minimum window, 32 pt at wide widths.
- No icon badge, no eyebrow, no pill above the title.
- The header is one accessibility element: its label composes title, subtitle, metric,
  and metric label, and it is static text. An identifier at the call site lands once on
  that element.

States:

- Default.
- While measuring: the metric slot shows `Measuring` with a small
  `ProgressView`, not a skeleton number.

## Page scaffold

Every content destination wraps in `PageScreen`. A page supplies slots; it never
places the chrome. That is the whole point: two screens cannot drift apart, and
a new screen cannot invent its own margin.

```swift
PageScreen(
    scrolls: true,            // false for a table or a split surface
    header: { PageHeader(…) },
    subHeader: { … },         // optional: breadcrumb, metric row
    content: { … },
    bar: { CommandBar(…) }    // omit: the frame reserves the same bottom height
)
```

The frame owns:

- The page margin. No fixed 24/32 literals at a call site.
- 24 pt from the top, then the header, 12 pt below the header block.
- The header is laid out at its natural height and never compressed. An
  oversized body shrinks or clips; it never pushes the title under the titlebar.
- `PageHeader` keeps the metric slot at full height when the number is missing,
  so a finished scan does not move the rows below it.
- One scroll rhythm: `Spacing.s6` between content sections, `Spacing.s6` bottom.
- The bottom bar through `safeAreaBar` when a page supplies one, and the reserved
  inset when it does not. An empty bar is not the same as no bar: it keeps the whole
  page height and clips the content away.
- `Preview only. Nothing is changed.` once, at the foot of the frame, in tertiary
  ink. Not a strip, not a per-page label.

Tables, empty, loading and error states use the same margin as the content.
The app detail composes `PageScreen(scrolls: false)`; it never hand-builds its frame.
Settings and About are separate windows; they keep their own fixed margins.

## Table row

A table is `ColumnTable`, and every row in it is `TableRow`. The shell owns the
things all four tables had written by hand: the 40 pt row height, the inset
(page margin, or the panel inset for a nested list), the selection wash, the
pointer shape, and the open gesture (Return and double click).

The row content is columns, built from three parts:

```
RowCheckbox(width:)   fixed mark column, one AX label, one disabled rule
name column           first column, maxWidth .infinity
SizeColumn(width:)    monospaced, right aligned, same everywhere
other columns         plain Text with its own width
```

Two rules follow from this:

- A column width lives in the screen's `*Columns` enum, never inline.
- A row does not set height, padding, wash, or a double click. Only `TableRow` does.
- The row shell owns the context menu and the shape that makes the whole
  rectangle clickable. A cell never carries its own menu, or only the rendered
  text takes the right click.
- A presentation-only column, such as the file kind on Large files, is added at
  the call site and never stored on the item.

## RowActionButton

A clickable row, card tile, glyph, or breadcrumb crumb.

```
label content (call site)
plain button style, focusable, one focus ring on a 6 pt box
contentShape(Rectangle()) so the whole label is the hit area
help + accessibility label (defaults to help) + optional identifier
```

The label content stays at the call site, so a row reads as a row, a tile as a
tile, a crumb as a crumb. The behaviour is never written twice: five call sites
had already drifted apart on the focus ring and the accessibility label.

## SectionHeader

```
SECTION TITLE (section, ink)
optional action (link, caption)
hairline
```

The label is sentence case, not uppercase. The action is a text button that
does one thing. There is no trailing icon-only menu unless the menu is the only
action and has an accessibility label. The header is one accessibility element
with a composed label (`title, trailing`); an identifier at the call site lands
once on that element.

## Metric

A label and a value:

```
label (caption, inkSecondary)
value (metric, tabular, ink)
```

Use for totals, the page-header metric, and the app-detail bundle size. A ledger
row size uses `row` in `ink`. The value never sits inside a colored shape. The
metric is right-aligned when it belongs to a table column.

## CapacityBar

A horizontal bar with three segments and a text legend:

```
used (capacityUsed) | reclaimable (accent) | free (capacityFree)
```

Rules:

- Height 10 pt. Segments have a 1 px `paper` gap, and the bar has a 1 px
  `hairline` outline so the free end stays visible on paper.
- The bar is the only chart on Home.
- The legend is text: `Used 320 GB`, `Can be reclaimed 12.4 GB`, `Free 88 GB`.
- The reclaimable segment is the accent. It is the only accent on the page
  besides the primary action.
- When the scan has not run, the reclaimable segment is absent and the legend
  says `Scan to measure`.
- The bar never animates its width. It updates in place.

## Home state copy

Home resolves one of five reasons before it speaks: never scanned, scanning, unreadable,
measured empty, and findings. `HomeState` owns every sentence, so the subtitle and the empty
state cannot disagree. While scanning, no empty state renders. The unreadable reason appears
when a folder a category measures could not be read or Full Disk Access is missing.

The incomplete-results banner is scoped: `ReadScope.blockingCount` counts only errors inside a
measured category root. Files passed as roots, vanished paths, protected system folders, and
other users' homes are classified and ignored, and the banner states the count it used.

## LedgerTable

The main comparison surface. It is `ColumnTable`: one pinned header, one hairline
under it, and custom rows. Each screen supplies its columns; the metrics do not
change.

Category columns, in order:

1. Selection checkbox.
2. Name, with a 22 pt icon and a second line for location.
3. Size, right-aligned, tabular.
4. Modified, right-aligned, secondary.
5. Risk, right-aligned, text only: `Review` or empty.

Apps and Homebrew use their own documented columns. They keep the same checkbox,
icon gutter, header height, row height, page margin, and column alignment.

Rules:

- Header height 32 pt. Rows are 40 pt.
- No alternating row backgrounds.
- One hairline under the header. Rows use the native separator or no line.
- Selected rows use `accentSoft`.
- The checkbox is the only selection control. Double-click or the context menu
  opens the item. The row itself is not a button.
- Column widths are stable. The name column takes the remaining space.
- Sorting is available from the column header. The default is largest first.
- No extra unnamed action column. More actions live in the context menu.

## CommandBar

A full-width bar at the bottom of the content area:

```
[ selected count and bytes ]                         [ primary action ]
--------------------------------------------------------------------- hairline
```

Rules:

- Height 56 pt minimum plus the safe-area bottom. Two lines of summary need it.
- The surface is the system glass (`GlassBar`) and spans the detail pane edge to edge,
  from the sidebar to the window edge. It reads as one piece with the top strip.
- The controls sit on the page margin inside the glass, so the summary aligns with the
  page content.
- Top 1 px `hairline`; no radius, no floating, no bottom padding.
- Left: the selection summary in two lines: the byte total in `metric`, the
  count in `caption`.
- Right: one primary button and an optional secondary text button. The primary
  names the consequence: `Clean`, `Move to Trash`, or `Remove`.
- The destructive button in a confirmation sheet uses the red tint. The command
  bar button uses the accent, because it opens the review, not the deletion.
- The bar is present whenever the screen can act. It is disabled when the
  selection is empty or an operation is running. The primary control stays in
  place and is disabled; it is never removed, so the layout cannot jump.
- A caption beside it says why when the reason is not obvious.
- The bar is the same component on every screen.

## StatusLabel

A small, plain status:

```
icon (16, semantic color) + text (caption, semantic color)
```

Use:

- `Review` in amber with `exclamationmark.circle`.
- `Running` in amber with `bolt.fill`.
- `Needs administrator` in amber with `lock.fill`.
- `Protected` in red with `shield.lefthalf.filled`.
- `Exact match` and `Name match` in `inkSecondary`, with no fill.
- `Shared` in `inkSecondary`, with no fill.

No capsule, no background fill, no glow. The text carries the meaning; the icon
supports it.

## EmptyState

```
title (section)
one sentence (body, inkSecondary) that says why it is empty
one action when an action exists: secondary when it only navigates
(`Back to Home`), primary when it fills the state
```

Use the screen's normal margins. No illustration, no large icon, no decorative
circle. Do not build an empty state from `ContentUnavailableView`'s default
symbol, because that renders a large icon. The copy names the cause and the next
step. First run, filtered to nothing, and permission denied are different states
with different copy. `EmptyStateView` collapses the title and message into one
static-text element and takes an optional `identifier`; the action button stays
a separate pressable element and does not carry the id.

## LoadingState

- A native `ProgressView` plus a sentence: `Reading applications`.
- If the exact shape is known and stable, a flat skeleton may hold the layout.
- No shimmer. No pulsing. The system spinner is the only motion.
- A loading state never claims a number or a result.
- `LoadingStateView` carries its identifier on the message text; the spinner is
  hidden from accessibility.

## ErrorState

- A title that names what failed.
- One sentence with the likely cause and the action that can fix it.
- A button that retries or opens the relevant System Settings page.
- The underlying error message is available in a disclosure or a tooltip, not
  as the first line.
- The tone is amber. Red is reserved for protected and destructive rows.

## PrimaryButton

- Native `.borderedProminent` with the accent tint, control size `.large`.
- Do not set `buttonBorderShape`. The system draws the current control shape.
- Label is a verb and an optional SF Symbol that names the action.
- One primary button per screen.
- The keyboard shortcut is shown in the help text, not inside the label.

## SecondaryButton

- Native `.bordered` or `.plain`.
- Used for Cancel, Reveal in Finder, Show Audit Log, Select.
- Never competes visually with the primary action.

## TopStatusStrip

A full-width strip directly under the toolbar, above the content:

```
icon (16) + message (row)                           [action] [dismiss]
```

Uses:

- Full Disk Access is limited: amber icon, message, `Open Settings`, dismiss.
- Scan finished: neutral icon, the result, dismiss. Auto-dismiss after 4 s.
- Dry run is engaged: amber icon, `Preview only. Nothing will be removed.`, no
  dismiss. The uninstall workspace uses `Preview only. Nothing will be moved.`
  The Tweaks page owns `Preview only. No tweak is changed.` The Homebrew page
  uses `Preview only. Nothing will be removed.`; its install sheet uses
  `Nothing will be installed.` and its uninstall and cleanup sheets use
  `Nothing will be removed.`
- Apps and Homebrew are not scan surfaces: their strip shows the page gate
  only, never the scan result.

Rules:

- Height 48 to 56 pt.
- System bar material, bottom 1 px `hairline`.
- No floating, no capsule, no overlay on content.
- The strip pushes content down; it never covers it.

## PreviewNotice

The one dry-run gate treatment. The call site supplies the verb that matches its
action.

- Tones: `destructive` is `exclamationmark.triangle` in amber; `inert` is
  `eye.slash` in neutral. The default is `destructive`.
- It renders `StatusLabel` and draws no surface of its own: no bar, no hairline.
- The component absorbs the five inline gate rows, or `StatusStrip` replaces it
  at those sites. A page-level gate lives in the top strip, not in an inline row.

## PreviewCopy

- Five verbs, one owner each: `statement` (`Preview only. Nothing is changed.`),
  `removals` (`Preview only. Nothing will be removed.`), `moves` (`Preview only.
  Nothing will be moved.`), `installs` (`Preview only. Nothing will be
  installed.`), and `tweaks`, consumed from `TweakError.gatedCopy`.
- A view prints the verb for its surface; it never retypes the sentence.
- The tweak sentence stays owned by ChetCore because the engine, not the view,
  decides gating.

## RowCheckbox

- One checkbox: `isOn`, `label`, optional `width`, `isEnabled`, `help`, and
  `identifier`.
- `init(identifier:isOn:label:)` makes the identifier a required argument of
  the adopted form. The identifier lands on the `Toggle` itself, never on a
  wrapper.
- The memberwise form stays available for a row that carries no identifier.
- Adoption sites, measured in code: eight files call it — `CategoryDetailView`,
  `AppBrowserView`, `AppCleanerDetailView`, `GroupedItemsView`, `HomebrewView`,
  `SnapshotsView`, `StorageComponents`, and `HomebrewInstallerSheet`.

## ColumnRegistry

- Roles: `mark`, `icon`, `name`, `location`, `version`, `size`, `status`, `age`,
  `local`, `kind`, `modified`, `risk`.
- Widths: shared roles take the widest current definition (`mark` 20, `icon` 22,
  `name` flex at 0, `location` 140, `version` 80, `size` 90, `status` 118).
  Table-only roles keep their own value (`age` 140, `local` 110, `kind` 140,
  `modified` 140, `risk` 110).
- Widest-wins for a shared role; a table does not override a width.
- `spacing` is `Spacing.s3`; `headerHeight` is `Metrics.tableHeaderHeight`.

## SortColumnButton

- One sortable label: caption text plus a chevron at `Metrics.chevronIconSize`
  (8), hidden when the column is inactive.
- The whole label takes the focus ring and hit shape; the arrow is not a second
  control.

## Toolbar scan control

Shown on category, Snapshots, and Storage. Home owns scan in its command bar;
Apps, Homebrew, and Tweaks have no scan control. The scan control is a global
tool, not the screen's primary content action; a screen may show it while its
command bar carries `Clean` or `Remove`.

- Idle: one `Scan` or `Scan again` button.
- Scanning: one 24 pt progress ring with a stop glyph inside. The ring is the
  loading indicator; the glyph is the action. No text, no second button.
- The button owns a 40 pt square frame and `contentShape`; the ring stays 24 pt
  drawn size. Symmetric 8 pt padding keeps it centered in the toolbar slot
  without shrinking the click area.
- Hover help and the accessibility label both say `Stop the scan`.
- The detailed phase, bytes, and folder trail live in the page, never in the
  toolbar.

## ScanProgressSection

The overview's scan state, in the page flow:

```
phase title (section)                              percent (metric)
linear ProgressView (accent)
current folder (caption, inkSecondary, truncating)
five phase rows with a checkmark or a small circle
```

Pause and Stop live in the page's bottom bar: the command bar on Home, the scan
strip on Storage. The strip shows one Pause/Resume control for the current state
plus `Stop scan`.

Rules:

- No card. The section sits between the capacity bar and the ledger.
- The phase list is a plain ledger: one row per phase with 4 pt vertical
  padding.
- The result of the scan replaces this section with the ledger.
- The detailed folder trail belongs to the disk map only.

## StorageLocationBar

```
Home > Library > Caches            Used 236.46 GB of 245.11 GB   Size on disk
--------------------------------------------------------------------- hairline
```

- Breadcrumb: plain text buttons, `inkSecondary` for ancestors, `ink` for the
  current folder. A chevron separates them. No pill.
- The volume line is caption, tabular. `Capacity unavailable` replaces it when
  the volume cannot be read.
- `Size on disk` is present only when the tree measured allocated bytes, and it
  carries a help string. No legend: the ledger swatch is the legend.
- Identifiers sit on the controls: `storage.crumb.<n>`,
  `storage.crumb.current`, `storage.volume`.

## StorageMetricsRow

```
Free space          | Cleanable            | Large files
8.65 GB             | -                    | -
96.5% used          | Scan for junk        | Scan to measure
--------------------------------------------------------------------------
```

- Three equal columns, 72 pt high, 16 pt inner insets, one 1 px `hairline`
  between columns. No fill, no radius, no card.
- Label is caption `inkSecondary`; value is `metric`, tabular, `ink`; the third
  line holds one fact and at most one text action.
- The action is `QuietActionButton`. `Cleanable` links to Home, `Large files`
  links to the category, and before a scan each offers the scan. When a scan ran
  and the source is empty, the value is `-` and the action is absent.
- Identifiers land on the control inside each block: `storage.metric.free`,
  `storage.metric.cleanable`, `storage.metric.largeFiles`.

## StorageLedger

```
Applications                                   11.49 GB
/Applications                              22 items
------------------------------------------------------------------
[] [swatch] Visual Studio Code.app              1.58 GB
[] [swatch] Google Chrome.app                   1.53 GB
```

- Fixed 288 pt column with a 1 px leading hairline. Header: folder name
  (`section`), size (`metric`, tabular), path and `N items` (caption).
- Rows are 40 pt: native checkbox, 10 x 10 ramp swatch, name (middle
  truncation), size (tabular). One hairline between rows, no alternating fill.
- The swatch is the block's ramp colour at the same share, so chart and list
  cannot drift.
- Selected and hovered rows use `accentSoft`. A row with children carries a
  trailing `chevron.right` button that opens the folder; double-click also
  opens it, and the context menu holds `Show in Finder`. Checkboxes are disabled
  while a scan runs.
- A folder change resets the list scroll to the top. Without it, a deep scroll
  offset can leave a shorter new sibling list showing blank rows.
- Read errors add one amber `StatusLabel` under the header.
- The identifiers are on the controls: `storage.row.<name>`,
  `storage.open.<name>`, `storage.ledger.header`.

## Treemap labels

- Direct labels on top-level blocks from 44 x 36 pt up. The name is `row` with
  medium weight, the size is caption, tabular, and appears only when the block is
  at least 64 x 54.
- Label ink is `MapColors.labelDark` or `labelLight`, chosen by the block's
  share. Mid-tone blocks carry no label; hover names them.
- A collected block's border is `Theme.accent`. The hovered block's border is
  `Theme.inkSecondary`. Both values are defined in `Palette.swift`.
- Clicking a block opens its folder when it has children. Collection is the tile's
  context menu and the ledger checkbox; a plain click never toggles. A 300 ms
  guard after an open stops the second click of a double click from drilling
  another level.
- The canvas exposes one accessibility element, `storage.canvas`, with the
  current folder in its label and the click hint in the hint.
- Hover elsewhere shows a small plain label with the folder name and size on
  `paperRaised` with a hairline. It is content, not glass.

## AppCell

Grid cell:

```
[checkbox]                    [icon 48]
                              name (row, 2 lines)
                              publisher (caption)
                              size · location (caption, tabular)
```

- Flat `paperRaised` surface, 1 px `hairline`, radius 6.
- Hover changes the border to `inkTertiary`; it does not change the fill.
- Marked state uses the accent border and a filled checkbox.
- The running state is a text label `Running`, not a dot.
- The admin state is a `lock.fill` icon with a help tooltip.
- Clicking the cell opens the detail. The checkbox marks for bulk removal.
- Selection is a `RowCheckbox`; `apps.select.<id>` lands on the control. `<id>` is
  the bundle identifier, else the app file name, lowercase.

## MediaCard

- Grid card for a grouped destination: thumbnail, checkbox or a Keep label, name, size.
- The thumbnail clip is `Metrics.panelRadius`.
- The checkbox is a `RowCheckbox`. A card grid passes `grouped.select.<id>`; a keeper
  card passes nil.
- The card's structure (thumbnail, label, actions) stays its own. It is not absorbed
  into a shared component.
- The thumbnail box is square: the column width less `Spacing.s2` on each side, image
  fitted and centred, never cropped. QuickLook is asked for the measured box side.
- The shell is `Spacing.s2` padding on the raised paper, `Metrics.controlRadius`, one
  hairline border. Grid gap and the pane gutter come from `Spacing.s4` and `Spacing.s2`;
  no literal sizes live in the view.

## AppRow

```
[checkbox] [icon 22] name                          location   version   size   status
                    bundle ID (caption)
```

- Row height 40 pt.
- Columns are stable, right-aligned for version and size.
- The row is not a button; a double click or the context menu opens the detail.
  The checkbox marks it for bulk removal. The context menu carries Open and Reveal.
- Running and admin states are `StatusLabel` text, never unlabeled dots.

## OwnershipRow

The related-file row in app detail:

```
[checkbox] [icon 22] name                         size (metric)
                    location · status label
```

- The checkbox is disabled for shared, admin, and protected rows.
- The status label is plain text:
  - `Exact match` in `inkSecondary`
  - `Name match` in `inkSecondary`
  - `Shared` in `inkSecondary`
  - `Needs administrator` in amber
  - `Protected` in red
- No pill, no colored background, no seal icon.

## ConfirmationSheet

```
Remove Chrome?                                    (title)
5 items, 920.3 MB                                 (body, tabular)
--------------------------------------------------------------------- hairline
App bundle       920.3 MB
Preferences      8 kB
Caches           233 kB
--------------------------------------------------------------------- hairline
The app and selected files move to the Trash.     (body)
Each item is checked again before it moves.       (caption)
[Cancel]                              [Move to Trash] (red)
```

Rules:

- Width `Metrics.sheetWidth` 520 pt. System sheet background. Flow sheets are
  520 pt; detail sheets are 540 pt (`Metrics.detailSheetWidth`); 480 pt is not
  used.
- No huge icon, no sparkle, no glass.
- The rows are a ledger, not cards.
- The destructive button uses the red tint. Cancel is the default button and
  takes Return and Escape. The destructive button never takes Return.
- The dry-run notice is the exact line: `Preview only. Nothing will be
  removed.` The uninstall sheet uses `Preview only. Nothing will be moved.`
- The running warning is an amber `StatusLabel`, not a colored block.

## SheetLedgerBox

The one ledger recipe, used by the six ledger sheets:

```
ScrollView
  ledger rows                              (name, location, size)
  hairline per row
```

- `Theme.paperRaised`, radius `Metrics.controlRadius` 6, horizontal `Spacing.s3`.
- Two forms: `SheetLedgerBox { }` scrolls and caps at 220 pt for a long ledger;
  `SheetLedgerBox(maxHeight: nil) { }` draws a short list with the same padding and
  surface, no scroll wrapper and no cap.
- The byte column is `Metrics.byteColumnWidth` (88 pt). A row never writes
  its own 88, 84, or 80.
- The box owns the scroll and the surface. A call site adds rows, never padding.
- Six sites adopt it: `ConfirmSheet`, both app-uninstall confirm sheets,
  `HomebrewUninstallSheet`, `HomebrewCleanupSheet`, and `StorageTrashSheet`.

## SheetFrame

The sheet shell every sheet renders through. Measured: 13 call sites in
`Chet/Views`.

- Width `Metrics.sheetWidth` 520 pt for a flow sheet; a detail sheet passes
  `Metrics.detailSheetWidth` 540 pt. 480 pt is not used.
- 24 pt padding, an optional fixed height, and the paper body.
- The system draws the sheet window; the frame supplies the body.

## ScanScopeSheet

The one place a scan scope is chosen. Reached from `Scope…` on Home and from
Settings; the sheet is never duplicated.

```
Scan a part of this Mac
Pick the categories and folders one scan reads. Everything else is left alone.

Safe to remove   [switch] Developer caches
Check first      [switch] Large files
Protected        [switch] Nix files
Folders          ~/Library/Caches              [x]
                 Choose…
Next launch      [switch] Remember this scope
                                  [Cancel] [Scan]
```

- Categories come from `CategoryCopy.scopeEntries`, in the same section order as
  Home. Every switch starts on.
- An empty category set means every category, so turning the last one off scans
  everything again. The summary line always names the scope that will run.
- Folders are additive; no folder means the home roots. A folder outside home
  needs the Other disks opt-in; the engine drops it otherwise.
- The remember switch is the only path to `UserDefaults`. Without it the scope
  lives for one scan.

## AppUninstallSheets

- Confirm and summary sheets for one app and for a bulk selection.
- The consequence rows share one file-private `consequenceRow(_:icon:)`. Both
  confirm sheets call it; neither holds its own copy.

## SummarySheet

```
Clean complete                                    (title)
12.4 GB freed                                     (display)
34 of 36 items cleaned                            (body)
--------------------------------------------------------------------- hairline
4 items left alone                                (DisclosureGroup)
  file name              reason
--------------------------------------------------------------------- hairline
[Show audit log]                                      [Done]
```

- No 56 pt icon, no bounce, no rounded 40 pt number.
- Width 520 pt, same as the confirmation sheet.
- Dry run changes the title to `Dry run complete` and the verb to `would be
  freed`, `would be moved`.
- The problems list is a plain table with the reason in secondary ink.
- `Done` dismisses.

## CleanProgressSheet

The progress surface for a running clean pass. It replaces the confirmation
content in the same sheet and is replaced by the summary when the pass ends.

```
[spinner] Cleaning                             42%
Item 12 of 34
[================== item progress ==================]

+-----------------------------------------------------+
| Items      11 of 34                                 |
| Bytes      2.4 GB of 10.4 GB                        |
| [============== byte progress ==============]       |
| Freed      2.3 GB                                   |
| Skipped    1                                        |
| Failed     0                                        |
| Current    ~/Library/Caches/com.example.app/...     |
|            Folder - Deleting - 18 MB                |
+-----------------------------------------------------+

Each item is checked again before it is removed. An item can be a file or a folder.
```

Rules:

- The top row is the loading indicator: native spinner, title, item fraction,
  and a linear item bar.
- The bordered box is the verbose layer: items, bytes plus a byte bar, freed or
  would-free bytes, skipped, failed, and the current path with its action.
- The current row names the exact path being processed, truncated in the middle,
  with the full path in the tooltip and selectable text.
- The sheet uses the same 520 pt width as the confirmation and summary.
- A fast clean holds the progress sheet for at least 0.45 s, so a six-item
  pass cannot flash past and read as the old instant summary.
- Interactive dismissal is disabled while `isCleaning` is true. Escape does not
  close it. The summary is the exit.
- Dry run changes `Cleaning` to `Simulating clean`, `Freed` to `Would free`, the
  current action to `Would delete` or `Would move to Trash`, and the skipped and
  failed labels to `Would skip` and `Would fail`.
- The update stream buffers the newest sample, so the UI never queues thousands
  of path updates on the main actor.

## MiseView

```
mise                                                  (title)
Tool versions declared in your mise config.           (body)
[Read again]  12 tools                                (toolbar)

Tool                          Requested   Status
swift                         6.0.3       Active
  ~/.local/share/mise/installs/swift/6.0.3
------------------------------------------------------------------ hairline
Locations
Config   ~/.config/mise/config.toml
Cache    ~/.local/share/mise
```

- `PageScreen(scrolls: false)`: page header, a toolbar with `Read again` and
  the tool count, the declared tool table, and a `Locations` section. No
  command bar and no glass on the content.
- One row per installed version, plus a row for a declared version that is
  not installed. A declared row carries a `declared` caption under the tool
  name. Ordering is tool name ascending, declared first, then version
  descending with numeric comparison. The name takes the
  remaining width; `version` uses the shared 80 pt column and `status` the
  shared 118 pt column.
- `Active` is an accent checkmark, `Inactive` a neutral minus, and
  `Not installed` an amber warning. A row with a resolved install path shows
  it as a caption line under the name, middle-truncated. The caption is not an
  accessibility target; the row's name text carries the row identifier. A
  declared tool with no resolved entry keeps its row and its `Not installed`
  label.
- `Locations` is a `SectionHeader` and two label and path rows: `Config` and
  `Cache`. The path is caption, selectable, and middle-truncated. `Cache` says
  `Unavailable` when the read fails.
- A failed `mise ls --json` is one amber `StatusLabel` above the table. The
  declared rows stay below it.
- Empty state: `No tools declared`, with `The mise config has no tools table.`
- Read-only. The view runs `mise ls --json` and `mise cache path` only; it
  never installs, uninstalls, switches, or prunes, so there is no confirmation
  and no dry-run gate.
- The view is only shown when the config declares at least one tool and a mise
  binary resolves at `~/.local/bin/mise`, else the first executable `mise` on
  `PATH`. Without both, the sidebar row and the view are absent.
- Identifiers: `mise.header` on the header, `mise.page` on the toolbar
  tool-count text, `mise.refresh` on `Read again`, `mise.empty` on the empty
  state, `mise.tool.<tool>.<version>` on a tool name, `mise.config` and
  `mise.cache` on the paths, and `sidebar.mise` on the sidebar row. The header
  is one accessibility element reading `mise`. `<tool>` and `<version>` are
  lowercased, and every character outside `[a-z0-9]` becomes `.`.

## PermissionPage

```
Chet needs Full Disk Access.                       (title)
macOS hides these folders from apps.               (body)
[short list of what access unlocks]                (body)
[Open System Settings]                             (primary)
[Continue with limited results]                    (link)
Checking for access...                             (caption + spinner)
```

- No glass card, no numbered circles, no pulsing dot.
- The three steps are plain rows with a small number in `inkSecondary`, not
  colored circles.
- The waiting state is a native small `ProgressView` plus text.
- The page uses the paper background, a 48 pt inset, and max width 520. The 48
  pt is the gate's deliberate inset, not a page margin.

## Settings frame and columns

- One page margin, owned by `SettingsPaneView`; a pane does not pad its own content.
- The control column is `Metrics.controlColumn` (150), shared by `SettingsGrid.slider`
  and `PreferenceRow.controlWidth`.
- The readout column is `SettingsGrid.valueColumn` (56), monospaced digits, right
  aligned.
- Control sizes: a primary action is `.large`; destructive and secondary actions are
  `.regular`; a settings slider is `.small`.
- `SettingsSliderRow` takes an optional `identifier` applied to the slider only; the
  readout text does not carry it.

## SettingsRow

Settings is a panel list, not a `Form`.

```
Include caches and build folders                 [toggle]
Search inside caches and build folders. Off by default.
```

- Use `SettingsPanel` with a `Grid`, `SettingsRow`, `SettingsNote`, and
  `SettingsDivider`. The row height and padding live in `SettingsGrid`.
- The caption explains the consequence and the default in one line.
- No extra sections, no card per preference, no form wrapper.

## PreferenceRow

The one row in a preference list. Used by Tweaks.

```
Show the path bar                                        [switch]  (i)
Show the folder path at the bottom of every Finder window.
On · Finder windows   Restart Finder
```

- Geometry lives in the component: 8 pt of vertical padding, a 150 pt control
  column, the info button after it, and a 2 pt gap inside the label block.
- `notes` carries at most a risk and a restart status. A low risk is not repeated;
  it is the baseline for a reversible preference write.
- The accessory is a parameter, so a switch, a pop-up, and a folder picker use the
  same row without a second row type. `isEnabled` is the global gate: the control
  stays visible and inert and the text stays readable.
- The details action is an `IconActionButton` labelled `Details for <name>`, never
  a clickable row.

## DefinitionRow

`label` on the left in a 110 pt column, value on the right, selectable, tabular
digits for numbers. An optional `detail` line sits under the value in caption,
truncated in the middle, for a path or a secondary fact. The value wraps to two
lines at most, so a long token cannot stretch the row. Used by the tweak details
sheet and the Go page. The component owns its padding, so a sheet never sets row
geometry at the call site.
