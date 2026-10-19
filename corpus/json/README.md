# JSON (RFC 8259) in hbnf

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

## Checked against Python's `json`

JSON is exactly defined, so there is no reason for any difference, and the check allows
none.  `sh tests/json-diff.sh [N [SEED]]` generates N random valid documents (nested to five
levels; strings with every escape, control characters, Unicode outside the BMP; integers
up to thirty digits; floats in every notation; indented, compact and loose) and N mutations of
them (a character deleted, inserted, replaced, swapped, doubled, or the text cut), and asks
the parser hbnf makes and Python's `json.loads` (strict, `NaN` and `Infinity` refused)
about each.  Run with 40,000 and 40,000: every valid document accepted, and the same
answer on every mutation (13,000 of the first 3,000 were accepted, the rest refused).
`tests/good` and `tests/bad` are 26 and 48 hand-written cases, in the style of the
well-known JSONTestSuite, and Python agrees with where each is filed.

In Tree-sitter (`sh tests/treesitter.sh corpus/json/json.hbnf corpus/json/tests/good
corpus/json/tests/bad`) the grammar needs no conflict declared, parses all 26 good cases and
shows an error on 47 of the 48 bad ones (Tree-sitter reads a byte-order mark as part of the
file's encoding, so `bom.json` parses); `TSD_GRAMMAR=corpus/json/json.hbnf
TSD_ORACLE=tests/json/oracle.py TSD_EXT=json sh tests/treesitter-diff.sh` finds no
difference between hbnf and Tree-sitter on 2,000 documents and 2,000 mutations.

The writer round-trips every good case (`tests/writer.sh`).

Not done: decoding `\uXXXX` (and surrogate pairs) into code points is the UTF-16 step of
`CHARLAYER.md`, which is not built; the parser reads a `\u` followed by four hex digits as
the text it is, which is all RFC 8259's grammar asks.
