# RFC corpus

The second validation corpus (alongside `tests/daemons/`): the BNF fragments of
the RFCs, so that "paste RFC ABNF and get a parser" is proven, not assumed.

## Layout

    tests/rfc/
      rfc5234/            # the ABNF spec itself (Appendix B.1 core rules)
      rfc3986/            # URI: scheme, host, …
      rfc5322/            # Internet Message Format: addr-spec, …
      rfc9112/            # HTTP/1.1: request-line, …
      …

One directory per RFC (or per fragment, when an RFC contributes several
independent pieces).  The `README.md` in each is the account of the exercise:
what the RFC says, what hbnf accepted, what it refused and why, and the
fixed-up form.

## Per-fragment rule

For each fragment, keep three things:

1. **The verbatim ABNF** — as the RFC writes it.  Where it compiles as-is,
   name it `<fragment>.hbnf` and say so in the README.
2. **The errors** — the exact `hbnf_cli` output, and a sentence on what each
   means and how to fix it.
3. **The fixed-up version** — the `.hbnf` that compiles.  Where the repair is
   involved rather than a mechanical spelling change, describe it instead of
   (or alongside) the file: a `<prose-val>` that defers its real definition to
   two or three other RFCs is rewritten to the rules those RFCs give, naming
   the provenance.

## The bar

A fragment is "done" when its messages alone tell the author how to repair what
hbnf could not accept silently — discoverability proven against the real
corpus, not a toy.
