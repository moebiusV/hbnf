# `->` in the Ada backend: sourced by tests/consequence.sh (it sets $CLI, $W, $fail, $total; cwd is the repo root).
# tests/consequence/tree.hbnf is generated as Ada, built with tests/consequence/tree-driver.adb and every case of
# tree-cases.txt is run; then what the backend does not do (layout tape, a fact or a function in the template) is
# refused with the rule named.  The compile needs gnatmake: the host's, else the container ada-toolchain:edge
# (docker), else the Ada part is skipped quietly.
ada_in() {   # ada_in DIR COMMAND: run COMMAND (sh) in DIR, where gnatmake is
	if command -v gnatmake > /dev/null 2>&1; then
		( cd "$1" && sh -c "$2" )
	else
		docker run --rm -u "$(id -u):$(id -g)" -v "$1":/w -w /w ada-toolchain:edge sh -c "$2"
	fi
}
ada_ok=
if command -v gnatmake > /dev/null 2>&1; then ada_ok=1
elif command -v docker > /dev/null 2>&1 && docker image inspect ada-toolchain:edge > /dev/null 2>&1; then ada_ok=1; fi
if [ -n "$ada_ok" ]; then
	d=$W/tree-ada; mkdir -p "$d"
	"$CLI" tests/consequence/tree.hbnf --backend=ada --package=Tr --ast > "$d/tr.ada" 2> "$d/err" \
		|| { echo "consequence: FAIL (tree does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	if [ -s "$d/tr.ada" ]; then
		cp tests/consequence/tree-driver.adb "$d/"
		cp tests/consequence/tree-cases.txt "$d/cases.txt"
		cat > "$d/run.sh" <<'EOS'
while IFS="$(printf '\t')" read -r want a b; do
	./m "$a" "$b" | cut -d: -f1
done < cases.txt
EOS
		if ada_in "$d" "gnatchop -w tr.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws tree-driver.adb -o m" > "$d/cc.txt" 2>&1; then
			ada_in "$d" "sh run.sh" > "$d/got.txt" 2> "$d/run.err"
			exec 3< "$d/got.txt"
			while IFS="$(printf '\t')" read -r want a b; do
				total=$((total + 1))
				IFS= read -r got <&3 || got=none
				[ "$got" = "$want" ] || { echo "consequence: FAIL (tree as Ada [$a] and [$b]: should be $want and is $got)"; fail=1; }
			done < tests/consequence/tree-cases.txt
			exec 3<&-
		else
			echo "consequence: FAIL (tree: the Ada does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1
		fi
	fi
	"$CLI" tests/consequence/tree.hbnf --backend=ada --layout=tape 2>&1 > /dev/null | grep -q 'has a `->` and `layout tape`' \
		|| { echo "consequence: FAIL (Ada does not refuse -> with layout tape)"; fail=1; }
	printf 'prefix none\nwhitespace none\ndoc = "a" as T -> f(T)\n' > "$W/tree-ada-fn.hbnf"
	"$CLI" "$W/tree-ada-fn.hbnf" --backend=ada 2>&1 > /dev/null | grep -q 'rule `doc` has a consequence' \
		|| { echo "consequence: FAIL (Ada does not refuse a function in a -> template, naming the rule)"; fail=1; }
	printf 'prefix none\nwhitespace none\ndoc = "a" as T -> T.attr\n' > "$W/tree-ada-fact.hbnf"
	# a fact makes it a grammar with a context, which the Ada backend refuses before it reaches the rule (hbnf_compilable.adb)
	"$CLI" "$W/tree-ada-fact.hbnf" --backend=ada > /dev/null 2> "$W/tree-ada-fact.err" \
		&& { echo "consequence: FAIL (Ada does not refuse a fact in a -> template)"; fail=1; }
	grep -q 'context' "$W/tree-ada-fact.err" \
		|| { echo "consequence: FAIL (a fact in a -> template for Ada is refused without saying why)"; fail=1; }
fi
