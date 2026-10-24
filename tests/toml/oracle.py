#!/usr/bin/env python3
"""The oracle for corpus/toml/toml.hbnf: Python's own tomllib (TOML 1.0).

  oracle.py gen N SEED DIR    write N random valid documents to DIR/g*.toml
  oracle.py mut N SEED DIR    write N mutated documents to DIR/m*.toml and, beside each,
                              DIR/m*.ref: 1 if tomllib accepts it, 0 if it refuses it for
                              its syntax, 2 if it refuses it for what it means (a key or
                              a table defined twice), which a grammar cannot see
  oracle.py check FILE...     print "FILE 1", "FILE 0" or "FILE 2" for each

Nothing here knows hbnf."""
import os, random, sys, tomllib

SEMANTIC = ("Cannot overwrite a value", "Cannot declare", "Cannot mutate immutable",
            "Cannot redefine", "Cannot append to", "Cannot access")

def verdict(b):
    try:
        tomllib.loads(b.decode("utf-8"))
        return 1
    except UnicodeDecodeError:
        return 0
    except tomllib.TOMLDecodeError as e:
        return 2 if str(e).startswith(SEMANTIC) else 0
    except RecursionError:
        return 0

WORDS = ["a", "b", "key", "x-y", "z_1", "Name", "0", "12", "é", "has space", 'q"uote', "dot.ted", ""]

def bare(w):
    return w != "" and all(c.isascii() and (c.isalnum() or c in "-_") for c in w)

def qs(r, w):
    k = r.random()
    if k < .5 or '"' in w:
        if "'" not in w and "\n" not in w:
            return "'" + w + "'"
    return '"' + w.replace("\\", "\\\\").replace('"', '\\"') + '"'

def rkey(r, w):
    if bare(w) and r.random() < .7:
        return w
    return qs(r, w)

def rpath(r, depth):
    return ".".join(rkey(r, r.choice(WORDS)) for _ in range(depth))

TEXT = [chr(c) for c in range(0x20, 0x7f)] + ["é", "€", "😀", "\t"]

def rstring(r):
    body = "".join(r.choice(TEXT) for _ in range(r.choice([0, 1, 3, 8])))
    k = r.randrange(4)
    if k == 0:
        return '"' + body.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if k == 1:
        return "'" + body.replace("'", "") + "'"
    if k == 2:
        b = body.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
        if b.endswith('"'): b = b[:-1] + '\\"'
        return '"""' + r.choice(["", "\n"]) + b + r.choice(["", "\n", "\\\n   "]) + '"""'
    b = body.replace("'''", "")
    if b.endswith("'"): b = b[:-1]
    return "'''" + r.choice(["", "\n"]) + b + r.choice(["", "\n"]) + "'''"

def rint(r):
    k = r.randrange(6)
    if k == 0: return str(r.randint(-10**6, 10**6))
    if k == 1: return "+" + str(r.randint(0, 99))
    if k == 2: return "0x%X" % r.randint(0, 10**6)
    if k == 3: return "0o%o" % r.randint(0, 10**4)
    if k == 4: return "0b%s" % bin(r.randint(0, 255))[2:]
    return "1_000_%d" % r.randint(100, 999)

def rfloat(r):
    return r.choice(["1.5", "-0.0", "3.14e10", "1E-5", "6.02_2e+23", "+1.0", "inf", "-inf", "nan",
                     "0e0", "9_9.1_1"])

def rdate(r):
    d = "%04d-%02d-%02d" % (r.randint(1, 9999), r.randint(1, 12), r.randint(1, 28))
    t = "%02d:%02d:%02d" % (r.randint(0, 23), r.randint(0, 59), r.randint(0, 59))
    if r.random() < .5: t += ".%d" % r.randint(0, 999999)
    return r.choice([d, t, d + "T" + t, d + " " + t, d + "T" + t + "Z", d + "t" + t + "+07:30", d + " " + t + "-01:00"])

def rvalue(r, depth):
    k = r.random()
    if depth < 3 and k < .2:
        n = r.choice([0, 1, 2, 4])
        sep = r.choice([", ", ",", " , ", ",\n  ", ",  # c\n"])
        body = sep.join(rvalue(r, depth + 1) for _ in range(n))
        tail = r.choice(["", "", ","]) if n else ""
        return "[" + r.choice(["", " ", "\n", " # c\n"]) + body + tail + r.choice(["", " ", "\n"]) + "]"
    if depth < 3 and k < .3:
        n = r.choice([0, 1, 3])
        used = r.sample(WORDS, n)
        return "{" + r.choice(["", " "]) + ", ".join(rkey(r, w) + r.choice([" = ", "="]) + rvalue(r, depth + 1) for w in used) + r.choice(["", " "]) + "}"
    return r.choice([rstring, rint, rfloat, rdate, lambda r: r.choice(["true", "false"])])(r)

def document(r):
    out = []
    nl = r.choice(["\n", "\r\n"])
    def comment():
        return r.choice(["", "", "", "  # a comment é"])
    for w in r.sample(WORDS, r.randint(0, 5)):
        out.append(r.choice(["", "  "]) + rkey(r, w) + r.choice([" = ", "="]) + rvalue(r, 0) + comment())
    seen = set()
    for i in range(r.randint(0, 4)):
        name = "t%d" % i
        if r.random() < .3:
            out.append("")
        if r.random() < .3:
            out.append("[[" + r.choice(["", " "]) + name + "." + rkey(r, "sub") + r.choice(["", " "]) + "]]" + comment())
        else:
            out.append("[" + r.choice(["", " "]) + name + r.choice(["", " . x"]) + r.choice(["", " "]) + "]" + comment())
        for w in r.sample(WORDS, r.randint(0, 4)):
            out.append(rkey(r, w) + (".z" if r.random() < .2 else "") + " = " + rvalue(r, 0) + comment())
    return nl.join(out) + r.choice(["", nl])

MUT = list("[]{}=.,\"'#\\ \t_-+:0123456789eExXoObBtTzZ") + ["\n", "\r", "\r\n", "\x01", "\x7f", "é",
       '"""', "'''", "true", "inf", "nan", "[[", "]]", "0x", "1_", "=", " = ", "\\u00", "\\U"]

def mutate(r, s):
    for _ in range(r.choice([1, 1, 1, 2])):
        k = r.choice(["del", "ins", "rep", "swap", "dup", "trunc"])
        if not s:
            s = r.choice(MUT)
            continue
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
            print(f, verdict(open(f, "rb").read()))
        sys.exit(0)
    n, seed, d = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    r = random.Random(seed)
    os.makedirs(d, exist_ok=True)
    for i in range(n):
        s = document(r)
        if mode == "gen":
            open(f"{d}/g{i:05d}.toml", "wb").write(s.encode("utf-8"))
            continue
        while True:
            m = mutate(r, s)
            if "\x00" not in m:
                try: b = m.encode("utf-8")
                except UnicodeEncodeError: continue
                break
        open(f"{d}/m{i:05d}.toml", "wb").write(b)
        open(f"{d}/m{i:05d}.ref", "w").write(str(verdict(b)))
