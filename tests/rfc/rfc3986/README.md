# RFC 3986, Appendix A: Collected ABNF for URI

`uri.hbnf` is the whole appendix, verbatim; its only addition is the `include`
that supplies RFC 5234's `ALPHA`, `DIGIT` and `HEXDIG`.  `uri.fixed.hbnf` is
the same rules as hbnf reads them.  `vectors/` holds 23 rules' inputs
(`scheme`, `host`, `IPv6address` and the rest of its closure, the path forms,
`URI`); `host` and `IPv6address` run in all four backends, the rest in C.

## What hbnf says to the RFC's text

Nearly every rule that names an alternative that is not one code point is
refused, with the same message:

    hbnf: uri.hbnf:31:28: `/` is ABNF's union, which hbnf takes only between
    alternatives that each match one code point (...); write `|`, ordered
    choice, longest first
      host          = IP-literal / IPv4address / reg-name

(`scheme`, `unreserved`, `sub-delims`, `IPvFuture` and the rest of the
character-level rules compile as written.)  And one more:

    hbnf: uri.hbnf:70:18: not written yet, in `path-empty`: <pchar>
      path-empty    = 0<pchar>

## The fixed-up version

The change made everywhere, and not marked each time, is `|` for `/`.  That is
a correct repair only where the alternatives cannot both match, and the RFC does
not promise that.  Where they overlap, ordered choice commits to the first that
matches and never goes back, so the order is part of the repair:

- **`dec-octet`**: the RFC lists the alternatives shortest first.  `|` would take
  `2` out of `255` and never try the rest.  Longest first: `"25" %x30-35`, then
  `"2" %x30-34 DIGIT`, `"1" 2DIGIT`, `%x31-39 DIGIT`, `DIGIT`.
- **`IPv6address`**: the RFC's left part, `[ *1( h16 ":" ) h16 ]`, takes the
  `:` of `::` for a separator, finds no `h16` after it, and as an optional that
  failed gives up its groups, so `1::2` fails.  Written `[ h16 *1( ":" h16 ) ]`
  it stops before the `::`.  The alternatives already run longest right part
  first, which is what ordered choice needs.  27 inputs, in all four backends.
- **`host`**: `IP-literal / IPv4address / reg-name` is ambiguous (a dotted quad
  is also a `reg-name`; RFC 3986 section 3.2.2 says so).  `|` commits to
  `IPv4address` and takes `1.2.3.4` out of `1.2.3.4.5`, then fails where the RFC's
  union goes on to `reg-name`.  `host = IP-literal | reg-name` accepts the same
  language; an address parses as a `reg-name`.
- **`path-empty = 0<pchar>`**: `<pchar>` is a prose-val in ABNF's own grammar
  (RFC 5234 section 4), and `0` of it is nothing.  Written `0pchar`.

`IPvFuture`'s `"v"` needed nothing: in a grammar with no `word` a letter-led
literal is the characters it spells, and `sensitivity string %i` makes it `v` or
`V`.

## Not covered

`URI-reference`, `relative-ref` and `relative-part` are converted the same
mechanical way and not tested: `URI | relative-ref` is ordered, and their
overlap (a relative reference whose first segment looks like a scheme) is what
RFC 3986 section 4.2 spends a paragraph on.  `URI` and `absolute-URI` are tested.
