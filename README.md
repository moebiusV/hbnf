# HyperBNF

> **Status, 24 October 2026.**  JSON, TOML and YAML are built and tested in all four backends
> (TOML against toml-test and `tomllib`, YAML against the YAML test suite and PyYAML).  A
> hyperrule whose parameters are numbers is now one rule that keeps them in a frame (`k in 0..`,
> `%spaces`, `%col`, `x %num`) or a copy for each value, whichever is cheaper (`--expand-params`,
> `--run-params`).  That is how YAML's indentation has no depth limit in the grammar, which is the
> size of the spec's and which the generator reads in under a second.  (The C parsers stop at
> `HBNF_MAX_DEPTH` rules open at once, 4096 by default, to keep the stack safe.)  The C11 grammar parses
> 2,478 of 2,481 gcc-accepted files from ten real corpora.  Next: C as a family of grammars, one per
> standard (K&R, C89, C99, C11, C17, C23) with a GNU layer, each checked against
> `gcc -std=cNN -pedantic-errors`; the C preprocessor; the back half of a small C compiler.

**HyperBNF** is a grammar language, and `hbnf` is the program that reads it: a parser generator
(a compiler compiler) that emits a parser and its typed tree in C, Rust, Zig or Ada.  The name is an
homage to the W-grammar and its hyper-rules: a rule may take parameters, and each use becomes an
ordinary rule before any backend sees it.  It is a superset of BNF, EBNF, ABNF and YBNF (yacc's grammar language).

The design is for anyone who is comfortable reading the RFCs. HyperBNF makes BNF
natural and readable the way the RFCs do: a grammar reads like the notation
RFCs have used for decades, not like a yacc file with embedded C actions.

HyperBNF ships with the basic formats ready to use: JSON, TOML, YAML and obconf, the config file
format that OpenBSD uses by default for new projects.  Drop one in and you have a parser; the grammar is short, readable
HyperBNF, so changing it to fit your own needs means editing a few lines, not learning a generator.

It is powerful enough to parse context-sensitive languages such as ALGOL 68 and C++ without breaking
a sweat: parameterised rules, back-references and context sets carry what a yacc grammar leaves to
hand-written lexer hacks.

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
"Hartmeier's BNF". It also reads as **HyperBNF**, which is what the notation
has grown into: the dialects of BNF, read as one.  The wish to implement obconf
(the OpenBSD configuration style) inspired it, and obconf is now one grammar
written in it, beside JSON, TOML and YAML.

## Two things

This directory holds two things:

1. **libhbnf**, a static Ada library: the grammar reader, the compilability
   checks and the four emitters (C, Rust, Zig, Ada).  Everything `hbnf` does is
   in it, and `hbnf`, the command line, is a thin wrapper over it: argument
   parsing, finding the templates, and printing what the library returns.
2. **The parser generator**, `hbnf`: read a schema in HyperBNF's ABNF-like
   notation and generate a parser and its typed tree in C, Rust, Zig or Ada.

       hbnf grammars/obconf_ntpd.hbnf --backend=c|rust|zig|ada
       hbnf grammars/bind/ntpd.hbnf --backend=c --conf   # ntpd's parse_config

   The generator's documents:
   - `WHY.md`: the grammar and its design choices, for an RFC reader;
   - `grammars/README.md`: the notation, and the nine daemon grammars
     translated from their `parse.y`;
   - `ABNF.md`: the notation against RFC 5234, feature by feature;
   - `CHARLAYER.md`: character rules, numeric terminals and UTF-8;
   - `WIRE.md`: octets and bit fields (`ttl:8`, `version@0:4`), enum numbers
     (`"icmp"@1`), and parsers that also write bytes back;
   - `RFCPLAN.md`: the plan to compile RFC grammars as written;
   - `USENIXSUBMISSION.md`: the design paper, with measurements.

## All the documents

Every markdown file in the repository, so none is lost.

**Start here**
- [`TUTORIAL.md`](TUTORIAL.md): start here: a six-line grammar to a typed tree you can use, in C, Zig, Rust and Ada, and the error messages.

**The design and its plan**
- [`WHY.md`](WHY.md): the grammar and its design choices, for an RFC reader.
- [`RFCPLAN.md`](RFCPLAN.md): the plan, its decisions and its status, step by step.
- [`ABNF.md`](ABNF.md): the notation against RFC 5234, feature by feature.
- [`CHARLAYER.md`](CHARLAYER.md): character rules, numeric terminals and UTF-8.
- [`WIRE.md`](WIRE.md): octets and bit fields, enum numbers, text and bit rules
  together, and parsers that also write bytes back.
- [`COMPILER-COMPILER.md`](COMPILER-COMPILER.md): what HyperBNF is as a compiler-compiler.
- [`METACOMPILERS.md`](METACOMPILERS.md): hbnf beside META II, IMP72, SNOBOL4 and
  W-grammars.
- [`IDREF.md`](IDREF.md): the id-ref serializer output of the C backend.
- [`USENIXSUBMISSION.md`](USENIXSUBMISSION.md): the design paper, with measurements.
- [`HISTORY.md`](HISTORY.md): a short history of the parser generator.
- [`STYLE.md`](STYLE.md): the Ada style the sources follow.

**Grammars, bindings and tests**
- [`grammars/README.md`](grammars/README.md): the notation and the nine daemon grammars.
- [`bindings/README.md`](bindings/README.md): the FFI bindings.
- [`tests/bytetest/README.md`](tests/bytetest/README.md): the byte-identity harness
  against OpenBSD's `parse.y`.

**Corpora** ([`corpus/README.md`](corpus/README.md) is the index)
- [`corpus/rfc/README.md`](corpus/rfc/README.md): RFC grammar snippets and vectors:
  [RFC 3986](corpus/rfc/rfc3986-1.md), [RFC 5234](corpus/rfc/rfc5234-1.md),
  [RFC 5322](corpus/rfc/rfc5322-1.md), [RFC 9112](corpus/rfc/rfc9112-1.md).
- [`corpus/posix/shell.md`](corpus/posix/shell.md): the POSIX shell grammar, read as the standard prints it, checked against dash on every script on the machine.
- [`corpus/algol60/README.md`](corpus/algol60/README.md): the ALGOL 60 report and its BNF.
- [`corpus/imp72/README.md`](corpus/imp72/README.md): the IMP72 compiler's sources (cancelled as a target: IMP72 will get its own compiler).
- [`corpus/mustache/README.md`](corpus/mustache/README.md): Mustache templates, with the back-reference that makes a closing tag repeat its opening one.
- [`corpus/json/README.md`](corpus/json/README.md): JSON in 14 rules, checked against Python's `json`.
- [`corpus/toml/README.md`](corpus/toml/README.md): TOML 1.0 in 46 rules against the ABNF's 124, all 208 valid toml-test files accepted, checked against Python's `tomllib`.
- [`corpus/yaml/README.md`](corpus/yaml/README.md): YAML 1.2, indentation as a number the parser works out, all 308 valid and 89 of 94 invalid cases of the YAML test suite, checked against PyYAML.
- [`corpus/bip39/README.md`](corpus/bip39/README.md): the ten BIP-39 word lists.
- [`corpus/bech32/README.md`](corpus/bech32/README.md): bech32 and bech32m.

**Measurements** ([`bench/README.md`](bench/README.md) says how they are made)
- [environment](bench/results/env.md), [headline](bench/results/headline.md),
  [toy grammar](bench/results/toy.md), [hbnf on the toy](bench/results/hbnf-toy.md),
  [hbnf on pfctl](bench/results/hbnf-pfctl.md), [ntpd](bench/results/ntpd.md),
  [yacc](bench/results/yacc.md), [ANTLR and PEG](bench/results/antlr-peg.md),
  [tree-sitter](bench/results/treesitter.md).

**How much grammar.**  The same language in the published notation and in HyperBNF, with
comments, blank lines and hbnf's directive lines left out of both
(`bench/notation.sh`).  A symbol is a whitespace-separated word.  Mustache is not
here because it has no published grammar to compare with.

For C the published grammars are yacc's, counted by their rules alone (the C actions, the
declarations and the lexer are left out, which favours yacc), and HyperBNF's side is `c11.hbnf`,
which also covers C11 and the GNU forms real code uses, against PCC's, 32V's and GCC 4.0.4's
older dialects.  The last C row adds the 41 token rules that do the lexer's work.  For YAML the published side is the specification's own productions.  HyperBNF puts
alternatives on one line, so it takes far fewer lines than any of them; its rules and symbols
are about PCC's, fewer than GCC's, and more than 32V's.

