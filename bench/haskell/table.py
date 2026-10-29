#!/usr/bin/env python3
"""table.py WORKDIR RUNS: the markdown of bench/results/haskell.md, from the rows inner.sh printed
(FORMAT, TOOL, MS, RSS_KIB, STATUS, NOTE) and the versions haskell.sh recorded."""
import datetime
import subprocess
import sys

W, runs = sys.argv[1:3]
root = sys.argv[3]
rows = {}
for line in open(f"{W}/haskell.tsv"):
    fmt, label, ms, rss, status, note = line.rstrip("\n").split("\t")
    rows.setdefault(fmt, []).append((label, float(ms), int(rss), status, note))
import re
vtxt = open(f"{W}/haskell.ver").read()
ghc, alex, happy = (re.search(r"ersion ([0-9.]+)", l).group(1) for l in vtxt.split("\n")[:3])
titles = {"json": "JSON", "toml": "TOML 1.0", "yaml": "YAML 1.2"}


def tm(ms):
    if ms < 10:
        return "%.1f ms" % ms
    return "%.0f ms" % ms if ms < 1000 else "%.2f s" % (ms / 1000)


for fmt in ("json", "toml", "yaml"):
    size = len(open(f"{W}/doc.{fmt}", "rb").read())
    print(f"**{titles[fmt]}** ({size / 1e6:.2f} MB, the same file for every tool; best of up to {runs} runs):\n")
    print("| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |")
    print("|---|---:|---:|---:|---|")
    for label, ms, rss, status, note in sorted(rows[fmt], key=lambda r: (r[3] != "ok", r[1])):
        if status != "ok":
            print(f"| {label} | {status} | | | {note} |")
            continue
        print(f"| {label} | {tm(ms)} | {size / 1e6 / (ms / 1000):.0f} MB/s | {rss // 1024} MB | {note} |")
    print()
rev = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"]).decode().strip()
print(f"_{datetime.date.today()}; amd64, glibc (Debian), GHC {ghc}, Alex {alex}, Happy {happy}; `-O2`; "
      f"hbnf {rev}.  The Haskell parsers are the syntax alone, as hbnf's are: every one is walked to the end, "
      "so nothing is left lazy when the clock stops.  Text is kept as the input holds it where the "
      "parser allows (hbnf's tape and the Alex/Happy JSON); the libraries that convert it say so._")
