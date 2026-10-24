#!/usr/bin/env python3
"""table.py WORKDIR ROOT CARGO.LOCK RUNS: the markdown of bench/results/libs.md, from the rows
inner.sh printed (FORMAT, TOOL, MS, RSS_KIB, STATUS) and the versions libs.sh recorded."""
import datetime
import re
import subprocess
import sys

W, root, lock, runs = sys.argv[1:5]
rows = {}
for line in open(f"{W}/glibc.tsv"):
    fmt, label, ms, rss, status = line.rstrip("\n").split("\t")
    rows.setdefault(fmt, []).append((label, float(ms), int(rss), status))
vers = dict(re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"', open(lock).read()))
ver = open(f"{W}/glibc.ver").read().split("\n")
titles = {"json": "JSON", "toml": "TOML 1.0", "yaml": "YAML 1.2"}


def tm(ms):
    if ms < 10:
        return "%.1f ms" % ms
    return "%.0f ms" % ms if ms < 1000 else "%.2f s" % (ms / 1000)


for fmt in ("json", "toml", "yaml"):
    size = len(open(f"{W}/doc.{fmt}", "rb").read())
    print(f"**{titles[fmt]}** ({size / 1e6:.2f} MB, the same file for every tool; best of up to {runs} runs):\n")
    print("| tool | parse time | MB/s | peak RSS | RSS over the input |")
    print("|---|---:|---:|---:|---:|")
    for label, ms, rss, status in sorted(rows[fmt], key=lambda r: (r[3] != "ok", r[1])):
        if label.startswith("serde_json"):
            label += " " + vers.get("serde_json", "")
        if label.startswith("toml (Rust)"):
            label += " " + vers.get("toml", "")
        if status != "ok":
            print(f"| {label} | {status} | | | |")
            continue
        over = max(rss * 1024 - size, 0) / size
        print(f"| {label} | {tm(ms)} | {size / 1e6 / (ms / 1000):.0f} MB/s | {rss // 1024} MB | {over:.1f}x |")
    print()
rev = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"]).decode().strip()
print(f"_{datetime.date.today()}; {ver[1].strip()}, {ver[0].strip()}, node {ver[2].strip().lstrip('v')}, "
      f"{ver[3].strip()}; `-O2`, the same sources and flags for every native library; hbnf {rev}.  "
      "simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build "
      "their own value types, and hbnf builds the typed tree its grammar describes._")
