#!/usr/bin/env python3
"""Random `#if` / `#elif` programs for tests/cpp.sh: python3 tools/cpp_fuzz.py SEED CHUNKS DIR [GROUPS_PER_CHUNK].
Each file DIR/N.c defines a few macros and has conditional groups (if, if/else, if/elif/else, ifdef/elif) whose expressions are made of the
operators of 6.10.1, character and integer constants (signed and unsigned), macros, undefined names and `defined`; the group that is taken
is the one whose identifier comes out, so a wrong value shows.  The right side of `/` and `%` is `(x | 1)` and a shift count is `(x & 7)`
so that gcc does not stop; where it does anyway (an overflow it counts as an error) the chunk is left out."""
import random, sys
seed=int(sys.argv[1]); nchunk=int(sys.argv[2]); out=sys.argv[3]
random.seed(seed)
consts=['0','1','2','3','7','10','255','0x10','010','1u','2UL','0xffffffffffffffffu','18446744073709551615u','9223372036854775807','4294967296','-1','-2','\'a\'','\'\\n\'','\'\\0\'','\'\\x41\'']
macros={'A':'1','B':'0','C':'(3+4)','D':'-5','E':'0x7f','F':'1u','G':'(A&&!B)','H':'100'}
undefined=['U','V','W']
def expr(d=0):
    k=random.random()
    if d>3 or k<0.25:
        r=random.random()
        if r<0.35: return random.choice(consts)
        if r<0.7: return random.choice(list(macros))
        if r<0.8: return random.choice(undefined)
        if r<0.9: return 'defined(%s)'%random.choice(list(macros)+undefined)
        return 'defined %s'%random.choice(list(macros)+undefined)
    if k<0.4: return random.choice(['!','~','-','+'])+expr(d+1)
    if k<0.5: return '(%s)'%expr(d+1)
    if k<0.6: return '%s ? %s : %s'%(expr(d+1),expr(d+1),expr(d+1))
    op=random.choice(['||','&&','|','^','&','==','!=','<','<=','>','>=','<<','>>','+','-','*','/','%'])
    if op in ('/','%'): return '%s %s (%s | 1)'%(expr(d+1),op,expr(d+1))
    if op in ('<<','>>'): return '%s %s (%s & 7)'%(expr(d+1),op,expr(d+1))
    return '%s %s %s'%(expr(d+1),op,expr(d+1))
chunks=[]
for c in range(nchunk):
    L=[]
    for k,v in macros.items(): L.append('#define %s %s'%(k,v))
    for g in range(int(sys.argv[4]) if len(sys.argv) > 4 else 15):
        form=random.choice(['plain','else','elif','elif2','ifdef-elif'])
        t='t%d_%d'%(c,g)
        if form=='plain': L+= ['#if '+expr(), t+'a;', '#endif']
        elif form=='else': L+= ['#if '+expr(), t+'a;', '#else', t+'b;', '#endif']
        elif form=='elif': L+= ['#if '+expr(), t+'a;', '#elif '+expr(), t+'b;', '#else', t+'c;', '#endif']
        elif form=='elif2': L+= ['#if '+expr(), t+'a;', '#elif '+expr(), t+'b;', '#elif '+expr(), t+'c;', '#endif']
        else: L+= [random.choice(['#ifdef ','#ifndef '])+random.choice(list(macros)+undefined), t+'a;', '#elif '+expr(), t+'b;', '#else', t+'c;', '#endif']
    chunks.append('\n'.join(L)+'\n')
for i,ch in enumerate(chunks): open('%s/%d.c'%(out,i),'w').write(ch)
