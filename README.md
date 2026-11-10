# HyperBNF

Parent: [All Projects](https://moebiusv.github.io/) | Git Repo: [github.com/moebiusV/hbnf](https://github.com/moebiusV/hbnf) | `git clone https://github.com/moebiusV/hbnf`

> **Status, 31 October 2026.**  JSON, TOML and YAML are built and tested in all four backends
> (TOML against toml-test and `tomllib`, YAML against the YAML test suite and PyYAML), and are
> measured against the libraries people use for them, on glibc.  C is a family of grammars, each
> checked against its own era's yacc grammar and compiler: `c79` (UNIX/32V's C, run over the 32V
> source tree itself), `c89`, `c99`, `pcc99` (what PCC's `cgram.y` reads), `gnu99` (what GCC 4.0.4's
> reads) and `c11`; the C parser is also measured against `gcc -fsyntax-only` and run over the
> SQLite amalgamation.  A grammar chooses the structure its parser builds: the typed tree (layout
> `ast`, the default), a flat tape of words (`tape`, `runtime/hbnf_tape.h`), or BSD's
> `sys/queue.h` and `sys/tree.h` containers (`tailq`, `rb`).  `%emit` blocks write the tape by hand
> where a layout does not fit.  The parsers read alternatives that begin alike once, and a ladder of
> binary operators with one look past its first operand.  The code templates are rendered by the
> project's own Mustache package, `HBNF_Template`, so libhbnf depends on nothing outside the GNAT
> runtime.
> Next: the tape layout for `str`, `bool`, `flag` and the fixed-width numbers and for the Rust, Zig and
> Ada backends (`RFCPLAN.md`), C17 and C23 for the C family, the C grammars through LLVM's ORC JIT and
> lld, the C preprocessor grammar and the typedef context for C, error recovery, grammars for COBOL,
> ALGOL 68 and C++ (full GLR where they need it, paid for only by the grammar that uses it), and the
> benchmark of the four backends against each other (the numbers here are the C backend's).

**HyperBNF** is a grammar language, and `hbnf` is the program that reads it: a parser generator
(a compiler compiler) that emits a parser and its typed tree in C, Rust, Zig or Ada.  The name is an
homage to the W-grammar and its hyper-rules: a rule may take parameters, and each use becomes an
ordinary rule before any backend sees it.  It is a superset of BNF, EBNF, ABNF and YBNF (yacc's grammar language).

The design is for anyone who is comfortable reading the RFCs. HyperBNF makes BNF
natural and readable the way the RFCs do: a grammar reads like the notation
RFCs have used for decades, not like a yacc file with embedded C actions.

It is also a tool for making language models more effective, on one premise: what lessens a
person's mental load lessens a model's token usage.  A grammar short enough for a person to hold in
mind is short enough for a model to read and write cheaply, and the same file gives a program its
parser.  `HISTORY.md` makes the case, `WHY.md` counts the tokens, and step 14 of `RFCPLAN.md` plans
the emitter that would hand the same grammar to a model's decoder.

HyperBNF ships with the basic formats ready to use: JSON, TOML, YAML and obconf (the OpenBSD configuration format).  Drop one in and you have a
parser; the grammar is short, readable HyperBNF, so changing it to fit your own needs means editing a
few lines, not learning a generator.

Parameterised rules, back-references and context sets carry what a yacc grammar leaves to
hand-written lexer hacks, which is what context-sensitive languages need.

ABNF is the starting point because it is the notation the RFCs actually use:
RFC 5234 defines it, RFC 7405 adds case-sensitive string literals, and dozens
of newer RFCs specify their protocols in it. Start from the notation people
already read fluently, and a grammar is documentation first and a parser
second.

The configuration file format that OpenBSD uses by default for new projects was the initial inspiration for developing hbnf, but then
that revealed some problems in the parser generator world that looked like they needed solving.  The
format and the grammar for it are in [`obconf.md`](obconf.md).

## Two things

This directory holds two things:

1. **libhbnf**, a static Ada library: the grammar reader, the compilability
   checks and the four emitters (C, Rust, Zig, Ada).  Everything `hbnf` does is
   in it, and `hbnf`, the command line, is a thin wrapper over it: argument
   parsing, finding the templates, and printing what the library returns.
2. **The parser generator**, `hbnf`: read a schema in HyperBNF's ABNF-like
   notation and generate a parser and its typed tree in C, Rust, Zig or Ada.

       hbnf corpus/json/json.hbnf --backend=c|rust|zig|ada

   `--layout=ast|tape|tailq|rb|NAME` picks the structure the parser builds (layouts are directories,
   `layouts/NAME/layout.hbnf`, found by `--layouts=DIR` or `$HBNF_LAYOUTS`), `--lint` says where an
   ordered choice `|` could be a union `/`, and `--no-factor` and `--no-ladder` turn off the shared
   reading of alternatives that begin alike and of a ladder of binary operators.

   The generator's documents:
   - `WHY.md`: the grammar and its design choices, for an RFC reader;
   - `ABNF.md`: the notation against RFC 5234, feature by feature;
   - `CHARLAYER.md`: character rules, numeric terminals and UTF-8;
   - `WIRE.md`: octets and bit fields (`ttl:8`, `version@0:4`), enum numbers
     (`"icmp"@1`), and parsers that also write bytes back;
   - `RFCPLAN.md`: the plan to compile RFC grammars as written;
   - `USENIXSUBMISSION.md`: the design paper, with measurements.

## All the documents

Every markdown file in the repository, so none is lost; `obconf.md` lists the ones that belong
to the OpenBSD configuration files.

**Start here**
- [`TUTORIAL.md`](TUTORIAL.md): start here: a six-line grammar to a typed tree you can use, in C, Zig, Rust and Ada, and the error messages.

**The design and its plan**
- [`WHY.md`](WHY.md): the grammar and its design choices, for an RFC reader.
- [`RFCPLAN.md`](RFCPLAN.md): the plan, its decisions and its status, step by step.
- [`decisions-and-status.md`](decisions-and-status.md): each design and implementation choice with its rationale and precedents, and whether it is done, left to do, rejected or left in the air.
- [`ABNF.md`](ABNF.md): the notation against RFC 5234, feature by feature.
- [`CONTEXTS.md`](CONTEXTS.md): design notes, reviewed and kept current: how a rule says it is in a context (an embedded language, a picture string), has an attribute, or is a kind of thing; what is decided and what is built is in the table at the top.
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
- [`obconf.md`](obconf.md): the OpenBSD configuration file format hbnf started from: its grammar,
  the daemon grammars and bindings ([`grammars/README.md`](grammars/README.md),
  [`bindings/README.md`](bindings/README.md),
  [`tests/bytetest/README.md`](tests/bytetest/README.md)), and the name's lineage.

**Corpora** ([`corpus/README.md`](corpus/README.md) is the index)
- [`corpus/rfc/README.md`](corpus/rfc/README.md): RFC grammar snippets and vectors:
  [RFC 3986](corpus/rfc/rfc3986-1.md), [RFC 5234](corpus/rfc/rfc5234-1.md),
  [RFC 5322](corpus/rfc/rfc5322-1.md), [RFC 9112](corpus/rfc/rfc9112-1.md).
- [`corpus/posix/shell.md`](corpus/posix/shell.md): the POSIX shell grammar, read as the standard prints it, checked against dash on every script on the machine.
  ([`corpus/posix/posix-shell-1.md`](corpus/posix/posix-shell-1.md) is the standard's text it is read from.)
- [`corpus/c/README.md`](corpus/c/README.md): C in six grammars (`c79`, `c89`, `c99`, `pcc99`, `gnu99`, `c11`), each against its era's yacc grammar and compiler; [`corpus/c/originals/README.md`](corpus/c/originals/README.md) lists the original grammars they are counted against.
- [`corpus/algol60/README.md`](corpus/algol60/README.md): the ALGOL 60 report and its BNF.
- [`corpus/imp72/README.md`](corpus/imp72/README.md): the IMP72 compiler's sources (cancelled as a target: IMP72 will get its own compiler).
- [`corpus/cobol/README.md`](corpus/cobol/README.md): COBOL in free format, checked against GnuCOBOL's `cobc`; a core of the language, begun.
- [`corpus/sgml/README.md`](corpus/sgml/README.md): SGML (ISO 8879), the part a grammar can read: the DTD's declarations, the SGML declaration and the instance's markup; no oracle was available.
- [`corpus/mustache/README.md`](corpus/mustache/README.md): Mustache templates, with the back-reference that makes a closing tag repeat its opening one.
- [`corpus/json/README.md`](corpus/json/README.md): JSON in 14 rules, checked against Python's `json`.
- [`corpus/toml/README.md`](corpus/toml/README.md): TOML 1.0 in 46 rules against the ABNF's 124, all 208 valid toml-test files accepted, checked against Python's `tomllib`.
- [`corpus/yaml/README.md`](corpus/yaml/README.md): YAML 1.2, indentation as a number the parser works out, all 308 valid and 89 of 94 invalid cases of the YAML test suite, checked against PyYAML.  The YAML 1.2.2 productions it is counted against are described in [`corpus/yaml/originals/README.md`](corpus/yaml/originals/README.md).
- [`corpus/graphql/README.md`](corpus/graphql/README.md): GraphQL (October 2021), the executable language and the type system in 54 rules against the specification's 99, no word reserved where the specification does not reserve it, 145 good and 145 bad files in four backends.
- [`corpus/js/README.md`](corpus/js/README.md): JavaScript (ECMAScript 2023), the Script and Module goals in 151 rules against the specification's 303 productions; semicolon insertion and `return`/`++`/`=>` line-end restrictions by `eol`; the test262 parser tests and V8 as the oracle.
- [`corpus/bip39/README.md`](corpus/bip39/README.md): the ten BIP-39 word lists.
- [`corpus/bech32/README.md`](corpus/bech32/README.md): bech32 and bech32m.

**Measurements** ([`bench/README.md`](bench/README.md) says how they are made)
- [environment](bench/results/env.md), [headline](bench/results/headline.md),
  [toy grammar](bench/results/toy.md), [hbnf on the toy](bench/results/hbnf-toy.md),
  [yacc](bench/results/yacc.md), [ANTLR and PEG](bench/results/antlr-peg.md),
  [tree-sitter](bench/results/treesitter.md), [the libraries](bench/results/libs.md),
  [C against gcc](bench/results/cspeed.md), [number conversion](bench/results/scalar.md),
  [the Haskell parsers](bench/results/haskell.md), [the Raku parsers](bench/results/raku.md), [the size of the notations](bench/results/notation.md),
  [tokens](bench/results/tokens.md), [the corpora with the old node layout and compact nodes](bench/results/corpus.md)
  (in [Rust](bench/results/corpus_rust.md), [Zig](bench/results/corpus_zig.md) and
  [Ada](bench/results/corpus_ada.md) too), the daemons' speed ([ntpd](bench/results/ntpd.md), and
  [pfctl](bench/results/hbnf-pfctl.md) against [its yacc](bench/results/pfctl_yacc.md)) and the size of
  their grammars against `parse.y` ([parsey](bench/results/parsey.md)).

**How much grammar.**  The same language in the published notation and in HyperBNF, with
comments, blank lines and hbnf's directive lines left out of both
(`bench/notation.sh`).  A symbol is a whitespace-separated word.  Mustache is not
here because it has no published grammar to compare with.

For C the published grammars are yacc's, counted by their rules alone (the C actions, the
declarations and the lexer are left out, which favours yacc, and so are the `%left` precedence
declarations, which spare a yacc grammar the ladder of expression rules HyperBNF writes out), and each
is set against the HyperBNF grammar of the C it reads: UNIX/32V's (1979) against `c79.hbnf`; PCC's
against `pcc99.hbnf`, which is C99, the C11 forms PCC's grammar has, and its subset of the GNU
extensions; and GCC 4.0.4's against `gnu99.hbnf`, C99 and the GNU extensions its grammar reads.  Each C
grammar is counted alone, and then with the token rules that do the lexer's work.  For YAML the
published side is the specification's own productions.  HyperBNF puts alternatives on one line, so it
takes far fewer lines than any of them.  Against the yacc grammars of 32V, PCC and GCC it takes fewer
rules, and about as many symbols or fewer (PCC's, within half a percent); in characters it is larger than
32V's and PCC's, because its rules are named as the standard names them and a yacc grammar's are short,
and smaller than GCC's.

<!-- bench:notation -->

| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | HyperBNF (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | HyperBNF (`corpus/json`) | 17 | 17 | 138 | 653 |
| | **saved** | **43%** | **62%** | **28%** | **31%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/json/json-tape.hbnf`) | 17 | 22 | 158 | 755 |
| | the same with the C it carries (the tags, the emits) | 17 | 28 | 243 | 1324 |
| | the tape both tape grammars share (`runtime/hbnf_tape.h`) | 0 | 80 | 331 | 2037 |
| TOML 1.0 | TOML's ABNF (toml.abnf) | 124 | 126 | 666 | 4646 |
| | HyperBNF (`corpus/toml`) | 45 | 49 | 600 | 2682 |
| | **saved** | **64%** | **61%** | **10%** | **42%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/toml/toml-tape.hbnf`) | 45 | 57 | 635 | 2853 |
| | the same with the C it carries (the tags, the emits) | 45 | 63 | 807 | 3968 |
| C | 32V's cgram.y (mip), 1979 | 55 | 386 | 813 | 3755 |
| | HyperBNF (`corpus/c/c79.hbnf`) | 51 | 75 | 623 | 4573 |
| | **saved** | **7%** | **81%** | **23%** | **-21%** |
| | HyperBNF with its token rules (`corpus/c/c79-words.hbnf` too) | 80 | 107 | 937 | 6073 |
|  | PCC's cgram.y (NetBSD trunk) | 84 | 368 | 1029 | 6505 |
| | HyperBNF (`corpus/c/pcc99.hbnf`) | 79 | 109 | 1034 | 7943 |
| | **saved** | **6%** | **70%** | **0%** | **-21%** |
| | HyperBNF with its token rules (`corpus/c/pcc99-words.hbnf` too) | 118 | 157 | 1489 | 10360 |
|  | GCC 4.0.4's c-parse.in (C part) | 172 | 892 | 1930 | 18966 |
| | HyperBNF (`corpus/c/gnu99.hbnf`) | 80 | 120 | 1080 | 8414 |
| | **saved** | **53%** | **87%** | **44%** | **56%** |
| | HyperBNF with its token rules (`corpus/c/gnu99-words.hbnf` too) | 119 | 169 | 1539 | 10888 |
| YAML 1.2 | the YAML 1.2.2 spec's productions | 201 | 861 | 1350 | 13273 |
| | HyperBNF (`corpus/yaml`) | 94 | 109 | 1423 | 6287 |
| | **saved** | **53%** | **87%** | **-4%** | **53%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/yaml/yaml-tape.hbnf`) | 97 | 120 | 1594 | 7107 |
| | the same with the C it carries (the tags, the emits) | 97 | 127 | 1998 | 9916 |

<!-- /bench:notation -->

## Performance

hbnf's generated C parser against the tools it is usually compared with, on one
toy language written once for each, at 100,000 and 1,000,000 rules.  Every
figure is the output of `bench/run.sh`, put here by `bench/update-docs.sh`;
`WHY.md` has the full table and what the numbers do and do not say.

<!-- bench:headline -->

**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 15 ms | 6.8 M rules/s | 526 MB/s | 17 MB |
| byacc + flex | 7.68 MB | 52 ms | 1.9 M rules/s | 147 MB/s | 29 MB |
| bison + flex | 7.68 MB | 53 ms | 1.9 M rules/s | 146 MB/s | 29 MB |
| tree-sitter 0.27.1 | 7.68 MB | 213 ms | 0.5 M rules/s | 36 MB/s | 58 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 301 ms | 0.3 M rules/s | 25 MB/s | 217 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 95 ms | 1.1 M rules/s | 81 MB/s | 471 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 148 ms | 6.8 M rules/s | 520 MB/s | 137 MB |
| byacc + flex | 76.86 MB | 523 ms | 1.9 M rules/s | 147 MB/s | 273 MB |
| bison + flex | 76.86 MB | 532 ms | 1.9 M rules/s | 144 MB/s | 273 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2164 ms | 0.5 M rules/s | 36 MB/s | 564 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1601 ms | 0.6 M rules/s | 48 MB/s | 1177 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1171 ms | 0.9 M rules/s | 66 MB/s | 2110 MB |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._

<!-- /bench:headline -->

### JSON, TOML, YAML and XML against the parsers people use

The same four documents against the parsers people use for each format: the popular C, C++ and
Rust libraries, built from one source with the same flags, and the parsers that Python and Node
programs call.  All of it runs on glibc (Debian).  The libraries were picked by GitHub stars and
package downloads, limited to what Debian packages or ships as a single file.  For XML they are
expat (the base of Python's pyexpat and ElementTree, of Firefox and Apache), libxml2 (the base of lxml
and xmllint), pugixml, TinyXML-2 and RapidXML (the original 1.13, unmaintained since 2009), the Python
and Node parsers (ElementTree, lxml, the raw `xml.parsers.expat`, fast-xml-parser and sax), against the
typed tree of `corpus/xml/xml.hbnf`.  The XML table has a column that says what each parser hands the
program, because they differ most there: expat, libxml2's SAX2 interface, pyexpat and sax are event
parsers that build nothing (the expat row that copies names, attributes and text into arrays shows the
price of a cheap tree), pugixml, TinyXML-2, RapidXML, libxml2, ElementTree and lxml build a DOM, and
every XML parser has to find the same elements, attributes and text as ElementTree or its row says
`check failed`.  The last column says whether the parser is a conforming XML 1.0 parser: how many of 34 documents that each break one well-formedness constraint it refuses (and, not shown, whether it accepts 11 well-formed ones), by `bench/xml-conformance.sh`, which keeps its result and checks a parser again only when its version, the case set or hbnf's grammar changes.  expat, libxml2, ElementTree and lxml refuse all 34; hbnf's grammar does since 2026-11-04; pugixml (8), RapidXML (7), TinyXML-2 (9), sax (20) and fast-xml-parser's `parse` (0) are marked with a red cross, because they accept content XML forbids, and their times are not like for like with the others.  What each builds
differs: the C++ and Rust libraries, Python, Node and the YAML parsers produce their own value
types, simdjson is its DOM API, and hbnf builds the typed tree its grammar describes.  Peak RSS is
the whole process, input included, and the last column shows it as a multiple of the input.  The
numbers are `bench/libs.sh`.

<!-- bench:libs -->

**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 2.2 ms | 922 MB/s | 4 MB | 1.6x |
| simdjson (DOM) | 2.3 ms | 870 MB/s | 12 MB | 5.6x |
| hbnf (C backend), typed tree | 2.8 ms | 727 MB/s | 7 MB | 2.7x |
| RapidJSON | 5.1 ms | 393 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.6 ms | 207 MB/s | 54 MB | 27.7x |
| Python json | 12 ms | 170 MB/s | 20 MB | 9.7x |
| cJSON | 12 ms | 166 MB/s | 17 MB | 8.1x |
| serde_json (Rust) 1.0.154 | 14 ms | 145 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 69 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 5.1 ms | 391 MB/s | 5 MB | 2.0x |
| hbnf (C backend), typed tree | 5.8 ms | 345 MB/s | 10 MB | 4.3x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 59 ms | 34 MB/s | 57 MB | 29.4x |
| Python tomllib | 255 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 650 ms | 3 MB/s | 93 MB | 48.5x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 7.5 ms | 264 MB/s | 5 MB | 1.7x |
| hbnf (C backend), typed tree | 12 ms | 160 MB/s | 18 MB | 8.9x |
| rapidyaml | 21 ms | 93 MB/s | 25 MB | 12.4x |
| libyaml | 42 ms | 48 MB/s | 39 MB | 19.8x |
| libfyaml | 69 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 123 ms | 16 MB/s | 81 MB | 41.8x |
| yaml-cpp | 287 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 709 ms | 3 MB/s | 118 MB | 61.1x |

**XML 1.0** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | builds | parse time | MB/s | peak RSS | RSS over the input | conforms to XML 1.0 (refuses the 34 ill-formed documents) |
|---|---|---:|---:|---:|---:|---:|
| pugixml | DOM, in place | 2.8 ms | 719 MB/s | 10 MB | 4.6x | ❌ 8 of 34 |
| hbnf (C backend), tape | a flat tape of 64-bit words | 3.5 ms | 564 MB/s | 5 MB | 2.1x | 34 of 34 |
| RapidXML | DOM, in place | 3.9 ms | 515 MB/s | 13 MB | 5.9x | ❌ 7 of 34 |
| hbnf (C backend), tree | the grammar's typed tree | 4.3 ms | 462 MB/s | 10 MB | 4.5x | 34 of 34 |
| libxml2, SAX2 events only | nothing (handlers count) | 4.8 ms | 415 MB/s | 6 MB | 2.4x | 34 of 34 |
| expat, events only | nothing (handlers count) | 8.4 ms | 238 MB/s | 5 MB | 1.8x | 34 of 34 |
| Python xml.parsers.expat, no handlers | nothing (well-formedness only) | 9.1 ms | 219 MB/s | 12 MB | 5.7x | 34 of 34 |
| TinyXML-2 | DOM | 10 ms | 196 MB/s | 17 MB | 8.1x | ❌ 9 of 34 |
| expat, events copied into a tree | a cheap tree of copies | 12 ms | 163 MB/s | 11 MB | 5.1x | 34 of 34 |
| libxml2, DOM | DOM | 17 ms | 115 MB/s | 29 MB | 14.6x | 34 of 34 |
| lxml (Python) | Element tree on libxml2 | 25 ms | 81 MB/s | 42 MB | 21.1x | 34 of 34 |
| Python xml.etree.ElementTree | Element tree | 31 ms | 65 MB/s | 30 MB | 14.9x | 34 of 34 |
| Python xml.parsers.expat, Python callbacks | nothing (Python callbacks count) | 32 ms | 63 MB/s | 13 MB | 5.8x | 34 of 34 |
| sax (Node) | nothing (handlers count) | 114 ms | 18 MB/s | 69 MB | 35.5x | ❌ 20 of 34 |
| fast-xml-parser (Node) | JavaScript objects | 271 ms | 7 MB/s | 113 MB | 58.4x | ❌ 0 of 34 |

_2026-11-05; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf f95d41d.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree.  The XML parsers: expat 2.9.0, libxml2 2.12.7, pugixml 1.14, TinyXML-2 11.0.0, RapidXML 1.13 (Marcin Kalicinski's original, unmaintained since 2009), lxml 5.4.0, fast-xml-parser 5.11.2, sax 1.6.1; the first six are Debian packages, the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar is measured twice: its typed tree and the same grammar under `--layout=tape` (the tape holds the elements, attributes and texts as 64-bit words; the driver counts from it), and that tree and that tape is the grammar's concrete syntax (a reference is a node and characters are not decoded).  The last column is `bench/xml-conformance.sh` (`bench/results/xml-conformance.md`): of 34 documents that each break one well-formedness constraint of XML 1.0 (a forbidden control character, invalid UTF-8, `]]>` or `<` where they may not be, two root elements, a bad character reference, a duplicate attribute, an undeclared entity ...), how many the parser refuses; ❌ marks a parser that does not refuse all of them or refuses a well-formed one; conforming parsers are left unmarked.  Expat, libxml2, ElementTree and lxml refuse all of them (34 of 34).  **pugixml (8 of 34), TinyXML-2 (9 of 34) and RapidXML (7 of 34) are not conforming XML parsers**: they check the structure of the tags and accept most content that XML forbids, and fast-xml-parser's `parse` (0 of 34) does not check well-formedness at all (the library has a separate `XMLValidator`, which this table does not time).  hbnf's grammar refuses 34 of 34.  A parser that skips checks does less work, so the time column is not like for like for the marked rows.  The check is done once and kept: a parser is checked again only when its version, the case set or, for hbnf, its grammar or generator changes.  **Measured on a busy machine, as quiet as it would get** (`fuzzy_search` on cores 0-4 and a VM; the YAML probe read 18.0-19.2 ms before and after, against 8.4-9.6 when quiet; load average 9; best of 9 runs each in place of 5, to catch the quieter moments; one core).  The reference rows say how much it cost: RapidJSON 5.1 ms (5.0 quiet), tomlc17 38 (36-38) and libyaml 42 (37-41) are at their quiet readings, simdjson 2.3 (1.7) and rapidyaml 21 (15-18) are 20-35% high, and the XML parsers other than hbnf reproduce their quiet readings (libxml2 SAX2 4.8 ms, expat 8.4).  hbnf's own rows are the ones the load hurts most, because it allocates and touches many fresh pages and a page fault costs about three times as much under this load (its JSON tree read 1.9 ms and its YAML tree 8.5 on the last quiet run, its XML tree 3.4 before the grammar was made conforming): read them as upper bounds.  No figure has been adjusted.  A quiet rerun is in TODO.md._

<!-- /bench:libs -->

On TOML the generated parser is the fastest by a wide margin.  On JSON the parser that writes a tape
(`corpus/json/json-tape.hbnf`) is close to the SIMD parser simdjson, uses less than half its memory, and the
typed-tree parser is ahead of everything else; on YAML both are ahead of rapidyaml, libyaml, libfyaml,
js-yaml, yaml-cpp and PyYAML, which build generic node trees.  The rows that say `%emit tape` build a
flat array of words and no tree (`runtime/hbnf_tape.h`); the others build the typed tree the grammar
describes.  `--layout=tape` makes any grammar's parser write such a tape, with no `%emit` in the grammar.  A program reading a tape converts a number or string with `runtime/hbnf_scalar.h`, which `bench/scalar.sh` compares with fast_float.

### C against gcc

The C11 grammar (`corpus/c/c11.hbnf`) on the same footing: preprocessed C from Lua, zlib and the SQLite
amalgamation, read by the generated parser as a typed tree and as a tape, and by `gcc -fsyntax-only`,
which also checks types.  The typed tree holds a node for every level of the expression grammar, which
is why it is the large one; the tape holds a word or two for each token and rule.  The numbers are
`bench/cspeed.sh`.

<!-- bench:cspeed -->

**47 translation units, 5.0 MB of preprocessed C** (Lua 5.4.7, zlib 1.3.1, the SQLite 3.45.1 amalgamation; best of 5 runs):

| tool | time | MB/s | peak memory, the largest unit alone (2.5 MB of C) |
|---|---:|---:|---:|
| hbnf (C backend), the C11 grammar, typed tree | 0.20 s | 24.4 MB/s | 47 MB |
| hbnf (C backend), the same grammar, `--layout=tape` | 0.12 s | 40.0 MB/s | 27 MB |
| `gcc -fsyntax-only` | 0.48 s | 10.4 MB/s | |

_2026-11-05; gcc (Debian 14.2.0-19) 14.2.0;ldd (Debian GLIBC 2.41-12+deb13u4) 2.41; `-O2`; hbnf 4d2f65a.  `gcc -fsyntax-only` also checks types and starts once for each file; the tree reads the whole program into memory, the tape a word or two for each token and rule._

<!-- /bench:cspeed -->

### Against Haskell's Alex and Happy

`sh bench/haskell.sh` runs the parsers Haskell programs use for the same three documents, in a Debian
container, on the cpu the other benchmarks use: `toml-parser`, which is an Alex lexer and a Happy parser
(its grammar is also built again with the generators in their optimising modes); a JSON grammar in Alex
and Happy, written for the comparison because no complete one is published, in the form the tutorials
give and tuned; `aeson`; and, for YAML, for which no Alex and Happy parser is known, HsYAML (pure Haskell)
and the `yaml` package on libyaml.  Every parser is asked about the good and bad files of the format's
corpus before it is timed, and the table says where one disagrees.

<!-- bench:haskell -->

**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 1.7 ms | 1150 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| aeson | 41 ms | 49 MB/s | 34 MB | agrees with the corpus (75 files); a Value, text and numbers converted |
| Alex and Happy, tuned | 109 ms | 18 MB/s | 48 MB | agrees with the corpus (75 files); a tree, text as slices of the input |
| Alex and Happy, as the tutorials write it | 204 ms | 10 MB/s | 92 MB | agrees with the corpus (75 files); a tree, text as slices of the input |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 5.3 ms | 377 MB/s | 8 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| toml-parser (Alex, Happy), generators in optimising modes | 291 ms | 7 MB/s | 188 MB | agrees with the corpus (31 files); a list of expressions, text as String |
| toml-parser (Alex, Happy), as Debian ships it | 327 ms | 6 MB/s | 188 MB | agrees with the corpus (31 files); a list of expressions, text as String |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 7.0 ms | 282 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| yaml (libyaml) into a Value | 272 ms | 7 MB/s | 75 MB | differs from the corpus on: docs.yaml explicit-key.yaml flow-dedent.yaml; a Value, text converted |
| HsYAML (events) | 6.02 s | 0 MB/s | 17 MB | agrees with the corpus (36 files); the event stream |

_2026-10-28; amd64, glibc (Debian), GHC 9.6.6, Alex 3.4.0.1, Happy 1.20.1.1; `-O2`; hbnf eac77a0.  The Haskell parsers are the syntax alone, as hbnf's are: every one is walked to the end, so nothing is left lazy when the clock stops.  Text is kept as the input holds it where the parser allows (hbnf's tape and the Alex/Happy JSON); the libraries that convert it say so._

<!-- /bench:haskell -->

### Against Raku's grammars

`sh bench/raku.sh` runs the parsers Raku programs use for the same three documents, in a Debian container,
on the cpu the other benchmarks use: `JSON::Tiny`, a JSON grammar written as a Raku grammar, and `JSON::Fast`,
which is hand-written; `TOML`, a Raku grammar for TOML 1.0; and `YAMLish`, a Raku grammar for YAML.  The
grammar-based modules are the ecosystem's tarballs, pinned by hash in `bench/pins.txt`.  Every parser is asked
about the good and bad files of the format's corpus before it is timed, and the table says where one
disagrees or refuses the document.  A parse over 20 seconds is run once.

<!-- bench:raku -->

**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 1.8 ms | 1136 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| JSON::Fast (hand-written Raku) | 291 ms | 7 MB/s | 168 MB | differs from the corpus on: bom.json leading-zero.json; a Raku tree, text and numbers converted |
| JSON::Tiny (a Raku grammar) | 4.29 s | 0 MB/s | 463 MB | differs from the corpus on: bom.json form-feed.json nbsp.json vertical-tab.json; a Raku tree, text and numbers converted |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 4.5 ms | 440 MB/s | 7 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| TOML (a Raku grammar) | 4.49 s | 0 MB/s | 193 MB | differs from the corpus on: arrays.toml dates.toml dotted.toml inline.toml numbers.toml bare-cr.toml inline-newline.toml inline-trailing-comma.toml; a Raku Hash tree, text and numbers converted |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 7.0 ms | 285 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| YAMLish (a Raku grammar) | refused: the module refused the document  | | | differs from the corpus on: anchors.yaml comment.yaml empty.yaml explicit-key.yaml literal.yaml double-yaml.yaml flow-dedent.yaml marker-in-flow.yaml; a Raku tree, text converted |

_2026-11-02; amd64, glibc (Debian), Rakudo v2024.09; hbnf d9f7a84.  The Raku modules are the syntax alone, as hbnf's are: the tree each builds is complete when the clock stops.  A run over 20 s is not repeated.  The grammar-based modules build Raku values and convert text and numbers; hbnf's tape holds offsets._

<!-- /bench:raku -->

## Naming

- **hbnf**: the parser generator and compiler compiler. Reads a grammar, emits
  a parser in C, Rust, Zig or Ada. Also the command line, the Alire name, and
  the project file (`hbnf.gpr`).
- **libhbnf**: the static Ada library (`libhbnf.a`, project `libhbnf.gpr`)
  that the `hbnf` command line wraps.  A C reference implementation, if there
  is one, will not take this name for its shared library.

## Building

Pure Ada on the GNAT runtime, no C dependency.  The code templates are rendered by the
library's own Mustache package, `HBNF_Template` (`hbnf_template.ads`); it reads a template with the
parser hbnf makes of `grammars/template.hbnf` (`hbnf_template_syntax*`, regenerated by
`scripts/gen-template-syntax.sh`, tested by `tests/template.sh`).

```
gprbuild -P libhbnf.gpr -p -XLIBRARY_TYPE=static
gprinstall -P libhbnf.gpr -p --prefix=/usr --sources-subdir=include/hbnf
```

Packaged for Alpine by the `ada-on-alpine` aports overlay as `testing/hbnf`.

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
expression functions, as few `out`/`in out` parameters as possible, loops replaced by `'Reduce`
and comprehensions, and side effects kept at the edges. Read it before
contributing.

## License

ISC. See `LICENSE`.
