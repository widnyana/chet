# UI guidelines

Status: rules for every new screen, panel, control, and copy change.
Date: 2026-11-09.
Checked against: macOS 27.0.1 (Golden Gate), Xcode 27.2, `MacOSX27.2.sdk`.
Chet deployment target: macOS 26.0.

Companion docs: [principles.md](principles.md) (position), [tokens.md](tokens.md)
(values), [components.md](components.md) (anatomy), [screens.md](screens.md)
(composition), [copy.md](copy.md) (words), [references.md](references.md)
(decision log).

## How to use this file

Read it in this order when you add or change a screen:

1. Name the screen job in [screens.md](screens.md). A screen with two jobs is
   two screens.
2. Compose existing components from [components.md](components.md), following
   [composition.md](composition.md). Do not restyle a row at the call site.
3. Apply the layer rules in section 2 and the surface rules in section 3.
4. Check the pitfalls below before writing the first line of the view.
5. Run the review gate in section 12 and the recipes in section 13.

If this file disagrees with [../DESIGN.md](../DESIGN.md), DESIGN.md wins and
this file is wrong. Fix it here.

### The working agreement

- The design docs are the target. `UI-FINDINGS.md` at the repo root is the gap
  list: it records where the shipped code has not caught up. It is local and
  untracked. Do not copy a gap into new work because it already exists.
- One concept has one value. If code and docs disagree, do not invent a third
  value. Use the value in this doc set and leave the code gap in the findings.
  If the doc itself is stale, update the doc in the same change.
- Never add a color, radius, spacing value, font size, icon size, or animation
  at a call site. If the table has no token, the change needs a token, a reason,
  and an entry in [tokens.md](tokens.md) first.
- Native first. A custom control needs a written reason and a keyboard and
  VoiceOver path. A hand-drawn control that imitates a system control is a
  regression, not a design.
- One focal point, one primary action. If a screen needs two, it is two screens.
  The global scan control in the toolbar is a tool, not a second primary
  action; the command bar still carries the content action.
- Copy is code. Strings live in `CategoryCopy`, `ScanStepCopy`, `AppCopy`, and
  `TweakCopy`. A view does not retype them.
- A disabled control is visible and inert. A control that disappears is a
  layout jump, and a control that does nothing is a defect.
- The action names the consequence. `Clean`, `Move to Trash`, `Remove`,
  `Uninstall`. Not `Continue` or `Done` when a better verb exists.

### Build order

1. Decide the screen's question and its one focal point.
2. Pick the surface: content, native control, sheet, or status strip.
3. Pick the component. If none fits, extend the owning component before you
   write a new view.
4. Pick the tokens. No literals for type, color, spacing, radius, or icons.
5. Write the four states: empty, loading, error, and the normal case.
6. Add the keyboard path, the accessibility label, and the help text.
7. Check light, dark, 960 x 632, Reduce Motion, Reduce Transparency, Increase
   Contrast, and both ends of the system glass slider.
8. Update the doc that owns the change: tokens, components, screens, or copy.

### When to ask, and when to decide

Decide and state the choice when the answer is already in these docs. Ask one
question, once, only when:

- the screen has two equally valid jobs and the split changes navigation;
- a new token value is needed and no existing token covers it;
- the copy changes a promise, a consequence, or a destructive verb.

Do not ask for permission to follow a rule in this file. Do not invent a value
to avoid the question.

## 1. Three tests

Every screen passes all three. A fail on any test blocks delivery.

| Test | Question | Fail signal |
|---|---|---|
| Native | Would a Mac user recognize every control and every shortcut? | A hand-drawn control, a fake window, a fake menu, a fixed control height |
| Ledger | Does the screen read as a total, entries, a rule, an action? | Cards, a hero number, decoration in the margin |
| Specific | Would this look the same if the app had another name? | Template layout, stock icon set, invented content |

