#!/usr/bin/env python3
"""The oracle of tests/js-diff.sh: V8, through py_mini_racer (pip install mini-racer), asked whether a text is a
JavaScript Script.  The text is compiled by V8 in a fresh context behind a `throw 0;` line, so that it is
parsed and not run: a text that V8 refuses with a SyntaxError was refused by the parser, and anything else parsed.

  oracle.py check FILE...        FILE 1 | 0 | L   for each
  oracle.py gen N SEED DIR       N random programs DIR/gNNNN.js (nearly all of them Scripts V8 accepts) and V8's verdicts DIR/gNNNN.ref
  oracle.py mut N SEED DIR       N mutations DIR/mNNNN.js, with V8's verdict in DIR/mNNNN.ref
  oracle.py ids DIR              every code point as the first and as a later character of a name: DIR/ids.in
                                 (the texts, NUL separated), DIR/ids.ref (V8's verdicts, 1 or 0, one byte each)

The verdict is 1 (accepted), 0 (a syntax error the grammar of the specification has: an unexpected token, a missing
bracket, a statement with no end ...) or L (a syntax error that the specification states as an early error, a rule
of its static semantics: an assignment to a number, a duplicate `let`, `break` outside a loop, a regular expression
that does not compile, an octal escape in strict code ...): the grammar of corpus/js leaves those out by design.
"""
import os
import random
import re
import sys

try:
    from py_mini_racer import MiniRacer, JSParseException
except ImportError:
    sys.stderr.write("oracle.py: py_mini_racer is not installed (pip install mini-racer)\n")
    sys.exit(3)

# V8's messages for the early errors of the specification (static semantics); every other SyntaxError is a 0.
EARLY = re.compile(
    r"Invalid left-hand side|Invalid destructuring assignment target|Invalid shorthand property|has already been declared|"
    r"Missing initializer|Illegal break|Illegal continue|Undefined label|Label '.*' has already|"
    r"Unexpected eval or arguments|strict mode|Strict mode|Octal|Decimals with leading zeros|Delete of an unqualified|"
    r"Duplicate parameter|Illegal 'use strict'|Invalid regular expression|Invalid Unicode escape|Invalid hexadecimal|"
    r"Undefined Unicode|'super' keyword|new\.target|Private field|Class constructor|A class may only|Classes may not|"
    r"Yield expression not allowed|Await expression not allowed|Invalid escape|Unexpected reserved word|"
    r"Invalid optional chain|Invalid tagged template|Unexpected token 'await'|Invalid left|Duplicate export|"
    r"Invalid escaped|Invalid shorthand|Cannot use|'arguments'|Invalid class|for-in loop variable declaration|"
    r"Invalid left-hand|Cannot redeclare|Illegal newline after throw|Unexpected token 'yield'")


def verdict(src):
    try:
        MiniRacer().eval('throw 0;\n' + src, timeout=2000)
    except JSParseException as e:
        return 'L' if EARLY.search(str(e)) else '0'
    except Exception:
        pass            # it ran, and threw, or took too long: it parsed
    return '1'


# ---- random programs --------------------------------------------------------------------------------------------

