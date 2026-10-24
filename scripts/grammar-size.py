#!/usr/bin/env python3
"""Count a grammar's size so a translation can be compared with its original.

    scripts/grammar-size.py FILE [FILE...]       (by extension: .y yacc, anything else hbnf)

Prints rules, alternatives, grammar symbols (names and literals on a rule's right-hand side) and
non-blank, non-comment lines.  Code blocks ({ ... }) and comments are left out, so what is counted is
the grammar and not the actions or the scanners written beside it."""
import re, sys

def strip_hbnf(t):
    t = re.sub(r'(?m);.*$', '', t)                       # ; comments
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    out, depth, i = [], 0, 0                              # drop { ... } code blocks
    while i < len(t):
        c = t[i]
        if c in '"\'':
            j = i + 1
            while j < len(t) and t[j] != c and t[j] != '\n':
                j += 2 if t[j] == '\\' else 1
            if depth == 0: out.append(t[i:j + 1])
            i = j + 1; continue
        if c == '{': depth += 1
        elif c == '}': depth = max(0, depth - 1)
        elif depth == 0: out.append(c)
        i += 1
    return ''.join(out)

def count_yacc(path):
    y = open(path, errors='replace').read().split('%%')
    rules = strip_hbnf(re.sub(r'/\*.*?\*/', ' ', y[1] if len(y) > 1 else '', flags=re.S))
    rules = re.sub(r'(?m);\s*$', '', rules)
    names = re.findall(r'(?m)^([A-Za-z_][\w]*)\s*:', rules)
    alts = len(re.findall(r'(?m)^\s*[:|]', rules)) - 0
    body = re.sub(r'(?m)^([A-Za-z_][\w]*)\s*:', ' ', rules)
    syms = len(re.findall(r"[A-Za-z_][\w]*|'[^']'|\"[^\"]*\"", body))
    lines = [l for l in rules.split('\n') if l.strip()]
    return len(names), alts, syms, len(lines)

def count_hbnf(path):
    t = strip_hbnf(open(path, errors='replace').read())
    t = re.sub(r'(?m)^\s*(include|prefix|whitespace|language|context|dialect|%start)\b.*$', '', t)
    rules, alts, syms = 0, 0, 0
    for m in re.finditer(r'(?ms)^([A-Za-z_][\w-]*(?:\([^)]*\))?)\s*(?::=|::=|=|:)(.*?)(?=^[A-Za-z_][\w-]*(?:\([^)]*\))?\s*(?::=|::=|=|:)|\Z)', t):
        rules += 1
        body = m.group(2)
        alts += len(re.findall(r'(?<![|/])[|/](?![|/])', body))
        body2 = re.sub(r'%x[0-9A-Fa-f.\-]+', ' CP ', body)
        syms += len(re.findall(r"[A-Za-z_][\w-]*|'[^']'|\"[^\"]*\"|CP", body2))
    lines = [l for l in t.split('\n') if l.strip()]
    return rules, alts, syms, len(lines)

if __name__ == '__main__':
    print(f"{'file':44} {'rules':>6} {'alts':>5} {'symbols':>8} {'lines':>6}")
    for p in sys.argv[1:]:
        r, a, s, l = (count_yacc if p.endswith('.y') else count_hbnf)(p)
        print(f"{p:44} {r:6d} {a:5d} {s:8d} {l:6d}")
