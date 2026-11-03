# SGML in HyperBNF

`sgml.hbnf` reads the part of SGML (ISO 8879:1986) that a grammar can read: the **document type declaration** with
the markup declarations that fill it, the **SGML declaration**, and the **instance at the level of markup** in the
reference concrete syntax.  `sgml-instance.hbnf` holds the instance (tags, references, marked sections, data) and
`sgml-tokens.hbnf` the tokens (a name, a literal, a comment, a reference): 85 rules, 100 lines of grammar and 5.7 KB
without the comments.

There are two entry points.  `document`, the first rule, reads a whole document: an optional SGML declaration, a
prolog, an instance.  `dtd` (`--root=dtd`) reads a file of declarations, the external subset of a DTD or an entity set
such as `HTMLlat1.ent`.  Both generate in the C, Rust, Zig and Ada backends, and `tests/sgml.sh` runs all four.

## What a grammar cannot do

SGML is not context-free at the level of a whole document.  What a document's text means depends on its DTD, and the
grammar reads the DTD as text too, so it cannot apply it:

- **Omitted tags.**  `<p>one<p>two` is two paragraphs because the DTD says `<!ELEMENT P - O ...>`: the end tag may be
  left out, and a start tag that cannot be inside an open `P` closes it.  Which tag was left out is worked out from the
  content models.  The grammar reads the tags that are there as a flat run and does not match a start tag with its end
  tag.  (A NET element, `<b/bold/`, is the one nesting it reads, since its end is a character and not an inference.)
- **Short references.**  Only the delimiters of the reference concrete syntax are read.  `<!SHORTREF>` and `<!USEMAP>`
  are read as declarations; what a quote or a line end then means in the instance is the map's business, and the
  instance grammar reads them as data.
- **A changed concrete syntax.**  The `SYNTAX` section of the SGML declaration can give `<`, `>` and every other
  delimiter a new spelling, and the instance is then another language.  The declaration is read in full and none of it
  is applied (see "Islands and switches").
- **Parameter entities.**  `%name;` is a reference to text, and the text may be a connector, a flag, a group or a
  whole attribute definition.  The grammar takes a `%name;` where a name, a group or a definition may stand and cannot
  see what the entity makes of it.  `<![ %draft; [ ... ]]>` is read as an included section, so its declarations are
  checked, though the entity may say IGNORE.  A definition list that mixes parameter entities with unquoted default values
  can be read two ways: in `Id %idreq; Role CDATA #IMPLIED`, `Role` is taken as the default of `Id` (the entity may
  have made `%idreq;` a whole definition), and the line is refused.  The HTML 4.01, DocBook and TEI files read, because
  their entities come before an attribute name that no declared value can follow.
- **Names.**  Names are case-insensitive, and so are the keywords (`sensitivity string %i`); the grammar compares no
  names, so that an end tag names its start tag, that an entity is declared, that an attribute exists, is not checked.
  A name is a letter and any run of letters, digits and `. - _ :` (the HTML 4.01 declaration's set; the reference syntax
  has `. -` and NAMELEN 8), and the capacity figures are not checked.
- **Attribute values.**  `<td nowrap>`, `<input checked>` and `<p "x">` are one form, a value alone; which attribute
  it belongs to is the declared value's to say.  A value with `/` in it (`src=a/b.gif`) ends at the `/`, as the reference
  syntax has it, because `/` is the NET delimiter.
- **Keywords that run on.**  `sensitivity string %i` makes a keyword a prefix match: `<!ELEMENTa - O EMPTY>` reads as
  `ELEMENT a`, and in a choice `IDREFS | IDREF | ID` has to be written longest first.  See "Limits of the notation".
- **Not read at all:** `<!LINKTYPE>` `<!LINK>` `<!IDLINK>`, the attribute specification list of a data entity
  (`NDATA gif [ width=10 ]`), rank suffixes (`h#`), `CONCUR` document type names in tags (`(a)<p>`), and what `DATATAG`
  allows.

