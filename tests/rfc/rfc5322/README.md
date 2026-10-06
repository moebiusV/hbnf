# RFC 5322: addr-spec

`addr-spec.hbnf` is `addr-spec` (section 3.4.1) and every rule it reaches, 27
rules, verbatim, in the order the RFC defines them.  `addr-spec.fixed.hbnf` is
the same rules as hbnf reads them.  `vectors/` holds inputs for ten of them;
`addr-spec` (29 inputs, with the obsolete syntax) runs in all four backends.

## What hbnf says to the RFC's text

Not about `/` first, but about a backslash:

    hbnf: addr-spec.hbnf: 9: 22: this string literal does not end on its line.
    A backslash in "..." starts an escape, so `\"` is a quote inside the string
    and `"\"` never closes: write a backslash as `\\` or %x5C
      quoted-pair = ("\" (VCHAR / WSP)) / obs-qp

ABNF has no escapes in a string; hbnf's `"..."` has C's.  (This used to say
`unexpected character '\'`, hundreds of columns away, at the next quote it
found.)  After that, the `/` between phrases, as in RFC 3986.  And this, once
`quoted-pair` is repaired:

    hbnf: rule `atom` has the name of a built-in type, which the generated code
    reads as a scalar; give the rule another name (RFC 5322 defines `atom` and
    `word` as structures: write `atom-rule` and `word-rule`)

hbnf's `atom` and `word` are scalar types (a bareword), in every backend.  The
RFC's are structures, and the generated code used to mix the two up without a
word.

## The fixed-up version

`|` for `/` everywhere, `whitespace none` and `sensitivity string %i` as in
RFC 5234, and:

- `"\"` is `%x5C` (twice: `quoted-pair`, `obs-qp`).
- `atom` and `word` are `atom-rule` and `word-rule`, at every use.
- `dtext`'s two ranges are a rule of their own, `dtext-char`.  hbnf refuses a
  range in a rule that also names a phrase rule, and says to give it one; the
  RFC's `dtext` names `obs-dtext`, which names `quoted-pair`.
- `FWS = obs-FWS | ([*WSP CRLF] 1*WSP)`, the RFC's two alternatives reversed.
  The first alternative takes one fold of `  \r\n  \r\n  ` and leaves the
  second; `obs-FWS` takes both, and only text that begins with the CRLF is left
  for the other one.
- `local-part = obs-local-part` and `domain = obs-domain | domain-literal`.
  `|` commits to the first alternative that matches, so `dot-atom` would take
  `a` out of `a. b` and the `@` would never be found, where the RFC's union goes
  on to `obs-local-part`.  `obs-local-part` already holds every `dot-atom` and
  every `quoted-string` (and `obs-domain` every `dot-atom`), so the language is
  the union's.  The tree has no `dot-atom` where the RFC has one.