The third test is the anti-slop test. Identity in Chet comes from structure:
the capacity bar, tabular numbers, hairlines, and one accent. It does not come
from an effect.

Fresh does not mean new effects. It means the app shows the current system
chrome, current control shapes, and current SDK behavior, and nothing that
dated. A 2025 glass card would make the app older, not newer.

## 2. Layers

Apple defines two layers (HIG Materials, Adopting Liquid Glass):

- the **control and navigation layer**, rendered by the system with Liquid
  Glass: sidebar, toolbar, sheets, popovers, menus, alerts, window chrome;
- the **content layer**, rendered by the app: everything Chet measures.

Chet draws the content layer. It does not redraw the control layer.

| Surface | Who renders it | Rule for Chet |
|---|---|---|
| Sidebar | system | No background, no tint, no glass wrapper, no overlay |
| Toolbar and title bar | system | Standard `ToolbarItem` only. Custom toolbar content is allowed; a custom toolbar background is not |
| Sheet | system window, Chet body | No background on the window. Paper goes on the sheet body. |
| Alert, popover, menu | system | Use `.alert`, `.confirmationDialog`, `.popover`. No custom overlay that imitates them |
| Table and list | Chet | `paper`, `paperRaised`, hairline. No row shadows, no card rows |
| Command bar | Chet | Full width via `safeAreaBar`, no painted fill, 1 px top hairline, in flow |
| Status strip | Chet | System bar material, 1 px bottom hairline, in flow, pushes content |
| Empty, loading, error | Chet | Text and one action. No illustration, no glass card |
| About, Settings | Chet | `paperRaised` panels, native controls |

Two hard rules follow from this table:

- Do not paint a background on chrome the system already renders. A custom
  background on `NavigationSplitView`, a toolbar, or a sheet fights Liquid
  Glass and the scroll edge effect.
- Do not place a floating control over content unless the content genuinely
  needs to pass under it. Chet has one such case today: the Storage map hover
  label, and it uses `paperRaised` plus a hairline, not glass.

## 3. Liquid Glass

The default answer for a new surface is: no custom glass.

Reason: Chet is a table of numbers. Glass moves contrast with whatever scrolls
behind it, and since macOS 27 the user controls the system glass appearance
(System Settings > Appearance, one slider from clear to opaque). A hand-drawn
glass surface cannot follow that setting, so it will disagree with the rest of
the system on some Macs.

### Allowed without review

- Native components that already use Liquid Glass: sidebar, toolbar, toolbar
  buttons, sheets, menus, alerts, popovers, search field, and the glass knob a
  slider or toggle shows during interaction.
- Nothing else.

### Allowed with a written reason

One transient control that must float over the disk map canvas, when the paper
version fails a readability check on the map. Then all of these apply:

- `glassEffect(.regular, in: <shape>)` on that control only;
- inside `GlassEffectContainer` when two or more custom glass shapes sit near
  each other (glass cannot sample glass);
- `.interactive()` when the control responds to the pointer;
- no tint, no custom blur, no custom opacity, no custom shadow behind it;
- one such container per screen, never two.

### Forbidden

| Never | Why |
|---|---|
| Glass card, glass table, glass panel, glass sheet body | Puts Liquid Glass in the content layer, which Apple advises against, and flattens hierarchy |
| Glass on glass | The second layer has nothing to refract; the result looks dirty |
| `clear` variant | It is for media backgrounds. Chet has none |
| `.regularMaterial` used to imitate Liquid Glass | It is a standard material for the content layer, not a glass substitute, and it ignores the system glass slider |
| Hardcoded blur or opacity to match the system look | It breaks when the user moves the slider |
| Tinted glass | Tint marks an action or a state, not a surface |
| Glass behind text | Text contrast must not depend on what scrolls behind it |

### Checks

- Remove the glass and put `paper` there. If the screen loses no information,
  the glass was decoration. Delete it.
