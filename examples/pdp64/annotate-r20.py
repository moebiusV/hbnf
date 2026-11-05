#!/usr/bin/env python3
"""One-time conversion for the r20 grammar (build/pdp64.hbnf of the pdp64 repository): roles for the fields of `insn`
and a %title for each alternative of its body.   annotate-r20.py IN.hbnf OUT.hbnf"""
import re, sys

ROLE = {'len': 'len', 'opc': 'opcode', 'reg': 'reg', 'low': 'low', 'rm': 'reg', 'rx': 'reg', 'rd': 'reg', 'r': 'reg', 't': 'reg',
        's': 'scale', 'd': 'disp', 'p': 'disp', 'sub': 'sub', 'pad': 'pad', 'count': 'imm', 'imm': 'imm', 'pos': 'imm',
        'width': 'imm', 'n': 'imm', 'sr': 'imm', 'x': 'imm', 'cond': 'cond', 'more': 'more'}
TITLES = ['Memory operand, len = 0 (low is a register)', 'Memory operand, base modes', 'Memory operand, indexed',
          'Memory operand, direct page', 'Memory operand, wide modes (pc-relative, immediate, absolute)',
          'BESC RORI: a count in the low byte', 'BESC bit-field operations (position and width in parcel 2)',
          'BESC, MBLK, AESC, FESC, ATOM: sub-opcode and registers', 'MESC: sub-opcode, register and displacement',
          'Conditional branch, len = 0 (8-bit displacement in reg:low)', 'Branch, SOB, TAG: 16 or 32 bit displacement',
          'SYS, len = 0', 'SYS PROBER/PROBEW: a register', 'SYS TRAPL: a vector number', 'SYS: a payload parcel',
          'cbCC: 5-bit immediate and displacement', 'MFSR/MTSR: system register and general register',
          'Page 2: one parcel, nothing follows', 'cbW: wide immediate and displacement', 'cbRR: condition and displacement',
          'SYSX: sub-opcode']
src = open(sys.argv[1]).read()
i = src.index('insn = ')
head, body = src[:i], src[i:]
body = re.sub(r'\b(len|opc|reg|low|rm|rx|rd|r|t|s|d|p|sub|pad|count|imm|pos|width|n|sr|x|cond|more):(\d+s?|bits\((?:[^()]|\([^()]*\))*\))',
              lambda m: m.group(0) + ' %' + ROLE[m.group(1)] + '("' + m.group(1) + '")', body)
# an alternative begins at `|` (or the first after `body:(`) with its guard; its fields end at the next alternative
lines = body.split('\n')
alts = [k for k, l in enumerate(lines) if re.match(r'\s*(\|\s*)?\?\(', l)]
if len(alts) != len(TITLES):
    sys.exit('annotate-r20: %d alternatives, %d titles' % (len(alts), len(TITLES)))
for n, k in enumerate(alts):
    lines[k] = lines[k].rstrip() + ' %title("' + TITLES[n] + '")'
open(sys.argv[2], 'w').write(head + '\n'.join(lines))
