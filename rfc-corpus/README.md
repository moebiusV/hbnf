# RFC corpus

The second validation corpus (alongside `tests/daemons/`): the BNF fragments of
the RFCs, so that "paste RFC ABNF and get a parser" is proven, not assumed.

## Layout

One snippet is one numbered id, `<rfc>-<n>`, and its files sit side by side:

    rfc-corpus/
      rfc5234-1.bnf        the RFC's text, as published
      rfc5234-1.hbnf       the form hbnf compiles
      rfc5234-1.md         what changed between the two, and why; the messages
      rfc5234-1.vectors/   <RULE>.accept and <RULE>.reject, one input a line
      rfc3986-1.*          RFC 3986, Appendix A (host, IPv6address, URI, ...)
      rfc5322-1.*          RFC 5322: addr-spec and the 27 rules it reaches
      rfc9112-1.*          RFC 9112: request-line, with what it takes from RFC 9110
      headline.txt         the rules that run in all four backends, not only C

- `<id>.bnf`: the RFC's ABNF **verbatim**.  Only the RFC's page headers and
  footers and the left margin its rules are indented by are removed, so the
  file is the RFC's text, and an `include` at the top supplies what the RFC takes
  from another snippet.  `hbnf FILE.bnf --abnf --root=RULE` reads it as RFC
  5234 reads ABNF and says what hbnf makes of any rule.
- `<id>.hbnf`: the same rules as hbnf compiles them.  It starts with the two
  directives `--abnf` stands for (`whitespace none`, `sensitivity string %i`),
  and every other change from the `.bnf` is marked `; hbnf:` with the reason.
- `<id>.vectors/<RULE>.accept` and `.reject`: inputs, one per line (`\r`, `\n`,
  `\t`, `\NNN` and `\\` as printf's `%b` reads them; an empty line is the empty
  input).

Other corpora follow the same rule: `posix-corpus/posix-shell-1.y` and
`posix-shell-1.hbnf` (the yacc BNF as POSIX prints it, and the form hbnf
compiles), with the same `.md` and `.vectors/`.

## Running it

    sh tests/rfc.sh                    # every rule: C; the headline rules in all four
    RFC_QUICK=1 sh tests/rfc.sh        # only the headline rules (what tests/e2e.sh runs)
    RFC_ONLY=rfc3986-1 sh tests/rfc.sh

Each rule is generated with `--root=RULE` from `<id>.hbnf`, and every accepted
input must parse and every rejected one must not.

## What the corpus found

The corpus is where "paste an RFC's ABNF and get a parser" is tested rather than
assumed.  The first thing it found is that it was not true, and each row is a
way it was not.  *Fixed* means hbnf changed; *open* means the fixed-up file works
around it, and the plan has the step.

| What the RFC's text did | Status |
|---|---|
| `/` between whole phrases (`host = IP-literal / IPv4address / reg-name`, every `request-target`, `IPv6address`) was refused | **fixed**: the reader finds an order of the alternatives in which ordered choice accepts the same language, and writes the choice in it (`hbnf_lookahead.adb`).  What it still refuses is a union that needs backtracking, naming the two alternatives and a text both match |
| `|` commits to the first alternative that matches, so overlapping alternatives lose input (`host`: `IPv4address` is also a `reg-name`; `FWS`; `local-part`/`domain`) | **open**, by design where the union needs backtracking, which the generated parsers do not do.  Each is repaired by hand in the fixed-up file, and tested.  (`dec-octet` is no longer one: a character rule takes the longest alternative; `IPv6address`'s and `ls32`'s `/` are the RFC's) |
| A repetition read greedily where ABNF would give one back (`IPv6address`: `[ *1( h16 ":" ) h16 ] "::" ...` refused `1::2` with no message) | **fixed**: `*n( A S ) A` is rewritten `A *n( S A )`, the same strings with nothing to give back; where hbnf cannot, it says "matched greedily, unlike ABNF's" and how to write it.  Checked only where nothing is skipped between elements (`whitespace none`) |
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

## What a message says

There are two kinds, and each says more than "no":

- **The ABNF is wrong** (or says less than it means): the message says *why* it
  is wrong, and, where what the author meant can be guessed, the form to write
  (`0<pchar>` is `0pchar`; `uri-host = <host, see [URI]>` is `uri-host = host`
  and an `include`).
- **The ABNF is fine, and hbnf does it differently**: the message says what the
  notation means in ABNF, what it means in hbnf, and how to write it in hbnf
  (a union that needs backtracking; a greedy repetition; a rule named `atom`;
  `"\"` in a string).

## The bar

A fragment is "done" when its messages alone tell the author how to repair what
hbnf could not accept silently.  By that measure the corpus is done where the
rows above say fixed, and the open rows are the work.
