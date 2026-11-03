#!/bin/sh
# The test262 parser tests (github.com/tc39/test262-parser-tests, pinned in bench/pins.txt, fetched into bench/cache/js262
# the first time): pass/ must be accepted, fail/ must be refused, early/ holds programs that match the grammar and break an
# early error (a rule of the static semantics), so it is only counted.  A file named *.module.js is read as a Module
# (the second root of corpus/js/js.hbnf), any other as a Script.  The tests the grammar does not match, each with its
# reason, are listed in corpus/js/test262-known.txt; the test fails when the list changes, in either direction.
#   HBNF=/path/to/hbnf sh tests/js262.sh      (JS262_DIR=dir uses an unpacked copy)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
. bench/pins.txt
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
T=${JS262_DIR:-}
if [ -z "$T" ]; then
	Z=bench/cache/js262/test262-parser-tests.tgz
	if [ ! -f "$Z" ]; then
		mkdir -p "$(dirname "$Z")"
		curl -sL -o "$Z" "$JS262_URL" 2> /dev/null && echo "$JS262_SHA  $Z" | sha256sum -c - > /dev/null 2>&1 \
			|| { rm -f "$Z"; echo "js262: SKIP (no copy of the tests at $Z, and they could not be fetched)"; exit 0; }
	fi
	python3 -c "import sys, tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2])" "$Z" "$W/t" 2> /dev/null \
		|| { echo "js262: SKIP (cannot unpack $Z)"; exit 0; }
	T=$(ls -d "$W"/t/test262-parser-tests-*)
fi
# a driver for each goal: FILE, then OK or REJECT
for goal in script module; do
	root=; [ $goal = module ] && root=--root=module
	"$CLI" corpus/js/js.hbnf $root --backend=c > "$W/$goal.c" 2> "$W/$goal.err" \
		|| { echo "js262: FAIL ($goal does not generate: $(head -c 300 "$W/$goal.err"))"; exit 1; }
	rt=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$goal.c")
	cat >> "$W/$goal.c" <<EOC
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb"); if (!f) return 2;
        fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
        char *buf = malloc(n + 1);
        if (fread(buf, 1, n, f) != (size_t)n) return 2;
        buf[n] = 0; fclose(f);
        $rt out; char err[512]; size_t l = 0, c = 0;
        printf("%s: %s\n", argv[i], parse_text(buf, &out, err, sizeof err, &l, &c) ? "OK" : "REJECT");
        free(buf);
    }
    return 0;
}
EOC
	${CC:-cc} -std=gnu11 -D_GNU_SOURCE -O1 -w -Itests/bsdinc -Iruntime "$W/$goal.c" -o "$W/$goal" 2> "$W/cc.err" \
		|| { echo "js262: FAIL ($goal does not compile)"; head -5 "$W/cc.err"; exit 1; }
done
# one process for each file, and ten seconds for it: a few tests are exponential for a parser that tries a reading and then another
run() { # DIR -> lines "DIR/NAME VERDICT"
	for f in "$T/$1"/*.js; do
		n=$(basename "$f")
		case $n in *.module.js) d="$W/module" ;; *) d="$W/script" ;; esac
		r=$(timeout 10 "$d" "$f" 2> /dev/null) && r=${r##*: } || r=TIMEOUT
		echo "$1/$n $r"
	done
}
run pass > "$W/pass.out"; run fail > "$W/fail.out"; run early > "$W/early.out"
npass=$(grep -c . "$W/pass.out"); nfail=$(grep -c . "$W/fail.out"); nearly=$(grep -c . "$W/early.out")
{ grep -v ' OK$' "$W/pass.out" | sed 's/ .*//; s/^/pass /'; grep -v ' REJECT$' "$W/fail.out" | sed 's/ .*//; s/^/fail /'; } | sort > "$W/miss"
awk '{ print $1, $2 }' corpus/js/test262-known.txt | sort > "$W/known"
rc=0
if ! cmp -s "$W/miss" "$W/known"; then
	echo "js262: the tests that are not matched differ from corpus/js/test262-known.txt:"
	diff "$W/known" "$W/miss" | head -20
	rc=1
fi
echo "js262: pass $((npass - $(grep -c '^pass' "$W/miss"))) of $npass accepted; fail $((nfail - $(grep -c '^fail' "$W/miss"))) of $nfail refused;" \
	"early $(grep -c ' REJECT$' "$W/early.out") of $nearly refused ($(grep -c ' OK$' "$W/early.out") accepted: early errors, not checked)"
echo "js262: $(grep -c '^pass' "$W/miss") valid programs and $(grep -c '^fail' "$W/miss") invalid ones are not matched, each with its reason in corpus/js/test262-known.txt"
[ $rc = 0 ] && echo "js262: OK" || { echo "js262: FAIL"; exit 1; }
