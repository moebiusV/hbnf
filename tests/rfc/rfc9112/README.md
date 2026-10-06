# RFC 9112: request-line

`request-line.hbnf` is `request-line` (section 3) and the rules it uses:
RFC 9112's own, then the five it takes from RFC 9110 (`token`, `tchar`,
`absolute-path`, `uri-host`, `port`), then RFC 3986's by the include.
`request-line.fixed.hbnf` is the same as hbnf reads it.  `vectors/` holds six
rules' inputs; `request-line` (22 inputs) runs in all four backends.

## What hbnf says to the RFC's text

The `/` of `request-target`, as before, and two prose-vals:

    hbnf: request-line.hbnf:33:17: not written yet, in `uri-host`:
    <host, see [URI], Section 3.2.2>
      uri-host      = <host, see [URI], Section 3.2.2>

    hbnf: request-line.hbnf:35:17: not written yet, in `port`:
    <port, see [URI], Section 3.2.3>

RFC 9110 defines `uri-host` and `port` by pointing at RFC 3986.  The message
says the rule is not written yet, which is true and does not say where to look;
the prose-val does (`[URI]` is RFC 3986).

## The fixed-up version

`|` for `/`, `whitespace none` and `sensitivity string %i`, and:

- `uri-host = host`, the rule the prose-val names.
- **`port = <port, ...>` is left out.**  A later `=` replaces an earlier one, so
  it would replace RFC 3986's `port = *DIGIT`, the rule it points at.
- `request-target`'s order is the RFC's: `absolute-form` before
  `authority-form`.  `example.com:80` is an `absolute-URI` (`example.com` is a
  valid scheme) as well as an `authority-form`, and ordered choice takes the
  first; the RFC says `authority-form` is used only by `CONNECT`, which the
  method decides and this rule cannot see.  The language is the same; the form
  recorded for `CONNECT example.com:80` is `absolute-form`.

`HTTP-name = %s"HTTP"` needed nothing: `%s` is hbnf's own spelling of RFC 7405's
case-sensitive string, and the vectors check that `http/1.1` is refused.
