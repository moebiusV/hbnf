#!/usr/bin/env python3
"""A reference for corpus/algol60/algol60.hbnf: the Report's own BNF (corpus/algol60/
syntax.txt) read by an independent Earley recognizer.

  reference.py gen N SEED DIR      write N random sentences of the Report to DIR/g*.a60
  reference.py mut N SEED DIR      write N mutated sentences to DIR/m*.a60 and, beside
                                   each, DIR/m*.ref saying 1 (the Report accepts) or 0
Sentences are token lists; identifiers, numbers and strings are pools of spellings.
Four lines of syntax.txt are transcription slips and are fixed here (the stray
`<factor>` alternative, `letter>`, the identifier and number productions, which
become tokens).  Nothing here knows hbnf."""
import re, sys, random, os

HERE = os.path.dirname(os.path.abspath(__file__))
SYNTAX = os.path.join(HERE, "../../corpus/algol60/syntax.txt")

def load():
    lines = open(SYNTAX, encoding="utf-8").read().split("\n")
    prods, cur = [], None
    for ln in lines[2:]:
        s = ln.strip()
        if not s:
            continue
        if "::=" in s:
            cur = [s]; prods.append(cur)
        elif cur is not None:
            cur.append(s)
    g = {}
    tok = re.compile(r"<[A-Za-z][A-Za-z ]*>|'[A-Z]+'|:=|[()\[\],;:+\-*/×÷<≤=≥>≠.]|[A-Za-z]+")
    for p in prods:
        text = " ".join(p)
        lhs, rhs = text.split("::=", 1)
        lhs = lhs.strip()
        alts = []
        for a in re.split(r"\s\|\s|\s\|$", " " + rhs + " "):
            alts.append(tok.findall(a))
        g[lhs] = alts
    # the fixes: tokens for the lexical level, and the transcription slips
    for n in ["<letter>", "<digit>", "<identifier>", "<unsigned integer>", "<letter string>",
              "<unsigned number>", "<decimal number>", "<decimal fraction>", "<exponential part>",
              "<integer>", "<string>", "<open string>", "<proper string>", "<basic symbol>",
              "<delimiter>", "<operator>", "<arithmetic operator>", "<logical operator>",
              "<sequential operator>", "<separator>", "<bracket>", "<declarator>",
              "<specificator>", "<logical value>"]:
        g.pop(n, None)
    g["<identifier>"] = [["ID"]]
    g["<letter string>"] = [["LS"]]
    g["<unsigned number>"] = [["NUM"], ["UINT"]]
    g["<string>"] = [["STR"]]
    g["<logical value>"] = [["'TRUE'"], ["'FALSE'"]]
    g["<label>"] = [["<identifier>"], ["UINT"]]
    g["<factor>"] = [["<primary>"], ["<factor>", "'POWER'", "<primary>"]]
    g["<procedure body>"] = [["<statement>"]]            # <code> is not read
    g["<empty>"] = [[]]
    # syntax.txt drops the closing ; of the second <specification part> alternative
    g["<specification part>"] = [["<empty>"], ["<specifier>", "<identifier list>", ";"],
                                 ["<specification part>", "<specifier>", "<identifier list>", ";"]]
    g["<basic statement>"] = g["<basic statement>"]
    return g

G = load()
START = "<program>"
def isnt(x): return x.startswith("<") and x.endswith(">") and len(x) > 2 and x[1].isalpha()

# ---- Earley ----
def nullable_set():
    nul = set(); ch = True
    while ch:
        ch = False
        for n, alts in G.items():
            if n not in nul and any(all(s in nul for s in a) for a in alts):
                nul.add(n); ch = True
    return nul
NUL = nullable_set()

