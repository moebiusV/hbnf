#!/usr/bin/env python3
"""The oracle for corpus/css/css.hbnf: tinycss2 (the structure of CSS Syntax 3: tokens, rules, declarations, nested
rules) and soupsieve (Selectors 4) are asked about the same text.  A style sheet is conforming here when
  * tinycss2 reports no parse error at any level (the rules, the declarations of every block, the tokens of every value),
  * every block, string, comment and url is closed (tinycss2 recovers silently at the end of the text: `unclosed` below
    scans for the brackets, quotes and comments left open),
  * a `!` in a value is the one of `!important`, and an ordinary property's value holds no `{}` block (CSS Nesting reads
    such a declaration as a rule),
  * the prelude of every style rule is a selector soupsieve compiles.
Mutations that soupsieve accepts only because :is() and :where() forgive an entry that is no selector are verdict 2 too.
soupsieve is stricter than the syntax about what a name means (an unknown pseudo-class or a pseudo-element is an error
for it, `:has()` takes no complex selector in its strict mode): those refusals are verdict 2, "for what it means".

  oracle.py gen N SEED DIR     write N random conforming style sheets to DIR/g*.css (every at-rule, value function and
                               selector the grammar knows)
  oracle.py mut N SEED DIR     write N mutated ones to DIR/m*.css and, beside each, DIR/m*.ref: 1 the oracle accepts it,
                               0 it refuses it, 2 it refuses it for what it means (either answer of the grammar is right)
  oracle.py check FILE...      print "FILE 1|0|2" for each
  oracle.py selectors FILE...  print "FILE 1|0|2" for each, the file's text being a selector list (soupsieve alone)
  oracle.py cpt DIR OUT        write the cases of css-parsing-tests (the JSON files in DIR) to OUT/NAME.ROOT.in (the
                               inputs, a NUL after each) and OUT/NAME.ROOT.exp (1 where the expected parse holds no
                               error node, else 0); one line "NAME ROOT" per job on the standard output
  oracle.py cpt-report OUT EXPECT   read OUT/NAME.ROOT.out (the parser's 1 or 0 for each case), print the tally, and
                               compare the cases where the grammar and the JSON differ with the file EXPECT
  oracle.py real DIR FILE      fetch the style sheets FILE lists ("sha256 url" lines) into DIR if they are not there, check
                               their hashes, and print their paths
  oracle.py sel-cases FILE OUT write the selector corpus FILE (lines "G O selector") as OUT.in (NUL separated)
  oracle.py sel-report FILE OUT.out   compare the parser's answers with the G column
Nothing here knows hbnf."""
import os, random, re, sys

MEANING = re.compile(r"Pseudo-element|unsupported or invalid|strict rules|Invalid syntax for pseudo class|is not a valid"
                     r"|Malformed pseudo|was detected as a pseudo-class|custom selector")

