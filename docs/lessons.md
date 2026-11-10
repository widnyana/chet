# Lessons from the layout session

Date: 2026-11-10. What broke, why, and what to do differently next time.
Everything here came out of one working session: the page-frame refactor
(`956721e`), the row-parts refactor (`2b9bccb`), and the verification that
followed them.

## Layout pitfalls

### 1. Shared chrome slots carry one thing

`PageScreen` gives every page four slots: header, sub-header, content, bar.
The bar slot exists for the `CommandBar`. Storage stuffed three strips into
it: the scan progress panel, the trash report, and the command bar.

Consequences, measured on a 1680 pt window:

- The bar grew from ~65 pt to ~180 pt while scanning.
- The frame draws its bar as native glass with `backgroundExtensionEffect()`.
  A tall glass bar mirrors the content edge into itself. With the bright
  Metal treemap touching the bottom edge, the whole map showed through as a
  blurred, mirrored copy behind the progress panel. On other pages the same
  effect is a thin sliver nobody notices; page chrome made it glaring.

Rule: page state (progress, result notices) is content, not chrome. The bar
keeps one command bar. If a page needs a progress surface, it renders inside
the page (Home does this with the step list) or in the top status strip.

The tell: a strip that changes the height of the bottom of the page is chrome
that a page invented. Push it back into content.

### 2. A `@ViewBuilder` slot is not a stack

`PageScreen`'s `content:` takes a `@ViewBuilder`. A builder that emits
sibling views produces a `TupleView`, not a `VStack`. In a fixed page
(`scrolls: false`) the frame lays the tuple out with no container between its
children, and the sections float apart. That is the giant empty band on the
duplicates category page: the table header pinned at the top, the group list
pushed to the bottom, empty paper between.

Fixed in `2b9bccb` by wrapping the page's builder output in a `VStack`.

Rule: when a slot takes a builder and the page emits more than one sibling,
wrap them in an explicit `VStack` at the call site. A builder is a list of
views, never a layout.

### 3. Moving chrome around changes geometry contracts

The same refactor removed `.frame(minHeight: 320)` from the treemap canvas
and made the header block `layoutPriority(1)` + `fixedSize`. Deliberate
choices, but they interact: at the 960 x 632 supported minimum, a header that
cannot compress eats the canvas. Every minimum that guarded a page against a
short window was there for a reason; removing one needs a check at the
minimum window size, not just at a large one.

Rule: after a frame refactor, run one page with content at 960 x 632 and
again at full width. The design is checked at the minimum size.

### 4. Doc drift is a bug, not a nuisance

The toolbar exclusion list grew from "Apps and Tweaks" to
"Apps, Tweaks, Homebrew, and Home" in `e37436f`, and `AGENTS.md` still said
"except Apps and Tweaks". A selector-driven test that expects
`toolbar.scanStop` on Home fails with "no element matches" and looks like a
broken spinner, not a doc drift. Home lost its scan control for weeks and
nobody noticed, because the command bar carries the same action.

Rule: a behavior flag in a list (excluded destinations, enabled pages) is an
interface. When it changes, the owning doc changes in the same commit. The
review gate in `docs/design/composition.md` already says this; it happened
anyway, which is why it is written down twice.

## Working with a second agent in the same tree

### 5. `mise run dev` is a weapon

It starts with `pkill -x chet`, which ends every running instance, including
the one the other session is driving a scan on. In this session it killed
four mid-scan verification cycles. `AGENTS.md` warns about it; the warning
undersells it. During a shared session, launch by path
(`open -n <app>`) and kill by pid. Treat `mise run dev` as something to run
only when you know the other session is idle.

### 6. Commits must not sweep the working tree

The other session ran a commit while this session's fix sat uncommitted in
the same file. The Storage bar fix landed inside their `refactor(ui):
compose table rows from shared parts` commit, with a message that does not
mention it. Nothing broke, but the history now attributes the fix to the
wrong change, and `git log` cannot tell you why the bar slot changed.

Rule: stage your own paths, never `git add -A`. When two sessions edited the
same file, split hunks (`git apply --cached` with a filtered patch) or wait.
A commit message should be able to name every change it contains.

### 7. Verify on a live app, and expect interruption

