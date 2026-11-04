#!/usr/bin/env python3
"""The oracle for corpus/xml/xml.hbnf: Python's xml.parsers.expat, which checks well-formedness (not
validity), plus the one lexical rule of Namespaces in XML that expat leaves to a namespace-aware layer.

  oracle.py gen N SEED DIR    write N random well-formed documents to DIR/g*.xml
  oracle.py mut N SEED DIR    write N mutated documents to DIR/m*.xml and, beside each, DIR/m*.ref:
                              1 if the oracle accepts it, 0 if it refuses it, L if expat refuses it
                              for a reason the grammar does not check (see LOOSE)
  oracle.py check FILE...     print "FILE 1", "FILE 0" or "FILE L" for each
  oracle.py names DIR         write DIR/names.in, the documents <Xb/> and <aXb/> for every code point X
                              (documents separated by NUL), and DIR/names.ref, one 1 or 0 for each: whether
                              the Fifth Edition's NameStartChar, or NameChar, includes X.  This does not ask
                              expat: its tables are the Fourth Edition's.

The document is given to expat as text (so a declared encoding is not used), with all of expat's own checks
on: a repeated attribute, a character reference to a character that is not a Char, an entity that is not
declared (unless an external subset or a parameter-entity reference may have declared it, or standalone="yes"
says it did not), an external or unparsed entity in an attribute value, an unparsed one in content.  The names of elements, attributes, declarations, entities, notations and
instruction targets must be QNames, [prefix ":"] local with both parts NCNames; expat reads a Name, where
colons are ordinary.

LOOSE are the checks of expat that the grammar does not make (corpus/xml/README.md, "Not checked"): the
encoding declaration (the document is text here, so expat never reads the declared name), and the text of an
entity, which expat reads when the entity is used and the grammar does not read at all (an entity that
recurs, one whose text is not balanced markup).  For a document that expat refuses for one of them, the
verdict is L: the grammar may accept it, and should not be asked to refuse it."""
import os, random, re, sys
import xml.parsers.expat as ex

START = ("A-Za-z_À-ÖØ-öø-˿Ͱ-ͽͿ-῿‌-‍"
         "⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�\U00010000-\U000EFFFF")
CONT = START + "0-9.·̀-ͯ‿-⁀-"
NCNAME = "[%s][%s]*" % (START, CONT)
QNAME = re.compile("(%s:)?%s\\Z" % (NCNAME, NCNAME))
NC = re.compile("%s\\Z" % NCNAME)

LOOSE = ("unknown encoding", "incorrect encoding", "asynchronous entity")
# and an error in the text of an entity that is used: see verdict


def model_names(m, out):
    # (type, quantifier, name, children)
    if m[2]:
        out.append(m[2])
    for c in m[3]:
        model_names(c, out)


NAME_START = re.compile("[%s]" % START)
NAME_ONLY = re.compile("[%s]" % CONT)


_expat_takes = {}


def expat_takes(c, first):
    k = (c, first)
    if k not in _expat_takes:
        p = ex.ParserCreate()
        try:
            p.Parse("<%s%s/>" % ("" if first else "a", c), True)
            _expat_takes[k] = True
        except ex.ExpatError:
            _expat_takes[k] = False
    return _expat_takes[k]


def fold(t):
    """expat's name tables are the Fourth Edition's, which differ from the Fifth in 937,000 code points (nearly
    all above U+FFFF).  Outside ASCII, a character that the Fifth Edition takes as the start of a name and expat
    does not is given to expat as a CJK ideograph (the same character for the same code point, almost), and one
    that the Fifth Edition takes only inside a name and expat does not as an Arabic-Indic digit.  That changes
    whether a document is well formed nowhere but in a name, and the names are checked against the Fifth
    Edition's ranges by `names`.  The XML declaration is left as it is (its words are ASCII)."""
    def one(c):
        if c < "\x80":
            return c
        if NAME_START.match(c):
            return c if expat_takes(c, True) else chr(0x4E00 + ord(c) % 20000)
        if NAME_ONLY.match(c):
            return c if expat_takes(c, False) else chr(0x0660 + ord(c) % 10)
        return c
    m = re.match("<\\?xml[ \t\r\n].*?\\?>", t, re.S)
    head = m.group(0) if m else ""
    return head + "".join(map(one, t[len(head):]))