def structure(text):
    """(errors, preludes) of a style sheet by tinycss2: the number of parse errors at every level, and the
    preludes of the style rules with whether each is nested."""
    import tinycss2
    n = [0, False]
    def bad(x, why=""):
        n[0] += 1
        if os.environ.get("ORACLE_DEBUG"): print("  %s %s" % (why or getattr(x, "message", x.type), x), file=sys.stderr)
    def values(nodes, top, custom):
        for x in nodes:
            t = x.type
            if t == "error": bad(x)
            elif top and t == "literal" and x.value in ("!", ";"): bad(x, "top-level " + x.value)
            elif top and t == "{} block" and not custom: bad(x, "a block in a value")
            elif t in ("() block", "[] block", "{} block"): values(x.content, False, custom)
            elif t == "function": values(x.arguments, False, custom)
    def contents(content, rel, sel):
        nodes = tinycss2.parse_blocks_contents(content, skip_comments=True, skip_whitespace=True)
        for k, d in enumerate(nodes):
            if d.type == "error": bad(d)
            elif d.type == "declaration":
                values(d.value, True, d.name.startswith("--"))
                v = [x for x in d.value if x.type not in ("whitespace", "comment")]
                if d.name.startswith("--") and len(v) > 1 and v[0].type == "{} block": bad(d, "a custom property that starts with a block holds nothing else")
                # tinycss2 ends a declaration at its {} block; the grammar wants the ; or } that ends it
                if d.name.startswith("--") and len(v) == 1 and v[0].type == "{} block" and k + 1 < len(nodes):
                    toks = [x for x in content if x.type not in ("whitespace", "comment")]
                    for i, x in enumerate(toks):
                        if x.type == "{} block" and i >= 2 and toks[i - 1].type == "literal" and toks[i - 1].value == ":" \
                           and toks[i - 2].type == "ident" and toks[i - 2].value.startswith("--") \
                           and i + 1 < len(toks) and not (toks[i + 1].type == "literal" and toks[i + 1].value == ";"):
                            n[1] = True
            else: rule(d, rel, sel)
    def rule(r, rel, sel):
        if r.type == "error": bad(r); return
        values(r.prelude, False, True)
        if r.type == "qualified-rule":
            if r.content is None or not [p for p in r.prelude if p.type not in ("whitespace", "comment")]: bad(r, "rule without block or prelude")
            elif sel is not None: sel.append((tinycss2.serialize(r.prelude).strip(), rel))
            if r.content is not None: contents(r.content, True, sel)
        elif r.content is not None:
            contents(r.content, rel, None if r.lower_at_keyword.endswith("keyframes") else sel)
    sel = []
    for r in tinycss2.parse_stylesheet(text, skip_comments=True, skip_whitespace=True):
        rule(r, False, sel)
    return n[0], sel, n[1]

def unclosed(t):
    """True when the text ends inside a comment, a string, an unquoted url or a ( [ { that is not closed."""
    st = []; i = 0; n = len(t)
    while i < n:
        c = t[i]
        if t.startswith("/*", i):
            j = t.find("*/", i + 2)
            if j < 0: return True
            i = j + 2; continue
        if c == "\\": i += 2; continue
        if c in "\"'":
            i += 1
            while i < n and t[i] != c:
                i += 2 if t[i] == "\\" else 1
            if i >= n: return True
            i += 1; continue
        if t[i:i + 4].lower() == "url(" and not (i and (t[i - 1].isalnum() or t[i - 1] in "-_\\" or ord(t[i - 1]) > 127)) and not re.match(r"url\([ \t\r\n\f]*[\"']", t[i:i + 40], re.I):
            j = i + 4
            while j < n and t[j] != ")":
                j += 2 if t[j] == "\\" else 1
            if j >= n: return True
            i = j + 1; continue
        if c in "([{": st.append(")]}"["([{".index(c)])
        elif st and c == st[-1]: st.pop()
        i += 1
    return bool(st)

def verdict(b, forgiving=False):
    try:
        text = b.decode("utf-8")
    except UnicodeDecodeError:
        return 0
    if b[:3] == b"\xef\xbb\xbf" or "\x00" in text:
        return 0
    dbg = os.environ.get("ORACLE_DEBUG")
    e, sel, odd = structure(text)
    if e:
        if dbg: print("  tinycss2: %d parse errors" % e, file=sys.stderr)
        return 0
    if unclosed(text):                                  # something was left open
        if dbg: print("  left open", file=sys.stderr)
        return 0
    import soupsieve
    meaning = odd or bool(re.search(r"!(?:\s|/\*.*?\*/)*[A-Za-z]*\\", text, re.S))   # !impor\\tant: an escaped keyword, which the grammar does not read

    for p, rel in sel:
        # a comment is white space: the selector must compile as written and with each comment made a space (soupsieve
        # reads some selectors with a comment wrongly)
        plain = re.sub(r"/\*.*?\*/", " ", p, flags=re.S)
        forms = [p, plain]
        if rel:                                         # a nested prelude's items may begin with one combinator
            forms = [",".join(re.sub(r"^\s*[>+~]\s*", "", i) for i in f.split(",")) for f in forms]
        for f in forms:
            try:
                soupsieve.compile(f.replace("||", ">"))     # the column combinator is only soupsieve's to refuse
                # :is() and :where() forgive an entry that is no selector; the grammar does not
                if forgiving and re.search(r":(is|where|matches)\(", f, re.I): meaning = True
            except Exception as ex:
                if dbg: print("  soupsieve: %r: %s" % (f, str(ex).split("\n")[0]), file=sys.stderr)
                if MEANING.search(str(ex)): meaning = True
                else: return 0
    return 2 if meaning else 1

