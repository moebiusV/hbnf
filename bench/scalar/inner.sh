#!/bin/sh
# inner.sh -- inside the glibc container: make the numbers, build fast_float and the benchmark, run it.  /w is the repository
# (read-only), /o the work directory.  Prints nb.c's lines.
set -u
cd /o
python3 /w/bench/formats/gen.py json 2000000 > doc.json
python3 - <<'PY'
import json, random, struct
random.seed(3)
t = open('doc.json').read()
ints, flts = [], []
json.loads(t, parse_int=lambda s: (ints.append(s), 0)[1], parse_float=lambda s: (flts.append(s), 0)[1])
open('ints.txt', 'w').write('\n'.join(ints)); open('floats.txt', 'w').write('\n'.join(flts))
open('mid17.txt', 'w').write('\n'.join('%.17g' % (random.uniform(1, 1000) * 10 ** random.randint(-5, 8)) for _ in range(200000)))
out = []
while len(out) < 200000:
    d = struct.unpack('<d', struct.pack('<Q', random.getrandbits(64)))[0]
    if d == d and abs(d) < 1e308 and d != 0: out.append('%.17g' % d)
open('rand17.txt', 'w').write('\n'.join(out))
PY
cp /w/bench/cache/scalar/fast_float.h .
g++ -O2 -std=c++17 -c /w/bench/scalar/ff.cpp -I. -o ff.o
gcc -O2 -std=gnu11 -I/w/runtime -c /w/bench/scalar/nb.c -o nb.o
g++ nb.o ff.o -o nb
for i in 1 2 3; do ./nb /o > run$i.txt; done
cat run1.txt run2.txt run3.txt
