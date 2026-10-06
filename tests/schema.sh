#!/bin/sh
# The obconf configuration-file grammar (hbnf_schema.hbnf), generated in every
# backend and run over the conformance files in tests/accept and tests/reject:
# each accept file must parse and each reject file must not.  This is the
# grammar the hand-written reader HBNF_Config (retired in 9c) was checked
# against.
#
# The same four-backend harness also runs the repetition grammars at the end:
# a repeated rule that can match nothing must terminate (RFCPLAN decision 9),
# which the interpreter HBNF_Match (retired in 9c) used to be the only test of.
#
# One reject file is left out, and says why: 005-decimal-overflow.conf is `x
# 1e40`, refused because the hand-written reader's fixed-point Decimal cannot
# hold it.  A grammar has no value range, so the generated parser reads `1e40`
# as a word and accepts it; that is the Decimal type, not the notation.
#
# SCHEMA_BACKENDS says which backends are gated (default: all four).
#   HBNF=/path/to/hbnf sh tests/schema.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${SCHEMA_BACKENDS:-c ada rust zig}"
want() { case " $BACKENDS " in *" $1 "*) return 0 ;; esac; return 1; }

# A parser that never ends is a failure, not a hung test run.
guard() { if command -v timeout > /dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi; }


# verdicts BACKEND FILE: FILE holds "path: OK|REJECT" lines for every file in
# ACCEPT then REJECT, in order.
verdicts() {
	bad=0
	for f in $ACCEPT; do
		got=$(grep -F "$f: " "$2" | head -1 | sed 's/.*: //')
		[ "$got" = OK ] || { echo "$LABEL: $1 FAIL ($f: $got, wanted OK)"; bad=1; }
	done
	for f in $REJECT; do
		got=$(grep -F "$f: " "$2" | head -1 | sed 's/.*: //')
		[ "$got" = REJECT ] || { echo "$LABEL: $1 FAIL ($f: $got, wanted REJECT)"; bad=1; }
	done
	if [ $bad = 0 ]; then
		echo "$LABEL: $1 OK ($(echo $ACCEPT | wc -w) accepted, $(echo $REJECT | wc -w) rejected)"
	else
		rc=1
	fi
}

