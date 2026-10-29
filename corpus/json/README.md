# JSON (RFC 8259) in HyperBNF

`json.hbnf` (the structure) and `json-tokens.hbnf` (a string and a number, where no blank
is allowed inside one) are the whole of JSON in 14 rules, against the RFC's 30 ABNF rules:
the RFC's rule for each punctuation mark is the quoted character, and a comma list is
`x *( "," x )`.  Measured with comments and blank lines left out of both, the RFC's
grammar is 45 lines, 193 symbols and 949 characters, and this is 14 lines, 129 symbols and
556 characters.

The tokens are in their own file because a rule is a *token* (a string, scanned by an
automaton, with no tree) only in a file that skips no white space; `json-tokens.hbnf` says
`whitespace none`, and `json.hbnf` skips the blanks between the rest.  (A rule called
`int` would be hbnf's own number, so the integer part is `integer`.)

## Onto a tape, with no tree

`json-tape.hbnf` is the same language with an `%emit{ }` where the tree would have made a node:
an object or an array is opened where its bracket is read, a string, number or literal is a tag
and the place of its text, and the closing bracket links the opener to the position after it.
The parser makes no struct and no list node, only a flat array of 64-bit words, which is the
layout a hand-written reader would choose.  `sh tests/emit.sh` generates it, compiles it and checks
that the tape holds as many values of each kind as Python's `json` finds in every good document
of `tests/good` and that every document of `tests/bad` is refused.

## Checked against Python's `json`

JSON is exactly defined, so there is no reason for any difference, and the check allows
none.  `sh tests/json-diff.sh [N [SEED]]` generates N random valid documents (nested to five
levels; strings with every escape, control characters, Unicode outside the BMP; integers
up to thirty digits; floats in every notation; indented, compact and loose) and N mutations of
them (a character deleted, inserted, replaced, swapped, doubled, or the text cut), and asks
the parser hbnf makes and Python's `json.loads` (strict, `NaN` and `Infinity` refused)
about each.  Run with 40,000 and 40,000: every valid document accepted, and the same
answer on every mutation (13,000 of the first 3,000 were accepted, the rest refused).
`tests/good` and `tests/bad` are 27 and 48 hand-written cases, in the style of the
well-known JSONTestSuite, and Python agrees with where each is filed.

In Tree-sitter (`sh tests/treesitter.sh corpus/json/json.hbnf corpus/json/tests/good
corpus/json/tests/bad`) the grammar needs no conflict declared, parses all 27 good cases and
shows an error on 47 of the 48 bad ones (Tree-sitter reads a byte-order mark as part of the
file's encoding, so `bom.json` parses); `TSD_GRAMMAR=corpus/json/json.hbnf
TSD_ORACLE=tests/json/oracle.py TSD_EXT=json sh tests/treesitter-diff.sh` finds no
difference between hbnf and Tree-sitter on 2,000 documents and 2,000 mutations.

The writer round-trips every good case (`tests/writer.sh`).

`true`, `false` and `null` are rules of their own (`literal-true`, `literal-false`, `literal-null`)
rather than quoted text in `value`, because a quoted literal leaves no field in the tree and the three
would look alike: the tree of a `value` has the field of the one that was read set, and the others nil.

The C parser stops at `HBNF_MAX_DEPTH` rules nested at once (4096 by default, about 1,365 levels of
JSON; override with `-DHBNF_MAX_DEPTH=n`) and reports "shallower nesting" as an error.  Without the limit
a document of 50,000 `[` ran the stack out and the parser died of a segmentation fault, which a program
reading JSON off a network cannot afford.

Not done: decoding `\uXXXX` (and surrogate pairs) into code points is the UTF-16 step of
`CHARLAYER.md`, which is not built; the parser reads a `\u` followed by four hex digits as
the text it is, which is all RFC 8259's grammar asks.