def accepts(toks):
    # Report 2.3: `end` followed by any sequence of symbols without `;`, `end` or
    # `else` is the same as `end`.
    t2, i = [], 0
    while i < len(toks):
        t2.append(toks[i])
        if toks[i] == "'END'":
            i += 1
            while i < len(toks) and toks[i] not in (";", "'END'", "'ELSE'"):
                i += 1
        else:
            i += 1
    toks = t2
    n = len(toks)
    S = [dict() for _ in range(n + 1)]
    def add(i, item, q):
        if item not in S[i]:
            S[i][item] = True; q.append(item)
    q = []
    for ai, a in enumerate(G[START]):
        add(0, (START, ai, 0, 0), q)
    for i in range(n + 1):
        q = list(S[i])
        while q:
            lhs, ai, dot, org = q.pop()
            rhs = G[lhs][ai]
            if dot < len(rhs):
                s = rhs[dot]
                if isnt(s):
                    if s not in G: continue
                    for bi in range(len(G[s])):
                        add(i, (s, bi, 0, i), q)
                    if s in NUL:
                        add(i, (lhs, ai, dot + 1, org), q)
                elif i < n and toks[i] == s:
                    S[i + 1][(lhs, ai, dot + 1, org)] = True
            else:
                for (l2, a2, d2, o2) in list(S[org]):
                    r2 = G[l2][a2]
                    if d2 < len(r2) and r2[d2] == lhs:
                        add(i, (l2, a2, d2 + 1, o2), q)
    return any(l == START and d == len(G[l][a]) and o == 0 for (l, a, d, o) in S[n])

# ---- generation ----
random.seed(1)
MIN = {}
def minsize():
    INF = 10 ** 9
    for n in G: MIN[n] = INF
    ch = True
    while ch:
        ch = False
        for n, alts in G.items():
            for a in alts:
                v = sum(1 if not isnt(s) else MIN.get(s, INF) for s in a)
                v = min(v, INF)
                if v < MIN[n]: MIN[n] = v; ch = True
minsize()
IDS = ["a", "b", "x", "y", "i", "n", "foo", "bar", "t1", "q2"]
NUMS = ["2.5", ".5", "10E3", "1.5E-2", "3E+1", "0.25"]
def derive(n, budget, out):
    alts = G[n]
    cost = lambda a: sum(1 if not isnt(s) else MIN[s] for s in a)
    ok = [a for a in alts if cost(a) <= budget] or [min(alts, key=cost)]
    if budget < 12: ok = [min(alts, key=cost)] if random.random() < .7 else ok
    a = random.choice(ok)
    share = max(1, (budget - cost(a)) // max(1, sum(1 for s in a if isnt(s)) or 1))
    for s in a:
        if isnt(s): derive(s, MIN[s] + share, out)
        else: out.append(s)
def sentence(budget=40):
    out = []
    derive(START, budget, out)
    return out

REND = {"×": "*", "÷": "'DIV'", "≤": "<=", "≥": ">=", "≠": "<>"}
def render(toks):
    r = []
    for t in toks:
        if t == "ID": r.append(random.choice(IDS))
        elif t == "LS": r.append(random.choice(["a", "foo", "bar"]))
        elif t == "UINT": r.append(random.choice(["1", "42", "7"]))
        elif t == "NUM": r.append(random.choice(NUMS))
        elif t == "STR": r.append('"s t"')
        else: r.append(REND.get(t, t))
    return " ".join(r)

WORDY = {"ID", "UINT", "NUM", "LS"}
def merged(t):
    # The Report gives blanks no significance (2.3), even inside a name or a number:
    # `i b` is the identifier ib.  The reference reads tokens, so skip those.
    return any(a in WORDY and b in WORDY for a, b in zip(t, t[1:]))

ALL = sorted({s for a in G.values() for al in a for s in al if not isnt(s)} - {"LS"})
def mutate(t):
    t = list(t); k = random.choice(["del", "dup", "swap", "ins", "rep"])
    if len(t) < 3: return t
    i = random.randrange(len(t))
    if k == "del": del t[i]
    elif k == "dup": t.insert(i, t[i])
    elif k == "swap" and i + 1 < len(t): t[i], t[i + 1] = t[i + 1], t[i]
    elif k == "ins": t.insert(i, random.choice(ALL))
    else: t[i] = random.choice(ALL)
    return t

if __name__ == "__main__":
    mode, n, seed, d = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    random.seed(seed); os.makedirs(d, exist_ok=True)
    i = 0
    while i < n:
        s = sentence(random.choice([12, 25, 40, 70]))
        if mode == "gen":
            if len(s) > 400: continue
            open(f"{d}/g{i:05d}.a60", "w").write(render(s) + "\n")
        else:
            m = mutate(s)
            if len(m) > 300 or merged(m): continue
            open(f"{d}/m{i:05d}.a60", "w").write(render(m) + "\n")
            open(f"{d}/m{i:05d}.ref", "w").write("1" if accepts(m) else "0")
            open(f"{d}/m{i:05d}.tok", "w").write(" ".join(m) + "\n")
        i += 1
