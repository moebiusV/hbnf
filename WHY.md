# The grammar, and why

For the reader who already reads the RFCs, HyperBNF's grammar is meant to be
obvious: it looks like the BNF the RFCs wrote, and where it differs, the
difference is a choice with a reason.

## Shift/reduce conflicts are an LR artifact

Shift/reduce and reduce/reduce conflicts are artifacts of the LR/LALR parsing
algorithms behind yacc and bison. The parser's state machine looks at the next
token and decides, by table lookup, whether to keep reading (shift) or collapse
the tokens it has into a syntax-tree node (reduce). When the table cannot
decide, it reports a conflict.

RFC BNFs are written for human comprehension, not for algorithmic determinism,
so they are almost always mathematically ambiguous. Paste one verbatim into
bison and it explodes with shift/reduce conflicts.

## Error messages, tool by tool

**Yacc / bison (LALR).** Hostile to anyone without an automata background. An
ambiguity surfaces as `State 45 conflicts: 2 shift/reduce`. Debugging it means
dumping a `.output` file, scrolling a finite-state-machine listing to
"State 45", and tracing the lookahead tokens by hand; fixing it means
precedence declarations (`%left`, `%right`) or restructuring the LR grammar.
For someone who just wants to implement a syntax specification, this is a cliff.

**Lex / flex.** Lexing is regular expressions, so errors here are usually a
malformed regex or overlapping rule, and they are straightforward. But lex and
flex are half of a lex/yacc pair: once the tokens meet the grammar, you are back
in the state machine.

**ANTLR v4 (ALL(*)).** Eliminates shift/reduce conflicts entirely. Its adaptive
top-down algorithm explores multiple paths at runtime, and an ambiguous grammar
is resolved by taking the rule listed first. Compile-time messages are
readable, and left recursion is handled natively, so a left-recursive RFC
definition stays as written.

**PEG (parsing expression grammars).** Ordered choice instead of unordered BNF
alternatives, so a PEG cannot have shift/reduce conflicts and cannot be
ambiguous: the parser tries the alternatives in the order listed and commits to
the first that works. The cost is a silent bug class, prefix hijacking. If rule
A matches a prefix of rule B and A is listed first, B is unreachable, and the
generator rarely warns. Instead of a compile error, the generated parser fails
to parse valid input at runtime, with an unhelpful message about an unexpected
token.

## The RFC translation trap

Left recursion is the trap. RFCs write lists and expressions left-recursively
(`expression = expression "+" term`). Bison needs restructuring or precedence
hacks. A PEG loops forever on left recursion and needs a manual rewrite into
repetition. ANTLR v4 keeps the grammar almost identical to the RFC text.

## Notation: every RFC era, and what ABNF lacks

hbnf accepts the spellings of every RFC era, for the human's convenience, to
lessen the cognitive load of pasting a grammar. The early RFC BNF (RFC 733,
RFC 822) wrote a rule `name ::= definition` and alternation with `|`; ABNF,
from RFC 2234 into RFC 5234, wrote `name = definition` and `/`. hbnf reads `=`,
`::=` and `:=` as one rule definition, and `|` as alternation, as the early
RFCs wrote it and as PEG and OpenBSD's parse.y read it; `/` means ABNF's union.
A grammar copied from any era compiles without retyping. `[ … ]` for an
optional is established the same way, from both sides at once: it is ABNF's
spelling, and it is also the one every manpage synopsis and command-line usage
line already writes (`ls [OPTION]… [FILE]…`), so the brackets mean "optional"
in a grammar exactly as they do everywhere else.

ABNF also stops at syntax. It has no `{ }` blocks for a prologue and epilogue,
no `%scan{}` scanner escape hatch, and no `%action{}` semantic construction.
hbnf adds all three, because a grammar that only recognizes input cannot build
a tree or drive a program. See `COMPILER-COMPILER.md` for those, and `ABNF.md`
for which `/` forms are implemented and which are still planned.

## Where HyperBNF lands

hbnf picks a side on each point above. It is recursive descent with ordered
choice, so there is no LR state machine and no shift/reduce conflict to debug.
Direct left recursion (`xs = xs "," x | x`) is read as a loop in all four
backends, so the RFC form is not rewritten.

