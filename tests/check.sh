#!/bin/sh
# check.sh -- run the test suites one at a time, and report each result as it comes: per suite,
# and per backend where a suite names them.  Every result is also appended to
# tests/results/check.tsv (when, revision, generator, arch, libc, suite, item, status, seconds),
# so progress can be followed over a day's work, and the log of each suite is kept in
# tests/results/logs/.
#
#   HBNF=/path/to/hbnf sh tests/check.sh                 every suite
#   sh tests/check.sh yaml toml                          just those suites
#   sh tests/check.sh yaml rust zig                      the yaml suite, in two backends
#   sh tests/check.sh --failed                           the suites that failed in the last run
#   sh tests/check.sh --list                             the suites, and the backends
#   sh tests/check.sh --status                           which suites are fresh, stale, or never run
#   sh tests/check.sh --force yaml                       run it even if nothing it depends on changed
#
# Like make, a suite is rerun only when something it depends on has changed since it last passed:
# its own script and the helpers it sources, the files it names under corpus/, grammars/ and
# tests/ (a grammar with the files it includes), and the part of the generator it exercises (the
# core, and the backends it runs).  A suite whose fingerprint is unchanged is shown as "same" with
# the time it last passed; --force runs it anyway, --status only lists which are fresh and which
# are stale.
#
# A word is a suite if a suite has that name, and a backend (c ada rust zig) otherwise; the
# backends restrict the suites that take them (schema, rfc, toml, yaml, params) and the lines
# shown for the others.  Suites run in sequence, never together, and a second check.sh refuses
# to start while one is running: results and timings come from one job at a time.
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
HBNF=${HBNF:-./hbnf}
export HBNF
R=tests/results
mkdir -p "$R/logs"

# name: the script, with the arguments it takes here.  A name is also the grammar or feature it
# tests where there is one.
SUITES="wire abnf syntax schema rfc enumval leftrec daemons writer ast spans tutorial errors forks
lookahead paths stmt recursive context params commalist compare algol60 numbers backref compact
posix hidden views textwarn c c79 c89 c99 gnu99 pcc99 toml yaml params-modes
e2e json-diff toml-diff yaml-suite yaml-diff"
ARGS_json_diff=3000; ARGS_toml_diff=3000; ARGS_yaml_diff=1000
BACKENDS_ALL="c ada rust zig"

if [ "${1:-}" = --list ]; then
	for s in $SUITES; do [ -f "tests/$s.sh" ] && echo "$s"; done
	echo "backends: $BACKENDS_ALL"
	exit 0
fi

# the words: suites and backends
WANT_S=""; WANT_B=""; FAILED=0; FORCE=0; STATUS=0
for w in "$@"; do
	case $w in
	--failed) FAILED=1 ;;
	--force|-f) FORCE=1 ;;
	--status) STATUS=1 ;;
	*) if [ -f "tests/$w.sh" ] && [ "$w" != suite ]; then WANT_S="$WANT_S $w"
	   else case " $BACKENDS_ALL " in *" $w "*) WANT_B="$WANT_B $w" ;;
	        *) echo "check.sh: '$w' is neither a suite nor a backend (--list shows them)" >&2; exit 2 ;; esac
	   fi ;;
	esac
done
if [ $FAILED = 1 ]; then
	[ -f "$R/last-failed" ] || { echo "check.sh: no failed run recorded"; exit 0; }
	WANT_S="$WANT_S $(cat "$R/last-failed")"
fi
[ -n "$WANT_S" ] || for s in $SUITES; do [ -f "tests/$s.sh" ] && WANT_S="$WANT_S $s"; done
[ -n "$WANT_B" ] && BK=$WANT_B || BK=$BACKENDS_ALL


