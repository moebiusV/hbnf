# tree-zig.sh: `->` in the Zig backend, sourced by tests/consequence.sh (CLI, W, fail and total are set; the cwd is the
# repo root).  tree.hbnf is generated for Zig, compiled with tree-driver.zig and every case of tree-cases.txt is run;
# then what Zig does not build (layout tape, a fact in the template) is checked to be refused, naming the rule.
# Zig is the host's, or the docker image ada-toolchain:edge-full's; with neither the whole fragment is skipped.
zig_run=
if command -v zig > /dev/null 2>&1; then
	zig_run=host
elif command -v docker > /dev/null 2>&1 && docker image inspect ada-toolchain:edge-full > /dev/null 2>&1; then
	zig_run=docker
fi
if [ -n "$zig_run" ]; then
	d=$W/tree-zig; mkdir -p "$d"
	"$CLI" tests/consequence/tree.hbnf --backend=zig > "$d/p.zig" 2> "$d/err" \
		|| { echo "consequence: FAIL (tree does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	if [ -s "$d/p.zig" ]; then
		cp tests/consequence/tree-driver.zig "$d/m.zig"
		zb='zig build-exe m.zig -O ReleaseFast -femit-bin=m'
		if [ "$zig_run" = host ]; then
			(cd "$d" && sh -c "$zb") > "$d/cc.txt" 2>&1
		else
			docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e ZIG_GLOBAL_CACHE_DIR=/tmp/zc -e ZIG_LOCAL_CACHE_DIR=/tmp/zl \
				-v "$d":/w -w /w ada-toolchain:edge-full sh -c "$zb" > "$d/cc.txt" 2>&1
		fi
		if [ -x "$d/m" ]; then
			while IFS="$(printf '\t')" read -r want a b; do
				total=$((total + 1))
				got=$("$d/m" "$a" "$b" 2>&1 | cut -d: -f1)
				[ "$got" = "$want" ] || { echo "consequence: FAIL (tree zig [$a] and [$b]: should be $want and is $got)"; fail=1; }
			done < tests/consequence/tree-cases.txt
		else
			echo "consequence: FAIL (tree: the Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1
		fi
	fi
	# refused, not ignored: layout tape; a fact in the template
	total=$((total + 1))
	"$CLI" tests/consequence/tree.hbnf --backend=zig --layout=tape > "$d/o.txt" 2> "$d/e.txt" \
		&& { echo "consequence: FAIL (tree zig: --layout=tape was not refused)"; fail=1; }
	grep -q 'cond' "$d/e.txt" || { echo "consequence: FAIL (tree zig: the refusal of layout tape does not name the rule: $(head -c 200 "$d/e.txt"))"; fail=1; }
	cat > "$d/fact.hbnf" <<'EOG'
prefix none
whitespace none
pair = name as A "=" name as B -> A.kind "=" B
name = 1*0x61..0x7A
EOG
	total=$((total + 1))
	"$CLI" "$d/fact.hbnf" --backend=zig > "$d/o.txt" 2> "$d/e.txt" \
		&& { echo "consequence: FAIL (tree zig: a template with a fact was not refused)"; fail=1; }
	grep -q 'pair' "$d/e.txt" || { echo "consequence: FAIL (tree zig: the refusal of a fact does not name the rule: $(head -c 200 "$d/e.txt"))"; fail=1; }
fi
