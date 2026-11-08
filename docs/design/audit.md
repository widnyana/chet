# Current UI audit

Date: 2026-11-08.
Scope: the shipped SwiftUI app in `Mackit/Views/`, the app icon, and the copy
visible inside the app. The audit is the reason for the redesign, not a list of
small fixes.

## Summary

The current interface is generous and careful in places, but it has no single
visual idea. It combines a colored category system, glass cards, floating
capsules, a marketing hero, a bar chart, a treemap with two color channels, and
three different bottom bars. Each piece is defensible on its own. Together they
compete for attention, so the app reads as a collection of screens rather than
one instrument.

The redesign replaces the collection with one idea: a ledger. Paper and ink,
tabular numbers, hairlines, one accent, and a single command bar.

## Findings

### 1. Glass is the character of the app, not an accent

Where: `OverviewView`, `CategoryDetailView`, `ActionBar`, `SnapshotsView`,
`AppBrowserView`, `AppCleanerDetailView`, `DiskMapView`, `OnboardingView`,
`ScanStatusView`, `ContentView`.

Problem: `.glassEffect` is used for every card, the overview panels, the
uninstall door, three bottom bars, the disk map breadcrumb, the hover chip, the
scan toast, the onboarding card, and the primary buttons. When every surface is
frosted, no surface is foreground. This breaks R-10.

Fix: remove custom glass. Use flat paper surfaces, hairlines, and native macOS
materials only where the platform uses them. The command bar is a real bar, not
a floating capsule.

### 2. The category palette is a rainbow with no hierarchy

Where: `CategoryStyle.swift`, `OverviewView` chart, `SidebarView`,
`ConfirmSheet`, `DiskMapView` legend.

Problem: the app assigns a different saturated color to each category: orange,
brown, blue, indigo, purple, cyan, teal, pink, red, mint, green, yellow. The
overview chart repeats those colors. The disk map adds a second color channel
(category border plus size heat). A user cannot learn twelve colors, so color
stops being information and becomes decoration. This breaks R-29 and R-01.

Fix: one accent, one paper, one ink. Category identity comes from the name and
a monochrome SF Symbol. Risk is the only semantic color: amber for review, red
for destructive or protected.

### 3. The overview is a stack of cards with a marketing hero

Where: `OverviewView`.

Problem: the first screen is a disk bar card, an uninstall card, and either a
marketing hero, a progress card, or a results card. The result card adds a
44 pt rounded number, a bar chart, and a second sentence about selection. This
is a landing page composition inside a utility. The chart duplicates the
category sizes that the sidebar already lists. This breaks R-05 and C-3.

Fix: one page, read top to bottom: capacity, the reclaimable total, the
category ledger. The capacity bar is the only visualization. The category rows
open the detail. No chart, no hero.

### 4. Three competing bottom bars

Where: `ActionBar`, `SnapshotsView`, `AppCleanerDetailView`, `AppBrowserView`.

Problem: category detail, snapshots, app detail, and the app browser each use a
different floating capsule with different widths, paddings, labels, and
shortcuts. The capsules overlap the content and leave the corners for the
DRY RUN badge. The grammar is not consistent, and the bars read as floating
toasts rather than actions.

Fix: one `CommandBar` component, full width, top hairline, no bottom padding.
It carries the selection summary on the left and one primary action on the
right. The same component appears on every surface that can act on a selection.

### 5. The icon language is generic

Where: `Mackit/AppIcon.icon/Assets/sparkle.svg`,
`small-sparkles.svg`, `icon.json`, `ConfirmSheet`, `ActionBar`,
`SnapshotsView`.

Problem: sparkles are the default vocabulary for an AI product, not for a disk
utility. They appear in the app icon and in the clean action. This breaks R-04.

Fix: the app icon becomes a measured disk mark: a ring with a missing segment,
in ink on paper. The clean action uses a plain trash or checkmark that names the
action, not a sparkle.

### 6. Decorative dots and motion

Where: `OnboardingView` (orange "Waiting for access" dot), `AppBrowserView`
(orange running dots), `SummaryView` and `UninstallSummaryView` (bounce),
`MediaCard` (green glass Keep badge).

Problem: the waiting dot is a pulsing status decoration with no state change to
justify the pulse. The running dot is the only signal for a real state but is
unlabeled. The bounce is celebration, not information. This breaks R-13, R-19,
and R-31.

Fix: text plus a static icon for running and waiting. The completion screen is
still; the number and the result are the event. Reduce Motion is respected by
removing all non-essential animation.

### 7. Floating capsules and badges

Where: `ReviewBadge`, `AppOwnershipBadge`, `KeepBadge`, `ScanFinishedToast`,
DRY RUN badge.

Problem: the app wraps small facts in pills: "Review", "Exact", "Shared",
"Admin", "Protected", "Keep", the scan toast, and the dry-run warning. The
badges use different fills and colors. A pill is not a hierarchy tool when every
small fact gets one. This breaks R-09 and R-11.

Fix: status labels are plain text with one small icon and a semantic color.
The dry-run warning is a full-width strip, because it is a real global state.
The scan toast becomes a top status strip, not a floating capsule.