## What is read

Productions are named as the standard names them.  The numbers of its productions are not given: I cannot reproduce
them from memory and a wrong number would mislead.  The clause numbers in the table are from memory too and may be
a little off.

| Part | Rules | ISO 8879 |
|---|---|---|
| Document, prolog | `document` `prolog-item` | SGML document entity, prolog |
| DOCTYPE | `doctype` `external-id` | document type declaration (11.1): external identifier, internal subset |
| `<!ELEMENT>` | `element` `element-names` `omit` `content` `model-group` `model-token` `occur` `exceptions` `inclusions` `exclusions` `name-group` | element declaration (11.2): omitted tag minimization, declared content `CDATA` `RCDATA` `EMPTY` `ANY`, content model with the connectors `,` `&` `\|` and the occurrence indicators, exceptions |
| `<!ATTLIST>` | `attlist` `attdef` `declared-value` `default-value` | attribute definition list declaration (11.3): the declared values, `#REQUIRED` `#IMPLIED` `#CURRENT` `#CONREF` `#FIXED`, name token groups, `NOTATION` groups, `#NOTATION` |
| `<!ENTITY>` | `entity` `entity-type` `data-type` `external-id` | entity declaration (10.5): general and parameter, `CDATA` `SDATA` `PI` `STARTTAG` `ENDTAG` `MS` `MD`, external with `PUBLIC` or `SYSTEM`, `NDATA` `CDATA` `SDATA` `SUBDOC`, `#DEFAULT` |
| `<!NOTATION>` `<!SHORTREF>` `<!USEMAP>` | `notation` `shortref` `usemap` | notation declaration, short reference mapping and use declarations |
| `<!SGML ...>` | `sgml-declaration` and 15 more | SGML declaration (13): `CHARSET` `CAPACITY` `SCOPE` `SYNTAX` `FEATURES` `APPINFO` section by section, down to the `QUANTITY` names |
| Comments | `com` `comment-decl` | comment declaration (10.3): `-- ... --` pairs, any number, in a declaration and in `<!-- -- -->` |
| Marked sections | `include-open` `ignore-open` `raw-open` `ignored` `raw` `dtd-section` `section` | marked section declaration (10.4): `INCLUDE` `IGNORE` `TEMP` `CDATA` `RCDATA` and a parameter entity, nested ignored sections counted |
| Processing instructions | `pi` | processing instruction |
| References | `pe-ref` `entity-ref` `char-ref` | parameter entity, general entity and character references, the reference close left out |
| Instance | `instance` `content` `start-tag` `end-tag` `net-element` `tag-head` `attribute` `data` | start tag, end tag, the empty tags `<>` and `</>`, a NET-enabling start tag with its null end tag, the attribute specification list in its three forms, data characters, an unclosed tag (`<a<b>`) |

How the grammar is meant to read:

- **A declaration is `<!`, a keyword, its parameters, `>`.**  `decl(P) := "<!" P ">"` says that once, a pattern rule,
  and `element = decl("ELEMENT" ...)` is each declaration's own part.  (The generator names the tree type of such a rule
  from its pattern, a long `decl_attlist_...`; `attlist_t` and the others are typedefs of those.)
- **Blanks and comments between parameters are the grammar's white space**, `ws = *( blank | com )`, so a declaration
  mentions none of it and the `-- ... --` comment is allowed wherever a blank is, as in the standard.  A comment
  declaration is `<!` and `>` round the comments, a token (`comment-decl`) that spells the comments out, because the
  instance has no `ws` to eat them; the declarations do not use it between their parameters.
- **In the instance white space is data.**  `sgml-instance.hbnf` and `sgml-tokens.hbnf` say `whitespace none`, and their
  rules skip nothing; the grammar's `ws` is used by the rules of `sgml.hbnf` only.  The per-file directive does here what
  an island is for.
- **A model group has one connector.**  `(a, b | c)` is refused as the standard refuses it: a first token, then any
  number of `, token`, or of `| token`, or of `& token`.
