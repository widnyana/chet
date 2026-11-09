#!/usr/bin/env python3
"""Extract the accessibility selectors of a running Chet window into a JSON file.

The macOS accessibility tree is the closest thing a desktop app has to a DOM. This script
calls `scripts/axdrv.swift` with `dump --json`, drops per-app inventory rows so the saved
file is stable across machines, and merges the result into `docs/ui-selectors.json` under a
screen name.

Usage:
    python3 scripts/ui_selectors.py --pid 1234 --screen apps
    python3 scripts/ui_selectors.py --list
    python3 scripts/ui_selectors.py --screen home --out /tmp/selectors.json

Exit codes:
    0  selectors written
    1  no Chet process, or several without --pid
    2  axdrv could not run or returned no JSON
"""

from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AXDRV_SOURCE = ROOT / "scripts" / "axdrv.swift"
AXDRV_BIN = ROOT / ".build" / "ui-selectors" / "axdrv"
DEFAULT_OUT = ROOT / "docs" / "ui-selectors.json"


def built_binary() -> Path:
    """Compile axdrv when its source is newer than the binary."""
    if AXDRV_BIN.exists() and AXDRV_BIN.stat().st_mtime >= AXDRV_SOURCE.stat().st_mtime:
        return AXDRV_BIN
    AXDRV_BIN.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["swiftc", "-O", "-o", str(AXDRV_BIN), str(AXDRV_SOURCE)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(2)
    return AXDRV_BIN


def chet_pids() -> list[int]:
    result = subprocess.run(["pgrep", "-x", "chet"], capture_output=True, text=True)
    return [int(line) for line in result.stdout.split() if line.strip()]


def resolve_pid(requested: int | None) -> int:
    if requested is not None:
        return requested
    pids = chet_pids()
    if not pids:
        raise SystemExit("No Chet process is running. Start one with `mise run dev`.")
    if len(pids) > 1:
        listing = ", ".join(str(pid) for pid in pids)
        raise SystemExit(
            f"Several Chet processes are running ({listing}). "
            "Pick one with --pid so the dump cannot come from another instance."
        )
    return pids[0]


def per_app_label(node: dict) -> bool:
    description = node.get("description", "")
    return description.startswith("Show files left by ") or description.startswith("Select ")


def dump(pid: int) -> dict:
    binary = built_binary()
    result = subprocess.run(
        [str(binary), "--pid", str(pid), "dump", "--json"], capture_output=True
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode("utf-8", "replace"))
        raise SystemExit(2)
    payload = json.loads(result.stdout)
    for node in payload["nodes"]:
        if (node.get("id") or "").startswith("SwiftUI."):
            node.pop("id", None)
    nodes = [node for node in payload["nodes"] if not per_app_label(node)]
    windows = [
        {"role": "AXWindow", "title": node.get("title", "")}
        for node in nodes
        if node.get("role") == "AXWindow"
    ]
    return {"pid": payload["target"]["pid"], "windows": windows, "nodes": nodes}


def summarise(payload: dict) -> None:
    nodes = payload["nodes"]
    roles: dict[str, int] = {}
    identifiers = []
    for node in nodes:
        roles[node["role"]] = roles.get(node["role"], 0) + 1
        if node.get("id"):
            identifiers.append(node["id"])
    print(f"pid {payload['pid']}: {len(nodes)} nodes in {len(payload['windows'])} window(s)")
    for role, count in sorted(roles.items(), key=lambda item: (-item[1], item[0])):
        print(f"  {count:4d}  {role}")
    if identifiers:
        print("Identifiers:")
        for identifier in sorted(set(identifiers)):
            print(f"  {identifier}")


def merge_into(path: Path, screen: str, payload: dict) -> None:
    document: dict = {}
    if path.exists():
        try:
            document = json.loads(path.read_text())
        except json.JSONDecodeError:
            document = {}
    document.setdefault("screens", {})
    document["generatedAt"] = subprocess.run(
        ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True
    ).stdout.strip()
    document["screens"][screen] = {
        "pid": payload["pid"],
        "windows": payload["windows"],
        "selectors": payload["nodes"],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    print(f"{path}: screen `{screen}` has {len(payload['nodes'])} selectors")


def main() -> None:
    # A closed pipe (`| head`) should end the summary quietly, not raise.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, help="PID of the Chet instance to inspect")
    parser.add_argument("--screen", default="current", help="screen key stored in the JSON")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output JSON file")
    parser.add_argument("--list", action="store_true", help="print a summary, write nothing")
    args = parser.parse_args()

    if not AXDRV_SOURCE.exists():
        raise SystemExit(f"missing {AXDRV_SOURCE}")

    payload = dump(resolve_pid(args.pid))
    if not args.list:
        merge_into(args.out, args.screen, payload)
    summarise(payload)


if __name__ == "__main__":
    main()
