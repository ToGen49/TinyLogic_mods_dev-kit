#!/usr/bin/env python3
"""Validate a Tiny Logic mod folder.

Usage:
    validate.py <mod-folder> [<mod-folder> ...]
    validate.py --kit <kit-root>          # validates template/ and examples/*

Checks:
  1. mod.json       — present, valid JSON, required keys, right types, id == folder name
  2. main.lua       — exists? balanced-ish Lua, no forbidden globals (io, os, require, ...)
  3. tl.* usage     — every tl.x / tl.x.y referenced must exist in api/api.json
  4. graph.json     — present? valid JSON, nodes have id/type, links reference real nodes

Exit code 0 = all good, 1 = at least one error. Warnings do not fail the run.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------- files

REQUIRED_KEYS = {
    "id": str,
    "name": str,
    "author": str,
    "version": str,
    "description": str,
    "enabled": bool,
}
OPTIONAL_KEYS = {"icon": str, "tags": list}

# Globals that exist in the VM but are NOT given to a mod's sandbox.
FORBIDDEN = {
    "io": "no file access in the sandbox",
    "os": "no os library in the sandbox",
    "require": "no module system — use tl.require(id)",
    "package": "no package library in the sandbox",
    "debug": "no debug library in the sandbox",
    "load": "load() is not available to mods",
    "loadfile": "loadfile() is not available to mods",
    "dofile": "dofile() is not available to mods",
    "loadstring": "loadstring() does not exist in Lua 5.5",
    "host": "host.* is the launcher-side table; use tl.*",
    "collectgarbage": "not provided to mods",
    # `print` is deliberately absent: it is allowed, routed to the mod console.
}

# `tl.foo` or `tl.foo.bar` used in code.
TL_CALL = re.compile(r"\btl\.([a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)?)")
# Bare forbidden global, not preceded by a dot (avoids `x.io` or `string.io`).
GLOBAL_USE = re.compile(r"(?<![\w.:])\b(io|os|require|package|debug|load|loadfile|dofile|loadstring|host|collectgarbage)\b")


# --------------------------------------------------------------------------- helpers

class Report:
    def __init__(self, label: str) -> None:
        self.label = label
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def flush(self) -> bool:
        tag = "FAIL" if self.errors else "ok  "
        print(f"[{tag}] {self.label}")
        for m in self.errors:
            print(f"        error:   {m}")
        for m in self.warnings:
            print(f"        warning: {m}")
        return not self.errors


def load_api(kit: Path) -> tuple[set[str], set[str]]:
    """Return (all names, group prefixes) from api/api.json."""
    path = kit / "api" / "api.json"
    if not path.is_file():
        return set(), set()
    data = json.loads(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    groups: set[str] = set()
    for g in data.get("groups", []):
        for item in g.get("items", []):
            name = item.get("name", "")
            names.add(name)
            parts = name.split(".")
            if len(parts) > 2:
                groups.add(".".join(parts[:2]))
    return names, groups


# --------------------------------------------------------------------------- checks

def check_mod_json(folder: Path, rep: Report) -> dict | None:
    path = folder / "mod.json"
    if not path.is_file():
        rep.err("mod.json is missing")
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        rep.err(f"mod.json is not valid JSON: {e}")
        return None

    if not isinstance(data, dict):
        rep.err("mod.json must be a JSON object")
        return None

    for key, kind in REQUIRED_KEYS.items():
        if key not in data:
            rep.err(f"mod.json is missing required key `{key}`")
        elif not isinstance(data[key], kind):
            rep.err(f"mod.json `{key}` should be {kind.__name__}, got {type(data[key]).__name__}")

    unknown = set(data) - set(REQUIRED_KEYS) - set(OPTIONAL_KEYS)
    if unknown:
        rep.warn(f"mod.json has keys this kit doesn't recognise: {', '.join(sorted(unknown))}")

    mod_id = data.get("id")
    if isinstance(mod_id, str):
        # The kit's template/ is not a mod: `id` there is a placeholder by design.
        if folder.name == "template":
            if mod_id != "my-mod":
                rep.warn(f"template id is `{mod_id}` — expected the placeholder `my-mod`")
        else:
            if mod_id != folder.name:
                rep.err(f"mod.json id `{mod_id}` != folder name `{folder.name}`")
            if mod_id != mod_id.lower() or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", mod_id):
                rep.warn(f"id `{mod_id}` should be lowercase letters, digits, `-` or `_`")

    return data


def check_script(folder: Path, api_names: set[str], api_groups: set[str], rep: Report) -> None:
    path = folder / "main.lua"
    graph = folder / "graph.json"
    has_graph = graph.is_file() and graph.stat().st_size > 2

    if not path.is_file():
        if has_graph:
            print(f"        note:    no main.lua — graph-only mod")
        else:
            rep.err("neither main.lua nor graph.json: a mod needs at least one of them")
        return

    source = path.read_text(encoding="utf-8", errors="replace")

    if not source.strip():
        if has_graph:
            print(f"        note:    empty main.lua — graph-only mod")
        else:
            rep.err("main.lua is empty and there is no graph.json")

    # --- balanced delimiters (a cheap syntax smoke test; Lua itself is the judge)
    stripped = re.sub(r"--\[\[.*?\]\]", "", source, flags=re.S)
    stripped = re.sub(r"--[^\n]*", "", stripped)
    for open_c, close_c in (("(", ")"), ("{", "}"), ("[", "]")):
        if stripped.count(open_c) != stripped.count(close_c):
            rep.warn(f"main.lua has unbalanced `{open_c}{close_c}` "
                     f"({stripped.count(open_c)} vs {stripped.count(close_c)}) — check your strings/comments")

    # --- forbidden globals
    for m in GLOBAL_USE.finditer(stripped):
        name = m.group(1)
        reason = FORBIDDEN.get(name)
        if reason:
            rep.err(f"main.lua uses `{name}`: {reason}")

    # --- unknown tl.* names
    if api_names:
        seen: set[str] = set()
        for m in TL_CALL.finditer(stripped):
            full = "tl." + m.group(1)
            if full in seen:
                continue
            seen.add(full)
            if full in api_names or full in api_groups:
                continue
            # tl.foo.bar where tl.foo.bar.baz exists is fine; check prefixes too
            if any(n.startswith(full + ".") for n in api_names):
                continue
            rep.err(f"main.lua calls `{full}` — not found in api/api.json (v0.2-beta)")


def check_graph(folder: Path, rep: Report) -> None:
    path = folder / "graph.json"
    if not path.is_file():
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        rep.err(f"graph.json is not valid JSON: {e}")
        return
    if not isinstance(data, dict):
        rep.err("graph.json must be a JSON object with `nodes` and `links`")
        return

    nodes = data.get("nodes", [])
    links = data.get("links", [])
    if not isinstance(nodes, list) or not isinstance(links, list):
        rep.err("graph.json `nodes` and `links` must be arrays")
        return

    ids = set()
    for i, node in enumerate(nodes):
        if not isinstance(node, dict):
            rep.err(f"graph.json nodes[{i}] is not an object")
            continue
        if "id" not in node:
            rep.err(f"graph.json nodes[{i}] has no `id`")
        else:
            ids.add(node["id"])
        if "type" not in node:
            rep.err(f"graph.json nodes[{i}] (id={node.get('id')}) has no `type`")

    for i, link in enumerate(links):
        if not isinstance(link, dict):
            rep.err(f"graph.json links[{i}] is not an object")
            continue
        for end in ("from", "to"):
            if end not in link:
                rep.err(f"graph.json links[{i}] has no `{end}`")
            elif link[end] not in ids:
                rep.err(f"graph.json links[{i}].{end} = {link[end]} doesn't match any node id")


# --------------------------------------------------------------------------- main

def validate_folder(folder: Path, api_names: set[str], api_groups: set[str]) -> bool:
    rep = Report(str(folder))
    if not folder.is_dir():
        rep.err("not a folder")
        return rep.flush()
    check_mod_json(folder, rep)
    check_script(folder, api_names, api_groups, rep)
    check_graph(folder, rep)
    return rep.flush()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Validate Tiny Logic mod folders.")
    ap.add_argument("folders", nargs="*", type=Path, help="mod folders to check")
    ap.add_argument("--kit", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="kit root (default: parent of tools/)")
    args = ap.parse_args(argv)

    folders = list(args.folders)
    if not folders:
        for candidate in (args.kit / "template", *sorted((args.kit / "examples").glob("*"))):
            if candidate.is_dir() and (candidate / "mod.json").is_file():
                folders.append(candidate)

    if not folders:
        print("nothing to validate", file=sys.stderr)
        return 1

    api_names, api_groups = load_api(args.kit)
    if not api_names:
        print(f"warning: {args.kit / 'api' / 'api.json'} not found — skipping tl.* name checks\n",
              file=sys.stderr)

    ok = True
    for i, folder in enumerate(folders):
        if i:
            print()
        ok = validate_folder(folder, api_names, api_groups) and ok

    print()
    print("all good" if ok else "problems found — see errors above")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
