#!/usr/bin/env python3
"""parsey.py — what is in a parse.y, and how much of it hbnf replaces.

    python3 bench/parsey.py > bench/results/parsey.md

Fetches the nine OpenBSD daemons' parse.y at the commit in bench/pins.txt (cached
in bench/cache/parsey/, hashes in bench/parsey.sha256, recorded the first time and
checked after), and splits each at its two `%%` lines into the prologue, the
grammar section and the C after it.  The grammar section is split again into the
rule notation and the `{ ... }` action code.  C comments and blank lines are left
out; hbnf's side leaves out whole-line comments, blank lines and directive lines.
"""
import hashlib, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DAEMONS = [("bgpd", "usr.sbin/bgpd"), ("dhcpleased", "sbin/dhcpleased"),
           ("httpd", "usr.sbin/httpd"), ("ldpd", "usr.sbin/ldpd"),
           ("ntpd", "usr.sbin/ntpd"), ("pfctl", "sbin/pfctl"),
           ("relayd", "usr.sbin/relayd"), ("snmpd", "usr.sbin/snmpd"),
           ("unwind", "sbin/unwind")]
DIRECTIVES = {"prefix", "whitespace", "include", "language", "sensitivity",
              "root", "dialect", "statements", "conf"}


def pin(key):
    for line in open(os.path.join(HERE, "pins.txt")):
        if line.startswith(key + "="):
            return line.strip().split("=", 1)[1]
    sys.exit("bench/pins.txt has no " + key)


def fetch(name, path, commit):
    cache = os.path.join(HERE, "cache", "parsey")
    os.makedirs(cache, exist_ok=True)
    f = os.path.join(cache, name + ".y")
    if not os.path.exists(f):
        url = "https://raw.githubusercontent.com/openbsd/src/%s/%s/parse.y" % (commit, path)
        with urllib.request.urlopen(url, timeout=60) as r:
            open(f, "wb").write(r.read())
    data = open(f, "rb").read()
    h = hashlib.sha256(data).hexdigest()
    sums = os.path.join(HERE, "parsey.sha256")
    known = dict(l.split()[::-1] for l in open(sums)) if os.path.exists(sums) else {}
    if name in known and known[name] != h:
        sys.exit("%s: parse.y differs from the recorded hash" % name)
    if name not in known:
        open(sums, "a").write("%s  %s\n" % (h, name))
    return data.decode("utf-8", "replace")


def strip_c(text):
    """Remove /* */ and // comments outside string and character literals."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def lines(text):
    return sum(1 for l in text.split("\n") if l.strip())


def split_sections(text):
    L = strip_c(text).split("\n")
    idx = [i for i, l in enumerate(L) if l.startswith("%%")]
    prologue = "\n".join(L[:idx[0]])
    gram = "\n".join(L[idx[0] + 1:idx[1]])
    epilogue = "\n".join(L[idx[1] + 1:])
    notation, actions, depth, i, n = [], [], 0, 0, len(gram)
    while i < n:
        c = gram[i]
        if depth == 0 and c in "\"'":
            j = i + 1
            while j < n and gram[j] != c and gram[j] != "\n":
                j += 2 if gram[j] == "\\" else 1
            notation.append(gram[i:j + 1])
            i = j + 1
            continue
        if c == "{":
            depth += 1
            if depth == 1:
                notation.append(" ")
        if depth:
            actions.append(c)
        else:
            notation.append(c)
        if c == "}":
            depth -= 1
        i += 1
    return prologue, "".join(notation), "".join(actions), epilogue


def hbnf_lines(*files):
    n = 0
    for f in files:
        for l in open(os.path.join(ROOT, f), errors="replace"):
            s = l.strip()
            if not s or s.startswith(";"):
                continue
            if s.split()[0] in DIRECTIVES:
                continue
            n += 1
    return n


def pct(a, b):
    return "**%d%%**" % round((a - b) * 100 / a)


def main():
    commit = pin("PARSEY_COMMIT")
    rows = []
    for name, path in DAEMONS:
        pro, notation, actions, epi = split_sections(fetch(name, path, commit))
        rows.append((name, lines(pro) + lines(epi), lines(actions), lines(notation),
                     hbnf_lines("grammars/obconf_%s.hbnf" % name)))
    shared = hbnf_lines("grammars/obconf.hbnf")
    print("| daemon | `parse.y` total | lexer, keywords, C | actions | rule notation | HyperBNF grammar |")
    print("|---|---:|---:|---:|---:|---:|")
    tot = [0, 0, 0, 0]
    for name, other, act, nota, h in rows:
        print("| %s | %s | %s | %s | %s | %s |" % (name, format(other + act + nota, ","),
              format(other, ","), format(act, ","), format(nota, ","), format(h, ",")))
        for k, v in enumerate((other, act, nota, h)):
            tot[k] += v
    print("| shared `obconf.hbnf` | | | | | %s |" % format(shared, ","))
    print("| **nine daemons** | **%s** | **%s** | **%s** | **%s** | **%s** |" % (
        format(sum(tot[:3]), ","), format(tot[0], ","), format(tot[1], ","),
        format(tot[2], ","), format(tot[3] + shared, ",")))
    print()
    print("Only the rule notation is directly comparable with the HyperBNF grammar; the")
    print("lexer is replaced by hbnf's reader, and the actions only where they are bound:")
    print()
    print("| daemon | `parse.y` total | HyperBNF grammar + bound actions | saved |")
    print("|---|---:|---:|---:|")
    for name in ("ntpd", "unwind"):
        r = [x for x in rows if x[0] == name][0]
        whole = r[1] + r[2] + r[3]
        ours = r[4] + hbnf_lines("grammars/bind/%s.hbnf" % name)
        print("| %s | %s | %s + %s = %s | %s |" % (
            name, format(whole, ","), r[4], ours - r[4], format(ours, ","), pct(whole, ours)))


main()
