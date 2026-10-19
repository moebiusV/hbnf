#!/usr/bin/env python3
"""The oracle for corpus/json/json.hbnf: Python's own json module, strict.

  oracle.py gen N SEED DIR    write N random valid documents to DIR/g*.json
  oracle.py mut N SEED DIR    write N mutated documents to DIR/m*.json and, beside each,
                              DIR/m*.ref: 1 if json.loads accepts it, else 0
  oracle.py check FILE...     print "FILE 1" or "FILE 0" for each

json.loads is told to refuse NaN and Infinity (RFC 8259 has neither); everything else is
its default, strict mode: a control character in a string is an error, a top-level
scalar is fine, duplicate keys are fine.  Nothing here knows hbnf."""
import json, os, random, sys

def boom(x):
    raise ValueError(x)

def accepts(b):
    try:
        json.loads(b.decode("utf-8"), parse_constant=boom)
        return True
    except (ValueError, RecursionError, UnicodeDecodeError):
        return False

ALPHA = ([chr(c) for c in range(0x20, 0x7f)] + ["\t", "\n", "\x01", "\x1f", "\x7f", "é", "ß", "€",
         " ", "😀", "\U0001F680", "\\", '"', "/", "퟿", "", "￿"])

def rstr(r):
    return "".join(r.choice(ALPHA) for _ in range(r.choice([0, 0, 1, 2, 5, 12])))

def rnum(r):
    k = r.random()
    if k < .35:
        return r.choice([0, 1, -1, 7, 42, 10 ** r.randint(1, 30), -(10 ** r.randint(1, 25)),
                         r.randint(-10 ** 6, 10 ** 6)])
    f = r.choice([0.0, -0.0, 0.5, 1e-7, 1.5e300, 2.5e-300, 123456.789, r.uniform(-1e3, 1e3),
                  r.uniform(-1, 1) * 10 ** r.randint(-30, 30)])
    return f

def rval(r, depth):
    k = r.random()
    if depth > 4 or k < .3:
        return r.choice([None, True, False, rnum(r), rstr(r), rnum(r), rstr(r)])
    if k < .65:
        return [rval(r, depth + 1) for _ in range(r.choice([0, 1, 2, 3, 6]))]
    return {rstr(r): rval(r, depth + 1) for _ in range(r.choice([0, 1, 2, 4]))}

def dump(r, v):
    kw = {"ensure_ascii": r.random() < .5, "allow_nan": False}
    k = r.random()
    if k < .3:
        kw["indent"] = r.choice([0, 1, 2, 4, "\t"])
    elif k < .5:
        kw["separators"] = r.choice([(",", ":"), (" , ", " : "), (", ", ": ")])
    s = json.dumps(v, **kw)
    return r.choice(["", "", " ", "\n", "\t \r\n"]) + s + r.choice(["", "", "\n", "  "])

MUT = list('{}[],:"\\ 0123456789eE+-.truefalsn/ubt') + ["\n", "\t", "\x01", "\x0c", "é", "﻿", " ", "NaN", "Infinity", "-", "0", "true", "null", "\\u", "\\ud800", '"', "'"]

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
        s = dump(r, rval(r, 0))
        if mode == "gen":
            open(f"{d}/g{i:05d}.json", "wb").write(s.encode("utf-8"))
            continue
        while True:
            m = mutate(r, s)
            if "\x00" not in m:
                try:
                    b = m.encode("utf-8")
                except UnicodeEncodeError:
                    continue
                break
        open(f"{d}/m{i:05d}.json", "wb").write(b)
        open(f"{d}/m{i:05d}.ref", "w").write("1" if accepts(b) else "0")
