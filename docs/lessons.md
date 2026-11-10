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
