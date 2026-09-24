# grammars/

OpenBSD daemons' configuration grammars, translated from their `parse.y`
into **hbnf**, the grammar notation.  Each file is a complete grammar for
that daemon's config file: the same shape `parse.y` describes, minus the
yacc machinery, the C `{ actions }`, and the macros.

## The notation

A grammar is `name = pattern` rules.  The first non-comment line declares the
language the inline scanner code is written in:

```
language C
```

- **Operators** — juxtaposition (sequence), `/` (alternation), `( ... )`
  (grouping), `[ ... ]` (optional), `*` / `1*` (repetition).  `;` starts a
  line comment.
- **Keywords** are quoted literals in their config spelling (`"router-id"`,
  `"read-only"`), never the yacc `%token` identifier.
- **Readable typed tokens** (no `%d`/`%x`/`%b` printf-isms): `str` (quoted
  string), `word`/`atom` (bareword), `int`, `bool`/`flag`, `u8`..`u64`/
  `i8`..`i64` (fixed-width), and `decint`/`hexint`/`octint`/`binint` for
  base-specific integers.  Character classes are named core rules
  (`digit`, `alpha`, `hexdig`, …) — the character level is the foundation;
  tokens and jets are sugar over it.
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
| `STRING` (quoted or bareword) | `string` — defined once as `string = str / word` |
| `NUMBER` | `int` |
| `x : y z` | `x = y z` |
| `x : y \| z` | `x = y / z` |
| `x_l : x_l y \| y` (list boilerplate) | hoisted: `xs = *( y )` as its own rule |
| `x : y \| /* empty */` / `[ y ]` | flattened: `prefix y / prefix` |
| `{ … }` action (TAILQ/alloc/logic) | dropped — the binder builds the tree |
| a hand-written scanner (`host()`, `get_address()`, the OID/AS/port parse) | an inline jet, with a fallback line |

Two shape rules keep the generated parser simple and match `parse.y` exactly:

- **Lists are hoisted** — a `_l` rule becomes a top-level `xs = *( y )`, and
  a block body references it (`"{" xs "}"`).  Never nest `*( … )` inside a
  sequence.
- **Optionals are flattened** — `prefix [ X ]` becomes the two-way alternation
  `prefix X / prefix`.

The generated lexer skips whitespace and newlines, so there is no `nl`/`ws`/
`comment` scaffolding — entries are token sequences delimited by their leading
keywords and `{ }` blocks, which is what `parse.y`'s `'\n'`-terminated rules
spell out anyway.

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

`commonconf.hbnf` and `tailq.hbnf` are include-only, not daemon grammars:
both are pulled in with `include "…"`.  `tailq.hbnf` carries the shared
`listops { }` block and defines no rules, so any script that globs
`grammars/*.hbnf` must skip the two of them (the nine daemons above are the
grammars).

## Bindings (`bind/`)

A grammar here is only the language: it compiles on its own, in every
backend.  `bind/<daemon>.hbnf` turns one into a drop-in for the daemon's
`parse.y`: it includes the grammar, declares the daemon's conf struct
(`conf struct ntpd_conf`), adds the daemon's headers to the preamble, and
attaches parse.y's tree actions with `action <rule> { … }`.  Generate the
daemon's `conf.h`/`conf.c` from the binding:

    hbnf_cli grammars/bind/ntpd.hbnf --backend=c --conf

| daemon | binding |
|---|---|
| ntpd | `bind/ntpd.hbnf` |