Ordered choice keeps the PEG property that makes conflicts impossible, and hbnf
keeps PEG's one failure mode from being silent. An alternative shadowed by an
earlier one that matches a prefix of it is found at schema time and refused with
a diagnostic ("N alternative(s) can never match"), where a PEG would compile it
and fail at runtime on valid input.

## Ergonomics

Two things make hbnf pleasant to use beyond the notation.

**Helpful errors.** A parse failure is a `line:column` with a caret under where
the error starts and the token that was expected, not a state-machine dump and
not a cryptic "unexpected token".

**Pretty-printing.** A parsed tree renders back to canonical text, and a
grammar that wants to can round-trip exactly: a decimal keeps its literal, a
string is re-quoted with the escape set. Comments are preserved and come back
out in the right places when the source is re-emitted, and printing is
idempotent.

**How much grammar.**  The same language in the published notation and in HyperBNF, with
comments, blank lines and hbnf's directive lines left out of both
(`bench/notation.sh`).  A symbol is a whitespace-separated word.  Mustache is not
here because it has no published grammar to compare with.

<!-- bench:notation -->

| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | HyperBNF (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | HyperBNF (`corpus/json`) | 17 | 17 | 138 | 641 |
| | **saved** | **43%** | **62%** | **28%** | **32%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/json/json-tape.hbnf`) | 17 | 22 | 158 | 743 |
| | the same with the C it carries (the tags, the emits) | 17 | 28 | 243 | 1312 |
| | the tape both tape grammars share (`runtime/hbnf_tape.h`) | 0 | 56 | 228 | 1349 |
| TOML 1.0 | TOML's ABNF (toml.abnf) | 124 | 126 | 666 | 4646 |
| | HyperBNF (`corpus/toml`) | 45 | 49 | 600 | 2604 |
| | **saved** | **64%** | **61%** | **10%** | **44%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/toml/toml-tape.hbnf`) | 45 | 57 | 635 | 2775 |
| | the same with the C it carries (the tags, the emits) | 45 | 63 | 807 | 3890 |
| C | 32V's cgram.y (mip), 1979 | 55 | 386 | 813 | 3755 |
| | HyperBNF (`corpus/c/c79.hbnf`) | 62 | 74 | 674 | 5155 |
| | **saved** | **-12%** | **81%** | **17%** | **-36%** |
| | HyperBNF with its token rules (`corpus/c/c79-words.hbnf` too) | 91 | 106 | 988 | 6649 |
|  | PCC's cgram.y (NetBSD trunk) | 84 | 368 | 1029 | 6505 |
| | HyperBNF (`corpus/c/pcc99.hbnf`) | 92 | 119 | 1074 | 8513 |
| | **saved** | **-9%** | **68%** | **-3%** | **-30%** |
| | HyperBNF with its token rules (`corpus/c/pcc99-words.hbnf` too) | 131 | 167 | 1529 | 10918 |
|  | GCC 4.0.4's c-parse.in (C part) | 172 | 892 | 1930 | 18966 |
| | HyperBNF (`corpus/c/gnu99.hbnf`) | 91 | 131 | 1111 | 8885 |
| | **saved** | **47%** | **85%** | **42%** | **53%** |
| | HyperBNF with its token rules (`corpus/c/gnu99-words.hbnf` too) | 130 | 180 | 1570 | 11347 |
| YAML 1.2 | the YAML 1.2.2 spec's productions | 201 | 861 | 1350 | 13273 |
| | HyperBNF (`corpus/yaml`) | 94 | 109 | 1423 | 6251 |
| | **saved** | **53%** | **87%** | **-4%** | **53%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/yaml/yaml-tape.hbnf`) | 97 | 120 | 1594 | 7071 |
| | the same with the C it carries (the tags, the emits) | 97 | 127 | 1998 | 9880 |

<!-- /bench:notation -->

**Fewer words to read, for a person or a model.**  A symbol is what a person reads; what a
language model reads and writes is counted in tokens, and a grammar that a person can hold in mind
is a grammar a model is charged less for.  The same text counted with two public tokenizers
(`bench/tokens.sh`; Claude's tokenizer is not public, so it was not measured):

<!-- bench:tokens -->

| language | notation | characters | o200k_base tokens | Qwen2.5 tokens |
|---|---|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 8064 | 2290 | 2269 |
| | HyperBNF | 3604 | 890 | 870 |
| | **saved** | **55%** | **61%** | **62%** |
| JSON | RFC 8259's ABNF | 949 | 379 | 407 |
| | HyperBNF | 641 | 247 | 260 |
| | **saved** | **32%** | **35%** | **36%** |
| TOML 1.0 | TOML's ABNF | 4646 | 1564 | 1625 |
| | HyperBNF | 2599 | 1130 | 1193 |
| | **saved** | **44%** | **28%** | **27%** |
| C | 32V's cgram.y, 1979 | 3755 | 1593 | 1566 |
| | HyperBNF | 5155 | 1187 | 1157 |
| | **saved** | **-36%** | **25%** | **26%** |
| | HyperBNF with its token rules | 6649 | 1754 | 1735 |
|  | PCC's cgram.y | 6505 | 2295 | 2248 |
| | HyperBNF | 8628 | 2084 | 2043 |
| | **saved** | **-32%** | **9%** | **9%** |
| | HyperBNF with its token rules | 11033 | 2991 | 2969 |
|  | GCC 4.0.4's c-parse.in | 18966 | 6050 | 5918 |
| | HyperBNF | 8992 | 2149 | 2109 |
| | **saved** | **53%** | **64%** | **64%** |
| | HyperBNF with its token rules | 11454 | 3070 | 3049 |
| YAML 1.2 | the spec's productions | 13273 | 4927 | 4912 |
| | HyperBNF | 6057 | 2642 | 2690 |
| | **saved** | **54%** | **46%** | **45%** |

_The text is the grammar as `notation.sh` counts it.  o200k_base is OpenAI's tokenizer (tiktoken 0.14.0) and Qwen2.5's is an open-weights model's (tokenizers 0.23.3); Claude's tokenizer is not public, so its count was not measured._

<!-- /bench:tokens -->

The premise, the reasoning and the evidence outside this repository are in `HISTORY.md`,
*Leverage: a notation for people is a notation for models*.

## How fast, against whom

The comparison is a script, `bench/run.sh` (`bench/README.md` says what it
needs and what it does not claim), and the tables here are its output, put into
this file by `bench/update-docs.sh`.  No number in this section is typed by
hand.  Every tool parses the same toy language, one rule per line (`pass in on
em0 proto tcp from 192.168.3.7 port 51234 to 192.168.9.1 port 443`), over
byte-identical input.  Each is written idiomatically in its own notation — a
lex and yacc pair the way an OpenBSD `parse.y` is, a PEG, a tree-sitter
grammar, an ANTLR grammar — builds what the parse found, and is checked to have
found the same rules before it is timed.

<!-- bench:toy -->

**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 18 ms | 5.5 M rules/s | 425 MB/s | 15 MB |
| byacc + flex | 7.68 MB | 56 ms | 1.8 M rules/s | 138 MB/s | 29 MB |
| bison + flex | 7.68 MB | 58 ms | 1.7 M rules/s | 133 MB/s | 29 MB |
| peg/leg | 7.68 MB | 44 ms | 2.3 M rules/s | 177 MB/s | 41 MB |
| tree-sitter 0.27.1 | 7.68 MB | 222 ms | 0.4 M rules/s | 35 MB/s | 58 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 33 ms | | | 76 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 257 ms | 0.4 M rules/s | 30 MB/s | 223 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 103 ms | 1.0 M rules/s | 75 MB/s | 606 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 234 ms | 0.4 M rules/s | 33 MB/s | 314 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 184 ms | 5.4 M rules/s | 419 MB/s | 136 MB |
| byacc + flex | 76.86 MB | 564 ms | 1.8 M rules/s | 136 MB/s | 273 MB |
| bison + flex | 76.86 MB | 558 ms | 1.8 M rules/s | 138 MB/s | 273 MB |
| peg/leg | 76.86 MB | 437 ms | 2.3 M rules/s | 176 MB/s | 395 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2303 ms | 0.4 M rules/s | 33 MB/s | 564 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 335 ms | | | 743 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1196 ms | 0.8 M rules/s | 64 MB/s | 1446 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1163 ms | 0.9 M rules/s | 66 MB/s | 2844 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 2033 ms | 0.5 M rules/s | 38 MB/s | 2502 MB |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.11 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._

<!-- /bench:toy -->

At 100,000 rules hbnf's generated C parser takes <!-- v:hbnf_100000_ms -->18<!-- /v --> ms.  byacc with flex
takes <!-- v:byacc_100000_ms -->56<!-- /v --> ms (<!-- v:ratio_byacc_100000 -->3.1<!-- /v --> times as long), peg/leg <!-- v:ratio_peg_100000 -->2.4<!-- /v --> times, tree-sitter
<!-- v:ratio_ts_100000 -->12<!-- /v --> times, and ANTLR <!-- v:ratio_antlr_cold_100000 -->14<!-- /v --> times in a fresh JVM (<!-- v:ratio_antlr_warm_100000 -->5.7<!-- /v --> times once
the JVM is warm).  At 1,000,000 rules the ratios hold (byacc <!-- v:ratio_byacc_1000000 -->3.1<!-- /v -->, tree-sitter
<!-- v:ratio_ts_1000000 -->13<!-- /v -->), so every tool's cost is linear and the table is not a small-input
effect.  Peak memory follows the same order: <!-- v:hbnf_100000_rss_mb -->15<!-- /v --> MB for hbnf, <!-- v:byacc_100000_rss_mb -->29<!-- /v --> MB for
byacc, <!-- v:ts_100000_rss_mb -->58<!-- /v --> MB for tree-sitter.

Three things this does not say.  The trees differ: hbnf builds typed structs
whose strings are slices of the input, the yacc and PEG parsers copy each
string, tree-sitter builds a node per token, and ANTLR's actions-only rows
build no tree at all.  The toy is the smallest realistic shape; the full pfctl
grammar, with its 35-way option alternation, takes <!-- v:pfctl_100000_ms -->168<!-- /v --> ms and <!-- v:pfctl_100000_rss_mb -->148<!-- /v --> MB for
100,000 rules, about <!-- v:pfctl_vs_toy_time -->9<!-- /v --> times the toy per rule, and that is the number to
set against a production ruleset.  And a machine with other work on it gives
slower, noisier times; the load average at the start of the run is recorded
under every table.

### A real parse.y

The toy is written by us for every tool, so it cannot settle whether hbnf
matches a parser people actually run.  This can: OpenBSD's ntpd `parse.y` at a
pinned commit, unmodified, built with byacc against stubs for the rest of ntpd,
against hbnf's binding of the same language (`grammars/bind/ntpd.hbnf`).  Both
fill ntpd's own `struct ntpd_conf` from the same N-sensor config, and each is
checked to have built the same sensors.

<!-- bench:ntpd -->

**100,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 61 ms | 1630 K sensors/s | 100 MB/s | 9.1 MB |
| hbnf binding | 6.14 MB | 60 ms | 1655 K sensors/s | 102 MB/s | 9.2 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 616 ms | 1623 K sensors/s | 101 MB/s | 77.8 MB |
| hbnf binding | 62.39 MB | 395 ms | 2532 K sensors/s | 158 MB/s | 77.8 MB |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.11 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._

<!-- /bench:ntpd -->

### A large parse.y: pfctl

ntpd's grammar is small.  pfctl's `parse.y` is the largest of the nine (6,546 lines), so the
same comparison on it: OpenBSD's `sbin/pfctl/parse.y` at a pinned commit, unmodified, through
byacc, against hbnf's translation of the grammar (`grammars/obconf_pfctl.hbnf`), on a file of
filter rules.  The two do not do the same work: `parse.y` runs its actions and fills a
`struct pf_rule` per rule (handed to a stub of `pfctl_add_rule` that copies and lists it, as
pfctl's does; address and interface lookups are stubs, in `bench/pfctl/stubs.c`); hbnf builds
and keeps a typed tree and runs no semantic code.  Both are checked to have found N rules, and
the yacc side also that the source ports add up.

<!-- bench:pfctl_yacc -->

**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 1.16 s | 87 K rules/s | 8 MB/s | 150.0 MB |
| hbnf pfctl grammar (`--no-compact`, typed tree) | 9.18 MB | 312 ms | 320 K rules/s | 29 MB/s | 448.4 MB |
| hbnf pfctl grammar (compact nodes, the default) | 9.18 MB | 163 ms | 612 K rules/s | 56 MB/s | 148.2 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 11.65 s | 86 K rules/s | 8 MB/s | 1481.9 MB |
| hbnf pfctl grammar (`--no-compact`, typed tree) | 91.86 MB | 3.09 s | 324 K rules/s | 30 MB/s | 4468.3 MB |
| hbnf pfctl grammar (compact nodes, the default) | 91.86 MB | 1.60 s | 625 K rules/s | 57 MB/s | 1468.2 MB |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 7.32 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._

<!-- /bench:pfctl_yacc -->

### Compact nodes on the rest of the corpus

The same change measured on the repository's own corpora, one generator and one grammar, the
old layout (`--no-compact`) against the new default, each corpus's good files parsed many
times over with every tree kept (about 30 MB of input per row):

<!-- bench:corpus -->

| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 180 ms | 187 ms | 0.96x | 270 MB | 265 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 72 ms | 58 ms | 1.25x | 90 MB | 48 MB | 1.88x |
| algol60 | 5 files x 12615 | 30.0 MB | 1775 ms | 1253 ms | 1.42x | 3075 MB | 1886 MB | 1.63x |
| bgpd | 4 files x 20000 | 19.7 MB | 519 ms | 471 ms | 1.10x | 381 MB | 277 MB | 1.38x |
| httpd | 1 files x 20000 | 15.9 MB | 333 ms | 304 ms | 1.09x | 239 MB | 106 MB | 2.25x |
| ntpd | 1 files x 20000 | 6.9 MB | 69 ms | 69 ms | 1.00x | 32 MB | 32 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 955 ms | 618 ms | 1.55x | 812 MB | 306 MB | 2.65x |
| relayd | 2 files x 20000 | 15.2 MB | 252 ms | 224 ms | 1.12x | 86 MB | 61 MB | 1.42x |
| snmpd | 2 files x 20000 | 10.9 MB | 153 ms | 144 ms | 1.06x | 66 MB | 53 MB | 1.25x |
| unwind | 1 files x 20000 | 4.7 MB | 55 ms | 54 ms | 1.01x | 16 MB | 15 MB | 1.08x |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 7.32 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._

<!-- /bench:corpus -->

Memory falls or stays the same everywhere: pfctl, with its many-alternative statements, by about
2.6 times, httpd 2.3, Mustache 1.9, ALGOL 60 1.6, relayd and bgpd 1.4, snmpd 1.3, and JSON, ntpd and
unwind are unchanged.  Speed is better or unchanged except for JSON, which is 4% slower, within the
noise of a shared machine: pfctl is 1.55 times as fast, ALGOL 60 1.4, Mustache 1.25, relayd, bgpd,
httpd and snmpd 6-12% faster, and ntpd and unwind unchanged.

**httpd was 13-28% slower in the first measurement, and finding why changed two things.**  Callgrind
showed the same instruction count and fewer cache misses for the compact layout, so it was not the
extra work; `-Os` made it faster and `-O3` kept it slower, so it was how the code was laid out and
scheduled.  The cost turned out to be in the failed attempts: the compact field was allocated
before its rule was tried, and given back when the rule failed, and httpd's block of 28 options
fails 105 times per file.  Without the give-back the time matched the old layout.  A field is now
parsed into a stack temporary and copied into the arena only when the rule matched, so a failed
attempt costs what it cost before.  The same profile showed 28% of httpd's time in `fail()`, which
compared a failed keyword with the sixteen already recorded for the error message, with `strcmp`,
each time; it now stops once the list is full and says "and more", and compares first letters
before `strcmp`.  That speeds every C parser with a keyword-heavy choice (the old layout's httpd
went from 700 to 540 ms).  A grammar whose
choices are few gains nothing, because there is nothing to compact.

### The same for Rust

The Rust parser had both faults, the second much worse.  Compact nodes are the same change: a
struct-valued field that only some of a choice's alternatives hold is an `Option<Box<T>>`, boxed
when that alternative is taken (and, as Rust returns the node by value, only on success).  The
larger cost was in the errors: every failed alternative built the whole message, counting the
lines from the start of the text and formatting the text of the line, and cloned it, so a parse
was quadratic in the input.  A failure is now only noted (what was expected, at the farthest
place), and the message is made once, when the parse fails.  The messages are the same
characters (`tests/errors.sh` passes in Rust unchanged).  The table has the Rust parser as it
was, with only the errors fixed, and as it is now, on the files the Rust parser reads (the
daemons' scanners written in C are not read by it):

<!-- bench:corpus_rust -->

| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 4622 | 3.0 MB | 1899 ms | 461 ms | 429 ms | 4.4x | 622 MB | 541 MB |
| mustache | 25 files x 8108 | 3.0 MB | 1417 ms | 422 ms | 297 ms | 4.8x | 552 MB | 244 MB |
| algol60 | 5 files x 1261 | 3.0 MB | 8746 ms | 498 ms | 446 ms | 19.6x | 196 MB | 142 MB |
| httpd | 1 files x 3778 | 3.0 MB | 4689 ms | 369 ms | 251 ms | 18.7x | 140 MB | 28 MB |
| relayd | 2 files x 3957 | 3.0 MB | 1373 ms | 187 ms | 149 ms | 9.2x | 108 MB | 44 MB |
| snmpd | 2 files x 5514 | 3.0 MB | 1238 ms | 155 ms | 144 ms | 8.6x | 39 MB | 28 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._

<!-- /bench:corpus_rust -->

The old Rust times (1.2 to 8.5 seconds for 3 MB) were not a Rust problem but this one.

### And for Zig and Ada

Zig had the same fault: every failure built the message, a pass over the text for the line, so a
parse cost more the further into the file it was.  It now notes the failure and builds the
message in `err_out`, when the parse fails, and holds the same fields as `?*T` (compact nodes).
"Time before" is the generator as it was, built from `bench/pre/` by the stage; "lazy errors" is
today's with `--no-compact`.  The time is the process's CPU time:

<!-- bench:corpus_zig -->

| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 3000 | 1.9 MB | 275 ms | 49 ms | 54 ms | 5.1x | 64 MB | 65 MB |
| mustache | 25 files x 3000 | 1.1 MB | 58 ms | 19 ms | 15 ms | 3.8x | 42 MB | 21 MB |
| algol60 | 5 files x 1000 | 2.4 MB | 6282 ms | 88 ms | 82 ms | 76.4x | 73 MB | 52 MB |
| httpd | 1 files x 2000 | 1.6 MB | 1093 ms | 80 ms | 79 ms | 13.8x | 71 MB | 15 MB |
| relayd | 2 files x 2000 | 1.5 MB | 252 ms | 39 ms | 37 ms | 6.7x | 22 MB | 9 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._

<!-- /bench:corpus_zig -->

Almost all of it is the errors again (up to 85 times on ALGOL 60, whose files are longest);
compact nodes cut the memory (httpd 70 to 16 MB) and make Mustache and httpd faster.

**Ada was different: its cost was exceptions, not messages.**  Ada's record fields for other records
were already access values, so there is no merged struct to compact, and its failures were already
noted and rendered once; trimming the strings built per failure made no measurable difference.  A
callgrind profile put three quarters of its instructions in exception unwinding
(`__gnat_personality_v0`, `_Unwind_Find_FDE`): it backtracked by raising `Parse_Error` and catching
it in each alternative, and a GNAT raise costs microseconds.  The generated parser now keeps a
failure as a flag on the parser (`P.Failed`): every call that can fail is followed by a check that
returns up to whoever tries the next way, alternatives jump to the next branch with a `goto`, and
`Parse_Text` raises `Parse_Error` once, with the message, if the parse failed.  The public
interface is unchanged.  "Time before" is the generator as it was (built from `bench/pre/`):

<!-- bench:corpus_ada -->

| corpus | input | parsed | time before (exceptions) | time now | faster | memory |
|---|---|---:|---:|---:|---:|---:|
| json | 26 files x 300 | 0.2 MB | 1070 ms | 79 ms | 13.52x | 23 MB |
| mustache | 25 files x 300 | 0.1 MB | 580 ms | 25 ms | 22.99x | 9 MB |
| httpd | 1 files x 200 | 0.2 MB | 1290 ms | 32 ms | 40.66x | 7 MB |
| relayd | 2 files x 200 | 0.2 MB | 387 ms | 17 ms | 22.20x | 6 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._

<!-- /bench:corpus_ada -->

It is still about ten times slower per byte than Zig on the same files (it builds
`Unbounded_String`s and vectors of accessed records, and runs `Skip_Ws` between every pair of
elements), but no longer hundreds of times.

Read it as it is: **with the default layout hbnf's C parser is level with byacc's on this
grammar (inside the noise), not ahead of it, and it uses about 2.6 times the memory** (a typed
tree of every rule against a 1.4 KB `struct pf_rule` per rule).  The toy-language lead (the
table above) does not carry over to a grammar this size.  With compact nodes (now the default) it is
faster than byacc, by 1.4 to 1.6 times in the runs I made (the host's load varied between them; the table
has the latest), and uses about 0.8 of its memory.

Profiling the first run (gprof, 200,000 rules) found two causes.  **Ordered choice re-parsed**
(a grammar fault): `fromto = from os to | from os | from to | from` parsed `from` three times;
`host` and `hostatom` parsed each address six times; `portval` and `portitem` each port six
times.  Factoring them (`from [ os ] [ to ]`, `hostfrom hostrest`, `address [ ":" port ]`,
`loportval [ portbin hiportval ]`; the language is the same, checked on 211 hand-written rules
against the old grammar and by the daemon, round-trip and compare tests) took the parse from
1.06 s to 0.78 s per 200,000 rules, from 15% behind byacc to level.  **Every node was as big as
all of its alternatives together** (a generator fault): a struct that gathers the fields of a
choice has one field per alternative, so a pfctl statement was a 2,208-byte node and each
`keep state` option a 1,712-byte one, of which one alternative was in use, and every parse
step cleared and copied them.  Compact nodes hold each such field as a pointer, allocated from
the arena only when that alternative is taken (and given back when the attempt fails); it
uses the pointer fields that already break a by-value cycle, so the writer, walkers and
free code needed no change.  That took the parse from 0.78 s to 0.50 s and the memory from
845 MB to 275 MB per 200,000 rules.  Compact nodes are the default in C (`--no-compact` gives the old layout; the generated
types differ: `r.pfrule.action` is `r.pfrule->action`); `tests/compact.sh` checks that every C
round trip passes both ways and that pfctl needs less than half the memory.
What the profile still shows per rule: about 78 failed alternatives and 105 whitespace skips.
"As efficient as yacc" now holds for the toy, ntpd and pfctl on speed, and for pfctl on memory
with compact nodes.

The first run of this comparison found a fault in HyperBNF, not in the harness: a
statement-at-a-time parse freed and re-allocated a 64 KiB arena chunk for every
statement, which on musl cost fourteen times the parse (905 ms against 63 ms
for 100,000 sensors, measured once, before the fix; byacc was 71 ms).  The
arena now keeps one chunk between statements, and the table above is after the
fix.  A benchmark against someone else's parser is also a test of your own.

## HyperBNF and ANTLR

ANTLR v4 is the right comparison, not yacc: it already removes shift/reduce
conflicts, handles left recursion, and reports readable errors. The two part
ways on what they optimize for.

hbnf emits a self-contained single file with no runtime library, where ANTLR
needs its runtime in the target language. hbnf gives a typed tree out of the
box, where ANTLR gives a generic parse tree and you write a visitor or listener
to build your own. HyperBNF's notation is ABNF, so an RFC grammar compiles almost
verbatim, and comments are first-class tokens a grammar can keep and
round-trip; ANTLR's grammar is its own syntax, and its parse tree drops
comments. hbnf's maximal-munch lexer plus
LL(1)-ish grammar parses a large grammar linearly, where ANTLR's ALL(*) explores
at runtime.

The remaining gap is narrow. ALL(*) parses genuinely ambiguous grammars, and
ANTLR runs actions during the parse and lets them steer recognition with
semantic predicates; hbnf is ordered choice, so it is never ambiguous, and its
actions run after the parse and never steer it. Indirect left recursion is a
temporary gap: hbnf reads direct left recursion as a loop, and the standard
elimination algorithm turns indirect into direct before the same loop. The
permanent differences are parse-time semantic feedback and ambiguity, which
hbnf refuses on purpose, plus the ecosystem around ANTLR (grammar libraries,
IDE support, incremental parsing) that hbnf does not aim to replace. hbnf is
a meta-compiler: configuration files are where it started, and the config-file
shape (scanner actions, a parse.y-shaped `parse_config`, id-ref output) is something ANTLR does not address, but
that is where it started and not where it stops.

## HyperBNF and tree-sitter

tree-sitter is the other obvious comparison, and the one most likely to be
proposed as a replacement, so it is worth being exact about. Its rows
are in the table above: the toy language written as a tree-sitter grammar,
generated with tree-sitter 0.27, compiled `gcc -O2`, and run over the same
bytes as every other tool.  Both parses are complete and correct (the script
checks the rule count and a checksum of the ports).

**On the comparison being fair.** tree-sitter has no BNF notation, so the
two notations cannot be compared; what is compared is the *task* — parse
this language, this input, build a usable tree — with each tool's grammar
written idiomatically. Three asymmetries are worth stating. The trees differ:
tree-sitter materialises a CST node per token with byte offsets, hbnf builds
typed structs, and tree-sitter's is the larger object. tree-sitter cannot
turn off the GLR and error-recovery machinery it carries. And the comparison
above is a *cold* parse, which is not what tree-sitter optimises.

So the cold number alone would be unfair, and the incremental one is in the
table too: after a one-byte edit, re-parsing the same file takes <!-- v:ts_edit_100000_ms -->33<!-- /v --> ms,
against <!-- v:hbnf_100000_ms -->18<!-- /v --> ms for hbnf's cold parse.  The reason is structural, and the
honest caveat: the toy is a flat list of N independent rules, so an edit forces
the root's N-child list to be rebuilt and incrementality has almost nothing to
prune.  For deeply nested source code that is edited and re-parsed all day,
which is what tree-sitter is for, the win would be large.  The conclusion is
therefore not a general claim about parsers: **where a document is parsed once
rather than edited and re-parsed — which is what a compiler front end, a
protocol parser or a configuration loader does — tree-sitter's design
advantage does not apply.**

Beyond speed, three structural differences. tree-sitter's output is a generic
CST walked with a cursor and compared by node-type string, where hbnf's
`parse_config()` fills the daemon's own `struct ntpd_conf` byte-identically
to parse.y — reading one field out of the CST took about twenty lines
against `r.from.int_`. tree-sitter refuses to generate on an ambiguity ABNF
considers legal, demanding hand-annotated `prec()` or a `conflicts`
declaration at each one, which is the opposite of pasting an RFC in. And it
cannot ship where this has to: a 16,800-line C runtime, grammars authored in
JavaScript, a Rust CLI to build them, and parse tables that run from 94,000
lines (javascript) to 471,000 (ruby), against 2,466 lines for hbnf's entire
ntpd parser with no runtime at all.

The deeper point is about scanner actions. tree-sitter's external scanner *is* a scanner action,
and a richer one — `create`/`destroy`/`scan`/`serialize`/`deserialize`, a
stateful scanner whose state is snapshotted so an incremental re-parse can
resume — handed a raw cursor (`lookahead`, `advance`, `mark_end`). It leaned
on that hard enough that there is no character-level grammar at all:
tree-sitter's answer to "what is a token" is a regex, or C, never grammar,
and the runtime hardcodes `keyword_capture_token` and a `reserved_words` set
for what a character grammar would say. In the main grammars, bash ships
1,217 lines of hand-written C, ruby 1,110, python 437, javascript 364; only
C and Go escape, being the languages whose tokens are genuinely regular.
Adopting it would mean writing *more* scanner actions, and stateful ones. hbnf is going
the other way: 18 scanner actions left and falling as the character layer absorbs them,
toward a parser with no hand-written scanner, where a scanner action is an optimisation
one may drop rather than the only way to say what a token is.

Where tree-sitter is better: error recovery, which RFCPLAN step 8 borrows
from deliberately. And it is the right tool for the other job — if `pf.conf`
ever wants editor highlighting, that is a tree-sitter grammar, a separate
artifact from the daemon's parser.

The targets point the same way. ANTLR's ten runtimes are Java (the reference),
C#, C++, Python 3, JavaScript, TypeScript, Go, Swift, PHP and Dart, each of
which must be linked. hbnf's four backends are C, Rust, Zig and Ada, each a
self-contained single file. The sets do not overlap today: ANTLR has no C,
Rust, Zig or Ada. hbnf's planned backends are D, Fortran, Free Pascal, Nim,
Odin, Objective-C, ATS and V, then the GC languages Go, Java, JavaScript, C#,
F#, Julia, Common Lisp and newLISP; of those, only Go, Java, JavaScript and C#
also have an ANTLR runtime, and even there hbnf's output stays self-contained.
The difference is the runtime, not the language family: ANTLR's parser links
the ANTLR runtime, and hbnf's links nothing beyond the target language's own
standard library.
