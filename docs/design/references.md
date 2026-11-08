# References and decision log

## Primary references

### Apple Human Interface Guidelines

Used for: the `NavigationSplitView` shell, sidebar behavior, toolbar placement,
table behavior, native controls, sheets, focus, and keyboard access.

What we take: macOS apps should feel like macOS. A custom visual language is
applied inside the platform's structure, not on top of it. Native controls are
the default; a custom control needs a reason.

What we do not take: the current app's use of Liquid Glass on every surface.
Glass is a system material for chrome, not a texture for content.

### macOS System Settings, Storage

Used for: the capacity bar and the language of used, reclaimable, and free
space.

What we take: a single horizontal bar with a text legend is enough to answer
"where did the space go". A second chart is not needed.

### Anti-slop core and UI skill

Used for: the Hard Gate, the Purpose Gate, the palette cap, the glass dose, the
motion rules, the accessibility requirements, and the Delivery Gate.

What we take: every technique needs a written reason. The design is checked
against the gate before delivery. The current audit cites the rules that the
redesign resolves.

### Dieter Rams, ten principles of good design

Used for: "as little design as possible", "good design is unobtrusive", and the
idea that a tool should recede when the user is working.

What we take: the interface does not perform. It gives the user the number and
the action, then gets out of the way.

### Edward Tufte, The Visual Display of Quantitative Information

Used for: the decision to remove the overview bar chart and the two-channel
treemap encoding.

What we take: data ink should carry data. A chart that repeats a list is
chartjunk. One encoding per mark is clearer than two.

### WCAG 2.2

Used for: contrast, focus visibility, keyboard operation, target size, and the
rule that color is never the only carrier of meaning.

What we take: every text/background pair is checked in light and dark mode. The
semantic colors always have a label and an icon.

### SF Pro and SF Symbols

Used for: typography and iconography.

Why: the system font is the native voice of macOS, it is legible at every size,
and it avoids a downloaded display face that would date the app. SF Symbols
provide a consistent optical weight and accessibility metadata.

What we avoid: multicolor symbols, sparkle and magic glyphs, and icons chosen
only because they are available.

## Decision log

Each line is the one-line reason required by R-31.

| Decision | Reason |
|---|---|
| Paper and ink palette | A utility is read, not watched. A warm neutral surface keeps the numbers in front. |
| One accent, ink blue | The primary action and the selected state need one signal. Blue is the least ambiguous action color after red is reserved for destructive. |
| No green | Green would add a third semantic color and imply safety that the data does not guarantee. Safe is a neutral checkmark. |
| Amber for review | Review is a caution, not a failure. Amber carries caution without competing with the red destructive action. |
| Red for destructive and protected | The two states that can lose data must be the strongest signal. |
| SF Pro | Native voice, no licensing, no download, no fallback, and the best small-size legibility on macOS. |
| 34 pt maximum number | The number is important but the screen is a tool, not a poster. |
| No cards | Cards add a second background and a third border. Hairlines and space are enough. |
| One command bar | The action must be in the same place on every screen. Floating capsules make the action move. |
| No glass | Glass flattens hierarchy when it is everywhere. The native sidebar material is the only material. |
| No overview chart | The category ledger is the chart. A bar chart repeats it and adds chartjunk. |
| Capacity bar | The disk is the product's subject. One bar with a text legend answers the top-level question. |
| Ledger table | Tables are the right tool for comparing size, date, and risk across many files. |
| Monochrome category symbols | The symbol is recognition, not identity. The name carries the meaning. |
| Neutral disk map ramp | One encoding per mark. Size is the question; category is not. |
| No decorative dots or pulses | Motion must explain a state. A dot that marks nothing is noise. |
| Top status strip instead of toast | A global state should push content, not cover it. |
| Permission page without a card | Access is a system task. It needs a sentence and a button, not a ceremony. |
| Measured disk icon | The app is about measuring and reclaiming disk space. A ring with a missing segment says that without sparkles, on one ink blue ground. |
| List as the default app layout | An uninstaller is a comparison task: name, publisher, size, status. The list supports that better than a grid. |
| Grid as a secondary layout | Some users recognize apps by icon. The grid is available, not primary. |
| No bulk operation without a mark | Bulk removal is destructive. The user must mark each app, then confirm the set. |
| Dry run is a top strip and a verb change | A debug gate must be impossible to mistake for a real removal. |

## Design Read

Reading this as: a native macOS utility for people who want to reclaim disk
space, in a quiet paper-and-ink ledger language, dial ENERGY 1 / RHYTHM 2 /
MOTION 1.

Why this read:

- Audience: Mac users, technical and non-technical. They want a clear answer,
  not a brand performance.
- Product kind: system utility. The operating system is the host; the app should
  not fight it.
- Visual language: paper and ink, one accent, tabular numbers, hairlines.
- ENERGY 1: the screen does not shout. The product's seriousness is the point.
- RHYTHM 2: the screens differ by job, not by decoration. Overview has the
  capacity hero, category has the table, disk map has the canvas, applications
  has the inventory.
- MOTION 1: state changes only. The scan is background work, not a show.

## What we deliberately did not use

- No reference to Linear, Vercel, Stripe, or Notion as a visual template.
- No Dribbble or landing-page trend as a direction.
- No blue-purple gradient, glow, or mesh.
- No bento grid, testimonial bar, pricing tier, or other landing-page section.
- No fake metrics or screenshots. Every number in the app comes from the scan,
  the file system, or the app inventory.
