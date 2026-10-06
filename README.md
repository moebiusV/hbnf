# hbnf

`hbnf` is a parser generator (a compiler compiler). It reads a grammar in an
ABNF-like notation and emits a parser and its typed tree in C, Rust, Zig or
Ada.

The design is for anyone who is comfortable reading the RFCs. HBNF makes BNF
natural and readable the way the RFCs do: a grammar reads like the notation
RFCs have used for decades, not like a yacc file with embedded C actions.

ABNF is the starting point because it is the notation the RFCs actually use:
RFC 5234 defines it, RFC 7405 adds case-sensitive string literals, and dozens
of newer RFCs specify their protocols in it. Start from the notation people
already read fluently, and a grammar is documentation first and a parser
second.

hbnf began as a project to implement **obconf**, a configuration language for
OpenBSD-style config files, so that other programs could use it without
having to learn yacc, lex, bison or flex. That work exposed how bad the state
of parser generation is: almost no one uses yacc for anything serious, because
it is a pain. So hbnf became a parser generator in its own right — a compiler
compiler — one that removes that pain with helpful errors and grammars that can
round-trip losslessly, without giving up speed, performance, or your favorite
programming language.

obconf is a configuration language, implemented as a grammar in hbnf. It
describes the declarative, block-structured form OpenBSD daemons have shared
since `pf.conf` (2001) and `bgpd` (2002): keyword arguments, `{ }` blocks,
double-quoted strings, `#` comments, no shell interpolation and no evaluation.
A parser generated from obconf reads the comments and skips them.  Keeping
them, and putting them back in the right places when the source is re-emitted,
is the pretty printer of RFCPLAN.md step 13.

The name is the initials of the four developers it is named for: Daniel
**H**artmeier (pf.conf, 2001), Henning **B**rauer (bgpd, 2002), Esben
**N**orby (ospfd, 2004), and Reyk **F**loeter (hoststated, 2007), whose
hand-written `parse.y` was cloned verbatim from daemon to daemon. The last
three initials spell **BNF** (Backus–Naur Form), so the name also reads as
"Hartmeier's BNF". To someone who already knows the genre, it is **obconf** —
OpenBSD configuration style.

## Two things

This directory holds two things:

1. **libhbnf**, a static Ada library: the grammar reader, the compilability
   checks and the four emitters (C, Rust, Zig, Ada).  Everything `hbnf` does is
   in it, and `hbnf`, the command line, is a thin wrapper over it: argument
   parsing, finding the templates, and printing what the library returns.
2. **The parser generator**, `hbnf`: read a schema in hbnf's ABNF-like
   notation and generate a parser and its typed tree in C, Rust, Zig or Ada.

       hbnf grammars/obconf_ntpd.hbnf --backend=c|rust|zig|ada
       hbnf grammars/bind/ntpd.hbnf --backend=c --conf   # ntpd's parse_config

   The generator's documents:
   - `WHY.md`: the grammar and its design choices, for an RFC reader;
   - `grammars/README.md`: the notation, and the nine daemon grammars
     translated from their `parse.y`;
   - `ABNF.md`: the notation against RFC 5234, feature by feature;
   - `CHARLAYER.md`: character rules, numeric terminals and UTF-8;
   - `RFCPLAN.md`: the plan to compile RFC grammars as written;
   - `USENIXSUBMISSION.md`: the design paper, with measurements.

## Naming

- **hbnf**: the parser generator and compiler compiler. Reads a grammar, emits
  a parser in C, Rust, Zig or Ada. Also the command line, the Alire name, and
  the project file (`hbnf.gpr`).
- **obconf**: a configuration language, implemented as a grammar in hbnf, for
  OpenBSD config files — keyword arguments, `{ }` blocks, `#` comments.
- **libhbnf**: the static Ada library (`libhbnf.a`, project `libhbnf.gpr`)
  that the `hbnf` command line wraps.  A C reference implementation, if there
  is one, will not take this name for its shared library.  (There used to be an
  Ada package `HBNF_Config` here, a hand-written obconf reader.  Its job is
  done by a parser generated from `hbnf_schema.hbnf`; see below.)

## Credits

Four initials cannot hold the whole lineage: HBNF is *named for* Hartmeier,
Brauer, Norby and Floeter, not credited to them alone. The obconf grammar
descends from the hand-written `parse.y` config parsers of the OpenBSD
daemons, each of which carries forward a copyright block naming everyone who
has touched it. Everyone, in the order they first appear:

