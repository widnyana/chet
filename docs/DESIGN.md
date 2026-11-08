# Mackit — UI Design

Reconstructed from the shipped SwiftUI code (`Mackit/Views/`). Native macOS app: a
`NavigationSplitView` shell — fixed-width sidebar on the left (240–280 pt), detail pane on
the right — on macOS 26 Liquid Glass.

## Sidebar

The sidebar is the app's spine and the clean-mode surface: Overview, the Reclaimable
categories, Disk map under Inspect. Uninstall has no place here — no mode switch, no tab,
no destination row. It opens from the Overview card (see Uninstall below).

In **Clean** mode the list has three visual zones, top to bottom:

1. **Overview** — a single root row (`gauge.with.dots.needle.67percent`, blue). Doubles as
   the scan progress indicator: a mini spinner replaces it while a scan runs.
1. **Reclaimable** section — one row per cleanable category, each with:
   - `Project build dirs` (`wrench.and.screwdriver`, purple): a recursive rule over
     `Development`, `Projects`, `Documents` and `Desktop` that matches regenerable build
     directories by name — `target/`, `node_modules/`, `vendor/`, `.build/`, `.gradle/`,
     `DerivedData/`, `Pods/`. Matches are never preselected (risk `.review`, mode
     `.trash`), a match is a leaf (no nested double-counts), `.git` is never entered, and
     recursion is capped at 6 levels.
   - a tinted SF Symbol icon from `CategoryStyle` (the color *is* the category's identity —
     the same symbol+color pair is reused in the overview grid, detail headers, and sheets),
   - the category name (single line, truncating),
   - a right-aligned, monospaced-digit byte count (`42 GB`) in secondary color,
   - inline state: mini spinner while that category is actively scanning, tertiary text for
     pending-but-empty categories, a small lock glyph when Full Disk Access is limiting it.
   - Localized Exception Management Utility for Applications snapshots show their count instead of bytes.
   - While scanning, the section shows a single "Scanning…" placeholder row; empty
     categories are dimmed rather than hidden.
3. **Inspect** section — `Disk map` (`square.grid.3x3.fill`, blue), the browse-everything view.

Row anatomy is deliberately flat: `Label { title + states + Spacer + trailing value } icon: { tinted symbol }`.
No custom backgrounds, no disclosure chrome — selection, hover, and focus come from the
system list.

The app inventory does not live in the sidebar and the sidebar never changes while the
uninstaller is open.

## Disk map — live nested treemap

The Disk map is a Metal-rendered treemap (`DiskMapView` + `TreemapMTKView`) of the home
folder that **grows into its final shape while the scan runs** — the WizTree experience,
not a wait-then-reveal chart.

How the data gets there:

1. The walker (`FileIndexBuilder`) reports each directory as it finishes measuring
   (post-order, children before parents) when it is interesting enough to render:
   depth ≤ 2 or ≥ 32 MB (`onRollup` → `ScanEvent.treeUpdate`).
2. `ScanModel` folds every rollup into a single **live home tree** (`liveTree`) via
   `FolderNode.inserting/merging` — subtree replace by URL, ancestors never shrink below
   their children's sum. A rollup whose parent chain isn't measured yet is dropped; its
   parent's own rollup carries it later.
3. The in-flight root gets a live-growing block from the walk's byte counters
   (`ProgressSnapshot.runningRootBytes`) on every progress tick, so the map exists from the
   first tick, not the first completed folder.
4. When the scan finishes, `.folderTrees` replaces the live tree with the full tree in the
   same canvas — no blank flash.

How it draws:

- **Nested rendering**: each block paints itself, then its children squarified inside it,
  inset 1 pt so the parent's color shows as a border; recursion goes three levels deep and
  only into blocks big enough to be legible (≥ 1.5% of the canvas area). Painter's order:
  ancestors first, descendants on top.
- **Colors**, two channels: the 1 pt parent border is the category (orange caches and
  logs, purple developer data, green media, blue other); the block fill carries size.
  Fill is a quantized four-tier ramp on the block's share of its parent (`sqrt(share)`
  cut at 0.2/0.45/0.7): lower tiers mix the block's own category hue toward neutral
  dark, the top tier is the full category color. Bigger blocks read brighter and more
  colorful; small blocks go gray. Container blocks render dimmed (0.72). Top-tier
  blocks (84 pt a side) carry direct name + size labels; the legend shows outlined
  category swatches and the four-tier size scale.
