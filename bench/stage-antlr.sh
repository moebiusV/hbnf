#!/bin/sh
# stage-antlr.sh — the toy as an ANTLR 4 grammar (compare/Toy.g4), Java target:
# the actions-only parse cold (first parse in a fresh JVM) and warm (fourth in
# the same JVM), and the default parse tree.
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rm -f "$RESULTS"/rows/*/5[0-9]-*.md
cp "$here/compare/Toy.g4" "$here/compare/java/ToyMain.java" "$W/"
if ! (cd "$W" && java -jar /opt/antlr.jar -Dlanguage=Java Toy.g4 \
	&& javac -nowarn -cp /opt/antlr.jar *.java) > "$W/build.err" 2>&1; then
	for n in $N_LIST; do add_skip "$n" 50 "ANTLR 4" "build failed: $(tail -c 160 "$W/build.err" | tr '\n' ' ')"; done
	exit 0
fi
HEAP=${ANTLR_HEAP:-8g}
run_one() {   # run_one ORDER LABEL MODE N
	order=$1; label=$2; mode=$3; n=$4
	bytes=$(wc -c < "$IN/toy-$n.txt")
	if got=$(best_of "$RUNS" java -Xmx$HEAP -cp "/opt/antlr.jar:$W" ToyMain "$mode" "$IN/toy-$n.txt"); then
		add_row "$n" "$order" "$label" "$bytes" "$got"
	else
		why=$(java -Xmx$HEAP -cp "/opt/antlr.jar:$W" ToyMain "$mode" "$IN/toy-$n.txt" 2>&1 | tail -1 | cut -c1-100)
		add_skip "$n" "$order" "$label" "did not finish with a ${HEAP} heap: ${why}"
	fi
}
for n in $N_LIST; do
	run_one 50 "ANTLR 4 (Java), actions, cold JVM" cold "$n"
	run_one 51 "ANTLR 4 (Java), actions, warm JVM" warm "$n"
	run_one 52 "ANTLR 4 (Java), parse tree, cold JVM" tree "$n"
done
