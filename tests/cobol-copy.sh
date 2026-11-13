#!/bin/sh
# COBOL's COPY and REPLACE as rewrites (corpus/cobol/cobol-copy.hbnf, C backend): the text of the library takes the place of the COPY
# statement, REPLACING and REPLACE substitute text words, and the grammar reads the new text.  Each program below is read
# only if the substitution was made: the text of the library has words the grammar does not know until they are replaced.
#   HBNF=/path/to/hbnf sh tests/cobol-copy.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/cobol/cobol-copy.hbnf --root=compilation-group --backend=c > "$W/p.c" 2> "$W/err" || { echo "cobol-copy: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.txt" || { echo "cobol-copy: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
mkdir -p "$W/lib" "$W/w"
cd "$W/w"
fail=0; n=0
# libraries
printf '       01  :P:-REC.\n           05  :P:-F  PIC 9.\n' > "$W/lib/PREC.cpy"
printf '       01  OLD-R.\n           05  F  PIC 9 BAD-CLAUSE.\n' > "$W/lib/OLDR.cpy"
printf '       01  R.\n           05  F  PIC 9 XCOMP.\n' > "$W/lib/LEAD.cpy"
printf '       01  R.\n           05  F  PIC 9.\n       COPY INNER.\n' > "$W/lib/OUTER.cpy"
printf '       01  S.\n           05  G  PIC X.\n' > "$W/lib/INNER.cpy"
printf '           MOVE 1 TO A\n' > "$W/lib/STMT.cpy"
printf '       01  Q.\n           05  H  PIC X VALUE "x" BAD-CLAUSE.\n' > "$W/lib/LIT.cpy"
# prog DATA-LINES PROC-LINES
prog() { printf '       IDENTIFICATION DIVISION.\n       PROGRAM-ID. cp.\n       DATA DIVISION.\n       WORKING-STORAGE SECTION.\n%s\n       PROCEDURE DIVISION.\n%s\n           GOBACK.\n' "$1" "$2"; }
chk() {   # WANT TEXT: the program is read (ok) or refused (bad)
	printf '%s' "$2" > t.cob; got=$(COBCPY="$W/lib" "$W/check" t.cob 2>&1 | cut -d' ' -f1 | head -1); n=$((n + 1))
	[ "$got" = "$1" ] || { echo "cobol-copy: FAIL ($3: should be $1 and is $got)"; fail=1; }
}
chk ok  "$(prog '       COPY PREC REPLACING ==:P:== BY ==X==.' '')" "pseudo-text pair"
chk bad "$(prog '       COPY PREC.' '')" "the same library without REPLACING"
chk ok  "$(prog '       COPY OLDR REPLACING BAD-CLAUSE BY COMP.' '')" "a word for a word"
chk ok  "$(prog '       COPY OLDR REPLACING ==BAD-CLAUSE== BY ==COMP== ==OLD-R== BY ==NEW-R==.' '')" "two pairs"
chk bad "$(prog '       COPY OLDR REPLACING BAD-CLAUSE BY NOPE-NOT.' '')" "a replacement that is still no clause"
chk ok  "$(prog '       COPY LEAD REPLACING LEADING ==X== BY ====.' '')" "LEADING and an empty pseudo-text"
chk ok  "$(prog '       COPY OUTER.' '')" "a COPY inside a library"
chk ok  "$(prog '' '           COPY STMT.')" "a COPY in the procedure division"
chk ok  "$(prog '       COPY "OUTER.cpy".' '')" "a library named by a literal"
chk ok  "$(prog '       COPY PREC OF SOMELIB REPLACING ==:P:== BY ==Y==.' '')" "OF library and REPLACING"
chk ok  "$(prog '       COPY LIT REPLACING ==BAD-CLAUSE== BY ==COMP==.' '')" "a word after a literal"
# a literal is one text word: what is inside it is not replaced
chk ok  "$(prog '       01  Z PIC X VALUE "OLD-R".' '           REPLACE ==OLD-R== BY ==QQ==.
           MOVE 1 TO A')" "REPLACE leaves a literal alone"
# REPLACE
chk ok  "$(prog '' '           REPLACE ==XX== BY ==MOVE 1 TO A==.
           IF 1 = 1 XX END-IF')" "REPLACE"
chk bad "$(prog '' '           IF 1 = 1 XX END-IF')" "the same text without REPLACE"
chk bad "$(prog '' '           REPLACE ==XX== BY ==MOVE 1 TO A==.
           IF 1 = 1 XX END-IF
           REPLACE OFF.
           IF 1 = 1 XX END-IF')" "REPLACE OFF ends it"
chk ok  "$(prog '' '           REPLACE ==XX== BY ==MOVE 1 TO A==.
           IF 1 = 1 XX END-IF
           REPLACE ==YY== BY ==MOVE 2 TO A==.
           IF 1 = 1 YY END-IF')" "a second REPLACE takes over"
chk bad "$(prog '' '           REPLACE ==XX== BY ==MOVE 1 TO A==.
           IF 1 = 1 XX END-IF
           REPLACE ==YY== BY ==MOVE 2 TO A==.
           IF 1 = 1 XX END-IF')" "a second REPLACE cancels the first"
if [ $fail -eq 0 ]; then echo "cobol-copy: OK ($n programs: COPY, REPLACING, LEADING, nesting, a library path and REPLACE)"; else exit 1; fi
