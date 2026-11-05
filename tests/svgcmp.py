import sys, glob, os, xml.etree.ElementTree as ET
def items(p):
    r = ET.parse(p).getroot(); out = []
    for e in r.iter():
        t = e.tag.split('}')[1]
        if t in ('rect', 'text') and (e.get('class') or '') != 'bg':
            out.append((t, e.get('x'), e.get('y'), e.get('width'), (e.text or '').strip()))
    return sorted(out, key=str)
a, b = sys.argv[1], sys.argv[2]
bad = 0; n = 0
for f in sorted(glob.glob(a + '/*.svg')):
    n += 1
    g = os.path.join(b, os.path.basename(f))
    if items(f) != items(g):
        bad += 1
        if bad <= 2:
            x, y = items(f), items(g); print(os.path.basename(f), [i for i in x if i not in y][:3], [i for i in y if i not in x][:3])
print(n, 'charts compared;', bad, 'differ in drawn rects/texts')
