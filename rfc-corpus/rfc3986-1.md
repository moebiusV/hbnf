# RFC 3986, Appendix A: Collected ABNF for URI

`uri.hbnf` is the whole appendix, verbatim; its only addition is the `include`
that supplies RFC 5234's `ALPHA`, `DIGIT` and `HEXDIG`.  `uri.fixed.hbnf` is
the same rules as hbnf reads them.  `vectors/` holds 23 rules' inputs
(`scheme`, `host`, `IPv6address` and the rest of its closure, the path forms,
`URI`); `host` and `IPv6address` run in all four backends, the rest in C.

## What hbnf says to the RFC's text

Most of the appendix compiles as written.  `/` is taken where ordered choice
accepts the same language: between one-code-point alternatives (`unreserved`,
`sub-delims`, `pchar`, `userinfo`, `query`), in character rules, whose scanner
takes the longest alternative (`dec-octet` in the RFC's own order), and between
longer alternatives that cannot begin alike, by one code point of lookahead or
two (`hier-part`: `"//" authority path-abempty` against `path-absolute`, which
begins with `/` and then not another).

What hbnf refuses is where the union itself needs backtracking, and it names the
two alternatives and what they share:

    hbnf: uri.hbnf:31:28: `/` is ABNF's union, which hbnf compiles only where
    the alternatives cannot begin alike (RFCPLAN.md decision 1): `IPv4address`
    and `reg-name` can both begin with `2` then `0`-`4`; write `|`, ordered
    choice, with the one to try first first
      host          = IP-literal / IPv4address / reg-name

and the same for `ls32`, `URI-reference` (`URI` and `relative-ref` both begin
with a scheme-looking word), `IPv6address` (seven alternatives that all begin
with an `h16`), and `path` (`path-abempty` and `path-empty` can both match
nothing).  One more:

    hbnf: uri.hbnf:70:18: not written yet, in `path-empty`: <pchar>
      path-empty    = 0<pchar>

## The fixed-up version

`/` stays wherever it compiled.  `|` is written, rule by rule, where it did not,
and where the order matters it is the repair:

- **`host`**: `IP-literal / IPv4address / reg-name` is ambiguous (a dotted quad
  is also a `reg-name`; RFC 3986 section 3.2.2 says so).  `|` commits to
  `IPv4address` and takes `1.2.3.4` out of `1.2.3.4.5`, then fails where the
  RFC's union goes on to `reg-name`.  `host = IP-literal | reg-name` accepts the
  same language; an address parses as a `reg-name`.
- **`IPv6address`**: the RFC's left part, `[ *1( h16 ":" ) h16 ]`, takes the
  `:` of `::` for a separator, finds no `h16` after it, and as an optional that
  failed gives up its groups, so `1::2` fails.  Written `[ h16 *1( ":" h16 ) ]`
  it stops before the `::`.  The alternatives already run longest right part
  first, which is what ordered choice needs.  27 inputs, in all four backends.
- **`ls32`**, **`URI-reference`**: `|` in the RFC's order, which is the order
  ordered choice needs (`h16 ":" h16` fails on a dotted quad before
  `IPv4address` is tried; `URI` is tried before `relative-ref`).
- **`path`** is a documentation rule the grammar does not use.  Its `|` is
  mechanical and **not repaired**: `path-abempty` can match nothing and is first,
  so ordered choice would take the empty match.  It has no vectors.
- **`path-empty = 0<pchar>`**: `<pchar>` is a prose-val in ABNF's own grammar
  (RFC 5234 section 4), and `0` of it is nothing.  Written `0pchar`.

`dec-octet` and `IPvFuture` needed nothing: the first is a character rule (the
scanner takes the longest alternative, so the RFC's shortest-first order works),
and in a grammar with no `word` a letter-led literal is the characters it
spells, which `sensitivity string %i` makes `v` or `V`.

## Not covered

`URI-reference`, `relative-ref`, `relative-part` and `path` have no vectors:
`URI | relative-ref` is ordered, and their overlap (a relative reference whose first segment looks like a scheme) is what
RFC 3986 section 4.2 spends a paragraph on.  `URI` and `absolute-URI` are tested.
