# yaml-tape.py SUITE DRIVER [SUITE-GAPS [TAPE-GAPS]]: the tape the generated parser writes, read back
# as events, has the events of every valid case of the YAML test suite (its test.event): documents,
# mappings, sequences, scalars and aliases in the same order.  The values are not compared; a tape
# holds the text as it stands.  The cases in SUITE-GAPS (the acceptance gaps) are skipped; those in
# TAPE-GAPS must differ, and the run fails when one does not.
import glob, os, subprocess, sys

DOC, MAP, SEQ, PLAIN, DQ, SQ, BLOCK, ALIAS, ANCHOR, TAG, NULL = range(1, 12)
OPEN = {DOC: "DOC", MAP: "MAP", SEQ: "SEQ"}
SCALAR = {PLAIN, DQ, SQ, BLOCK, NULL}

def events_of_tape(lines):
    words = []
    for ln in lines[1:]:
        p = ln.split()
        words.append((int(p[0]), int(p[2]) if len(p) > 2 and p[1] == "link" else None))
    out, stack, i = [], [], 0
    while i < len(words):
        while stack and stack[-1][0] == i:
            out.append("-" + stack.pop()[1])
        tag, link = words[i]
        if tag in OPEN:
            out.append("+" + OPEN[tag]); stack.append((link, OPEN[tag]))
        elif tag in SCALAR:
            out.append("=VAL")
        elif tag == ALIAS:
            out.append("=ALI")
        i += 1
    while stack:
        out.append("-" + stack.pop()[1])
    return out

def events_of_file(path):
    out = []
    for ln in open(path, encoding="utf-8"):
        k = ln.split(" ", 1)[0].strip()
        if k in ("+DOC", "-DOC", "+MAP", "-MAP", "+SEQ", "-SEQ", "=VAL", "=ALI"):
            out.append(k)
    return out

def listed(path):
    return {l.split()[0] for l in open(path) if l.strip() and not l.startswith("#")}

gaps = listed(sys.argv[3]) if len(sys.argv) > 3 else set()
expected = listed(sys.argv[4]) if len(sys.argv) > 4 else set()
bad = ok = 0
seen = set()
for d in sorted(glob.glob(sys.argv[1] + "/*/") + glob.glob(sys.argv[1] + "/*/*/")):
    inp = os.path.join(d, "in.yaml")
    if not os.path.exists(inp) or os.path.exists(os.path.join(d, "error")) or not os.path.exists(os.path.join(d, "test.event")):
        continue
    name = os.path.relpath(d, sys.argv[1]).strip("/")
    if name in gaps or name.startswith("name/"):
        continue
    r = subprocess.run([sys.argv[2], inp], capture_output=True, text=True)
    lines = r.stdout.splitlines()
    if not lines or lines[0] != "tape":
        bad += 1; print("yaml-tape: REFUSED", name); continue
    got, want = events_of_tape(lines), events_of_file(os.path.join(d, "test.event"))
    if got != want and name not in expected:
        bad += 1
        print("yaml-tape: DIFF", name, "\n   got ", " ".join(got[:40]), "\n   want", " ".join(want[:40]))
    elif got == want and name in expected:
        bad += 1
        print("yaml-tape: listed in tape-gaps.txt but now right (remove it):", name)
    else:
        ok += 1
    seen.add(name)
print("yaml-tape: %d cases as expected (%d listed gaps), %d unexpected" % (ok, len(expected), bad))
sys.exit(1 if bad else 0)
