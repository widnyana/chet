# Principles

## The position

An operating system utility should feel like part of the operating system. Not a
dashboard, not a landing page, not a branded experience placed on top of macOS.
Chet earns trust by being clear about consequences and quiet about itself.

The design language is called the **ledger**. It borrows the structure of a
well-kept account book:

- a total at the top,
- entries below it,
- a rule between the account and the action,
- one number in every row that answers the question,
- nothing in the margin that does not belong.

## The five rules

### 1. One focal point per screen

Every screen has one thing the eye lands on first.

| Screen | Focal point |
|---|---|
| Home | The reclaimable total and the capacity bar |
| Category | The size of the category and the table of entries |
| Apps | The inventory itself, with the search field |
| Homebrew | The package inventory, with the search field |
| App detail | The app name and the size of what will move |
| Storage | The map canvas |
| Settings | The single toggle |

Everything else is secondary and stays secondary. A screen with two focal
points has none.

### 2. Numbers carry the hierarchy

The product is about bytes, counts, and dates. Use tabular digits, right-align
comparisons, and keep the number in the same place from screen to screen.

- The largest figure on a screen is the answer to the screen's question.
- Secondary numbers are smaller and in secondary ink.
- Do not animate numbers. A changing number is already motion.
- Do not put a number inside a decorative shape.

### 3. Color is a signal

The surface is paper. The content is ink. The one accent is **ink blue**. It is
used for:

- the primary action,
- a text action such as `Select` or `Read again`,
- the selected state of a checkbox or row,
- the reclaimable segment of the capacity bar,
- focus rings,
- the app mark.

Amber and red are semantic, not decorative:

- **Amber** means the user must review something or an app is running.
- **Red** means destructive or protected. It appears on the destructive button
  in a confirmation sheet and on protected rows.

There is no green. "Safe" is a neutral checkmark and a normal ink label. This
keeps the palette at two cores plus one accent, with two functional signals.

### 4. Flat surfaces, real hierarchy

The app uses:

- the window background,
- a paper content background,
- 1 px hairlines,
- the native sidebar material,
- native sheets.

It does not use:

- custom glass,
- cards with shadows,
- floating capsules,
- gradient panels,
- background grids or textures,
- decorative glows.

Hierarchy comes from size, weight, space, and a hairline. If a panel needs a
border, use a hairline. If two sections need separation, use 40 pt of space.

### 5. The action is explicit

Every screen that can change files has a full-width command bar at the bottom:

- left: what is selected, in plain language and bytes;
- right: one primary action with a verb that names the consequence.

The bar is part of the window, not a floating object. It is always in the same
place. It is disabled when the action is impossible, and it says why in a
nearby status line.

The confirmation sheet repeats the consequence, the count, and the destination
(Trash). The summary sheet reports what happened. Neither is a celebration.

## Typography

Use the system font, SF Pro. It is the voice of the platform, it is legible at
every size, and it does not ask the app to perform a brand. The identity comes
from the ledger structure, not from a display face.

- Display: 34 pt semibold, tabular digits.
- Title: 24 pt semibold.
- Section: 16 pt semibold.
- Body: 15 pt regular.
- Row: 14 pt regular.
- Caption: 12 pt regular.

No rounded design. No all-caps tracking. No monospace headings. Monospaced
digits are a property of numbers, not a costume. Use the system leading; do not
set a custom line height.

## Dark mode

The app ships both modes. The paper becomes a near-black warm gray, the ink
becomes a warm off-white, and the accent becomes a lighter ink blue. The
semantic amber and red become lighter so they meet contrast on the dark paper.
The disk map receives the color scheme and uses a separate ramp. Both modes are
checked at the same time, not one after the other.

## Accessibility

- Every control is reachable by keyboard, in visual order.
- Focus is always visible. The focus ring uses the accent.
- All text meets WCAG AA against its actual background. `inkTertiary` is for
  disabled text only; informative hints use `inkSecondary`.
- Color is never the only carrier of meaning: status has text and an icon.
- Motion respects Reduce Motion. There are no loops.
- The minimum window is 960 x 632. Nothing clips or overlaps there.
- Screen readers get labels for icon-only buttons and a value for every row.

## Motion

The only motion is a state change:

- a status strip enters from the top in 160 ms,
- a sheet is presented by the system,
- a row selection uses the system highlight,
- progress changes with the system progress view.

There is no bounce, no pulse, no floating, no shimmer, and no symbol effect.
The scan is background work. The interface does not perform it.

## The identity motif

The capacity bar is the repeated gesture. It appears:

- on Home as the full disk breakdown,
- in a category header as a thin share-of-reclaimable line,
- in the disk map legend as the four-step ramp,
- in the app detail header as the share of the app that will move.

The bar is always horizontal, always uses the same ink and accent, and always
labels its segments with text. It is the one visual element that belongs to
Chet and to no other product.

## Anti-slop commitments

These are not style preferences. They are the rules the redesign must satisfy.

- No em dash in app copy or design documents. Use a period, comma, colon, or
  parentheses.
- No sparkle, star, magic, or orb icon.
- No custom gradient, glow, or glass as a default. System Liquid Glass on chrome is the only material.
- No card grid, no bento, no bar chart that repeats the ledger.
- No pill for every small fact.
- No decorative dot and no endless pulse.
- No invented numbers, testimonials, or claims.
- No dead controls. If an action cannot run, it is disabled with a reason.
- Every empty, loading, and error state names the cause and the next action.
- Every screen is checked in light and dark mode, with keyboard only.
