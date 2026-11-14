#!/usr/bin/env python3
"""The tokens of preprocessed C text, one to a line: what `gcc -E -P` and the C preprocessor grammar (corpus/c/cpp.hbnf) are compared by (their
spacing differs, so spacing is not compared; two tokens that one side has glued and the other has not are different tokens, which is the point).
Read in one pass, so that a comment is a comment and a string is a string wherever they stand (`"/*"` is a string, `'"'` a character):
  - comments are dropped;
  - a line that begins with `#` (after blanks and comments) is a directive the compiler would see, `#pragma` for one, and is dropped whole,
    as a comment inside it does not end it (the grammar leaves its processed lines out, and a `#` in the middle of a line is a token);
  - a backslash before a newline is gone.
With --strings-nospace the blanks inside a string literal are dropped (for telling a difference of tokens from one of the blanks in a string).
Exit status 0.  python3 tools/cpp_tokens.py [--strings-nospace] < text"""
import re
import sys

TOK = re.compile(r'''/\*.*?\*/|//[^\n]*|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|[A-Za-z_]\w*|\.?\d(?:[eEpP][+-]|[\w.])*|\.\.\.|<<=|>>=|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||\+=|-=|\*=|/=|%=|&=|\|=|\^=|##|\n|[ \t\r\f\v]+|\S''', re.S)


def tokens(text, nospace=False):
    """the tokens of text, as a list (see above)"""
    text = re.sub(r"\\\r?\n", "", text)          # a line continuation
    out = []
    bol = True            # nothing but blanks and comments since the line began
    skip_line = False     # a directive line: what is left of it is dropped (a comment in it may run over lines, so the line ends at a newline outside any)
    for m in TOK.finditer(text):
        t = m.group(0)
        if t == "\n":
            bol = True
            skip_line = False
            continue
        if t[0] in " \t\r\f\v" or t.startswith("/*") or t.startswith("//"):
            continue                                  # white space and comments: they do not end the beginning of a line
        if skip_line:
            continue
        if bol and t == "#":
            skip_line = True
            bol = False
            continue
        bol = False
        if nospace and t[0] == '"':
            t = re.sub(r"\s+", "", t)
        out.append(t)
    return out


if __name__ == "__main__":
    nospace = "--strings-nospace" in sys.argv
    for t in tokens(sys.stdin.read(), nospace):
        print(t)
