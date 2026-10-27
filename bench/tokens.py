#!/usr/bin/env python3
"""tokens.py CACHE_DIR: how many tokens of a language model a grammar takes, the published
grammar of a language against the same language in HyperBNF.

The pairs and the text are those of bench/notation.sh: comments, blank lines and HyperBNF's
directive lines left out of both, each line stripped of its blanks.  The text is counted with
two public tokenizers, OpenAI's o200k_base and the Qwen2.5 tokenizer.  Claude's tokenizer is not
public, so no count is made with it.

Writes the markdown table on stdout and the figures bench/update-docs.sh quotes on stderr as
NAME=VALUE lines.  Each pair's character count is checked against bench/results/notation.md, so
the text counted here is the text that table counts."""
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
sys.path.insert(0, here)
import count  # noqa: E402  (bench/count.py: the yacc, specbnf and hbnf-code readers)

cache = sys.argv[1]
os.environ["TIKTOKEN_CACHE_DIR"] = os.path.join(cache, "tiktoken")
import tiktoken  # noqa: E402
from tokenizers import Tokenizer  # noqa: E402

o200k = tiktoken.get_encoding("o200k_base")
qwen = Tokenizer.from_file(os.path.join(cache, "qwen-tokenizer.json"))


def n_o200k(text):
    return len(o200k.encode(text, disallowed_special=()))


def n_qwen(text):
    return len(qwen.encode(text, add_special_tokens=False).ids)


def awk_lines(kind, paths):
    """The lines notation.sh's count() keeps for `bnf`, `abnf` and `hbnf`, as it keeps them."""
    def strip(s):
        out, quoted = [], False
        for c in s:
            if c == '"':
                quoted = not quoted
            if c == ";" and not quoted and kind != "bnf":
                break
            out.append(c)
        return "".join(out)

    raw = []
    for p in paths:
        raw += open(p, errors="replace").read().split("\n")
    if raw and raw[-1] == "":
        raw.pop()
    kept = []
    for nr, l in enumerate(raw, 1):
        line = l if kind == "bnf" else strip(l)
        line = re.sub(r"[ \t\r]+$", "", line)
        if re.match(r"^[ \t]*$", line):
            continue
        if kind == "bnf" and "::=" not in line and nr <= 2:
            continue
        w = re.sub(r"^[ \t]+", "", line)
        first = re.split(r"[ \t]+", w)[0]
        if kind == "hbnf" and re.match(r"^(prefix|whitespace|include|language|sensitivity|root|dialect)$", first):
            continue
        kept.append(w)
    return kept


def py_lines(kind, paths):
    return [w for w, _ in count.counted_lines(kind, [os.path.join(root, p) for p in paths])]


def text_of(reader, kind, paths):
    paths = [os.path.join(root, p) for p in paths] if reader == "awk" else paths
    lines = awk_lines(kind, paths) if reader == "awk" else py_lines(kind, paths)
    return "\n".join(lines) + "\n", lines


