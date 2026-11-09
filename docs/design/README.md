# Chet design system

Status: canonical direction for the UI redesign.
Date: 2026-11-08.
Scope: every SwiftUI surface, the Metal disk map, the app icon, and the copy
inside the app.

## The idea

Chet is a ledger for disk space.

It shows what is there, what can be reclaimed, and what will happen when you
act. It does not decorate the act of cleaning. The interface is quiet because
the decision is serious: files move to the Trash, apps lose their settings, and
some data cannot be rebuilt.

The product is a measuring instrument, not a dashboard and not a landing page.
The instrument is precise, legible, and calm. Its identity comes from the
ledger structure, the typography, and one repeated gesture: the capacity bar.
It does not come from a rainbow of category colors or floating glass.

## Design Read

Reading this as: a native macOS utility for people who want to reclaim disk
space, in a quiet paper-and-ink ledger language, dial ENERGY 1 / RHYTHM 2 /
MOTION 1.

- ENERGY 1: the screen does not shout. One focal point per screen.
- RHYTHM 2: consistent typography and spacing, with clear breaks between the
  capacity section, the ledger, and the command bar.
- MOTION 1: state transitions only. No loops, no bounce, no ambient motion.

## What is in this folder

| File | What it answers |
|---|---|
| [audit.md](audit.md) | What is wrong with the current UI, with file references |
| [principles.md](principles.md) | The design position and the rules that follow from it |
| [tokens.md](tokens.md) | Color, type, spacing, radius, elevation, motion |
| [components.md](components.md) | The reusable pieces and their states |
| [screens.md](screens.md) | Each screen, what it must do, and how it is composed |
| [copy.md](copy.md) | Voice, labels, empty states, and error text |
| [references.md](references.md) | Sources and the reasoning behind the direction |

The shipped summary is [../DESIGN.md](../DESIGN.md). It is the file the layout
checker reads.

## The five design rules

1. **One job per screen.** Overview answers "what can I reclaim?". A category
   answers "which of these should I remove?". The app browser answers "which app
   should I remove?". The disk map answers "where is the space?".
2. **Numbers are the content.** Every total, count, and byte figure uses
   tabular digits and a stable place. Numbers do not bounce, animate, or compete
   with decoration.
3. **Color is a signal.** The interface is paper and ink. Ink blue is the one
   accent. Amber means review. Red means destructive or protected. Nothing else
   gets a color.
4. **Flat surfaces, real hierarchy.** Sections are separated by space and
   hairlines, not cards, shadows, or glass. Native macOS controls do the work.
5. **The action is explicit.** The primary action sits in a full-width command
   bar at the bottom of the content. It says what will happen. It is disabled
   when it cannot happen.

## What is deliberately gone

- Category colors. The category is named and has a monochrome symbol.
- Glass capsules on every surface. Native materials remain only where macOS
  uses them.
- Floating action bars. They become full-width command bars.
- Sparkle and magic icons. They describe neither cleaning nor disk space.
- The bar chart on Overview. The capacity bar and the category ledger already
  answer the question.
- Decorative status dots and endless pulses.
- Bounce and symbol effects on completion screens.
- The app icon's sparkles and multi-color blue treatment. The icon uses one ink
  blue ground and a white measured disk mark.

## How to use this system

When adding a screen, decide which of the five screen jobs it serves. Use the
tokens and components in this folder. Do not introduce a new color, radius,
shadow, or motion without a one-line reason in the pull request or the plan.
If the reason cannot be written in one line, the decision is not ready.