def sel_verdict(b):
    import soupsieve
    try:
        text = b.decode("utf-8")
        soupsieve.compile(text.strip())
        return 1
    except UnicodeDecodeError:
        return 0
    except Exception as ex:
        return 2 if MEANING.search(str(ex)) else 0

# ---- the generator ----
class Gen:
    def __init__(s, rnd, special):
        s.r = rnd; s.special = special; s.depth = 0
    def pick(s, *xs): return s.r.choice(xs)
    def ws(s): return s.pick(" ", " ", " ", "\n", "  ", "\t", " /* c */ ", "\n\t")
    def ows(s): return s.pick("", "", " ", "\n", "/* c */", " /**/ ")
    def ident(s):
        w = s.pick("a", "b", "foo", "bar-baz", "x1", "_u", "-v", "é", "Ü", "c\\41 d", "e\\.f", "\\31 0", "--k", "-webkit-box", "font-size", "color", "margin", "grid-area", "x-y-z")
        return w
    def name(s): return s.pick("a", "b", "div", "span", "p", "ul", "li", "h1", "x-foo", "É")
    def number(s): return s.pick("0", "1", "-1", "+2", "1.5", ".5", "-.5", "10", "1e3", "1E-3", "2.5e+2", "100")
    def dim(s): return s.number() + s.pick("px", "em", "rem", "vh", "deg", "s", "ms", "x", "fr", "Q", "e3x")
    def string(s):
        body = s.pick("", "a b", "x\\\"y", "it's", "\\27 s", "a\\\nb", "é", "\\0041", "/* no */", "{;}")
        return '"' + body + '"' if "\"" not in body.replace('\\"', '') else "'" + body + "'"
    def url(s): return s.pick("url(a.png)", "url( a.png )", "url(\"a b.png\")", "url('x')", "url(data:image/png;base64,AAA=)", "url()", "URL(x)")
    def hash(s): return s.pick("#fff", "#a1b2c3", "#-x", "#_y", "#é", "#12")
    def simple(s):
        k = s.r.randrange(12)
        if k < 3: return s.ident()
        if k < 5: return s.number()
        if k < 7: return s.dim()
        if k == 7: return s.number() + "%"
        if k == 8: return s.string()
        if k == 9: return s.hash()
        if k == 10: return s.url()
        return s.pick(",", "/", "*", "+ ", "- ", ":", "=", ">", "<", "~", "|", "&", "%", "?")
    def value(s, n=None, depth=0):
        out = []
        for _ in range(s.r.randrange(1, 5) if n is None else n):
            k = s.r.randrange(10)
            if k == 0 and depth < 2: out.append(s.ident() + "(" + s.ows() + s.value(depth=depth + 1) + s.ows() + ")")
            elif k == 1 and depth < 2: out.append("(" + s.ows() + s.value(depth=depth + 1) + ")")
            elif k == 2 and depth < 2: out.append("[" + s.value(depth=depth + 1) + "]")
            elif s.special and k == 3: out.append(s.special_value())
            else: out.append(s.simple())
        return s.ws().join(out) if s.r.random() < 0.8 else " ".join(out)
    def special_value(s):
        k = s.r.randrange(8)
        n = s.number; d = s.dim
        if k == 0: return "calc(" + d() + " + " + d() + ")"
        if k == 1: return "calc((" + d() + " * 2 - 10%) / " + n() + ")"
        if k == 2: return "min(" + d() + ", " + d() + ", calc(100% - " + d() + "))"
        if k == 3: return "clamp(" + d() + ", " + n() + "vw, " + d() + ")"
        if k == 4: return "var(--" + s.name() + (", " + s.value(1) if s.r.random() < 0.5 else "") + ")"
        if k == 5: return "rgb(" + n() + " " + n() + " " + n() + (" / " + n() + "%" if s.r.random() < 0.5 else "") + ")"
        if k == 6: return "hsla(" + n() + ", " + n() + "%, " + n() + "%, " + n() + ")"
        return "env(safe-area-inset-top, " + d() + ")"
    # selectors
    def anb(s): return s.pick("odd", "even", "3", "-3", "2n+1", "2n + 1", "n", "-n+3", "+n", "-2n - 1", "4N", "n- 1", "+3n")
    def attr(s):
        a = "[" + s.ows() + s.pick("", "*|", "|", "ns|") * 0 + s.ident()
        if s.r.random() < 0.7:
            v = s.pick(s.ident(), s.string())
            a += s.ows() + s.pick("=", "~=", "|=", "^=", "$=", "*=") + s.ows() + v
            if s.r.random() < 0.3: a += s.pick(" i", " s", " I") if not v.startswith(('"', "'")) else s.pick("i", " i", " s")
        return a + s.ows() + "]"
    def piece(s, depth):
        k = s.r.randrange(11)
        if k < 2: return "." + s.ident()
        if k < 3: return "#" + s.ident()
        if k < 5: return s.attr()
        if k < 7: return ":" + s.pick("hover", "first-child", "last-child", "root", "empty", "only-child", "checked", "disabled", "enabled", "link", "focus", "first-of-type")
        if depth > 1: return "." + s.ident()
        if k == 7: return ":" + s.pick("not", "is", "where") + "(" + s.ows() + s.sel_list(depth + 1) + s.ows() + ")"
        if k == 8: return ":has(" + s.ows() + (s.pick("", ">", "+", "~") + s.ows() + s.compound(9) if s.r.random() < 0.8 else s.compound(9)) + s.ows() + ")"
        if k == 9: return ":" + s.pick("nth-child", "nth-last-child") + "(" + s.ows() + s.anb() + (" of " + s.sel_list(depth + 1) if s.r.random() < 0.3 else "") + s.ows() + ")"
        return ":" + s.pick("nth-of-type", "nth-last-of-type") + "(" + s.ows() + s.anb() + s.ows() + ")"
    def compound(s, depth):
        out = ""
        if s.r.random() < 0.6: out += s.pick(s.name(), "*", s.name(), "*|" + s.name(), s.name() + "|" + s.name())
        for _ in range(s.r.randrange(0 if out else 1, 3)): out += s.piece(depth)
        return out
    def complex(s, depth, rel=False):
        out = ""
        if rel and s.r.random() < 0.7: out += s.pick(">", "+", "~") + s.ows() + (" " if s.r.random() < 0.5 else "")
        out += s.compound(depth)
        for _ in range(s.r.randrange(0, 3)):
            out += s.pick(s.ws(), s.ows() + ">" + s.ows(), s.ows() + "+" + s.ows(), s.ows() + "~" + s.ows()) if True else ""
            out += s.compound(depth)
        return out
    def sel_list(s, depth=0, rel=False, nested=False):
        items = []
        for _ in range(s.r.randrange(1, 3)):
            if nested and depth == 0 and s.r.random() < 0.4:
                c = s.pick("&", "&:hover", "&.x", "& " + s.compound(1), "&" + s.pick(">", " + ") + s.compound(1), s.compound(1) + " &", "> " + s.compound(1), "~" + s.compound(1))
            else: c = s.complex(depth, rel)
            items.append(c)
        return (s.ows() + "," + s.ows()).join(items)
    # structure
    def decl(s):
        r = s.r.random()
        imp = s.pick("", "", "", " !important", "!important", " ! important", " !IMPORTANT")
        if r < 0.15:
            if s.r.random() < 0.3: return "--" + s.name() + s.ows() + ":" + s.ows() + s.pick("{a:b}", "{ " + s.value() + "; }", "{}") + s.ows()
            return "--" + s.name() + s.ows() + ":" + s.ows() + s.pick("", s.value(), "[" + s.value() + "]", s.string()) + imp
        return s.pick("color", "margin", "font-size", "-webkit-box-flex", "x\\31 y", "Ü", "grid-area", "b") + s.ows() + ":" + s.ows() + s.value() + imp
    def block(s, depth, rel=True):
        items = []
        for _ in range(s.r.randrange(0, 4)):
            if depth < 2 and s.r.random() < 0.25: items.append(s.rule(depth + 1, rel))
            else: items.append(s.decl() + s.pick(";", ";", ";" + s.ws()))
        if items and s.r.random() < 0.3 and not items[-1].endswith(("}",)): items[-1] = items[-1].rstrip().rstrip(";")
        return "{" + s.ows() + s.ws().join(items) + s.ows() + "}"
    def rule(s, depth=0, nested=False):
        r = s.r.random()
        if s.special and r < 0.35: return s.at_special(depth, nested)
        if r < 0.45: return "@" + s.pick("foo", "-x-bar", "font-face", "page", "property", "counter-style", "scope", "starting-style") + s.pick(" ", " x ", " :first ", " --k ") + (s.block(depth, nested) if s.r.random() < 0.7 else ";")
        return s.sel_list(0, rel=nested, nested=nested) + s.ows() + s.block(depth)
    def mq(s):
        return s.pick("screen", "print and (min-width: 100px)", "(400px <= width <= 700px)", "not all and (monochrome)", "(min-aspect-ratio: 16/9)",
                      "only screen and (orientation: landscape), print", "(width >= 600px) and (height < 2em)", "((color) or (grid)) and (not (hover))", "all")
    def at_special(s, depth, nested):
        k = s.r.randrange(10)
        inner = lambda: "{" + s.ows() + (s.rule(depth + 1, nested) if not nested else s.decl() + ";") + s.ows() + "}"
        if k == 0: return "@media " + s.mq() + s.ows() + inner()
        if k == 1: return "@supports " + s.pick("(display: grid)", "not (display: grid)", "(a: b) and (c: d)", "selector(a > b)", "((a: b) or (c: d))") + s.ows() + inner()
        if k == 2: return "@container " + s.pick("(min-width: 400px)", "card (min-width: 400px)", "style(--x: 1)", "not (width < 1px)") + s.ows() + inner()
        if k == 3: return "@layer " + s.pick("a", "a.b, c", "") + s.pick(";", " " + inner())
        if k == 4 and not nested: return "@keyframes " + s.pick("x", '"y"') + " { from { a: b } " + s.pick("50%", "to") + " { c: d } }"
        if k == 5 and not nested: return "@import " + s.pick('"a.css"', "url(a.css)", 'url("a.css")') + s.pick("", " layer", " layer(x.y)", " supports(display: grid)", " screen and (min-width: 1px)") + ";"
        if k == 6 and not nested: return "@namespace " + s.pick("", "svg ") + s.pick('"http://x"', "url(http://x)") + ";"
        if k == 7 and not nested: return "@charset \"utf-8\";"
        return "@media " + s.mq() + s.ows() + inner()
    def sheet(s):
        items = []
        if s.special and s.r.random() < 0.2: items.append('@charset "utf-8";')
        for _ in range(s.r.randrange(1, 6)): items.append(s.rule(0))
        sep = lambda: s.pick("\n", " ", "\n\n", " /* c */\n", "<!-- ", " --> ")
        out = s.ows()
        for it in items: out += it + sep()
        return out