REF = re.compile("&([^&;#]*);")


def ref_names(s):
    return REF.findall(s)


def tag_text(t, i):
    """the start tag that begins at byte i of t (quote-aware)"""
    q = None
    j = i
    while j < len(t):
        c = t[j]
        if q:
            if c == q:
                q = None
        elif c in b"\"'":
            q = c
        elif c == 0x3E:
            break
        j += 1
    return t[i:j]


def verdict(b, again=True, foreign=False):
    """(1|0|L, message).  `foreign` is for the second look at a document with parameter-entity references (below)."""
    try:
        t = b.decode("utf-8")
        t = fold(t[1:] if t.startswith("\ufeff") else t)   # a byte order mark is the encoding's, expat takes it off bytes
    except UnicodeDecodeError:
        return "0", "not UTF-8"
    seen = []
    p = ex.ParserCreate()
    if foreign:
        p.UseForeignDTD(True)
    p.SetParamEntityParsing(ex.XML_PARAM_ENTITY_PARSING_NEVER)

    def qn(*names):
        for n in names:
            seen.append((n, True))

    def nc(*names):
        for n in names:
            seen.append((n, False))
    span = []
    p.StartDoctypeDeclHandler = lambda n, sysid, pubid, subset: (qn(n), in_dtd.append(1), span.append(p.CurrentByteIndex))
    tb = t.encode("utf-8")

    def start(n, a):
        qn(n)
        qn(*a)
        nc(*ref_names(tag_text(tb, p.CurrentByteIndex).decode("utf-8", "replace")))
    p.StartElementHandler = start
    p.ElementDeclHandler = lambda n, m: (qn(n), [qn(x) for x in (lambda o: (model_names(m, o), o)[1])([])])
    p.AttlistDeclHandler = lambda e, a, ty, d, r: (
        qn(e, a), nc(*ref_names(d or "")), nc(*(ty[9:-1].split("|") if ty.startswith("NOTATION(") else [])))
    internal = set()      # the general entities declared with a replacement text (the first declaration counts)
    external = set()

    def entity_decl(n, pe, v, b, s_, pub, nd):
        nc(n.lstrip("%")), nc(*ref_names(v or "")), nc(*([nd] if nd else []))
        if not pe and n not in internal and n not in external:
            (internal if v is not None else external).add(n)
    p.EntityDeclHandler = entity_decl
    p.NotationDeclHandler = lambda n, b, s, pub: nc(n)
    p.ProcessingInstructionHandler = lambda t, d: nc(t)
    p.SkippedEntityHandler = lambda n, pe: nc(n.lstrip("%"))
    pes = []
    in_dtd = []

    def default(d):
        # a parameter-entity reference: expat reports no declaration after one (it may have changed them)
        if in_dtd and re.match("%[^\\s;]+;\\Z", d):
            pes.append((p.CurrentByteIndex, len(d.encode("utf-8")), d[1:-1]))
    p.DefaultHandlerExpand = default      # (DefaultHandler would stop expat expanding the internal entities)
    p.EndDoctypeDeclHandler = lambda: (in_dtd.clear(), span.append(p.CurrentByteIndex))
    try:
        p.Parse(t, True)
    except ex.ExpatError as e:
        msg = str(e)
        if any(m in msg for m in LOOSE):
            return "L", msg
        # an error that expat finds in the replacement text of an entity when it is used (a reference to an entity
        # that is not declared, a character reference to a character out of range, a `<` in an attribute value, an
        # unparsed entity ...) is reported at the reference to that entity; the grammar does not read the text
        # of an entity, so it may accept such a document
        if "recursive" in msg or "undefined entity" in msg:      # the grammar walks the texts of the entities for these
            return "0", msg
        if internal and again and not in_dtd:        # (an error in the DOCTYPE itself is the grammar's)
            # with the text of every entity made harmless: if expat then accepts the document, the error was in that text
            t2 = re.sub("(<!ENTITY[ \t\r\n]+[^%\\s]+[ \t\r\n]+)(\"[^\"]*\"|'[^']*')", lambda m: m.group(1) + '"x"', t)
            if verdict(t2.encode("utf-8", "surrogatepass"), False)[0] == "1":
                return "L", msg + " (in the text of an entity)"
        return "0", msg
    # expat says nothing at all of an ATTLIST that defines no attribute, not even its name
    if len(span) == 2:
        dtd = tb[span[0]:span[1]].decode("utf-8", "replace")
        dtd = re.sub("<!--.*?-->|<\\?.*?\\?>", "", dtd, flags=re.S)       # not the text of a comment or an instruction
        seen += [(n, True) for n in re.findall("<!ATTLIST[ \t\r\n]+([^\\s>]+)[ \t\r\n]*>", dtd)]
    for n, q in seen + [(n, False) for _, _, n in pes]:
        if not (QNAME if q else NC).match(n):
            return "0", "not a QName: " + n
    if pes and again:
        # the declarations after a reference were not reported: ask again with the references taken out (and an
        # external subset supposed, since the references were what made an undeclared entity no error)
        for i, n, _ in reversed(pes):
            tb = tb[:i] + b" " * n + tb[i + n:]
        return verdict(tb, False, True)
    return "1", ""