- Move the system glass slider to both ends. Check the screen at both. Check
  Reduce Transparency, Increase Contrast, and Reduce Motion.
- If a custom glass control becomes unreadable at the clearest slider setting,
  the control must not be custom glass.

## 4. Geometry

- Radii come from [tokens.md](tokens.md): 0, 6, 8. No other value.
- Nested rounded content uses the system shape, not a guessed radius:

```swift
// inside a sheet, popover, or window corner
.background(Theme.paperRaised, in: ConcentricRectangle())

// a nested corner that must not undercut the token
.clipShape(.rect(corners: .concentric(minimum: .fixed(6))))
.clipShape(.rect(corners: .fixed(8)))   // when the token is the intent
```

- Use `ConcentricRectangle` or `.rect(corners:)`; they read the enclosing
  container. A fixed radius is correct only when the token is the intent.
- Do not set `buttonBorderShape` on a native button. The system shape follows
  the control size and the container. A fixed 6 pt radius is a pre-26 metric
  and fights the current control shape. `PrimaryActionButton`,
  `DestructiveActionButton`, and `SecondaryActionButton` still set it: known
  deviation, fix on the next touch of `DesignSystem.swift`.
- Do not hardcode the height of a native control. `controlSize` drives it.
  Chet's own metrics (40 pt custom row, 56 pt command bar, 32 pt custom table
  header) live in `Metrics` and apply to Chet surfaces only. A native `Table`
  keeps the system row height.
- No capsule created by the app. A capsule is allowed only where the system
  already ships one, such as the search field.

## 5. Color

Palette cap: three cores (paper, ink, hairline family) plus one accent and two
signals. Full values are in [tokens.md](tokens.md).

- The accent appears in exactly five roles: the primary action, a text action
  (`Select`, `Read again`, a sort label), the selected state, the reclaimable
  capacity segment, and the focus ring. Anything else is decoration; remove it.
- Amber means review, running, or attention. Red means destructive or
  protected. Neither ever fills a card or a strip background.
- No green. A safe state is a neutral checkmark and plain text.
- No per-category color. A category is a name plus one monochrome SF Symbol.
- Tint a native control only when it is the primary action or a selected
  state. Never tint a surface.
- Check every text/background pair in both modes against the real background.
  `inkSecondary` on `paper` is the lightest pair the app ships and must stay at
  4.5:1 or better.

## 6. Type, numbers, copy

- Use the tokens. The largest number on a screen is 34 pt. No 56 pt number, no
  rounded design, no monospace family, no all-caps label with tracking.
- Every figure that can change uses tabular digits and keeps its column.
- Never animate a number. A changing value is already motion.
- Sentence case everywhere, including section headers and buttons.
- Copy: verb first, name the consequence, one sentence per idea.
- No em dash. No "powerful", "seamless", "AI", "next generation", "effortless".
- Empty, loading, and error copy names the cause and the next action, and it
  distinguishes first run, filtered to nothing, and access denied.

## 7. States

A state delta must be structural, not a small tint shift. A user must see it
without reading a label and on any background.

| State | Required delta | Check |
|---|---|---|
| Focus | 2 pt accent ring, drawn above the surface | Visible on paper, on `accentSoft`, and on a selected row |
| Hover | border or fill change only | No scale, no shadow, no lift |
| Pressed | system control response | No custom bounce, no custom scale |
| Disabled | `inkTertiary` text, no accent, `.disabled(true)` | Still readable; no leftover highlight that reads as active |
| Error | icon plus text plus an action | Never color alone |
| Loading | `ProgressView` plus a sentence | No shimmer, no fake number |
| Empty | cause plus one next action | Differs for first run, filter, and denied |
| Selected | `accentSoft` fill plus checkbox | Never color alone |
| Review | amber `StatusLabel` with icon and text | Never a bare dot |

A disabled control keeps its text readable. It loses its accent and its hover
response, not its label.