<!-- bench:notation -->

| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | HyperBNF (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | HyperBNF (`corpus/json`) | 14 | 14 | 129 | 556 |
| | **saved** | **53%** | **69%** | **33%** | **41%** |
| TOML 1.0 | TOML's ABNF (toml.abnf) | 124 | 126 | 666 | 4646 |
| | HyperBNF (`corpus/toml`) | 46 | 49 | 599 | 2599 |
| | **saved** | **63%** | **61%** | **10%** | **44%** |
| C | PCC's cgram.y (NetBSD trunk) | 84 | 368 | 1029 | 6505 |
| | HyperBNF (`corpus/c/c11.hbnf`) | 86 | 116 | 1060 | 8441 |
| | **saved** | **-1%** | **68%** | **-2%** | **-29%** |
|  | 32V's cgram.y (mip) | 55 | 386 | 813 | 3755 |
| | HyperBNF (`corpus/c/c11.hbnf`) | 86 | 116 | 1060 | 8441 |
| | **saved** | **-55%** | **70%** | **-29%** | **-124%** |
|  | GCC 4.0.4's c-parse.in (C part) | 172 | 892 | 1930 | 18966 |
| | HyperBNF (`corpus/c/c11.hbnf`) | 86 | 116 | 1060 | 8441 |
| | **saved** | **50%** | **87%** | **45%** | **55%** |
| | HyperBNF with its token rules (`corpus/c/c-words.hbnf` too) | 130 | 165 | 1445 | 10501 |
| YAML 1.2 | the YAML 1.2.2 spec's productions | 201 | 861 | 1350 | 13273 |
| | HyperBNF (`corpus/yaml`) | 95 | 102 | 1370 | 6008 |
| | **saved** | **53%** | **88%** | **0%** | **55%** |

<!-- /bench:notation -->

## Performance

hbnf's generated C parser against the tools it is usually compared with, on one
toy language written once for each, at 100,000 and 1,000,000 rules.  Every
figure is the output of `bench/run.sh`, put here by `bench/update-docs.sh`;
`WHY.md` has the full table, the real-`parse.y` comparison against OpenBSD's
ntpd, and what the numbers do and do not say.

<!-- bench:headline -->

**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.2 M rules/s | 325 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 125 MB/s | 23 MB |
| bison + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 126 MB/s | 23 MB |
| tree-sitter 0.27.1 | 7.68 MB | 221 ms | 0.5 M rules/s | 35 MB/s | 63 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 207 ms | 0.5 M rules/s | 37 MB/s | 197 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 110 ms | 0.9 M rules/s | 70 MB/s | 530 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 236 ms | 4.2 M rules/s | 325 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 612 ms | 1.6 M rules/s | 126 MB/s | 224 MB |
| bison + flex | 76.86 MB | 619 ms | 1.6 M rules/s | 124 MB/s | 224 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2176 ms | 0.5 M rules/s | 35 MB/s | 620 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1302 ms | 0.8 M rules/s | 59 MB/s | 1426 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1125 ms | 0.9 M rules/s | 68 MB/s | 3027 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._

<!-- /bench:headline -->

### JSON, TOML and YAML

The three formats HyperBNF ships, through the C backend, against the libraries usually used
for them, on one generated document each (a list of records with strings, numbers, booleans,
lists and a nested table).  The numbers are `bench/run.sh --only=formats`.  What is built differs:
the generated parser builds the typed tree its grammar describes, with each string copied into
an arena; the libraries build the host language's own objects, which is what a program then
holds.  Python's `json` is a C extension and `JSON.parse` is V8's hand-tuned C++, so these are
native parsers; where one is faster, the table says so.

<!-- bench:formats -->

**JSON** (2.00 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 13 ms | 151 MB/s | 15 MB |
| Python 3.14.8 json | 16 ms | 122 MB/s | 19 MB |
| Node 24.18.1 JSON.parse | 8.5 ms | 235 MB/s | 51 MB |

**TOML 1.0** (1.99 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 30 ms | 65 MB/s | 24 MB |
| Python tomllib | 278 ms | 7 MB/s | 23 MB |

**YAML 1.2** (1.99 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 148 ms | 13 MB/s | 119 MB |
| PyYAML 6.0.3 on libyaml (C) | 698 ms | 3 MB/s | 114 MB |
| PyYAML, pure Python | 3.44 s | 1 MB/s | 162 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._

<!-- /bench:formats -->

## Naming

- **hbnf**: the parser generator and compiler compiler. Reads a grammar, emits
  a parser in C, Rust, Zig or Ada. Also the command line, the Alire name, and
  the project file (`hbnf.gpr`).
- **obconf**: a configuration language, implemented as a grammar in HyperBNF, for
  OpenBSD config files — keyword arguments, `{ }` blocks, `#` comments.
- **libhbnf**: the static Ada library (`libhbnf.a`, project `libhbnf.gpr`)
  that the `hbnf` command line wraps.  A C reference implementation, if there
  is one, will not take this name for its shared library.  (There used to be an
  Ada package `HBNF_Config` here, a hand-written obconf reader.  Its job is
  done by a parser generated from `hbnf_schema.hbnf`; see below.)

## Credits

Four initials cannot hold the whole lineage: HyperBNF is *named for* Hartmeier,
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