# ---- documents ----------------------------------------------------------------------------------
LETTERS = "abcdefgxyz"
UNI = ["é", "ñ", "ß", "日本", "Ω", "ключ", "\u00b7", "\u0301", "\u203f", "\U00010400", "\u2070"]


def ncname(r):
    n = r.choice(LETTERS) + "".join(r.choice(LETTERS + "0123456789-_.") for _ in range(r.randint(0, 3)))
    if r.random() < 0.15:
        n = r.choice(UNI[:3] + UNI[4:6] + UNI[9:]) + n
    if r.random() < 0.08:
        n += r.choice(UNI)
    return n


def qname(r, prefixes):
    return (r.choice(prefixes) + ":" if prefixes and r.random() < 0.3 else "") + ncname(r)


def blanks(r, lo=0):
    return "".join(r.choice(" \t\n\r") for _ in range(r.randint(lo, 2) if lo else r.choice([0, 0, 1, 2])))


def S(r):
    return blanks(r, 1) or " "


NEED = set()      # the names of the entities the document refers to: the prolog has to declare them


def reference(r):
    k = r.random()
    if k < 0.4:
        n = r.choice(["amp", "lt", "gt", "quot", "apos", "other", ncname(r)])
        if n not in ("amp", "lt", "gt", "quot", "apos"):
            NEED.add(n)
        return "&" + n + ";"
    if k < 0.7:
        return "&#%d;" % r.choice([65, 233, 8364, 0x1D11E, 9, 10, 0x2028])
    return "&#x%s;" % r.choice(["41", "e9", "20AC", "1D11E", "a", "D", "FFFD"])


def text(r, attr=None):
    alphabet = "abc xyz\n\t0189.,;:!?()[]{}-_+*/#@$%^|~`>" + ("" if attr == '"' else '"') + ("" if attr == "'" else "'")
    out = []
    for _ in range(r.randint(0, 4)):
        k = r.random()
        if k < 0.7:
            out.append("".join(r.choice(alphabet) for _ in range(r.randint(1, 8))))
        elif k < 0.85:
            out.append(reference(r))
        else:
            out.append(r.choice(["é", "€", "\U0001D11E", "日本語", "\u00a0", "\ud7ff", "\ue000", "\ufffd"]
                                + ([] if attr else ["\r\n"])))
    s = "".join(out)
    if not attr:
        s = re.sub(r"\]\](?=>)", "]] ", s)
        if s.endswith("]"):
            s += " "        # the text after it may begin with >
    return s


