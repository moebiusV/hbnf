#!/usr/bin/env python3
"""The tokens of preprocessed C text, one to a line: what `gcc -E -P` and the C preprocessor grammar (corpus/c/cpp.hbnf) are
compared by (their spacing differs).  Lines that begin with `#` (with their continuations) are dropped: the grammar leaves its
`#define` lines in the text, which the C grammars read as white space.  Comments are dropped."""
import re
import sys

text = sys.stdin.read()
text = re.sub(r"\\\r?\n", "", text)          # a line continuation
out = []
for line in text.split("\n"):
    if line.lstrip().startswith("#"):
        continue
    out.append(line)
text = "\n".join(out)
text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
text = re.sub(r"//[^\n]*", " ", text)
tok = re.compile(r'''"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|[A-Za-z_]\w*|\.?\d(?:[eEpP][+-]|[\w.])*|\.\.\.|<<=|>>=|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||\+=|-=|\*=|/=|%=|&=|\|=|\^=|##|\S''')
for m in tok.finditer(text):
    print(m.group(0))