## 8. Motion

- Only state changes: 160 ms ease-out for the status strip, 200 ms for a small
  in-row change, nothing else.
- No entry animation, no bounce, no pulse, no float, no shimmer, no symbol
  effect, no loop.
- `ProgressView` is the only continuous motion, and only while a real
  operation runs.
- Respect `accessibilityReduceMotion`. Custom transitions become instant.
- Window inactivity is system-rendered (the `appearsActive` environment value
  exists for custom UI that needs it). Do not dim or desaturate the content
  yourself.

## 9. Interaction and accessibility

- Every control is reachable by Tab in visual order, and the focus ring is
  visible at every stop.
- A custom icon-only control gets a real frame, at least the row height
  (40 pt), so the pointer target matches what the row looks like. A glyph with
  a tight frame is a hit-target bug. `IconActionButton` currently has no frame:
  known deviation.
- Every icon-only control has `accessibilityLabel` and `.help`.
- Native `Table` and `List` keep their selection, keyboard, and VoiceOver
  behavior. Do not rebuild a table to change its look.
- Status always has text. Color and icon support the text; they never carry the
  meaning alone.
- Contrast: 4.5:1 for normal text, 3:1 for large text and chart segments.
  Check both modes.
- Increase Contrast: hairlines and control borders must stay visible.
  Reduce Transparency: nothing to do, because the content layer has no custom
  transparency.
- The supported minimum is 960 x 632. Nothing clips, overlaps, or scrolls
  sideways there. The layout registry uses the same size.

## 10. Slop filter

These are the tells that the sources agree on, restated for this app.

| Tell | Rule here |
|---|---|
| Glass on every surface | Section 3. One functional layer, rendered by the system |
| Card grid, bento, one card per row | Ledger rows and tables. No cards in content |
| Floating capsule action bar | Full-width command bar, in flow, same place on every screen |
| Rainbow of category colors | One accent, monochrome symbols |
| Gradient, glow, mesh, background grid | None in the content. The app icon is the only gradient asset |
| Decorative dot or endless pulse | Status is text plus icon |
| Pill badge for every small fact | Plain text. A capsule only where the system ships one |
| Small pill above the page title | Forbidden. The title names the job |
| Sparkle, magic, star, orb icons | Forbidden. Icons name the object or the action |
| Huge display number | 34 pt maximum |
| Black box around a pretend window or terminal | Show the real app UI or nothing |
| Skeleton used as a product shot | Skeletons hold a known layout while it loads, nothing more |
| Invented numbers, testimonials, claims | Every number comes from the scan, the file system, or the inventory |
| Dead control, link to nowhere | Remove it, or disable it with a visible reason |
| Emoji in UI text | None |
| One icon library look everywhere | SF Symbols, monochrome, chosen for meaning |
| Dark interface because it looks technical | Follow the system appearance |
| Uniform spacing and rhythm in every section | Vary space by grouping. Rhythm 2: clear breaks between capacity, ledger, command bar |
| Hover as the only route to an action | The action is also in the context menu or the command bar |

## Pitfalls that already shipped

Each row is a mistake found in this tree. Read it before you write a view.