def comment(r):
    s = "".join(r.choice("abc <>&;'\"[]?!é-") for _ in range(r.randint(0, 12)))
    s = re.sub("-(?=-)", "- ", s)
    if s.endswith("-"):
        s += " "
    return "<!--" + s + "-->"


def pi(r):
    t = r.choice(["pi", "x-y", "target1", "xmlx", "xml-stylesheet", "é", "p.q"])
    d = "".join(r.choice("abc <>&;'\"[]!é-?") for _ in range(r.randint(0, 12)))
    d = re.sub(r"\?(?=>)", "? ", d)
    return "<?" + t + (S(r) + d if d or r.random() < 0.3 else "") + "?>"


def cdata(r):
    s = "".join(r.choice("abc <>&;'\"[]?!é-") for _ in range(r.randint(0, 12)))
    return "<![CDATA[" + re.sub(r"\]\](?=>)", "]] ", s) + "]]>"


def attributes(r, prefixes):
    out, names = [], set()
    for _ in range(r.choice([0, 0, 1, 1, 2, 3])):
        n = qname(r, prefixes)
        if n in names:
            continue
        names.add(n)
        q = r.choice(['"', "'"])
        out.append(S(r) + n + blanks(r) + "=" + blanks(r) + q + text(r, q) + q)
    return "".join(out)


def element(r, depth, prefixes):
    n = qname(r, prefixes)
    a = attributes(r, prefixes)
    if depth <= 0 or r.random() < 0.25:
        return "<" + n + a + blanks(r) + "/>"
    body = []
    for _ in range(r.randint(0, 5)):
        k = r.random()
        if k < 0.3:
            body.append(text(r))
        elif k < 0.6:
            body.append(element(r, depth - 1, prefixes))
        elif k < 0.7:
            body.append(comment(r))
        elif k < 0.78:
            body.append(pi(r))
        elif k < 0.88:
            body.append(cdata(r))
        else:
            body.append(reference(r))
    return "<" + n + a + blanks(r) + ">" + "".join(body) + "</" + n + blanks(r) + ">"


def particle(r, depth, prefixes):
    if depth <= 0 or r.random() < 0.6:
        return qname(r, prefixes) + r.choice(["", "", "?", "*", "+"])
    sep = r.choice(["|", ","])
    parts = [particle(r, depth - 1, prefixes) for _ in range(r.randint(1 if sep == "," else 2, 3))]
    return "(" + blanks(r) + (blanks(r) + sep + blanks(r)).join(parts) + blanks(r) + ")" + r.choice(["", "?", "*", "+"])


def literal(r, chars, extra=""):
    q = r.choice(['"', "'"])
    s = "".join(r.choice(chars) for _ in range(r.randint(0, 8)))
    return q + s.replace(q, "") + q


