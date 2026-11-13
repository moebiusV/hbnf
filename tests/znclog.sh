#!/bin/sh
# ZNC's log lines (soju's znclog) as a grammar (corpus/znclog/znclog.hbnf, C backend): a transducer that turns each line into
# `KIND<TAB>field<TAB>field...` as soju's Go reader (msgstore/znclog/reader.go) splits it, at the first delimiter, the text after it free
# (it may hold `> `, `- `, parentheses and quotes).  The same splitting in Python (corpus/znclog/oracle.py) is the oracle: 30000 lines of
# fuzz built from the delimiters themselves, and a few written out, must give the same fields.  (The oracle is a port of the Go code's
# splits, not the Go code: there is no Go toolchain here.)
#   HBNF=/path/to/hbnf sh tests/znclog.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
command -v python3 > /dev/null 2>&1 || { echo "znclog: skipped (no python3)"; exit 0; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/znclog/znclog.hbnf --backend=c > "$W/p.c" 2> "$W/err" || { echo "znclog: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat > "$W/main.c" <<'EOM'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1); if (fread(buf, 1, n, f) != (size_t)n) return 2; buf[n] = 0; fclose(f);
    OUT_T tree; char err[2048]; size_t l, c;
    memset(&tree, 0, sizeof tree);
    if (parse_text(buf, &tree, err, sizeof err, &l, &c)) { fputs(hbnf_rr_buf ? hbnf_rr_buf : buf, stdout); return 0; }
    fprintf(stderr, "ERROR %zu:%zu %s\n", l, c, err); return 1;
}
EOM
cat "$W/p.c" "$W/main.c" > "$W/m.c"
cc -O2 -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/znclog" 2> "$W/cc.txt" || { echo "znclog: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
fail=0; n=0
# lines written out: a message, a notice, an action and the events, each with delimiters in the text
cat > "$W/fixed.log" <<'EOF'
[12:00:01] <bob> (<a> b> c)
[12:00:02] <a>b> x> y
[12:00:03] -ChanServ- notice - with - dashes
[12:00:04] * bob waves <ok> at you
[12:00:05] *** Joins: carol (u@h)
[12:00:06] *** Parts: dan (u@h.x) (bye now)
[12:00:07] *** Quits: eve (u@h) (Quit: gone (really))
[12:00:08] *** al is now known as bo
[12:00:09] *** x was kicked by y (why (not))
[12:00:10] *** x changes topic to 'it's'
[12:00:11] *** x sets mode: +o y
[12:00:12] junk after the prefix is skipped
[12:00:13] *** Joins: is now known as z
[12:00:14] <> empty sender
[12:00:15] <dave> 
EOF
# fuzz: the delimiters and the words the format knows, put together at random (seeded, so a failure repeats)
python3 - "$W/fuzz.log" <<'EOP'
import random, sys
random.seed(20261113)
frag = ['<','>','> ','>>','- ','-',' ','  ','(',')','()',"'","''",'@','@@','*','* ','*** ','a','bob','x y','é','\\','\t','\r','Joins:','Parts:','Quits:','is now known as ','was kicked by ','changes topic to ','sets mode: ','u@h','(u@h)','+o','.',':','[12:00:00]','z']
def junk(n): return ''.join(random.choice(frag) for _ in range(random.randint(0, n)))
def stamp(): return '[%02d:%02d:%02d] ' % (random.randint(0, 23), random.randint(0, 59), random.randint(0, 59))
out = []
for i in range(30000):
    k = random.random()
    if k < 0.18: l = '<' + junk(4) + '> ' + junk(8)
    elif k < 0.30: l = '-' + junk(4) + '- ' + junk(8)
    elif k < 0.40: l = '* ' + junk(3) + ' ' + junk(8)
    elif k < 0.55: l = '*** ' + random.choice(['Joins:', 'Parts:', 'Quits:']) + ' ' + junk(3) + ' ' + random.choice(['', '(', '']) + junk(3) + random.choice(['@', '', '@@']) + junk(3) + random.choice([')', '', ') ', ') (']) + junk(6)
    elif k < 0.70: l = '*** ' + junk(2) + ' ' + random.choice(['is now known as ', 'was kicked by ', 'changes topic to ', 'sets mode: ', 'is now known as']) + junk(7)
    elif k < 0.80: l = '*** ' + junk(6)
    else: l = junk(10)
    out.append(stamp() + l.replace('\n', ' '))
open(sys.argv[1], 'w', encoding='utf-8', newline='').write('\n'.join(out) + '\n')
EOP
for f in fixed fuzz; do
	n=$((n + 1))
	"$W/znclog" "$W/$f.log" > "$W/$f.got" 2> "$W/$f.err" || { echo "znclog: FAIL ($f.log is refused: $(head -c 300 "$W/$f.err"))"; fail=1; continue; }
	python3 corpus/znclog/oracle.py "$W/$f.log" > "$W/$f.want"
	cmp -s "$W/$f.want" "$W/$f.got" || { echo "znclog: FAIL ($f.log: the fields are not the Go code's)"; diff "$W/$f.want" "$W/$f.got" | head -6; fail=1; }
done
# a line without the time prefix is an error, as in soju (it fails the read of the day)
printf '[12:00:01] <a> b\nno prefix\n' > "$W/bad.log"
n=$((n + 1)); "$W/znclog" "$W/bad.log" > /dev/null 2>&1 && { echo "znclog: FAIL (a line without the prefix is not refused)"; fail=1; }
# the Ada backend generates the same grammar (its facts-free rewrites, with the escapes of the templates translated), and reads the same lines
# (it cannot show the text the rewrites made, only that the lines are read or refused)
if command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/ad"
	if "$CLI" corpus/znclog/znclog.hbnf --backend=ada --package=Zl > "$W/ad/all.ada" 2> "$W/err"; then
		aroot=$(grep -o "return [A-Za-z0-9_]*_Type" "$W/ad/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
		sed "s/MODULE/Zl/g; s/ROOT/$aroot/g" corpus/posix/check.adb > "$W/ad/check.adb"
		if (cd "$W/ad" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
			n=$((n + 2))
			got=$("$W/ad/m" "$W/fixed.log" 2>&1 | cut -d' ' -f1 | head -1); [ "$got" = ok ] || { echo "znclog: FAIL (Ada refuses the written lines: $got)"; fail=1; }
			got=$("$W/ad/m" "$W/bad.log" 2>&1 | cut -d' ' -f1 | head -1); [ "$got" = bad ] || { echo "znclog: FAIL (Ada reads a line without the prefix: $got)"; fail=1; }
		else echo "znclog: FAIL (the Ada parser does not compile: $(grep -m2 error "$W/ad/cc.txt" | head -c 300))"; fail=1; fi
	else echo "znclog: FAIL (Ada does not generate: $(head -c 300 "$W/err"))"; fail=1; fi
fi
[ $fail -eq 0 ] && echo "znclog: OK ($n checks: 15 written lines and 30000 fuzzed ones give the Go code's fields; a line without the prefix is refused)" || exit 1
