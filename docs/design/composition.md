# Composition

Status: rules for adding a view, layout, page, or component.
Date: 2026-11-09.

This file answers one question: how do I add UI without making a second
version of the design system?

Values live in [tokens.md](tokens.md). Component anatomy lives in
[components.md](components.md). Screen jobs live in [screens.md](screens.md).
Layer and Glass rules live in [ui-guidelines.md](ui-guidelines.md). This file
only covers composition.

## The rule

A screen composes shared parts. It does not rebuild a pattern, and it does not
set geometry on a call site.

If two screens need the same thing, it is a component. If one screen needs a
variant, the variant is a parameter. If a component needs a third copy, stop and
extract it.

## Decision tree

Before writing a view:

1. Is this a new job? Name it in [screens.md](screens.md). If the screen has two
   jobs, split it.
2. Does an existing component already do this? Use it.
3. Does it need one more state or one more column? Add a parameter to the owner.
4. Is it a local arrangement of existing components? A private subview in the
   screen file is enough.
5. Is it a new visual pattern that a second screen will need? Add it to
   `DesignSystem.swift` or the feature parts file, with anatomy in
   [components.md](components.md).
6. Is it a new value? Add the token first, with a reason in
   [tokens.md](tokens.md).

Never start at step 5. Most requests stop at step 2 or 4.

## Page recipe

Every content destination uses the page scaffold in
[components.md](components.md#page-scaffold).

The order is fixed:

1. Toolbar items: native `ToolbarItem` only. No toolbar background.
2. `PageHeader`: title, one-sentence subtitle, optional metric, hairline.
3. State: content, or exactly one of loading, empty, error, filtered empty.
4. Inventory or content block.
5. `CommandBar` through `safeAreaBar` when the page can act.
6. Sheets attach to the page that owns the action.

Do not add a second header, a card wrapper around a table, or page-level
padding on a child. The page scaffold and the table own the margin.

Every state uses the same margin as the normal content. A loading state that
starts at the window edge while the table starts at the page margin is a bug.

## Layout recipe

Choose the layout by the question, not by taste:

| Question | Layout |
|---|---|
| Compare many rows on several facts | `ColumnTable` |
| Recognize an object visually | Grid of `AppCell` or media cards |
| Read one object and choose parts | Detail page with rows and a command bar |
| Change preferences | Native `TabView` and `SettingsPanel` |
| Confirm a destructive action | `SheetFrame` with a ledger and two actions |
| Report a short global state | `StatusStrip` |

A grid is not a table with bigger rows. A table is not a stack of cards. Do not
mix the two in one page.

### Tables

Use `ColumnTable`. It owns the pinned header, the header rule, row rules, and
the page margin. A screen supplies:

- the items;
- its header view, built from `SortColumnButton`;
- its row view, built from the page's row components.

Rows use 40 pt, one line of primary text, one optional caption line, and a
trailing status. A row does not set its own horizontal margin or its own
vertical padding. If a row needs a new column, add it to the screen's column
enum and keep the header and row on the same widths.

### Pages that share a shape

Apps, Homebrew, Category, and Snapshots share one shape. When one changes, check
the other three. They must keep the same:

- page margin and header spacing;
- checkbox column, icon gutter, header height, row height;
- selected row fill;
- empty, loading, and error scaffold;
- command bar placement and disabled reason.

The data differs. The geometry does not.

## Component recipe

A new component is justified when:

- the pattern appears in at least two places, or
- the pattern has state, accessibility, or focus behavior that must not be
  copied, or
- the pattern is a system boundary such as a sheet, table, or bar.

A component owns:

- its padding, height, radius, and column widths;
- its default, hover, focus, selected, disabled, loading, and error states;
- its accessibility label, value, hint, and identifier convention;
- its keyboard shortcut and focus ring when it is interactive.

A component API has:

- required content first;
- variants as parameters with defaults;
- one action closure, not a configuration object;
- no screen-specific copy inside the component.

Good:

```swift
ColumnTable(items: packages) {
    SortColumnButton(title: "Name", isActive: sort == .name, ascending: ascending) {
        sort = .name
    }
} row: { package in
    HomebrewRow(package: package)
}
```

Bad:

```swift
ScrollView {
    LazyVStack {
        header.padding(.horizontal, 24)
        ForEach(packages) { package in
            row(package).padding(.horizontal, 24)
        }
    }
}
```

The bad version has no pinned header, two margin literals, and two things to
change when the page margin changes.

## Shared parts

Use these before writing a view:

| Need | Component |
|---|---|
| Page title and metric | `PageHeader` |
| Table surface | `ColumnTable` |
| Sortable column label | `SortColumnButton` |
| Bottom action bar | `CommandBar` + `safeAreaBar` |
| Dry-run gate | `PreviewNotice` |
| Short status | `StatusLabel` |
| Empty, loading, error | `EmptyStateView`, `LoadingStateView`, `ErrorStateView` |
| Primary, secondary, destructive action | `PrimaryActionButton`, `SecondaryActionButton`, `DestructiveActionButton` |
| Icon action | `IconActionButton` |
| Sheet shell | `SheetFrame` |
| Capacity bar | `CapacityBarView` |
| Page margin | `pageHorizontalPadding()` |
| Focus ring | `focusRing()` |

If a screen uses a different control, state why in the review and update
[components.md](components.md). A one-off control is a design decision, not a
detail.

## Anti-patterns

- A `padding(.horizontal, 24)` or `padding(.horizontal, 32)` at a call site.
  Use `pageHorizontalPadding()`.
- A local header `HStack` beside a `ColumnTable` with different widths.
- A second copy of a row, button, empty state, or gate label.
- A fixed height that does not come from `Metrics`.
- A component that takes a screen's copy string.
- A view that sets `foregroundStyle` to imitate a selected state.
- A custom background on system chrome.
- Glass on content. Native Glass belongs to chrome and controls.
- A layout that has no loading, empty, or error state.

## Review gate

Before a new page or component is done:

1. It uses the page scaffold and the page margin.
2. It uses existing components. Any new one has anatomy in
   [components.md](components.md).
3. Header and row columns share one width table.
4. Loading, empty, error, and filtered empty use the same margin.
5. The command bar is present and disabled with a reason when no selection
   exists.
6. Keyboard focus is visible and the primary action has a shortcut.
7. VoiceOver reads the action and its object.
8. Light, dark, 960 x 632, Reduce Motion, Reduce Transparency, and Increase
   Contrast are checked.
9. The owning doc is updated in the same change. No code and doc contradiction
   is allowed to land.
