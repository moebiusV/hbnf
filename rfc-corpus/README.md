# RFC corpus

The second validation corpus (alongside `tests/daemons/`): the BNF fragments of
the RFCs, so that "paste RFC ABNF and get a parser" is proven, not assumed.

## Layout

    tests/rfc/
      rfc5234/   Appendix B.1: the sixteen core rules
      rfc3986/   Appendix A: the collected ABNF for URI (host, IPv6address, URI, ...)
      rfc5322/   addr-spec and the 27 rules it reaches
      rfc9112/   request-line, with what it takes from RFC 9110 and RFC 3986
      headline.txt   the rules that run in all four backends, not only C

Each directory has, for its fragment:

- `<name>.hbnf`: the RFC's ABNF **verbatim**.  Only the RFC's page headers and
  footers and the left margin its rules are indented by are removed, so the file
  is the RFC's text, and an `include` at the top supplies what the RFC takes
  from another.  `hbnf FILE --root=RULE` says what hbnf makes of any rule.
- `<name>.fixed.hbnf`: the same rules as hbnf reads them.  Every change from the
  verbatim file is marked `; hbnf:` with the reason, except `|` for `/`, which
  is kept only where `/` is still refused, and explained in the README.
- `vectors/<RULE>.accept` and `.reject`: inputs, one per line (`\r`, `\n`,
  `\t`, `\NNN` and `\\` as printf's `%b` reads them; an empty line is the empty
  input).
- `README.md`: the account: what hbnf said to the verbatim text, and each change.

## Running it

    sh tests/rfc.sh                 # every rule: 62 parsers, in C; the headline rules in all four
    RFC_QUICK=1 sh tests/rfc.sh     # only the headline rules (what tests/e2e.sh runs)
    RFC_ONLY=rfc3986 sh tests/rfc.sh

Each rule is generated with `--root=RULE` from the fixed-up file, and every
accepted input must parse and every rejected one must not.

## What the corpus found

The corpus is where "paste an RFC's ABNF and get a parser" is tested rather than
assumed.  The first thing it found is that it was not true, and each row is a
way it was not.  *Fixed* means hbnf changed; *open* means the fixed-up file works
around it, and the plan has the step.

| What the RFC's text did | Status |
|---|---|
| `/` between whole phrases (`host = IP-literal / IPv4address / reg-name`, every `request-target`, `IPv6address`) was refused | **fixed** where ordered choice accepts the same language: alternatives that cannot begin alike, by one code point of lookahead or two (RFCPLAN.md decision 1, `hbnf_lookahead.adb`), and character rules.  The rest are refused with the two alternatives and what they share |
| `|` commits to the first alternative that matches, so overlapping alternatives lose input (`host`; `IPv6address`'s left part; `FWS`; `local-part`/`domain`) | **open**, by design: the union there needs backtracking, which the generated parsers do not do.  Each is repaired by hand in the fixed-up file, and tested.  (`dec-octet` is no longer one: a character rule takes the longest alternative) |
| `/` between one-character strings (`BIT = "0" / "1"`, `HEXDIG`, `tchar`, `atext`) was refused though each is one code point | **fixed** |
| A string literal in `"..."` has C escapes in hbnf and none in ABNF: `"\"` ran on to the next quote and reported `unexpected character '\'` hundreds of columns away | **fixed**: the message names the line and the cause |
| A rule named `atom` or `word` (RFC 5322 defines both, as structures) was read as hbnf's built-in scalar of that name, and the generated code disagreed with itself in three backends | **fixed**: a generation-time error that says to rename the rule |
| Case-insensitive letters: `"A"` in ABNF is `a` or `A`; in hbnf only with `sensitivity string %i`, and a case-insensitive literal was matched as a whole word, so `HEXDIG` refused the `a` in `abcd` | **fixed**: a literal with letters is both cases inside a character rule (up to four letters), and bytes in a grammar with no words |
| Every letter-led literal was a keyword, matched as a whole word.  In ABNF `"v"` is the character, and `v1.fe80` is not the word `v` | **fixed**: a literal is a keyword only in a grammar that has words (`word`/`atom`, or a `keywords` block) |
| `whitespace`: a phrase rule skipped blank space before every element, so `method SP request-target` never matched its `SP`; there was no way to turn it off, and with none, C's `parse_text` called a `skip_ws` it had not defined | **fixed**: `whitespace none`, and the C bug |
| A literal with no letters was marked case-insensitive by `sensitivity string %i` (`"1"`), which made `dec-octet` not a character rule | **fixed** |
| Generating one rule of a collected ABNF (`host` out of RFC 3986) meant moving it to the top of the file | **fixed**: `--root=RULE` |
| `<prose-val>` for a rule defined elsewhere (`uri-host = <host, see [URI]...>`, `path-empty = 0<pchar>`) is refused with "not written yet" | works as designed; the message does not say where to look, and `0<x>` could simply be empty.  The fixed-up files write the rule |
| A later definition replaces an earlier one, so RFC 9110's prose `port` would replace RFC 3986's real one | works as designed; noted in `rfc9112/README.md` |
| `OCTET = %x00-FF` is a byte in ABNF and a code point up to U+00FF in hbnf, which reads UTF-8 | **open**, the `binary` layer (step 5) |
| Rust: a repetition with a maximum of zero (`0pchar`) emitted a comparison rustc rejects | **fixed** |

## The bar

A fragment is "done" when its messages alone tell the author how to repair what
hbnf could not accept silently.  By that measure the corpus is done where the
rows above say fixed, and the open rows are the work.
