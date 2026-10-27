#!/bin/sh
# The grammar of C that PCC's compiler reads (corpus/c/pcc.hbnf), C backend.  In corpus/c/tests-pcc:
#   good/      accepted by the parser, and by gcc (-std=gnu11 -fsyntax-only, implicit int allowed);
#   bad/       refused by the parser, and by gcc: a syntax error;
#   pcc-only/  accepted by the parser, refused by gcc: PCC's grammar has it and gcc's does not (a type
#              as the argument of a call);
#   not-pcc/   refused by the parser, accepted by gcc: GNU C that PCC's cgram.y has no production for
#              (`__extension__`, `__label__`, a nested function, `__real__`, a label before `}`...).
#   HBNF=/path/to/hbnf sh tests/pcc.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/c

"$CLI" $D/pcc.hbnf --backend=c > "$W/pcc.c" 2> "$W/err" || { echo "pcc: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/pcc.c")
cat "$W/pcc.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "pcc: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad pcc-only not-pcc; do
	for f in $D/tests-pcc/$kind/*.c; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		case $kind in good|pcc-only) want=ok ;; *) want=bad ;; esac
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v gcc > /dev/null 2>&1; then
			gcc -fsyntax-only -std=gnu11 -fpermissive -Wno-implicit-int "$f" > /dev/null 2>&1; r=$?
			case $kind in
			good|not-pcc) [ $r -ne 0 ] && echo "NOTE $f: gcc refuses it (rc $r)" ;;
			bad|pcc-only) [ $r -eq 0 ] && echo "NOTE $f: gcc accepts it" ;;
			esac
		fi
	done
done
if [ $fail -eq 0 ]; then echo "pcc: OK ($n files)"; else echo "pcc: FAIL ($fail of $n)"; exit 1; fi
