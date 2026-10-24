#!/bin/sh
# notation.sh — how much notation a grammar takes: the published grammar of a
# language against the same language in hbnf.
#
#   sh bench/notation.sh > bench/results/notation.md
#
# Comments and blank lines are left out of both; so are hbnf's directive lines
# (prefix, whitespace, include ...), which are not rules.  A rule is a line that
# starts a definition (`name ::=`, `name =`, `name(X) :=`); a symbol is a whitespace-separated
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
		if (kind != "bnf" && line ~ /^[A-Za-z][A-Za-z0-9_-]*(\([^)]*\))?[ \t]*(:=|=\/?|:)[ \t]*/ && line !~ /^[ \t]/) rules++
	}
	END { printf "%d %d %d %d\n", rules, lines, sym, chars }'
}

saved() { awk -v a="$1" -v b="$2" 'BEGIN { printf "**%d%%**", (a - b) * 100 / a + 0.5 }'; }

# The yacc grammars are counted by count.py: the rules between the %%, without the C
# actions, the lexer or the declarations; HyperBNF's C is counted with its token rules
# (the lexer) and without the scanners written beside them.
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
LABEL_PUB="TOML's ABNF (toml.abnf)"; DIR=corpus/toml
row "TOML 1.0" "$(count abnf corpus/toml/toml.abnf)" "$(count hbnf corpus/toml/toml.hbnf corpus/toml/toml-tokens.hbnf)"
# C: the grammar alone against each yacc grammar's rules, then the same with the token rules
# (the lexer's job, which the yacc counts leave out) added to HyperBNF's side.
CG="$(python3 -I "$here/count.py" hbnf-code corpus/c/c11.hbnf)"
CL="$(python3 -I "$here/count.py" hbnf-code corpus/c/c11.hbnf corpus/c/c-words.hbnf)"
DIR=corpus/c/c11.hbnf
LABEL_PUB="PCC's cgram.y (NetBSD trunk)"
row "C" "$(python3 -I "$here/count.py" yacc corpus/c/originals/pcc-cgram.y)" "$CG"
LABEL_PUB="32V's cgram.y (mip)"
row "" "$(python3 -I "$here/count.py" yacc corpus/c/originals/v32-cgram.y)" "$CG"
LABEL_PUB="GCC 4.0.4's c-parse.in (C part)"
row "" "$(python3 -I "$here/count.py" yacc corpus/c/originals/gcc-4.0.4-c-parse.in)" "$CG"
set -- $CL
printf '| | HyperBNF with its token rules (`corpus/c/c-words.hbnf` too) | %d | %d | %d | %d |\n' "$1" "$2" "$3" "$4"
LABEL_PUB="the YAML 1.2.2 spec's productions"; DIR=corpus/yaml
row "YAML 1.2" "$(python3 -I "$here/count.py" specbnf corpus/yaml/originals/yaml-1.2.2-productions.bnf)" "$(python3 -I "$here/count.py" hbnf-code corpus/yaml/yaml.hbnf corpus/yaml/yaml-tokens.hbnf)"
