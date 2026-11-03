"""tests/graphql-diff.sh's reference: a second reading of the October 2021 specification's lexical grammar
(sections 2.1 to 2.9), written as a hand-made scanner and not from graphql.hbnf, with just enough of the
syntax (`{ name(name: value ...) }`, values with variables, lists and objects) to ask about a value.

    python3 -I oracle.py N SEED FILE     writes N documents `{ a(x: S) }` to FILE, NUL-separated, S a random run
                                         of the pieces below, and FILE.ref, a line of 1 (valid) or 0 each.

No GraphQL library is installed to ask, so this is the only other opinion; it covers numbers (`01`, `1.`,
`1e`, `0x`, a name or a dot after a number), strings (escapes, a line end, `""` followed by `"`), block
strings (an escaped three quotes, and the first unescaped three quotes ends one), comments, commas and the
byte order mark."""
import random, sys

class Err(Exception):
    pass

def lex(t):
    i, n, out = 0, len(t), []
    def source(c): return c in '\t\n\r' or '\x20' <= c
    while i < n:
        c = t[i]
        if c in ' \t\n\r,﻿':
            i += 1; continue
        if c == '#':
            while i < n and t[i] not in '\n\r':
                if not source(t[i]): raise Err('control character')
                i += 1
            continue
        if t.startswith('...', i):
            out.append(('p', '...')); i += 3; continue
        if c in '!$&():=@[]{|}':
            out.append(('p', c)); i += 1; continue
        if c == '_' or 'A' <= c <= 'Z' or 'a' <= c <= 'z':
            j = i + 1
            while j < n and (t[j] == '_' or (t[j].isascii() and t[j].isalnum())): j += 1
            out.append(('name', t[i:j])); i = j; continue
        if c == '-' or '0' <= c <= '9':
            j = i + 1 if c == '-' else i
            if j >= n or not '0' <= t[j] <= '9': raise Err('a minus sign needs a digit')
            if t[j] == '0':
                j += 1
            else:
                while j < n and '0' <= t[j] <= '9': j += 1
            if j + 1 < n and t[j] == '.' and '0' <= t[j + 1] <= '9':
                j += 1
                while j < n and '0' <= t[j] <= '9': j += 1
            if j < n and t[j] in 'eE':
                k = j + 1
                if k < n and t[k] in '+-': k += 1
                if k < n and '0' <= t[k] <= '9':
                    while k < n and '0' <= t[k] <= '9': k += 1
                    j = k
            if j < n and (t[j] == '.' or t[j] == '_' or '0' <= t[j] <= '9' or (t[j].isascii() and t[j].isalpha())):
                raise Err('a number is followed by a digit, a dot or a name')
            out.append(('num', t[i:j])); i = j; continue
        if c == '"':
            if t.startswith('"""', i):
                j = i + 3
                while True:
                    if j >= n: raise Err('unterminated block string')
                    if t.startswith('\\"""', j): j += 4; continue
                    if t.startswith('"""', j): j += 3; break
                    if not source(t[j]): raise Err('control character')
                    j += 1
                out.append(('str', 0)); i = j; continue
            if t.startswith('""', i):
                out.append(('str', 0)); i += 2; continue
            j = i + 1
            while True:
                if j >= n: raise Err('unterminated string')
                d = t[j]
                if d == '"': break
                if d in '\n\r' or not source(d): raise Err('bad character in a string')
                if d == '\\':
                    e = t[j + 1] if j + 1 < n else ''
                    if e == 'u':
                        h = t[j + 2:j + 6]
                        if len(h) != 4 or any(x not in '0123456789abcdefABCDEF' for x in h): raise Err('bad \\u')
                        j += 6
                    elif e and e in '"\\/bfnrt':
                        j += 2
                    else:
                        raise Err('bad escape')
                else:
                    j += 1
            out.append(('str', 0)); i = j + 1; continue
        raise Err('no token starts with this character')
    return out

def valid(t):
    try:
        toks = lex(t)
    except Err:
        return False
    pos = [0]
    def peek(): return toks[pos[0]] if pos[0] < len(toks) else ('eof', '')
    def take(k, v=None):
        tk = peek()
        if tk[0] != k or (v is not None and tk[1] != v): raise Err('parse')
        pos[0] += 1
    def value():
        k, v = peek()
        if k in ('num', 'str', 'name'):
            pos[0] += 1
        elif (k, v) == ('p', '$'):
            pos[0] += 1; take('name')
        elif (k, v) == ('p', '['):
            pos[0] += 1
            while peek() != ('p', ']'): value()
            pos[0] += 1
        elif (k, v) == ('p', '{'):
            pos[0] += 1
            while peek() != ('p', '}'):
                take('name'); take('p', ':'); value()
            pos[0] += 1
        else:
            raise Err('value')
    try:
        take('p', '{'); take('name'); take('p', '(')
        while True:
            take('name'); take('p', ':'); value()
            if peek() == ('p', ')'): break
        take('p', ')'); take('p', '}')
        return pos[0] == len(toks)
    except Err:
        return False

PIECES = ['"', '""', '"""', '\\', '\\"', '\\"""', 'u', 'u00e9', '0', '1', '7', '.', 'e', 'E', '-', '+', 'a', '_', ' ', '\n',
          '\r', '\t', '[', ']', ',', '#', '{', '}', 'é', 'true', 'null', '$', 'x', '00', '1.5', '1e5', ':', '"a"',
          '"""b"""', '\x01', '﻿', 'F', '@']

if __name__ == '__main__':
    n, seed, path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    random.seed(seed)
    docs = ['{ a(x: ' + ''.join(random.choice(PIECES) for _ in range(random.randint(1, 9))) + ') }' for _ in range(n)]
    with open(path, 'wb') as f:
        f.write(b'\0'.join(d.encode('utf-8') for d in docs) + b'\0')
    with open(path + '.ref', 'w') as f:
        f.write(''.join('1\n' if valid(d) else '0\n' for d in docs))
