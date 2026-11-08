#!/usr/bin/env python3
"""Check floating UI chrome against the layout registry in docs/DESIGN.md.

The registry (a ```json block in docs/DESIGN.md) is the source of truth for where
fixed chrome sits: toolbar pill, toast, access banner, action bars, the DRY RUN
badge. This script verifies the Swift code still matches the registry, then lays
the floating pieces out on the minimum window and reports any overlap.

Run: python3 scripts/layout_check.py   (or: mise run layout)

Estimated sizes are minimums, not measured pixel heights; they are good enough to
catch structural collisions (a full-width bar under a corner badge, an overlay on
the title bar). If you move chrome, update the registry in the same commit.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs" / "DESIGN.md"
VIEWS = ROOT / "Mackit"


def load_registry():
    text = DOC.read_text()
    blocks = re.findall(r"```layout-registry\n(.*?)```", text, re.S)
    if len(blocks) != 1:
        sys.exit(f"error: expected exactly one ```layout-registry block in {DOC}, found {len(blocks)}")
    return json.loads(blocks[0])


def source(rel):
    path = ROOT / rel
    if not path.exists():
        sys.exit(f"error: registry points at missing file {rel}")
    return path.read_text()


def check_verify(entry, text, errors):
    for needle in entry.get("verify", {}).get("contains", []):
        if needle not in text:
            errors.append(f"{entry['id']}: expected snippet missing in {entry['file']}:\n    {needle}")
    for needle in entry.get("verify", {}).get("not-contains", []):
        if needle in text:
            errors.append(f"{entry['id']}: forbidden snippet present in {entry['file']}:\n    {needle}")


def rect_from_bottom_left(window, entry):
    return (
        entry["insets"]["leading"],
        window["height"] - entry["insets"]["bottom"] - entry["height"],
        entry["insets"]["leading"] + entry["width"],
        window["height"] - entry["insets"]["bottom"],
    )


def rect_from_bottom_center(window, entry):
    left = (window["width"] - entry["width"]) / 2
    return (
        left,
        window["height"] - entry["insets"]["bottom"] - entry["height"],
        left + entry["width"],
        window["height"] - entry["insets"]["bottom"],
    )


def overlaps(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


MECHANISMS = {
    "overlay-bottomLeading": rect_from_bottom_left,
    "safeAreaInset-bottom-centered-capsule": rect_from_bottom_center,
}


def main():
    registry = load_registry()
    window = registry["window"]
    errors = []
    floating = []

    for entry in registry["chrome"]:
        text = source(entry["file"])
        check_verify(entry, text, errors)
        rect_fn = MECHANISMS.get(entry["mechanism"])
        if rect_fn:
            floating.append((entry, rect_fn(window, entry)))

    # Any window-level top overlay would cover the title bar and the toolbar pill.
    # A top overlay carrying only a Divider is an in-flow separator, not chrome.
    for swift in sorted(VIEWS.rglob("*.swift")):
        text = swift.read_text()
        for match in re.finditer(r"\.overlay\(alignment: \.top[,\)]", text):
            if "Divider" in text[match.end():match.end() + 40]:
                continue
            line = text[: match.start()].count("\n") + 1
            errors.append(f"top overlay forbidden (covers the toolbar): {swift.name}:{line}")

    # Floating pieces must not intersect each other on the minimum window.
    # Bars on different surfaces never share the screen; the badge floats over any of them.
    for i, (a, ra) in enumerate(floating):
        for b, rb in floating[i + 1:]:
            # An entry without a surface (the badge) floats over every surface.
            if a.get("surface") and b.get("surface") and a["surface"] != b["surface"]:
                continue
            if overlaps(ra, rb):
                errors.append(
                    f"overlap: {a['id']} {ra} intersects {b['id']} {rb} "
                    f"at min window {window['width']}x{window['height']}"
                )

    # Human-readable map, top of window downward.
    print(f"min window {window['width']}x{window['height']}, titlebar {window['titlebar']} pt")
    for entry in registry["chrome"]:
        rect = next((r for e, r in floating if e is entry), None)
        place = f"x {rect[0]:.0f}..{rect[2]:.0f} y {rect[1]:.0f}..{rect[3]:.0f}" if rect else entry["mechanism"]
        print(f"  {entry['id']:<24} {place}")
    print()

    if errors:
        print("LAYOUT PROBLEMS:")
        for error in errors:
            print(f"  - {error}")
        sys.exit(1)
    print("layout ok: code matches the registry, no overlaps at minimum window size")


if __name__ == "__main__":
    main()