- **Navigation** is a URL path stack, not node references: the live tree is replaced
  several times a second, so the current node is re-resolved against the newest tree on
  every render; stale paths trim the breadcrumb stack instead of crashing.
- **Hover** shows a glass capsule with the folder name and byte count (monospaced digits);
  **click** zooms into a folder with children; right-click offers Reveal in Finder.
- **Two sections.** The treemap owns the top; progress owns the bottom. The bottom strip
  (quaternary background, top divider) carries the phase headline, the linear bar, the
  detail line (label, rate, elapsed, paused), file counters, the five-line folder trail,
  and Pause/Stop. It appears only while scanning and is text-only: its per-tick updates
  never relayout the Metal canvas.
- **Throttled snapshots.** Rollups replace `liveTree` several times a second; the UI draws
  a 250 ms snapshot (`displayTree`, refreshed by a poll task) so the canvas and the path
  pill relayout at most 4x/s instead of strobing. Hover re-resolves by URL against the
  newest snapshot.

## Uninstall

Uninstall is a task, not a mode. The Overview page carries the one door: a quiet
**Uninstall apps** card under the disk bar, present in every overview state. It opens the
app browser over the detail pane; a leading **Done** toolbar button leaves it and returns
attention to the Overview. The sidebar never changes. The browser is a searchable
inventory of installed apps, switchable
between a **grid** (adaptive cells) and a **list** (dense rows) from the toolbar. Both
styles render the same model state; the choice persists across launches.

Every app carries its facts: display name, publisher (`vendorLabel`, falling back to the
bundle ID), size (measured by a background loop after each reload — cells show "—" until
their measurement lands), and install location (`Applications`, `User Applications`, or
the parent folder). A running app shows an orange dot; an app only an administrator can
remove shows a lock. Neither blocks anything — the confirm sheet and the core carry the
consequences.

Removing in bulk: the corner circle-check (grid) or leading checkbox (list) marks apps;
a floating glass capsule reports the marked count and total bytes. Its `Remove…` button
opens the bulk confirm — the marked apps, the total, and the removal policy ("each app
bundle and its exact-match Library files move to the Trash"; running apps will be
skipped). The dry-run notice appears here when `DryRun.enabled`. During the pass the
capsule becomes a progress line ("Removing 3 of 7…") and the grid stays interactive.
Afterwards a summary sheet reports the total, one row per app, and every skipped or
failed item with the app it belonged to. The dry run reads `DryRun.enabled` exactly once
per pass and passes it to every core call — the same gate the single-app flow uses, so
dry-run bulk removal performs zero trash moves and logs `dry-` audit rows.

The search field filters by display name and bundle ID; the toolbar Reload button
re-reads the applications folder. Void states: a skeleton in the exact shape of the
chosen style while reading, "No applications found" when the folder yields nothing, "No
matches" when the search misses. The context menu on every cell and row offers Show
Related Files (pushes the review surface), Open, Reveal in Finder, and Mark/Unmark for
Removal. Opening a cell pushes the review surface:

1. **App header** - 64 pt icon, display name, bundle ID, path, version and measured bundle
   size. The "Remove app bundle" checkbox is the only control that targets the app itself.
   It is disabled while the app (or a helper) runs or when the bundle cannot be written. A
   running app gets an orange warning; an administrator-owned app gets a lock warning. A
   back button returns to the grid; the confirm and summary sheets attach to the
   workspace, so the summary survives the automatic pop after a completed removal.
2. **Related files list** - sections by component kind (Application Support, Preferences,
   Caches, Logs, Containers, Group Containers, Saved Application State, Cookies, Application
   Scripts, Launch Agents, WebKit). Each row carries a checkbox, workspace icon, path, size
   and an ownership badge:
   - `Exact` (green): bundle ID or embedded helper ID, selected by default;
   - `Name match` (orange): app name or bundle-ID leaf, unselected until reviewed;
   - `Shared` (gray): group container or data another installed app claims, unselectable;
   - `Admin` (orange lock): `/Library` or read-only folder, unselectable;
   - `Protected` (red shield): a system or private path that is never offered.

The selection header offers "Exact Matches Only", "All Selectable" and "None". A floating
glass capsule at the bottom reports selected count and bytes; its `Remove` button opens a
confirmation sheet that names the app, groups the selected items by kind, states that
everything goes to the Trash, warns when the app runs, and shows the DRY RUN notice when
engaged. The completion sheet reports moved count and bytes, lists skipped rows with their
reasons, and links to the audit log.

