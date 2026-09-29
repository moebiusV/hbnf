# grammars/

OpenBSD daemons' configuration grammars, translated from their `parse.y`
into **hbnf**, the grammar notation.  Each file is a complete grammar for
that daemon's config file: the same shape `parse.y` describes, minus the
yacc machinery and the C `{ actions }`, which a binding in `bind/` adds
back.

## The notation

A grammar is `name = pattern` rules.  The first non-comment line declares the
language the inline scanner code is written in:

```
language C
```

- **Operators** — juxtaposition (sequence), `|` (ordered choice: the first
  alternative that matches wins), `( ... )` (grouping), `[ ... ]`
  (optional), `*`, `1*`, `n*m`, `*m` (repetition).  ABNF's `/` (union) is
  taken between alternatives of one character each, where it means the
  same as `|`; `../RFCPLAN.md` plans the rest.  Direct left recursion, as
  parse.y writes lists (`xs = xs "," x | x`), is read as a loop.  `;`
  starts a line comment.
- **Lines** — a rule goes on to a line that is indented or starts with `|`,
  and across newlines inside `( )` and `[ ]`.
- **`=/`** adds alternatives to a rule defined before it, here or in an
  included file, joined with `/`.
- **`<prose-val>`** — a rule described in words, not written yet.  If the
  parser would use it, generation stops and points at it, with a caret.
- **Include and override** — `include "file"`, before the first rule, reads
  a file once, however often it is included.  A later `name =` overrides an
  earlier one, in the same file or another, so a daemon grammar replaces the
  `commonconf.hbnf` rules it needs to.  The root is the top file's first
  new rule; a file that only overrides and extends keeps the root of what
  it includes.  `language` and `sensitivity` apply to their own file; the
  other directives describe the one generated parser, and two files that
  set one differently are an error.
- **`sensitivity`** — `sensitivity %i` makes the file's bare literals and
  rule references ignore case, as ABNF's do; `sensitivity string %i` or
  `sensitivity rule-name %i` does one of the two.  A literal's own `%i` or
  `%s` wins.
- **Keywords** are quoted literals in their config spelling (`"router-id"`,
  `"read-only"`), never the yacc `%token` identifier.
- **Readable typed tokens** — `str` (quoted string), `word`/`atom`
  (bareword), `int`, `bool`/`flag` (yes/no), `u8`..`u64`/`i8`..`i64`
  (fixed-width).  Character classes are the RFC 5234 names in
  `ascii.hbnf` (`DIGIT`, `ALPHA`, `HEXDIG`, …, uppercase), and single code
  points and ranges are the `%b`/`%d`/`%o`/`%u`/`%x` numeric terminals.  A
  rule made only of these is a character rule, compiled to a scanner.
- **`%` is the dispatch prefix** — the reader macro of hbnf, what `#'` is to
  Common Lisp: it marks a special form rather than a rule name.  `%i`/`%s`
  (case markers), `%b`/`%d`/`%o`/`%x` (numeric terminals), `%u` (a Unicode
  code point), and `%scan`/`%action` (code blocks).
- **Character literals** — `'a'` is a single code point (C escapes allowed),
  and `-` ranges two code-point designators: `'a'-'c'` = `%x61-63`, the
  endpoint order not mattering.  `-` is a range only after `'` or `%`, so it
  never collides with `-` in a rule name (`close-ma9`).  In a rule that is
  not a character rule, a single character (`','`, `%x2C`) is the
  one-character literal: `'{'` and `"{"` are the same there.  Write a
  single character in `'…'` and a longer literal in `"…"`.  A range in such
  a rule is refused until the character model (RFCPLAN.md step 4); name it
  in a rule of its own.
- **Jets** — a rule whose body is hand-written scanner code instead of a
  token sequence:

  ```
  ; ipv4 — 1*3digit "." 1*3digit "." 1*3digit "." 1*3digit   (each 0..255)
  ipv4 = { … C code: sees s, pos, len; returns matched length … }
  ```

  Every jet carries a **fallback line** above it: the character-level BNF it
  implements, so the hand-written code is readable and verifiable against its
  definition.

## The translation (`parse.y` → hbnf)

| parse.y | hbnf |
|---|---|
| `%token` keyword + `lookup()` table | a quoted literal, in keyword-table spelling |
| `STRING` (quoted or bareword) | `string` — defined once in `commonconf.hbnf` as `string = str \| word \| wildcard` |
| `NUMBER` | `int` |
| `x : y z` | `x = y z` |
| `x : y \| z` | `x = y \| z` |
| `x_l : x_l y \| y` | as written: `xs = xs y \| y`, read as a loop |
| `x : /* empty */ \| x_l` with `x_l : x_l y \| y` | `xs = \| xs y` (the empty alternative first, where parse.y writes `/* empty */`) |
| `x_l : y \| x_l comma y`, with `comma : ',' \| /* empty */` | `xs = xs ',' y \| xs y \| y`: the comma written out |
| `x_l : y x_l \| y` (right-recursive) | `xs = 1*( y )` |
| `x : y \| /* empty */` / `[ y ]` | flattened: `prefix y \| prefix` |
| `{ … }` action (TAILQ/alloc/logic) | dropped — the binder builds the tree |
| a hand-written scanner (`host()`, `get_address()`, the OID/AS/port parse) | an inline jet, with a fallback line |

