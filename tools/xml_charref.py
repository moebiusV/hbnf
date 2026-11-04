#!/usr/bin/env python3
"""Writes the regular expression of corpus/xml/xml.hbnf's `charnum`: the rest of a character reference whose
number is a legal XML `Char` (#x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]), from the
`#` to the `;`, in decimal or in hexadecimal (`#x...;`, a lowercase x), with leading zeros allowed.

  python3 tools/xml_charref.py          print the rule `charnum = r"..."`
  python3 tools/xml_charref.py --check  also test it against every number from 0 to 0x110010 in both bases (with
                                        and without leading zeros, hex in both cases) and against the texts that
                                        are not numbers, under the reading hbnf gives a regular expression:
                                        alternatives in order, a repetition or a group that matched is not given back

The expression is a deterministic automaton written out: after each digit the next digit's class says which way
to go (no two alternatives of a group begin with the same character), and a `;` ends the number, so the
parser reads it with no backtracking and the generator can prove it (it warns of a rule whose alternatives can
begin at the same byte).  The states are the residual sets of legal numbers after a prefix; equal ones are
one state, which is why `[0-9]{4};` and the like come out short."""
import re, sys

LEGAL = [(0x9, 0xA), (0xD, 0xD), (0x20, 0xD7FF), (0xE000, 0xFFFD), (0x10000, 0x10FFFF)]


def clip(intervals, lo, hi):
    return tuple((max(a, lo), min(b, hi)) for a, b in intervals if max(a, lo) <= min(b, hi))


def automaton(base, ndigits):
    """states: signature -> (accepting, {digit: signature})  where signature[m] are the intervals of the numbers
    x < base**m that complete the prefix with m more digits"""
    top = max(b for _, b in LEGAL)
    start = tuple(clip(LEGAL, 0, base ** m - 1) for m in range(ndigits + 1))
    states = {}

    def build(sig):
        if sig in states:
            return
        accepting = bool(sig[0])
        trans = {}
        for d in range(base):
            child = []
            for m in range(1, len(sig)):
                lo = d * base ** (m - 1)
                hi = lo + base ** (m - 1) - 1
                child.append(tuple((a - lo, b - lo) for a, b in clip(sig[m], lo, hi)))
            child = tuple(child)
            # child[m-1] is for m-1 remaining digits; pad to the full length with nothing
            child = child + ((),)
            if any(child):
                trans[d] = child
        states[sig] = (accepting, trans)
        for c in trans.values():
            build(c)
    build(start)
    return start, states


def digit_class(digits, base):
    dig = "0123456789abcdef"
    ds = sorted(digits)
    runs, i = [], 0
    while i < len(ds):
        j = i
        while j + 1 < len(ds) and ds[j + 1] == ds[j] + 1:
            j += 1
        runs.append((ds[i], ds[j]))
        i = j + 1
    out = ""
    for a, b in runs:                       # decimal digits, then the letters in both cases
        if a < 10:
            hi = min(b, 9)
            out += dig[a] + ("-" + dig[hi] if hi > a else "")
    for a, b in runs:
        if b >= 10:
            lo = max(a, 10)
            out += dig[lo] + ("-" + dig[b] if b > lo else "") + dig[lo].upper() + ("-" + dig[b].upper() if b > lo else "")
    return out if len(out) == 1 else "[" + out + "]"


def free_tail(sig, base):
    """(lo, hi) if the numbers that complete the prefix are all digit strings of lo to hi digits, else None"""
    ks = [k for k, iv in enumerate(sig) if iv]
    if not ks or any(sig[k] != ((0, base ** k - 1),) for k in ks) or ks != list(range(ks[0], ks[-1] + 1)):
        return None
    return ks[0], ks[-1]


def expression(start, states, base):
    """the language of a state as a regular expression, without the `;` that ends the number: a state that
    accepts the number so far makes its continuation optional"""
    memo = {}
    any_digit = digit_class(range(base), base)

    def regex(sig):
        if sig in memo:
            return memo[sig]
        accepting, trans = states[sig]
        t = free_tail(sig, base)
        if t:
            lo, hi = t
            r = any_digit + ("" if lo == hi == 1 else "{%d}" % lo if lo == hi else "{%d,%d}" % (lo, hi)) if hi > 0 else ""
            memo[sig] = r
            return r
        groups = {}
        for d, c in trans.items():
            if sig == start and d == 0:
                continue                    # the zeros before the number are `0*`
            groups.setdefault(c, []).append(d)
        alts = [digit_class(ds, base) + regex(c) for c, ds in groups.items()]
        r = alts[0] if len(alts) == 1 else "(" + "|".join(alts) + ")"
        if accepting:
            r = "(" + r + ")?" if not r.startswith("(") or len(alts) == 1 else r + "?"
        memo[sig] = r
        return r
    return regex(start)


def runs(r):
    # [0-9][0-9][0-9] -> [0-9]{3}
    return re.sub(r"(\[[^\]]+\]|\d|[a-fA-F])\1+(?![{0-9])", lambda m: m.group(1) + "{%d}" % (len(m.group(0)) // len(m.group(1))), r)


def rule():
    s10, st10 = automaton(10, 7)
    s16, st16 = automaton(16, 6)
    dec = runs(expression(s10, st10, 10))
    hexa = runs(expression(s16, st16, 16))
    return 'charnum = r"#(0*%s|x0*%s);"' % (dec, hexa)


if __name__ == "__main__":
    r = rule()
    print(r)
    if "--check" in sys.argv:
        p = r[r.index('"') + 1:-1]
        # python's atomic groups and possessive repetition are the reading hbnf gives
        q = re.sub(r"\((?!\?)", "(?>", p).replace("0*", "0*+")
        pat = re.compile(q)
        legal = lambda n: any(lo <= n <= hi for lo, hi in LEGAL)
        bad = 0
        for n in list(range(0, 0x110010)) + [10 ** 12, 0x7FFFFFFF, 0xFFFFFFFF, 0x100000000]:
            for text in ("#%d;" % n, "#%s;" % ("0" * 3 + str(n)), "#x%x;" % n, "#x%X;" % n, "#x%s;" % ("0" * 5 + "%x" % n)):
                if bool(pat.fullmatch(text)) != legal(n):
                    bad += 1
                    if bad < 10:
                        print("DIFFERENT:", text)
        for text in ("#;", "#x;", "#X9;", "#-1;", "#xg;", "#9", "#x9", "#1x;", "#09;", "#x09;", "#xa;", "#xA;", "#9;;", "#0;", "#00;"):
            print(text, bool(pat.fullmatch(text)))
        print("length", len(p), "check:", "OK" if not bad else "%d differ" % bad)
