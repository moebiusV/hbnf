# json-tape.py CORPUS DRIVER: the tape the generated parser writes holds as many values of each kind as
# Python's json finds (keys counted as read, so a repeated key counts each time), in every good
# document of the corpus, and the parser refuses every bad one.
import glob, json, subprocess, sys

KINDS = ("obj", "arr", "str", "num", "true", "false", "null", "key")

def count(pairs_or_value, c):
    v = pairs_or_value
    if isinstance(v, Obj):
        c[0] += 1
        for k, x in v.pairs:
            c[7] += 1
            count(x, c)
    elif isinstance(v, list):
        c[1] += 1
        for x in v:
            count(x, c)
    elif isinstance(v, str): c[2] += 1
    elif v is True: c[4] += 1
    elif v is False: c[5] += 1
    elif v is None: c[6] += 1
    else: c[3] += 1

class Obj:
    def __init__(self, pairs): self.pairs = pairs

def run(path):
    return subprocess.run([sys.argv[2], path], capture_output=True, text=True).stdout.split()

bad = 0
for f in sorted(glob.glob(sys.argv[1] + "/good/*")):
    c = [0] * 8
    count(json.load(open(f, encoding="utf-8"), object_pairs_hook=Obj), c)
    out = run(f)
    got = [int(out[out.index(k) + 1]) for k in KINDS] if out and out[0] != "error" else None
    if got != c:
        bad += 1
        print("json-tape: DIFF", f, got, c)
for f in sorted(glob.glob(sys.argv[1] + "/bad/*")):
    out = run(f)
    if not out or out[0] != "error":
        bad += 1
        print("json-tape: ACCEPTED", f)
sys.exit(1 if bad else 0)
