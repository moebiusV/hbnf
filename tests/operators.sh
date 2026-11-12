#!/bin/sh
# C++ operator overloading, as the notation must carry it for the C++ grammars (tests/operators/cxx-operators.hbnf): `operator()` and
# `operator[]` (paren and bracket pairs, blanks allowed between), `operator new[]`, the operators that are the front of another, the
# literal operator and the conversion function.  C first; the same cases are run in Rust where rustc is installed.
#   HBNF=/path/to/hbnf sh tests/operators.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0; n=0
G=tests/operators/cxx-operators.hbnf
"$CLI" $G --backend=c > "$W/o.c" 2> "$W/err" || { echo "operators: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/o.c")
cat "$W/o.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/chk" 2> "$W/cc.txt" || { echo "operators: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
CASES="$W/cases.txt"
cat > "$CASES" <<'EOF'
ok	operator+;
ok	operator ( );
ok	operator();
ok	operator[];
ok	operator [ ];
ok	operator new[];
ok	operator new [ ];
ok	operator delete [ ];
ok	operator new;
ok	operator delete;
ok	operator->*;
ok	operator->;
ok	operator<=>;
ok	operator<=;
ok	operator<<=;
ok	operator<<;
ok	operator<;
ok	operator>>=;
ok	operator,;
ok	operator co_await;
ok	operator""_km;
ok	operator "" _km;
ok	operator int*;
ok	operator foo&;
ok	operator+;operator();operator[];operator new[];
ok	operator()
bad	operator;
bad	operator(;
bad	operator();(;
bad	operator[;
bad	operator new[;
bad	operator"";
EOF
# (the line `ok operator()` has no `;`: it must be refused; it is written bad below)
sed -i 's/^ok\toperator()$/bad\toperator()/' "$CASES"
while IFS="$(printf '\t')" read -r want text; do
	printf '%s' "$text" > "$W/t.txt"; got=$("$W/chk" "$W/t.txt" | cut -d' ' -f1)
	n=$((n + 1)); [ "$got" = "$want" ] || { echo "operators: FAIL ([$text] should be $want and is $got)"; fail=1; }
done < "$CASES"
if command -v rustc > /dev/null 2>&1; then
	mkdir -p "$W/rs"
	"$CLI" $G --backend=rust > "$W/rs/l.rs" 2> "$W/err" || { echo "operators: FAIL (does not generate in Rust)"; exit 1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$W/rs/m.rs"
	(cd "$W/rs" && rustc --edition 2021 -A warnings -C opt-level=0 -o m m.rs > cc.txt 2>&1) || { echo "operators: FAIL (the Rust parser does not compile)"; exit 1; }
	while IFS="$(printf '\t')" read -r want text; do
		printf '%s' "$text" > "$W/t.txt"; got=$("$W/rs/m" "$W/t.txt" 2>&1 | cut -d' ' -f1 | head -1)
		n=$((n + 1)); [ "$got" = "$want" ] || { echo "operators: FAIL ([$text] in Rust should be $want and is $got)"; fail=1; }
	done < "$CASES"
fi
[ $fail = 0 ] && echo "operators: OK ($n results: operator() and operator[] with and without blanks, new[] and delete[], the operators that are the front of another, operator\"\"_x, operator T*; C and, where rustc is installed, Rust)"
exit $fail
