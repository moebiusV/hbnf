#!/bin/sh
# The recursive tree type (RFCPLAN step 9b): one grammar whose value contains
# itself, generated, compiled and RUN in every backend that emits it.
# tests/abnf/recursive.hbnf is `prim = '(' expr ')' | int` with `expr = prim`.
#
# Each backend gets a small driver that parses one expression from the command
# line and says whether it was accepted, so the gate is the pair
#   (1)  accepted      -- the pointer holds a real subtree
#   1)   rejected      -- and the parser still requires the whole input
# Modelled on tests/portable.sh, which does the same for all four backends on
# a schema that is not recursive.
#
# C is gated in tests/abnf.sh's recursive block (gen_file/check).  This script
# covers the backends whose driver lives here: Ada, Rust and Zig.
#   HBNF=/path/to/hbnf sh tests/recursive.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/recursive
SCHEMA=tests/abnf/recursive.hbnf
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0

# check BACKEND OUTPUT PROGRAM ARGS...
check() {
	Backend=$1; Out=$2; Prog=$3; shift 3
	"$Prog" "$@" > "$W/got.txt" 2>&1
	Got=$?
	if [ "$Got" != "$Out" ]; then
		echo "recursive: $Backend FAIL (exit $Got, wanted $Out): $(head -1 "$W/got.txt")"
		rc=1
		return
	fi
	if [ "$Out" = 0 ]; then
		case $(cat "$W/got.txt") in
			"OK expr=set") ;;
			*) echo "recursive: $Backend FAIL (accepted but $(cat "$W/got.txt"))"; rc=1; return ;;
		esac
		echo "recursive: $Backend OK (accepts $*)"
	else
		case $(head -c 6 "$W/got.txt") in
			REJECT) ;;
			*) echo "recursive: $Backend FAIL (rejected oddly: $(head -1 "$W/got.txt"))"; rc=1; return ;;
		esac
		echo "recursive: $Backend OK (rejects $*)"
	fi
}

# ---- Ada -----------------------------------------------------------------
if command -v gnatmake > /dev/null 2>&1; then
	mkdir "$W/ada"
	"$CLI" "$SCHEMA" --backend=ada --package=Recursive > "$W/ada/all.ada" \
		|| { echo "recursive: Ada FAIL (does not generate)"; rc=1; }
	if [ -s "$W/ada/all.ada" ]; then
		cp $T/recursive_main.adb "$W/ada/"
		if (cd "$W/ada" && gnatchop -q -w all.ada \
			&& gnatmake -q -gnat2022 recursive_main.adb -o main) \
			> "$W/ada.err" 2>&1
		then
			check Ada 0   "$W/ada/main" "(1)"
			check Ada 1   "$W/ada/main" "1)"
			check Ada 0   "$W/ada/main" "((1))"
			check Ada 1   "$W/ada/main" "(1"
		else
			echo "recursive: Ada FAIL (compile)"; head -20 "$W/ada.err"; rc=1
		fi
	fi
else
	echo "recursive: Ada skipped (no gnatmake)"
fi

# ---- Rust ----------------------------------------------------------------
# `Option<Box<T>>`, so the struct still derives Default (a bare Box<T> would
# recurse without end building the default).  -D warnings as tests/portable.sh.
if command -v rustc > /dev/null 2>&1; then
	mkdir "$W/rs"
	"$CLI" "$SCHEMA" --backend=rust > "$W/rs/recursive.rs" \
		|| { echo "recursive: Rust FAIL (does not generate)"; rc=1; }
	if [ -s "$W/rs/recursive.rs" ]; then
		cp $T/main.rs "$W/rs/"
		if (cd "$W/rs" && rustc -D warnings main.rs -o main) > "$W/rs.err" 2>&1
		then
			check Rust 0   "$W/rs/main" "(1)"
			check Rust 1   "$W/rs/main" "1)"
			check Rust 0   "$W/rs/main" "((1))"
			check Rust 1   "$W/rs/main" "(1"
		else
			echo "recursive: Rust FAIL (compile)"; head -20 "$W/rs.err"; rc=1
		fi
	fi

	# The direct-member cycle, whose walkers descend through the box.
	mkdir "$W/rd"
	"$CLI" tests/abnf/recursive-direct.hbnf --backend=rust \
		> "$W/rd/recursive_direct.rs" \
		|| { echo "recursive: Rust direct FAIL (does not generate)"; rc=1; }
	if [ -s "$W/rd/recursive_direct.rs" ]; then
		cp $T/main_direct.rs "$W/rd/"
		if (cd "$W/rd" && rustc -D warnings main_direct.rs -o main) \
			> "$W/rd.err" 2>&1
		then
			# `(((5)))` is three x nodes deep; each walker must reach them all
			# through the box, so a walker that stopped at the pointer says 1.
			"$W/rd/main" "(((5)))" > "$W/got.txt" 2>&1
			if [ "$(cat "$W/got.txt")" = "OK visited=3 folded=3" ]; then
				echo "recursive: Rust direct OK (walkers reach all 3 nodes)"
			else
				echo "recursive: Rust direct FAIL ($(head -1 "$W/got.txt"))"; rc=1
			fi
			if "$W/rd/main" "((5)" > /dev/null 2>&1; then
				echo "recursive: Rust direct FAIL (accepted an unbalanced input)"; rc=1
			else
				echo "recursive: Rust direct OK (rejects ((5) )"
			fi
		else
			echo "recursive: Rust direct FAIL (compile)"; head -20 "$W/rd.err"; rc=1
		fi
	fi