C79_G = ["corpus/c/c79.hbnf"]
C79_L = ["corpus/c/c79.hbnf", "corpus/c/c79-words.hbnf"]
C99_G = ["corpus/c/c99.hbnf"]
C99_L = ["corpus/c/c99.hbnf", "corpus/c/c99-words.hbnf"]
# language, notation label, reader, kind, files
ROWS = [
    ("ALGOL 60", "the Report's BNF", "awk", "bnf", ["corpus/algol60/syntax.txt"]),
    ("", "HyperBNF", "awk", "hbnf", ["corpus/algol60/algol60.hbnf"]),
    ("JSON", "RFC 8259's ABNF", "awk", "abnf", ["corpus/json/rfc8259.abnf"]),
    ("", "HyperBNF", "awk", "hbnf", ["corpus/json/json.hbnf", "corpus/json/json-tokens.hbnf"]),
    ("TOML 1.0", "TOML's ABNF", "awk", "abnf", ["corpus/toml/toml.abnf"]),
    ("", "HyperBNF", "awk", "hbnf", ["corpus/toml/toml.hbnf", "corpus/toml/toml-tokens.hbnf"]),
    ("C", "32V's cgram.y, 1979", "py", "yacc", ["corpus/c/originals/v32-cgram.y"]),
    ("", "HyperBNF", "py", "hbnf-code", C79_G),
    ("", "HyperBNF with its token rules", "py", "hbnf-code", C79_L),
    ("", "PCC's cgram.y, C99", "py", "yacc", ["corpus/c/originals/pcc-cgram.y"]),
    ("", "HyperBNF", "py", "hbnf-code", C99_G),
    ("", "GCC 4.0.4's c-parse.in, C99", "py", "yacc", ["corpus/c/originals/gcc-4.0.4-c-parse.in"]),
    ("", "HyperBNF", "py", "hbnf-code", C99_G),
    ("", "HyperBNF with its token rules", "py", "hbnf-code", C99_L),
    ("YAML 1.2", "the spec's productions", "py", "specbnf", ["corpus/yaml/originals/yaml-1.2.2-productions.bnf"]),
    ("", "HyperBNF", "py", "hbnf-code", ["corpus/yaml/yaml.hbnf", "corpus/yaml/yaml-tokens.hbnf"]),
]

# the characters column of notation.md, row by row (the "saved" rows are left out)
chars_in_table = []
for l in open(os.path.join(here, "results", "notation.md")):
    cells = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(cells) == 6 and cells[5].isdigit():
        chars_in_table.append(int(cells[5]))
if len(chars_in_table) != len(ROWS):
    sys.exit("tokens.py: notation.md has %d rows of figures, this has %d" % (len(chars_in_table), len(ROWS)))

counted = []
for (lang, label, reader, kind, files), want in zip(ROWS, chars_in_table):
    text, lines = text_of(reader, kind, files)
    got = sum(len(w) for w in lines)
    if got != want:
        sys.exit("tokens.py: %s (%s) has %d characters here and %d in notation.md" % (lang or label, label, got, want))
    counted.append((lang, label, got, n_o200k(text), n_qwen(text)))


def saved(a, b):
    return "**%d%%**" % ((a - b) * 100 / a + 0.5)


print("| language | notation | characters | o200k_base tokens | Qwen2.5 tokens |")
print("|---|---|---:|---:|---:|")
vals = {}
i = 0
names = {"ALGOL 60": "algol60", "JSON": "json", "TOML 1.0": "toml", "C": "c", "YAML 1.2": "yaml"}
lang_now = ""
while i < len(counted):
    lang, label, ch, a, b = counted[i]
    if lang:
        lang_now = lang
    if label == "HyperBNF with its token rules":
        print("| | %s | %d | %d | %d |" % (label, ch, a, b))
        i += 1
        continue
    pair = counted[i + 1]
    ph, oh, qh = pair[2], pair[3], pair[4]
    print("| %s | %s | %d | %d | %d |" % (lang, label, ch, a, b))
    print("| | HyperBNF | %d | %d | %d |" % (ph, oh, qh))
    print("| | **saved** | %s | %s | %s |" % (saved(ch, ph), saved(a, oh), saved(b, qh)))
    key = names[lang_now] + ("_" + re.sub(r"[^a-z0-9]+", "", label.lower())[:4] if lang_now == "C" else "")
    vals["tokens_%s_o200k_saved" % key] = int((a - oh) * 100 / a + 0.5)
    vals["tokens_%s_qwen_saved" % key] = int((b - qh) * 100 / b + 0.5)
    i += 2
print()
print("_The text is the grammar as `notation.sh` counts it.  o200k_base is OpenAI's tokenizer "
      "(tiktoken %s) and Qwen2.5's is an open-weights model's (tokenizers %s); Claude's tokenizer "
      "is not public, so its count was not measured._" % (tiktoken.__version__, __import__("tokenizers").__version__))
for k, v in vals.items():
    print("%s=%s" % (k, v), file=sys.stderr)
