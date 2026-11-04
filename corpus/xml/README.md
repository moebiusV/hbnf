# XML 1.0 in HyperBNF

`xml.hbnf` reads a well-formed XML 1.0 (Fifth Edition) document in 66 rules, against the
specification's 77 for the same ground, and checks the well-formedness constraints that need a table
(a repeated attribute, a character reference to a character XML forbids, an entity that is not declared, an
external or unparsed entity where it may not be): the prolog (the XML declaration, comments, processing
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
| HyperBNF (`corpus/xml/xml.hbnf`), without its C | 66 | 73 | 736 | 4837 |
| **saved**, against the first row | **14%** | **5%** | **-12%** | **-25%** |
| the same grammar before the constraints were checked | 48 | 52 | 579 | 2973 |

The specification's 77 productions only describe the syntax; the row for `xml.hbnf` also holds what the
specification states in prose as well-formedness constraints, which that row does not count (18 rules, 157 symbols and 1864
characters more than the syntax alone; half of the characters are the one regular expression of the legal character
references, which `tools/xml_charref.py` writes).  Not in that row: the two blocks of C of the entity table (about 40 lines, the
`%where` that walks the entities and the `%bind` that keeps an entity's text).

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

## The well-formedness constraints

The syntax cannot say these; the grammar checks them with the `context` mechanism (named sets of names that the
parser keeps while it reads: `x ? C` tests one, `%bind C += x` adds to it, a guess that fails puts them back) and with one
regular expression.  Each is written in the grammar once, in a few symbols.

| constraint | how | size | feature |
|---|---|---|---|
| Unique Att Spec: no attribute name twice in a tag | `attribute = qname ?! atts %bind atts += qname ..`; `%scope` on `attributes` empties the set at the end of the tag | 0 rules, 7 symbols | context |
| Legal Character: `&#..;` names a character of `Char`, in text, in an attribute value, in an entity value, in an attribute default | `charnum = r"#(..)"`, a regular expression over the digits (decimal and hex, leading zeros allowed), written as an automaton so that no two alternatives begin alike (`tools/xml_charref.py [--check]`; the check tries every number from 0 to 0x110010 in both bases) | 1 rule, 925 characters (`charref`, `predef`, `simple-ref` are the old `reference` split) | regular expression: every backend, not a context |
| Entity Declared | `ents` holds the general entities of the internal subset (`gen-entity`); `&name;` is `declared`, a name in `ents`; the five predefined are the token `predef`.  A document whose DOCTYPE has an external identifier or a `%name;` may have declared the name elsewhere: `open` is set there and `declared` accepts any name; `standalone="yes"` (`solo`) says it did not | 7 rules | context |
| No Recursion; and Entity Declared once more, for the names inside the text of an entity that is used | each entity declared with a text keeps the text in the context log next to its name (`%bind { }` after `entity-value`, `vals`); `declared` runs a `%where { }` that walks, from the entity named, the entities that the texts name, with a mark for the ones on the path and for the ones done (`safe` remembers the entity that passed, so each is walked once): a name met again on the path is a recursion, a name that is not declared (and not predefined, in a document that is not `open`) is an error | about 40 lines of C, once | context, `%where` and `%bind` code (C only) |
| Parsed Entity (no `&e;` of an NDATA entity in content), No External Entity References (none in an attribute value) | `unp` and `ext` hold the entities declared with NDATA and with an external identifier; `ent-ref("unp")` is the reference of content, `ent-ref("ext")` that of an attribute value (a parameterised rule over context names).  The first declaration of a name binds (`ents` is asked before), so `<!ENTITY e "x"><!ENTITY e SYSTEM ..>` is a parsed `e`, as in expat | the 4 alternatives of `gen-entity` | context |
| No < in Attribute Values | a `<` is not an `att-char` | already there | |
| In DTD (a parameter-entity reference only in the DTD) | `%p;` outside the DTD is text (`chardata` takes it), inside a declaration it is refused (as before) | already there | |

`open` and `solo` are flags: a set in which a name that matched nothing (`nil = ""`) is or is not.  A set cannot say "yes" without a name;
a context that kept a value with a name would not need them.

A reference in an entity value is read for its syntax and its character (`entity-ref`), not for its declaration (`<!ENTITY a "&b;">` with no `b`
is well formed until `&a;` is used); a reference in an attribute default is checked at the declaration, as expat does (`<!ATTLIST a x CDATA "&e;">`
needs `e` declared before it).

In C the constraints cost 14% of the tree parse and 24% of the tape (below).  The grammar is C only now: the contexts are in the C, Rust and Zig backends, but the
walk of the entities is code (`%where { }`, `%bind { }`), which only C has, so the Rust and Zig backends refuse the grammar (`compile_error!` at the
code) and Ada, which has no contexts, no longer generates it; before the walk the Rust and Zig parsers passed every test.  Tree-sitter leaves a context out and
never took this grammar.  Moving the walk out of the grammar needs a value kept with a name in a context (`CONTEXTS.md` section 13) in those backends.

## Not checked

The replacement text of an entity is not parsed as content when the entity is used (the walk only reads the names in it).  So these are accepted, the first with a
file in `corpus/xml/tests/loose`:

- an entity whose text is not balanced markup (`<!ENTITY e "<b>">` used in content);
- a `<` (`<!ENTITY e "&#60;">` in an attribute value) or an unparsed entity named inside the text of an entity that is used, and a
  character reference made by a bypassed `&#38;#0;`: the walk of the entities reads names, not markup;
- the checks of Namespaces in XML other than the lexical rule (a prefix bound to a URI, `xmlns` used as a prefix);
- `<!DOCTYPE name` naming the root element (a validity constraint), and everything else about validity;
- the external subset, conditional sections (`<![INCLUDE[`), `TextDecl` and external parsed entities
  (`originals/xml-1.0-external.bnf`): those are another file's text;
- XML 1.1 (`version="1.1"` is read as a version number and the rules are 1.0's), and the declared encoding, which is
  read and not used: a parser reads characters.  A byte order mark at the start is accepted; invalid UTF-8 is the
  decoder's, not the grammar's; a NUL byte ends the text of the C parser (a C string), so `<a/>` followed by a NUL and
  anything is accepted by it.

What these need is the text of an entity read as markup where the entity is used: a bounded island (`CONTEXTS.md` section 27: parse the
replacement text as `content`, with the declared entities and the entities being expanded in a context), or a value kept with a name in a context
(section 13), which the parser then expands and checks.  Neither is built.  The oracle (`tests/xml/oracle.py`) marks the documents they decide
(`L`), so the test counts them apart.

## Tests

`corpus/xml/tests/{good,bad,loose}` are 179, 324 and 1 hand-written cases, written from the
specification's productions and from the classes of error expat reports (`mismatched tag`, `junk
after document element`, `invalid token`, `unclosed token`, `duplicate attribute`, `undefined
entity` ...); `sh tests/xml.sh` runs them through the C parser (the `loose` file is accepted).  The 14 files that had been
in `loose` because the grammar did not check them are closed: thirteen are in `bad` now, and one (the entity that is not balanced) remains.  New: a dozen or more cases for each of the repeated attribute (`attribute-repeated-*` bad, `attribute-name-*` and
`attribute-same-name-*` good), the character reference (every boundary of `Char`: `char-reference-decimal-*` and `char-reference-hex-*`, good and
bad, in text, in an attribute value, in an entity value and in an attribute default) and the entity (`entity-predefined-*`, `entity-declared-*`
and `entity-undeclared-*` good, with an external subset, a parameter-entity reference or `standalone="no"`; `entity-reference-*` bad; `entity-recursive-*` bad and
`entity-chain-*`, `entity-diamond`, `entity-recursive-not-used` good).  `bench/formats/xml_cases.py`'s 34 ill-formed and 11 well-formed documents are refused and accepted
as expat does.
`sh tests/tapecap.sh` reads the same files through the tape parser (`--layout=tape`) and compares the verdicts with the tree's.  The W3C
XML Conformance Test Suite (`xmlconf`) is not in the repository (no download offline).

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
- **Entities.**  expat runs with all its own checks on (the grammar makes them now): an undeclared entity, a repeated attribute, a character
  reference out of range, an external or unparsed entity in an attribute value and an unparsed one in content are errors in both.  What the
  grammar does not check is marked `L` by the oracle: the two errors expat makes when an entity is used (`recursive entity reference`,
  `asynchronous entity`), the encoding (below), and any other error expat reports in the text of an entity that is used (an undeclared entity
  or a `<` inside it): the document is asked again with the texts of the entities made harmless, and when expat then accepts it the error was
  in the text.  The test allows the grammar to accept an `L` document and counts it; an error in the DOCTYPE itself is the grammar's.  One
  refused document in 20,000 would be reported apart: expat stops at the first error, and when that is an `L` one the oracle cannot say if there
  is a later syntax error.
- **Internal subset.**  A parameter-entity reference may stand between declarations and not inside one
  (not in an entity value either: `<!ENTITY e "%p;">` is an error in an internal subset), and the grammar
  and expat agree.

With 20,000 and 20,000 (seeds 7, 11, 23 and 101): every well-formed document accepted, the same answer as expat on every mutation but 4, 1, 1 and 1,
which are `L` (an error in the text of an entity that is used); no document that the grammar accepts and expat refuses outside that class, and none
that it refuses and expat accepts.  The random documents now declare the entities they refer to or have an external subset (`tests/xml/oracle.py`).
Gaps of the oracle found on the way: an `<!ATTLIST` inside a processing instruction taken for a declaration, and the second look at a document with
parameter-entity references, which now supposes an external subset.  The oracle is expat 2.9.0 (the container's Python 3.14); the host's
Python 3.13 has 2.7.1, which does not check the value of `version` in the XML declaration, so it accepts four `xml-decl-version-*` bad files and
`tests/xml-diff.sh` run there reports them.
The names: no difference from the Fifth Edition's ranges in 1,112,062 code points.

### Performance

The C parser reads the 2 MB generated catalog (`python3 bench/formats/gen.py xml 2000000`: 1,997,938 bytes, 37,094 elements,
35,951 attributes) with `bench/formats/time_xml_tree.c` and `time_xml_tape.c` (best of 25 runs, interleaved, pinned to one core on a
`cc -O2`, the generator with the SSE2 loop of main; the machine was moderately busy, the probe read 9 to 15 ms where quiet reads 8.5 to 9.6, so
the figures are relative to each other, not absolute):

| | before the constraints | with them | |
|---|---:|---:|---|
| tree | 2.68 ms, 9.8 MB | 3.05 ms, 11.9 MB | +0.37 ms (+14%) |
| tape (`--layout=tape`) | 2.53 ms, 5.7 MB | 3.14 ms, 7.7 MB | +0.61 ms (+24%) |

Of the tree's extra time (ablations of an earlier build, +0.58 ms in all, proportions only): the repeated-attribute check 0.4 ms (a hash lookup, a push and a pop for each of the 36,000
attributes), the legal-character regular expression 0.27 ms (a reference is checked as it is read: `&amp;` and the like are a token of five
literals first, the numbers a pass over the digits of an automaton), the entity table nothing here (the catalog has no entity but the predefined).
The memory is the attribute value, which is a small node now (a token when it holds no reference, a list of runs and references when it does).
Two repairs of the C generator keep the cost this small: a grammar with `context` and no `%where`/`%bind` code that reads the node keeps its string slices,
overlaid nodes and the arena put back (a grammar with `context` had none, 12.5 ms and 26 MB here), and a rule that puts the contexts back goes
straight to its body in the first pass (the tape had a fraction of its words).  (Expat from Python reads it in about 3 ms.)

## In the other outputs

C parses the 179 + 1 files and refuses the 324 (`tests/xml.sh`).  Rust and Zig refuse the grammar (they have no code for the walk of the entities), Ada has no contexts, and the tree-sitter backend still refuses it, as before.  `--layout=tape` works (a back-reference in a tape layout was fixed
earlier, and the tape of a grammar with a context holds all its words since the repair above) and is compared with the tree's verdicts on all 504
files by `tests/tapecap.sh`.
