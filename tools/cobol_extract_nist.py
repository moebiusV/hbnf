#!/usr/bin/env python3
"""cobol_extract_nist.py NEWCOB.VAL EXEC85.CONF OUT-DIR

Writes the programs of the NIST COBOL-85 validation suite (newcob.val, fixed format, public domain) as free-format files in OUT-DIR,
named after the module (NC101A.cob).  The suite is a template: its members begin with a `*HEADER,COBOL,NAME` card and end at `*END-OF`,
the tokens XXXXXnnn stand for what an implementor chooses, and GnuCOBOL's own configuration (tests/cobol85/EXEC85.conf.in, which
EXEC85 reads) says what to put there and replaces a few lines of 17 programs (a `*START NAME` section: each line carries a six-digit
sequence number and takes the place of the line with that number).  This does the same two things, then converts the fixed format as
tools/cobol_extract.py does.  The members of the copy library (`*HEADER,CLBRY`) are not programs and are not written.
With a fourth argument FIXED-DIR the programs are also written there as they are, in the fixed reference format (substitutions and
patches done, the columns kept): what corpus/cobol/cobol-fixed.hbnf reads.
Prints how many programs were written."""
import os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
sys.argv, args = sys.argv[:1], sys.argv[1:]
exec(open(os.path.join(here, 'cobol_extract.py')).read().split('def main')[0])

def read_conf(path):
    subs, patches, cur = {}, {}, None
    for l in open(path, errors='replace').read().split('\n'):
        m = re.match(r'X-(\d\d\d)73\s+(.*?)\s*$', l)
        if m and cur is None:
            subs['XXXXX' + m.group(1)] = m.group(2)
            continue
        m = re.match(r'\*START\s+(\S+)', l)
        if m:
            cur = m.group(1); patches.setdefault(cur, [])
        elif l.startswith('*END-UPDATE'):
            cur = None
        elif cur and re.match(r'\d{6}', l):
            patches[cur].append(l)
    return subs, patches

def members(path):
    cur = None
    for l in open(path, errors='replace').read().split('\n'):
        m = re.match(r'\*HEADER,(\w+),(\S+)', l)
        if m:
            if cur: yield cur
            cur = [m.group(1), m.group(2).strip(), []]
        elif cur is not None:
            if l.startswith('*END-OF'):
                yield cur; cur = None
            else:
                cur[2].append(l)
    if cur: yield cur

def main():
    val, conf, dst = args[:3]
    fixed_dir = args[3] if len(args) > 3 else None
    os.makedirs(dst, exist_ok=True)
    if fixed_dir:
        os.makedirs(fixed_dir, exist_ok=True)
    subs, patches = read_conf(conf)
    wrote = 0
    for kind, name, lines in members(val):
        if kind != 'COBOL':
            continue
        if patches.get(name):
            by = {l[:6]: l for l in lines}
            for p in patches[name]:
                by[p[:6]] = p
            lines = [by[s] for s in sorted(by)]
        text = '\n'.join(lines)
        for k, v in subs.items():
            text = text.replace(k, v)
        if fixed_dir:
            # the suite marks lines in column 7 with letters (S, C, P, Y ...) that its configuration decides about; as the free
            # conversion does, they are read as blanks, so that the indicator is one a compiler knows
            fx = []
            for l in text.split('\n'):
                l = l.expandtabs(8)
                if len(l) > 6 and l[6] not in ' */-Dd':
                    l = l[:6] + ' ' + l[7:]
                fx.append(l)
            with open(os.path.join(fixed_dir, name + '.cob'), 'w') as f:
                f.write('\n'.join(fx) + '\n')
        free = to_free(text.split('\n'))
        if free is None:
            print('cobol_extract_nist: %s has a continuation line that cannot be joined' % name, file=sys.stderr)
            continue
        with open(os.path.join(dst, name + '.cob'), 'w') as f:
            f.write('\n'.join(free) + '\n')
        wrote += 1
    print('cobol_extract_nist: %d programs written to %s' % (wrote, dst))

main()
