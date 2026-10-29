# json-counts.py CORPUS DRIVER: the tape made from corpus/json/json.hbnf with --layout=tape holds as many
# objects, arrays, members, strings (values and keys), numbers, trues, falses and nulls as Python's json
# finds in every good document (a repeated key counts each time), and the parser refuses every bad one.
import glob, json, subprocess, sys

class Obj:
    def __init__(self, pairs): self.pairs = pairs

def count(v, c):
    if isinstance(v, Obj):
        c["object"] += 1
        for k, x in v.pairs:
            c["member"] += 1; c["string"] += 1
            count(x, c)
    elif isinstance(v, list):
        c["array"] += 1
        for x in v: count(x, c)
    elif isinstance(v, str): c["string"] += 1
    elif v is True: c["literal-true"] += 1
    elif v is False: c["literal-false"] += 1
    elif v is None: c["literal-null"] += 1
    else: c["number"] += 1

NAMES = ("object", "array", "member", "string", "number", "literal-true", "literal-false", "literal-null")
bad = 0
for f in sorted(glob.glob(sys.argv[1] + "/good/*")):
    c = dict.fromkeys(NAMES, 0)
    count(json.load(open(f, encoding="utf-8"), object_pairs_hook=Obj), c)
    r = subprocess.run([sys.argv[2], f], capture_output=True, text=True).stdout.splitlines()
    if not r or r[0] != "tape":
        bad += 1; print("layout: REFUSED", f); continue
    got = dict.fromkeys(NAMES, 0)
    for ln in r[1:]:
        k = ln.split(" ", 1)[0]
        if k in got: got[k] += 1
    if got != c:
        bad += 1; print("layout: DIFF", f, got, c)
for f in sorted(glob.glob(sys.argv[1] + "/bad/*")):
    r = subprocess.run([sys.argv[2], f], capture_output=True, text=True).stdout
    if not r.startswith("error"):
        bad += 1; print("layout: ACCEPTED", f)
sys.exit(1 if bad else 0)
