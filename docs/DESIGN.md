# Mackit — UI Design

Reconstructed from the shipped SwiftUI code (`Mackit/Views/`). Native macOS app: a
`NavigationSplitView` shell — fixed-width sidebar on the left (240–280 pt), detail pane on
the right — on macOS 26 Liquid Glass.

## Sidebar

The sidebar is the app's spine. One `List` with three visual zones, top to bottom:

1. **Overview** — a single root row (`gauge.with.dots.needle.67percent`, blue). Doubles as
   the scan progress indicator: a mini spinner replaces it while a scan runs.
2. **Reclaimable** section — one row per cleanable category, each with:
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
- **Colors** come from the sidebar legend: orange caches and logs, purple developer data,
  green media, blue other. Two channels: hue is the category, brightness is size. A block's
  brightness scales with its share of the canvas (`0.55 + 0.45 * sqrt(share)`, clamped to
  1.0), so the folders that dominate the disk read as the strongest color and slivers read
  dim. Container blocks render dimmed (0.72) so their children pop.
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

## Visual language

- **Glass everywhere.** Floating chrome is `.glassEffect(.regular, in: .capsule/.rect)`;
  primary buttons are `.glassProminent`. Glass is used for: the floating ActionBar capsule
  (bottom of category views), the scan status pill (toolbar), overview cards
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

- Scanning: per-row spinners + dimmed pending rows in the sidebar, a phase-titled status
  pill in the toolbar, and a toast (`ScanFinishedToast`, top center) when done.
- Access: when Full Disk Access is denied the onboarding screen takes over the window until
  the grant lands or the user picks "Continue without Full Disk Access" for this launch;
  a dismissible orange banner (`AccessBanner`) above the detail pane explains limited access
  after that choice. Onboarding: shield icon, bold title, a three-step glass card, a
  prominent glass button, and an orange "Waiting for access" dot.
- Debug: an orange "DRY RUN ENGAGED" capsule floats bottom-left — compile-time
  `#if DEBUG` plus runtime `DryRun.enabled`, so release builds can't show it.

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
        "contains": ["safeAreaInset(edge: .top, spacing: 0) { ScanFinishedToast() }"],
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
      "id": "scan-status-pill",
      "file": "Mackit/Views/ScanStatusView.swift",
      "mechanism": "toolbar-pill",
      "height": 44,
      "verify": {"contains": ["glassEffect(.regular, in: .capsule)"]}
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