| Wrong | Right | Why |
|---|---|---|
| Painting `Theme.paper` behind content placed in the sidebar | Delete the fill; keep the hairline | The sidebar is system chrome. An opaque slab kills the system material and selection treatment |
| Building a second capacity bar in the sidebar | Reuse `CapacityBarView`, or add one compact variant to it | Two bars drift: height, radius, segment colors, and the missing reclaimable segment |
| A scan button in the toolbar, inline, and in the command bar | The command bar owns the primary action | Three calls to action make none of them primary. One per screen |
| Rendering the primary control only while `!isWorking` | Keep it, disabled, with the spinner beside it | Removing a control moves the layout and hides what is happening |
| Binding the destructive sheet button to Return | Cancel takes Return and Escape; destructive takes neither | A sheet opens with Return as default. One stray key moves files to the Trash |
| Drawing an unknown tweak as an Off switch | Replace the control with the reason text | Off says the value is known to be false. Unknown is not false |
| Leaving the detail sheet enabled when the row is disabled | Apply the same `isSupported` gate to both | The row says the app cannot read the value. The sheet then writes it |
| Building an empty state from `ContentUnavailableView` with a symbol | Title, one sentence, one action, no large icon | The component adds a large decorative symbol the design forbids |
| An icon-only button with no frame | 40 x 40 frame plus `contentShape` | The glyph becomes a 12 pt click target |
| A hint in `inkTertiary` | Use `inkSecondary` | Tertiary is 3.15:1 on light paper. Hints are informative, not disabled |
| Setting `buttonBorderShape` or a 6 pt radius on a native button | Let the system draw the shape | The fixed radius fights the current control shape and the window corner |
| One-off `.font(.system(size:))` values | Use a `Typography` token | The scale already exists. A new size makes it unknowable |
| Rendering a read failure as an empty list | Separate error state with cause and retry | Empty says "nothing here". A failure says "the app could not look" |
| A synonym for the dry-run gate | Use the exact sentence in [copy.md](copy.md) | The AX tests assert the gate text. Synonyms break the test and the promise |
| A sixth table column for a row menu | Use the context menu | The ledger is five columns by design |
| A native row highlight plus a checkbox | Checkbox selects; `accentSoft` marks the row | Two selection models make the user ask which one removes files |
| A fixed 32 pt page margin at every width | Responsive margin: 24 at 960, 32 wide | Wide margins waste the minimum window; 24 at wide widths breaks alignment |
| A decorative icon or dot with no state | Hide it from VoiceOver, or remove it | A `lock.shield` becomes an AX element named `lock.shield` with no meaning |
| A claim like "sends nothing off it" with no evidence | State the behavior, or point to the code path | The anti-slop rule applies to privacy too |
| A canvas publishing derived text (labels, names) back through `@State` written inside `updateNSView` | Compute the text in SwiftUI from the same state and size that position the thing it names | The disk-map labels landed late or not at all, so an old name sat on a tile that had moved; the click resolved the tile and drilled into a different folder than the label said |

## Field notes

Small techniques that prevent the pitfalls above.

- Use `Spacer(minLength: Spacing.s3)` beside a long label. A bare `Spacer` lets
  the label collapse the trailing control.
- A path or a long name gets `.lineLimit(1)`, `.truncationMode(.middle)`, and
  `.help(fullValue)`. Middle truncation keeps both ends of a path readable.
- Put `.contentShape(Rectangle())` only on a control that should own the whole
  area. A row that is not a button keeps its checkbox as the only click target.
- A running destructive task uses `.interactiveDismissDisabled(true)`. Escape
  must not close it; the summary is the exit.
- Use `.confirmationDialog` or `.alert` for a decision with two outcomes. Use a
  sheet when the user must read a ledger before deciding.
- Use a native `Table` for a comparison table. Use `ColumnTable` only when the
  header must stay pinned over a custom row. Do not build both in one screen.
- A checkbox is `Toggle(..., isOn:).toggleStyle(.checkbox).labelsHidden()` with
  an explicit `.accessibilityLabel("Select <name>")`.
- A composed status uses `.accessibilityElement(children: .combine)`. A purely
  decorative image gets `.accessibilityHidden(true)`.
- A color that changes with appearance comes from `Color(nsColor:)` with a
  dynamic provider. Never use `Color.white` or `.black` for text.
- A determinate `ProgressView(value:)` needs a real denominator. Without one,
  use the native indeterminate spinner and a sentence.
- Every control gets an accessibility identifier at creation time, next to its
  label. Backfilling identifiers after the test breaks is slower.
