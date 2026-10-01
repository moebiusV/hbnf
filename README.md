# hbnf

`hbnf` is a parser generator (a compiler compiler) that reads a grammar in an
ABNF-like notation and emits a parser and its typed tree in C, Rust, Zig or
Ada. It is pleasant to use: anyone who knows the RFC series can write a grammar
with minimal adjustment. Almost no one uses yacc for anything serious, because
it is a pain; hbnf removes that pain with helpful `line:column` errors and
lossless source round-tripping, without giving up speed, performance, or your
favorite programming language.

Its first use case is **oconf**, the OpenBSD-style configuration language: the
declarative, block-structured form OpenBSD daemons have shared since `pf.conf`
(2001) and `bgpd` (2002), with keyword arguments, `{ }` blocks, double-quoted
strings, `#` comments, no shell interpolation and no evaluation. In oconf,
comments are preserved and come back out in the right places when the parsed
source is re-emitted.

The name is the initials of the four developers it is named for: Daniel
**H**artmeier (pf.conf, 2001), Henning **B**rauer (bgpd, 2002), Esben
**N**orby (ospfd, 2004), and Reyk **F**loeter (hoststated, 2007), whose
hand-written `parse.y` was cloned verbatim from daemon to daemon. The last
three initials spell **BNF** (Backus–Naur Form), so the name also reads as
"Hartmeier's BNF". To someone who already knows the genre, it is "parse.y
style".

## Two products

This directory holds two things:

1. **The crate** (the rest of this README): read an **oconf** file into a
   generic tree and walk it.
2. **The parser generator**, `hbnf`: read a schema in hbnf's ABNF-like
   notation and generate a parser and its typed tree in C, Rust, Zig or Ada.

       hbnf grammars/ntpd.hbnf --backend=c|rust|zig|ada
       hbnf grammars/bind/ntpd.hbnf --backend=c --conf   # ntpd's parse_config

   The generator's documents:
   - `grammars/README.md`: the notation, and the nine daemon grammars
     translated from their `parse.y`;
   - `ABNF.md`: the notation against RFC 5234, feature by feature;
   - `CHARLAYER.md`: character rules, numeric terminals and UTF-8;
   - `RFCPLAN.md`: the plan to compile RFC grammars as written;
   - `USENIXSUBMISSION.md`: the design paper, with measurements.

## Naming

- **oconf**: the OpenBSD-style configuration language, this project's first
  use case. Keyword arguments, `{ }` blocks, `#` comments.
- **HBNF**: the notation, and the Ada package (`HBNF.Parse`, `HBNF.Tree`).
- **hbnf**: this crate; the Alire name, the project file (`hbnf.gpr`), and the
  command-line tool.
- **libhbnf**: reserved for a C reference implementation (`libhbnf.so`,
  `-lhbnf`, `hbnf.pc`); not spent on this Ada crate.

## Credits

Four initials cannot hold the whole lineage: HBNF is *named for* Hartmeier,
Brauer, Norby and Floeter, not credited to them alone. The single best
artifact of that lineage is the copyright block of `relayd/parse.y`, copied
forward for two decades and still accumulating authors:

```
 * Copyright (c) 2007 - 2014 Reyk Floeter <reyk@openbsd.org>
 * Copyright (c) 2008 Gilles Chehade <gilles@openbsd.org>
 * Copyright (c) 2006 Pierre-Yves Ritschard <pyr@openbsd.org>
 * Copyright (c) 2004, 2005 Esben Norby <norby@openbsd.org>
 * Copyright (c) 2004 Ryan McBride <mcbride@openbsd.org>
 * Copyright (c) 2002, 2003, 2004 Henning Brauer <henning@openbsd.org>
 * Copyright (c) 2001 Markus Friedl.  All rights reserved.
 * Copyright (c) 2001 Daniel Hartmeier.  All rights reserved.
 * Copyright (c) 2001 Theo de Raadt.  All rights reserved.
```