- **An occurrence indicator follows at once.**  A `+` after a group is an indicator unless a `(` follows it (the grammar
  skips blanks before it looks), in which case it begins an inclusion: `(a)+ +(b)` and `(a) +(b)` read as the standard
  has them, and `(a)+(b)` and `(a)+ (b)` as inclusions, where the standard has an indicator and a stray group.
- **The attribute forms.**  `name=value`, a name token alone and a value alone are one rule, since the last two are
  the same text: `attribute = [ name-token "=" ] ( literal | name-token )`.
- **The raw and the ignored.**  A CDATA or RCDATA section is a token up to `]]>`; an IGNORE section is a recursive one
  that counts `<![` and `]]>`.

## Checked

`sh tests/sgml.sh` generates the parser in every backend installed (`SGML_BACKENDS="c rust"` for fewer) and runs it on
`tests/good` (58 files, all accepted) and `tests/bad` (84 files, all refused): the `.sgml` files are documents, the
`.dtd` files `--root=dtd`.  `tests/bad/REASONS.tsv` gives for each bad file the line where it must be refused and the one
reason it states, and the C parser's refusal is compared with it, so that a file is not refused by accident, for another
fault than its name says (a bad file and its reason: an unterminated declaration, one minimization flag where there are two,
`(a, b | c)`, `(a b)`, `-- no end`, `#REQURED`, a short reference with no entity name, a marked section with no `]]>` ...).

No SGML parser was available (OpenSP/`onsgmls` is not installed and there is no network), so there is no oracle: the
corpus is checked against the author's reading of the standard.  Where the files look real they are reconstructions
from memory:

- `html401-strict.dtd` is a reconstruction of the HTML 4.01 Strict DTD, all of it (the entities, `%attrs;`, the head,
  body, lists, forms and tables), close to the original in its declarations and not word for word in its comments.  It
  was the real-world test: the grammar was changed until it read this, and what that took is the interesting part
  (`-- comments --` after every attribute, a parameter entity as a declared value, as a default and as a whole list of
  definitions, `<!ELEMENT (%fontstyle;|%phrase;) - - (%inline;)*>`, an exclusion through a parameter entity).
- `sgml-reference-declaration.sgml` is the SGML declaration of the reference concrete syntax as the standard prints it,
  from memory of its layout, and `sgml-html4-declaration.sgml` the one of HTML 4.01.
- `docbook-pool.dtd`, `docbook-hierarchy.dtd` and the two TEI files are excerpts written to follow the conventions of the
  DocBook 3/4 SGML and TEI P3 DTDs (`<!ENTITY % local.para.char.mix "">` hooks, `%common.attrib;`, `<![ %x; [ ... ]]>`,
  `%n.p;` for element names, single-quoted literals).  They are not copies.
- `html-latin1.dtd`, `html-symbol.dtd` and `html-special.dtd` are the heads of the three HTML entity sets.
- The order of exclusions and inclusions in an element declaration is read both ways, since I am not sure which the
  standard puts first.

## Islands and switches

Three experiments, in `experiments/` (not in the suite; their outcomes are the comments at the top of each file).

- **An island does what is wanted of it, and is not needed.**  `include "sgml-instance.hbnf" as inst` and `inst.instance`
  generate in C, Rust, Zig, Ada and tree-sitter, and the C parser says the same of the 57 documents (28 accepted, 29 refused).  But `sgml.hbnf` has
  the effect already: the instance's files say `whitespace none` and the declarations' file has a `ws`, per file, in one
  scope.  What an island cannot hold is a pattern rule: `content(D)` inside `inst` is refused, "rule `D` is not defined
  in grammar `inst`", so the experiment writes it out three times.  An island would pay if the same name had to mean two
  things (a `name` of the declarations and another of the instance), which SGML does not ask.