# ---- css-parsing-tests (Simon Sapin's, https://github.com/SimonSapin/css-parsing-tests): JSON files of an input and the expected tree ----
# NAME, the grammar's root, how the input is wrapped, and whether a case that expects an error is a test of that root
# (a root takes a list, so "exactly one rule" is not its business)
CPT = [("stylesheet", "stylesheet", "%s", True), ("rule_list", "stylesheet", "%s", True), ("one_rule", "stylesheet", "%s", False),
       ("declaration_list", "declaration-list", "%s", True), ("one_declaration", "declaration-list", "%s", False),
       ("component_value_list", "component-value-list", "%s", True), ("one_component_value", "component-value-list", "%s", False),
       ("blocks_contents", "stylesheet", "x{%s}", True), ("An+B", "selector-list", ":nth-child(%s)", True)]

def has_error(x):
    if isinstance(x, list):
        return (len(x) >= 1 and x[0] == "error") or any(has_error(i) for i in x)
    return False

def cpt_load(d, name):
    import json
    j = json.load(open("%s/%s.json" % (d, name), encoding="utf-8"))
    return [(j[i], j[i + 1]) for i in range(0, len(j), 2) if isinstance(j[i], str)]

def cpt_cases(d, out):
    os.makedirs(out, exist_ok=True)
    for name, root, wrap, err_ok in CPT:
        cases = cpt_load(d, name)
        # An+B expects null for an invalid one, every other file an error node
        exp = [0 if (e is None if name == "An+B" else has_error(e)) else 1 for _, e in cases]
        with open("%s/%s.%s.in" % (out, name, root), "wb") as f:
            for i, _ in cases:
                # the input stream is preprocessed (CSS Syntax 3.3): U+0000 is U+FFFD (and a C string ends at a NUL)
                f.write((wrap % i).replace("\0", "�").encode("utf-8", "surrogatepass") + b"\0")
        with open("%s/%s.%s.exp" % (out, name, root), "w") as f:
            f.write("".join(map(str, exp)))
        print(name, root)

