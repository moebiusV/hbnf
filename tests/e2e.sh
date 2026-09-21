#!/bin/sh
# Cross-language end-to-end smoke test for the astbnf CLI: emit a self-contained
# parser (declarations + lexer + parser) in each language, compile and run it.
# Run inside the Alpine container (has gcc-gnat; rust/zig are optional).
set -u
cd "$(dirname "$0")/.."

echo "== building generators =="
gnatmake -q -gnat2022 -I. -Itests astbnf_cli.adb -o /tmp/astbnf_cli
gnatmake -q -gnat2022 -I. -Itests tests/gen_all.adb -o /tmp/gen_all

echo "== C =="
/tmp/astbnf_cli tests/server.astbnf --backend=c > /tmp/server.c
cp tests/c_main.c /tmp/
( cd /tmp && gcc -std=gnu11 -D_GNU_SOURCE c_main.c -o c_test 2>&1 | head -20 && ./c_test )

echo "== Rust =="
if command -v rustc >/dev/null 2>&1; then
    /tmp/astbnf_cli tests/server.astbnf --backend=rust > /tmp/server.rs
    cp tests/rust_main.rs /tmp/
    ( cd /tmp && rustc rust_main.rs -o rust_test 2>&1 | head -20 && ./rust_test )
else
    echo "  (rustc not installed -- skipping)"
fi

echo "== Zig =="
if command -v zig >/dev/null 2>&1; then
    /tmp/astbnf_cli tests/server.astbnf --backend=zig > /tmp/server.zig
    cp tests/zig_main.zig /tmp/
    ( cd /tmp && zig build-exe zig_main.zig -femit-bin=zig_test 2>&1 | head -30 && ./zig_test )
else
    echo "  (zig not installed -- skipping)"
fi

echo "== Ada =="
/tmp/gen_all tests/server.astbnf
cp tests/ada_main.adb /tmp/
cp server_schema.ads server_schema-parser.ads server_schema-parser.adb /tmp/
( cd /tmp && gnatmake -q -gnat2022 ada_main.adb -o ada_test 2>&1 | head -30 && ./ada_test )
rm -f server.c server.rs server.zig server_schema.ads server_schema-parser.ads server_schema-parser.adb
