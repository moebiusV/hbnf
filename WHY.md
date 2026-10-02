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
IDE support, incremental parsing) that hbnf does not aim to replace. hbnf's
narrowness is where it wins: the config-file shape (jets, `--conf`, id-ref
output) is something ANTLR does not address.

## hbnf and tree-sitter

tree-sitter is the other obvious comparison, and the one most likely to be
proposed as a replacement, so it is worth being exact about. Measured
2026-10-01: the §6 toy grammar written twice — once in hbnf, once as a
tree-sitter grammar accepting the same language — generated, compiled `gcc
-O2`, and run over byte-identical input, best of five.

| input | hbnf | tree-sitter 0.27 |
|---|---|---|
| 7.68 MB | **48 ms**, 21 MB RSS | 502 ms, 117 MB |
| 76.9 MB | **489 ms**, 202 MB | 5159 ms, 1155 MB |

Both parses complete and correct (tree-sitter: 100,000 and 1,000,000
children, no error). About 159 MB/s against about 15 MB/s.

**On the comparison being fair.** tree-sitter has no BNF notation, so the
two notations cannot be compared; what is compared is the *task* — parse
this language, this input, build a usable tree — with each tool's grammar
written idiomatically. Three asymmetries are worth stating. The trees differ:
tree-sitter materialises a CST node per token with byte offsets, hbnf builds
typed structs, and tree-sitter's is the larger object. tree-sitter cannot
turn off the GLR and error-recovery machinery it carries. And the comparison
above is a *cold* parse, which is not what tree-sitter optimises.

So the cold number alone would be unfair, and the incremental one was
measured too: after a one-byte edit, re-parsing the 7.68 MB file takes **87
ms** — still slower than hbnf's 48 ms cold parse. The reason is structural,
and the honest caveat: a config file is a flat list of N independent rules,
so an edit forces the root's N-child list to be rebuilt and incrementality
has almost nothing to prune. For deeply nested source code, which is what
tree-sitter is for, the win would be large. The conclusion is therefore
narrow and not a general claim: **for the shape of input hbnf targets, a
flat list parsed once, tree-sitter's design advantage does not apply.**

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

The deeper point is about jets. tree-sitter's external scanner *is* a jet,
and a richer one — `create`/`destroy`/`scan`/`serialize`/`deserialize`, a
stateful scanner whose state is snapshotted so an incremental re-parse can
resume — handed a raw cursor (`lookahead`, `advance`, `mark_end`). It leaned
on that hard enough that there is no character-level grammar at all:
tree-sitter's answer to "what is a token" is a regex, or C, never grammar,
and the runtime hardcodes `keyword_capture_token` and a `reserved_words` set
for what a character grammar would say. In the main grammars, bash ships
1,217 lines of hand-written C, ruby 1,110, python 437, javascript 364; only
C and Go escape, being the languages whose tokens are genuinely regular.
Adopting it would mean writing *more* jets, and stateful ones. hbnf is going
the other way: 18 jets left and falling as the character layer absorbs them,
toward a parser with no hand-written scanner, where a jet is an optimisation
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
