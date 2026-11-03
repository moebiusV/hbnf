#!/usr/bin/env python3
"""Rewrite the old spellings of hbnf's own notation to the new ones.

    %x41  %x41-5A  %x0D.0A  %d65  %b1000001  %i"abc"  %s"abc"
becomes
    0x41  0x41..0x5A  0x0D 0x0A  65  0b1000001  i"abc"  s"abc"

hbnf's own notation is a file with no `dialect` line, or `dialect hbnf`.  A file
that says `dialect abnf`, `ebnf`, `bnf` or `ybnf` is another notation's and is
left as it is, as are comments, strings, `{ code }` blocks and the expressions
in parentheses of a rule (`?(cond)`, `name(args)`, `%spaces(k)`).  In a rule of
bit fields (`len:8`, `data:[n]`, `?(cond)`), where `0x05` is a constant as wide
as its digits, the `%` forms are still read, and stay.

    tools/hbnf_modernize.py [--check] [PATH ...]

PATH is a file or a directory; none means the repository's corpus, grammars,
tests, bindings and tutorial.  A directory is searched for `*.hbnf`, skipping
those that start with `_`.  --check changes nothing, lists the files that need
work and exits 1 if there are any.  Running it again changes nothing.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIRS = ["corpus", "grammars", "tests", "bindings", "tutorial", "layouts", "bench"]
OTHER_DIALECTS = {"abnf", "ebnf", "bnf", "ybnf"}

PATTERN = re.compile(
    r"%(?P<base>[xXdDbBoOuU])(?P<digits>[0-9A-Fa-f]+(?:[-.][0-9A-Fa-f]+)*)(?![A-Za-z0-9_])"
    r"|%(?P<case>[iIsS])[ \t]*(?![A-Za-z0-9_])")
# A repetition count written apart from what it repeats (`1*3 ( x )`, `2 "x"`): in hbnf's own notation a decimal
# number is a code point unless it is against the element after it.
SPACED = re.compile(r"(?<![A-Za-z0-9_.@:#%-])(\d+)([ \t]+)(?=[A-Za-z_(\"'<~\[%!&])")
CHAR = re.compile(r"'(?:\\[0-7]{1,3}|\\x[0-9A-Fa-f]+|\\.|[^\\'\n])'")
NAME_END = re.compile(r"[A-Za-z0-9_-]*$")


def dialect_of(text):
    for line in text.split("\n"):
        m = re.match(r"\s*dialect\s+([A-Za-z]+)", line)
        if m:
            return m.group(1)
    return "hbnf"


def tokens(text):
    """Split the text into (kind, string): code, comment, string, char, block,
    raw, and an empty `rule` marker where a rule starts (a line in column 1
    outside brackets)."""
    out = []
    i, n = 0, len(text)
    buf = []
    depth = 0
    newline = True          # at the start of a line, nothing but blanks since

    def flush():
        if buf:
            out.append(("code", "".join(buf)))
            buf.clear()

    def balanced(j, open_c, close_c):
        """Index just past the bracket that closes the one at j, quotes skipped."""
        d = 0
        while j < n:
            c = text[j]
            if c == '"':
                j += 1
                while j < n and text[j] != '"' and text[j] != "\n":
                    j += 2 if text[j] == "\\" else 1
            elif c == open_c:
                d += 1
            elif c == close_c:
                d -= 1
                if d == 0:
                    return j + 1
            j += 1
        return n

    def glued_to_name(j):
        return bool(re.search(r"[A-Za-z_][A-Za-z0-9_-]*$", text[max(0, j - 80):j]))

    while i < n:
        c = text[i]
        if newline and i == 0 or (newline and depth == 0 and c not in " \t|/\r\n;"):
            flush()
            out.append(("rule", ""))
        if c not in " \t\r\n;":
            newline = False
        if c == "\n":
            newline = True
            buf.append(c)
            i += 1
        elif c == ";":
            flush()
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(("comment", text[i:j]))
            i = j
        elif text.startswith("/*", i) or (text.startswith("(*", i) and i + 2 < n and text[i + 2] in " \t\n\r"):
            flush()
            close = "*/" if c == "/" else "*)"
            j = text.find(close, i + 2)
            j = n if j < 0 else j + 2
            out.append(("comment", text[i:j]))
            i = j
        elif c == '"':
            flush()
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(("string", text[i:j]))
            i = j
        elif c == "'" and CHAR.match(text, i):
            flush()
            m = CHAR.match(text, i)
            out.append(("char", m.group(0)))
            i = m.end()
        elif c == "{":
            flush()
            d, j = 0, i
            while j < n:
                e = text[j]
                if e == '"':
                    j += 1
                    while j < n and text[j] != '"':
                        j += 2 if text[j] == "\\" else 1
                elif e == "'":
                    m = CHAR.match(text, j)
                    if m:
                        j = m.end() - 1
                elif text.startswith("//", j):
                    while j < n and text[j] != "\n":
                        j += 1
                    continue
                elif text.startswith("/*", j):
                    k = text.find("*/", j + 2)
                    j = n if k < 0 else k + 1
                elif e == "{":
                    d += 1
                elif e == "}":
                    d -= 1
                    if d == 0:
                        j += 1
                        break
                j += 1
            out.append(("block", text[i:j]))
            for ch in text[i:j]:
                if ch == "\n":
                    newline = True
            i = j
        elif c == "<" and re.match(r"<[^<>\n]*>", text[i:]):
            m = re.match(r"<[^<>\n]*>", text[i:])
            flush()
            out.append(("raw", m.group(0)))
            i += m.end()
        elif c == "(" and glued_to_name(i):
            # name(args), a parameterised rule's head or a use of one
            flush()
            j = balanced(i, "(", ")")
            out.append(("raw", text[i:j]))
            i = j
        elif c == "?" and text.startswith("?(", i):
            flush()
            j = balanced(i + 1, "(", ")")
            out.append(("raw", text[i:j]))
            i = j
        elif c == ":" and i + 1 < n and text[i + 1] in "[(" and glued_to_name(i):
            buf.append(c)
            flush()
            o = text[i + 1]
            j = balanced(i + 1, o, "]" if o == "[" else ")")
            out.append(("raw", text[i + 1:j]))
            i = j
        else:
            if c in "([":
                depth += 1
            elif c in ")]":
                depth = max(0, depth - 1)
            buf.append(c)
            i += 1
    flush()
    return out


def rules_of(toks):
    """The tokens of each rule, as lists of indexes."""
    result = []
    for k, (kind, _) in enumerate(toks):
        if kind == "rule":
            result.append([])
        elif result:
            result[-1].append(k)
        else:
            result.append([k])
    return result


def convert_numeric(base, digits, before, after):
    """The new spelling of a numeric terminal, with the spacing it needs."""
    base = base.lower()
    parts = re.split(r"([-.])", digits)
    values, seps = parts[0::2], parts[1::2]
    radix = {"x": 16, "u": 16, "b": 2, "d": 10, "o": 8}[base]

    def one(d):
        if base in "xu":
            return "0x" + d
        if base == "b":
            return "0b" + d
        if base == "d":
            return str(int(d))
        return "0x%02X" % int(d, 8)

    try:
        if "-" in seps and "." in seps:
            return None
        if "-" in seps:
            if len(values) != 2:
                return None
            lo, hi = values
            if int(lo, radix) > int(hi, radix):
                lo, hi = hi, lo
            text, multi = one(lo) + ".." + one(hi), False
        elif seps:
            text, multi = " ".join(one(v) for v in values), True
        else:
            text, multi = one(values[0]), False
    except ValueError:
        return None
    run = NAME_END.search(before).group(0)
    if run and run.isdigit():
        text = "(" + text + ")"             # 3%x41: a count, so a group
    elif multi and before.endswith("*"):
        text = "(" + text + ")"
    elif run:
        text = " " + text
    if after and after[0] not in " \t\r\n|)]/":
        text += " "
    return text


def codes_of(toks, rules, k):
    """The code of the rule that token k is in."""
    for r in rules:
        if k in r:
            return "".join(toks[j][1] for j in r if toks[j][0] == "code")
    return ""


def glue_counts(s, nxt):
    """Close the space between a repetition count and what it repeats; nxt is
    the first character of the token after s, which can be what is repeated."""
    text = s + nxt
    pieces, pos = [], 0
    for m in SPACED.finditer(text):
        if m.start() >= len(s):
            continue
        if re.search(r"%[A-Za-z]+[ \t]+$", text[:m.start()]):
            continue                         # %spaces 4: the number is the operand
        pieces.append(text[pos:m.end(1)])
        pos = m.end(2)
    pieces.append(text[pos:])
    result = "".join(pieces)
    return result[:len(result) - len(nxt)]


def rewrite(text):
    toks = tokens(text)
    rules = rules_of(toks)
    codes = {}
    for r in rules:
        codes[tuple(r)] = "".join(toks[k][1] for k in r if toks[k][0] == "code")
    # the names of fields and of their value sets (`ethertype:16`, `p:proto`)
    names = set()
    for code in codes.values():
        names.update(re.findall(r"([A-Za-z_][\w-]*):[^\s=:]", code))
        names.update(re.findall(r":([A-Za-z_][\w-]*)", code))
    skip = set()
    for r in rules:
        code = codes[tuple(r)]
        head = re.match(r"\s*([A-Za-z_][\w-]*)", code)
        guard = any(toks[k][0] == "raw" and toks[k][1].startswith("?(") for k in r)
        if (re.search(r"[A-Za-z0-9_\]\)]:[^\s=:]", code) or guard
                or (head and head.group(1) in names)):
            skip.update(r)
    out = []
    tail = ""
    for k, (kind, s) in enumerate(toks):
        if kind == "code" and k not in skip and "::=" not in codes_of(toks, rules, k):
            s = glue_counts(s, toks[k + 1][1][:1] if k + 1 < len(toks) else "")
        if kind == "code" and k not in skip and "%" in s:
            pieces, pos = [], 0
            nxt = toks[k + 1][1][:1] if k + 1 < len(toks) else ""
            for m in PATTERN.finditer(s):
                pieces.append(s[pos:m.start()])
                before = (tail + "".join(pieces))[-24:]
                after = s[m.end():] or nxt
                if m.group("case"):
                    # %i"abc": the string is the next token
                    new = m.group("case").lower() if (m.end() == len(s) and nxt == '"') else m.group(0)
                else:
                    new = convert_numeric(m.group("base"), m.group("digits"), before, after)
                    if new is None:
                        new = m.group(0)
                pieces.append(new)
                pos = m.end()
            pieces.append(s[pos:])
            s = "".join(pieces)
        out.append(s)
        tail = (tail + s)[-24:]
    result = "".join(out)
    return result, result != text


def files_under(path):
    if os.path.isfile(path):
        yield path
        return
    for d, dirs, files in os.walk(path):
        dirs[:] = sorted(x for x in dirs if not x.startswith("_") and x != ".git")
        for f in sorted(files):
            if f.endswith(".hbnf") and not f.startswith("_"):
                yield os.path.join(d, f)


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        paths = [os.path.join(ROOT, d) for d in DEFAULT_DIRS]
        paths += [os.path.join(ROOT, f) for f in sorted(os.listdir(ROOT)) if f.endswith(".hbnf")]
    todo = []
    for p in paths:
        for f in files_under(p):
            with open(f, encoding="utf-8") as fh:
                text = fh.read()
            if dialect_of(text) in OTHER_DIALECTS:
                continue
            out, changed = rewrite(text)
            if changed:
                todo.append(f)
                if not check:
                    with open(f, "w", encoding="utf-8") as fh:
                        fh.write(out)
    for f in todo:
        print(("needs work: " if check else "rewrote: ") + os.path.relpath(f, ROOT))
    return 1 if (check and todo) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
