# The grammar, and why

For the reader who already reads the RFCs, hbnf's grammar is meant to be
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

## Where hbnf lands

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

**How much grammar.**  The same language in the published notation and in hbnf, with
comments, blank lines and hbnf's directive lines left out of both
(`bench/notation.sh`).  A symbol is a whitespace-separated word.  Mustache is not
here because it has no published grammar to compare with.

<!-- bench:notation -->
| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | hbnf (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | hbnf (`corpus/json`) | 14 | 14 | 129 | 556 |
| | **saved** | **53%** | **69%** | **33%** | **41%** |
<!-- /bench:notation -->

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
| hbnf (C backend) | 7.68 MB | 24 ms | 4.1 M rules/s | 318 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 68 ms | 1.5 M rules/s | 112 MB/s | 23 MB |
| bison + flex | 7.68 MB | 63 ms | 1.6 M rules/s | 121 MB/s | 23 MB |
| peg/leg | 7.68 MB | 57 ms | 1.7 M rules/s | 134 MB/s | 30 MB |
| tree-sitter 0.27.1 | 7.68 MB | 227 ms | 0.4 M rules/s | 34 MB/s | 63 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 34 ms | | | 81 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 223 ms | 0.4 M rules/s | 34 MB/s | 207 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 123 ms | 0.8 M rules/s | 62 MB/s | 582 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 267 ms | 0.4 M rules/s | 29 MB/s | 300 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 242 ms | 4.1 M rules/s | 318 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 685 ms | 1.5 M rules/s | 112 MB/s | 224 MB |
| bison + flex | 76.86 MB | 633 ms | 1.6 M rules/s | 121 MB/s | 224 MB |
| peg/leg | 76.86 MB | 575 ms | 1.7 M rules/s | 134 MB/s | 294 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2294 ms | 0.4 M rules/s | 34 MB/s | 620 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 360 ms | | | 804 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1244 ms | 0.8 M rules/s | 62 MB/s | 1395 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1651 ms | 0.6 M rules/s | 47 MB/s | 3011 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 2311 ms | 0.4 M rules/s | 33 MB/s | 2491 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
<!-- /bench:toy -->

At 100,000 rules hbnf's generated C parser takes <!-- v:hbnf_100000_ms -->24<!-- /v --> ms.  byacc with flex
takes <!-- v:byacc_100000_ms -->68<!-- /v --> ms (<!-- v:ratio_byacc_100000 -->2.8<!-- /v --> times as long), peg/leg <!-- v:ratio_peg_100000 -->2.4<!-- /v --> times, tree-sitter
<!-- v:ratio_ts_100000 -->9.5<!-- /v --> times, and ANTLR <!-- v:ratio_antlr_cold_100000 -->9.3<!-- /v --> times in a fresh JVM (<!-- v:ratio_antlr_warm_100000 -->5.1<!-- /v --> times once
the JVM is warm).  At 1,000,000 rules the ratios hold (byacc <!-- v:ratio_byacc_1000000 -->2.8<!-- /v -->, tree-sitter
<!-- v:ratio_ts_1000000 -->9.5<!-- /v -->), so every tool's cost is linear and the table is not a small-input
effect.  Peak memory follows the same order: <!-- v:hbnf_100000_rss_mb -->21<!-- /v --> MB for hbnf, <!-- v:byacc_100000_rss_mb -->23<!-- /v --> MB for
byacc, <!-- v:ts_100000_rss_mb -->63<!-- /v --> MB for tree-sitter.

Three things this does not say.  The trees differ: hbnf builds typed structs
whose strings are slices of the input, the yacc and PEG parsers copy each
string, tree-sitter builds a node per token, and ANTLR's actions-only rows
build no tree at all.  The toy is the smallest realistic shape; the full pfctl
grammar, with its 35-way option alternation, takes <!-- v:pfctl_100000_ms -->298<!-- /v --> ms and <!-- v:pfctl_100000_rss_mb -->133<!-- /v --> MB for
100,000 rules, about <!-- v:pfctl_vs_toy_time -->12<!-- /v --> times the toy per rule, and that is the number to
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
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 111 ms | 905 K sensors/s | 56 MB/s | 7.2 MB |
| hbnf binding (`--conf`) | 6.14 MB | 115 ms | 867 K sensors/s | 53 MB/s | 7.3 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 1.07 s | 931 K sensors/s | 58 MB/s | 68.8 MB |
| hbnf binding (`--conf`) | 62.39 MB | 1.16 s | 862 K sensors/s | 54 MB/s | 69.0 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
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
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 674 ms | 148 K rules/s | 14 MB/s | 173.1 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 714 ms | 140 K rules/s | 13 MB/s | 457.1 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 482 ms | 208 K rules/s | 19 MB/s | 132.6 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 6.75 s | 148 K rules/s | 14 MB/s | 1723.7 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 7.28 s | 137 K rules/s | 13 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 4.86 s | 206 K rules/s | 19 MB/s | 1322.3 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
<!-- /bench:pfctl_yacc -->

### Compact nodes on the rest of the corpus

The same change measured on the repository's own corpora, one generator and one grammar, the
old layout (`--no-compact`) against the new default, each corpus's good files parsed many
times over with every tree kept (about 30 MB of input per row):

<!-- bench:corpus -->
| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 939 ms | 939 ms | 1.00x | 308 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 446 ms | 298 ms | 1.50x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 4004 ms | 3699 ms | 1.08x | 975 MB | 662 MB | 1.47x |
| bgpd | 4 files x 20000 | 19.7 MB | 1336 ms | 1269 ms | 1.05x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 711 ms | 818 ms | 0.87x | 221 MB | 110 MB | 2.01x |
| ntpd | 1 files x 20000 | 6.9 MB | 99 ms | 100 ms | 1.00x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 1922 ms | 1315 ms | 1.46x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 334 ms | 320 ms | 1.05x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 212 ms | 199 ms | 1.06x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 70 ms | 70 ms | 0.99x | 18 MB | 16 MB | 1.15x |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
<!-- /bench:corpus -->

Memory falls or stays the same everywhere; pfctl, with its many-alternative statements, falls
about 4 times, httpd and Mustache about half.  Speed is mixed, not better across the board: ALGOL
60, pfctl, Mustache and bgpd are 6-60% faster, ntpd, unwind and JSON are unchanged, and
**httpd is 13-28% slower** (in every run of this container, built against musl; the same
code on the host's glibc was within noise, so the cause may be the allocator or `memset`, and I
have not found it).  A grammar whose
choices are few gains nothing, because there is nothing to compact.

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

The first run of this comparison found a fault in hbnf, not in the harness: a
statement-at-a-time parse freed and re-allocated a 64 KiB arena chunk for every
statement, which on musl cost fourteen times the parse (905 ms against 63 ms
for 100,000 sensors, measured once, before the fix; byacc was 71 ms).  The
arena now keeps one chunk between statements, and the table above is after the
fix.  A benchmark against someone else's parser is also a test of your own.

## hbnf and ANTLR

ANTLR v4 is the right comparison, not yacc: it already removes shift/reduce
conflicts, handles left recursion, and reports readable errors. The two part
ways on what they optimize for.

hbnf emits a self-contained single file with no runtime library, where ANTLR
needs its runtime in the target language. hbnf gives a typed tree out of the
box, where ANTLR gives a generic parse tree and you write a visitor or listener
to build your own. hbnf's notation is ABNF, so an RFC grammar compiles almost
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
shape (scanner actions, `--conf`, id-ref output) is something ANTLR does not address, but
that is where it started and not where it stops.

## hbnf and tree-sitter

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
table too: after a one-byte edit, re-parsing the same file takes <!-- v:ts_edit_100000_ms -->34<!-- /v --> ms,
against <!-- v:hbnf_100000_ms -->24<!-- /v --> ms for hbnf's cold parse.  The reason is structural, and the
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
