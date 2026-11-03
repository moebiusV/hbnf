#!/usr/bin/env python3
"""The oracle for corpus/html/html.hbnf: html5lib's strict parser (HTMLParser(strict=True)), which raises
on the first parse error of the tokenizer and the tree builder of the WHATWG HTML Living Standard 13.2,
that is, on a document that does not conform.  lxml.html (libxml2, an HTML 4 parser) can be asked as a second
opinion (--lxml): it only tells the documents it cannot recover.

  oracle.py gen N SEED DIR    write N random valid documents to DIR/g*.html
  oracle.py mut N SEED DIR    write N mutated documents to DIR/m*.html and, beside each, DIR/m*.ref: 1 if
                              html5lib accepts it, 0 if it refuses it for its syntax, 2 if it refuses it
                              for a reason a grammar of the syntax cannot see, or accepts it with an end tag
                              that spells its name in another case than the start tag (the grammar does not fold)
  oracle.py check FILE...     print "FILE 1", "FILE 0" or "FILE 2" for each (--lxml: lxml's verdict, 1 or 0)

html5lib also raises for what a document means: an element where the content model does not allow it, a
duplicate attribute, a named reference that is not in the table, a numeric reference to a code point that
must not be written, and a few places where it is older or stricter than the standard (a comment with "--"
inside, a "&" followed by letters).  Those are verdict 2: either answer of the grammar is counted as agreement.
A byte order mark is removed first, as a browser does before it parses.  Nothing here knows hbnf."""
import os, random, re, sys

# html5lib's messages (html5lib/constants.py) for the refusals a grammar of the syntax cannot see: the content
# model (an element where it may not be, an end tag that closes nothing the tree builder opened, text where
# only elements go), a duplicate attribute, a character reference that names nothing or something that must not
# be written, a comment with "--" inside (the standard allows it).  A stray end tag is the grammar's to refuse
# too (an element has the end tag its start tag had), but the tree builder says the same of an end tag that
# follows an end tag the grammar lets be omitted, so "Unexpected end tag" counts here.
MEANING = re.compile(
    r"Dropped duplicate attribute|Named entity|Numeric entity represents|Numeric entity couldn't"
    r"|Unexpected '-' after '--' found in comment|Unexpected ! after -- in comment|Unexpected character in comment found|Undefined error"
    r"|Unexpected start tag|Unexpected end tag|End tag \(.*seen too early|violates step"
    r"|Unexpected non-space|Missing end tag|Unexpected input|Unexpected image|phase|needs to be the first|non-html context")

def verdict(b):
    if b[:3] == b"\xef\xbb\xbf":
        b = b[3:]
    try:
        t = b.decode("utf-8")
    except UnicodeDecodeError:
        return 0
    import html5lib
    try:
        html5lib.HTMLParser(strict=True).parse(t)
    except Exception as e:
        return 2 if MEANING.search(str(e)) else 0
    return 1

def case_mismatch(b):
    """an end tag that spells its name in another case than any start tag does: html5lib folds the names, the
    grammar does not (`%same` repeats the text of the start tag), so for such a document either answer is fine"""
    t = b.decode("utf-8", "replace")
    starts = set(re.findall(r"<([A-Za-z][^\s/>]*)", t))
    low = {x.lower() for x in starts}
    return any(n not in starts and n.lower() in low for n in re.findall(r"</([A-Za-z][^\s/>]*)", t))

def lxml_verdict(b):
    from lxml import etree
    if b[:3] == b"\xef\xbb\xbf":
        b = b[3:]
    try:
        etree.fromstring(b, etree.HTMLParser(recover=False))
        return 1
    except Exception:
        return 0

# ---------------------------------------------------------------- random valid documents
WORDS = ["a", "word", "hello", "x", "text", "café", "日本", "emoji\U0001f600", "1", "it's", 'say "hi"', "a-b", "x>y", "(par)", "50%", "tab\there"]
REFS = ["&amp;", "&lt;", "&gt;", "&quot;", "&nbsp;", "&copy;", "&#65;", "&#x41;", "&#X41;", "&#128512;", "&#xa9;", "&hellip;"]

def text(r):
    out = [r.choice(WORDS)]
    for _ in range(r.randint(0, 3)):
        k = r.random()
        out.append(r.choice([" ", " & ", "\n", "\r\n", "  "]))
        out.append(r.choice(WORDS) if k < .7 else r.choice(REFS))
    return "".join(out)

def comment(r):
    return "<!--" + r.choice(["", " c ", " <p>x</p> ", " a - b ", "\n multi\n line\n", "x", " & ", " <b "]) + "-->"

ATTRS = ["class", "id", "title", "lang", "data-x", "aria-label", "style", "hidden", "x-y.z", "tabindex", "role", "dir"]

