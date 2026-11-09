# Copy and voice

Chet speaks like a careful person who knows the machine. It is direct, calm,
and specific. It does not sell, reassure with slogans, or apologize for the
work.

## Rules

- Verb first. `Scan this Mac`, `Clean selected`, `Move to Trash`, `Quit Chrome`.
- Say what will happen. `The app and selected files move to the Trash.` Not
  `This action cannot be undone` unless it is true.
- Use the user's words for things: `app`, `file`, `folder`, `Trash`.
- Keep one sentence per idea.
- No em dash. Use a period, comma, colon, or parentheses.
- No sparkle, magic, AI, seamless, effortless, powerful, or revolutionary.
- No invented numbers, quotes, or claims.
- Use `Review` only when the user must look at an item before removing it.
- Use `Exact match`, `Name match`, `Shared`, `Needs administrator`, and
  `Protected` exactly as they are defined in the app model. Do not invent a
  sixth state.

## Page titles and subtitles

| Screen | Title | Subtitle |
|---|---|---|
| Overview, never scanned | `Overview` | `A clear account of this disk` |
| Overview, results | `Overview` | `N categories, X can be reclaimed` |
| Caches | `Caches` | `X across N items. Apps rebuild this data.` |
| Logs | `Logs` | `X across N items. Apps rebuild this data.` |
| Duplicates | `Duplicates` | `X across N groups. One copy stays in each group.` |
| Large files | `Large and old files` | `X across N items. Review before removing.` |
| Applications | `Applications` | `N installed, M marked` |
| App detail | app name | `Version X, bundle ID` |
| Disk map | `Disk map` | `Where the space is` |
| Snapshots | `Local snapshots` | `N snapshots. macOS reports size when deleted.` |
| Settings | `Settings` | none |

## Primary actions

- `Scan this Mac`
- `Stop scan`
- `Clean selected`
- `Clean`
- `Move to Trash`
- `Remove`
- `Open System Settings`
- `Reload`
- `Clear search`

Do not use `Get started`, `Learn more`, `Continue`, or `Done` for an action
that has a better verb. `Done` is only for closing a sheet or leaving an
inspection surface.

## Risk and status copy

- Safe: `Apps rebuild this data.`
- Review: `Review each item. Removed items go to the Trash.`
- Running: `Running. Quit it before removing.`
- Admin only: `Needs administrator. Chet cannot move this app.`
- Shared: `Shared with another app. Not selected.`
- Protected: `Protected. Chet never removes this.`
- Dry run: `Dry run. No files will be moved.`
- Partial access: `Limited access. Some folders are hidden.`

## Empty states

Each one names the cause and the next action.

- Never scanned: `No scan yet. Run a scan to see what can be reclaimed.`
- Nothing found: `Nothing to reclaim. This Mac is tidy.`
- No app results: `No applications found. If this is unexpected, check Full Disk Access.`
- Filter miss: `No application matches "query". Clear the search to see all apps.`
- No related files: `No related files. The app bundle can still be removed.`
- No snapshots: `No local snapshots. Time Machine keeps them only while it has room.`
- No disk map: `The disk map appears after a scan.`
- No selection: `Select an item to see the action.`

## Loading states

- `Reading applications`
- `Measuring the app`
- `Looking for related files`
- `Scanning caches and logs`
- `Hashing duplicates`
- `Checking snapshots`

A loading state never claims a number.

## Error states

- `The applications folder could not be read. Check Full Disk Access, then reload.`
- `The disk map could not be read for this folder. Reveal it in Finder or try another folder.`
- `The snapshot command failed. macOS returned: [message].`
- `Chet could not move this item. It may have changed since the scan.`
- `Chet could not move this app. An administrator may need to remove it.`

The first line names the failed action. The second names the likely cause and
the next action. The raw error is secondary.

## Confirmation copy

Single app:

```
Remove Chrome?
5 items, 920.3 MB

The app and selected files move to the Trash.
Each item is checked again before it moves.
Cancel | Move to Trash
```

Bulk:

```
Remove 3 apps?
2.4 GB total
Chrome, Slack, Figma

Each app bundle and its exact-match Library files move to the Trash.
Running apps are skipped.
Cancel | Move 3 to Trash
```

Clean:

```
Clean 12.4 GB?
34 items in 6 categories
8.2 GB is deleted now. Apps rebuild it.
4.2 GB moves to the Trash.
Every item is checked again before removal.
Cancel | Clean
```

Dry run adds one line: `Dry run. No files will be moved.`

## Clean progress copy

```
Cleaning                      42%
Item 12 of 34

Items      11 of 34
Bytes      2.4 GB of 10.4 GB
Freed      2.3 GB
Skipped    1
Failed     0
Current    ~/Library/Caches/com.example.app/cache.db
           Folder - Deleting - 18 MB
```

Dry run:

```
Simulating clean
Would free 2.3 GB
Would skip 1
```

When the item list is finished and snapshots are still being removed:

```
Finishing the snapshot removal
```

No busy word, no apology, no percentage without a denominator. If the total is
not known yet, the subtitle says `Preparing the clean pass`.

## Summary copy

Clean:

```
Clean complete
12.4 GB freed
32 of 34 items cleaned
2 items left alone
[Show audit log] [Done]
```

Dry run:

```
Dry run complete
12.4 GB would be freed
32 of 34 items would be cleaned
Nothing was deleted.
```

Applications:

```
Uninstall complete
920.3 MB moved to the Trash
5 of 5 items moved
[Done]
```

Bulk:

```
Uninstall complete
2.4 GB moved to the Trash
17 of 19 items across 3 apps moved
2 items left alone
```

## Accessibility labels

- Icon-only button: the action, not the icon name. `Pause scan`, not
  `pause.fill`.
- Checkbox: `Select <name>` or `Remove <name>`.
- Status label: the status text is the label, and it is visible.
- Capacity bar: `Used X, reclaimable Y, free Z`.
- Disk map block: `Folder name, size, share of parent`.
- Confirmation button: the full consequence, `Move Chrome and 5 items to Trash`.

## Anti-slop checklist for copy

- No em dash.
- No generic CTA.
- No AI marketing word.
- No claim without evidence.
- No line that could belong to any cleaner app after swapping the name.
- No apology or filler.
- No exclamation mark.
