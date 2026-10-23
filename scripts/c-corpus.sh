#!/bin/sh
# Fetch the C corpora the pcc size work used (lua, zlib, lz4, cJSON, chibicc, c-testsuite, mbedtls,
# BearSSL, the SQLite amalgamation, gcc's c-torture execute tests) into DIR, preprocess every file with
# gcc -E, keep the ones gcc -fsyntax-only accepts, and give them to the generated C11 parser.
# The sources are the branch heads (or the releases named below) on the day this is run, so the counts move.
#   HBNF=/path/to/hbnf sh scripts/c-corpus.sh [DIR]      (default ./c-corpora, ~700 MB with the torture checkout)
set -u
cd "$(dirname "$0")/.."
DIR=${1:-c-corpora}
mkdir -p "$DIR"; DIR=$(cd "$DIR" && pwd)
fetch() {   # fetch NAME URL
	[ -d "$DIR/$1" ] && return 0
	mkdir -p "$DIR/$1" && wget -q -O "$DIR/$1.tgz" "$2" && tar xzf "$DIR/$1.tgz" -C "$DIR/$1" --strip-components=1 \
		|| { echo "could not fetch $1"; rm -rf "$DIR/$1" "$DIR/$1.tgz"; }
}
fetch lua https://github.com/lua/lua/archive/refs/heads/master.tar.gz
fetch zlib https://github.com/madler/zlib/archive/refs/heads/master.tar.gz
fetch lz4 https://github.com/lz4/lz4/archive/refs/heads/dev.tar.gz
fetch cjson https://github.com/DaveGamble/cJSON/archive/refs/heads/master.tar.gz
fetch chibicc https://github.com/rui314/chibicc/archive/refs/heads/main.tar.gz
fetch c-testsuite https://github.com/c-testsuite/c-testsuite/archive/refs/heads/master.tar.gz
fetch mbedtls https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v3.6.0.tar.gz
[ -d "$DIR/bearssl" ] || git clone -q --depth 1 https://bearssl.org/git/BearSSL "$DIR/bearssl"
if [ ! -d "$DIR/sqlite" ]; then
	mkdir -p "$DIR/sqlite" && (cd "$DIR/sqlite" && wget -q https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip && unzip -q -o sqlite-amalgamation-3450100.zip)
fi
if [ ! -d "$DIR/gcc-sparse" ]; then
	git clone -q --depth 1 --filter=blob:none --sparse https://github.com/gcc-mirror/gcc.git "$DIR/gcc-sparse" \
		&& (cd "$DIR/gcc-sparse" && git sparse-checkout set gcc/testsuite/gcc.c-torture/execute)
fi

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
"$CLI" corpus/c/c11.hbnf --backend=c > "$W/c11.c" 2> /dev/null || { echo "generate failed"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c11.c")
cat "$W/c11.c" corpus/c/check.c > "$W/m.c"
cc -O2 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || exit 1

n=0
{ for c in lua zlib lz4 cjson chibicc c-testsuite mbedtls bearssl; do find "$DIR/$c" -name '*.c' -size -600k | sort; done
  find "$DIR/sqlite" -name sqlite3.c
  ls "$DIR"/gcc-sparse/gcc/testsuite/gcc.c-torture/execute/*.c; } | while read -r f; do
	n=$((n + 1)); d=$(dirname "$f"); c=${f#"$DIR"/}; c=${c%%/*}; r=$DIR/$c
	gcc -E -P -std=gnu11 -D_GNU_SOURCE -I"$d" -I"$d/.." -I"$r" -I"$r/include" -I"$r/inc" -I"$r/lib" -I"$r/library" -I"$r/src" -w "$f" > "$W/u$n.i" 2> /dev/null || continue
	gcc -fsyntax-only -std=gnu11 -w "$W/u$n.i" 2> /dev/null && echo "$W/u$n.i $c"
done > "$W/list.txt"
"$W/check" $(cut -d' ' -f1 "$W/list.txt") > "$W/out.txt" 2>&1
awk 'NR == FNR { c[$1] = $2; next } { f = $2; sub(/:$/, "", f); k = c[f]; if ($1 == "ok") ok[k]++; else bad[k]++ }
     END { for (k in ok) tot[k] = 1; for (k in bad) tot[k] = 1
           for (k in tot) printf "%-12s gcc accepts %4d, the grammar accepts %4d\n", k, ok[k] + bad[k], ok[k] + 0 }' "$W/list.txt" "$W/out.txt" | sort
awk '/^ok/{o++} /^bad/{b++} END { printf "total: gcc accepts %d, the grammar accepts %d, refuses %d\n", o + b, o + 0, b + 0 }' "$W/out.txt"