class Gen:
    """Programs that V8 accepts, by construction: every name is declared once, `break`, `return`, `yield`, `await`,
    `super` and `new.target` stand where they are allowed, a statement that begins with `(`, `[`, a template or an
    operator follows a `;`, and a line end stands in the places where ASI inserts a `;` and in some of the places
    where blanks may stand."""

    def __init__(self, rnd):
        self.r = rnd
        self.n = 0
        self.names = ['a0']
        self.ret = self.yld = self.awt = self.sup = self.nt = self.loop = self.brk = False
        self.strict = False

    def fresh(self, base='v'):
        self.n += 1
        return '%s%d' % (base, self.n)

    def use(self):
        return self.r.choice(self.names)

    def pick(self, *xs):
        return self.r.choice(xs)

    def chance(self, p):
        return self.r.random() < p

    def ctx(self, **kw):
        old = {k: getattr(self, k) for k in kw}
        for k, v in kw.items():
            setattr(self, k, v)
        return old

    def restore(self, old):
        for k, v in old.items():
            setattr(self, k, v)

    # -- atoms
    def num(self):
        xs = ['0', '1', '42', '3.14', '.5', '5.', '1e3', '0x1F', '0b101', '0o17', '1_000', '10n', '0xFFn', '1.5e-3', '9007199254740993n', '1_0.2_5e1_0']
        if not self.strict:
            xs += ['07', '08.5']
        return self.pick(*xs)

    def string(self):
        return self.pick('"a"', "'b'", '"\\n"', "'\\u0041'", '"\\x41"', '"\\u{1F600}"', "'a\\\nb'", '""', '"\\0"', "'\\''", '" "', '"/* x */"', "'//'")

    def regex(self):
        return self.pick('/a+/g', '/[/]/', '/\\//i', '/(?:a|b)*?c/', '/[a-z]\\d{2,3}/', '/=/', '/[^/]*/y', '/\\u{41}/u', '/(?<n>a)\\k<n>/')

    def template(self, d):
        parts = ['`']
        for _ in range(self.r.randint(0, 2)):
            parts.append(self.pick('a', ' ', '\\`', '$', '$$', '\\${', 'x\ny'))
            parts.append('${' + self.expr(d + 1) + '}')
        parts.append(self.pick('', 'z', '\\u0041'))
        parts.append('`')
        return ''.join(parts)

    def key(self, d):
        return self.pick(self.fresh('p'), 'if', '"s"', '1', '0x10', '1.5', "'x y'", '[' + self.expr(d + 1) + ']', 'get', 'set', 'static', 'async', 'of', 'let', 'class')

    def obj(self, d):
        out = []
        for _ in range(self.r.randint(0, 3)):
            k = self.r.random()
            if k < 0.3:
                out.append(self.key(d) + ': ' + self.expr(d + 1))
            elif k < 0.4:
                out.append(self.use())
            elif k < 0.5:
                out.append('...' + self.use())
            elif k < 0.65:
                out.append(self.key(d) + '(' + self.params(d) + ') ' + self.fbody(d, False, False, True))
            elif k < 0.75:
                out.append('get ' + self.key(d) + '() ' + self.fbody(d, False, False, True))
            elif k < 0.85:
                out.append('set ' + self.key(d) + '(' + self.fresh('s') + ') ' + self.fbody(d, False, False, True))
            elif k < 0.92:
                out.append('async ' + self.pick('', '*') + self.key(d) + '() ' + self.fbody(d, True, False, True))
            else:
                out.append('*' + self.key(d) + '() ' + self.fbody(d, False, True, True))
        return '{' + ', '.join(out) + (self.pick('', ',') if out else '') + '}'

    def arr(self, d):
        out = [self.pick('', self.expr(d + 1), self.expr(d + 1), '...' + self.use()) for _ in range(self.r.randint(0, 3))]
        return '[' + ', '.join(out) + ']'

    def args(self, d):
        out = [self.pick(self.expr(d + 1), '...' + self.use()) for _ in range(self.r.randint(0, 3))]
        return '(' + ', '.join(out) + (self.pick('', ',') if out else '') + ')'

    def params(self, d):
        out = []
        for _ in range(self.r.randint(0, 3)):
            out.append(self.pick(self.fresh('q'), self.fresh('q') + ' = ' + self.expr(d + 1), '[' + self.fresh('q') + ', , ' + self.fresh('q') + ']',
                                 '{' + self.fresh('q') + ', k: ' + self.fresh('q') + ' = 1}'))
        if self.chance(0.2):
            return ', '.join(out + ['...' + self.fresh('r')])
        return ', '.join(out) + (self.pick('', ',') if out else '')

    def fbody(self, d, is_async, is_gen, method=False, arrow=False):
        saved_names = self.names[:]
        if arrow:
            old = self.ctx(ret=True, loop=False, brk=False)
        else:
            old = self.ctx(ret=True, yld=is_gen, awt=is_async, nt=True, loop=False, brk=False, sup=method or self.sup)
        body = self.stmts(d + 1, self.r.randint(0, 3))
        self.restore(old)
        self.names = saved_names
        return '{ ' + body + ' }'

    def func(self, d, decl=False):
        a = self.chance(0.2)
        g = self.chance(0.2)
        nm = self.fresh('f') if (decl or self.chance(0.5)) else ''
        return ('async ' if a else '') + 'function' + ('*' if g else '') + ' ' + nm + '(' + self.params(d) + ') ' + self.fbody(d, a, g)

    def arrow(self, d):
        a = self.chance(0.2)
        ps = self.fresh('q') if self.chance(0.3) else '(' + self.params(d) + ')'
        if self.chance(0.5):
            old = self.ctx(awt=a, yld=False)
            body = self.expr(d + 1)
            self.restore(old)
            if body.startswith('{'):
                body = '(' + body + ')'
        else:
            body = self.fbody(d, a, False, arrow=True)
        return ('async ' if a else '') + ps + ' => ' + body

    def cls(self, d, decl=False):
        out = []
        nm = self.fresh('C') if (decl or self.chance(0.5)) else ''
        ext = ' extends ' + self.pick('Object', 'Array') if self.chance(0.3) else ''
        old = self.ctx(sup=True)
        old_strict, self.strict = self.strict, True
        for _ in range(self.r.randint(0, 4)):
            k = self.r.random()
            static = 'static ' if self.chance(0.2) else ''
            nm1 = self.pick(self.fresh('m'), '"s"', '[' + self.expr(d + 1) + ']', '#' + self.fresh('h'))
            if k < 0.25:
                out.append(static + nm1 + '(' + self.params(d) + ') ' + self.fbody(d, False, False, True))
            elif k < 0.5:
                out.append(static + self.pick(self.fresh('x'), '#' + self.fresh('h'), '"y"', '[' + self.expr(d + 1) + ']') + self.pick('', ' = ' + self.expr(d + 1)) + ';')
            elif k < 0.6:
                out.append(static + 'get ' + self.fresh('g') + '() ' + self.fbody(d, False, False, True))
            elif k < 0.7:
                out.append(static + 'set ' + self.fresh('g') + '(' + self.fresh('s') + ') ' + self.fbody(d, False, False, True))
            elif k < 0.8:
                out.append(static + 'async ' + self.pick('', '*') + self.fresh('m') + '() ' + self.fbody(d, True, False, True))
            elif k < 0.9:
                old2 = self.ctx(ret=False, loop=False, brk=False)
                out.append('static { ' + self.stmts(d + 1, 1) + ' }')
                self.restore(old2)
            else:
                out.append(';')
        self.strict = old_strict
        self.restore(old)
        return 'class ' + nm + ext + ' { ' + ' '.join(out) + ' }'

    def primary(self, d):
        k = self.r.random()
        if d > 4:
            return self.pick(self.use(), self.num(), self.string(), 'this', 'null', 'true')
        if k < 0.22:
            return self.use()
        if k < 0.32:
            return self.num()
        if k < 0.40:
            return self.string()
        if k < 0.45:
            return self.regex()
        if k < 0.52:
            return self.template(d)
        if k < 0.59:
            return self.arr(d)
        if k < 0.66:
            return self.obj(d)
        if k < 0.72:
            return '(' + self.expr(d + 1) + ')'
        if k < 0.77:
            return self.func(d)
        if k < 0.80:
            return self.cls(d)
        if k < 0.86:
            return self.pick('this', 'null', 'true', 'false')
        if k < 0.89 and self.nt:
            return 'new.target'
        if k < 0.92 and self.sup:
            return 'super.' + self.fresh('z')
        return self.use()

    def chain(self, d):
        s = self.primary(d)
        if s[0].isdigit() or s[0] == '.':
            s = '(' + s + ')'
        optional = False
        for _ in range(self.r.choice((0, 0, 1, 2, 3))):
            k = self.r.random()
            if k < 0.25:
                s += self.pick('.', '\n.') + self.pick(self.fresh('p'), 'if', 'class', 'async')
            elif k < 0.35:
                s += '[' + self.expr(d + 1) + ']'
            elif k < 0.55:
                s += self.args(d)
            elif k < 0.65:
                s += '?.' + self.pick(self.fresh('p'), '[0]', '(1)')
                optional = True
            elif k < 0.72 and not optional:
                s += self.template(d)
            elif k < 0.80 and not optional and not s.startswith('super'):
                s = 'new ' + self.pick(self.use(), 'Object', 'Array') + self.args(d)
        return s

    def target(self, d):
        k = self.r.random()
        if k < 0.5:
            return self.use()
        if k < 0.7:
            return self.use() + '.' + self.fresh('p')
        if k < 0.8:
            return self.use() + '[' + self.expr(d + 1) + ']'
        return self.use()

    def unary(self, d):
        k = self.r.random()
        if k < 0.6:
            return self.chain(d)
        if k < 0.8:
            return self.pick('!', '~', 'typeof ', 'void ', '-', '+', '- ', '+ ') + self.chain(d + 1)
        if k < 0.85:
            t = self.target(d)
            return self.pick('++' + t, '--' + t, t + '++', t + '--', t + ' ++', '++ ' + t)
        if k < 0.88 and self.awt:
            return 'await ' + self.chain(d + 1)
        if k < 0.9:
            return 'import(' + self.string() + ')'
        return self.chain(d)

    def binary(self, d):
        a = self.unary(d + 1)
        k = self.r.random()
        if k < 0.5:
            return a
        if k < 0.6:
            return '(' + a + ') ** ' + self.unary(d + 1)
        if k < 0.7:
            return a + ' ' + self.pick('&&', '||') + ' ' + self.unary(d + 1)
        if k < 0.75:
            return a + ' ?? ' + self.unary(d + 1)
        ops = ['+', '-', '*', '/', '%', '<<', '>>', '>>>', '<', '>', '<=', '>=', '==', '!=', '===', '!==', '&', '|', '^', 'in', 'instanceof']
        s = a
        for _ in range(self.r.randint(1, 3)):
            s += ' ' + self.pick(*ops) + ' ' + self.unary(d + 1)
        return s

    def expr(self, d=0):
        if d > 5:
            return self.pick(self.use(), self.num(), self.string())
        k = self.r.random()
        if k < 0.35:
            return self.binary(d)
        if k < 0.45:
            return self.binary(d + 1) + ' ? ' + self.expr(d + 1) + ' : ' + self.expr(d + 1)
        if k < 0.6:
            return self.assign(d)
        if k < 0.68:
            return self.arrow(d)
        if k < 0.72:
            return '(' + self.expr(d + 1) + ', ' + self.expr(d + 1) + ')'
        if k < 0.76 and self.yld:
            return self.pick('(yield)', '(yield ' + self.unary(d + 1) + ')', '(yield* ' + self.unary(d + 1) + ')')
        return self.binary(d)

    def assign(self, d):
        k = self.r.random()
        if k < 0.15:
            return '[' + self.use() + ', ' + self.use() + '.q = 1, ...' + self.use() + '] = ' + self.unary(d + 1)
        if k < 0.25:
            return '({a: ' + self.use() + ', b: ' + self.use() + ' = 3, ...' + self.use() + '} = ' + self.unary(d + 1) + ')'
        return self.target(d) + ' ' + self.pick('=', '=', '+=', '-=', '*=', '**=', '<<=', '||=', '&&=', '??=', '|=') + ' ' + self.expr(d + 1)

    # -- statements
    def exprstmt(self, e):
        if e[0] in '{' or e.startswith('function') or e.startswith('class') or e.startswith('async function') or e.startswith('let'):
            e = '(' + e + ')'
        return e

    def stmts(self, d, n):
        out = []
        for i in range(n):
            s = self.stmt(d)
            if i and s[0] in '([`+-/':
                s = ';' + s
            out.append(s)
        return ''.join(out)

    def end(self):
        return self.pick(';', ';', ';\n', '\n', ' \n', '; // c\n', ' /* c */ \n')

    def block(self, d):
        old = self.names[:]
        s = '{ ' + self.stmts(d + 1, self.r.randint(0, 2)) + ' }'
        self.names = old
        return s

    def sub(self, d):
        return self.pick(self.block(d), self.exprstmt(self.expr(d + 1)) + ';', ';')

    def decl(self, d):
        kind = self.pick('var ', 'let ', 'const ')
        out = []
        for _ in range(self.r.randint(1, 2)):
            k = self.r.random()
            if k < 0.6:
                nm = self.fresh()
                out.append(nm + ' = ' + self.expr(d + 1))
                self.names.append(nm)
            elif k < 0.8:
                n1, n2 = self.fresh(), self.fresh()
                out.append('[' + n1 + ', ' + n2 + ' = 1, ...' + self.fresh('r') + '] = ' + self.unary(d + 1))
                self.names += [n1, n2]
            else:
                n1, n2 = self.fresh(), self.fresh()
                out.append('{' + n1 + ', a: ' + n2 + ' = 2, ...' + self.fresh('r') + '} = ' + self.unary(d + 1))
                self.names += [n1, n2]
        return kind + ', '.join(out) + self.end()

    def stmt(self, d):
        if d > 3:
            return self.exprstmt(self.expr(d)) + self.end()
        k = self.r.random()
        if k < 0.14:
            return self.decl(d)
        if k < 0.32:
            return self.exprstmt(self.expr(d + 1)) + self.end()
        if k < 0.38:
            return 'if (' + self.expr(d + 1) + ') ' + self.sub(d) + self.pick('', ' else ' + self.sub(d)) + '\n'
        if k < 0.46:
            return self.loopstmt(d)
        if k < 0.50:
            old = self.ctx(brk=True)
            s = 'switch (' + self.expr(d + 1) + ') { case ' + self.expr(d + 1) + ': ' + self.stmts(d + 1, 1) + ' break; default: ' + self.stmts(d + 1, 1) + ' }\n'
            self.restore(old)
            return s
        if k < 0.56:
            return 'try ' + self.block(d) + self.pick(' catch (' + self.fresh('e') + ') ' + self.block(d), ' catch ' + self.block(d), ' finally ' + self.block(d),
                                                       ' catch ({message}) ' + self.block(d) + ' finally ' + self.block(d)) + '\n'
        if k < 0.61:
            return self.func(d, True) + '\n'
        if k < 0.64:
            return self.cls(d, True) + '\n'
        if k < 0.68:
            return 'throw ' + self.expr(d + 1) + self.end()
        if k < 0.74 and self.ret:
            return self.pick('return', 'return ' + self.expr(d + 1), 'return\n' + self.pick('', '1')) + self.end()
        if k < 0.78:
            return self.block(d) + '\n'
        if k < 0.82:
            lab = self.fresh('L')
            old = self.ctx(brk=True)
            s = lab + ': ' + self.pick('while (false) ' + self.block(d), self.block(d) + ' ') + '\n'
            self.restore(old)
            return s
        if k < 0.84:
            return ';\n'
        if k < 0.88 and self.brk:
            return self.pick('break', 'continue' if self.loop else 'break') + self.end()
        if k < 0.89:
            return 'debugger' + self.end()
        return self.exprstmt(self.expr(d + 1)) + self.end()

    def loopstmt(self, d):
        old = self.ctx(loop=True, brk=True)
        k = self.r.random()
        v = self.fresh('i')
        body = lambda: self.pick(self.block(d), self.exprstmt(self.expr(d + 1)) + ';', ';')
        if k < 0.25:
            s = 'for (var ' + v + ' = 0; ' + v + ' < 3; ' + v + '++) ' + body()
        elif k < 0.4:
            s = 'for (let ' + v + ' in ' + self.expr(d + 1) + ') ' + body()
        elif k < 0.55:
            s = 'for (const [' + v + ', ' + self.fresh() + '] of ' + self.expr(d + 1) + ') ' + body()
        elif k < 0.62 and self.awt:
            s = 'for await (const ' + v + ' of ' + self.expr(d + 1) + ') ' + body()
        elif k < 0.8:
            s = 'while (' + self.expr(d + 1) + ') ' + body()
        elif k < 0.9:
            s = 'do ' + body() + ' while (' + self.expr(d + 1) + ')' + self.pick(';', '\n', ';\n')
        else:
            s = 'for (;;) ' + body()
        self.restore(old)
        return s + '\n'

    def program(self):
        self.names = ['a0']
        return 'var a0 = 1, undefined_ = 2;\n' + self.stmts(0, self.r.randint(3, 12))