suite() { # LABEL SCHEMA-FILE, with ACCEPT and REJECT set
	LABEL=$1; S=$2
	D="$W/$(echo "$LABEL" | tr ' ' _)"
	mkdir -p "$D"
	# ---- C -------------------------------------------------------------------
	if ! want c; then :
	elif command -v gcc > /dev/null 2>&1; then
		"$CLI" "$S" --backend=c > "$D/s.c" 2> "$D/c.err" \
			|| { echo "$LABEL: C FAIL (does not generate): $(head -1 "$D/c.err")"; rc=1; }
		if [ -s "$D/s.c" ]; then
			ROOT=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$D/s.c")
			cp "$D/s.c" "$D/m.c"
			cat >> "$D/m.c" <<-EOC
	int main(int argc, char **argv) {
	    for (int i = 1; i < argc; i++) {
	        FILE *f = fopen(argv[i], "rb"); if (!f) return 2;
	        static char buf[1 << 20];
	        size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = 0; fclose(f);
	        $ROOT out; char err[512]; size_t l = 0, c = 0;
	        printf("%s: %s\n", argv[i], parse_text(buf, &out, err, sizeof err, &l, &c) ? "OK" : "REJECT");
	    }
	    return 0;
	}
	EOC
			if gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$D/m.c" -o "$D/c" 2> "$D/cc.err"; then
				guard "$D/c" $ACCEPT $REJECT > "$D/c.out"
				verdicts C "$D/c.out"
			else
				echo "$LABEL: C FAIL (compile)"; head -5 "$D/cc.err"; rc=1
			fi
		fi
	else
		echo "$LABEL: C skipped (no gcc)"
	fi

	# ---- Ada -----------------------------------------------------------------
	if ! want ada; then :
	elif command -v gnatmake > /dev/null 2>&1; then
		mkdir "$D/ada"
		"$CLI" "$S" --backend=ada --package=Schema > "$D/ada/all.ada" 2> "$D/ada.err" \
			|| { echo "$LABEL: Ada FAIL (does not generate): $(head -1 "$D/ada.err")"; rc=1; }
		if [ -s "$D/ada/all.ada" ]; then
			cp $T/schema_main.adb "$D/ada/"
			if (cd "$D/ada" && gnatchop -q -w all.ada \
				&& gnatmake -q -gnat2022 schema_main.adb -o main) > "$D/ada.err" 2>&1
			then
				guard "$D/ada/main" $ACCEPT $REJECT > "$D/ada.out" 2>&1
				verdicts Ada "$D/ada.out"
				# And the round trip: print each accepted file from the tree,
				# re-parse the print and re-print it; the two prints must agree.
				cp $T/print_main.adb "$D/ada/"
				if [ "$LABEL" != schema ]; then :
				elif (cd "$D/ada" && gnatmake -q -gnat2022 print_main.adb -o print) \
					> "$D/print.err" 2>&1
				then
					"$D/ada/print" $ACCEPT > "$D/print.out" 2>&1
					bad=0
					for f in $ACCEPT; do
						grep -qF "$f: OK" "$D/print.out" \
							|| { echo "$LABEL: Ada round trip FAIL ($(grep -F "$f: " "$D/print.out" | head -1))"; bad=1; }
					done
					if [ $bad = 0 ]; then
						echo "$LABEL: Ada round trip OK ($(echo $ACCEPT | wc -w) files print to a fixed point)"
					else
						rc=1
					fi
				else
					echo "$LABEL: Ada round trip FAIL (compile)"; head -10 "$D/print.err"; rc=1
				fi
			else
				echo "$LABEL: Ada FAIL (compile)"; head -10 "$D/ada.err"; rc=1
			fi
		fi
	else
		echo "$LABEL: Ada skipped (no gnatmake)"
	fi

	# ---- Rust ----------------------------------------------------------------
	if ! want rust; then :
	elif command -v rustc > /dev/null 2>&1; then
		mkdir "$D/rs"
		"$CLI" "$S" --backend=rust > "$D/rs/schema.rs" 2> "$D/rs.err" \
			|| { echo "$LABEL: Rust FAIL (does not generate): $(head -1 "$D/rs.err")"; rc=1; }
		if [ -s "$D/rs/schema.rs" ]; then
			cp $T/main.rs "$D/rs/"
			if (cd "$D/rs" && rustc -D warnings main.rs -o main) > "$D/rs.err" 2>&1; then
				guard "$D/rs/main" $ACCEPT $REJECT > "$D/rs.out" 2>&1
				verdicts Rust "$D/rs.out"
			else
				echo "$LABEL: Rust FAIL (compile)"; head -10 "$D/rs.err"; rc=1
			fi
		fi
	else
		echo "$LABEL: Rust skipped (no rustc)"
	fi

	# ---- Zig -----------------------------------------------------------------
	# Zig 0.16's file API is not worth wiring here, so the driver embeds the files.
	if ! want zig; then :
	elif command -v zig > /dev/null 2>&1; then
		mkdir "$D/zg"
		"$CLI" "$S" --backend=zig > "$D/zg/schema.zig" 2> "$D/zg.err" \
			|| { echo "$LABEL: Zig FAIL (does not generate): $(head -1 "$D/zg.err")"; rc=1; }
		if [ -s "$D/zg/schema.zig" ]; then
			{
				echo 'const std = @import("std");'
				echo 'const g = @import("schema.zig");'
				echo 'const cases = [_]struct { name: []const u8, text: []const u8 }{'
				for f in $ACCEPT $REJECT; do
					cp "$f" "$D/zg/$(echo "$f" | tr / _)"
					echo "    .{ .name = \"$f\", .text = @embedFile(\"$(echo "$f" | tr / _)\") },"
				done
				echo '};'
				cat <<-'EOZ'
	pub fn main() void {
	    for (cases) |cs| {
	        var err: [512]u8 = undefined;
	        var el: usize = 0;
	        var ec: usize = 0;
	        const r = g.parse_text(std.heap.page_allocator, cs.text, &err, &el, &ec);
	        std.debug.print("{s}: {s}\n", .{ cs.name, if (r) |_| "OK" else |_| "REJECT" });
	    }
	}
	EOZ
			} > "$D/zg/main.zig"
			if (cd "$D/zg" && zig build-exe main.zig -femit-bin=main) > "$D/zg.err" 2>&1; then
				guard "$D/zg/main" > "$D/zg.out" 2>&1
				verdicts Zig "$D/zg.out"
			else
				echo "$LABEL: Zig FAIL (compile)"; head -10 "$D/zg.err"; rc=1
			fi
		fi
	else
		echo "$LABEL: Zig skipped (no zig)"
	fi
}

ACCEPT=$(ls tests/accept/*.conf)
REJECT=$(ls tests/reject/*.conf | grep -v 005-decimal-overflow)
suite schema hbnf_schema.hbnf

# A repeated rule that can match nothing: `empty` matches `a` or nothing.  Each
# shape must accept the empty text, `a` and `a a`, refuse `aa` (one bareword,
# not the keyword), and above all END: it used to loop forever on `aa`.
mkdir "$W/rep"
printf '' > "$W/rep/empty.txt"
printf 'a' > "$W/rep/a.txt"
printf 'a a' > "$W/rep/a_a.txt"
printf 'aa' > "$W/rep/aa.txt"
ACCEPT="$W/rep/empty.txt $W/rep/a.txt $W/rep/a_a.txt"
REJECT="$W/rep/aa.txt"
n=0
for body in 'config = *empty' 'config = 1*empty' 'config = *( [ "a" ] )'; do
	n=$((n + 1))
	{ printf 'language C\n%s\n' "$body"; printf 'empty = [ "a" ]\n'; } > "$W/rep/g$n.hbnf"
	suite "repeat $n" "$W/rep/g$n.hbnf"
done

exit $rc
