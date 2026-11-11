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
| Home, never scanned | `Clean up your Mac` | `A clear account of this disk` |
| Home, results | `Clean up your Mac` | `N categories. Pick one to review.` |
| Caches | `Caches` | `N items. Apps rebuild this data.` |
| Logs | `Logs` | `N items. Apps rebuild this data.` |
| Duplicates | `Duplicates` | `N groups. One copy stays in each group.` |
| Large files | `Large and old files` | `N items. Review each item. Removed items go to the Trash.` |
| Apps | `Apps` | `N installed, M marked` |
| Homebrew | `Homebrew` | `N packages, M marked` |
| App detail | app name | `Version X, bundle ID` |
| Storage | `Storage` | `Where your space goes.` |
| Snapshots | `Local snapshots` | `macOS reports size only when deleted.` |
| Settings | `Settings` | none |
| Permission page | `Chet needs Full Disk Access` | one sentence: what macOS hides |

## Primary actions

- `Scan this Mac`
- `Stop scan`
- `Clean selected`
- `Clean`
- `Move to Trash`
- `Remove`
- `Uninstall`
- `Clear`
- `Deselect`
- `Open System Settings`
- `Reload`
- `Clear search`
- `Continue with limited results`

Do not use `Get started`, `Learn more`, `Continue`, or `Done` for an action
that has a better verb. `Done` is only for closing a sheet or leaving an
inspection surface. The one fixed exception is the permission link
`Continue with limited results`, whose text the gate test asserts.

## Risk and status copy

- Safe: `Apps rebuild this data.`
- Review: `Review each item. Removed items go to the Trash.`
- Running: `Running. Quit it before removing.`
- Admin only: `Needs administrator. Chet cannot move this app.`
- Shared: `Shared with another app. Not selected.`
- Protected: `Protected. Chet never removes this.`
- Dry run, cleaning: `Preview only. Nothing will be removed.`
- Dry run, uninstall: `Preview only. Nothing will be moved.`
- Dry run, Homebrew page: `Preview only. Nothing will be removed.`
- Dry run, tweaks: `Preview only. No tweak is changed.`
- Partial access: `Limited access. Some folders are hidden.`

One word per state. Do not invent a synonym:

| Concept | The only words |
|---|---|
| Gate, cleaning | `Preview only. Nothing will be removed.` |
| Gate, uninstall | `Preview only. Nothing will be moved.` |
| Gate, tweaks | `Preview only. No tweak is changed.` |
| Progress title, dry run | `Simulating clean` |
| Summary title, dry run | `Dry run complete` |
| Progress labels | `Items`, `Bytes`, `Freed`, `Skipped`, `Failed`, `Current` |
| Dry-run labels | `Would free`, `Would skip`, `Would fail` |
| Missing value | `Unknown` |
| Duplicate keeper | `Keep` |
| Log action | `Show audit log` |

Singular and plural both sound right: `1 item`, `2 items`, `1 app`, `2 apps`.
Never ship `1 items`.

## Empty states

Each one names the cause and the next action.

- Never scanned: `No scan yet. Run a scan to see what can be reclaimed.`
- Nothing found: `Nothing to reclaim. This Mac is tidy.`
- No app results: `No applications found. If this is unexpected, check Full Disk Access.`
- App read failure: `The applications folder could not be read. Check Full Disk Access, then reload.`
- Homebrew empty: `No Homebrew packages. Install one with brew, then reload.`
- Homebrew missing: `Homebrew is not installed. Install it from brew.sh, then reload.`
- Filter miss: `No application matches "query". Clear the search to see all apps.`
- No related files: `No related files. The app bundle can still be removed.`
- No snapshots: `No local snapshots. Time Machine keeps them only while it has room.`
- No disk map: `The disk map appears after a scan.`
- No selection: `Select an item to see the action.`

## Loading states

- `Reading applications`
- `Reading Homebrew packages`
- `Measuring the app`
- `Looking for related files`
- `Scanning caches and logs`
- `Hashing duplicates`
- `Checking snapshots`

A loading state never claims a number.

## Error states

- `The applications folder could not be read. Check Full Disk Access, then reload.`
- `The Homebrew list could not be read. Run brew list in Terminal, then reload.`
- `The disk map could not be read for this folder. Reveal it in Finder or try another folder.`
- `The snapshot command failed. Try again later.` The raw output is in the
  details disclosure.
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

Use the title that matches the set: `Clean N items?` when it mixes deletion and
Trash, `Move N items to the Trash?` for Trash only, `Delete N items?` for
permanent removal only. The subtitle is always `N items in M categories`.

Dry run adds one line. Cleaning confirmation:
`Preview only. Nothing will be removed.` App confirmation:
`Preview only. Nothing will be moved.`

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

The title follows what happened: `Removed` for a mixed set, `Moved to the
Trash` for Trash only, `Deleted` for permanent removal only. Dry run uses
`Dry run complete`.

Clean:

```
Removed
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

Apps:

```
Removed
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

## Homebrew

- Header: `N packages, M marked`.
- Actions: `Update catalog`, `Upgrade N packages`, `Install packages…`,
  `Remove old versions…`, `Uninstall`.
- Empty, no packages: `No Homebrew packages. Install one with brew, then reload.`
- Missing Homebrew: `Homebrew is not installed. Install it from brew.sh, then
  reload.`
- Error: `The Homebrew list could not be read. Run brew list in Terminal, then
  reload.`
- Gate, uninstall: `Preview only. Nothing will be removed.`
- Gate, install: `Preview only. Nothing will be installed.`
- Gate, page: `Preview only. Nothing will be removed.`
- Confirm: `Uninstall N packages?`, with `Uninstall` and, for casks,
  `Uninstall and delete data`. The message names what the data option deletes.
- Confirm, cleanup: `Remove old versions?`, with `Remove` and Cancel. The message
  names old versions and the download cache.
- Results: `Removed N packages.`, `Installed N packages.`,
  `Upgraded N packages.`, `Added the tap name.`, `Freed X.`,
  `No old versions to remove.`, `Homebrew's catalog is up to date.`
- Status: `Outdated`, `Pinned`, `Unused`, `Installed`.

## About

- Version line: `Version <v> (build <b>)`.
- Rows: `Minimum macOS`, `Full Disk Access`, `Last scan`, `Audit log`, `Logs folder`.
- Status: `Granted` or `Not granted`.
- Denied sentence: `Some folders stay hidden until you grant access.`
- Loading: `Reading this build`.
- Empty: `No scan yet`, `No log yet`; scanning: `Scanning`.
- Missing value: `Unknown`.

## Tweaks

- State: `On`, `Off`, a choice label (`PNG`), `Set to <value>`, or the reason for
  `Unsupported` / `Unknown`. Never translate an unknown value into `Off`.
- Risk: `Low risk`, `Medium risk`, `High risk`. Show the label only above low;
  low is the baseline for a reversible preference write.
- Restart: `Restart Finder to see the change.`, `Restart the Dock to see the
  change.`, `Restart the menu bar to see the change.`, `Sign out and back in to
  see the change.`
- Gate: `Preview only. No tweak is changed.`
- Empty: `No tweaks match`, `No changed tweaks`. Loading: `Reading your settings.`
- These strings live in `TweakCopy`; a view does not retype them.
