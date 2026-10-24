#!/bin/sh
# notation.sh — how much notation a grammar takes: the published grammar of a
# language against the same language in hbnf.
#
#   sh bench/notation.sh > bench/results/notation.md
#
# Comments and blank lines are left out of both; so are hbnf's directive lines
# (prefix, whitespace, include ...), which are not rules.  A rule is a line that
# starts a definition (`name ::=`, `name =`); a symbol is a whitespace-separated
# word, which is what a reader (or a language model) pays for.
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root" || exit 1

# count KIND FILE...: "rules lines symbols characters"
count() {
	kind=$1; shift
	cat "$@" | awk -v kind="$kind" '
	function strip(s,   i, c, q, r) {
		r = ""; q = 0
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\"") q = !q
			if (c == ";" && !q && kind != "bnf") break
			r = r c
		}
		return r
	}
	BEGIN { skip = 0 }
	{
		line = kind == "bnf" ? $0 : strip($0)
		gsub(/[ \t\r]+$/, "", line)
		if (line ~ /^[ \t]*$/) next
		if (kind == "bnf" && line !~ /::=/ && NR <= 2) next
		w = line; sub(/^[ \t]+/, "", w); split(w, a, /[ \t]+/)
		if (kind == "hbnf" && a[1] ~ /^(prefix|whitespace|include|language|sensitivity|root|dialect)$/) next
		lines++
		n = split(w, tok, /[ \t]+/); sym += n
		chars += length(w)
		if (kind == "bnf" && line ~ /::=/) rules++
		if (kind != "bnf" && line ~ /^[A-Za-z][A-Za-z0-9_-]*[ \t]*(=\/?|:)[ \t]*/ && line !~ /^[ \t]/) rules++
	}
	END { printf "%d %d %d %d\n", rules, lines, sym, chars }'
}

saved() { awk -v a="$1" -v b="$2" 'BEGIN { printf "**%d%%**", (a - b) * 100 / a + 0.5 }'; }

row() {
	name=$1; pub=$2; ours=$3
	set -- $pub; pr=$1 pl=$2 ps=$3 pc=$4
	set -- $ours; hr=$1 hl=$2 hs=$3 hc=$4
	printf '| %s | %s | %d | %d | %d | %d |\n' "$name" "$LABEL_PUB" "$pr" "$pl" "$ps" "$pc"
	printf '| | HyperBNF (`%s`) | %d | %d | %d | %d |\n' "$DIR" "$hr" "$hl" "$hs" "$hc"
	printf '| | **saved** | %s | %s | %s | %s |\n' \
		"$(saved "$pr" "$hr")" "$(saved "$pl" "$hl")" "$(saved "$ps" "$hs")" "$(saved "$pc" "$hc")"
}

echo "| language | notation | rules | lines | symbols | characters |"
echo "|---|---|---:|---:|---:|---:|"
LABEL_PUB="the Report's BNF"; DIR=corpus/algol60
row "ALGOL 60" "$(count bnf corpus/algol60/syntax.txt)" "$(count hbnf corpus/algol60/algol60.hbnf)"
LABEL_PUB="RFC 8259's ABNF"; DIR=corpus/json
row "JSON" "$(count abnf corpus/json/rfc8259.abnf)" "$(count hbnf corpus/json/json.hbnf corpus/json/json-tokens.hbnf)"