def decl(r, prefixes):
    k = r.randrange(8)
    if k == 0:
        return "<!ELEMENT " + qname(r, prefixes) + S(r) + r.choice(["EMPTY", "ANY"]) + blanks(r) + ">"
    if k == 1:
        names = [qname(r, prefixes) for _ in range(r.randint(0, 3))]
        m = "(" + blanks(r) + "#PCDATA" + "".join(blanks(r) + "|" + blanks(r) + n for n in names) + blanks(r) + ")"
        if names or r.random() < 0.5:
            m += "*"
        return "<!ELEMENT " + qname(r, prefixes) + S(r) + m + blanks(r) + ">"
    if k == 2:
        m = "(" + blanks(r) + particle(r, 2, prefixes) + blanks(r) + r.choice(["|", ","]) + blanks(r) + particle(r, 2, prefixes) + ")"
        m = m if r.random() < 0.5 else particle(r, 3, prefixes)
        if not m.startswith("("):
            m = "(" + m + ")"
        # one separator throughout the group; a nested group is its own
        return "<!ELEMENT " + qname(r, prefixes) + S(r) + fix_group(m) + blanks(r) + ">"
    if k == 3:
        defs = []
        for _ in range(r.randint(0, 3)):
            ty = r.choice(["CDATA", "ID", "IDREF", "IDREFS", "ENTITY", "ENTITIES", "NMTOKEN", "NMTOKENS",
                           "(" + blanks(r) + "x" + blanks(r) + "|" + blanks(r) + "y.1:z" + blanks(r) + ")",
                           "NOTATION" + S(r) + "(" + blanks(r) + ncname(r) + blanks(r) + ")"])
            d = r.choice(["#REQUIRED", "#IMPLIED", "#FIXED" + S(r) + literal(r, "abc ."),
                          literal(r, "abc .")])
            defs.append(S(r) + qname(r, prefixes) + S(r) + ty + S(r) + d)
        return "<!ATTLIST " + qname(r, prefixes) + "".join(defs) + blanks(r) + ">"
    if k == 4:
        n = "E" + r.choice(LETTERS)   # no reference of the generator's names it, which expat would expand
        ext = "SYSTEM" + S(r) + literal(r, "abc/.")
        if r.random() < 0.3:
            return "<!ENTITY %" + S(r) + n + S(r) + r.choice([literal(r, "abc <>é[]!-"), ext]) + blanks(r) + ">"
        return "<!ENTITY " + n + S(r) + r.choice([literal(r, "abc <>é[]!-"), ext,
                                                   ext + S(r) + "NDATA" + S(r) + ncname(r)]) + blanks(r) + ">"
    if k == 5:
        ex_ = r.choice(["SYSTEM" + S(r) + literal(r, "abc/."),
                        "PUBLIC" + S(r) + literal(r, "abc -()+,./:=?;!*#@$_%") + (S(r) + literal(r, "abc/.") if r.random() < 0.5 else "")])
        return "<!NOTATION " + ncname(r) + S(r) + ex_ + blanks(r) + ">"
    if k == 6:
        return comment(r) if r.random() < 0.5 else pi(r)
    return "%" + ncname(r) + ";"


def fix_group(m):
    # make every group of m use one separator: replace the separators by the first one found at its level
    out, stack = [], []
    for i, c in enumerate(m):
        if c == "(":
            stack.append(None)
            out.append(c)
        elif c == ")":
            stack.pop()
            out.append(c)
        elif c in "|," and stack:
            if stack[-1] is None:
                stack[-1] = c
            out.append(stack[-1])
        else:
            out.append(c)
    return "".join(out)


def prolog(r, prefixes):
    out = []
    if r.random() < 0.5:
        d = '<?xml' + S(r) + 'version' + blanks(r) + '=' + blanks(r)
        q = r.choice(['"', "'"])
        d += q + "1." + str(r.choice([0, 0, 0, 1, 9, 10])) + q
        if r.random() < 0.5:
            d += S(r) + "encoding" + blanks(r) + "=" + blanks(r) + r.choice(['"UTF-8"', "'utf-8'", '"US-ASCII"', '"ISO-8859-1"'])
        if r.random() < 0.4:
            d += S(r) + "standalone" + blanks(r) + "=" + blanks(r) + r.choice(['"no"', "'no'"])
        out.append(d + blanks(r) + "?>")
    misc = lambda: "".join(blanks(r) + r.choice([comment, pi])(r) for _ in range(r.choice([0, 0, 1, 2]))) + blanks(r)
    out.append(misc())
    if r.random() < 0.5 or NEED:
        d = "<!DOCTYPE" + S(r) + qname(r, prefixes)
        # a reference to an entity needs its declaration, or an external subset that may hold it
        ext = r.random() < 0.4 or (NEED and r.random() < 0.3)
        if ext:
            d += S(r) + r.choice(["SYSTEM" + S(r) + literal(r, "abc/. \"'"),
                                  "PUBLIC" + S(r) + literal(r, "abc -()+,./:=?;!*#@$_%") + S(r) + literal(r, "abc/.")])
        if r.random() < 0.7 or (NEED and not ext):
            decls = [blanks(r) + decl(r, prefixes) for _ in range(r.randint(0, 6))]
            if not ext:
                decls += [blanks(r) + "<!ENTITY " + n + S(r) + r.choice(['"v"', "'v w'", '"&amp;"']) + blanks(r) + ">" for n in sorted(NEED)]
            r.shuffle(decls)
            d += blanks(r) + "[" + "".join(decls) + blanks(r) + "]"
        d += blanks(r) + ">"
        out.append(d + misc())
    return "".join(out)


