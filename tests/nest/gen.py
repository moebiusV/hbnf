#!/usr/bin/env python3
"""gen.py DIR N SEED: N files in DIR, each some statements of tests/nest/trie.hbnf, a third of them with a token
dropped, doubled or replaced."""
import os, random, sys
d, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
random.seed(seed)
stmts = ["fr 1 os 2 to 3", "fr 1 os 2", "fr 1 to 3", "fr 1", "k 1 : v 2 !", "k 1 : v 2", "k 1 = v 2", "k 1",
         "kk 1 : vv 2 !", "kk 1 : vv 2", "kk 1 = vv 2",
         "a 1 b 2 c 3", "a 1 b 2 d 3", "a 1 e 2", "a 1", "b 1 c 2"]
toks = ["fr", "os", "to", "k", "kk", "v", "vv", ":", "=", "!", "a", "b", "c", "d", "e", ";", "7", "8"]
os.makedirs(d, exist_ok=True)
for i in range(1, n + 1):
    parts = []
    for _ in range(random.randint(1, 5)):
        parts += random.choice(stmts).split() + [";"]
    if random.random() < 0.35:
        k = random.randrange(len(parts))
        r = random.random()
        if r < 0.33: del parts[k]
        elif r < 0.66: parts.insert(k, parts[k])
        else: parts[k] = random.choice(toks)
    open(os.path.join(d, "c%d.txt" % i), "w").write(" ".join(parts))
