#!/usr/bin/env python3
"""Random macro programs for tests/cpp.sh: python3 tools/cpp_fuzz_macros.py SEED FILES DIR.
Each file DIR/N.c defines object-like and function-like macros (no parameters up to three, and a `...` or `name...` rest) whose bodies use
the parameters plainly, with `#`, and on either side of `##`, call the macros defined before them, and are called with arguments that are
names, numbers, empty, strings with commas, parenthesised lists with commas, other macros and nested calls.  The tokens that come out are
compared with gcc's; a file gcc itself refuses (a paste that is no token, too few arguments) is left out."""
import random, sys
seed = int(sys.argv[1]); nfile = int(sys.argv[2]); out = sys.argv[3]
random.seed(seed)
IDENTS = ['x', 'y', 'foo', 'bar', 'N1', 'Q']
NUMS = ['0', '1', '42', '7u', '0x10']
OPS = ['+', '-', '*', ',', '<', '&&']


class Macro:
    def __init__(self, name, params, variadic, vname, body):
        self.name, self.params, self.variadic, self.vname, self.body = name, params, variadic, vname, body


def param_names(m):
    p = list(m.params)
    if m.variadic:
        p.append(m.vname)
    return p


def body_atom(m, earlier, depth=0):
    r = random.random()
    names = param_names(m) if m else []
    if names and r < 0.40:
        return random.choice(names)
    if names and r < 0.50:
        return '#' + random.choice(names)
    if names and r < 0.62:
        a = random.choice(names)
        b = random.choice(names + IDENTS + NUMS)
        return random.choice(['%s ## %s', '%s##%s'])% (a, b) if random.random() < 0.5 else '%s ## %s' % (b, a)
    if r < 0.72:
        return random.choice(IDENTS)
    if r < 0.78:
        return random.choice(NUMS)
    if earlier and depth < 2 and r < 0.95:
        c = random.choice(earlier)
        if c.params or c.variadic:
            n = len(c.params) + (random.randint(0, 2) if c.variadic else 0)
            args = [body_atom(m, earlier, depth + 1) if random.random() < 0.7 else random.choice(IDENTS) for _ in range(n)]
            if not args and c.variadic:
                args = []
            return '%s(%s)' % (c.name, ', '.join(args))
        return c.name
    return '(%s)' % body_atom(m, earlier, depth + 1)


def make_macro(i, earlier):
    name = 'M%d' % i
    obj = random.random() < 0.25
    if obj:
        params, variadic, vname = None, False, None
    else:
        n = random.randint(0, 3)
        params = ['a', 'b', 'c'][:n]
        variadic = random.random() < 0.3
        vname = random.choice(['__VA_ARGS__', '__VA_ARGS__', 'rest'])
    m = Macro(name, params, variadic, vname, None)
    if obj:
        m.params = []
        m.body = ' '.join(body_atom(None, earlier) if random.random() < 0.5 else random.choice(IDENTS + NUMS) for _ in range(random.randint(0, 3)))
        m.obj = True
        if random.random() < 0.3:
            m.body = '%s ## %s' % (random.choice(IDENTS), random.choice(IDENTS + NUMS))
        return m
    m.obj = False
    parts = []
    for _ in range(random.randint(1, 4)):
        parts.append(body_atom(m, earlier))
        parts.append(random.choice(OPS) if random.random() < 0.5 else '')
    m.body = ' '.join(p for p in parts if p)
    if m.variadic and random.random() < 0.2:
        m.body = 'pre(%s, ## %s)' % (random.choice(IDENTS), m.vname)
    return m


def header(m):
    if m.obj:
        return '#define %s %s' % (m.name, m.body)
    ps = list(m.params)
    if m.variadic:
        ps.append('...' if m.vname == '__VA_ARGS__' else 'rest...')
    return '#define %s(%s) %s' % (m.name, ', '.join(ps), m.body)


def arg(macros, depth=0):
    r = random.random()
    if r < 0.25:
        return random.choice(IDENTS)
    if r < 0.40:
        return random.choice(NUMS)
    if r < 0.50:
        return ''
    if r < 0.57:
        return '"s,t"'
    if r < 0.64:
        return '(1, 2)'
    if r < 0.70:
        return '%s %s' % (random.choice(IDENTS), random.choice(IDENTS))
    if macros and depth < 2 and r < 0.92:
        return use(random.choice(macros), macros, depth + 1)
    return random.choice(IDENTS)


def use(m, macros, depth=0):
    if m.obj:
        return m.name
    n = len(m.params) + (random.randint(0, 3) if m.variadic else 0)
    if m.variadic and not m.params:
        n = random.randint(0, 3)
    args = [arg(macros, depth) for _ in range(n)]
    if n == 1 and args[0] == '' and not m.params and not m.variadic:
        args = []
    return '%s(%s)' % (m.name, ', '.join(args))


for f in range(nfile):
    macros = []
    L = []
    for i in range(random.randint(2, 5)):
        m = make_macro(i, macros)
        macros.append(m)
        L.append(header(m))
    for k in range(random.randint(3, 8)):
        L.append('v%d_%d = %s ;' % (f, k, use(random.choice(macros), macros)))
    open('%s/%d.c' % (out, f), 'w').write('\n'.join(L) + '\n')