def cpt_report(out, expect):
    want = set()
    for l in open(expect):
        w = l.split("#")[0].split()
        if len(w) >= 2: want.add(w[0] + " " + w[1])
    got = set(); tally = []
    for name, root, wrap, err_ok in CPT:
        exp = open("%s/%s.%s.exp" % (out, name, root)).read().strip()
        res = open("%s/%s.%s.out" % (out, name, root)).read().strip()
        a = r = da = dr = skip = 0
        for k, (e, v) in enumerate(zip(exp, res)):
            if e == "0" and not err_ok: skip += 1; continue
            if e == v:
                if v == "1": a += 1
                else: r += 1
            else:
                got.add("%s %d" % (name, k))
                if v == "1": da += 1
                else: dr += 1
        tally.append((name, len(exp), a, r, da, dr, skip))
    print("css-parsing-tests: %-22s %5s %8s %8s %10s %10s %8s" % ("file", "cases", "both ok", "both err", "we accept", "we refuse", "skipped"))
    for t in tally: print("css-parsing-tests: %-22s %5d %8d %8d %10d %10d %8d" % t)
    print("css-parsing-tests: (we accept: the tree holds an error node and the grammar accepts; we refuse: it holds none and the grammar refuses)")
    new, gone = sorted(got - want), sorted(want - got)
    for x in new: print("css-parsing-tests: NEW difference " + x)
    for x in gone: print("css-parsing-tests: listed difference gone " + x)
    return 0 if not new and not gone else 1