What worked here, in order of value:

- `axdrv dump` to measure: roles, identifiers, frames. The empty toolbar was
  proven by `dump --all role=AXToolbar` returning zero children; no
  screenshot needed.
- Screenshots for what AX cannot see: color, blur, mirrors. Pixel-measure
  with PIL when a margin looks off; do not eyeball scaled screenshots.
- Blur vs sharpness diagnoses rendering: a sharp edge in the wrong place is
  overflow; a blurred copy is an effect (`backgroundExtensionEffect`), and
  the fix is different.
- Accessibility identifiers on every control you will ever press. The scan
  state machine (gate, `home.scan`, `toolbar.scanStop`, `home.stop`) was
  driven entirely by selectors, through six app relaunches.

What to expect: a fresh launch lands on the permission gate; window frames
move between launches, so never hard-code coordinates; `press` on a disabled
control reports success and does nothing; the app can be killed at any moment
by the other session, so verify the pid before every command batch and treat
"target app not found" as an interruption, not a crash. Check
`~/Library/Logs/DiagnosticReports/` when unsure: this session killed the app
six times and produced zero crash reports, because the kills were external.

## One-line summary

Slots carry what the frame says they carry, builders are not layouts, docs
change with the list they describe, and in a shared tree you launch by path,
kill by pid, and stage by hunk.

## Working rules from the component session

Added after the page-frame and row-parts commits. These are the checks that
would have caught the two regressions before the user did.

### A page frame pins its header, and the body must be able to shrink

`PageScreen` needed three things to stop the title sliding under the titlebar:

```swift
header
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
// later in the same VStack:
content
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
```

A flexible body that carries a hard `minHeight` (the treemap had 320) can
refuse to shrink, and then the whole stack overflows upward. Remove the
minimum or make the body scroll. Do not fix the result with padding.

A header whose height depends on data (a metric that is nil before the first
scan) moves every row when the data arrives. Reserve the slot: render the
same text layout with `.clear` ink when there is no number.

### An empty bar is not the same as no bar

`PageScreen` applied `.safeAreaBar(edge: .bottom) { bar }` unconditionally.
Tweaks is the only destination that passes no command bar, so its bar was an
`EmptyView`. An empty bar still claims the whole content height: the scroll
area measured `450,372,710,0` and the entire list was clipped away. Header,
gate notice, and page summary stayed visible, which reads as "the tweaks list
is missing" rather than "the page has no room".

Rule: a view that only decorates the bottom of a page is applied only when it
exists.

```swift
@ViewBuilder func body(content: Content) -> some View {
    if Bar.self == EmptyView.self {
        content
    } else {
        content.safeAreaBar(edge: .bottom) { bar }
    }
}
```

`Bar.self` reads the type, so this only works when the empty case has the
`EmptyView` type. A `@ViewBuilder` bar with one `if` and no `else` is still a
bar type and still claims the height when the condition is false. A page whose
bar depends on its data branches above the frame:

```swift
var body: some View {
    if isProtected {
        page(bar: EmptyView())
    } else {
        page(bar: commandBar)
    }
}
```

The tell: a page that renders its header and nothing else. Axis-dump the page
and read the container frame, do not trust the screenshot alone.

### Smoke checklist for a layout change, about two minutes

```sh
xcodebuild -project chet.xcodeproj -scheme chet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xc build
mise run lint
mise run test
```

Then assert a number, not an impression:

```sh
pkill -x chet; DRY_RUN=1 open -n .build/xc/Build/Products/Debug/chet.app
P=$(pgrep -f 'chet.app/Contents/MacOS/chet$' | head -1)
/tmp/axdrv --pid $P press id=gate.continue
/tmp/axdrv --pid $P dump id=home.header
/tmp/axdrv --pid $P dump id=storage.header
```

`home.header`, `apps.header` and `storage.header` must report the same `frame`
x and y. That equality is the contract of the shared frame. State checks read
the same way: `desc=Scanning enabled=false` proves a disabled control, "looks
disabled" does not.

### Driving the app, cheaply

- Home has no toolbar scan button: `toolbar.scan` exists only on non-overview
  destinations. Start the scan with `home.scan` (or `home.rescan`).