- `DRY_RUN=1` is the only safe way to exercise a removal path. Check the gate
  sentence before you touch the control.
- One piece of screen state has one producer. If a view and its canvas both
  derive from it, pass the same snapshot to both in the same render pass; do
  not let the canvas hand derived data back.
- Resolve a click against the state that renders the screen, not against a
  private copy inside the canvas. The breadcrumb and the drill must never read
  two different trees.
- When instrumenting a click path, log before the first early return. A guard
  that swallows the event looks identical to "the user never clicked".
- Probe a running app with selector-scoped dumps (`axdrv dump id=...`) and
  frame existence checks. A full-tree JSON dump twice a second starves the
  app and the probe.
- A debug copy relaunches itself when the FDA probe flips, so a pid captured
  once is stale within the minute. Re-resolve the pid every drive step and
  kill only instances you launched.

## 11. Asking an agent for UI work

An adjective tells an agent nothing. A component, an API, and a constraint do.

| Weak request | Request that holds the design |
|---|---|
| "Make the toolbar glassy" | "Keep the native toolbar. Put the scan control in a `ToolbarItem`; do not set a toolbar background" |
| "Make the corners look better" | "Use `ConcentricRectangle` for the nested image frame inside the sheet" |
| "Make the card pop" | "Use `paperRaised` plus a hairline. No shadow, no glass" |
| "Add a subtle animation" | "160 ms ease-out on the status strip only, disabled under Reduce Motion" |
| "Improve the empty state" | "Name the cause and one next action. No illustration, no large icon" |
| "Add a stat row" | "Add the reclaimable total to `PageHeader`. No stat cards" |
| "Make it feel more premium" | Reject. Name the screen job and the one focal point instead |

Before an agent edits UI, it answers these in the plan or the commit message:

1. Which screen job does this serve?
2. Which existing component already does this?
3. Is a new token needed? If yes, one line of reason.
4. Which file owns the component? The change lands there, not at the call site.
5. What happens at 960 x 632, in light, in dark, by keyboard, with Reduce
   Motion, and with the system glass slider at both ends?

Treat the Xcode Coding Assistant as a reference, not as a replacement for this
file. It does not know this app's tokens, components, or review gate.

## 12. Review gate

A UI change is done when all of these are true.

- [ ] The screen serves one job and has one focal point.
- [ ] No new color, radius, shadow, or motion without a one-line reason.
- [ ] No custom glass. Any allowed glass has a written reason and passes the
      slider check.
- [ ] No background on system chrome.
- [ ] Every control is native unless a written reason exists, and every native
      control keeps its system shape and size.
- [ ] The command bar is present whenever the screen can act, and disabled with
      a reason when it cannot.
- [ ] A destructive sheet defaults to Cancel. The destructive button does not
      take Return.
- [ ] Every icon-only control has a 40 x 40 frame, a label, and help text.
- [ ] No informative text uses `inkTertiary`.
- [ ] Every state in section 7 exists and was looked at, not assumed.
- [ ] Light and dark mode checked at 960 x 632.
- [ ] Keyboard only pass, focus visible at every stop.
- [ ] Reduce Motion, Reduce Transparency, and Increase Contrast checked.
- [ ] System glass slider checked at both ends.
- [ ] Copy has no em dash, no AI words, no invented numbers, and matches
      [copy.md](copy.md) word for word.
- [ ] `mise run build`, `mise run lint`, and `mise run layout` pass, with no
      floating chrome reported.
- [ ] The owning doc was updated in the same change: tokens, components,
      screens, or copy.
- [ ] A screenshot of the changed screen exists for both modes.

## 13. Verification recipes

Run these. Do not report a state you did not see.

1. **Build and check.** `mise run build`, `mise run lint`, `mise run layout`.
   All three pass. The layout checker reads the registry in
   [../DESIGN.md](../DESIGN.md).
2. **Launch a test copy.** `open -n --env DRY_RUN=1 <app>` for anything that can
   remove files. Never launch without the gate for a destructive path.
