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

**Pretty-printing.** A parsed tree renders back to canonical text and
round-trips exactly: a decimal keeps its literal, a string is re-quoted with
the escape set. Comments are preserved and come back out in the right places
when the source is re-emitted, and printing is idempotent.

## hbnf and ANTLR

ANTLR v4 is the right comparison, not yacc: it already removes shift/reduce
conflicts, handles left recursion, and reports readable errors. The two part
ways on what they optimize for.

hbnf emits a self-contained single file with no runtime library, where ANTLR
needs its runtime in the target language. hbnf gives a typed tree out of the
box, where ANTLR gives a generic parse tree and you write a visitor or listener
to build your own. hbnf's notation is ABNF, so an RFC grammar compiles almost
verbatim, and comments are preserved and round-tripped; ANTLR's grammar is its
own syntax, and its parse tree drops comments. hbnf's maximal-munch lexer plus
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
