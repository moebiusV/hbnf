#!/usr/bin/env python3
"""The oracle for corpus/mustache/mustache.hbnf: the `chevron` Mustache renderer.

  oracle.py gen N SEED DIR    write N random valid templates to DIR/g*.mustache
  oracle.py mut N SEED DIR    write N mutated templates to DIR/m*.mustache and, beside
                              each, DIR/m*.ref: 1 if chevron accepts it, else 0
  oracle.py check FILE...     print "FILE 1" or "FILE 0" for each

A template is accepted when chevron.render(template, {}) does not raise: it raises on
an unclosed tag, a section never closed, a closing tag that names another section.
Chevron also takes a tag with no name ({{#}}, {{>}}), which hbnf refuses, and raises on
{{}}, so a tag with nothing in it is refused here too; and it lets a bare {{ end the
text, where mustache.js says "Unclosed tag", so that is refused here.  Needs `pip install chevron`."""
import os, random, re, sys
import chevron

EMPTY = re.compile(r"\{\{[#^/&>]?[ \t\r\n]*\}\}")

def accepts(b):
    try:
        t = b.decode("utf-8")
    except UnicodeDecodeError:
        return False
    if EMPTY.search(t):
        return False
    k = t.rfind("{{")
    if k >= 0 and "}}" not in t[k + 2:]:
        return False        # a tag opened and never closed (chevron lets a bare {{ end the text)
    try:
        chevron.render(t, {}, warn=False)
        return True
    except Exception:
        return False

NAMES = ["a", "b", "items", "x.y", "name", "user.email", ".", "ab", "a1", "é", "k-v"]
# no text ends with a { (it would join the {{ of the tag after it: {{{ is a tag of its own)
TEXTS = ["", "hello", " ", "\n", "line one\nline two\n", "a { b", "x } y", "{ ", "}", "<li>", "é €", "\t", "{ x }", "a{b"]

def tag(r, depth):
    k = r.random()
    n = r.choice(NAMES)
    sp = lambda: r.choice(["", "", " ", "  ", "\t"])
    if k < .25:
        return "{{" + sp() + n + sp() + "}}"
    if k < .33:
        return "{{{" + sp() + n + sp() + "}}}"
    if k < .40:
        return "{{&" + sp() + n + sp() + "}}"
    if k < .48:
        return "{{!" + r.choice(["", " a comment ", " with } brace ", " x\ny "]) + "}}"
    if k < .54:
        return "{{>" + sp() + n + sp() + "}}"
    if depth > 3:
        return "{{" + n + "}}"
    mark = r.choice("#^")
    return ("{{" + mark + sp() + n + sp() + "}}" + body(r, depth + 1) + "{{/" + sp() + n + sp() + "}}")

def body(r, depth):
    return "".join(r.choice([lambda: r.choice(TEXTS), lambda: tag(r, depth)])() for _ in range(r.choice([0, 1, 2, 4])))

MUT = list("{}#^/&!>= abx.\n\t") + ["{{", "}}", "{{{", "}}}", "{{#a}}", "{{/a}}", "{{/b}}", "{{>", "{{!", "é", "{{#", "{{^"]

def mutate(r, s):
    for _ in range(r.choice([1, 1, 1, 2])):
        k = r.choice(["del", "ins", "rep", "swap", "dup", "trunc"])
        if not s:
            s = r.choice(MUT)
            continue
        i = r.randrange(len(s))
        if k == "del":
            s = s[:i] + s[i + 1:]
        elif k == "ins":
            s = s[:i] + r.choice(MUT) + s[i:]
        elif k == "rep":
            s = s[:i] + r.choice(MUT) + s[i + 1:]
        elif k == "swap" and i + 1 < len(s):
            s = s[:i] + s[i + 1] + s[i] + s[i + 2:]
        elif k == "dup":
            s = s[:i] + s[i] + s[i:]
        else:
            s = s[:i]
    return s

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "check":
        for f in sys.argv[2:]:
            print(f, 1 if accepts(open(f, "rb").read()) else 0)
        sys.exit(0)
    n, seed, d = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    r = random.Random(seed)
    os.makedirs(d, exist_ok=True)
    for i in range(n):
        s = body(r, 0) or "x"
        if mode == "gen":
            open(f"{d}/g{i:05d}.mustache", "wb").write(s.encode("utf-8"))
            continue
        m = mutate(r, s)
        while "\x00" in m:
            m = mutate(r, s)
        b = m.encode("utf-8")
        open(f"{d}/m{i:05d}.mustache", "wb").write(b)
        open(f"{d}/m{i:05d}.ref", "w").write("1" if accepts(b) else "0")