### 8. Typography has two voices

Where: `OverviewView` and the summary sheets use 40 to 56 pt rounded bold
numbers and large icons; the rest uses system text styles.

Problem: the large rounded figures read as marketing, while the tables read as
a utility. The two voices do not belong to the same product. The summary
screens also put the largest element in the sheet, which makes the action feel
like a reward screen.

Fix: one type scale. The largest number on a screen is 34 pt, tabular, regular
or semibold. The summary is a result, not a celebration.

### 9. The disk map has two competing encodings

Where: `DiskMapView`, `TreemapMTKView.color(for:)`, `heat(_:)`, legend.

Problem: fill color encodes size share; border color encodes category. Two
encodings in one small rectangle, plus a eight-swatch legend, plus a breadcrumb
capsule, plus a hover chip. The map is informative but hard to read. The
category border is not needed: the folder hierarchy and labels already say what
the blocks are. This breaks R-29 and C-3.

Fix: one encoding, size. A single neutral ramp from light to ink, with a 1 px
separator. The legend says "Darker means larger share" and shows four steps. The
breadcrumb is a plain text row. Hover is a plain label.

### 10. The scan state lives in three places

Where: `ScanStatusView` toolbar ring, `OverviewView` progress card,
`DiskMapView` progress panel, `ScanFinishedToast`.

Problem: the toolbar shows a percentage ring, the overview shows a five-step
card, the disk map shows a detailed strip, and the toast repeats the result.
There is no single place a user can look to know what the scan is doing.

Fix: the toolbar keeps one compact action (Scan or Stop). The overview shows a
single progress section in the page flow. The disk map owns the detailed strip
because the map is the inspection surface. The finished result is a top strip
with a dismiss action, not a floating toast. The same phase and byte values feed
all three, so they cannot disagree.

### 11. The app browser mixes selection models

Where: `AppBrowserView`, `AppCell`, `AppRow`.

Problem: clicking a cell opens the app; a circle check marks it for bulk
removal; a running dot has no label; the list row uses a checkbox and a tap
gesture. The primary action is ambiguous. The grid and list do not share the
same row grammar. This breaks C-2 and R-26.

Fix: one marking model. The row and the cell both show a checkbox at the leading
edge. Opening is a separate disclosure or double-click. The running state is
text, not a dot. The bulk action bar appears only when at least one app is
marked.

### 12. Copy uses the agent's default voice

Where: `OverviewView` ("Find what you can safely remove"), `AccessBanner`,
`OnboardingView`, `ScanStatusView`, `AppBrowserView`.

Problem: the copy is a mix of marketing ("Find what you can safely remove"),
reassurance ("Nothing leaves your Mac"), and internal shorthand ("root 1 of 27").
Em dashes appear in the banner and the disk map headline. This breaks R-02,
R-15, and R-16.

Fix: verbs first, facts first. "Scan this Mac". "12.4 GB can be reclaimed".
"Quit Chrome before removing it." No em dashes. No claims without evidence.

### 13. Dark mode is inherited, not designed

Where: every view uses `Color.orange`, `.green`, `.gray`, `.secondary`, and
custom glass without a token layer.

Problem: the app has no explicit palette, so light and dark mode are whatever
the system colors do. Some combinations (orange on orange-tinted glass, green
on green-tinted glass, black/white treemap labels) are not checked in both
modes. This breaks R-21 and R-34.

Fix: a small token layer with dynamic paper and ink colors, an accent, and
semantic amber and red. Every surface is checked in both modes. The disk map
receives the color scheme and uses a light and a dark ramp.

### 14. The app icon is the default AI mark

Where: `Mackit/AppIcon.icon/icon.json`, `sparkle.svg`, `small-sparkles.svg`.

Problem: a blue gradient with two white sparkles. It could be an AI assistant,
a photo editor, or a writing tool. It says nothing about disk space. This
breaks R-04 and R-20.

Fix: a single-hue ink blue ground with a white ring and a missing segment, plus
a small solid dot at the center. The mark is a measured disk with a reclaimable
gap. It works at 16 pt and at 1024 pt.

## What stays

- The native `NavigationSplitView` shell. The app is a Mac app and should behave
  like one.
- The table and the grouped list. They are the right structures for comparing
  files.
- The Metal disk map. The visualization is the product's strongest original
  surface; it needs one encoding, not a rebuild.
- The safety model and the dry-run contract. The UI must keep showing them
  honestly.
- The keyboard shortcuts and the Select menu.
- The two-level app model: Clean for system data, Applications for app bundles.
  The redesign moves Applications into the sidebar as a destination.

## What the redesign must prove

1. A new user can tell, in one screen, how much space is reclaimable and what
   the next action is.
2. A returning user can open a category and clean a subset without reading a
   paragraph.
3. A user can find an app, see what belongs to it, and understand why each row
   is selected or not.
4. The same selection and action grammar appears on every screen.
5. Every screen works in light and dark mode, with keyboard only, at the
   minimum window size.
