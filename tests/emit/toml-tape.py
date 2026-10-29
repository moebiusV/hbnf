# toml-tape.py CORPUS DRIVER: the tape the generated parser writes holds as many strings, integers,
# floats, booleans and dates as Python's tomllib finds in every good document of the corpus (keys
# cannot repeat in TOML, so a value on the page is a value in the tree), and the parser refuses every
# bad one.
import datetime, glob, subprocess, sys, tomllib

def count(v, c):
    if isinstance(v, dict):
        for x in v.values():
            count(x, c)
    elif isinstance(v, list):
        for x in v:
            count(x, c)
    elif isinstance(v, str): c["str"] += 1
    elif isinstance(v, bool): c["bool"] += 1
    elif isinstance(v, int): c["int"] += 1
    elif isinstance(v, float): c["float"] += 1
    elif isinstance(v, (datetime.datetime, datetime.date, datetime.time)): c["date"] += 1
    else: raise SystemExit("toml-tape: a value of a kind not known: %r" % (v,))

def run(path):
    return subprocess.run([sys.argv[2], path], capture_output=True, text=True).stdout.split()

bad = 0
for f in sorted(glob.glob(sys.argv[1] + "/good/*.toml")):
    c = {"str": 0, "int": 0, "float": 0, "bool": 0, "date": 0}
    count(tomllib.load(open(f, "rb")), c)
    out = run(f)
    if not out or out[0] == "error":
        bad += 1
        print("toml-tape: REFUSED", f)
        continue
    got = {k: int(out[out.index(k) + 1]) for k in c}
    if got != c:
        bad += 1
        print("toml-tape: DIFF", f, got, c)
for f in sorted(glob.glob(sys.argv[1] + "/bad/*.toml")):
    out = run(f)
    if not out or out[0] != "error":
        bad += 1
        print("toml-tape: ACCEPTED", f)
sys.exit(1 if bad else 0)