- A full scan runs about two minutes. Start it, then do other work. Sleeping
  in a poll loop wastes whole turns.
- AX walking a long `List` costs 300 to 450 nodes and can stall `dump --all`.
  One identifier, or one exact string, per call.
- `screencapture -l <windowid>` fails with "could not create image from
  window" when the window is behind or on another Space. `screencapture -x`
  of the full screen works, and the app must be frontmost to appear in it.
- `open -n` accumulates instances. `pkill -x chet` first, pick the pid
  explicitly, and `pgrep -x chet` must print nothing when the work is done.

### Extraction rules

Extraction is not free. A wrapper with one caller is cost without benefit.

- Extract at the second real call site, or when copies have already drifted.
  The five hand-written row buttons had drifted (one had no focus ring, one no
  label); the app grid tile had one caller, so it stayed a cell.
- Extract behaviour, not layout. `RowActionButton` owns focus ring, hit shape,
  help and label; the label content stays at the call site. `TableRow` owns
  height, inset, wash and the open gesture. `RowCheckbox` owns the label,
  width and disabled rule.
- A variant is a parameter when two call sites need two values
  (`SizeColumn.foreground`), never a flag only one caller sets.
- A view that already has the right shape but a different container (a row
  inside a `List`) can use the primitives without adopting the shell. No
  layout change, no new risk.
- When a component moves a control's accessibility wiring, re-read its
  description in the running app. `RowCheckbox` read as "Remove, Select X to
  remove" until its `Toggle` title was emptied; selectors match on that text.

### The formatter is a reviewer

- `swift format` rejects a call that passes both a closure argument and a
  trailing closure. Name it: `content: { ... }`, `label: { ... }`.
- Long-line failures surface leftovers: a lint run found
  `NSLog("TMAP open push=...")` from an earlier session.
- Run `swift format --in-place` on the files you touched before lint. It
  cannot fix a missing brace, so fix structure first.

### Docs are part of the change

A new component, a moved notice, or a changed bar means an edit in
[design/components.md](design/components.md) and the table in
[design/composition.md](design/composition.md). This repo had docs describing
a page scaffold that did not exist; that is how it starts.

## Debugging a report you cannot reproduce

A report said a list was missing while its count and size were visible. Four
hours went into chasing data paths that were correct the whole time.

### Read the container frame, not the text

The accessibility tree lists children that are clipped. `texts` printed every
row of the hidden tweak list, so "the items are in the tree" proves nothing.
The decisive number is the container frame: `frame=450,372,710,0`.

- Height 0 with rows inside means the body is clipped. Fix the frame.
- Normal height with no rows means nothing was built. Fix the data.

Take the frame first, then a screenshot. `EmptyStateView` also carries
`maxHeight: .infinity`, so a collapsed page can look like a designed state.

### Prove the binary before proving the code

A stale copy is the cheapest explanation and the easiest to rule out.

```sh
ps -o command= -p <pid>                       # which path is running
sha256sum .build/xc/Build/Products/Debug/chet.app/Contents/MacOS/chet
```

A rebuilt app also loses its Full Disk Access grant, so a launch that drops to
the onboarding gate is the rebuild talking, not a regression. `open -n` leaves
the old instance running; `pkill -x chet` first.

### Check who else is writing the tree

Another session committed to `DesignSystem.swift` between two of my builds.
The build then contained work I had not read, and its commit was invisible in
`git log -1` unless asked for.

- `git log --oneline -3` before the build and after it.
- `git status --short` tells you what is in flight; leave those paths alone.
- A commit you did not make is input to review, not something to revert.

### Look in the directory before naming the file

`.harness/impl/.15.impl` existed before I wrote it. `ls -1a .harness/impl`
costs one command; guessing the next number costs a correction from the owner.

### An empty view is not the same as no view

Two fixes came out of this: `safeAreaBar` with an `EmptyView` claims the whole
page, and a `@ViewBuilder` `if` still produces a bar type. Both are the same
mistake at different levels, so the rule belongs in the frame and at the call
site, not in one patch per page.

### Do not refactor on a hunch

I removed `safeAreaBar`, added frames, and rewrote a page before measuring.
Each attempt was reversible, but none was evidence. One measurement of the
container frame ended the hunt.
