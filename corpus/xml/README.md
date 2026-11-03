# XML 1.0 in HyperBNF

`xml.hbnf` is the syntax of a well-formed XML 1.0 (Fifth Edition) document in 48 rules, against the
specification's 77 for the same ground: the prolog (the XML declaration, comments, processing
instructions, a DOCTYPE with its internal subset), elements and attributes, character data, CDATA
sections, character and entity references, and the markup declarations of the internal subset (ELEMENT,
ATTLIST, ENTITY, NOTATION, comments, processing instructions, parameter-entity references between
them).  A name is a QName of *Namespaces in XML 1.0*, `[prefix ":"] local`, with both parts NCNames:
the grammar reads the names and resolves nothing.  The name characters are the Fifth Edition's
`NameStartChar` and `NameChar` as code point ranges.

| | rules | lines | symbols | characters |
|---|---:|---:|---:|---:|
| the productions of XML 1.0 and of the Namespaces QName (`originals/xml-1.0-productions.bnf`) | 77 | 77 | 657 | 3866 |
| all 88 productions of XML 1.0 and those 9 (`originals/xml-1.0-external.bnf` adds the external subset, conditional sections, the text declaration, `Names` and `Nmtokens`) | 88 | 88 | 731 | 4406 |
| HyperBNF (`corpus/xml/xml.hbnf`) | 48 | 53 | 581 | 2995 |
| **saved**, against the first row | **38%** | **31%** | **12%** | **23%** |

