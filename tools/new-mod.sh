#!/usr/bin/env bash
# Scaffold a new Tiny Logic mod from the kit's template.
#
#   new-mod.sh <mod-id> [--name "Human Name"] [--author "you"] [--dir <parent>]
#
# Creates <dir>/<mod-id>/ with mod.json, main.lua, graph.json.
# Default <dir> is <kit>/mods.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT/template"

ID=""
NAME=""
AUTHOR="you"
OUTDIR="$KIT/mods"

usage() {
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --name)   NAME="${2:?--name needs a value}"; shift 2 ;;
        --author) AUTHOR="${2:?--author needs a value}"; shift 2 ;;
        --dir)    OUTDIR="${2:?--dir needs a value}"; shift 2 ;;
        -*)       echo "unknown option: $1" >&2; usage 1 ;;
        *)
            [[ -n "$ID" ]] && { echo "only one mod id, got: $ID and $1" >&2; exit 1; }
            ID="$1"; shift ;;
    esac
done

[[ -n "$ID" ]] || { echo "missing <mod-id>" >&2; usage 1; }

if ! [[ "$ID" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "invalid mod id: '$ID'" >&2
    echo "use lowercase letters, digits, '-' or '_', starting with a letter or digit" >&2
    exit 1
fi

[[ -f "$TEMPLATE/mod.json" ]] || { echo "template not found: $TEMPLATE" >&2; exit 1; }

[[ -n "$NAME" ]] || NAME="$(echo "$ID" | sed -E 's/[-_]+/ /g; s/\b(.)/\u\1/g')"

DEST="$OUTDIR/$ID"
if [[ -e "$DEST" ]]; then
    echo "already exists: $DEST" >&2
    exit 1
fi

mkdir -p "$DEST"
cp "$TEMPLATE/main.lua" "$TEMPLATE/graph.json" "$DEST/"

python3 - "$TEMPLATE/mod.json" "$DEST/mod.json" "$ID" "$NAME" "$AUTHOR" <<'PY'
import json, sys
src, dst, mod_id, name, author = sys.argv[1:6]
data = json.load(open(src, encoding="utf-8"))
data.update(id=mod_id, name=name, author=author)
json.dump(data, open(dst, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
open(dst, "a", encoding="utf-8").write("\n")
PY

# Leave a marker so the template's placeholder id never ships by accident.
sed -i "s/^-- my-mod —/-- $ID —/" "$DEST/main.lua" 2>/dev/null || true

echo "created $DEST"
echo
echo "next:"
echo "  $KIT/tools/validate.py $DEST"
echo "  $KIT/tools/install.sh $DEST"
echo "  then in the game: menu > mods > save + run"