3. **Drive by identifier.** Build the AX driver once:
   `swiftc -O scripts/axdrv.swift ChetCore/Sources/ChetCore/AXSelector.swift -o /tmp/axdrv`. Then
   `/tmp/axdrv --pid <pid> dump --json`, `press id=home.scan`,
   `select id=sidebar.tweaks`, `texts`. The map of identifiers is in
   [../../AGENTS.md](../../AGENTS.md).
4. **Keyboard.** Tab through the screen in visual order. Every stop has a
   visible focus ring. Space activates a control, Return activates the default,
   Escape closes a sheet. A destructive default is a fail.
5. **Modes.** Check light and dark. Turn on Reduce Motion, Reduce Transparency,
   and Increase Contrast. Move the system glass appearance slider to both ends
   in System Settings > Appearance. The app must not change its own contrast,
   opacity, or motion in response.
6. **Size.** Set the window to 960 x 632. Nothing clips, overlaps, or scrolls
   sideways. Check the page header, the command bar, and the last table row.
7. **Copy.** Grep the changed strings and compare them with
   [copy.md](copy.md). The gate sentence, the dry-run verbs, and the status
   words are exact, not paraphrased.
8. **Record the limit.** If a state was not observed, write it in the change or
   the findings. "Should work" is not a check.

## 14. Corrections against the sources

The sources below were read on 2026-11-09. Several details had aged out. These
are checked against the 27.2 SDK, not against the articles. The geometry and
glass snippets in sections 3 and 4 typecheck against `MacOSX27.2.sdk` with a
macOS 26.0 deployment target.

| Claim in a source | Status | Correct form |
|---|---|---|
| `glassEffect(_:in:isEnabled:)` | Wrong. No `isEnabled` parameter | `glassEffect(_:in:)`. Use `.identity` to turn it off |
| `Glass.tint(_ color: Color)` | Incomplete | `tint(_ color: Color?)` |
| `interactive()` is iOS only | Wrong | `Glass.interactive(_:)` is available on macOS 26 and later |
| `RoundedRectangle(cornerRadius: .containerConcentric)` | Does not exist in the SDK | `ConcentricRectangle()`, or `.rect(corners: .concentric)` with `Edge.Corner.Style` |
| `.rect(cornerRadius: .containerConcentric)` for glass | Wrong | Pass a real `Shape`, for example `ConcentricRectangle()` or `.rect(corners: .fixed(8))` |
| `buttonStyle(.glass)` for secondary actions | Real on macOS 26.0, and `.glass(_:)` also typechecks against a 26.0 target | Use native `.bordered` and `.borderedProminent` for app actions. `.glass` is for chrome actions, if ever |
| `ToolbarSpacer(.fixed, spacing: 20)` | Wrong signature | `ToolbarSpacer(.fixed, placement:)`. `SpacerSizing` has no spacing value |
| `.glassProminent` with `.circle` needs `clipShape(Circle())` | Beta-era artifact, not reproduced on 27.2 | Do not add the workaround without a reproduction |
| `.regularMaterial` cards as a glass look | Obsolete as a glass substitute | It is a standard material for the content layer. It does not follow the glass slider |
| Minimum 44 pt target | iOS number | On macOS use the native control size, and give a custom icon control a 40 pt frame |
| Tab bars, `tabBarMinimizeBehavior`, bottom accessories, sheet zoom transitions | iOS and iPadOS features | Not applicable. Chet uses `NavigationSplitView` and system sheets |
| "Add Liquid Glass to cards and content" | Contradicts Apple | HIG: do not use Liquid Glass in the content layer |
| A two-state Clear/Tinted glass setting | Out of date since macOS 27 | One continuous system slider. Apps follow it; they do not imitate it |
| Custom glass should hand-tune blur, border, highlight, and shadow to feel real | Wrong direction for a native app | Let the system draw the material. A hand-tuned imitation is the failure mode |

