#!/usr/bin/env python3
"""table.py WORKDIR RUNS: the markdown of bench/results/raku.md, from the rows inner.sh printed
(FORMAT, TOOL, MS, RSS_KIB, STATUS, NOTE) and the versions raku.sh recorded."""
import datetime
import subprocess
import sys

W, runs = sys.argv[1:3]
root = sys.argv[3]
rows = {}
for line in open(f"{W}/raku.tsv"):
    fmt, label, ms, rss, status, note = line.rstrip("\n").split("\t")
    rows.setdefault(fmt, []).append((label, float(ms), int(rss), status, note))
import re
vtxt = open(f"{W}/raku.ver").read()
rakuver = "Rakudo " + re.search(r"v[0-9][0-9.]*[0-9]", open(f"{W}/raku.ver").read()).group(0)
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
print(f"_{datetime.date.today()}; amd64, glibc (Debian), {rakuver}; hbnf {rev}.  The Raku modules are the syntax alone, as "
      "hbnf's are: the tree each builds is complete when the clock stops.  A run over 20 s is not repeated.  The "
      "grammar-based modules build Raku values and convert text and numbers; hbnf's tape holds offsets._")