Everything is checked again in the core before the first move: running app, stamp (inode,
size, mtime), match still valid, protected path, writability. The app bundle moves last.

## Visual language

One grammar, applied everywhere. Every surface speaks it; nothing speaks a second one.

- **Cards.** One recipe: 24 pt padding, 22 pt corners, `.glassEffect(.regular, in:
  .rect(cornerRadius: 22))`. Action cards carry a `.title3.bold()` title and may end in
  a neutral quaternary capsule chip; status strips (disk bar, scan progress) carry a
  `.headline` label. Nothing else gets a card.
- **Icons.** Bare, tinted SF Symbols — never inside a filled badge or box. Row scale
  16-18 pt (sidebar), list scale 20-24 pt (detail rows), card scale 28 pt. Color comes
  from `CategoryStyle` or `.tint`/`.secondary`; orange is reserved for attention.
- **Toolbar.** Icon buttons and the search field, nothing else. A mode exit is an
  icon-only `chevron.left` with a help tag; a view switcher is a segmented icon picker.
- **Buttons.** Exactly one `.glassProminent` button per surface (the primary act).
  Neutral secondary actions are plain or quaternary capsules.
- **Glass everywhere.** Floating chrome is `.glassEffect(.regular, in: .capsule/.rect)`;
  primary buttons are `.glassProminent`. Glass is used for: the floating ActionBar capsule
  (bottom of category views), overview cards
  (22 pt-corner rects), confirmation/summary sheets, and success chips (green-tinted glass).
- **Color = meaning, not decoration.** Category tints (orange caches, cyan browser, purple
  package caches, red large files…) are the only saturated color. Orange also signals
  attention (access banner, DRY RUN badge). System gray means "snapshots/neutral".
- **Numbers are monospaced.** Every byte count uses `.monospacedDigit()` so totals don't
  jitter during scans.
- **Type scale** stays in system text styles: `.title.bold()` hero numbers (rounded design,
  40–56 pt on summary screens), `.headline` for card titles/selected totals, `.callout` for
  body, `.caption` for metadata — always `.secondary`/`.tertiary` for hierarchy.
- **Destructive actions are explicit.** The Clean button is the only prominent glass button
  per surface (Command-Delete shortcut), and it opens `ConfirmSheet` before touching files.

## Feedback & states

- Scanning: per-row spinners + dimmed pending rows in the sidebar, a 26 pt progress ring
  in the toolbar (quaternary track, accent arc over the five scan steps, percent centered;
  click pauses, hover tooltips the phase words, no capsule), and a toast
  (`ScanFinishedToast`, top center) when done.
- Access: when Full Disk Access is denied the onboarding screen takes over the window until
  the grant lands or the user picks "Continue without Full Disk Access" for this launch;
  a dismissible orange banner (`AccessBanner`) above the detail pane explains limited access
  after that choice. Onboarding: shield icon, bold title, a three-step glass card, a
  prominent glass button, and an orange "Waiting for access" dot.
- Debug: an orange "DRY RUN ENGAGED" capsule floats bottom-left — compile-time
  `#if DEBUG` plus runtime `DryRun.enabled`, so release builds can't show it. Under dry
  run the confirm sheet says nothing will be deleted, the summary says "would be freed",
  and audit rows are prefixed `dry-` — a simulated clean never reads as a real deletion.
  `Cleaner.dryRun` is a required init parameter, so no composition root can build a
  mutating cleaner without deciding.

- Settings (Cmd+, the standard `Settings` scene): exactly one opt-in toggle, "Include
  caches and build folders". The duplicates step skips regenerable build dirs
  (`DuplicateScope.regenerableNames`, shared with the "Project build dirs" rule),
  caches (`Caches`, `.cache`), and temporary places (`tmp`, `temp`, `.tmp`) by default;
  the toggle maps to `DuplicateScope.everything`. No other options live on the page.

## Rules of thumb

1. Reuse `CategoryStyle` — never hardcode a symbol or color for a category.
2. New floating chrome = glass capsule/rect with the established paddings (16–18 pt
   horizontal, 8–10 pt vertical), not opaque backgrounds.
3. Anything countable renders monospaced-digit, secondary, right-aligned.
4. State is communicated in the row it belongs to (spinner/lock/dim) — not with new UI.

## Layout registry