Current SDK notes that matter here:

- `EnvironmentValues.appearsActive` tells custom UI whether the window is
  active. The system already dims chrome, so only custom content that must
  react needs it. Its availability is back-deployed; test behavior, do not
  gate on an OS version.
- `visibilityPriority(_:)` (macOS 26.1) keeps an important toolbar item
  visible as the window narrows. Use it before building a custom toolbar
  layout.
- `ToolbarOverflowMenu` and `topBarPinnedTrailing` are unavailable on macOS.
  Do not copy iOS toolbar advice into this app.
- Building with the 27 SDK refreshes the Liquid Glass appearance of native
  chrome. Re-check screenshots after an SDK bump instead of assuming nothing
  moved.

## 15. Sources

| Source | Date | What it contributes | What we reject from it |
|---|---|---|---|
| [Bitrig, Liquid Glass best practices](https://bitrig.com/blog/liquid-glass-best-practices) | Aug 2026 | Native components first, control layer only, no glass on glass, tint with meaning, concentricity, Icon Composer, the nine-question checklist | iOS framing. The control layer here is a Mac split view, not a tab bar |
| [Setproduct, Liquid glass practical guide](https://www.setproduct.com/blog/liquid-glass-design-explained-a-practical-guide) | Jan 2026 | The four stress tests: background, state, density, fallback. States must be structural. Density is the honesty test | The two-part glass stack and the tier system. Those build a glass look; this app uses paper instead |
| [giorgio-a11y, Liquid Glass guide](https://github.com/giorgio-a11y/liquid-glass-guide/blob/main/LIQUID-GLASS-GUIDE.md) | 2025 | HIG pillars, the three-layer diagram, a broad SwiftUI pattern catalog, accessibility settings table | Pre-26 material recipes used as glass, the `containerConcentric` API, 44 pt as a Mac rule |
| [Conor Luddy, iOS 26 Liquid Glass reference](https://medium.com/@madebyluddy/overview-37b3685227aa) | Nov 2025 | API inventory, glass variants, container and morphing behavior, accessibility environment values | The `isEnabled` parameter, iOS-only assumptions, iOS navigation and sheet APIs |
| [liquidglassdesign.com/ui](https://liquidglassdesign.com/ui) | undated gallery | A catalog of the look to avoid: glass cards, glow, floating capsules, marketing mockups | Essentially all of it. It is concept art, not product guidance |
| [Apple HIG, Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | change log Sep 2025 | The layer rule, regular versus clear, dimming guidance, standard materials on macOS | Nothing |
| [Apple, Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) | current | Remove custom backgrounds from chrome, scroll edge effect, button styles, `backgroundExtensionEffect`, concentric shapes, layered icons | Nothing |
| [Apple, SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) | Sep 2026 | Which APIs exist and when they arrived | Nothing |
| [WWDC26, What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/) | Jun 2026 | 27 look refresh, toolbar overflow and priority, `appearsActive`, interactive glass on macOS | Nothing |
| [9to5Mac, macOS 27 glass control](https://9to5mac.com/2026/09/22/macos-27-gives-you-more-control-over-liquid-glass/) | Sep 2026 | The system-wide appearance slider, its location, and its effect on chrome | Nothing |

## 16. Change log

| Date | Change |
|---|---|
| 2026-11-09 | First version. Merges the five requested sources, corrects the APIs against the 27.2 SDK, and ties the rules to this app's tokens and components |
| 2026-11-09 | Second version. Adds the working agreement, the shipped-pitfalls catalog, and the verification recipes. Aligns the type scale, row, command bar, window, gate copy, and Homebrew destination across the doc set |
| 2026-11-10 | Adds the disk-map pitfall (derived text published from the canvas) and field notes on single-producer state, click resolution, instrumentation, and driving a self-relaunching debug copy |
