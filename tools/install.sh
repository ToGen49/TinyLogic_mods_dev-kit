#!/usr/bin/env bash
# Install a mod folder into the game's profile, or package it for sharing.
#
#   install.sh <mod-folder> [--profile <path>] [--link] [--dry-run]
#   install.sh --zip <mod-folder>        # build a shareable archive instead
#   install.sh --where                   # print the profile path this script found
#
# The profile is auto-detected on Linux (XDG data dir). Override with
# --profile or the TINYLOGIC_PROFILE environment variable.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINK=0
DRY=0
ZIP=0
WHERE=0
PROFILE="${TINYLOGIC_PROFILE:-}"
SRC=""

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --link)    LINK=1; shift ;;
        --dry-run) DRY=1; shift ;;
        --zip)     ZIP=1; shift ;;
        --where)   WHERE=1; shift ;;
        --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        -*)        echo "unknown option: $1" >&2; usage 1 ;;
        *)         SRC="$1"; shift ;;
    esac
done

# ---------------------------------------------------------------- detect profile
detect_profile() {
    if [[ -n "$PROFILE" ]]; then
        printf '%s\n' "$PROFILE"
        return 0
    fi
    local base="${XDG_DATA_HOME:-$HOME/.local/share}/Mazell/TinyLogic"
    if [[ -d "$base/beta-profile" ]]; then
        printf '%s\n' "$base/beta-profile"
        return 0
    fi
    if [[ -d "$base" ]]; then
        # stable profile: the folder that actually holds a mods/ or projects/ dir
        local d
        for d in "$base"/*/; do
            if [[ -d "$d/mods" || -d "$d/projects" ]]; then
                printf '%s\n' "${d%/}"
                return 0
            fi
        done
        printf '%s\n' "$base"
        return 0
    fi
    return 1
}

if [[ $WHERE -eq 1 ]]; then
    if p="$(detect_profile)"; then
        echo "$p"
    else
        echo "profile not found — pass --profile <path> or set TINYLOGIC_PROFILE" >&2
        exit 1
    fi
    exit 0
fi

[[ -n "$SRC" ]] || { echo "missing <mod-folder>" >&2; usage 1; }
[[ -d "$SRC" ]] || { echo "not a folder: $SRC" >&2; exit 1; }
SRC="$(cd "$SRC" && pwd)"

[[ -f "$SRC/mod.json" ]] || { echo "no mod.json in $SRC — is that a mod folder?" >&2; exit 1; }

MOD_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$SRC/mod.json")" \
    || { echo "could not read id from mod.json" >&2; exit 1; }

if [[ "$MOD_ID" != "$(basename "$SRC")" ]]; then
    echo "warning: mod.json id '$MOD_ID' != folder name '$(basename "$SRC")'" >&2
    echo "         the game keys mods on the folder name — rename one of them" >&2
fi

# ---------------------------------------------------------------- package
if [[ $ZIP -eq 1 ]]; then
    OUT="$KIT/dist/$MOD_ID.zip"
    mkdir -p "$KIT/dist"
    # Python's zipfile, so the kit has no external dependency beyond bash + python3.
    python3 - "$SRC" "$OUT" "$MOD_ID" <<'PY'
import os, sys, zipfile
src, out, mod_id = sys.argv[1], sys.argv[2], sys.argv[3]
skip = {"store.json", ".git", "__pycache__"}
count = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in skip and not d.startswith(".")]
        for f in files:
            if f in skip or f.endswith(".bak") or f.startswith("."):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, os.path.dirname(src))
            z.write(full, rel)
            count += 1
print(f"packaged {out}  ({count} files)")
PY
    echo "hand this to another player: they use 'bring in...' in their mods panel"
    exit 0
fi

# ---------------------------------------------------------------- install
PROFILE="$(detect_profile)" || {
    echo "could not find the game profile." >&2
    echo "pass --profile <path>, or set TINYLOGIC_PROFILE." >&2
    echo "hint: the game's own README.txt names the location for your platform." >&2
    exit 1
}

DEST="$PROFILE/mods/$MOD_ID"

echo "source : $SRC"
echo "target : $DEST"

if [[ $DRY -eq 1 ]]; then
    echo "(dry run — nothing written)"
    exit 0
fi

mkdir -p "$PROFILE/mods"

if [[ $LINK -eq 1 ]]; then
    if [[ -e "$DEST" || -L "$DEST" ]]; then
        rm -rf "$DEST"
    fi
    ln -s "$SRC" "$DEST"
    echo "symlinked — edits to the source take effect on the next save + run"
else
    if [[ -e "$DEST" ]]; then
        rm -rf "$DEST"
    fi
    mkdir -p "$DEST"
    # copy the mod, never its runtime state or editor droppings
    for f in "$SRC"/*; do
        case "$(basename "$f")" in
            store.json|.git|*.bak) continue ;;
        esac
        cp -R "$f" "$DEST/"
    done
    echo "copied — re-run this script after each change"
fi

echo
echo "next: in the game, menu > mods > save + run"