Fixed chrome and its coordinates, tracked so pieces never overlap. `scripts/layout_check.py`
reads this block, verifies the Swift code still matches, and lays the floating pieces on the
minimum window (960 x 600) to check for intersections. Estimated sizes are minimums, not
measured pixels: they catch structural collisions, not kerning. If you move chrome, update
this registry in the same commit, then run `mise run layout`.

Rules the script enforces:

1. Nothing floats over the title bar: no `.overlay(alignment: .top)` anywhere in `Mackit/`.
   The toast is a top safe-area inset, so it sits below the toolbar, above the banner.
2. Bottom capsules hug their content and center, so the bottom corners stay free for the
   DRY RUN badge. A full-width bottom bar would collide with it.
3. Floating chrome anchored to the same corner must stay mutually clear at minimum size.

```layout-registry
{
  "window": {"width": 960, "height": 600, "titlebar": 52},
  "chrome": [
    {
      "id": "toast",
      "file": "Mackit/Views/ContentView.swift",
      "mechanism": "safeAreaInset-top",
      "height": 40,
      "verify": {
        "contains": ["safeAreaInset(edge: .top, spacing: 0) {\n            if !showingUninstaller { ScanFinishedToast() }"],
        "not-contains": [".overlay(alignment: .top)"]
      }
    },
    {
      "id": "dry-run-badge",
      "file": "Mackit/Views/ContentView.swift",
      "mechanism": "overlay-bottomLeading",
      "width": 190,
      "height": 26,
      "insets": {"leading": 16, "bottom": 12},
      "verify": {"contains": [".overlay(alignment: .bottomLeading) { dryRunBadge }"]}
    },
    {
      "id": "category-action-bar",
      "file": "Mackit/Views/ActionBar.swift",
      "surface": "category-detail",
      "mechanism": "safeAreaInset-bottom-centered-capsule",
      "width": 340,
      "height": 50,
      "insets": {"bottom": 16},
      "verify": {"contains": ["glassEffect(.regular, in: .capsule)\n        .frame(maxWidth: .infinity)"]}
    },
    {
      "id": "app-uninstall-action-bar",
      "file": "Mackit/Views/AppCleanerDetailView.swift",
      "surface": "app-uninstaller",
      "mechanism": "safeAreaInset-bottom-centered-capsule",
      "width": 340,
      "height": 50,
      "insets": {"bottom": 16},
      "verify": {
        "contains": ["glassEffect(.regular, in: .capsule)\n        .frame(maxWidth: .infinity)"]
      }
    },
    {
      "id": "app-browser-bulk-bar",
      "file": "Mackit/Views/AppBrowserView.swift",
      "surface": "app-browser",
      "mechanism": "safeAreaInset-bottom-centered-capsule",
      "width": 420,
      "height": 50,
      "insets": {"bottom": 16},
      "verify": {
        "contains": ["glassEffect(.regular, in: .capsule)\n                .frame(maxWidth: .infinity)"]
      }
    },
    {
      "id": "snapshots-action-bar",
      "file": "Mackit/Views/SnapshotsView.swift",
      "surface": "snapshots",
      "mechanism": "safeAreaInset-bottom-centered-capsule",
      "width": 420,
      "height": 50,
      "insets": {"bottom": 16},
      "verify": {"contains": ["glassEffect(.regular, in: .capsule)\n            Spacer()"]}
    },
    {
      "id": "scan-status-ring",
      "file": "Mackit/Views/ScanStatusView.swift",
      "mechanism": "toolbar-ring",
      "height": 26,
      "verify": {"contains": ["rotationEffect(.degrees(-90))"]}
    },
    {
      "id": "disk-map-path-pill",
      "file": "Mackit/Views/DiskMapView.swift",
      "mechanism": "in-flow-header",
      "height": 30,
      "verify": {"contains": ["glassEffect(.regular, in: .capsule)"]}
    },
    {
      "id": "disk-map-progress-strip",
      "file": "Mackit/Views/DiskMapView.swift",
      "mechanism": "in-flow-bottom-of-page",
      "height": 150,
      "verify": {"contains": ["background(.quaternary.opacity(0.4))"]}
    },
    {
      "id": "access-banner",
      "file": "Mackit/Views/AccessBanner.swift",
      "mechanism": "in-flow-top-of-detail",
      "height": 56,
      "verify": {"contains": [".padding(.horizontal, 16)", ".padding(.vertical, 10)"]}
    }
  ]
}
```

