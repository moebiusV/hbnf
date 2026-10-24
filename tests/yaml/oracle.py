#!/usr/bin/env python3
"""The oracle for corpus/yaml/yaml.hbnf: PyYAML.

  oracle.py gen N SEED DIR    write N random valid documents to DIR/g*.yaml: random data
                              dumped in PyYAML's block and flow styles, at several widths
                              and indents, with anchors and multi-line strings
  oracle.py mut N SEED DIR    write N mutated documents to DIR/m*.yaml and, beside each,
                              DIR/m*.ref: 1 if PyYAML reads it, else 0
  oracle.py check FILE...     print "FILE 1" or "FILE 0" for each

PyYAML reads YAML 1.1, so a mutation it refuses and the grammar accepts (or the reverse) is
not always a fault of the grammar; tests/yaml-diff.sh counts them and gates only on the valid
documents.  Nothing here knows hbnf."""
import os, random, sys, yaml

def accepts(b):
    try:
        list(yaml.safe_load_all(b.decode("utf-8")))
        return 1
    except Exception:
        return 0

WORDS = ["a", "b", "key", "x y", "Name", "0", "12", "é", "has: colon", "- dash", "# hash",
         "quote\"s", "it's", "tab\there", "multi\nline", "trailing ", " leading", "", "yes",
         "null", "~", "1.5", "[brackets]", "{braces}", "a,b", "*star", "&amp", "!bang",
         "%pct", "@at", "line1\nline2\n\nline4", "long " * 30]

def rscalar(r):
    return r.choice([r.choice(WORDS), r.randint(-10**6, 10**6), r.random() * 100,
                     r.choice([True, False, None])])

def rval(r, depth):
    k = r.random()
    if depth > 4 or k < .35:
        return rscalar(r)
    if k < .7:
        return [rval(r, depth + 1) for _ in range(r.choice([0, 1, 2, 3, 5]))]
    return {r.choice(WORDS[:20]) + str(i): rval(r, depth + 1)
            for i in range(r.choice([0, 1, 2, 3]))}

def dump(r, v):
    kw = dict(default_flow_style=r.choice([False, False, True, None]),
              width=r.choice([20, 40, 80, 1000]), indent=r.choice([2, 3, 4, 7]),
              allow_unicode=r.random() < .5, sort_keys=r.random() < .5,
              default_style=r.choice([None, None, None, '"', "'", "|", ">"]))
    try:
        s = yaml.dump(v, **kw)
    except Exception:
        s = yaml.dump(v)
    return r.choice(["", "", "---\n", "# comment\n", "%YAML 1.1\n---\n"]) + s + r.choice(["", "", "...\n", "# end\n"])

MUT = list("[]{}:,-?#&*!|>'\"%@` \t.0123456789") + ["\n", "\n  ", "\n    ", "- ", ": ", "---", "...", "\t",
       "\r\n", "&a ", "*a", "!!str ", "|\n  x", ">-\n  x", "? ", "{}", "[]"]

def mutate(r, s):
    for _ in range(r.choice([1, 1, 1, 2])):
        if not s:
            s = r.choice(MUT)
            continue
        k = r.choice(["del", "ins", "rep", "swap", "dup", "trunc"])
        i = r.randrange(len(s))
        if k == "del": s = s[:i] + s[i + 1:]
        elif k == "ins": s = s[:i] + r.choice(MUT) + s[i:]
        elif k == "rep": s = s[:i] + r.choice(MUT) + s[i + 1:]
        elif k == "swap" and i + 1 < len(s): s = s[:i] + s[i + 1] + s[i] + s[i + 2:]
        elif k == "dup": s = s[:i] + s[i] + s[i:]
        else: s = s[:i]
    return s

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "check":
        for f in sys.argv[2:]:
            print(f, accepts(open(f, "rb").read()))
        sys.exit(0)
    n, seed, d = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    r = random.Random(seed)
    os.makedirs(d, exist_ok=True)
    for i in range(n):
        s = dump(r, rval(r, 0))
        if mode == "gen":
            open(f"{d}/g{i:05d}.yaml", "wb").write(s.encode("utf-8"))
            continue
        while True:
            m = mutate(r, s)
            if "\x00" not in m:
                try: b = m.encode("utf-8")
                except UnicodeEncodeError: continue
                break
        open(f"{d}/m{i:05d}.yaml", "wb").write(b)
        open(f"{d}/m{i:05d}.ref", "w").write(str(accepts(b)))
