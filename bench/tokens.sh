#!/bin/sh
# tokens.sh -- how many tokens of a language model a grammar takes: the published grammar of a
# language against the same language in HyperBNF, with two public tokenizers (OpenAI's o200k_base
# and Qwen2.5's).  Seconds long and needs no container; run it by hand, as notation.sh is.
#
#   sh bench/tokens.sh            writes bench/results/tokens.md and bench/results/vals/tokens.txt
#
# The vocabularies are fetched once into bench/cache/tokenizers and checked against the sha256
# in pins.txt; the packages that read them go into a virtual environment in bench/cache/venv.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
cache=$here/cache/tokenizers
venv=$here/cache/venv
mkdir -p "$cache/tiktoken" "$here/results/vals"

fetch() {   # fetch URL FILE SHA
	[ -f "$2" ] || curl -sfL -o "$2" "$1" || { echo "tokens.sh: could not fetch $1" >&2; exit 1; }
	echo "$3  $2" | sha256sum -c - > /dev/null || { echo "tokens.sh: $2 does not match pins.txt" >&2; exit 1; }
}
# tiktoken looks for a vocabulary under the sha1 of its URL in its cache directory
fetch "$TOK_O200K_URL" "$cache/tiktoken/$(printf '%s' "$TOK_O200K_URL" | sha1sum | cut -d' ' -f1)" "$TOK_O200K_SHA"
fetch "$TOK_QWEN_URL" "$cache/qwen-tokenizer.json" "$TOK_QWEN_SHA"

if [ ! -x "$venv/bin/python" ] || ! "$venv/bin/python" -c "
import tiktoken, tokenizers, sys
sys.exit(0 if (tiktoken.__version__, tokenizers.__version__) == ('$TOK_TIKTOKEN', '$TOK_TOKENIZERS') else 1)" 2> /dev/null
then
	python3 -m venv "$venv"
	"$venv/bin/pip" install -q "tiktoken==$TOK_TIKTOKEN" "tokenizers==$TOK_TOKENIZERS"
fi

PYTHONDONTWRITEBYTECODE=1 "$venv/bin/python" -I "$here/tokens.py" "$cache" > "$here/results/tokens.md" 2> "$here/results/vals/tokens.txt"
# bench/assemble.sh builds values.txt from vals/*.txt on a full run; keep this one's lines in it
# between full runs, so the inline figures of the documents have them.
if [ -f "$here/results/values.txt" ]; then
	grep -v '^tokens_' "$here/results/values.txt" > "$here/results/values.txt.new" || true
	cat "$here/results/vals/tokens.txt" >> "$here/results/values.txt.new"
	mv "$here/results/values.txt.new" "$here/results/values.txt"
fi
cat "$here/results/tokens.md"