def gen_program(seed):
    return Gen(random.Random(seed)).program()


ALPHABET = ['(', ')', '{', '}', '[', ']', ';', ',', '.', ':', '=', '+', '-', '*', '/', '<', '>', '!', '?', '&', '|', '`', '"', "'", '\\',
            '\n', ' ', '++', '--', '=>', '...', '?.', '??', 'var ', 'let ', 'function ', 'return ', 'if ', 'else ', 'for ', 'in ', 'of ',
            'async ', 'await ', 'yield ', 'class ', 'new ', 'x', '1', '/a/', '#p', '${', '0x', '1_', 'static ', 'get ', ' ', '/*', '*/', '//']


def mutate(rnd, src):
    n = len(src)
    if n == 0:
        return src
    k = rnd.random()
    i = rnd.randrange(n)
    if k < 0.2:
        return src[:i] + src[i + 1:]
    if k < 0.45:
        return src[:i] + rnd.choice(ALPHABET) + src[i:]
    if k < 0.65:
        return src[:i] + rnd.choice(ALPHABET) + src[i + 1:]
    if k < 0.75 and i + 1 < n:
        return src[:i] + src[i + 1] + src[i] + src[i + 2:]
    if k < 0.85:
        return src[:i] + src[i:i + rnd.randint(1, 6)] * 2 + src[i + 1:]
    if k < 0.93:
        return src[:i]
    # move a whole line end: delete a newline or insert one
    j = src.find('\n', i)
    if j < 0:
        return src + '\n'
    return src[:j] + src[j + 1:] if rnd.random() < 0.5 else src[:i] + '\n' + src[i:]


