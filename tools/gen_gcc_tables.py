#!/usr/bin/env python3
"""The tables the C preprocessor grammar (corpus/c/cpp.hbnf) takes from gcc, written as corpus/c/cpp-gnu.hbnf: python3 tools/gen_gcc_tables.py [gcc].
gcc is authoritative for what a GNU preprocessor defines and accepts, so nothing is typed in by hand:
  - the predefined macros (`gcc -dM -E -x c /dev/null`), object-like and function-like;
  - the names `__has_attribute` knows and what it answers (found by asking gcc about every identifier its compiler proper holds as a string);
  - the same for `__has_builtin` and `__has_c_attribute`;
  - the system include directories (`gcc -E -v`).
The result is tied to the gcc and target it was made on (a comment at the top says which); run it again for another."""
import re, subprocess, sys, os, tempfile

gcc = sys.argv[1] if len(sys.argv) > 1 else 'gcc'


def run(args, inp=None):
    return subprocess.run(args, input=inp, capture_output=True, text=True)


ver = run([gcc, '--version']).stdout.splitlines()[0]
target = run([gcc, '-dumpmachine']).stdout.strip()

# the predefined macros, for every standard gcc has (what gcc builds in: with -nostdinc, which leaves out what glibc's stdc-predef.h, included before every file, defines) (-std=c89 ... gnu2y): a macro has the standards it is defined in, with and without -undef
STDS = ['c89', 'c99', 'c11', 'c17', 'c23', 'c2y', 'gnu89', 'gnu99', 'gnu11', 'gnu17', 'gnu23', 'gnu2y']


def macros(std, undef):
    cmd = [gcc] + (['-std=' + std] if std else []) + (['-undef'] if undef else []) + ['-nostdinc', '-dM', '-E', '-x', 'c', '/dev/null']
    out = set()
    for line in run(cmd).stdout.splitlines():
        m = re.match(r'#define (\w+)(\(([^)]*)\))? ?(.*)$', line)
        if m:
            out.add((m.group(1), m.group(3) if m.group(2) else None, m.group(4)))
    return out


per = {}      # (name, params, body) -> [mask, umask]
dflt = macros(None, False)
dflt_std = None
for k, st in enumerate(STDS):
    plain, und = macros(st, False), macros(st, True)
    if plain == dflt and dflt_std is None:
        dflt_std = k
    for e in plain:
        per.setdefault(e, [0, 0])[0] |= 1 << k
    for e in und:
        per.setdefault(e, [0, 0])[1] |= 1 << k
pre = sorted(per.items(), key=lambda kv: (kv[0][0], kv[0][2] or ''))

# the system include directories
v = run([gcc, '-E', '-v', '-x', 'c', '/dev/null']).stderr
dirs = []
grab = False
for line in v.splitlines():
    if line.startswith('#include <...>'):
        grab = True
        continue
    if line.startswith('End of search list'):
        grab = False
    if grab and line.startswith(' '):
        dirs.append(line.strip())

# the identifiers the compiler proper holds
cc1 = run([gcc, '-print-prog-name=cc1']).stdout.strip()
words = set()
data = open(cc1, 'rb').read()
for m in re.finditer(rb'[A-Za-z_][A-Za-z_0-9]{1,60}', data):
    words.add(m.group(0).decode())
words = sorted(words)


def ask(feature, names):
    """name -> value for the names `feature(name)` answers non-zero for"""
    res = {}
    for i in range(0, len(names), 4000):
        chunk = names[i:i + 4000]
        src = ''.join('@%d@ %s(%s)\n' % (k, feature, n) for k, n in enumerate(chunk))
        with tempfile.NamedTemporaryFile('w', suffix='.c', delete=False) as f:
            f.write(src)
            path = f.name
        out = run([gcc, '-E', '-P', '-w', '-undef', '-nostdinc', path]).stdout
        os.unlink(path)
        for line in out.splitlines():
            m = re.match(r'@(\d+)@ (\d+)L?$', line.strip())
            if m and int(m.group(2)) != 0:
                res[chunk[int(m.group(1))]] = m.group(2)
    return res


attrs = ask('__has_attribute', [w for w in words if not (w.startswith('__') and w.endswith('__'))])
# an attribute is also known as __name__
attrs = {k: v for k, v in attrs.items()}
builtins = ask('__has_builtin', words)
cattrs = ask('__has_c_attribute', [w for w in words if not w.startswith('__')] + ['gnu::' + w for w in attrs])
cppattrs = ask('__has_cpp_attribute', [w for w in words if not w.startswith('__')] + ['gnu::' + w for w in attrs])
features = ask('__has_feature', [w for w in words])
extensions = ask('__has_extension', [w for w in words])


def cstr(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


out = []
out.append('; The tables the C preprocessor grammar takes from gcc, made by tools/gen_gcc_tables.py: do not edit.')
out.append(';   %s, target %s' % (ver, target))
out.append('{')
out.append('#include <stddef.h>')
out.append('/* gcc\'s predefined macros (`gcc -dM -E`): name, parameters (NULL for an object-like macro), body, and whether -undef leaves it */')
out.append('static const char *cpp_gnu_stds[] = { %s };   /* the standards of -std=, the bit of each in the masks below */' % ', '.join(cstr(x) for x in STDS))
out.append('static const int cpp_gnu_default_std = %d;   /* the one gcc has without -std= */' % (dflt_std if dflt_std is not None else STDS.index('gnu23')))
out.append('static const struct { const char *name, *params, *body; unsigned mask, umask; } cpp_gnu_pre[] = {   /* the standards it is defined in, and with -undef */')
for (n, p, b), (mk, um) in pre:
    out.append('    { %s, %s, %s, %du, %du },' % (cstr(n), cstr(p) if p is not None else 'NULL', cstr(b), mk, um))
out.append('};')
out.append('static const char *cpp_gnu_sysdirs[] = { %s };' % ', '.join(cstr(d) for d in dirs))
for nm, tbl in (('attr', attrs), ('builtin', builtins), ('cattr', cattrs), ('cppattr', cppattrs), ('feature', features), ('ext', extensions)):
    out.append('/* what `__has_%s(name)` answers, for the names it answers something but 0 for (sorted) */' % {'attr': 'attribute', 'builtin': 'builtin', 'cattr': 'c_attribute', 'cppattr': 'cpp_attribute', 'feature': 'feature', 'ext': 'extension'}[nm])
    out.append('static const struct { const char *name; long value; } cpp_gnu_%s[] = {' % nm)
    for k in sorted(tbl):
        out.append('    { %s, %sL },' % (cstr(k), tbl[k].rstrip('L')))
    out.append('};')
out.append('}')
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'corpus', 'c', 'cpp-gnu.hbnf'), 'w').write('\n'.join(out) + '\n')
print('%d predefined macro definitions, %d system directories, %d attributes, %d builtins, %d c attributes, %d c++ attributes, %d features, %d extensions' % (len(pre), len(dirs), len(attrs), len(builtins), len(cattrs), len(cppattrs), len(features), len(extensions)))