That header is one among several; each daemon carries its own `parse.y`
(bgpd's credits Claudio Jeker's sustained work on that grammar). A
surname-initial name is precedented too: Fowler–Noll–Vo (FNV) is three people,
and nobody expands it aloud.

## The grammar

```
# a directive: keyword, then arguments, terminated by newline
listen on egress port 443 tls

# a block: keyword, optional qualifier, then nested entries in braces
relay "webserver" {
    forward to "127.0.0.1" port 8080
}
```

- Words are unquoted tokens; `"quoted strings"` may contain spaces and a fixed
  escape set (`\"`, `\\`, `\n`, `\t`, `\r`).
- A backslash at the end of a line continues the line (as in OpenBSD's
  `parse.y`): the `\` and the newline are consumed and no newline token is
  emitted, so a directive or a word can span physical lines.
- Integers and decimals are classified automatically. A decimal is kept
  **both** as its exact source text and as a fixed-point value.
- `#` starts a comment that runs to end of line.
- No macros, no includes, no arithmetic, no conditionals: everything is
  decidable at parse time, and a parse either succeeds completely or fails
  with a `line:column`. (A daemon grammar can declare parse.y's macros and
  `include` with the `macros` and `includes` directives; see
  `grammars/README.md`.)

## Comments

A `#` comment is one of three kinds, distinguished by where it sits:

- **Leading**: a block of own-line comments attaches to the directive or
  block that follows it, held in that entry's `Leading_Comment`. Blank lines
  in between do not break the attachment.
- **Trailing**: a comment on the same line as a directive or block annotates
  that line, held in `Trailing_Comment`.
- **Standalone**: a comment block with nothing after it is kept as its own
  `Comment` node in the children sequence: the file header before the first
  directive (which documents the whole file) and trailing lines before a `}`.
  `Find` and `Find_All` skip `Comment` nodes.

## API

```ada
R : constant HBNF.Parse_Result := HBNF.Parse (Text);
if not R.Success then
   --  R.Line, R.Col, R.Msg describe the first error
end if;

Root : constant HBNF.Node_Access := R.Root;
for C of HBNF.Children (Root.all) loop ... end loop;

Slot : constant HBNF.Node_Access := HBNF.Find (Root.all, "slot");
Cap  : constant HBNF.Node_Access := HBNF.Find (Slot.all, "total-capital");
V    : constant HBNF.Value := HBNF.Value_At (Cap.all, 1);

Amount : constant HBNF.Decimal := HBNF.As_Decimal (V);  -- fixed-point
Exact  : constant String       := HBNF.As_Text (V);      -- as written
```

`Parse` returns a synthetic block root; `Children` / `Find` / `Find_All` walk
it; `Value_At` and the `As_*` functions extract typed values. A `Value` is one
of `Word`, `Str`, `Int`, or `Dec`.

## Decimal round-tripping

`Dec` stores the literal twice:

- `Text`: the exact characters as written (`"100000.00"`, `"0.001"`), so a
  value can be written back out bit-for-bit without numeric conversion.
- `Num`: a fixed-point `Decimal` (`delta 10.0 ** (-8) digits 38`), so callers
  can compare and compute directly without parsing a string.

Both are populated by the parser; neither requires the caller to convert.

## Pretty-printing

`HBNF.Print` renders a parsed tree back to canonical text: single-space token
separation, three-space indentation, `{` on the header line and `}` alone at
the parent indent. Values round-trip exactly (a decimal keeps its literal, a
string is re-quoted with the escape set). Comments are preserved: a leading
block stays on its own lines before the entry it documents, a trailing
comment stays on its line, and a standalone comment (file header, or a block
trailer before `}`) stays a comment of its own. Printing is idempotent, so it
normalizes two configs that differ only in whitespace or brace position.

## Building

```
gprbuild -P hbnf.gpr -p -XLIBRARY_TYPE=static
gprinstall -P hbnf.gpr -p --prefix=/usr --sources-subdir=include/hbnf
```

Packaged for Alpine by the `ada-on-alpine` aports overlay as `testing/hbnf`.

## License

ISC. See `LICENSE`.
