#!/usr/bin/env python3
"""gen.py FORMAT BYTES: a deterministic document of about BYTES bytes in JSON, TOML or YAML,
the shape of the data these formats carry: a list of records with strings, integers, floats,
booleans, nested tables and lists.  The same generator and seed give the same bytes, so every
tool reads the same file.  Written to standard output."""
import random, sys

WORDS = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu".split()

def rec(r, i):
    return {
        "id": i,
        "name": "%s-%s-%d" % (r.choice(WORDS), r.choice(WORDS), i),
        "active": r.random() < .5,
        "score": round(r.uniform(0, 1000), 3),
        "count": r.randint(-100000, 100000),
        "tags": [r.choice(WORDS) for _ in range(r.randint(0, 5))],
        "owner": {"user": r.choice(WORDS), "uid": r.randint(1000, 60000),
                  "home": "/home/" + r.choice(WORDS)},
        "note": " ".join(r.choice(WORDS) for _ in range(r.randint(2, 9))),
    }

def json_doc(r, i):
    import json
    return json.dumps(rec(r, i), separators=(", ", ": "))

def toml_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def toml_doc(r, i):
    x = rec(r, i)
    return "\n".join([
        "[[record]]",
        "id = %d" % x["id"],
        "name = %s" % toml_str(x["name"]),
        "active = %s" % ("true" if x["active"] else "false"),
        "score = %s" % repr(x["score"]),
        "count = %d" % x["count"],
        "tags = [%s]" % ", ".join(toml_str(t) for t in x["tags"]),
        "note = %s" % toml_str(x["note"]),
        "owner = { user = %s, uid = %d, home = %s }" % (toml_str(x["owner"]["user"]), x["owner"]["uid"], toml_str(x["owner"]["home"])),
        "",
    ])

def yaml_doc(r, i):
    x = rec(r, i)
    tags = "".join("    - %s\n" % t for t in x["tags"]) if x["tags"] else ""
    return (
        "- id: %d\n  name: %s\n  active: %s\n  score: %s\n  count: %d\n"
        "  tags:\n%s  owner:\n    user: %s\n    uid: %d\n    home: %s\n  note: \"%s\"\n"
        % (x["id"], x["name"], "true" if x["active"] else "false", repr(x["score"]), x["count"],
           tags if tags else "    []\n" , x["owner"]["user"], x["owner"]["uid"], x["owner"]["home"], x["note"])
    )

fmt, target = sys.argv[1], int(sys.argv[2])
r = random.Random(20261024)
out, size, i = [], 0, 0
while size < target:
    d = {"json": json_doc, "toml": toml_doc, "yaml": yaml_doc}[fmt](r, i)
    out.append(d)
    size += len(d) + 2
    i += 1
if fmt == "json":
    sys.stdout.write("[\n" + ",\n".join(out) + "\n]\n")
else:
    sys.stdout.write("\n".join(out) + "\n")
