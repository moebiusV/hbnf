#!/usr/bin/env python3
"""count.py KIND FILE... -> "rules lines symbols characters", for bench/notation.sh.

KIND is `yacc` (the rules between the first two %% of a yacc grammar, with the C actions, the
comments and the Objective-C sections of GCC's c-parse.in taken out) or `hbnf-code` (a HyperBNF
grammar with the scanners written beside it, in C, Rust, Zig and Ada, taken out).  What is left is
counted the way notation.sh counts the others: a rule is a line that starts a definition, a
symbol is a whitespace-separated word, and blank lines are not lines."""
import re, sys

def drop_blocks(t, open_c='{', close_c='}', line_comment=None):
    """Remove comments and brace blocks (code), keeping strings and character literals."""
    out, i, depth, n = [], 0, 0, len(t)
    while i < n:
        c = t[i]
        if t.startswith('/*', i):
            j = t.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if line_comment and c == line_comment and depth == 0:
            j = t.find('\n', i)
            i = n if j < 0 else j
            continue
        if c in '"\'':
            j = i + 1
            while j < n and t[j] != c and t[j] != '\n':
                j += 2 if t[j] == '\\' else 1
            if depth == 0:
                out.append(t[i:j + 1])
            i = j + 1
            continue
        if c == open_c:
            depth += 1
        elif c == close_c:
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(c)
        i += 1
    return ''.join(out)

def yacc(paths):
    t = ''.join(open(p, errors='replace').read() for p in paths)
    t = re.sub(r'(?ms)^@@ifobjc\b.*?^@@end_ifobjc\b[^\n]*\n?', '', t)
    t = re.sub(r'(?m)^@@.*$', '', t)
    parts = t.split('\n%%')
    body = parts[1] if len(parts) > 1 else t
    body = drop_blocks(body)
    return body, r'^[A-Za-z_][\w.]*[ \t]*:'

def specbnf(paths):
    """The productions of the YAML specification: `[#] name(n,c) ::= ...`, with the comments
    (`# ...`) and the production numbers' marker `[#]` left out."""
    t = ''.join(open(p, errors='replace').read() + '\n' for p in paths)
    t = re.sub(r'(?m)^\[#\] ', '', t)
    t = re.sub(r'(?m)[ \t]*#.*$', '', t)
    return t, r'^[A-Za-z][\w-]*(\([^)]*\))?[ \t]*::='

def hbnf(paths):
    t = ''.join(open(p, errors='replace').read() + '\n' for p in paths)
    t = drop_blocks(t, line_comment=';')
    t = re.sub(r'(?m)^\s*(prefix|whitespace|include|language|sensitivity|root|dialect|context|%start)\b.*$', '', t)
    return t, r'^[A-Za-z][\w-]*(\([^)]*\))?[ \t]*(:=|::=|=/?|:)'

kind, paths = sys.argv[1], sys.argv[2:]
text, rule = {'yacc': yacc, 'hbnf-code': hbnf, 'specbnf': specbnf}[kind](paths)
rules = lines = syms = chars = 0
for l in text.split('\n'):
    l = l.rstrip()
    if not l.strip():
        continue
    w = l.strip()
    lines += 1
    syms += len(w.split())
    chars += len(w)
    if re.match(rule, l):
        rules += 1
print(rules, lines, syms, chars)
