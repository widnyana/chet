# SwiftUI performance guidance

Source: Apple, "Understanding and improving SwiftUI performance"
(https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance),
read 2026-11-09. This file turns that page into rules for Chet. Where a rule names a Chet
file, the line was read in the tree on that date; nothing here was profiled yet. Treat each
Chet site as a suspect to confirm in Instruments, not as a measured fault.

## Why it matters

SwiftUI must finish every view update before the next display frame. A body that runs too
long, or views that update too often, cause hitches. Chet has two screens that update fast
while a scan runs: Storage (the Metal treemap, fed by a live tree) and Home (progress and
ledgers). Both sit on `ScanModel`, one `@Observable` object that changes many times a second.

## Measure first

1. In Xcode choose Product > Profile, pick the SwiftUI template, press Record.
2. Run one thing: a scan, a resize of the Storage window, a sort click in a category table.
3. Stop. Read the SwiftUI track lanes:

|Lane|What it shows|
|---|---|
|Update Groups|Time SwiftUI spends computing updates. Long groups with no long bodies mean too many small updates.|
|Long View Body Updates|Orange: a body took over 500 microseconds. Red: over 1000 microseconds.|
|Long Platform View Updates|Slow AppKit drawing hosted in SwiftUI. Chet hosts `TreemapMTKView` this way.|
|Other Long Updates|Geometry and text layout work.|

4. For a long body: Control-click it, choose Set Inspection Range and Zoom, then read the Time
   Profiler call tree or flame graph. One sample can be too thin. Repeat the action and filter
   with Show Calls Made by `<View>.body`.
5. For many short updates: Control-click an update group, choose Set Inspection Range, then
   hover an update and choose Show Causes. Blue nodes are Chet code, gray nodes are the system.
   A blue to gray to blue chain means Chet caused an event it then answers itself.
6. Fix the most frequent cause first. Record again: the graph shows one changing property per
   edge, so a second property can keep the same view updating.

## Rules

### Keep `body` cheap

- A body does no sorting, filtering, formatting, or tree walking. Compute it off the main
  actor or in the model, cache the result, and read the cache in the body.
- A computed property read from a body is part of the body. `var sorted: [X] { sort(...) }`
  runs on every read, and a body that reads it twice sorts twice.
- Keep non-UI work out of the `View` initializer, `body`, `onAppear`, `onChanged`, and any
  modifier that changes view state. SwiftUI rebuilds views often.
- Do not allocate formatters or arrays per update. Hoist them to a `static let` or the model.

### Update less often

- Use `@Observable`, not `ObservableObject`. The macro tracks only the properties a body
  reads, so an unrelated property change does not touch the view. `ScanModel` already uses it.
  Keep it true: a body that reads `model.categories` re-runs on every category change, so read
  a narrow stored value (`totalBytes`) instead of a collection you then reduce.
- Split a view when only part of it depends on fast state. Move the fast-changing piece into
  its own child view so the parent body does not re-run.
- Do not write `@State` or model properties on every event if the value did not change.
  Compare first, then assign. Do not rely on SwiftUI to drop an equal write; confirm in the
  Update Groups lane that an unchanged hover causes no body update.
- Throttle fast sources. A live tree that changes several times a second should reach the UI
  at a fixed rate (Storage already publishes a 250 ms snapshot).
- For size or geometry callbacks (`onGeometryChange`), act only when the change passes a
  threshold, not on every pixel.

### Layout readers

- `GeometryReader` and `ScrollViewReader` re-run when their parent's layout changes. Keep them
  small and put views that do not affect layout outside them.
- Do not feed a layout reader's output back into state that changes the same layout.

### Closures in views

- Do not store escaping closures that build child views. They capture state, and SwiftUI
  recomputes the result whenever captured state changes. If the closure captures `self`, any
  property change counts. Call the builder closure in the initializer and store the returned view.
- Action closures (`Button`) and per-element closures (`ForEach`) are fine, but they can still
  cause too many updates, so check them with Show Causes.

## Chet sites to check

Read from the tree on 2026-11-09, not profiled. Rank by Instruments before changing any.

|Site|Pattern|Suspect|
|---|---|---|
|`Chet/Views/DiskMapView.swift` `TreemapMTKView.mouseMoved`, `tile(at:)`|Per-event work|`tiles.filter{}.min` allocates an array of every tile under the pointer on each mouse event. Tiles are appended parent before child, so the last containing tile is the deepest; one reverse scan with no allocation gives the same answer.|
|`DiskMapView` `onHover: { hovered = $0 }`|Redundant state write|Assigns on every move even when the tile is unchanged. Compare node ids first.|
|`DiskMapView` `pathNodes`|Computed property in `body`|Read four or five times per body (header, chrome, canvas, largest folders), each time walking the stack. Compute once per body into a local, or cache with the snapshot.|
|`DiskMapView` poll task, `node(with:in:)`|Tree walk on a timer|Depth-first search of the whole live tree every 250 ms while hovering. Look the node up by stack path, not by scanning.|
|`DiskMapView.largestFolders`|Sort in `body`|Sorts children that `FolderNode` already keeps sorted largest first.|
|`TreemapMTKView.relayout`, `labels(for:)`|Work on every resize step|`setFrameSize` runs a full layout, builds a new Metal buffer, and `labels` repeats the top level `Treemap.layout`. Reuse the first layout; coalesce resize steps.|
|`Chet/Views/CategoryDetailView.swift`|Sort and filter in `body`|`category.items.sorted(using:)` feeds `Table`, and `categorySelected` filters all items on each access. With tens of thousands of items, cache the sorted array in the model and keep a selected count.|
|`Chet/Views/GroupedItemsView.swift`|Computed property read twice|`sorted` re-sorts the groups for each `ForEach` that reads it.|
|`Chet/Views/AppBrowserView.swift`|Sort in `body`|`apps.sorted` with `localizedStandardCompare` runs per body. Sort when the inputs change, not on every render.|
|`Chet/Views/OverviewView.swift`|Repeated model read|`model.selectedItems` is read twice in one body; it is now O(selected), but read it once into a local.|

## Rules of thumb for new views

1. If a body has a loop, a sort, or a formatter, move it to the model and cache it.
2. If a value changes faster than 4 times a second, it does not go straight into a view.
3. Read the smallest stored value the body needs.
4. Add a threshold or an equality check before any state write inside an event handler.
5. After a change, record again in Instruments and compare the update count, not only the time.
