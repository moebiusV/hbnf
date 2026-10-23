#!/bin/sh
# Compare the POSIX shell grammar with dash on every shell script this machine has, and on
# mutations of them (a character, a line or a stray token removed or added).  dash -n is the
# reference.  Disagreements are listed; the three the grammar owes (dash reads a function body that is not a
# compound command; a line that begins inside a multi-line quotation does not see its here-document;
# bytes that are not UTF-8) are known.
#   HBNF=/path/to/hbnf sh scripts/posix-scan.sh [N-mutations-per-script]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
M=${1:-3}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
D=corpus/posix
"$CLI" $D/shell.y --backend=c > "$W/shell.c" 2> /dev/null || { echo "generate failed"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/shell.c")
cat "$W/shell.c" $D/check.c > "$W/m.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w -DOUT_T="$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || exit 1

find /usr /etc /lib /opt /sbin /bin -xdev -type f -size -200k 2> /dev/null | while read -r f; do
	case "$(head -c 40 "$f" 2> /dev/null | head -1 | tr -d '\0')" in
	'#!/bin/sh'*|'#!/usr/bin/sh'*|'#!/bin/dash'*|'#!/usr/bin/dash'*|'#!/usr/bin/env sh'*) echo "$f" ;;
	esac
done > "$W/scripts.txt"
mkdir -p "$W/mut"
python3 - "$W" "$M" << 'PY'
import random, sys
w, m = sys.argv[1], int(sys.argv[2])
random.seed(7)
ins = ['fi','done',';;','esac',')','}','(','{','"',"'",'`','|','&&','<<','do','then','in',';',"\n"]
n = 0
for f in (l.strip() for l in open(w + '/scripts.txt')):
    try: data = open(f, 'rb').read().decode('utf-8')
    except Exception: continue
    if len(data) > 20000: continue
    open(f'{w}/mut/o{n}.sh', 'w').write(data); n += 1
    for k in range(m):
        d = list(data)
        kind = random.choice(['delchar', 'delline', 'insert', 'dupline'])
        if kind == 'delchar': del d[random.randrange(len(d))]; s = ''.join(d)
        elif kind == 'delline':
            lines = data.split('\n'); del lines[random.randrange(len(lines))]; s = '\n'.join(lines)
        elif kind == 'dupline':
            lines = data.split('\n'); i = random.randrange(len(lines)); lines.insert(i, lines[i]); s = '\n'.join(lines)
        else:
            i = random.randrange(len(d)); s = ''.join(d[:i]) + random.choice(ins) + ''.join(d[i:])
        open(f'{w}/mut/m{n}.sh', 'w').write(s); n += 1
print(n, "files")
PY
for f in "$W"/mut/*.sh; do dash -n "$f" > /dev/null 2>&1; echo "$? $f"; done > "$W/dash.txt"
"$W/check" "$W"/mut/*.sh > "$W/ours.txt" 2>&1
awk 'NR == FNR { d[$2] = $1; next }
     { f = $2; sub(/:$/, "", f); v = ($1 == "ok") ? 0 : 2;
       if ((d[f] == 0) != (v == 0)) print ((v == 0) ? "grammar accepts, dash refuses: " : "grammar refuses, dash accepts: ") $0 }' "$W/dash.txt" "$W/ours.txt" | cut -c1-200
awk '{c[$1]++} END { printf "dash: %d accepted, %d refused\n", c[0], c[2] }' "$W/dash.txt"
