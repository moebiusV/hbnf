#!/usr/bin/env python3
"""Compare the C preprocessor grammar (corpus/c/cpp.hbnf) with gcc on every .c file under the directories named, in parallel.
  python3 scripts/cpp-scan.py [--gcc PATH] [--pp PATH] [--flags "..."] [--jobs N] [--show N] [--timeout S] DIR...
For each file gcc is asked (`gcc -E -P -w FLAGS -I dir -I dir/..`) and so is the program (a `pp` made as tests/cpp.sh makes it: --pp is where it is; without
it one is made in a temporary directory with the hbnf in HBNF or ./hbnf).  The files are put in classes:
  same        gcc succeeds and the tokens of both are the same
  tokens      gcc succeeds and the tokens differ (the first are shown)
  refused     gcc succeeds and the program does not (a parse error, a crash, a timeout)
  extra-error gcc fails (a diagnostic of error kind) and the program does not report one
  diag-same   both fail, with the same lines of diagnostics (line and kind)
  diag-differ both fail and the diagnostics differ
Exit status 0; the numbers are the report."""
import argparse, os, re, subprocess, sys, tempfile, multiprocessing as mp
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from cpp_tokens import tokens

ap = argparse.ArgumentParser()
ap.add_argument('dirs', nargs='+')
ap.add_argument('--gcc', default='gcc')
ap.add_argument('--pp', default=None)
ap.add_argument('--flags', default='')
ap.add_argument('--jobs', type=int, default=8)
ap.add_argument('--show', type=int, default=12)
ap.add_argument('--timeout', type=int, default=30)
ap.add_argument('--max-size', type=int, default=400000)
ap.add_argument('--out', default=None, help='write every result as `class<TAB>file<TAB>detail` here')
args = ap.parse_args()
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
PP = args.pp
if not PP:
    w = tempfile.mkdtemp()
    hb = os.environ.get('HBNF', os.path.join(ROOT, 'hbnf'))
    env = dict(os.environ, HBNF_TEMPLATES=os.environ.get('HBNF_TEMPLATES', os.path.join(ROOT, 'templates')))
    src = subprocess.run([hb, os.path.join(ROOT, 'corpus/c/cpp.hbnf'), '--backend=c'], capture_output=True, text=True, env=env).stdout
    m = re.search(r'^bool parse_text\(const char \*text, (.*) \*out,$', src, re.M)
    open(w + '/m.c', 'w').write(src + open(os.path.join(ROOT, 'tests/cpp-main.c')).read())
    r = subprocess.run(['cc', '-O1', '-std=gnu11', '-D_GNU_SOURCE', '-w', '-I', os.path.join(ROOT, 'runtime'), '-DOUT_T=' + m.group(1), w + '/m.c', '-o', w + '/pp'], capture_output=True, text=True)
    if r.returncode:
        sys.exit('cc: ' + r.stderr[:300])
    PP = w + '/pp'


def run(cmd, tmo):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=tmo)
    except subprocess.TimeoutExpired:
        return None


DIAG = re.compile(r'^[^:\n]*:(\d+)(?::\d+)?: (fatal error|error|warning): (.*)$', re.M)


def diags(text):
    out = set()
    for m in DIAG.finditer(text):
        out.add((int(m.group(1)), 'error' if 'error' in m.group(2) else 'warning'))
    return out


def work(f):
    d = os.path.dirname(f)
    fl = args.flags.split() + ['-I' + d, '-I' + d + '/..']
    g = run([args.gcc, '-E', '-P'] + fl + [f], args.timeout)
    o = run([PP] + fl + [f], args.timeout)
    if g is None:
        return (f, 'skip', 'gcc timed out')
    gdiag = diags(g.stderr)
    gerr = any(k == 'error' for _, k in gdiag) or g.returncode != 0
    if o is None:
        return (f, 'refused', 'timeout')
    if 'bad\n' in o.stderr[:5] or o.returncode < 0:
        return (f, 'refused' if not gerr else 'diag-differ', (o.stderr.splitlines() or ['crash'])[1:2] and o.stderr.splitlines()[1][:150] or 'crash %d' % o.returncode)
    odiag = diags(o.stderr)
    oerr = any(k == 'error' for _, k in odiag)
    if not gerr:
        gt, ot = tokens(g.stdout), tokens(o.stdout)
        if gt == ot:
            return (f, 'same', '')
        i = next((k for k in range(min(len(gt), len(ot))) if gt[k] != ot[k]), min(len(gt), len(ot)))
        return (f, 'tokens', 'token %d: gcc %r ours %r' % (i, gt[i:i + 3], ot[i:i + 3]))
    if not oerr:
        return (f, 'extra-error', 'gcc: ' + (sorted(gdiag)[:2].__repr__()))
    if {x for x in gdiag if x[1] == 'error'} == {x for x in odiag if x[1] == 'error'}:
        return (f, 'diag-same', '')
    return (f, 'diag-differ', 'gcc %s ours %s' % (sorted(gdiag)[:3], sorted(odiag)[:3]))


files = []
for d in args.dirs:
    for root, _, fs in os.walk(d):
        for n in fs:
            if n.endswith('.c'):
                p = os.path.join(root, n)
                if os.path.getsize(p) <= args.max_size:
                    files.append(p)
files.sort()
with mp.Pool(args.jobs) as pool:
    results = pool.map(work, files, chunksize=4)
if args.out:
    with open(args.out, 'w') as fo:
        for r in results:
            fo.write('%s\t%s\t%s\n' % (r[1], r[0], r[2]))
classes = {}
for r in results:
    classes.setdefault(r[1], []).append(r)
print('%d files' % len(files))
for k in ('same', 'tokens', 'refused', 'extra-error', 'diag-same', 'diag-differ', 'skip'):
    if k in classes:
        print('  %-12s %d' % (k, len(classes[k])))
for k in ('tokens', 'refused', 'extra-error', 'diag-differ'):
    for r in classes.get(k, [])[:args.show]:
        print('%s: %s: %s' % (k, r[0], r[2][:200]))