Counted as `bench/notation.sh` counts the others (`python3 -I bench/count.py hbnf-code corpus/xml/xml.hbnf`;
for the specification, `count.py specbnf` with a line that starts with `#` as the comment, since `#x9` and
`#PCDATA` are XML's own).  The specification's rules are one to a line here, as its Recommendation prints
them, so the lines match its rules; `xml.hbnf` wraps a few.  The symbols save least because XML's
syntax is mostly punctuation and keywords; what the grammar saves is rules, by stating a family once:

- **`till(T)`** is "anything up to T": the text of a comment (up to `--`, which a comment may not
  hold, so it is the specification's `Char - '-'` and `'-' (Char - '-')` in one), of a processing
  instruction (up to `?>`) and of a CDATA section (up to `]]>`); the specification has `CData`, the tail of
  `PI` and the body of `Comment` as three different expressions.
- **`quoted(C)`** is a literal in either quote whose characters are `C`: the `AttValue` (`C` is
  `~( "<" | "&" ) | reference`), the `EntityValue`, the `SystemLiteral` and the `PubidLiteral`, which the
  specification writes four times with the quote excluded by hand in each.
- **`pseudo(K, V)`** is ` version="1.0"`, ` encoding="UTF-8"`, ` standalone="yes"` of the XML
  declaration (`VersionInfo`, `EncodingDecl`, `SDDecl`), and **`sep(C)`**, **`alts(X)`** are the
  separator with its optional blanks and the parenthesised `|` list of `Enumeration` and `NotationType`.
- **`group`** is `choice` and `seq` of an element declaration in one rule: `( cp ( 1*( "|" cp ) | *( "," cp ) ) )`,
  a group of one name being a sequence as in the specification, so a group does not mix `|` and `,`.
- The **legal characters** are checked once for the whole document, `&legal` before the first rule is
  tried (`legal = *Char !any`): a character outside `Char` is an error wherever it is, so no rule says
  "`Char` minus ...", and `~"<"` is the specification's `[^<]`.
- `qname`, `ncname` and `nmtoken` are the names (`NameStartChar` and `NameChar` without the colon, which a
  `QName` places itself); `PITarget` is `ncname - reserved`, a token exception, where `reserved` is `xml`
  in any case.
- The closing tag repeats the opening one's name with a **back-reference**, `qname as tag` ... `$tag`
  (the same `as` and `$` as `corpus/mustache`).  The `$tag` has to be in the rule of the `as tag`, which is why the empty element is the
  rule's other alternative, written out, and why `element` is not split into the specification's
  `STag content ETag`.

## Not covered

What the syntax cannot say, or what needs the declarations, the specification states as constraints
and a parser has to check besides; this grammar does not:

- a repeated attribute in one tag (Unique Att Spec);
- a character reference to a code point outside `Char` (`&#0;`, `&#xD800;`, `&#x110000;`: the digits
  are what is checked);
- an entity that is not declared before its use, one that refers to itself, an unparsed entity named
  in content or in an attribute, a `<` that an entity puts in an attribute value, an entity whose text
  does not nest: entities are not expanded, `&name;` and `%name;` are references;
- `<!DOCTYPE name` naming the root element (a validity constraint), and everything else about
  validity;
- the external subset, conditional sections (`<![INCLUDE[`), `TextDecl` and external parsed entities
  (`originals/xml-1.0-external.bnf`): those are another file's text;
- XML 1.1 (`version="1.1"` is read as a version number and the rules are 1.0's), and the declared
  encoding, which is read and not used: a parser reads characters.  A byte order mark at the start is
  accepted; invalid UTF-8 is the decoder's, not the grammar's; a NUL byte ends the text of the C parser
  (a C string), so `<a/>` followed by a NUL and anything is accepted by it.

`tests/xml/oracle.py` and the folders mark the places: `corpus/xml/tests/loose` holds a file for each
of the checks above that expat makes and the grammar does not.

## Tests

`corpus/xml/tests/{good,bad,loose}` are 106, 230 and 14 hand-written cases, written from the
specification's productions and from the classes of error expat reports (`mismatched tag`, `junk
after document element`, `invalid token`, `unclosed token`, `duplicate attribute`, `undefined
entity` ...); `sh tests/xml.sh` runs them through the C, Ada, Rust and Zig parsers (the `loose` files
are accepted).  The W3C XML Conformance Test Suite (`xmlconf`) is not in the repository (no download offline):
its not-well-formed tests are of the same classes, and a run of the parser over it is the next
check to make.

### Checked against expat

`sh tests/xml-diff.sh [N [SEED]]` generates N random well-formed documents (a prolog with an XML
declaration, a DOCTYPE with random declarations of every kind, elements nested to five levels
with prefixed and Unicode names, attributes in both quotes, references, CDATA sections, comments,
processing instructions) and N mutations of them (a character deleted, inserted, replaced, swapped,
doubled, or the text cut; the inserted characters are the ones XML cares about: `< > & ; " ' / = ! ? - [ ]
% # :`, `]]>`, `<!--`, a control character, U+FFFF), and asks the parser hbnf makes and Python's
`xml.parsers.expat` about each.  Then it asks the parser about every code point as the first and as a
later character of a name, and runs the three folders.

expat checks well-formedness, not validity, so it is the right oracle, and where it differs from
the grammar the oracle (`tests/xml/oracle.py`) is built to say so:

- **Namespaces.**  expat reads a Name, where `a:b:c`, `:a` and `a:` are names; the grammar reads a
  QName.  The oracle adds the lexical rule (at most one colon, and both parts NCNames) to the names of
  elements, attributes, the DOCTYPE, declarations, entities, notations and instruction targets.
- **Name characters.**  expat's tables are the Fourth Edition's (Appendix B), not the Fifth's: the two
  differ in 937,000 code points, nearly all of them above U+FFFF, so expat refuses `<𐀀/>`,
  `<a‿b/>` and `<⁰/>`, which are names in the Fifth Edition.  For the documents the oracle folds such a
  character into one expat takes (an ideograph for a start character, an Arabic-Indic digit for the
  others), and the characters themselves are checked against the Fifth Edition's ranges by the code point
  test (1,112,062 code points, no difference).
- **Encoding.**  The oracle gives expat text, not bytes, so the declared encoding is not used and
  `encoding="no-such-code-page"` is accepted by both; with bytes expat would say `unknown encoding`.
  The XML declaration's own syntax is checked by both (`EncName` is ASCII).  A byte order mark at the
  start is removed for expat, which does so on bytes.
- **Entities.**  expat refuses `&undeclared;` in a document without an external subset; the oracle
  switches that check off (`UseForeignDTD`) since the grammar does not know the declarations.  The checks
  the grammar leaves out and expat makes are marked `L` by the oracle (a repeated attribute, a character
  reference out of range, an entity that recurs, is unparsed or does not nest), and the test allows the
  grammar to accept such a document and counts it.  One refused document in 20,000 is reported
  apart: expat stops at the first error, and when that is one of these the oracle cannot say if there is
  a later syntax error; it is, each time, the grammar being right (the text had been cut).
- **Internal subset.**  A parameter-entity reference may stand between declarations and not inside one
  (not in an entity value either: `<!ENTITY e "%p;">` is an error in an internal subset), and the grammar
  and expat agree.

With 20,000 and 20,000 (seed 7): every well-formed document accepted, and the same answer on 19,972
mutations; 27 were accepted where expat refused one of the checks above (nearly all a character reference
out of range) and 1 was refused by both for different reasons.  Ten other seeds of 20,000 gave the same
kind of result and no difference of the other two kinds (the grammar accepting what expat and the
Namespaces rule refuse, or refusing what they accept); finding the oracle's own gaps (the name of an
ATTLIST that defines nothing, which expat does not report; the declarations after a parameter-entity
reference, which it does not either) is what most of those runs were for.
The names: no difference from the Fifth Edition's ranges in 1,112,062 code points.

### Performance

The C parser reads a 1 MB generated catalog (1,000,089 bytes: 3,114 books with attributes,
references, CDATA sections and comments) in about 11 ms with `cc -O2` (about 90 MB/s); expat, from Python,
3 ms.  (`bench/` has no XML corpus; this is a one-off figure, not in `bench/results`.)

## In the other outputs

C, Ada, Rust and Zig parse the 106 + 14 files and refuse the 230 (`tests/xml.sh`; the Rust build
allows rustc's `unused_assignments`, which the `as` code of the Rust backend trips).  The tree-sitter
backend writes a `grammar.js` (a lookahead is left out, as for the other grammars, and a closing tag
is any name).  `--layout=tape` is refused for this grammar: a back-reference in a tape layout writes
code that does not compile (`cl_tag` undeclared).