Two shape rules keep the generated parser simple and match `parse.y` exactly:

- **Lists are rules of their own**, written as parse.y writes them: a
  left-recursive `_l` rule stays left-recursive (`hosts = hosts ',' host |
  hosts host | host`), and a block body references it (`"{" hosts "}"`).
  Left recursion is read as a loop, so a long list costs no stack.  A list
  parse.y writes right-recursive is `*( y )` or `1*( y )`.  A group, an
  optional or a repetition inside a sequence (`"on" [ "log" ] *( ',' w )`)
  works too: before code generation each becomes a rule of its own, named
  `<rule>_<n>` in the tree, so name it yourself where a binding reads it.
- **Optionals are flattened** where parse.y writes them so —
  `prefix [ X ]` becomes the two-way alternation `prefix X | prefix`.  An
  optional word can be written inline, `"block" [ "log" ]`, and records
  whether it was there; a rule of its own (`blocklog = 0*1( "log" )`) gives
  the tree field a name of your choosing.

The generated lexer skips whitespace and newlines, so there is no `nl`/`ws`/
`comment` scaffolding.  The daemon grammars declare `statements` instead: the
C parser reads one statement at a time, a statement ending at a newline
outside `{ }` (backslash-newline, and a next line starting with `{`, continue
it), and each statement is one entry of the root list — `parse.y`'s
`grammar : grammar entry '\n'`.  An error is reported and the parse goes on
with the next statement, as `parse.y`'s `error` rule does.  `macros varset`
and `includes include` name the rules whose statements define a macro and
include a file: `$name` then expands as in `parse.y`'s lexer, and `include`
reads the file in place.  ntpd has neither; dhcpleased has no `include`.

Each grammar also carries its `parse.y`'s keyword table, `keywords { … }`:
only those words are reserved, so a literal like pfctl's `"none"` (a STRING
that `parse.y` compares in an action) matches the word and does not stop it
being a value elsewhere (`set loginterface none`).  Copy the table from the
`lookup()` function; `tests/bytetest/keywords.sh` checks each against its
`parse.y`.

Ordered choice keeps the first alternative that matches, so write the longer
of two alternatives with the same start first (`"keypair" name "key" file |
"keypair" name`).  The C backend refuses a grammar where it is the other way
round.

## Covered

| daemon | file | parse.y |
|---|---|---|
| dhcpleased | `dhcpleased.hbnf` | `sbin/dhcpleased/parse.y` |
| httpd | `httpd.hbnf` | `usr.sbin/httpd/parse.y` |
| ntpd | `ntpd.hbnf` | `usr.sbin/ntpd/parse.y` |
| unwind | `unwind.hbnf` | `sbin/unwind/parse.y` |
| ldpd | `ldpd.hbnf` | `usr.sbin/ldpd/parse.y` |
| snmpd | `snmpd.hbnf` | `usr.sbin/snmpd/parse.y` |
| relayd | `relayd.hbnf` | `usr.sbin/relayd/parse.y` |
| bgpd | `bgpd.hbnf` | `usr.sbin/bgpd/parse.y` |
| pfctl | `pfctl.hbnf` | `sbin/pfctl/parse.y` |

Each grammar round-trips through the `hbnf` generator (`hbnf_cli`): it
emits a self-contained C parser that compiles and parses a sample config.

`commonconf.hbnf`, `tailq.hbnf`, `ascii.hbnf` and `core.hbnf` are
include-only, not daemon grammars: each is pulled in with `include "…"`.
`commonconf.hbnf` holds the rules the daemons share (`string`, `address`,
…), which a daemon grammar may override; `tailq.hbnf` carries the shared
`listops { }` block and the `#include <sys/queue.h>` it needs, and defines
no rules; `ascii.hbnf` is the ASCII names and the RFC 5234 character
classes, and `core.hbnf` adds `CRLF` to them: RFC 5234 Appendix B.1 in one
include.  Any script that globs `grammars/*.hbnf` must skip the four of
them (the nine daemons above are the grammars).

## Bindings (`bind/`)

A grammar here is only the language: it compiles on its own, in every
backend.  `bind/<daemon>.hbnf` turns one into a drop-in for the daemon's
`parse.y`: it includes the grammar, declares the daemon's conf struct
(`conf struct ntpd_conf`), adds the daemon's headers to the preamble, and
attaches parse.y's tree actions with `action <rule> { … }`.  When the
daemon's `parse_config` has another signature (unwind's returns a new
`struct uw_conf *`), `entry hbnf_parse_config` renames the generated
function and the binding's epilogue defines `parse_config` around it.
Generate the daemon's `conf.h`/`conf.c` from the binding:

    hbnf_cli grammars/bind/ntpd.hbnf --backend=c --conf

| daemon | binding |
|---|---|
| ntpd | `bind/ntpd.hbnf` (`tests/bytetest/byteident.sh`, `ntpd-proof.sh`) |
| unwind | `bind/unwind.hbnf` (`tests/bytetest/unwind-ident.sh`) |
