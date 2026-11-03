#!/usr/bin/env python3
"""cobol_extract.py TESTSUITE.SRC-DIR OUT-DIR

Writes each COBOL program embedded in GnuCOBOL's autotest files (AT_DATA([name.cob], [...])) as a free-format file in
OUT-DIR, named after the test file and the program's number in it.  The tests are fixed format (a sequence area,
an indicator column, the text from column 8 to 72); the conversion is the reference format's own: the first seven
columns go, a `*` or `/` in column 7 makes a comment line, a `D` makes a debugging line (also dropped), and nothing
after column 72 is read.  A tab goes to the next multiple of 8 columns first; a continuation line (`-` in column 7) is joined to the
line before it, and when that line ends inside a nonnumeric literal, which runs through column 72, the literal goes on after the
quote that opens the continuation.  A program with a `>>SOURCE FORMAT` directive that changes the format in it is left out (it is the
case a switch of grammar is for), as is one that has a continuation the rules above cannot join; one with `>>SOURCE FORMAT FREE`
only, and one that the tests compile with -free, is copied as it is.
Prints how many were written and how many left out, and why."""
import os, re, sys

QUAD = [('@<:@', '['), ('@:>@', ']'), ('@%:@', '#'), ('@&t@', ''), ('@{:@', '('), ('@:}@', ')'), ('@S|@', '$')]

def unquad(s):
    for a, b in QUAD:
        s = s.replace(a, b)
    return s

def blocks(text):
    """(name, body, tail) for each AT_DATA([name], [body]): m4 quotes are balanced [ ]."""
    for m in re.finditer(r'AT_DATA\(\[([^\]]+)\],\s*\[', text):
        i = m.end(); depth = 1
        while i < len(text) and depth:
            c = text[i]
            if c == '[': depth += 1
            elif c == ']': depth -= 1
            i += 1
        body = text[m.end():i - 1]
        end = text.find('AT_CLEANUP', i)
        yield m.group(1), body, text[i:end if end >= 0 else i + 4000]

def open_quote(text):
    """The quote character of a nonnumeric literal that `text` leaves open, or ''."""
    q = ''
    for c in text:
        if q:
            if c == q:
                q = ''
        elif c in '"\'':
            q = c
    return q

def to_free(lines):
    out = []
    for l in lines:
        l = l.rstrip('\n').expandtabs(8)
        ind = l[6] if len(l) > 6 else ' '
        if ind in '*/' or ind in 'Dd':
            out.append('')
        elif ind == '-':
            c = l[7:72].lstrip()
            prev = next((i for i in range(len(out) - 1, -1, -1) if out[i].strip()), None)
            if prev is None:
                return None
            q = open_quote(out[prev])
            if q:
                # the literal runs through column 72: pad the line before, then go on after the opening quote
                if not c.startswith(q):
                    return None
                out[prev] = out[prev].ljust(72) + c[1:]
                out[prev + 1:] = []
            else:
                out.append('       ' + c)
        else:
            out.append('       ' + l[7:72] if len(l) > 7 else '')
    return out

def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    wrote = 0; left = {}
    for fn in sorted(os.listdir(src)):
        if not fn.endswith('.at'):
            continue
        text = open(os.path.join(src, fn), errors='replace').read()
        n = 0
        for name, body, tail in blocks(text):
            if not re.search(r'\.(cob|cbl|CBL|COB)$', name.strip()):
                continue
            n += 1
            body = unquad(body)
            lines = body.split('\n')
            if lines and lines[0].strip() == '':
                lines = lines[1:]
            why = None
            fmts = re.findall(r'>>\s*SOURCE\s+(?:FORMAT\s+)?(?:IS\s+)?(\w+)', body, re.I)
            if any(f.upper() != 'FREE' for f in fmts):
                why = 'source directive'
            free = bool(re.search(r'-free\b|-fformat=free|\$COMPILE_ONLY.*-F\b', tail)) or bool(fmts)
            if why is None and not free:
                conv = to_free(lines)
                if conv is None:
                    why = 'continuation line'
                else:
                    lines = conv
            if why:
                left[why] = left.get(why, 0) + 1
                continue
            base = fn[:-3]
            with open(os.path.join(dst, '%s-%03d.cob' % (base, n)), 'w') as f:
                f.write('\n'.join(lines) + '\n')
            wrote += 1
    print('cobol_extract: %d programs written to %s; left out: %s' % (wrote, dst, ', '.join('%d %s' % (v, k) for k, v in sorted(left.items())) or 'none'))

main()