| Year | Author | First parser |
|---|---|---|
| 2001 | Markus Friedl | pfctl |
| 2001 | Daniel Hartmeier | pfctl |
| 2001 | Theo de Raadt | pfctl |
| 2002 | Henning Brauer | bgpd |
| 2004 | Ryan McBride | ifstated |
| 2004 | Esben Norby | ospfd |
| 2004 | Hans-Joerg Hoexer | iked |
| 2006 | Michele Marchetto | ripd |
| 2006 | Pierre-Yves Ritschard | hoststated |
| 2007 | Reyk Floeter | hoststated |
| 2008 | Gilles Chehade | smtpd |
| 2009 | Martin Hedenfalk | ldapd |
| 2013 | Renato Westphal | ldpd |
| 2016 | Job Snijders | bgpd |
| 2016 | Peter Hessler | bgpd |
| 2017 | Sebastian Benoit | bgpd |
| 2018 | Florian Obser | dhcpleased |
| 2019 | Tobias Heider | iked |
| 2020 | Matthias Pressfreund | httpd |

The four the name spells — Hartmeier, Brauer, Norby and Floeter — are the
lineage it names; the last three initials spell **BNF** (Backus–Naur Form),
so the name also reads as "Hartmeier's BNF". Friedl, Hartmeier, de Raadt and
Brauer appear in every parser's block, carried forward for two decades.

A surname-initial name is precedented too: Fowler–Noll–Vo (FNV) is three
people, and nobody expands it aloud.

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
  escape set (C's: `\"`, `\\`, `\n`, `\t`, octal, `\x` and `\u`).  Only the
  backslash is dropped, as in the C backend: `\n` reads as `n`.
- A backslash at the end of a line continues the line (as in OpenBSD's
  `parse.y`): the `\` and the newline are consumed and no newline token is
  emitted, so a directive or a word can span physical lines.
- An integer is `int`; any other bareword is a `word`, including a number with
  a dot (`3.14`, `10.0.0.1`).  A grammar that wants a decimal type defines one.
- `#` starts a comment that runs to end of line.
- No macros, no includes, no arithmetic, no conditionals: everything is
  decidable at parse time, and a parse either succeeds completely or fails
  with a helpful error: a `line:column`, a caret under where the error starts,
  and the token that was expected. (A daemon grammar can declare parse.y's
  macros and
  `include` with the `macros` and `includes` directives; see
  `grammars/README.md`.)

## Reading an obconf file

`hbnf_schema.hbnf` is the structure of an obconf file (`config`, `entry`,
`block`, `statement`, `arg`) over the lexical rules of `grammars/obconf.hbnf`.
Generate a parser from it in the language you want:

    hbnf hbnf_schema.hbnf --backend=ada --package=Obconf
    hbnf hbnf_schema.hbnf --backend=rust
    hbnf hbnf_schema.hbnf --backend=zig
    hbnf hbnf_schema.hbnf --backend=c

and walk the typed tree it returns.  `tests/accept` and `tests/reject` are its
conformance files, and `tests/schema.sh` runs them through all four backends.

What the tree keeps is what the grammar names.  Comments are skipped, not
kept, and a decimal is a `word` with no fixed-point value.  The comment-keeping
round trip the old reader had comes back with the pretty printer (RFCPLAN.md
step 13); `tests/schema.sh` already prints a tree and checks the print is a
fixed point.

## Building

Needs [mustache-ada](https://github.com/moebiusV/mustache-ada) installed: it
renders the code templates.  Pure Ada on the GNAT runtime, no C dependency.

```
gprbuild -P libhbnf.gpr -p -XLIBRARY_TYPE=static
gprinstall -P libhbnf.gpr -p --prefix=/usr --sources-subdir=include/hbnf
```

Packaged for Alpine by the `ada-on-alpine` aports overlay as `testing/hbnf`,
which also carries `testing/mustache-ada`.

**Build through the project files, not `gnatmake -I.`.**  `gprbuild` keeps its
own object directory; `gnatmake -I. -D <tmpdir>` compiles into the temp
directory but `gnatlink` takes `hbnf.ali` from `.`, so a stale `.o` left in the
source directory wins the link and the build reports success while running
yesterday's code.  Those files are `.gitignore`d, so `git status` stays clean
while it happens.  If you must use `gnatmake`, `rm -f *.o *.ali` first;
`tests/e2e.sh` does that for you and refuses to run against a binary older
than its newest source.

## Contributing

Ada is written in the functional style in `STYLE.md`: constants by default,
expression functions, no `out`/`in out` parameters, loops replaced by `'Reduce`
and comprehensions, and side effects kept at the edges. Read it before
contributing.

## License

ISC. See `LICENSE`.
