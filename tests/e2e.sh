#!/bin/sh
# Cross-language end-to-end smoke test for the hbnf CLI: emit a self-contained
# parser (declarations + lexer + parser) in each language, compile and run it.
# Run inside the ada-toolchain:edge-full container (gcc-gnat, g++, rust, zig).
set -u
rc=0   # any suite below that fails makes this one fail
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
HERE=$(pwd)

# mustache-ada (moebiusV/mustache-ada, the ada-on-alpine aport) renders the
# code templates.  gprinstall puts its sources here; MUSTACHE_INC overrides
# for a different prefix or a source checkout.  gnatmake compiles the two
# sources itself, so no library link is needed.
MUSTACHE_INC="${MUSTACHE_INC:-/usr/include/mustache}"
if [ ! -f "$MUSTACHE_INC/mustache.ads" ]; then
	echo "e2e: no mustache.ads under $MUSTACHE_INC (set MUSTACHE_INC=)" >&2
	exit 1
fi
A="-gnat2022 -I. -Itests -I$MUSTACHE_INC"

# A stale .o in the source directory wins the link: gnatmake -D <tmpdir>
# compiles into the temp directory, but gnatlink takes hbnf.ali from `.`, so
# the build reports success while running yesterday's code.  They are
# .gitignore'd, so `git status` does not show it.  Clear them, then check the
# binary really is newer than every source that went into it.
rm -f ./*.o ./*.ali

newer_than_sources() { # $1 = binary
	[ -f "$1" ] || return 1
	for f in ./*.ad[bs] tests/*.ad[bs] "$MUSTACHE_INC"/*.ad[bs]; do
		[ -f "$f" ] || continue
		[ "$f" -nt "$1" ] && return 1
	done
	return 0
}

echo "== building generators =="
gnatmake -q $A hbnf.adb -o /tmp/hbnf
gnatmake -q $A tests/gen_all.adb -o /tmp/gen_all
for b in /tmp/hbnf /tmp/gen_all; do
	newer_than_sources "$b" || {
		echo "e2e: $b is older than a source it was built from;" \
		     "a stale object won the link (rm -f *.o *.ali)" >&2
		exit 1
	}
done

# the drivers use unprefixed names: one copy of the schema says so for every leg
(echo "prefix none"; cat tests/server.hbnf) > /tmp/server-np.hbnf

echo "== C =="
/tmp/hbnf /tmp/server-np.hbnf --backend=c --no-views > /tmp/server.c
cp tests/c_main.c /tmp/
( cd /tmp && gcc -std=gnu11 -D_GNU_SOURCE -I"$HERE/tests/bsdinc" c_main.c -o c_test 2> c_test.err \
    && ./c_test ) || { head -20 /tmp/c_test.err; echo "e2e: the C smoke test failed"; rc=1; }

echo "== C: entry points the grammar's epilogue writes (tests/server_ffi.hbnf) =="
/tmp/hbnf tests/server_ffi.hbnf --backend=c --no-views > /tmp/server_ffi.c
cat /tmp/server_ffi.c tests/conf_main.c > /tmp/conf_test.c
( cd /tmp
  printf '"example.com"\non wg0 port 443\n"/var/www"\n"www"\nyes\n' > valid.conf
  printf '"example.com"\non wg0 port oops\n"/var/www"\n"www"\nyes\n' > bad.conf
  gcc -std=gnu11 -D_GNU_SOURCE -I"$HERE/runtime" -I"$HERE/tests/bsdinc" conf_test.c "$HERE/runtime/hbnf_conf.c" \
    -o conf_test > cc.out 2>&1 \
    && ./conf_test || { head -20 cc.out; false; }
) || { echo "e2e: the C entry-point test failed"; rc=1; }

echo "== FFI (C shared lib + ctypes/Fiddle) =="
( cd /tmp
  cc -shared -fPIC -I"$HERE/runtime" -I"$HERE/tests/bsdinc" server_ffi.c "$HERE/runtime/hbnf_conf.c" -o libhbnfconf.so 2>&1 | head -10
  if command -v python3 >/dev/null 2>&1; then
    cp "$HERE/bindings/python/hbnfconf.py" .
    echo "  python:"; LD_LIBRARY_PATH=. python3 hbnfconf.py valid.conf 2>&1 | head -20
  else
    echo "  (python3 not installed -- skipping)"
  fi
  if command -v ruby >/dev/null 2>&1; then
    cp "$HERE/bindings/ruby/hbnfconf.rb" .
    echo "  ruby:"; LD_LIBRARY_PATH=. ruby hbnfconf.rb valid.conf 2>&1 | head -20
  else
    echo "  (ruby not installed -- skipping)"
  fi
)

echo "== Rust =="
if command -v rustc >/dev/null 2>&1; then
    /tmp/hbnf /tmp/server-np.hbnf --backend=rust > /tmp/server.rs
    cp tests/rust_main.rs /tmp/
    ( cd /tmp && rustc rust_main.rs -o rust_test > cc.out 2>&1 \
        && ./rust_test || { head -20 cc.out; false; } ) || { echo "e2e: a leg failed (see above)"; rc=1; }
else
    echo "  (rustc not installed -- skipping)"
fi

echo "== Zig =="
if command -v zig >/dev/null 2>&1; then
    /tmp/hbnf /tmp/server-np.hbnf --backend=zig > /tmp/server.zig
    cp tests/zig_main.zig /tmp/
    ( cd /tmp && zig build-exe zig_main.zig -femit-bin=zig_test > cc.out 2>&1 \
        && ./zig_test || { head -30 cc.out; false; } ) || { echo "e2e: a leg failed (see above)"; rc=1; }
else
    echo "  (zig not installed -- skipping)"
fi

echo "== Ada =="
/tmp/gen_all /tmp/server-np.hbnf
cp tests/ada_main.adb /tmp/
cp server_schema.ads server_schema-parser.ads server_schema-parser.adb /tmp/
( cd /tmp && gnatmake -q -gnat2022 ada_main.adb -o ada_test > cc.out 2>&1 \
        && ./ada_test || { head -30 cc.out; false; } ) || { echo "e2e: a leg failed (see above)"; rc=1; }

echo "== daemon grammars (tests/daemons) =="
HBNF=/tmp/hbnf sh tests/daemons.sh || rc=1

echo "== statements, macros, include (tests/stmt) =="
HBNF=/tmp/hbnf sh tests/stmt.sh || rc=1

echo "== macros against hand expansion (tests/compare) =="
HBNF=/tmp/hbnf sh tests/compare.sh || rc=1

echo "== notation beyond ABNF (tests/syntax) =="
HBNF=/tmp/hbnf sh tests/syntax.sh || rc=1

echo "== left recursion, read as a loop (tests/leftrec) =="
HBNF=/tmp/hbnf sh tests/leftrec.sh || rc=1

echo "== one schema through every backend (tests/portable) =="
HBNF=/tmp/hbnf sh tests/portable.sh || rc=1

echo "== a recursive tree type, compiled and run (tests/recursive) =="
HBNF=/tmp/hbnf sh tests/recursive.sh || rc=1

echo "== the obconf configuration-file grammar, against tests/accept and tests/reject =="
HBNF=/tmp/hbnf sh tests/schema.sh || rc=1

echo "== the RFC corpus: corpus/rfc/, RFC 5234, 3986, 5322, 9112 (tests/rfc.sh, headline rules) =="
RFC_QUICK=1 HBNF=/tmp/hbnf sh tests/rfc.sh || rc=1

echo "== character rules and UTF-8 (tests/utf8-test.sh) =="
HBNF=/tmp/hbnf sh tests/utf8-test.sh || rc=1

echo "== RFC 5234 forms (tests/abnf.sh) =="
HBNF=/tmp/hbnf sh tests/abnf.sh || rc=1

echo "== the reader and emitters (tests/hbnf_emit_check.adb) =="
gnatmake -q $A tests/hbnf_emit_check.adb -o /tmp/hbnf_emit_check \
    && { /tmp/hbnf_emit_check tests/server.hbnf hbnf_schema.hbnf > /tmp/emit.out 2>&1; st=$?
      grep -v '^ok:' /tmp/emit.out
      [ $st = 0 ] || { echo "e2e: the emit check failed"; rc=1; }; }

rm -f server.c server.rs server.zig server_schema.ads server_schema-parser.ads server_schema-parser.adb
exit $rc