def real(d, f):
    import hashlib, urllib.request
    os.makedirs(d, exist_ok=True)
    for l in open(f):
        if l[0] == "#" or not l.strip(): continue
        h, u = l.split()
        p = "%s/%s.css" % (d, h[:16])
        if not os.path.exists(p):
            data = urllib.request.urlopen(u, timeout=60).read()
            if hashlib.sha256(data).hexdigest() != h: sys.exit("css-diff: FAIL (%s has not the pinned sha256)" % u)
            open(p, "wb").write(data)
        print(p)

def sel_lines(f):
    for l in open(f, encoding="utf-8"):
        l = l.rstrip("\n")
        if not l or l[0] == "#": continue
        g, o, sel = l[0], l[2], l[4:]
        sel = re.sub(r"\\(x[0-9a-f]{2}|.)", lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1)) or (chr(int(m.group(1)[1:], 16)) if m.group(1)[0] == "x" else m.group(1)), sel)
        yield g, o, sel

def sel_cases(f, out):
    with open(out + ".in", "wb") as o:
        for g, _, sel in sel_lines(f): o.write(sel.replace("\0", "\ufffd").encode("utf-8") + b"\0")

def sel_report(f, out):
    res = open(out).read().strip()
    bad = differ = n = 0
    for (g, o, sel), v in zip(sel_lines(f), res):
        n += 1
        if (g == "+") != (v == "1"): bad += 1; print("css-diff: selector verdict changed: want %s got %s: %r" % (g, v, sel))
        if (g == "+") != (o == "+"): differ += 1
    print("css-diff: soupsieve's own test selectors: %d, the grammar differs from soupsieve on %d (an unknown pseudo-class, a pseudo-element, a form only soupsieve has, an end of text inside a construct)" % (n, differ))
    return 1 if bad or n != len(res) else 0