# ---- what a suite depends on ----------------------------------------------------------------
arch=$(uname -m)
libc=$(ldd --version 2>&1 | head -1 | grep -qi musl && echo musl || echo glibc)
S=$R/stamps/$arch-$libc
mkdir -p "$S"
hashfiles() { # FILE...: one hash of names and contents
	for f in "$@"; do [ -f "$f" ] && printf '%s %s\n' "$f" "$(sha256sum < "$f" | cut -c1-16)"; done | sha256sum | cut -c1-16
}
# the files a grammar includes, transitively
closure() {
	todo="$*"; seen=""
	while [ -n "$todo" ]; do
		set -- $todo; f=$1; shift; todo="$*"
		case " $seen " in *" $f "*) continue ;; esac
		[ -f "$f" ] || continue
		seen="$seen $f"
		for i in $(sed -n 's/^[ \t]*include[ \t]*"\([^"]*\)".*/\1/p' "$f"); do todo="$todo $(dirname "$f")/$i"; done
	done
	echo $seen
}
# the files named in a suite script, expanded; a directory is every file under it
suite_files() {
	for w in $(grep -oE '(corpus|grammars|tests|bench/formats)/[A-Za-z0-9_./*-]+' "tests/$1.sh" | sort -u); do
		case $w in tests/results*) continue ;; esac
		for g in $w; do
			if [ -d "$g" ]; then
				# a directory the script names: the entries it names by name, else all of it
				hit=0
				for e in $(ls "$g"); do
					if grep -qF -- "$e" "tests/$1.sh"; then hit=1; find "$g/$e" -type f; fi
				done
				[ $hit = 1 ] || find "$g" -type f
			elif [ -f "$g" ]; then echo "$g"; fi
		done
	done
	echo "tests/$1.sh"; [ -f tests/suite.sh ] && grep -q 'tests/suite.sh' "tests/$1.sh" && echo tests/suite.sh
}
# the backends a suite runs: a script that names one backend runs that one, and one that picks
# the backend by a variable (or takes BACKENDS) runs all.  With a backend filter, those.
suite_backends() {
	if [ -n "$WANT_B" ]; then echo $WANT_B; return; fi
	b=$(grep -oE -- '--backend=[A-Za-z$_{}]+' "tests/$1.sh" | sed 's/--backend=//' | sort -u)
	case "$b$(grep -c 'BACKENDS\|want ' "tests/$1.sh")" in
	*'$'*|*'{'*|*[1-9]) echo "$BACKENDS_ALL" ;;
	'0') echo c ;;
	*) echo $b ;;
	esac
}
core_src() { ls hbnf.adb hbnf_grammar.ad[sb] hbnf_lookahead.ad[sb] hbnf_compilable.ad[sb] hbnf_wire.ad[sb] hbnf_wire-lower.ad[sb] hbnf_c.ads 2> /dev/null; }
backend_src() {
	case $1 in
	c) ls hbnf_c.adb hbnf_wire-c.ad[sb] templates/c_* templates/conf_* 2> /dev/null ;;
	rust) ls hbnf_rust.ad[sb] hbnf_wire-rust.ad[sb] templates/rust_* hbnf_c.adb 2> /dev/null ;;
	zig) ls hbnf_zig.ad[sb] hbnf_wire-zig.ad[sb] templates/zig_* hbnf_c.adb 2> /dev/null ;;
	ada) ls hbnf_ada.ad[sb] hbnf_wire-ada_lang.ad[sb] templates/ada_* hbnf_c.adb 2> /dev/null ;;
	esac
}
fingerprint() { # SUITE
	files=$(suite_files "$1" | sort -u)
	hb=""; for f in $files; do case $f in *.hbnf) hb="$hb $f" ;; esac; done
	gen="$(core_src) $(for b in $(suite_backends "$1"); do backend_src "$b"; done)"
	printf '%s %s %s %s\n' "$(hashfiles $files $(closure $hb))" "$(hashfiles $(echo $gen | tr ' ' '\n' | sort -u))" \
		"$(suite_backends "$1" | tr ' ' ,)" "${YAML_TEST_SUITE:-}"
}
stamp_name() { echo "$S/$1@$(suite_backends "$1" | tr ' ' ,)"; }

