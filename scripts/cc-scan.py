#!/usr/bin/env python3
"""Compare a C grammar (corpus/c/*.hbnf) with gcc on every .c file under the directories named, in parallel.
  python3 scripts/cc-scan.py [--gcc PATH] [--grammar c11] [--std gnu11] [--pp gcc|ours] [--jobs N] [--show N] [--out FILE] DIR...
Each file is preprocessed (by gcc -E -P, or by the program of corpus/c/cpp.hbnf with --pp ours, which is the whole pipeline of hbnf's own front end),
with `__attribute__` and `__asm__` taken out as c-scan.sh does (the grammars have neither).  gcc -fsyntax-only is asked about the result:
  both-accept        gcc accepts it and the grammar does
  grammar-refuses    gcc accepts it and the grammar refuses it   <- what is to be fixed or explained (GNU or C23 syntax the grammar does not have)
  grammar-accepts    gcc refuses it (a syntax or a semantic error: the grammar knows no types) and the grammar accepts it  (informational)
  both-refuse        both refuse
  pp-fails           the preprocessor gave an error (gcc's, or ours with --pp ours) and there is no text to read
The first lines each class are shown, with the first thing the grammar says."""
import argparse, os, re, subprocess, sys, tempfile, multiprocessing as mp

ap = argparse.ArgumentParser()
ap.add_argument('dirs', nargs='+')
ap.add_argument('--gcc', default='gcc')
ap.add_argument('--grammar', default='c11')
ap.add_argument('--std', default='gnu11')
ap.add_argument('--pp', default='gcc', choices=['gcc', 'ours'])
ap.add_argument('--jobs', type=int, default=8)
ap.add_argument('--show', type=int, default=15)
ap.add_argument('--timeout', type=int, default=30)
ap.add_argument('--max-size', type=int, default=300000)
ap.add_argument('--out', default=None)
ap.add_argument('--keep', default=None, help='keep the preprocessed files in this directory')
args = ap.parse_args()
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
W = tempfile.mkdtemp()
hb = os.environ.get('HBNF', os.path.join(ROOT, 'hbnf'))
env = dict(os.environ, HBNF_TEMPLATES=os.environ.get('HBNF_TEMPLATES', os.path.join(ROOT, 'templates')))


def build(grammar, main, out):
    src = subprocess.run([hb, os.path.join(ROOT, 'corpus/c', grammar), '--backend=c'], capture_output=True, text=True, env=env).stdout
    m = re.search(r'^bool parse_text\(const char \*text, (.*) \*out,$', src, re.M)
    open(W + '/' + out + '.c', 'w').write(src + open(main).read())
    r = subprocess.run(['cc', '-O1', '-std=gnu11', '-D_GNU_SOURCE', '-w', '-I', os.path.join(ROOT, 'runtime'), '-I', os.path.join(ROOT, 'tests/bsdinc'), '-DOUT_T=' + m.group(1), W + '/' + out + '.c', '-o', W + '/' + out],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit('cc ' + out + ': ' + r.stderr[:300])


build(args.grammar + '.hbnf', os.path.join(ROOT, 'corpus/c/check.c'), 'check')
if args.pp == 'ours':
    build('cpp.hbnf', os.path.join(ROOT, 'tests/cpp-main.c'), 'pp')

STRIP = ['-D__attribute__(x)=', '-D__asm__(x)=', '-D__asm(x)=', '-D__extension__=']


def run(cmd, tmo):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=tmo)
    except subprocess.TimeoutExpired:
        return None


def work(item):
    n, f = item
    d = os.path.dirname(f)
    inc = ['-I' + d, '-I' + d + '/..']
    u = '%s/u%d.i' % (args.keep or W, n)
    if args.pp == 'gcc':
        r = run([args.gcc, '-E', '-P', '-std=' + args.std] + STRIP + inc + ['-w', f], args.timeout)
        if r is None or r.returncode != 0:
            return (f, 'pp-fails', 'gcc -E fails')
        open(u, 'w').write(r.stdout)
    else:
        r = run([W + '/pp', '-std=' + args.std, '-D__attribute__(x)=', '-D__asm__(x)=', '-D__asm(x)=', '-D__extension__='] + inc + [f], args.timeout)
        if r is None or r.returncode != 0 or r.stderr.startswith('bad'):
            return (f, 'pp-fails', (r.stderr.splitlines() or ['timeout'])[0][:140] if r else 'timeout')
        open(u, 'w').write(r.stdout)
    g = run([args.gcc, '-fsyntax-only', '-std=' + args.std, '-w', u], args.timeout)
    gok = g is not None and g.returncode == 0
    c = run([W + '/check', u], args.timeout)
    cok = c is not None and c.stdout.startswith('ok')
    detail = ''
    if c is not None and not cok:
        detail = (c.stdout.splitlines() or [''])[0][:180]
    if gok and cok:
        return (f, 'both-accept', '')
    if gok:
        return (f, 'grammar-refuses', detail)
    if cok:
        return (f, 'grammar-accepts', (g.stderr.splitlines() or [''])[0][:120] if g else 'gcc timeout')
    return (f, 'both-refuse', '')


files = []
for d in args.dirs:
    for root, _, fs in os.walk(d):
        for nme in fs:
            if nme.endswith('.c'):
                p = os.path.join(root, nme)
                if os.path.getsize(p) <= args.max_size:
                    files.append(p)
files.sort()
if args.keep:
    os.makedirs(args.keep, exist_ok=True)
with mp.Pool(args.jobs) as pool:
    results = pool.map(work, list(enumerate(files)), chunksize=4)
if args.out:
    with open(args.out, 'w') as fo:
        for r in results:
            fo.write('%s\t%s\t%s\n' % (r[1], r[0], r[2]))
classes = {}
for r in results:
    classes.setdefault(r[1], []).append(r)
print('%d files, grammar %s, std %s, preprocessed by %s' % (len(files), args.grammar, args.std, args.pp))
for k in ('both-accept', 'grammar-refuses', 'grammar-accepts', 'both-refuse', 'pp-fails'):
    if k in classes:
        print('  %-16s %d' % (k, len(classes[k])))
for k in ('grammar-refuses',):
    for r in classes.get(k, [])[:args.show]:
        print('%s: %s: %s' % (k, r[0], r[2]))
