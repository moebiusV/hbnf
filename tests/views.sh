#!/bin/sh
# --views: a string in the tree is a slice of the input (hbnf_sp, hbnf_sn), copied only when an
# escape has to be undone or it is 65535 bytes or more.
#   HBNF=/path/to/hbnf sh tests/views.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
"$CLI" tests/views/pair.hbnf --backend=c --views > "$W/parser.c" 2> "$W/err" \
    || { echo "views: FAIL (generate: $(head -c 200 "$W/err"))"; exit 1; }
cc -std=gnu11 -D_GNU_SOURCE -w -I"$W" tests/views/main.c -o "$W/t" 2> "$W/cc" \
    || { echo "views: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
"$W/t"