def attrs(r, extra=()):
    names = r.sample(ATTRS, r.choice([0, 0, 1, 1, 2, 3])) + list(extra)
    out = []
    for n in names:
        k = r.random()
        if n in ("hidden",) and k < .5:
            out.append(" " + n); continue
        v = r.choice(["a", "b c", "x&amp;y", "1", "it's", "", "p/q", 'say "hi"', "a&#x41;b", "café", "x > y", "50%"])
        if k < .15 and v and re.fullmatch(r"[A-Za-z0-9/%é&;#]+", v) and "&" not in v:
            out.append(f" {n}={v}")
        elif k < .3 and "'" not in v:
            out.append(f" {n}='{v}'")
        elif '"' in v:
            out.append(f" {n}='{v}'")
        else:
            sp = r.choice(["", "", " ", "\n"])
            out.append(f" {n}{sp}={sp}\"{v}\"")
    return "".join(out) + r.choice(["", "", " ", "\n"])

INLINE = ["span", "b", "i", "em", "strong", "code", "small", "abbr", "u", "x-widget", "my-tag.v"]

def phrasing(r, d, in_a=False):
    out = []
    for _ in range(r.randint(1, 3)):
        k = r.random()
        if k < .4 or d > 3:
            out.append(text(r))
        elif k < .5:
            out.append(comment(r))
        elif k < .75:
            n = r.choice(INLINE)
            out.append(f"<{n}{attrs(r)}>{phrasing(r, d + 1, in_a)}</{n}>")
        elif k < .83 and not in_a:
            out.append(f"<a{attrs(r, ['href'])}>{phrasing(r, d + 1, True)}</a>")
        elif k < .9:
            out.append(r.choice(["<br>", "<br/>", "<br />", "<wbr>", f"<img src=a.png alt=x{r.choice(['', '/', ' /'])}>", f"<input type=text{attrs(r)}>"]))
        elif k < .94:
            out.append(rcdata(r, "textarea"))
        elif k < .97:
            out.append(script(r))
        else:
            out.append(svg(r) if r.random() < .6 else math(r))
    return "".join(out)

def script(r):
    body = r.choice(["", "var a = 1;", "if (a < b && c > d) f(\"</p>\");", "x = '<b>' + \"&amp;\";", "a</scripts>b", "/* </scrip */", "\n  f();\n  // done\n"])
    return f"<script{attrs(r)}>{body}</script{r.choice(['', ' ', chr(10)])}>"

def rcdata(r, n):
    body = r.choice(["", "plain", "a &amp; b", "a < b", "<b>not markup</b>", "x &#65; y", "&lt;/" + n + "&gt;", "</" + n + "x> y", "\ntwo\nlines"])
    return f"<{n}{attrs(r)}>{body}</{n}>"

def svg(r):
    def kid(d):
        k = r.random()
        if d > 2 or k < .3:
            return f"<circle{attrs(r)} cx=1 cy=2 />" if r.random() < .5 else "<path d=\"M0 0\"/>"
        if k < .5:
            return f"<text{attrs(r)}>{r.choice(['t', 'a &amp; b', 'x'])}</text>"
        if k < .6:
            return "<![CDATA[ a < b && c ]]>"
        if k < .7:
            return comment(r)
        if k < .8:
            return f"<foreignObject width=1>{r.choice(['t', '<div>x</div>', '<p>y</p><b>z</b>'])}</foreignObject>"
        if k < .85:
            return "<rect></rect>"
        n = r.choice(["g", "defs", "linearGradient", "clipPath"])
        return f"<{n}{attrs(r)}>{''.join(kid(d + 1) for _ in range(r.randint(0, 3)))}</{n}>"
    if r.random() < .1:
        return "<svg/>"
    return f"<svg{attrs(r)}>{''.join(kid(0) for _ in range(r.randint(0, 3)))}</svg>"

def math(r):
    return "<math><mi>x</mi><mo>+</mo><mn>1</mn>" + r.choice(["", "<mspace width=1em />", "<mrow><mi>y</mi></mrow>"]) + "</math>"

def items(r, d, n, tag, omit_rule):
    """n elements of tag with the end tag omitted where omit_rule(next_tag_or_None) says so"""
    out = []
    for i in range(n):
        content = phrasing(r, d + 1) if r.random() < .8 else ""
        out.append(f"<{tag}{attrs(r)}>{content}" + ("" if omit_rule(i == n - 1) and r.random() < .6 else f"</{tag}>"))
    return "".join(out)