def document(r):
    prefixes = ["x", "y", "xmlns", "xml"] if r.random() < 0.5 else []
    NEED.clear()
    root = element(r, r.randint(0, 5), prefixes)
    return prolog(r, prefixes) + root + "".join(
        blanks(r) + r.choice([comment, pi])(r) for _ in range(r.choice([0, 0, 1]))) + blanks(r)


# ---- mutations ----------------------------------------------------------------------------------
INTERESTING = list("<>&;\"'/=!?-[]%# \n\t:_.,()|*+") + ["]]>", "<!--", "-->", "<![CDATA[", "<?", "?>", "&#", "&#x",
                                                         "\x01", "\x0b", "￾", "￿", "é", "𝄞", "\r", "xml",
                                                         "<!DOCTYPE", "<!ELEMENT", "<!ATTLIST", "<!ENTITY", "#PCDATA",
                                                         "xmlns:", "a", "Z", "9", "·", "́", "⁰"]


def mutate(r, s):
    for _ in range(r.choice([1, 1, 1, 2])):
        if not s:
            s = r.choice(INTERESTING)
            continue
        k = r.randrange(6)
        i = r.randrange(len(s))
        if k == 0:
            s = s[:i] + s[i + 1:]
        elif k == 1:
            s = s[:i] + r.choice(INTERESTING) + s[i:]
        elif k == 2:
            s = s[:i] + r.choice(INTERESTING) + s[i + 1:]
        elif k == 3 and i + 1 < len(s):
            s = s[:i] + s[i + 1] + s[i] + s[i + 2:]
        elif k == 4:
            s = s[:i] + s[i] + s[i:]
        else:
            s = s[:i]
    return s


def main():
    mode = sys.argv[1]
    if mode == "check":
        for f in sys.argv[2:]:
            print(f, verdict(open(f, "rb").read())[0])
        return
    if mode == "names":
        d = sys.argv[2]
        os.makedirs(d, exist_ok=True)
        start, cont = re.compile("[%s]" % START), re.compile("[%s]" % CONT)
        docs, ref = [], []
        for c in range(0x110000):
            if 0xD800 <= c <= 0xDFFF or c in (0x3A, 0x00):
                continue
            ch = chr(c)
            docs += ["<%sb/>" % ch, "<a%sb/>" % ch]
            ref += ["1" if start.match(ch) else "0", "1" if cont.match(ch) else "0"]
        open(d + "/names.in", "wb").write("\0".join(docs).encode("utf-8") + b"\0")
        open(d + "/names.ref", "w").write("".join(ref))
        return
    n, seed, d = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    os.makedirs(d, exist_ok=True)
    r = random.Random(seed)
    for i in range(n):
        if mode == "gen":
            doc = document(r)
            # the generator is checked by the oracle: a document it makes must be accepted
            v, why = verdict(doc.encode())
            if v != "1":
                sys.stderr.write("generator made a document the oracle refuses (%s): %r\n" % (why, doc))
                sys.exit(1)
            open("%s/g%05d.xml" % (d, i), "wb").write(doc.encode())
        else:
            doc = mutate(r, document(r))
            b = doc.encode("utf-8", "surrogatepass")
            open("%s/m%05d.xml" % (d, i), "wb").write(b)
            open("%s/m%05d.ref" % (d, i), "w").write(verdict(b)[0])


if __name__ == "__main__":
    main()
