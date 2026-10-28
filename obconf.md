# obconf

hbnf began as a project to implement **obconf**, a configuration language for OpenBSD-style
config files, so that other programs could use it without having to learn yacc, lex, bison or
flex.  That work exposed how bad the state of parser generation is: almost no one uses yacc for
anything serious, because it is a pain.  So hbnf became a parser generator in its own right, a
compiler compiler, one that removes that pain with helpful errors and grammars that can
round-trip losslessly, without giving up speed, performance, or your favorite programming
language.  [`README.md`](README.md) is about that generator; this file is about the
configuration language it started from.

obconf is a configuration language, implemented as a grammar in hbnf.  It describes the
declarative, block-structured form OpenBSD daemons have shared since `pf.conf` (2001) and
`bgpd` (2002): keyword arguments, `{ }` blocks, double-quoted strings, `#` comments, no shell
interpolation and no evaluation.  A parser generated from obconf reads the comments and skips
them.  Keeping them, and putting them back in the right places when the source is re-emitted,
is the pretty printer of RFCPLAN.md step 13.

## The name

The name is the initials of the four developers it is named for: Daniel **H**artmeier
(pf.conf, 2001), Henning **B**rauer (bgpd, 2002), Esben **N**orby (ospfd, 2004), and Reyk
**F**loeter (hoststated, 2007), whose hand-written `parse.y` was cloned verbatim from daemon to
daemon.  The last three initials spell **BNF** (Backus–Naur Form), so the name also reads as
"Hartmeier's BNF".  It also reads as **HyperBNF**, which is what the notation has grown into:
the dialects of BNF, read as one.  The wish to implement obconf (the OpenBSD configuration
style) inspired it, and obconf is now one grammar written in it, beside JSON, TOML and YAML.

A surname-initial name is precedented too: Fowler–Noll–Vo (FNV) is three people, and nobody
expands it aloud.

## The notation

```
# a directive: keyword, then arguments, terminated by newline
listen on egress port 443 tls

# a block: keyword, optional qualifier, then nested entries in braces
relay "webserver" {
    forward to "127.0.0.1" port 8080
}
```

- Words are unquoted tokens; `"quoted strings"` may contain spaces and a fixed escape set (C's:
  `\"`, `\\`, `\n`, `\t`, octal, `\x` and `\u`).  Only the backslash is dropped, as in the C
  backend: `\n` reads as `n`.
- A backslash at the end of a line continues the line (as in OpenBSD's `parse.y`): the `\` and
  the newline are consumed and no newline token is emitted, so a directive or a word can span
  physical lines.
- An integer is `int`; any other bareword is a `word`, including a number with a dot (`3.14`,
  `10.0.0.1`).  A grammar that wants a decimal type defines one.
- `#` starts a comment that runs to end of line.
- No macros, no includes, no arithmetic, no conditionals: everything is decidable at parse time,
  and a parse either succeeds completely or fails with a helpful error: a `line:column`, a
  caret under where the error starts, and the token that was expected.  (A daemon grammar can
  declare `parse.y`'s macros and `include` with the `macros` and `includes` directives; see
  `grammars/README.md`.)

## Reading an obconf file

`hbnf_schema.hbnf` is the structure of an obconf file (`config`, `entry`, `block`, `statement`,
`arg`) over the lexical rules of `grammars/obconf.hbnf`.  Generate a parser from it in the
language you want:

    hbnf hbnf_schema.hbnf --backend=ada --package=Obconf
    hbnf hbnf_schema.hbnf --backend=rust
    hbnf hbnf_schema.hbnf --backend=zig
    hbnf hbnf_schema.hbnf --backend=c

and walk the typed tree it returns.  `tests/accept` and `tests/reject` are its conformance
files, and `tests/schema.sh` runs them through all four backends.

What the tree keeps is what the grammar names.  Comments are skipped, not kept, and a decimal is
a `word` with no fixed-point value.  The comment-keeping round trip the old reader had comes
back with the pretty printer (RFCPLAN.md step 13); `tests/schema.sh` already prints a tree and
checks the print is a fixed point.  (There used to be an Ada package `HBNF_Config` here, a
hand-written obconf reader.  Its job is done by a parser generated from `hbnf_schema.hbnf`.)

## The daemons

`grammars/` holds the nine daemon grammars, each translated from the daemon's own `parse.y`,
over the shared `obconf.hbnf`:

    hbnf grammars/obconf_ntpd.hbnf --backend=c|rust|zig|ada

`grammars/bind/` turns a grammar into a drop-in for the daemon's `parse.y`: it includes the
grammar, attaches `parse.y`'s tree actions, and writes the daemon's `parse_config` in its own
epilogue around the driver in `runtime/hbnf_conf.h`.  The generated file is linked with
`runtime/hbnf_conf.c`:

    hbnf grammars/bind/ntpd.hbnf --backend=c > parse.c

- [`grammars/README.md`](grammars/README.md): the notation and the nine daemon grammars.
- [`bindings/README.md`](bindings/README.md): the FFI bindings (Python, Ruby, Perl, newLISP)
  that drive the generated C directly.
- [`tests/bytetest/README.md`](tests/bytetest/README.md): the byte-identity harness against
  OpenBSD's `parse.y`.

Measurements against the real `parse.y` (`bench/README.md` says how they are made):
[ntpd](bench/results/ntpd.md) and [hbnf on pfctl](bench/results/hbnf-pfctl.md).  `WHY.md` has
the full comparison against OpenBSD's ntpd.

## Credits

Four initials cannot hold the whole lineage: HyperBNF is *named for* Hartmeier, Brauer, Norby
and Floeter, not credited to them alone.  The obconf grammar descends from the hand-written
`parse.y` config parsers of the OpenBSD daemons, each of which carries forward a copyright block
naming everyone who has touched it.  Everyone, in the order they first appear:

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

The four the name spells — Hartmeier, Brauer, Norby and Floeter — are the lineage it names; the
last three initials spell **BNF** (Backus–Naur Form), so the name also reads as "Hartmeier's
BNF".  Friedl, Hartmeier, de Raadt and Brauer appear in every parser's block, carried forward
for two decades.
