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
# covers the backends whose driver lives here: Ada now; Rust and Zig as their
# stage of 9b lands.
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

exit $rc