def write(path, text):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def run_driver(driver, files):
    """The verdict of the parser under test (1, 0) for each file: the driver prints `FILE 1|0` lines."""
    import subprocess
    res = {}
    for i in range(0, len(files), 200):
        out = subprocess.run([driver] + files[i:i + 200], capture_output=True).stdout.decode('utf-8', 'replace')
        for line in out.split('\n'):
            if ' ' in line:
                f, v = line.rsplit(' ', 1)
                res[f] = int(v) if v in ('0', '1') else None
    return res


# A text that holds `await` or `yield` is allowed to be accepted where V8 refuses it: the grammar reads them as an operator
# wherever the operand that follows could not be a name's neighbour, since it does not know whether a function is async
# or a generator (CONTEXTS-style limit, README.md).
LOOSE_OK = re.compile(r'\b(await|yield)\b')


def compare(driver, d, prefix):
    import glob
    files = sorted(glob.glob('%s/%s*.js' % (d, prefix)))
    res = run_driver(driver, files)
    agree = loose = strict = design = unknown = known = 0
    bad = []
    for f in files:
        ref = open(f[:-3] + '.ref').read().strip()
        v = res.get(f)
        if v is None:
            bad.append('no verdict: ' + f)
        elif ref == 'L':
            if v == 1:
                design += 1
            else:
                unknown += 1
        elif str(v) == ref:
            agree += 1
        elif v == 1:
            with open(f, encoding='utf-8', errors='replace', newline='') as fh:
                if LOOSE_OK.search(fh.read()):
                    known += 1
                else:
                    loose += 1
                    bad.append('hbnf accepts, V8 refuses: ' + f)
        else:
            strict += 1
            bad.append('hbnf refuses, V8 accepts: ' + f)
    print('js-diff: %s: %d agree, %d hbnf looser, %d hbnf stricter; %d looser for await or yield outside a function that has them; '
          'V8 early errors (left out by design): %d accepted, %d refused' % (prefix, agree, loose, strict, known, design, unknown))
    for b in bad[:10]:
        print(b)
    return not bad


