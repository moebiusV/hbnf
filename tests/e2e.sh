#!/bin/sh
# Cross-language end-to-end smoke test for the astbnf parser generators: build
# the generators, emit the server schema in all four languages, compile and run
# each.  Run inside the Alpine container (has gcc-gnat; rust/zig are optional).
set -u
cd "$(dirname "$0")/.."

echo "== building generators =="
gnatmake -q -gnat2022 -I. -Itests tests/gen_all.adb -o /tmp/gen_all
rm -f server.c server.rs server.zig server_schema.ads server_schema-parser.ads server_schema-parser.adb
/tmp/gen_all tests/server.astbnf

echo "== C =="
cp tests/c_main.c /tmp/
cp server.c /tmp/
( cd /tmp && gcc -std=gnu11 -D_GNU_SOURCE c_main.c -o c_test 2>&1 | head -20 && ./c_test )

echo "== Rust =="
if command -v rustc >/dev/null 2>&1; then
    cp tests/rust_main.rs /tmp/
    cp server.rs /tmp/
    ( cd /tmp && rustc rust_main.rs -o rust_test 2>&1 | head -20 && ./rust_test )
else
    echo "  (rustc not installed -- skipping)"
fi

echo "== Zig =="
if command -v zig >/dev/null 2>&1; then
    cp tests/zig_main.zig /tmp/
    cp server.zig /tmp/
    ( cd /tmp && zig build-exe zig_main.zig -femit-bin=zig_test 2>&1 | head -30 && ./zig_test )
else
    echo "  (zig not installed -- skipping)"
fi

echo "== Ada =="
cp tests/ada_main.adb /tmp/
cp server_schema.ads server_schema-parser.ads server_schema-parser.adb /tmp/
( cd /tmp && gnatmake -q -gnat2022 ada_main.adb -o ada_test 2>&1 | head -30 && ./ada_test )
