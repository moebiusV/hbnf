# RFC 5234, Appendix B.1: the core rules

`core.hbnf` is the sixteen core rules, verbatim.  `core.fixed.hbnf` is the same
text with the changes hbnf needs, each marked `; hbnf:`.  `vectors/` holds the
inputs each rule must accept and refuse; `tests/rfc.sh` runs them.

## What hbnf says to the RFC's text

Any rule can be tried on its own: `hbnf core.hbnf --root=RULE`.

Fifteen of the sixteen rules compile as written.  That includes the ones that
write `/`, because every alternative is one code point (`BIT = "0" / "1"`,
`HEXDIG = DIGIT / "A" / "B" / ...`, `CTL = %x00-1F / %x7F`).  One does not:

    LWSP = *(WSP / CRLF WSP)

    hbnf: core.hbnf:37:25: `/` is ABNF's union, which hbnf takes only between
    alternatives that each match one code point (a %x value, a 'c' literal, a
    one-character string, or a rule of them) so far (RFCPLAN.md step 5); write
    `|`, ordered choice, longest first

`WSP` and `CRLF WSP` cannot begin with the same character, so ordered choice is
the union, and writing `|` is the whole repair.

## The fixed-up version

Two lines are added, and one rule changes.

- `whitespace none`.  hbnf skips blank space between the elements of a rule
  unless told not to; ABNF skips nothing, and where a space counts the RFC
  writes it.  Without this, `SP` could never match: the skip would take the
  space first.
- `sensitivity string %i`.  A literal in ABNF is case-insensitive (`"A"` is `a`
  or `A`); in hbnf it is not unless the file says so.  Without this, `HEXDIG`
  would refuse `a` and every RFC that uses it would silently disagree with the
  RFC.  A case-insensitive literal in a grammar with no words compares bytes, in
  either case.
- `LWSP`: `/` becomes `|`.

## What the vectors say about the text itself

`OCTET = %x00-FF` is eight bits in ABNF.  hbnf reads its input as UTF-8 and
matches code points, so `OCTET` matches a code point up to U+00FF, which is one
byte only for ASCII.  That is a difference between the notations, not a bug in
the rule; a grammar over bytes is the `binary` layer (RFCPLAN.md step 5).
