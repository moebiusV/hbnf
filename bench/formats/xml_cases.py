#!/usr/bin/env python3
"""xml_cases.py DIR: writes the inputs of the XML conformance table into DIR as c01.xml, c02.xml ... and an index,
DIR/index.tsv: id, kind (ill = XML 1.0 forbids it, wf = well-formed), what it is.  Each ill-formed input breaks one
well-formedness constraint of XML 1.0 (Fifth Edition) on its own, and each well-formed one is something a lax checker
might refuse (so a parser that refuses everything does not look conformant).  Expat, with its own checks on, is the
reference for the table; bench/xml-conformance.sh prints the places where it differs from what is written here."""
import sys, os
ILL = [
 ("control character U+0001 in text",            b"<a>\x01</a>"),
 ("control character U+0001 in an attribute",    b"<a b='\x01'/>"),
 ("duplicate attribute",                         b"<a x='1' x='2'/>"),
 ("invalid UTF-8 in text (FF FE)",               b"<a>\xff\xfe</a>"),
 ("overlong UTF-8 (C0 80)",                      b"<a>\xc0\x80</a>"),
 ("name containing U+0080",                      b"<a\xc2\x80b/>"),
 ("name starting with a digit",                  b"<1a/>"),
 ("character reference &#0;",                    b"<a>&#0;</a>"),
 ("character reference &#x110000;",              b"<a>&#x110000;</a>"),
 ("character reference &#xD800; (surrogate)",    b"<a>&#xD800;</a>"),
 ("character reference &#xFFFE;",                b"<a>&#xFFFE;</a>"),
 ("literal U+FFFE in text",                      b"<a>\xef\xbf\xbe</a>"),
 ("literal ]]> in text",                         b"<a>x]]>y</a>"),
 ("< in an attribute value",                     b"<a b='<'/>"),
 ("-- inside a comment",                         b"<a><!-- x -- y --></a>"),
 ("comment ending in --->",                      b"<a><!-- x ---></a>"),
 ("undeclared entity &foo;",                     b"<a>&foo;</a>"),
 ("two root elements",                           b"<a/><b/>"),
 ("no root element, only text",                  b"just text"),
 ("mismatched end tag",                          b"<a></b>"),
 ("unterminated element",                        b"<a>"),
 ("unquoted attribute value",                    b"<a b=c/>"),
 ("attribute without a value",                   b"<a b/>"),
 ("no space between two attributes",             b"<a b='1'c='2'/>"),
 ("XML declaration not at the start",            b" <?xml version='1.0'?><a/>"),
 ("bad standalone value in the declaration",     b"<?xml version='1.0' standalone='maybe'?><a/>"),
 ("a bare & in text",                            b"<a>a & b</a>"),
 ("entity reference without the semicolon",      b"<a>&amp</a>"),
 ("text after the root element",                 b"<a/>x"),
 ("processing instruction named XML",            b"<a><?XML x?></a>"),
 ("CDATA section outside the root",              b"<![CDATA[x]]><a/>"),
 ("DOCTYPE after the root element",              b"<a/><!DOCTYPE a>"),
 ("recursive entity",                            b"<!DOCTYPE a [<!ENTITY e '&e;'>]><a>&e;</a>"),
 ("end tag with an attribute",                   b"<a></a b='1'>"),
]
WF = [
 ("empty element",                               b"<a/>"),
 ("tab and newline in content",                  b"<a>\t\n</a>"),
 ("nested elements and an attribute",            b"<a x='1'><b>t&amp;u</b></a>"),
 ("legal characters: U+10FFFF, UTF-8 text",      b"<a>&#x10FFFF;\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80</a>"),
 ("XML declaration with an encoding",            b"<?xml version='1.0' encoding='UTF-8'?><a/>"),
 ("CDATA with ]] > and <&",                      b"<a><![CDATA[ ]] > <& ]]></a>"),
 ("declared entity and the predefined ones",     b"<!DOCTYPE a [<!ENTITY e 'x'>]><a>&e;&lt;&gt;&amp;&apos;&quot;</a>"),
 ("comment and processing instruction",          b"<a b='1' c=\"2\"><!-- c --><?pi x?></a>"),
 ("byte order mark and declaration",             b"\xef\xbb\xbf<?xml version='1.0'?><a/>"),
 ("names with colon, dash, dot, digit",          b"<a:b-c.d_1 xmlns:a='u'/>"),
 ("a non-ASCII element name",                    b"<\xc3\xa4/>"),
]
d = sys.argv[1]
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, "index.tsv"), "w") as ix:
    for i, (kind, items) in enumerate((("ill", ILL), ("wf", WF))):
        pass
    n = 0
    for kind, items in (("ill", ILL), ("wf", WF)):
        for what, data in items:
            n += 1
            open(os.path.join(d, "c%02d.xml" % n), "wb").write(data)
            ix.write("c%02d.xml\t%s\t%s\n" % (n, kind, what))
