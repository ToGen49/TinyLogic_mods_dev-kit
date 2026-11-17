#!/usr/bin/env bash
# Refresh api/api.json from a game installation.
#
#   sync-api.sh --install <path-to-game-install>
#   sync-api.sh --auto
#   sync-api.sh --from <file>
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$KIT/api/api.json"
SRC=""

usage() {
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --install) SRC="${2:?--install needs a value}"; shift 2 ;;
        --from)    SRC="${2:?--from needs a value}"; shift 2 ;;
        --auto)    SRC="auto"; shift ;;
        *)         echo "unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -n "$SRC" ]] || { echo "missing --install <path> | --auto | --from <file>" >&2; usage 1; }

if [[ "$SRC" == "auto" ]]; then
    # Search the usual places for assets/mods/api.json. No absolute paths baked in:
    # everything is derived from $HOME / $XDG_DATA_HOME.
    CANDIDATES=()
    base="${XDG_DATA_HOME:-$HOME/.local/share}/Mazell/TinyLogic"
    [[ -d "$base" ]] && CANDIDATES+=("$base"/beta/*/assets/mods/api.json "$base"/*/assets/mods/api.json)
    CANDIDATES+=("$HOME"/Games/*/assets/mods/api.json "$HOME"/*/assets/mods/api.json)

    FOUND=""
    for c in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
        [[ -f "$c" ]] && FOUND="$c" && break
    done
    [[ -n "$FOUND" ]] || {
        echo "could not find api.json automatically." >&2
        echo "use: sync-api.sh --install <game-install-folder>" >&2
        exit 1
    }
    SRC="$FOUND"
elif [[ -d "$SRC" ]]; then
    # accept either the install root or the assets/mods folder itself
    if [[ -f "$SRC/api.json" ]]; then
        SRC="$SRC/api.json"
    elif [[ -f "$SRC/assets/mods/api.json" ]]; then
        SRC="$SRC/assets/mods/api.json"
    else
        echo "no api.json under: $SRC" >&2
        exit 1
    fi
fi

[[ -f "$SRC" ]] || { echo "not a file: $SRC" >&2; exit 1; }

python3 - "$SRC" "$DEST" <<'PY'
import json, os, shutil, sys
src, dest = sys.argv[1], sys.argv[2]
old = None
try:
    old = json.load(open(dest, encoding="utf-8"))
except Exception:
    pass
new = json.load(open(src, encoding="utf-8"))

same = os.path.exists(dest) and os.path.samefile(src, dest)
if not same:
    shutil.copyfile(src, dest)

def count(d):
    return sum(len(g.get("items", [])) for g in d.get("groups", []))

print(f"source : {src}")
print(f"target : {dest}" + ("   (identical — nothing copied)" if same else ""))
print(f"version: {new.get('version')}   groups: {len(new.get('groups', []))}   items: {count(new)}")
if old:
    ov, nv = old.get("version"), new.get("version")
    if ov != nv:
        print(f"NOTE: version changed {ov} -> {nv} — re-read docs/04-api.md")
    diff = count(new) - count(old)
    if diff:
        print(f"NOTE: {diff:+d} API entries vs the previous copy")
PY

echo
echo "re-run the checks:"
echo "  $KIT/tools/validate.py"