- **`=> grammar(x)` for a CDATA section works, and is the wrong tool.**  `<![CDATA[` switches to a grammar whose white
  space is everything up to `]]>`, and `]]>` switches back; C accepts and refuses the right texts, Rust, Zig and Ada
  generate it, tree-sitter refuses a switch.  The text is skipped as white space, so it is not in the tree, where
  `raw` as a token keeps it.  The white-space rule cannot say "up to `]]>`" exactly: a lookahead inside what a rule of
  characters repeats is refused by the C backend (`*( !"]]>" any )`; Rust, Zig and Ada took it without a word), and
  the version that is accepted gives up on `]]]>`.
- **A change of delimiters is refused.**  A grammar `alt` that redefines the token rules `stago` and `tagc`, switched
  to after `SYNTAX`, is refused: "`alt.stago` is defined, and the including grammar has a rule `stago` too ... a grammar
  a parser switches to replaces white space only so far".  That is CONTEXTS.md section 22 as written; token rules are
  its next step.  Even then only a *named* syntax could be a switch (`SYNTAX PUBLIC "ISO 8879:1986//SYNTAX Reference//EN"`
  could pick the grammar `reference`); a declaration that spells its own delimiters (`DELIM GENERAL SGMLREF STAGO "["`)
  is a grammar made while the parser runs, which no `=> grammar(x)` of a grammar written beforehand can be.

Tree-sitter: `--backend=tree-sitter` writes a `grammar.js` for both entry points, with a warning that the lookaheads
(the `<` and `&` of data, `]]>` in a section) are left out, so a text where a `<` is not a tag is ambiguous there.  The
`grammar.js` was not run through `tree-sitter generate`: there was no `node` (the node directory of `hbnf-build/ts` is
empty), so whether it generates, and with how many conflicts, is not known.

## Limits of the notation met on the way

Found while writing this grammar; none is fixed here.  Each had a workaround, which the grammar uses.

- **`sensitivity string %i` has no word boundary.**  A letter-led literal is matched as a whole word only when the grammar
  names `word` or lists `keywords`; without that it is a `strncasecmp` prefix, and `ID` matches the front of `IDREF`.
  With it a rule of type `word` refuses every word that is a keyword anywhere, so `name` could not be an attribute name
  since `NAME` is a declared value, and SGML has no reserved words.  The grammar names no `word` and writes the longer
  keyword first (`IDREFS | IDREF | ID`).
- **A literal passed as a word parameter (`decl(K, P)` with `K` = `"ELEMENT"`) does not take the file's
  `sensitivity string %i`**, and generation stops with "the keyword `ENTITY` is written both with `i"..."` and without".
  A literal inside a pattern argument does (`decl("ELEMENT" ...)`), which is how it is written.
- **A rule called `flag` is the built-in `flag` (yes or no), silently.**  `word` and `atom` get a warning that the rule is
  renamed; `flag`, `bool`, `int` and the others get none, and the parser says "expected yes or no".  The minimization
  flag is `omit`.
- **A rule of only literals and token rules is itself a token and skips no blanks inside.**  `appinfo = "APPINFO" ( "NONE" | literal )`
  matched `APPINFOnone` and not `APPINFO NONE`; the same words with an optional or a repetition in them are phrases.  The
  grammar says `appinfo = "APPINFO" ps ( ... )`, the separator spelled out.
- **A pattern rule inside an island** is refused, as above.
- **Ada: a rule that is a list and contains itself** (`ignored = *( "<![" ignored "]]>" | ... )`) generates a record that
  uses its own vector type before the type is declared (`"Ignored_Type" is undefined`).  Giving the entry its own rule
  (`ignored = *ignored-part`) is the cure.
- **A rule of characters with a lookahead is read a character at a time** and builds a node for each (the warning on
  `end-tag` and `raw`).  The runs `1*~"]"` carry the common case in `raw` and `ignored`, and the lookahead is only for the
  `]` that may begin the end.  `end-tag` could be a token if the unclosed `</a<b>` were not read.
- **Generation takes about 20 seconds** (`hbnf-w433`, on a machine with other work).