else
	echo "recursive: Rust skipped (no rustc)"
fi

# ---- Zig -----------------------------------------------------------------
# `?*T`, zero-initialised null, and a generated deinit_<rule> that releases
# the box.  The drivers run under std.heap.DebugAllocator, whose leak report
# also names parse_text's own token and line arrays (it never frees them), so
# the gate is that no leaked allocation was made by the box (`box__anon`).
zig_run() { # DIR EXE -> $W/zig.out holds the case lines
	"$1/$2" > "$W/zig.raw" 2>&1
	grep -E '^[^ ].*: (OK|REJECT)' "$W/zig.raw" > "$W/zig.out"
	if grep -q 'in box__' "$W/zig.raw"; then
		echo "recursive: Zig $3 FAIL (a box leaked)"; rc=1; return 1
	fi
}
if command -v zig > /dev/null 2>&1; then
	mkdir "$W/zg"
	"$CLI" "$SCHEMA" --backend=zig > "$W/zg/recursive.zig" \
		|| { echo "recursive: Zig FAIL (does not generate)"; rc=1; }
	if [ -s "$W/zg/recursive.zig" ]; then
		cp $T/main.zig "$W/zg/"
		if (cd "$W/zg" && zig build-exe main.zig -femit-bin=main) > "$W/zg.err" 2>&1
		then
			if zig_run "$W/zg" main ""; then
				if [ "$(cat "$W/zig.out")" = "(1): OK expr=set
1): REJECT
((1)): OK expr=set
(1: REJECT" ]; then
					echo "recursive: Zig OK (accepts (1) ((1)), rejects 1) (1; no box leaked)"
				else
					echo "recursive: Zig FAIL ($(head -4 "$W/zig.out" | tr '\n' '|'))"; rc=1
				fi
			fi
		else
			echo "recursive: Zig FAIL (compile)"; head -20 "$W/zg.err"; rc=1
		fi
	fi

	# The direct-member cycle, whose walkers descend through the pointer.
	mkdir "$W/zd"
	"$CLI" tests/abnf/recursive-direct.hbnf --backend=zig \
		> "$W/zd/recursive_direct.zig" \
		|| { echo "recursive: Zig direct FAIL (does not generate)"; rc=1; }
	if [ -s "$W/zd/recursive_direct.zig" ]; then
		cp $T/main_direct.zig "$W/zd/"
		if (cd "$W/zd" && zig build-exe main_direct.zig -femit-bin=main) \
			> "$W/zd.err" 2>&1
		then
			if zig_run "$W/zd" main "direct"; then
				# `(((5)))` is three x nodes deep: each walker must reach all
				# of them through the pointer, not stop at it.
				if [ "$(cat "$W/zig.out")" = "(((5))): OK visited=3 folded=3
((5): REJECT" ]; then
					echo "recursive: Zig direct OK (walkers reach all 3 nodes; no box leaked)"
				else
					echo "recursive: Zig direct FAIL ($(head -2 "$W/zig.out" | tr '\n' '|'))"; rc=1
				fi
			fi
		else
			echo "recursive: Zig direct FAIL (compile)"; head -20 "$W/zd.err"; rc=1
		fi
	fi

	# deinit_<root> on a real tree (lists, entries), not just the boxes.
	mkdir "$W/zp"
	"$CLI" tests/portable/portable.hbnf --backend=zig > "$W/zp/portable.zig" \
		|| { echo "recursive: Zig deinit FAIL (does not generate)"; rc=1; }
	if [ -s "$W/zp/portable.zig" ]; then
		cp $T/deinit_main.zig tests/portable/good.conf tests/portable/quiet.conf "$W/zp/"
		if (cd "$W/zp" && zig build-exe deinit_main.zig -femit-bin=main) \
			> "$W/zp.err" 2>&1
		then
			"$W/zp/main" > "$W/zp.raw" 2>&1
			# A leak the tree made has a parse_<rule> frame; parse_text's own
			# arrays have only lex and parse_text.
			if grep -E ' in parse_[a-z_]+ ' "$W/zp.raw" | grep -qv ' in parse_text '; then
				echo "recursive: Zig deinit FAIL (the tree leaked)"; rc=1
			elif grep -qi 'invalid free\|double free' "$W/zp.raw"; then
				echo "recursive: Zig deinit FAIL (freed what it did not own)"; rc=1
			elif [ "$(grep -E '^(OK|REJECT)' "$W/zp.raw")" = "OK hosts=3
OK hosts=1" ]; then
				echo "recursive: Zig deinit OK (a real tree is released whole)"
			else
				echo "recursive: Zig deinit FAIL ($(head -2 "$W/zp.raw" | tr '\n' '|'))"; rc=1
			fi
		else
			echo "recursive: Zig deinit FAIL (compile)"; head -20 "$W/zp.err"; rc=1
		fi
	fi
else
	echo "recursive: Zig skipped (no zig)"
fi

exit $rc