if [ $STATUS = 1 ]; then
	for s in $WANT_S; do
		[ -f "tests/$s.sh" ] || continue
		st=$(stamp_name "$s")
		if [ ! -f "$st" ]; then w=never
		elif [ "$(sed -n 2p "$st")" = "$(fingerprint "$s")" ]; then w="fresh  (passed $(sed -n 1p "$st"))"
		else w="stale  (last passed $(sed -n 1p "$st"))"; fi
		printf '%-14s %s\n' "$s" "$w"
		[ -n "${CHECK_DEBUG:-}" ] && printf '    %s\n' "$(fingerprint "$s")"
	done
	exit 0
fi

# one job at a time
exec 9> "$R/.lock"
if command -v flock > /dev/null 2>&1; then
	flock -n 9 || { echo "check.sh: another check is running; results and timings need one at a time" >&2; exit 3; }
fi

rev=$(git -c safe.directory='*' rev-parse --short HEAD 2> /dev/null || true)
if [ -z "$rev" ] && [ -f .git/HEAD ]; then   # no git here (a container): read the files
	ref=$(sed -n 's/^ref: //p' .git/HEAD)
	rev=$(cut -c1-7 < ".git/${ref:-HEAD}" 2> /dev/null || true)
fi
rev=${rev:-unknown}
gen=$(basename "$HBNF")
when() { date +%Y-%m-%dT%H:%M:%S; }
emit() { # SUITE ITEM STATUS SECONDS
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(when)" "$rev" "$gen" "$arch" "$libc" "$1" "$2" "$3" "$4" >> "$R/check.tsv"
	printf '%-5s %-14s %-10s %5ss   [%s %s]\n' "$3" "$1" "$2" "$4" "$arch" "$libc"
}

pass=0; fail=0; same=0; : > "$R/last-failed.new"
for s in $WANT_S; do
	[ -f "tests/$s.sh" ] || { echo "SKIP  $s (no such suite)"; continue; }
	name=$(echo "$s" | tr 'a-z-' 'A-Z_')
	# the backends this suite takes
	[ -n "$WANT_B" ] && export "${name}_BACKENDS=$WANT_B"
	eval "args=\${ARGS_$(echo "$s" | tr - _):-}"
	log="$R/logs/$s.log"
	fp=$(fingerprint "$s"); st=$(stamp_name "$s")
	if [ $FORCE = 0 ] && [ -f "$st" ] && [ "$(sed -n 2p "$st")" = "$fp" ]; then
		printf '%-5s %-14s %-10s        (nothing it depends on changed since %s)\n' same "$s" "(all)" "$(sed -n 1p "$st")"
		same=$((same + 1)); continue
	fi
	t0=$(date +%s)
	timeout 3000 sh "tests/$s.sh" $args > "$log" 2>&1 9>&-
	rc=$?
	secs=$(( $(date +%s) - t0 ))
	# a backend's own lines, "suite: Rust OK (...)" or "suite: Rust FAIL (...)"
	items=$(sed -n 's/^[a-z0-9 -]*: \(C\|Ada\|Rust\|Zig\|Tree-sitter\)[ ]*\(OK\|FAIL\).*/\1 \2/p' "$log" | sort -u)
	if [ -n "$items" ]; then
		echo "$items" | while read -r b st; do
			bl=$(echo "$b" | tr 'A-Z' 'a-z')
			case " $BK " in *" $bl "*) ;; *) continue ;; esac
			emit "$s" "$bl" "$([ "$st" = OK ] && echo ok || echo FAIL)" "-"
		done
	fi
	if [ $rc = 0 ]; then printf '%s\n%s\n' "$(when)" "$fp" > "$(stamp_name "$s")"; st=ok; pass=$((pass + 1)); else st=FAIL; fail=$((fail + 1)); echo "$s" >> "$R/last-failed.new"; fi
	emit "$s" "(all)" "$st" "$secs"
	[ $rc = 0 ] || { grep -E "FAIL|error|^[-+][^-+]" "$log" | head -4 | sed 's/^/        /'; echo "        (log: $log)"; }
done
mv "$R/last-failed.new" "$R/last-failed"
echo "-- $pass suites ok, $fail failed, $same unchanged   ($rev, $gen, $arch $libc)"
[ $fail = 0 ]
