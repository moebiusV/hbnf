#!/bin/sh
# The C grammars on a real program: the SQLite amalgamation (sqlite3.c, 2.3 MB preprocessed), pinned in
# bench/pins.txt and fetched into bench/cache/cspeed the first time.  What SQLite promises is "ANSI-C"
# (its requirement S50100); the code is C89 with `long long`, and clean under C99 -pedantic.  So:
#   corpus/c/c11.hbnf, corpus/c/gnu99.hbnf, corpus/c/pcc99.hbnf    accept it
#   corpus/c/c99.hbnf, strict, as gcc -std=c99 -pedantic-errors does   accept it
#   corpus/c/c89.hbnf, strict, as gcc -std=c89 -pedantic-errors does   refuse it (long long)
#   corpus/c/c79.hbnf                                                  refuse it (no prototypes, void, const)
# The strict grammars read the file with gcc's own headers made plain: <stdarg.h> is replaced
# (tests/sqlite/va.h), the GNU spellings are neutralised as scripts/c-scan.sh does, and gcc's
# __builtin_offsetof is written the classic way, since SQLite wrote offsetof.
#   HBNF=/path/to/hbnf sh tests/sqlite.sh        (SQLITE_ZIP=file uses a copy of the amalgamation)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
. bench/pins.txt
Z=${SQLITE_ZIP:-bench/cache/cspeed/sqlite.zip}
if [ ! -f "$Z" ]; then
	mkdir -p "$(dirname "$Z")"
	curl -sL -o "$Z" "$CSPEED_SQLITE_URL" 2> /dev/null && echo "$CSPEED_SQLITE_SHA  $Z" | sha256sum -c - > /dev/null 2>&1 \
		|| { rm -f "$Z"; echo "sqlite: SKIP (no copy of the amalgamation at $Z, and it could not be fetched)"; exit 0; }
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$Z" "$W" 2> /dev/null \
	|| { echo "sqlite: SKIP (cannot unpack $Z)"; exit 0; }
SQ=$(ls -d "$W"/sqlite-amalgamation-*)
VA=$(pwd)/tests/sqlite/va.h
G99="-D__extension__= -D__restrict=restrict -D__restrict__=restrict -D__inline=inline -D__inline__=inline -D__const=const -D__signed__=signed -D__volatile__=volatile -D__builtin_va_list=void* -include $VA"
G89="-D__extension__= -D__restrict= -D__restrict__= -D__inline= -D__inline__= -D__const=const -D__signed__=signed -D__volatile__=volatile -D__builtin_va_list=void* -include $VA"
fail=0; good=""; bad=""
# grammar std mode expected
for spec in "c11 gnu11 - accept" "gnu99 gnu99 - accept" "pcc99 gnu11 - accept" "c99 c99 strict accept" "c89 c89 strict refuse" "c79 gnu11 - refuse"; do
	set -- $spec; g=$1; std=$2; mode=$3; want=$4
	PED=; GNU=
	if [ "$mode" = strict ]; then PED=-pedantic-errors; GNU=$G99; [ "$std" = c89 ] && GNU=$G89; fi
	"$CLI" corpus/c/$g.hbnf --backend=c > "$W/$g.c" 2> "$W/$g.err" \
		|| { echo "sqlite: FAIL ($g does not generate: $(head -c 200 "$W/$g.err"))"; fail=1; continue; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$g.c")
	cat "$W/$g.c" corpus/c/check.c > "$W/m$g.c"
	${CC:-cc} -O1 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m$g.c" -o "$W/check$g" 2> "$W/cc.err" \
		|| { echo "sqlite: FAIL ($g parser does not compile: $(head -c 200 "$W/cc.err"))"; fail=1; continue; }
	gcc -E -P -std=$std $GNU "-D__attribute__(x)=" "-D__asm__(x)=" "-D__asm(x)=" -w -I"$SQ" "$SQ/sqlite3.c" > "$W/$g.i" 2> /dev/null \
		|| { echo "sqlite: FAIL (gcc cannot preprocess sqlite3.c for $g)"; fail=1; continue; }
	if [ "$mode" = strict ]; then
		python3 - "$W/$g.i" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'__builtin_offsetof\s*\(\s*([^,()]+?)\s*,\s*([^()]+?)\s*\)', r'((size_t)&((\1 *)0)->\2)', t)
open(sys.argv[1], 'w').write(t)
PY
		# gcc's own verdict on the same text, for the standard the grammar is
		if gcc -fsyntax-only -std=$std $PED "$W/$g.i" 2> "$W/gcc.err"; then gcc_says=accept; else gcc_says=refuse; fi
		[ "$gcc_says" = "$want" ] \
			|| { echo "sqlite: FAIL (gcc -std=$std $PED would $gcc_says sqlite3.c; the test expects $want)"; fail=1; continue; }
	fi
	r=$("$W/check$g" "$W/$g.i" | head -1)
	case "$r" in ok*) got=accept ;; *) got=refuse ;; esac
	if [ "$got" != "$want" ]; then
		echo "sqlite: FAIL ($g should $want sqlite3.c and does $got: $(echo "$r" | sed 's|^[a-z]* [^:]*: ||' | cut -c1-160))"; fail=1
	elif [ "$want" = accept ]; then good="$good $g"
	else bad="$bad $g"
	fi
done
[ $fail = 0 ] && echo "sqlite: OK (sqlite3.c accepted by${good}; refused by${bad}, as it should be)"
exit $fail
