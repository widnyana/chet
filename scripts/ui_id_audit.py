#!/usr/bin/env python3
"""Audit a running Chet window for duplicate and missing accessibility identifiers.

Usage:
    python3 scripts/ui_id_audit.py --pid 1234 --screen overview
    python3 scripts/ui_id_audit.py --pid 1234 --require mise.page --require mise.header
    python3 scripts/ui_id_audit.py --dump /tmp/dump.json --require tweaks.empty

Exit codes:
    0  no duplicate identifier and every required identifier is present
    1  a duplicate, a missing identifier, or a failed dump
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ui_selectors

USAGE = (
    "python3 scripts/ui_id_audit.py --pid <pid> [--screen <name>] "
    "[--require <id> ...] [--expected <path>] [--dump <path>]"
)
IDENTIFIER = re.compile(r"^[a-z][a-z0-9]*(?:\.[A-Za-z0-9_<>*:@./ -]+)+$")
BACKTICK = re.compile(r"`([^`\n]+)`")
HEADING = re.compile(r"^#{1,6}\s+")


class DumpFailure(Exception):
    pass


def driver_binary() -> Path:
    override = os.environ.get("AXDRV")
    if override:
        path = Path(override).expanduser()
        if not path.is_file():
            raise DumpFailure(f"AXDRV is not a file: {path}")
        return path
    if ui_selectors.AXDRV_BIN.exists():
        return ui_selectors.built_binary()
    fallback = Path("/tmp/axdrv")
    if fallback.is_file():
        return fallback
    return ui_selectors.built_binary()


def nodes_from(payload: object) -> list[dict]:
    if not isinstance(payload, dict):
        raise DumpFailure("dump is not a json object")
    nodes = payload.get("nodes")
    if not isinstance(nodes, list):
        raise DumpFailure("dump has no nodes array")
    kept: list[dict] = []
    for node in nodes:
        if not isinstance(node, dict):
            continue
        identifier = node.get("id")
        if isinstance(identifier, str) and identifier.startswith("SwiftUI."):
            node = {key: value for key, value in node.items() if key != "id"}
        kept.append(node)
    return kept


def read_dump(pid: int | None, path: Path | None) -> list[dict]:
    if path is not None:
        try:
            payload = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise DumpFailure(f"{path}: {error}") from error
        return nodes_from(payload)
    binary = driver_binary()
    result = subprocess.run(
        [str(binary), "--pid", str(pid), "dump", "--json"],
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise DumpFailure(detail or f"axdrv exited {result.returncode}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise DumpFailure(f"axdrv returned invalid json: {error}") from error
    return nodes_from(payload)


def identifier_counts(nodes: list[dict]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for node in nodes:
        identifier = node.get("id")
        if isinstance(identifier, str) and identifier:
            counts[identifier] += 1
    return counts


def placeholder_prefix(requirement: str) -> str | None:
    positions = [
        position
        for position in (requirement.find("*"), requirement.find("<"))
        if position >= 0
    ]
    if not positions:
        return None
    return requirement[: min(positions)]


def identifier_section(text: str) -> str:
    lines = text.splitlines()
    headings = [index for index, line in enumerate(lines) if HEADING.match(line)]
    for keyword in ("identifier", "selector"):
        for position, start in enumerate(headings):
            title = HEADING.sub("", lines[start]).strip().lower()
            if (title.startswith(keyword) if keyword == "identifier" else keyword in title):
                end = headings[position + 1] if position + 1 < len(headings) else len(lines)
                return "\n".join(lines[start:end])
    return text


def expected_identifiers(path: Path) -> list[str]:
    section = identifier_section(path.read_text())
    pattern = re.search(r"Identifiers are\s+`([^`]+)`", section)
    pattern_token = pattern.group(1).strip() if pattern else None
    tokens: list[str] = []
    for match in BACKTICK.finditer(section):
        token = match.group(1).strip()
        if not IDENTIFIER.fullmatch(token):
            continue
        if token == pattern_token:
            continue
        following = section[match.end() : match.end() + 24].lstrip().lower()
        if following.startswith("description"):
            continue
        tokens.append(token)
    return tokens


def unique_requirements(requirements: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for requirement in requirements:
        if requirement not in seen:
            seen.add(requirement)
            ordered.append(requirement)
    return ordered


def report(counts: Counter[str], requirements: list[str]) -> bool:
    for identifier in sorted(counts):
        print(f"{counts[identifier]}  {identifier}")
    absent: list[str] = []
    for requirement in requirements:
        prefix = placeholder_prefix(requirement)
        if prefix is None:
            present = requirement in counts
        else:
            present = any(identifier.startswith(prefix) for identifier in counts)
        if not present:
            absent.append(requirement)
    for requirement in sorted(absent):
        print(f"0  {requirement}")
    duplicates = sum(1 for count in counts.values() if count > 1)
    print(f"duplicates: {duplicates}")
    print(f"missing: {len(absent)}")
    return duplicates == 0 and not absent


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        usage=USAGE,
        description="Audit accessibility identifiers for duplicates and missing ids.",
    )
    parser.add_argument("--pid", type=int, help="PID of the Chet instance to inspect")
    parser.add_argument("--screen", default="app", help="label printed in the report")
    parser.add_argument(
        "--require",
        action="append",
        default=[],
        metavar="ID",
        help="identifier that must appear; repeatable",
    )
    parser.add_argument(
        "--expected",
        type=Path,
        help="markdown file whose identifier section lists expected identifiers",
    )
    parser.add_argument(
        "--dump",
        type=Path,
        help="read a saved axdrv dump instead of a running app",
    )
    return parser


def main() -> int:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = build_parser()
    args = parser.parse_args()
    if args.dump is None and args.pid is None:
        parser.error("--pid is required unless --dump is given")
    print(f"screen: {args.screen}")
    try:
        nodes = read_dump(args.pid, args.dump)
        expected = expected_identifiers(args.expected) if args.expected else []
    except DumpFailure as error:
        print(f"dump failed: {error}", file=sys.stderr)
        print("verdict: fail")
        return 1
    except (OSError, SystemExit) as error:
        print(f"audit failed: {error}", file=sys.stderr)
        print("verdict: fail")
        return 1
    requirements = unique_requirements(args.require + expected)
    counts = identifier_counts(nodes)
    passed = report(counts, requirements)
    print(f"verdict: {'pass' if passed else 'fail'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