def main(argv):
    cmd = argv[1]
    if cmd == 'compare':
        ok = compare(argv[2], argv[3], argv[4])
        sys.stdout.flush()
        os._exit(0 if ok else 1)
    if cmd == 'check':
        for p in argv[2:]:
            try:
                with open(p, 'rb') as f:
                    text = f.read().decode('utf-8')
            except (UnicodeDecodeError, OSError):
                print(p, 'U')            # not UTF-8 text: V8 would be given a different text from the parser's
                continue
            print(p, verdict(text))
    elif cmd == 'gen':
        n, seed, d = int(argv[2]), int(argv[3]), argv[4]
        os.makedirs(d, exist_ok=True)
        bad = 0
        for i in range(n):
            src = gen_program(seed * 1000003 + i)
            v = verdict(src)
            if v != '1':
                bad += 1            # the generator's own mistake: written as it is, with V8's verdict, like a mutation
            write('%s/g%04d.js' % (d, i), src)
            write('%s/g%04d.ref' % (d, i), v)
        sys.stderr.write("oracle.py gen: %d programs, %d that V8 refuses (generator mistakes, left in)\n" % (n, bad))
    elif cmd == 'mut':
        n, seed, d = int(argv[2]), int(argv[3]), argv[4]
        os.makedirs(d, exist_ok=True)
        rnd = random.Random(seed)
        for i in range(n):
            src = gen_program(seed * 1000003 + rnd.randrange(10 ** 6))
            for _ in range(rnd.choice((1, 1, 1, 2))):
                src = mutate(rnd, src)
            write('%s/m%04d.js' % (d, i), src)
            write('%s/m%04d.ref' % (d, i), verdict(src))
    elif cmd == 'ids':
        d = argv[2]
        os.makedirs(d, exist_ok=True)
        ctx = MiniRacer()
        ctx.eval("""
        function ok(s) { try { new Function(s); return 1; } catch (e) { return 0; } }
        function scan(lo, hi, pre, post) {
          var out = [];
          for (var c = lo; c < hi; c++) {
            if (c >= 0xD800 && c <= 0xDFFF) { out.push(2); continue; }
            out.push(ok(pre + String.fromCodePoint(c) + post));
          }
          return out.join('');
        }""")
        ref = []
        texts = []
        for lo in range(0x80, 0x110000, 0x10000):
            hi = min(lo + 0x10000, 0x110000)
            first = ctx.eval("scan(%d, %d, 'var ', '')" % (lo, hi))
            later = ctx.eval("scan(%d, %d, 'var a', '')" % (lo, hi))
            ref.append((first, later))
        out_ref = []
        with open(d + '/ids.in', 'wb') as fin:
            for (first, later), lo in zip(ref, range(0x80, 0x110000, 0x10000)):
                for k in range(len(first)):
                    c = lo + k
                    if 0xD800 <= c <= 0xDFFF:
                        continue
                    ch = chr(c).encode('utf-8')
                    fin.write(b'var ' + ch + b'\0var a' + ch + b'\0')
                    out_ref.append(first[k])
                    out_ref.append(later[k])
        with open(d + '/ids.ref', 'w') as fr:
            fr.write(''.join(out_ref))
    else:
        sys.stderr.write(__doc__)
        sys.exit(2)
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)           # py_mini_racer can hang when the interpreter shuts down


if __name__ == '__main__':
    main(sys.argv)
