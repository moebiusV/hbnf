# hbnf

`hbnf` is an Ada crate that reads the **HBNF** configuration grammar — the
declarative, block-structured form that OpenBSD daemons have shared since
`pf.conf` (2001) and `bgpd` (2002): keyword arguments, `{ }` blocks,
double-quoted strings, `#` comments, no shell interpolation and no evaluation.
It parses a file into an abstract syntax tree you walk with a handful of
accessors.

The name is the initials of the four developers it is named for — Daniel
**H**artmeier (pf.conf, 2001), Henning **B**rauer (bgpd, 2002), Esben
**N**orby (ospfd, 2004), and Reyk **F**loeter (hoststated, 2007) — whose
hand-written `parse.y` was cloned verbatim from daemon to daemon. The last
three initials spell **BNF** (Backus–Naur Form), so the name also reads as
"Hartmeier's BNF". When explaining it to someone who already knows the genre,
call it "parse.y style".

## Naming

- **HBNF** — the notation, and the Ada package (`HBNF.Parse`, `HBNF.Tree`).
- **hbnf** — this crate; the Alire name, the project file (`hbnf.gpr`).
- **libhbnf** — reserved for a C reference implementation
  (`libhbnf.so`, `-lhbnf`, `hbnf.pc`); not spent on this Ada crate.

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

That header is one among several — each daemon carries its own `parse.y`
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
  with a `line:column`.

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

- `Text` — the exact characters as written (`"100000.00"`, `"0.001"`), so a
  value can be written back out bit-for-bit without numeric conversion.
- `Num` — a fixed-point `Decimal` (`delta 10.0 ** (-8) digits 38`), so callers
  can compare and compute directly without parsing a string.

Both are populated by the parser; neither requires the caller to convert.

## Pretty-printing

`HBNF.Print` renders a parsed tree back to canonical text — single-space token
separation, three-space indentation, `{` on the header line and `}` alone at
the parent indent. Values round-trip exactly (a decimal keeps its literal, a
string is re-quoted with the escape set). Printing is idempotent and drops
comments, so it normalizes two configs that differ only in whitespace or brace
position.

## Building

```
gprbuild -P hbnf.gpr -p -XLIBRARY_TYPE=static
gprinstall -P hbnf.gpr -p --prefix=/usr --sources-subdir=include/hbnf
```

Packaged for Alpine by the `ada-on-alpine` aports overlay as `testing/hbnf`.

## License

ISC. See `LICENSE`.
