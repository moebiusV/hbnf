# HTML in HyperBNF

`html.hbnf` is the syntax of a conforming HTML document, as section 13.1 "Writing HTML documents" of the
[WHATWG HTML Living Standard](https://html.spec.whatwg.org/multipage/syntax.html) writes it: the doctype, elements
with their start and end tags, the elements whose tags may be left out, void elements, attributes in their
three quoted forms, text and character references, comments, CDATA in svg and math, and the elements that hold
raw text (`script`, `style`) or escapable raw text (`textarea`, `title`).  `html-tokens.hbnf` has the
characters (white space, names, references, attribute values, comments).  It is not the parser of section 13.2,
which reads any text and recovers from every error, and it knows nothing of the content model (which element
may hold which).  The standard has no grammar of the syntax: 13.1 is prose, and the tokenizer of 13.2.5 is a
state machine of about eighty states that also says what to do with every error, so there is nothing to count
against (`bench/notation.sh` has no HTML baseline, and none was made up).

## Size

Measured by `python3 bench/count.py hbnf-code`, comments and blank lines left out:

| | rules | lines | symbols | characters |
|---|---:|---:|---:|---:|
| `html.hbnf` + `html-tokens.hbnf` | 52 | 65 | 665 | 3772 |
| with `html-islands.hbnf` (see below), without `js-stub.hbnf` | 53 | 66 | 671 | 3829 |

Eleven of the 52 are hyperrules: the whole family of omissible end tags is `omit(N, S)` and `last(N)`, written once,
and the elements are twenty calls; the two raw-text forms are `raw-element(N)` and `rcdata-element(N)`; characters
up to something, with the references among them, are `chars(X)`, which reads element text, a title, and the
three forms of attribute value alike.

## What is read

- **The document**: an optional byte order mark, comments and white space, a doctype (`<!DOCTYPE html>` in any case,
  with blanks before the `>`, or the one legacy form 13.1.1 permits, `<!DOCTYPE html SYSTEM "about:legacy-compat">` in
  either quote).  `PUBLIC` doctypes are not conforming and are refused.  Then nodes.
- **Elements**: a start tag, content, and an end tag that has the name of the start tag; void elements
  (`area base br col embed hr img input link meta source track wbr`) with `>` or `/>` and no end tag; any name that starts
  with a letter, so custom elements (`x-y`) read like the rest.  A `/>` on any other HTML element is refused.
- **Attributes**: blank, name, and optionally `=` (blanks allowed on both sides) and a value, unquoted (not empty, none of
  `"'=<>` and the backtick, no blank), single-quoted or double-quoted.  After a quoted value a blank must come before the
  next attribute.  A name is made of anything but controls, blanks, `"` `'` `>` `/` `=` and `<`.
- **Text and references**: `&name;`, `&#65;`, `&#x41;` (and `&#X41;`).  A `&` that does not start a reference is text.
  A `<` is never text.  The characters of a document are those 13.1.1 allows: no NUL, controls other than blanks,
  surrogates or noncharacters (the last two code points of each plane above the first are not left out).
- **Comments**: `<!--` ... `-->`, not starting with `>` or `->`, not holding `<!--`, `-->` or `--!>`; two hyphens by
  themselves are fine, as in the standard (html5lib's strict mode disagrees).
- **Raw text**: `script` and `style` hold anything up to `</script` or `</style` followed by a blank, `/` or `>`;
  `textarea` and `title` the same with character references.  The end tag takes no attributes.  The double-escape quirk of
  script data (`<!-- <script> ... </script> -->`) is not modelled: the first `</script` ends the element, as the tokenizer's
  outer state does.
- **Foreign content (svg, math)**: elements of any name, `<x/>` or `<x>...</x>`, comments, and **CDATA sections, which
  are read only here** and refused in HTML elements (`<p><![CDATA[x]]></p>` is an error, as 13.1.5 says).  Inside svg the
  integration points `foreignObject`, `desc` and `title` hold HTML again.  The HTML elements that break out of foreign content
  (`<p>` in an svg) are not refused, and the integration points of math are not modelled.
- **Omitted tags (13.1.2.4)**, as far as no content model is needed:
  - *End tags, done*: `li dt dd p rt rp optgroup option colgroup caption thead tbody tfoot tr td th`, and `html head body`.
    An element with such an end tag ends where its end tag is, before the end tag of its parent or the end of the text, or
    before a start tag that cannot be inside it: `li` before `<li>`, `dt` and `dd` before `<dt>` or `<dd>`, `p` before the
    twenty-odd block-level start tags, `option` before `<option>` or `<optgroup>`, `tr` before `<tr>`, `td` and `th` before
    `<td>` or `<th>`, `thead` and `tbody` before `<tbody>` or `<tfoot>`, `rt` and `rp` before `<rt>` or `<rp>`, `head` before
    `<body>`, `caption` and `colgroup` before a table part.  `tfoot`, `body` and `html` end only with their parent or the text.
  - *Start tags, done* by not requiring them: `html`, `head`, `body`, `colgroup` and `tbody` start tags may be missing, and the
    end tags `</head> </body> </html>` (at the top of the document or of `<html>`) and `</colgroup> </tbody>` (in a table)
    are read with no start tag.  A parser that wants the tree the content model gives (`<tr>` inside an implied `tbody`) needs
    the content model; the grammar only accepts the same documents.
  - *Not done*: the conditions about what follows (`head`, `colgroup` and `caption` end tags may be omitted only if the next thing
    is not a blank or a comment); that `p` and the rest may be left open only if the parent is not `a`, `audio`, `del`, `ins`,
    `map`, `noscript`, `video` or a custom element, or an svg element; that a `p` closed by a block start tag must have
    been one a content model allows.
- **Not read**: `plaintext`, `xmp`, `iframe`, `noembed`, `noframes` and `noscript` as raw text (all obsolete or switched by the
  scripting flag), `template` content (read as ordinary markup), the content model, attribute names and values that the
  standard defines (a `class`, an `href`, a number), duplicate attributes, the table of 2,231 named references (a name between
  `&` and `;` is any letters and digits; 13.1.4 asks for one in the table), the legacy names that are references without a
  `;` (`&amp ` is text), what a numeric reference may name (`&#0;`, a surrogate, a C1 control), text that is whitespace-only
  where the content model does not want text, the language of a `lang`, `<meta charset>` against the real encoding, the
  length of anything.

## Two things the notation does not say

- **An end tag has to repeat the case of its start tag.**  `as tag` keeps the text of the tag name and `$tag` repeats it
  byte for byte, so `<DIV>...</div>` is refused, though the standard (and html5lib) fold the case of tag names.  Every
  other keyword of the grammar ignores case (`sensitivity string %i`).  The elements that have a rule of their own (`script`, `p`,
  `li`, ...) match their end tag with a literal and fold the case.
- **A big comment or script is a list of characters in the tree.**  A rule of characters that holds a lookahead of more than one
  character (`!"-->"`, `!"]]>"`, the end tag of a script) is read one character at a time and the tree has a node for each:
  the generator warns of it for `html-comment`, `cdata` and `raw-closing-script` / `raw-closing-style`.  The text parses
  quickly (C, `-O2`: a script of half a megabyte in 0.01 s, a megabyte of markup in 0.07 s) but its node is not a single string.

## Raw text and the island features

`html-islands.hbnf` is `html.hbnf` with the inside of `<script>` read by another grammar, `js-stub.hbnf` (a small JavaScript
stub: `var`, assignment, call, `if`, strings, numbers, `//` comments), through `include "js-stub.hbnf" as js` and one rule,

    script = open(i"script") js.program *space end(i"script")

It works in the C, Rust, Zig and Ada backends and gives the same answer as `html.hbnf` on all 100 cases when the stub
can read the script.  What it shows:

- The script ends where the *guest* stops, not at `</script`.  A script that holds the string `"</script>"` is one script to
  the island variant, which reads the string to its closing quote, and two things to a browser, which ends the element at the
  first `</script` whatever JavaScript thinks of it (`tests-islands/guest-reads-past-end-string.html`).  The raw text of
  HTML is a decision of the tokenizer, which runs before the language of the script; an island puts the decision in the guest.
  The plain grammar's `script` is therefore the faithful one.
- A guest is not skipped for white space in the host's way: the host skips none, a guest that skipped its own would make two
  white-space rules in one parser, and the generator refuses it, so `js-stub.hbnf` says `whitespace none` and takes its
  blanks and comments itself.
- A hyperrule defined in the guest, and a lookahead (`!x`) on a rule of the guest, are not found in the scope.
- `=> grammar(js)` after `<script>` does generate, and changes nothing the document could show: the switch replaces
  the white space skipped, HTML skips none, and the raw text is still read by the rules of the host.  There is no way back,
  either: `=> grammar(x)` names an included file, and the host cannot include itself.  The island is the form that does the job.

## Checked against html5lib

`sh tests/html.sh` runs the 100 files of `tests/` (below) and the 8 of `tests-islands/` through the C, Rust, Zig and Ada
parsers.  `sh tests/html-diff.sh [N [SEED]]` asks the C parser and Python's `html5lib` (`HTMLParser(strict=True)`, which raises
on the first parse error of 13.2, that is on a document that does not conform) the same questions (`PYTHON=` a python that
has it; without, only the files are run).  The oracle is `tests/html/oracle.py`; lxml (libxml2, an HTML 4 parser) was asked as
a second opinion (`oracle.py --lxml check`) and is no help: it accepts 20 of the 40 refused files and refuses 12 of the 41
good ones, since it does not know `section` or `svg`.

The 100 files are written from the examples of 13.1 and the classes of error html5lib reports, in four folders by what the
two are expected to say:

| folder | files | grammar | html5lib |
|---|---:|---|---|
| `tests/good` | 41 | accepts | accepts |
| `tests/bad` | 40 | refuses | refuses |
| `tests/oracle-stricter` | 16 | accepts | refuses |
| `tests/grammar-stricter` | 3 | refuses | accepts |

Where they differ, by design:

- *html5lib checks what a syntax cannot* (12 of the 16): a named reference not in the table, `a &b` or `&amp ` with no `;`, a
  numeric reference to U+0000, a duplicate attribute, `<td>` outside a table, a nested `a`, a `div` in a table, an `<a>` or
  an svg holding a `p` whose end tag is left out (the standard allows leaving it out only if the parent is an HTML element
  that is not `a`), a `<br>` in an svg (it breaks out of foreign content), and a `<caption>` closed by an omitted end tag
  (html5lib answers "Undefined error", which is its tree builder failing on a legal document).
- *html5lib is older or stricter than the standard* (4): `<!-- a -- b -->`, `<!-- a --->` and `<!-- a --!-->` are
  conforming comments, and a doctype with `SYSTEM "About:Legacy-Compat"` is too, the string being matched without regard to case.
- *the grammar is stricter than html5lib* (3 files): an end tag in another case than its start tag (`<DIV>x</div>`, above).

`html-diff.sh` also generates N random valid documents (every omissible end tag, raw text, svg with CDATA and
integration points, math, references, all forms of attribute and doctype, a byte order mark) and N mutations of them (a
character deleted, inserted, replaced, swapped, doubled, the text cut).  Every valid document is accepted by both.
For the mutations, html5lib's refusals are told apart by their message: those that are about what a document means (the
list in `oracle.py`) are counted apart and either answer of the grammar is agreement; any other difference fails.  With
20,000 documents and 20,000 mutations (seed 5): 15,317 agree, 4,683 are meaning (the grammar refuses 3,961 of them and
accepts 722: unknown reference names, legacy references with no `;`, numeric values, `--` in a comment, elements where
the content model does not want them, an end tag in another case than its start tag), none differs otherwise.  Seeds 1, 3,
5, 7, 11, 21 and 22 were run, 5,000 to 20,000 each.
What the "meaning" class can hide is a document the grammar wrongly accepts that html5lib refuses for a reason on the list;
the list was made from the messages of the first runs, each one read against the standard.
