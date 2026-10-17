#!/usr/bin/env python3
"""imp72_to_hbnf.py -- read IMP72's syntax statements as an hbnf grammar.

    python3 tools/imp72_to_hbnf.py imp72-corpus/tape/syntax.imc [more.imc ...] > imp72.hbnf

IMP72 defines its language in statements of the form

    <CLASS> ::= element element <CLASS,name> 'c' ... ::= semantics ;

(the manual's section 2.3.2).  This keeps the syntax part, the left of the
second `::=`, and drops the semantics: a measurement of what the grammar alone
is, and what hbnf makes of it.  It is a stand-in for a `dialect imp72` reader
in hbnf itself, and says so: the rules it writes are the productions as they
stand, one alternative each, in order, joined with `/` (a union) so that hbnf's
own analysis reports every place two alternatives cannot be told apart.

Rules of the notation, from the manual and the sources:
  - `#` starts a comment, to the next `#`.  A literal `#` is written '#'.
  - `<NAME>` or `<CLASS,name>` is a syntactic class.  A bare `<x>` is the class
    EXP named x, or ATOM when it is the first thing (manual 2.3.2, item 4);
    unless x is a class the files define, in which case it is that class.
  - an identifier, or a symbol, stands for itself; `'c'` is the one character c.
    `=>` and `//` are single symbols.  A `"` is a symbol until the `::=` that begins the semantics.
  - after the `::=` that follows the syntax part, everything up to `;` (outside quotes and brackets) is
    semantics.  `%%` ends the part the kernel reads; the file goes on.
  - `<NAM>` and `<SYM>` are the lexer's own classes, not productions.
"""
import re
import sys

NT = re.compile(r"<([A-Za-z0-9]+)(?:,([A-Za-z0-9]+))?>")
WORD = re.compile(r"[A-Za-z0-9]+")


def skip(text, i):
    n = len(text)
    while i < n:
        if text[i] in " \t\r\n":
            i += 1
        elif text[i] == "#":
            j = text.find("#", i + 1)
            i = n if j < 0 else j + 1
        else:
            break
    return i


def statements(text):
    """Yield (class, [elements], has_semantics) for each syntax statement."""
    i, n = 0, len(text)
    while True:
        i = skip(text, i)
        while i < n and text[i] == "%":
            i = skip(text, i + 1)
        if i >= n:
            return
        m = NT.match(text, i)
        # A statement is `<CLASS> ::= ...`; anything else (declarations in
        # IMP, stray text) is read to its `;` and ignored.
        head = m.group(1) if m and text.startswith("::=", skip(text, m.end())) else None
        elems, seps, sem = [], 0, False
        if head:
            i = skip(text, m.end()) + 3
        depth = 0
        while i < n:
            i = skip(text, i)
            if i >= n:
                break
            c = text[i]
            if c == ";" and depth == 0:
                i += 1
                break
            if c == "%" and seps >= 1 and depth == 0:
                # `%%` ends the part of the file the kernel (rsyn) reads on its
                # own; the compiler reads on from there.
                while i < n and text[i] == "%":
                    i += 1
                break
            if text.startswith("::=", i):
                seps += 1
                i += 3
                continue
            if c == "'" and i + 2 < n and text[i + 2] == "'":
                if seps < 1:
                    elems.append(("t", text[i + 1]))
                i += 3
                continue
            if c == '"':
                if seps >= 1:                       # quoted semantics
                    j = text.find('"', i + 1)
                    i = n if j < 0 else j + 1
                    sem = True
                else:
                    elems.append(("t", '"'))
                    i += 1
                continue
            if seps >= 1:
                sem = True
                if c in "([":
                    depth += 1
                elif c in ")]":
                    depth -= 1
                i += 1
                continue
            m2 = NT.match(text, i)
            if m2:
                elems.append(("nt", m2.group(1), m2.group(2)))
                i = m2.end()
                continue
            w = WORD.match(text, i)
            if w:
                elems.append(("t", w.group(0)))
                i = w.end()
                continue
            if text.startswith("=>", i) or text.startswith("//", i):
                elems.append(("t", text[i:i + 2]))
                i += 2
                continue
            elems.append(("t", c))
            i += 1
        if head:
            yield head, elems, sem


def lit(s):
    """An hbnf literal for the terminal s."""
    if s.isalnum():
        return '"%s"' % s
    return " ".join("%%x%02X" % ord(c) for c in s) if any(c in '"\\' for c in s) else '"%s"' % s


def rulename(c):
    return c.lower()


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    prods = []                      # (class, elements, has_semantics)
    for path in argv[1:]:
        with open(path, errors="replace") as f:
            prods += list(statements(f.read().replace("\r", "")))
    classes = []
    for c, _, _ in prods:
        if c not in classes:
            classes.append(c)
    defined = set(classes) | {"NAM", "SYM"}

    out = []
    out.append("; imp72.hbnf -- IMP72's syntax statements, read as a grammar.")
    out.append("; Generated by tools/imp72_to_hbnf.py from " + ", ".join(
        p.split("/")[-1] for p in argv[1:]) + "; the semantic parts are dropped.")
    out.append("; Classes are lower case; <NAM> and <SYM> are the lexer's own.")
    out.append("")
    out.append("prefix none")
    out.append("whitespace ws")
    out.append("")
    by = {}
    for c, e, s in prods:
        if c in ("NAM", "SYM"):
            continue
        by.setdefault(c, []).append(e)
    nalt = 0
    for c in classes:
        if c in ("NAM", "SYM"):
            continue
        alts = []
        for e in by[c]:
            parts = []
            for k, el in enumerate(e):
                if el[0] == "t":
                    parts.append(lit(el[1]))
                else:
                    name, arg = el[1], el[2]
                    if arg is None and name not in defined:
                        name = "ATOM" if k == 0 else "EXP"
                    parts.append(rulename(name))
            alts.append(" ".join(parts) if parts else '""')
            nalt += 1
        out.append("%s = %s" % (rulename(c), "\n    / ".join(alts)))
        out.append("")
    out.append("; The lexer's classes: a name is a letter or digit run (numbers are names),")
    out.append("; a symbol is any other printing character.")
    out.append("nam = 1*( %x41-5A / %x61-7A / %x30-39 )")
    out.append("sym = %x21-2F / %x3A-40 / %x5B-60 / %x7B-7E")
    out.append("")
    out.append("; Blanks and `#` comments.")
    out.append("ws = 1*( %x20 / %x09 / %x0D / %x0A / comment )")
    out.append('comment = "#" *~"#" "#"')
    sys.stdout.write("\n".join(out) + "\n")
    sys.stderr.write("%d statements, %d classes (%d lexical), %d alternatives\n" % (
        len(prods), len(by), len(defined) - len(by), nalt))


if __name__ == "__main__":
    main(sys.argv)