ALPHABET = list("{}()[];:,.#@!+-*/\\\"'<>=~|&^$%_ \n\tab1é") + ["/*", "*/", "!important", "url(", "--", "\\"]

def mutate(rnd, t):
    for _ in range(rnd.choice([1, 1, 1, 2])):
        if not t: break
        op = rnd.randrange(6)
        i = rnd.randrange(len(t))
        if op == 0: t = t[:i] + t[i + 1:]
        elif op == 1: t = t[:i] + rnd.choice(ALPHABET) + t[i:]
        elif op == 2: t = t[:i] + rnd.choice(ALPHABET) + t[i + 1:]
        elif op == 3 and i + 1 < len(t): t = t[:i] + t[i + 1] + t[i] + t[i + 2:]
        elif op == 4: t = t[:i] + t[i] + t[i:]
        else: t = t[:i]
    return t

def main(argv):
    cmd = argv[1]
    if cmd == "check":
        for f in argv[2:]:
            print(f, verdict(open(f, "rb").read()))
    elif cmd == "cpt":
        cpt_cases(argv[2], argv[3])
    elif cmd == "cpt-report":
        sys.exit(cpt_report(argv[2], argv[3]))
    elif cmd == "real":
        real(argv[2], argv[3])
    elif cmd == "sel-cases":
        sel_cases(argv[2], argv[3])
    elif cmd == "sel-report":
        sys.exit(sel_report(argv[2], argv[3]))
    elif cmd == "selectors":
        for f in argv[2:]:
            print(f, sel_verdict(open(f, "rb").read()))
    elif cmd in ("gen", "mut"):
        n, seed, d = int(argv[2]), int(argv[3]), argv[4]
        os.makedirs(d, exist_ok=True)
        rnd = random.Random(seed)
        for i in range(n):
            g = Gen(rnd, special=(cmd == "gen"))
            t = g.sheet()
            if cmd == "mut":
                t = mutate(rnd, t)
                with open("%s/m%d.ref" % (d, i), "w") as f:
                    f.write("%d\n" % verdict(t.encode("utf-8"), forgiving=True))
            with open("%s/%s%d.css" % (d, "g" if cmd == "gen" else "m", i), "w", encoding="utf-8") as f:
                f.write(t)
    else:
        sys.exit(__doc__)

if __name__ == "__main__":
    main(sys.argv)
