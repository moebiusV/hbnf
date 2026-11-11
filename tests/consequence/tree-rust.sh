# tree-rust.sh: `->` in the Rust backend (sourced by tests/consequence.sh; $CLI, $W, $fail, $total are set).
# tree.hbnf is generated for Rust, compiled with tests/consequence/tree-driver.rs and every case of tree-cases.txt run;
# then what Rust does not do is refused: layout tape, and a template with a fact.
if command -v rustc > /dev/null 2>&1; then
	d=$W/tree-rs; mkdir -p "$d"
	"$CLI" tests/consequence/tree.hbnf --backend=rust > "$d/p.rs" 2> "$d/err" \
		|| { echo "consequence: FAIL (tree for rust does not generate: $(head -c 300 "$d/err"))"; fail=1; }
	if [ -s "$d/p.rs" ]; then
		cat "$d/p.rs" tests/consequence/tree-driver.rs > "$d/m.rs"
		if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
			while IFS="$(printf '\t')" read -r want a b; do
				total=$((total + 1))
				got=$("$d/m" "$a" "$b" | cut -d: -f1)
				[ "$got" = "$want" ] || { echo "consequence: FAIL (tree for rust [$a] and [$b]: should be $want and is $got)"; fail=1; }
			done < tests/consequence/tree-cases.txt
		else echo "consequence: FAIL (tree: the Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
	fi
	# a template that rewrites itself ends with an error, and does not overflow the stack
	cat > "$d/loop.hbnf" <<'EOT'
prefix none
whitespace none
r = "a" as A -> "a"
  | "b"
EOT
	total=$((total + 1))
	"$CLI" "$d/loop.hbnf" --backend=rust > "$d/loop.rs" 2> "$d/err" \
		&& { cat "$d/loop.rs" > "$d/lm.rs"
		     printf 'fn main() { println!("{}", match parse_text("a") { Ok(_) => "ok".to_string(), Err(e) => e.msg }); }\n' >> "$d/lm.rs"
		     if (cd "$d" && rustc --edition 2021 -A warnings -o lm lm.rs > lcc.txt 2>&1); then
			     case $("$d/lm" 2>&1) in *"rewrite that ends"*|*"tree that is as"*) ;; *) echo "consequence: FAIL (rust: a template that rewrites itself does not end with an error)"; fail=1 ;; esac
		     else echo "consequence: FAIL (rust: the self-rewriting grammar does not compile: $(head -c 300 "$d/lcc.txt"))"; fail=1; fi; } \
		|| { echo "consequence: FAIL (rust: the self-rewriting grammar does not generate: $(head -c 300 "$d/err"))"; fail=1; }
fi
# layout tape is the C backend's: refused for Rust
total=$((total + 1))
if "$CLI" tests/consequence/tree.hbnf --backend=rust --layout=tape > /dev/null 2> "$W/tree-rs-tape.err"; then
	echo "consequence: FAIL (tree: rust accepted layout tape)"; fail=1
else grep -q "layout tape" "$W/tree-rs-tape.err" || { echo "consequence: FAIL (tree: the refusal of layout tape for rust says: $(head -c 200 "$W/tree-rs-tape.err"))"; fail=1; }; fi
# a fact in the template is C's: refused for Rust, naming the rule
total=$((total + 1))
cat > "$W/tree-fact.hbnf" <<'EOT'
prefix none
whitespace none
cond = name as A " > " num as B -> A.attr " > " B
name = 1*0x61..0x7A
num = 1*0x30..0x39
EOT
if "$CLI" "$W/tree-fact.hbnf" --backend=rust > /dev/null 2> "$W/tree-rs-fact.err"; then
	echo "consequence: FAIL (tree: rust accepted a fact in a template)"; fail=1
else grep -q "rule \`cond\`" "$W/tree-rs-fact.err" || { echo "consequence: FAIL (tree: the refusal of a fact for rust does not name the rule: $(head -c 200 "$W/tree-rs-fact.err"))"; fail=1; }; fi
