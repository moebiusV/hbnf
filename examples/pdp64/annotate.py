#!/usr/bin/env python3
"""One-time conversion: add layout annotations (LAYOUT.md) to the leaf rules of a pdp64 prefix-coded encoding grammar.

    annotate.py IN.hbnf OUT.hbnf

The roles are read from the names the pdp64 grammars already give their fields (o1-r, o2-base, o1-d, o3-pcrel, sub, ...),
the title and the sub-opcode note from the form's sub-FORM-K rule.  After this the annotations live in the grammar, which
is the only place they are kept; this script is not part of any build.
"""
import re, sys

ROLE = {'r': 'reg', 'base': 'reg', 'index': 'reg', 'scale': 'scale', 'd': 'disp', 'pcrel': 'disp', 'abs': 'disp',
        'stride': 'disp', 'imm': 'imm', 'imm0': 'imm', 'sp': 'prefix'}


def main(src, dst):
    lines = open(src).read().split('\n')
    # the mnemonic lists: sub-X-K = "a" | "b" ... (continued on indented lines)
    subs, i = {}, 0
    while i < len(lines):
        m = re.match(r'^sub-(\S+) =', lines[i])
        if m:
            j, body = i, lines[i]
            while j + 1 < len(lines) and lines[j + 1][:1] in ' \t':
                j += 1
                body += ' ' + lines[j]
            subs[m.group(1)] = re.findall(r'"([^"]+)"', body)
            i = j
        i += 1
    out = []
    for ln in lines:
        m = re.match(r'^leaf-(\S+) = (.*)$', ln)
        if not m:
            out.append(ln)
            continue
        name, rest = m.groups()
        mns = subs.get(name, [])
        note = ' '.join(mns)
        toks, res = rest.split(' '), []
        k = 0
        while k < len(toks):
            t = toks[k]
            k += 1
            if t.startswith('?('):                      # a check: may hold blanks up to its closing paren
                while t.count('(') > t.count(')') and k < len(toks):
                    t += ' ' + toks[k]
                    k += 1
                res.append(t)
            elif re.fullmatch(r'0b[01]+', t):
                res.append(t + ' %prefix')
            elif re.fullmatch(r'x?sub(?:-\d+)?:\d+', t):
                res.append(t + ' %sub("' + re.sub(r'-\d+','',t.split(':')[0]) + '"' + (' "' + note + '"' if note else '') + ')')
            else:
                mm = re.fullmatch(r'o(\d+)-([a-z0-9]+)(?:-(\d+))?:(\d+)(s?)', t)
                if mm and mm.group(2) in ROLE:
                    idx, part, piece, w, sg = mm.groups()
                    lab = part + idx
                    res.append(t + ' %' + ROLE[part] + '("' + lab + '")')
                else:
                    res.append(t)
        title = '%s: %s%s' % (name, ' '.join(mns[:4]), ' ...' if len(mns) > 4 else '')
        out.append('leaf-%s = %s %%title("%s")' % (name, ' '.join(res), title))
    open(dst, 'w').write('\n'.join(out))


main(sys.argv[1], sys.argv[2])
