# Tokens

These values are the only visual primitives the app uses. A new value needs a
one-line reason and a token name. Do not hardcode a color, radius, or spacing
value in a view.

## Color

The palette is paper and ink, one accent, and two functional signals. The ratio
of neutral surface to accent should stay near 90:10. If the accent starts
appearing on more than the primary action, the selected state, the capacity bar,
and focus, it is being used as decoration.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#F6F4EF` | `#121316` | Main content background |
| `paperRaised` | `#FCFBF8` | `#191B1E` | Table header, inset areas, sheet body |
| `ink` | `#1B1C1E` | `#F2F0EA` | Primary text, titles, icons |
| `inkSecondary` | `#63635F` | `#A3A19A` | Supporting text, row locations |
| `inkTertiary` | `#8B8A83` | `#74746F` | Disabled text, hints |
| `hairline` | `#DDD9D0` | `#2C2E32` | 1 px rules and table separators |
| `accent` | `#244C9A` | `#8FA8E8` | Primary action, selection, focus, reclaimable segment |
| `accentSoft` | `#E8EDF8` | `#1B2436` | Selected row background, accent tint at low strength |
| `onAccent` | `#FFFFFF` | `#101114` | Text on an accent fill |
| `amber` | `#9A5B00` | `#E0A458` | Review, running app, attention |
| `red` | `#A3231B` | `#F08A82` | Destructive action, protected data |
| `capacityUsed` | `#D6D2C8` | `#3A3C41` | Used disk segment |
| `capacityFree` | `#E9E6DE` | `#222428` | Free disk segment |

Rules:

- `accent` is never a large background. It is a 1 px line, a 2 px focus ring, a
  checkbox, or a button fill.
- `amber` and `red` are text and icon colors. They never fill a card.
- No green. A safe state is a neutral checkmark and plain text.
- No gradient, except the app icon fill. The icon is the one allowed gradient
  because it is a platform asset, not an in-app surface.
- Every text/background pair must be checked in both modes. `inkSecondary` on
  `paper` is the lightest text the app ships and must still meet 4.5:1.

## Typography

System font: SF Pro. It is the native macOS voice and needs no download, no
license, and no fallback. Numbers use `.monospacedDigit()` so columns do not
shift as they update.

| Token | Size / line | Weight | Use |
|---|---|---|---|
| `display` | 34 / 40 | semibold | The reclaimable total, app size, summary total |
| `title` | 22 / 28 | semibold | Page title |
| `section` | 15 / 20 | semibold | Section heading |
| `body` | 14 / 20 | regular | Paragraphs, form labels |
| `row` | 13 / 18 | regular | Table cells, list rows |
| `caption` | 11 / 14 | regular | Locations, metadata, hints |
| `metric` | 17 / 22 | medium, tabular | Row size, selection total |

Rules:

- No rounded design.
- No all-caps labels with letter spacing.
- No monospace family. Monospaced digits only.
- The largest text on a screen is at most 34 pt. There is no 56 pt number.
- Body text is never smaller than 11 pt.

## Spacing

Base unit: 4 pt.

| Token | Value | Use |
|---|---|---|
| `space1` | 4 | Icon to label |
| `space2` | 8 | Inside a row |
| `space3` | 12 | Row padding, control groups |
| `space4` | 16 | Card-less section padding |
| `space6` | 24 | Page side margin at wide widths |
| `space8` | 32 | Between major sections |
| `space10` | 40 | Between the capacity hero and the ledger |
| `space12` | 48 | Page top and bottom margin |

Page content width: 880 pt maximum, centered above 1100 pt. At the minimum
window of 960 x 600, side margin is 24 pt.

## Radius

| Token | Value | Use |
|---|---|---|
| `radiusNone` | 0 | Pages, sections, command bars, tables |
| `radiusControl` | 6 | Buttons, fields, checkboxes (native) |
| `radiusMedia` | 8 | Photo and video thumbnails |
| `radiusSheet` | 0 | Sheets use the system shape |

No pill shapes. A capsule is reserved for a macOS system control that already
ships as a capsule (for example the search field), not for app-created badges.

## Elevation

| Token | Use |
|---|---|
| `elevationNone` | Everything in the content area |
| System sheet | Presented and dismissed by macOS |

No custom shadows. No glass. The sidebar uses the native sidebar material. The
command bar uses the window background plus a top hairline. The app icon is the
only place with a gradient.

## Motion

| Token | Value | Use |
|---|---|---|
| `motionQuick` | 160 ms ease-out | Status strip enters or leaves |
| `motionStandard` | 200 ms ease-out | A small state change inside a row |
| `motionNone` | 0 | Reduced Motion, and all non-essential transitions |

Rules:

- No bounce, pulse, float, shimmer, or symbol effect.
- No animation runs longer than 200 ms.
- No infinite animation.
- `ProgressView` is the only continuous motion the app ships, and only while a
  real operation is running.
- Respect `accessibilityReduceMotion`: if it is on, use `motionNone`.

## Icon sizes

| Token | Value | Use |
|---|---|---|
| `iconRow` | 22 | Table and list rows |
| `iconHeader` | 44 | Page header, app detail header |
| `iconAction` | 16 | Buttons and status labels |

SF Symbols are used at their default weight. Category symbols are monochrome
and use `inkSecondary` when inactive, `ink` when selected. No multicolor
symbols.

## Table and bar metrics

| Token | Value |
|---|---|
| Row height | 36 pt |
| Table header height | 32 pt |
| Command bar height | 52 pt plus safe-area bottom |
| Command bar top rule | 1 px `hairline` |
| Capacity bar height | 10 pt |
| Capacity bar segment gap | 1 px `paper` |
| Focus ring | 2 pt `accent` |
