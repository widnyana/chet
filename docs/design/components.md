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
- The icon is optional and only for an object page: an app or About. It is
  44 pt and uses the page's own asset.
- The subtitle is one sentence. It may name the risk or the count.
- The metric is the number the page is about. It is optional; when present it
  is right-aligned and tabular.
- The header sits 24 pt from the top. Its side inset is the page margin: 24 pt
  at the minimum window, 32 pt at wide widths.
- No icon badge, no eyebrow, no pill above the title.

States:

- Default.
- While measuring: the metric slot shows `Measuring` with a small
  `ProgressView`, not a skeleton number.

## SectionHeader

```
SECTION TITLE (section, ink)
optional action (link, caption)
hairline
```

The label is sentence case, not uppercase. The action is a text button that
does one thing. There is no trailing icon-only menu unless the menu is the only
action and has an accessibility label.

## Metric

A label and a value:

```
label (caption, inkSecondary)
value (metric, tabular, ink)
```

Use for totals and row sizes. The value never sits inside a colored shape. The
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

## LedgerTable

The main comparison surface. It is a native SwiftUI `Table` or a `List` styled
with the same metrics.

Columns, in order:

1. Selection checkbox.
2. Name, with a 22 pt icon and a second line for location.
3. Size, right-aligned, tabular.
4. Modified, right-aligned, secondary.
5. Risk, right-aligned, text only: `Review` or empty.

Rules:

- Header height 32 pt. Custom rows are 40 pt; a native `Table` keeps its system
  row height and is not forced.
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
- Background `paper`, top 1 px `hairline`.
- No radius, no floating, no bottom padding.
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
one action (secondary or primary) when an action exists
```

Use the screen's normal margins. No illustration, no large icon, no decorative
circle. Do not build an empty state from `ContentUnavailableView`'s default
symbol, because that renders a large icon. The copy names the cause and the next
step. First run, filtered to nothing, and permission denied are different states
with different copy.

## LoadingState

- A native `ProgressView` plus a sentence: `Reading applications`.
- If the exact shape is known and stable, a flat skeleton may hold the layout.
- No shimmer. No pulsing. The system spinner is the only motion.
- A loading state never claims a number or a result.

## ErrorState

- A title that names what failed.
- One sentence with the likely cause and the action that can fix it.
- A button that retries or opens the relevant System Settings page.
- The underlying error message is available in a disclosure or a tooltip, not
  as the first line.

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
  The Tweaks page owns `Preview only. No tweak is changed.`
- Apps and Homebrew workspaces: no scan strip.

Rules:

- Height 48 to 56 pt.
- Background `paperRaised`, bottom 1 px `hairline`.
- No floating, no capsule, no overlay on content.
- The strip pushes content down; it never covers it.

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

Pause and Stop live in the command bar, not in the section.

Rules:

- No card. The section sits between the capacity bar and the ledger.
- The phase list is a plain ledger: one row per phase with 4 pt vertical
  padding.
- The result of the scan replaces this section with the ledger.
- The detailed folder trail belongs to the disk map only.

## DiskMapChrome

```
Home / Library / Caches                     Darker means a larger share
--------------------------------------------------------------------- hairline
```

- Breadcrumb: plain text buttons, `inkSecondary` for ancestors, `ink` for the
  current folder. A chevron separates them. No pill.
- Legend: four 10 x 10 swatches of the neutral ramp, with `Small` and `Large`
  labels and a sentence. No category names.
- Hover: a small plain label with the folder name and size. It uses
  `paperRaised` and a hairline, not glass.
- Detail labels on large blocks use the ink color that contrasts with the
  block.

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

## AppRow

```
[checkbox] [icon 22] name                          location   version   size   status
                    bundle ID (caption)
```

- Row height 40 pt.
- Columns are stable, right-aligned for version and size.
- The row is not a button; a double click or the chevron opens the detail. The
  checkbox marks it for bulk removal. The context menu carries Open and Reveal.
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

- Width 520 pt. System sheet background. Flow sheets are 520 pt; detail sheets
  are 540 pt; 480 pt is not used.
- No huge icon, no sparkle, no glass.
- The rows are a ledger, not cards.
- The destructive button uses the red tint. Cancel is the default button and
  takes Return and Escape. The destructive button never takes Return.
- The dry-run notice is the exact line: `Preview only. Nothing will be
  removed.` The uninstall sheet uses `Preview only. Nothing will be moved.`
- The running warning is an amber `StatusLabel`, not a colored block.

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
digits for numbers. Used by the tweak details sheet. The component owns its
padding, so a sheet never sets row geometry at the call site.