def flow(r, d=0):
    out = []
    for _ in range(r.randint(1, 4)):
        k = r.random()
        if d > 3 or k < .2:
            out.append(phrasing(r, d + 1))
        elif k < .32:
            n = r.choice(["div", "section", "article", "blockquote", "aside"])
            out.append(f"<{n}{attrs(r)}>{flow(r, d + 1)}</{n}>")
        elif k < .5:
            out.append(items(r, d, r.randint(1, 3), "p", lambda last: True) + "<div></div>")
        elif k < .62:
            n = r.choice(["ul", "ol"])
            out.append(f"<{n}{attrs(r)}>" + "".join(
                f"<li{attrs(r)}>{phrasing(r, d + 1)}" + (f"<ul><li>{phrasing(r, d + 2)}</ul>" if r.random() < .2 else "") + r.choice(["", "</li>"])
                for _ in range(r.randint(1, 3))) + f"</{n}>")
        elif k < .7:
            out.append("<dl>" + "".join(f"<dt>{phrasing(r, d + 1)}" + r.choice(["", "</dt>"]) + f"<dd>{phrasing(r, d + 1)}" + r.choice(["", "</dd>"]) for _ in range(r.randint(1, 3))) + "</dl>")
        elif k < .76:
            out.append("<select>" + "".join(r.choice([f"<option value=1>{r.choice(['a', 'b'])}", f"<option>x</option>", f"<optgroup label=g><option>y<option>z"]) for _ in range(r.randint(1, 3))) + "</select>")
        elif k < .86:
            rows = lambda tag: "".join("<tr>" + "".join(f"<{tag}>{r.choice(['1', 'a &amp; b', 'x'])}" + r.choice(["", f"</{tag}>"]) for _ in range(r.randint(1, 3))) + r.choice(["", "</tr>"]) for _ in range(r.randint(1, 2)))
            out.append("<table>" + r.choice(["", "<caption>cap</caption>"]) + r.choice(["", "<colgroup><col><col></colgroup>"])
                       + r.choice(["", "<thead>" + rows("th") + r.choice(["", "</thead>"])]) + "<tbody>" + rows("td") + r.choice(["", "</tbody>"])
                       + r.choice(["", "<tfoot>" + rows("td") + r.choice(["", "</tfoot>"])]) + "</table>")
        elif k < .9:
            out.append(r.choice(["<hr>", "<hr/>", "<hr />"]))
        elif k < .94:
            out.append(script(r))
        elif k < .97:
            out.append(svg(r))
        else:
            out.append(comment(r))
    return "".join(out)

def doctype(r):
    return r.choice(["<!DOCTYPE html>", "<!doctype html>", "<!DocType HTML>", "<!DOCTYPE html >", "<!DOCTYPE  html\n>",
                     '<!DOCTYPE html SYSTEM "about:legacy-compat">', "<!DOCTYPE html SYSTEM 'about:legacy-compat'>"])

def document(r):
    out = []
    if r.random() < .1:
        out.append("﻿")
    for _ in range(r.choice([0, 0, 1, 2])):
        out.append(r.choice([comment(r), " ", "\n"]))
    out.append(doctype(r))
    out.append(r.choice(["", "\n"]))
    head = "".join(r.choice(["<meta charset=utf-8>", "<link rel=stylesheet href=a.css>", f"<style>a > b {{ c: \"</p>\" }}</style>", "<base href=/>", script(r)]) for _ in range(r.choice([0, 1, 2])))
    title = f"<title>{r.choice(['T', 'a &amp; b', 'x < y', 't&#65;'])}</title>"
    k = r.random()
    if k < .4:
        out.append(f"<html{attrs(r)}><head>{title}{head}" + r.choice(["</head>", ""]) + f"<body{attrs(r)}>{flow(r)}" + r.choice(["</body></html>", "</body>", "", "</html>"]) )
    elif k < .8:
        out.append(f"{title}{head}{flow(r)}")
    else:
        out.append(flow(r))
    out.append(r.choice(["", "\n", "<!-- end -->"]))
    return "".join(out)

# ---------------------------------------------------------------- mutations
ALPHABET = list("<>/=\"'&;!-# x\n") + ["</", "<!--", "-->", "&#", "&amp;", "<p>", "</p>", "<br>", "\x01", "é"]

def mutate(r, t):
    for _ in range(r.choice([1, 1, 1, 2])):
        if not t:
            break
        i = r.randrange(len(t))
        k = r.randrange(6)
        if k == 0:
            t = t[:i] + t[i + 1:]
        elif k == 1:
            t = t[:i] + r.choice(ALPHABET) + t[i:]
        elif k == 2:
            t = t[:i] + r.choice(ALPHABET) + t[i + 1:]
        elif k == 3 and i + 1 < len(t):
            t = t[:i] + t[i + 1] + t[i] + t[i + 2:]
        elif k == 4:
            t = t[:i] + t[i] + t[i:]
        else:
            t = t[:i]
    return t

def main():
    a = sys.argv[1:]
    lx = False
    if a and a[0] == "--lxml":
        lx = True; a = a[1:]
    if a[0] == "check":
        for f in a[1:]:
            b = open(f, "rb").read()
            print(f, lxml_verdict(b) if lx else verdict(b))
        return
    n, seed, d = int(a[1]), int(a[2]), a[3]
    os.makedirs(d, exist_ok=True)
    r = random.Random(seed)
    for i in range(n):
        t = document(r)
        if a[0] == "gen":
            open(f"{d}/g{i}.html", "wb").write(t.encode("utf-8"))
        else:
            m = mutate(r, t)
            b = m.encode("utf-8", "surrogatepass")
            open(f"{d}/m{i}.html", "wb").write(b)
            v = verdict(b)
            open(f"{d}/m{i}.ref", "w").write(f"{2 if v == 1 and case_mismatch(b) else v}\n")

main()
