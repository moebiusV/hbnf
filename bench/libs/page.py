#!/usr/bin/env python3
"""page.py LIBS.MD: bench/results/libs.md as a page (stdout), where a row marked with a red cross has a pale red background.
GitHub shows no cell colours in Markdown, so the colour lives here; the Markdown stays the record."""
import html, re, sys
out = ["<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>Library benchmark</title>",
       "<style>:root{--bg:#fff;--fg:#1f2328;--line:#d1d9e0;--bad:#fdf0ef}"
       "@media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--line:#30363d;--bad:#2a1517}}"
       "body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;max-width:60rem;margin:0 auto;padding:1rem 16px}"
       "table{border-collapse:collapse;margin:.5rem 0 1.5rem;display:block;overflow-x:auto}th,td{border:1px solid var(--line);padding:.25rem .6rem}"
       "td.n,th.n{text-align:right}tr.bad td{background:var(--bad)}</style>"]
def inline(s):
    s = html.escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", s)
lines = open(sys.argv[1]).read().split("\n"); i = 0
while i < len(lines):
    l = lines[i]
    if l.startswith("| "):
        j = i
        while j < len(lines) and lines[j].startswith("|"): j += 1
        blk = lines[i:j]; i = j
        cells = lambda r: [c.strip() for c in r.strip().strip("|").split("|")]
        al = ["n" if c.endswith(":") else "" for c in cells(blk[1])]
        out.append("<table><tr>" + "".join('<th class="%s">%s</th>' % (a, inline(c)) for a, c in zip(al, cells(blk[0]))) + "</tr>")
        for r in blk[2:]:
            cs = cells(r)
            out.append('<tr%s>' % (' class="bad"' if "❌" in r else "") + "".join('<td class="%s">%s</td>' % (a, inline(c)) for a, c in zip(al, cs)) + "</tr>")
        out.append("</table>")
    else:
        if l.strip(): out.append("<p>%s</p>" % inline(l.strip("_")))
        i += 1
print("\n".join(out))
