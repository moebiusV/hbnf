# HBNF: Return of the Metacompiler

*A short history of the parser generator.*

© 2026 David Walther · 1 October 2026

Named here, by year of first contribution: Emil Post (1943) · Noam Chomsky (1956) · John Backus (1959) · Peter Naur (1960) · John McCarthy (1960) · Edgar Irons (1961) · R. A. Brooker (1963) · D. Morris (1963) · Christopher Strachey (1963) · Donald Knuth (1964) · Dewey Val Schorre (1964) · Robert McClure (1965) · Martin Richards (1966) · Douglas McIlroy (1968) · Ken Thompson (1969) · Stephen Johnson (1971) · Al Aho (1971) · Dennis Ritchie (1972) · David Crocker (1982) · Robert Corbett (1985) · Richard Stallman (1987) · Michael Tiemann (1987) · Leonard Tower (1987) · Paul Rubin (1987) · John Gilmore (1987) · Keith Bostic (1987) · Mike Karels (1987) · Terence Parr (1988) · Isaac Mozeson (1989) · Jeff Fox (1996) · Bryan Ford (2002) · Anders Magnusson (2002) · Joseph Myers (2004) · Max Brunsfeld (2014).

A parser generator reads a grammar — a precise description of what a language
may say — and writes the program that recognizes exactly that. It matters
because every compiler, every config-file reader, every network protocol has to
parse text, and a parser written by hand is slow, error-prone, and thrown away
whenever the language grows.

Before any of this was engineering, it was linguistics. Noam Chomsky asked how
a person produces and understands sentences never spoken before, and answered:
with a grammar — a finite set of rules that generates the infinite set of legal
sentences. Generative grammar turned language from examples into a formal
object. It gave computing the Chomsky hierarchy, a ladder from regular to
context-free to context-sensitive, and every parser in this history sits on one
rung of that ladder, almost always the context-free one. The idea that a
grammar is a machine for generating strings is Chomsky's; everything that
follows is the story of people building that machine.

A grammar has two readers: the person and the machine. Every system in this
history leans toward one of them — easier for a person to read, or easier for a
machine to turn into code. The aim underneath never changes: get the writer's
intention into the machine without losing it, and make plain to the next reader
what the machine was meant to do. One is a person talking to a machine. The
other is a person talking to a person.

A language used to be described the way a recipe is: prose and examples. Two
implementors reading the same manual could ship two different languages. That
stopped in 1959, when John Backus needed to describe ALGOL 58 well enough that
implementations would not silently diverge. He took the idea of production
rules from Emil Post and published the syntax as metalinguistic formulas. The
notation was rough — a colon, the word "or", brackets that did not quite close —
and it said nothing about meaning, only about form. It was still the break: a
finite set of rewrite rules that generated exactly the legal strings.

Peter Naur made it usable. Editing the ALGOL 60 Report, he kept Backus's idea
and fixed the marks: angle brackets for non-terminals, `::=` for definition,
`|` for choice. Backus had written a paper; Naur had written the reference
grammar of a real language, with recursion and block structure inside the same
formalism. Donald Knuth insisted it be called Backus–Naur Form and not Backus
Normal Form, because it is not a normal form. The name stuck, and the notation
became the default way to write a language down.

*Sources:* Chomsky, *Syntactic Structures* (1957); Post, "Formal reductions of the general combinatorial decision problem" (1943); Backus, "The syntax and semantics of the proposed international algebraic language" (1959); Naur (ed.), "Revised Report on the Algorithmic Language ALGOL 60" (1963); [Knuth, "On the translation of languages from left to right" (1965)](https://doi.org/10.1016/S0019-9958(65)90426-2).

## The first compiler compilers

BNF was meant to be read, and it turned out to be nearly executable. Within a
year of the ALGOL 60 Report, Edgar Irons published *A Syntax-Directed Compiler
for ALGOL 60* (1961): the parser was driven straight off the BNF Naur had just
written, the grammar supplying the recognition tables as a program supplies its
data. The notation was written for people; it happened to run.

The name "compiler compiler" came next, from R. A. Brooker and D. Morris at
Manchester (1963). Their Compiler Compiler read a phrase-structure description
of a language — BNF with the semantics hung off the rules — and generated a
machine-code compiler for the Atlas. It was a working tool, not a toy; it built
compilers for Algol and Atlas Autocode.

A program describing itself came earlier still. John McCarthy's Lisp paper
(1960) defined the language with a metacircular evaluator — `eval` written in
Lisp, a self-interpreter — four years before META II. McCarthy meant it "for
reading, not for computing"; Steve Russell had to run it for it to become a
language.

Running it is where the half-page stops being a definition. Kragen Sitaker,
who went on to write StoneKnifeForth, translated the Lisp 1.5 metacircular
interpreter into a low-level language in 2007 and found that about half the
code went to things the metacircular interpreter says nothing about: memory
management, argument evaluation order, laziness versus strictness, the rest of
control flow, the representation and comparison of atoms, the representation
of pairs, parsing, type checking and type testing, recursive call and return,
tail calls, and lexical versus dynamic scoping. The gap is not an oversight in
McCarthy's `eval`; it is what self-definition is. Reynolds, revisiting his own
definitional interpreters in 1998, put it plainly: a metacircular interpreter
"is not really a definition, since it is trivial when the defining language is
understood, and otherwise it is ambiguous" — his Interpreters I and II say
nothing about order of application. He quotes Jim Morris going further: "The
activity of defining features in terms of themselves is highly suspect,
especially when they are as subtle as functional objects. It is a fad that
should be debunked." Reynolds then grants what the thing is good for: he
remembers McCarthy's definition as a great help when he first learned Lisp,
"but it was not the sole support of my understanding."

Sitaker's conclusion is the one that bears on a compiler compiler: a
metacircular *compiler* forces you to confront that complexity, because it has
to emit the memory management and the calling convention rather than inherit
them, and it is self-sustaining in a way an interpreter is not — once it runs,
features added to the language are available to the compiler itself. That is
the line this story follows from here: not a description that reads well, but
one that has to produce the code.

Then the metacompilers. Dewey Val Schorre's META II (1964) wrote a language as
"syntax equations" in the shape of BNF and compiled each equation to the
subroutine that recognized it; META II compiled itself, the first documented
metacompiler.

Its notation is worth reading closely, because most of it is still in use.
Schorre dropped Naur's angle brackets and `::=` for ordinary algebraic
punctuation — a bare `=` between the name and its definition, `/` between
alternatives, each equation closed by a terminator — and added the one
operator BNF lacked. A top-down parser cannot take BNF's left-recursive
`<list> ::= <item> | <list> <item>` without running off its own stack, so
META II wrote repetition out as an operator instead: `$` for "zero or
more", with `( )` to group what it repeated. Four built-in recognizers
covered the token level — `.ID`, `.NUMBER`, `.STRING`, and `.EMPTY` for a
production that matches nothing — and `.OUT('…')` emitted a line of target
assembly from inside the equation, with `*` standing for whatever token had
just matched. The whole of an expression translator is one line:

    EXPR = TERM $( '+' TERM .OUT('ADD') / '-' TERM .OUT('SUB') );

Read that and you are reading EBNF a decade early: the `=`, the explicit
repetition operator in place of recursion, the parenthesised group. Wirth's
EBNF kept the first two and spelled the repetition `{ }`; ABNF kept the `=`
and the `/`, and wrote repetition as a prefix count. The inheritance is the
*decision* rather than the character — that a grammar for a top-down parser
says "repeat this" instead of naming itself again — and every notation since
has made it, hbnf included.

What did not survive into the parser generators is the part that made META
II a compiler-compiler rather than one of them: output directives living
inside the syntax. Yacc put its actions at the end of a production, ANTLR
and its successors built a tree and walked it afterwards, and hbnf did the
same — a `%action{ }` block had to end its rule, so there was nowhere to put
`.OUT` where META II puts it. That is being repaired rather than admired:
the block positions are a notation decision in `RFCPLAN.md` step 12, and
`%emit{ }` — the generative sibling of `%scan{ }` and `%action{ }` — is the
`.OUT` directive sixty years on, one level up, writing a target language
instead of one machine's assembly. Schorre's loop closed because the
directives were in the grammar. Whether hbnf's closes depends on the same
thing.

Robert McClure's TMG (1965) did the same, at Texas Instruments; McIlroy
ported it to Unix, and Ken Thompson used it around 1970 to write B — the
language C grew out of — in place of the FORTRAN compiler he had set out to
build.

None of them became the way compilers were written. Each was a demonstration
tied to one machine, with a notation of its own and no settled algorithm
underneath: the grammar drove the parser, but how was still open. They proved
the idea. What was missing was a reliable way to do it.

*Sources:* [McCarthy, "Recursive Functions of Symbolic Expressions and Their Computation by Machine" (1960)](https://doi.org/10.1145/367177.367199) · [Sitaker, "A metacircular Lisp interpreter in a low-level language" (kragen-hacks, September 2007)](http://lists.canonical.org/pipermail/kragen-hacks/2007-September/000464.html) · [Reynolds, "Definitional Interpreters Revisited", *Higher-Order and Symbolic Computation* 11, 355–361 (1998)](http://www.brics.dk/~hosc/local/HOSC-11-4-pp355-361.pdf) · [Irons, "A Syntax-Directed Compiler for ALGOL 60" (1961)](https://doi.org/10.1145/366062.366083) · [Brooker, MacCallum, Morris & Rohl, "The Compiler Compiler" (1963)](https://curation.cs.manchester.ac.uk/atlas/docs/ccPaperDL.pdf) · [Schorre, "META II: A Syntax-Oriented Compiler Writing Language", *Proc. ACM SYMSAM* (1964)](https://dl.acm.org/doi/10.1145/800257.808896) ([scan](https://ibm-1401.info/Meta-II-schorre.pdf)) · McClure, TMG (1965).

## The machine: Yacc

Yacc did not invent the compiler compiler; it found the algorithm that made one
stick. The decade of attempts before it had proved a grammar could drive a
parser, but each was a machine-specific experiment, and none had answered how
to turn an arbitrary grammar into a correct parser on its own.

Stephen Johnson answered it. At Bell Labs in the early 1970s he wanted
to add an exclusive-or operator to the B compiler and found the hand-written
parser impossible to change cleanly. Al Aho pointed him at Knuth's LR parsing
papers, and Yacc was the result. A Yacc grammar is BNF plus C code that runs
when a rule matches; the tool compiles the grammar into a shift-reduce
automaton. The change was in who had to understand the parser. Before Yacc, a
parser was an expert's handwritten artifact. After Yacc, a grammar was a text
file, and the machine did the hard part.

Yacc chose LALR(1), the compromise between canonical LR(1) — exact but
explosive — and SLR(1) — small but too weak. Canonical LR(1) splits states by
lookahead and blows up on a language the size of C; SLR(1) uses a global follow
set and accepts reductions that are not legal in context. LALR(1) builds the
LR(1) machine and merges the states that share a core, keeping the state count
of LR(0) and nearly all the power of LR(1). It fit in 1970s memory, and it
handled C, B, and Pascal.

What it could not handle was ambiguity. Yacc turned ambiguity into a diagnostic
— shift/reduce and reduce/reduce conflicts — and gave the grammar writer tools
to resolve it: shift-on-conflict for the dangling else, `%left`/`%right`/
`%nonassoc` for precedence. A Yacc grammar for C needed a feedback hack from
the symbol table, because a typedef name and an identifier are the same token
until they are not. The hack worked. It was the cost of the machine, and it
stayed hidden in the grammar file for thirty years.

*Sources:* [Johnson, "Yacc: Yet Another Compiler-Compiler" (1975), Bell Labs CSTR 32](https://www.cs.utexas.edu/~novak/yaccpaper.htm) · [Knuth, "On the translation of languages from left to right" (1965)](https://doi.org/10.1016/S0019-9958(65)90426-2) · [Aho & Johnson, "LR Parsing" (1974)](https://doi.org/10.1145/356616.356620).

## The protocol metalanguage: ABNF

Meanwhile the people writing network standards needed something else. RFC 822
(1982), David Crocker's specification of ARPA Internet mail, was not written
for compiler authors. It was written for people who had to say, in plain ASCII,
exactly which bytes a header may contain. So it dropped the angle brackets,
changed `::=` to `=`, changed `|` to `/`, and let a literal be a quoted string
or a byte value. It specified a language, not a parser. There were no actions,
no conflict tables, no commitment to LL or LR.

Formal grammars reached ordinary people through this door. BNF and Yacc were
tools for a priesthood of compiler writers. RFC 822 was a tool for anyone who
had to implement a mail client, and in the 1980s that meant nearly everyone who
wrote software. A network engineer who had never heard of Chomsky could still
read a rule and know what it meant. Without the RFC series, most of those
people would never have seen a formal grammar at all.

It was good enough that for fifteen years every other RFC cited "the BNF in
RFC 822" instead of writing its own. That citation habit produced ABNF. RFC
2234 (1997) extracted the notation and made it a standard; RFC 5234 (2008) is
the current form. ABNF kept the looseness on purpose: a rule names its
alternatives with `/`, repetition is explicit (`1*DIGIT`, `*WSP`), and the core
rules (`ALPHA`, `DIGIT`, `CRLF`) ship with the spec. Ambiguity is legal. There
is no generated automaton. ABNF exists so two protocol authors cannot silently
disagree about the bytes on the wire.

*Sources:* [RFC 822 (Crocker, 1982)](https://www.rfc-editor.org/rfc/rfc822) · [RFC 2234 (1997)](https://www.rfc-editor.org/rfc/rfc2234) · [RFC 5234 (2008)](https://www.rfc-editor.org/rfc/rfc5234).

## The return to top-down: ANTLR

Yacc won because it was easier than hand-writing a parser. It lost for the same
reason. The shift-reduce automaton is fast, but when it rejects a grammar it
tells you there is a conflict, not why, and you cannot step through the state
machine it generated.

Terence Parr went the other way. ANTLR (1988–90) generated the recursive-descent
parser a human would have written, top-down, with the lexer and parser in one
grammar. Where finite lookahead could not decide, it added predicates and
backtracking — "try this, and if it fails try that" — instead of forcing the
grammar to be LALR(1). Left recursion still had to be rewritten, and backtracking
could go exponential. Those were the price of a parser a person could debug.

*Sources:* [Parr & Quong, "ANTLR: A Predicated-LL(k) Parser Generator" (1995)](https://doi.org/10.1002/spe.4380250705).

## The compilers: pcc, GCC, and C++

The language those compilers compiled had the same parent. C reaches ALGOL 60
through a chain of simplifications — Christopher Strachey's CPL, Martin
Richards's BCPL, Ken Thompson's B, and finally Ritchie's C — the curly-brace
line that kept ALGOL's block structure and dropped everything else. What C took
from ALGOL 68, Ritchie said, was the scheme of type composition and its names:
`int`, `char`, `long`, `short`, `union`, `struct` and `void` are all ALGOL 68's,
the cast is named after ALGOL 68's, and the compound-assignment operators came
the same way, through Douglas McIlroy's TMG. The library borrowed too: ALGOL 68's
formatted output was already `printf`, and C kept the name and the idea of a
format string — though the `%` directives themselves came from BCPL's `writef`,
which had them in 1966. So the C grammar Stallman later fed to Bison was, in its
bones, an ALGOL grammar.

Johnson's own compiler carried the machine into production. pcc shipped with
Seventh Edition Unix in 1979, moved to the VAX through 32V, and became the
compiler that let C leave the PDP-11. For a decade nearly every serious C
compiler was pcc or a descendant of it.

Then came GCC. Richard Stallman wrote the C grammar — copyright 1987, GCC 1.0
shipped 22 March 1987 — and fed it to Bison rather than Johnson's Yacc. GCC 1.0
credits Stallman as author, Leonard Tower for parts of the parser and the RTL,
and Paul Rubin for most of the preprocessor. Bison itself was a half-breed:
Stallman wrote its C skeleton, Robert Corbett its LALR engine from his Berkeley
Yacc. Michael Tiemann wrote the C++ grammar for g++, the same kind of grammar,
and that one became the standing lesson in what the machine could not do.

GCC pushed pcc out. John Gilmore did the work in 1987–88, compiling the whole
BSD tree with the VAX GCC so CSRG could drop pcc; Keith Bostic and Mike Karels
endorsed it, for ANSI C, better code, and a way out from under the AT&T
copyright. By 1994 pcc was out of the BSD line and unmaintained.

Then GCC climbed off the machine. The C++ front end dropped its Bison grammar
for hand-written recursive descent in 2004; Joseph Myers wrote the C replacement
for GCC 4.1 in 2006, the way Ritchie had written the original — shift and reduce
became calls and returns, and the typedef hack became a real symbol table. Clang,
when it came, never used a generator at all.

The one compiler that kept Yacc was pcc. Anders Magnusson revived it in 2002
from the opened 32V sources, half the front end and most of the back end
rewritten. It still lives today, still driven by a Yacc grammar, and it crawls
while GCC and LLVM, which do not use Yacc or Bison, are the compilers the world
develops. The machine was right for 1975. It is why the work is hard now.

*Sources:* [Ritchie, "The Development of the C Language" (1993)](https://www.bell-labs.com/usr/dmr/www/chist.html); Johnson, pcc (1979); Stallman, GCC 1.0 (1987); Corbett, Berkeley Yacc (1985); Tiemann, g++ (1987).

## Ordered recognition: PEG

Bryan Ford asked a different question. Context-free grammars were built to
model natural language, where ambiguity is a feature. For a programming
language it is a nuisance, and the entire apparatus — LR conflicts, scanner
hacks, the lexer/parser split — exists to beat it back down.

A PEG (Ford, 2002–04) answers by changing what alternation means. In a CFG,
`A | B` says both are possible and a conflict is an error. In a PEG, `/` is
ordered choice: try `A`, and if it matches, `B` is never considered. Ambiguity
becomes impossible because the order of the text picks the winner. The grammar
is scannerless — tokens and structure live in one set of rules — and memoizing
every `(rule, position)` pair gives linear time. Ford was explicit that he was
rehabilitating a 1970 recognition scheme, not inventing one. The differences
that bite are left recursion and the greed of ordered choice.

*Sources:* [Ford, "Parsing Expression Grammars: A Recognition-Based Syntactic Foundation" (2004)](https://bford.info/pub/lang/peg.pdf).

## The incremental tree: Tree-sitter

The last turn was not about compilers at all. Max Brunsfeld built Tree-sitter
(2014–18) for the editor: a syntax tree that updates from an edit instead of
re-parsing the whole file, and that still returns something when the buffer is
briefly illegal. It uses generalized LR, keeping a stack of stacks so local
ambiguity can be represented, and writes ERROR and MISSING nodes into the tree
rather than failing. The grammar is a JavaScript DSL that compiles to C. Atom
is gone; Tree-sitter is now the usual answer whenever a tool needs a real
syntax tree for a language it does not itself compile.

*Sources:* [Brunsfeld, "Tree-sitter: A New Parsing System for Programming Tools" (2018)](https://www.thestrangeloop.com/2018/treesitter---a-new-parsing-system-for-programming-tools.html).

The thread through all of it: Backus and Naur gave a generative notation,
Johnson mechanized the LR subset of it, Crocker loosened the notation for
protocol writers, Parr and then Myers walked production parsers back to
debuggable top-down code, Ford replaced generative choice with ordered
recognition, and Brunsfeld optimized the tree for a buffer that is never
finished.

It is a pendulum between the two readers, each swing trading one reader's ease
for the other's.

## HBNF

HBNF starts from where that thread left off and picks a side. Its bet is that
the notation worth compiling is the one the RFCs already use — ABNF — and that
a grammar should be documentation first and a parser second. The same file that
explains a language to a reader compiles to a parser and a typed tree in C,
Rust, Zig, or Ada, self-contained, with no runtime library.

It keeps the best of each system and dodges the worst, in the way Jeff Fox
taught at UltraForth (may he rest in peace): do not solve the hard problem,
remove what makes it hard. Ordered choice leaves no shift/reduce conflict to
resolve. Left recursion read as a loop leaves nothing to rewrite. A shadowed
alternative refused up front leaves no ambiguity to stumble on at runtime. Each
system's pain is not fought; it is not built in.

**Where it succeeds.** An RFC grammar compiles nearly verbatim: `=`, `|`, `/`,
`*`, `1*`, `n*m`, `[ ]`, and the core character classes all mean what an RFC
reader already expects. Character-level rules compile to scanners — `int = 1*DIGIT`,
`comment = "#" *comment_char` — so there is no separate lexer grammar and no
regex. Direct left recursion is read as a loop, not rejected. Ordered choice
keeps conflicts impossible, and a shadowed alternative is refused at schema time
with a diagnostic rather than failing at runtime. The tree is typed from the
shape of the rule — enum, scalar, list, struct — with no visitor to write. And
HBNF makes round-tripping easy: comments are first-class tokens, not
whitespace, and a value written `0xFF` comes back as `0xFF`, not 255, so a
grammar that wants it — obconf does — hands the file back unchanged, and
pretty-printing and debug printouts become simple and pleasant. A parse failure
is a line, a column, and a caret under the token that was expected.

The literal syntax is C's on purpose: a string is `"…"`, a character `'a'`, a
code point `%x21` or `%d33`, an escape `\n`. The reader already knows these
spellings, and a notation should astonish no one — every mark it invents is one
more thing to learn before the grammar is readable. The choice is not cosmetic.
At the root a token is a sequence of bits, and nothing else; `%x21` and `"!"`
name the same byte, so a grammar can reach straight down to the bytes it
describes instead of floating above them in a lexer's abstractions. Human
readability and machine exactness meet there: spell the bits the way a person
already spells them, and keep the design honest about what is underneath.

**Where it could do better.** It has no incremental parse; an edit means parsing
the file again. It has no error recovery; bad input fails instead of producing a
broken tree. Non-keyword-led alternations get no kind discriminant in the C tree,
so a consumer must infer which branch matched. The `--conf` drop-in for parse.y
replacement is C-only; the other backends warn and parse the whole file. And the
grammar must be LL(1)-ish under maximal munch — it will not decide an ambiguous
branch by looking arbitrarily far ahead.

**Where it will not.** Two things are off the table, and they are the same
thing. Incremental, error-recovering parsing is Tree-sitter's entire reason for
existing, and it requires a generalized-LR engine with a stack of stacks. HBNF's
design is ordered choice plus maximal munch, the opposite trade; adding GLR
would mean discarding the design. And HBNF will not handle genuinely ambiguous
grammars, because that is not a missing feature to add later — it is the thing
the design refuses on purpose. ALL(*) and GLR exist for the languages that need
them. HBNF exists for the ones that do not, and for the person who wants the
grammar and the parser to be the same document.

Judged on that single aim — one document that serves both the person and the
machine — the others all pick a side. BNF and ABNF are for people; Yacc and
Tree-sitter are for machines; ANTLR and PEG generate code but drop the writer's
comments and exact spellings. HBNF tries to be both at once, and the round trip
a grammar can build is the proof: the text a person reads is what the machine
runs, and the machine hands it back unchanged. The writer's intention arrives
whole, and no earlier tool managed that.

The line ends where it began, and it ends against Chomsky. Generative grammar
started as a claim about the mind: a language is a set of rules that produces
its sentences. That method drove the early years — BNF and Yacc both generate.
But the useful work drifted the other way. ABNF defines a language without an
automaton; PEG replaces generation with ordered recognition; the grammar stopped
producing strings and started describing the ones that exist. Generation lost.
Description won.

Isaac Mozeson would be pleased. Chomsky was cruel to him — an Orthodox Jewish
linguist who described the actual words, tracing every tongue back to a single
source, and who saw language as the thing that brings people together — and
Chomsky dismissed him as he dismissed everyone who disagreed. The field came
around to his side anyway. The descriptive method won, and it won pointing the
way he pointed: a grammar that names what is there can join a person to a
machine as readily as it joins one person to another. Chomsky was nasty, and
Chomsky was wrong. Bringing people and machines together through language is
the more useful end.

An intelligence that must read what people wrote and act on it needs exactly
that bridge — a text a person can read, a machine can run, an intention carried
whole. HBNF was not written for AI. That is what will make it useful to AI.

*Sources:* the [hbnf repository](https://github.com/moebiusV/hbnf), and [RFC 5234](https://www.rfc-editor.org/rfc/rfc5234) for the ABNF it compiles.

## Appendix — Incremental Parsing without Giving Up the Grammar

1. Tree-sitter's two real wins are incremental reparse and error recovery. Both
rest on a concrete tree whose nodes carry byte spans: an edit reuses every
subtree it does not touch, and a broken file still yields a tree with ERROR and
MISSING nodes instead of nothing.

2. Tree-sitter needs generalized LR for this because it must preserve ambiguity
across an edit. HBNF has no ambiguity to preserve, because it refuses it up
front. A deterministic parser has exactly one result at a position, so an edit
invalidates only the nodes whose span it touches; the rest is reused as-is, and
re-parsing the touched range is guaranteed to match what a full parse would
have produced. Incremental parsing falls out of determinism, not out of a stack
of stacks.

3. Recovery is the same trick in the other direction. Where the parser fails it
does not fork; it writes an ERROR node, skips to the next synchronizing token,
resumes, and writes MISSING where a token was expected. The valid regions stay
correct because the core parser never changed. Recovery is a wrapper, not a
replacement.

4. The grammar stays the document. The extended ABNF — `=`, `|`, `/`, `*`,
`1*`, `n*m`, `[ ]`, the character classes, the `%scan{}` jets, `whitespace ws`
— remains the single source, read by the person and run by the machine. The
spans and the recovery are added underneath, invisible in the notation.

5. One thing is worth taking back, lost when ABNF dropped it: the angle
brackets. Naur's 1960 report wrote `<expression>` for a non-terminal and the
terminal bare, and Knuth kept the convention in *The Art of Computer
Programming* and WEB. ABNF threw the brackets away to fit ASCII. HBNF already
reads `=` and `::=`, `|` and `/`, side by side, so reading `<name>` as sugar for
`name` is the same move, and it is the one a literate grammar wants — the
bracket marks the thing being defined for the reader, and the parser ignores
it. The brackets are for non-terminals. That was the point: a terminal is
written as itself, a non-terminal is written as a name in brackets, and the
reader tells the two apart at a glance.

## Appendix — The people

In the order of the list under the title.

**Emil Post (1943).** Emil Leon Post (1897–1954), a Polish-American logician.
His "Formal reductions of the general combinatorial decision problem" (1943)
gave production systems — strings rewritten by rules — the mechanism Backus
later took for his metalinguistic formulas. He had already shown, independently
of Turing and Gödel, the limits of formal computation.

**Noam Chomsky (1956).** Noam Chomsky (b. 1928), linguist at MIT. Generative
grammar turned language from examples into a formal object: a finite rule set
that generates the infinite legal sentences. The Chomsky hierarchy — regular,
context-free, context-sensitive — is the ladder every parser in this history
sits on. That a grammar is a machine for generating strings is his idea.

**John Backus (1959).** John Warner Backus (1924–2007) led the IBM team that
built FORTRAN, then spent the rest of his career arguing that programming
should move away from the von Neumann style he had helped entrench. At UNESCO's
ICIP in Paris, June 1959, he published the ALGOL 58 syntax as "metalinguistic
formulas" derived from Post's production systems — the first finite set of
rewrite rules that generated exactly the legal strings. Turing Award, 1977.

**Peter Naur (1960).** Peter Naur (1928–2016), a Danish astronomer who had used
EDSAC for comet orbits and moved to computing at Regnecentralen. As editor of
the ALGOL 60 Report (CACM, May 1960) he made the notation usable: angle
brackets, `::=`, `|`, with recursion and block structure in the one formalism.
Backus wrote a paper; Naur wrote the reference grammar of a real language.
Turing Award, 2005.

**John McCarthy (1960).** John McCarthy (1927–2011), at MIT and later Stanford.
Inventor of Lisp; his 1960 paper defined the language with a metacircular
evaluator, `eval` written in Lisp — a program that describes itself, four years
before META II. Turing Award, 1971.

**Edgar Irons (1961).** Edgar T. "Ned" Irons, at Princeton. His
"A Syntax-Directed Compiler for ALGOL 60" (January 1961) was the first compiler
whose parser ran straight off the BNF, the grammar supplying the recognition
tables as a program supplies its data. Then he went further than anyone in this
story: he built IMP, a syntax-extensible language whose production rules,
written in the program itself, rewrote the compiler's own grammar on the fly —
the grammar not merely executed, but evolving as it ran. He used those
techniques to build early time-sharing operating systems for the NSA and the
Cray supercomputers. He is the hero of this history: the man who showed a
grammar could not merely describe a language but run it, and then change it.

**R. A. Brooker (1963).** Ralph Anthony "Tony" Brooker (1925–2019), at Manchester. With D. Morris he built
the Compiler Compiler for the Atlas — the system that gave the field its name.
It read a phrase-structure description of a language and generated a
machine-code compiler for it; it built compilers for Algol and Atlas Autocode.

**D. Morris (1963).** Derrick Morris, at Manchester. Co-designer, with Brooker, of
the Compiler Compiler.

**Christopher Strachey (1963).** Christopher Strachey (1916–1975), a British
computer scientist. He led the Cambridge–London effort behind CPL (Combined
Programming Language, 1963), the ALGOL descendant whose simplifications became
BCPL, then B, then C. He went on to found denotational semantics.

**Donald Knuth (1964).** Donald E. Knuth (b. 1938), at Stanford. He founded
the theory this history mechanizes — "On the Translation of Languages from
Left to Right" (1965) — and, in *The Art of Computer Programming* and WEB, the
literate ideal that one document can be both prose a person reads and code a
machine runs. He insisted the name be Backus–Naur Form, not Backus Normal
Form, because it is not a normal form: the honesty of naming, applied to a
whole field. Turing Award, 1974.

**Dewey Val Schorre (1964).** Dewey Val Schorre, at UCLA. META II (1964), the
first documented metacompiler: a language written as "syntax equations" in the
shape of BNF, each equation compiled to the subroutine that recognized it.
He replaced `::=` with `=` and `|` with `/`, and introduced `$` for
repetition because a top-down parser cannot survive left recursion — three
decisions every later notation inherited in one form or another. META II
compiled itself; he went on to the CWIC compiler-writing project at System
Development Corporation.

**Robert McClure (1965).** Robert M. McClure, at Texas Instruments. TMG
(TransMoGrifier, 1965), a recursive-descent compiler-compiler; ported to Unix
by McIlroy, it was TMG that Ken Thompson used to write B.

**Martin Richards (1966).** Martin Richards (b. 1940), at Cambridge. BCPL
(Basic CPL, 1966), the typeless language C descended from; his `writef` is
where C's `%` format directives came from.

**Douglas McIlroy (1968).** Douglas McIlroy (b. 1932), at Bell Labs. The
inventor of the Unix pipe; he implemented TMG on the PDP-7, and it was through
his TMG that the compound-assignment operators passed from ALGOL 68 into B and
C.

**Ken Thompson (1969).** Ken Thompson (b. 1943), at Bell Labs. Co-creator of
Unix (1969); he set out to write a FORTRAN compiler with TMG and wrote B
instead, the language C grew out of. Later Go.

**Stephen Johnson (1971).** Stephen Curtis Johnson (b. 1944), at Bell Labs.
Yacc, lint, and the Portable C Compiler. He wanted to add an exclusive-or to
the B compiler and found the hand-written parser impossible to change; Al Aho
pointed him at Knuth's LR papers, and Jeff Ullman's "another compiler-compiler?"
supplied the name.

**Al Aho (1971).** Alfred Aho (b. 1941), at Bell Labs and later Columbia.
"LR Parsing" (1974, with Johnson) and the "dragon book"; AWK. It was his
pointer to Knuth's LR papers that set Johnson on Yacc.

**Dennis Ritchie (1972).** Dennis Ritchie (1941–2011), at Bell Labs. Co-creator
of Unix and the author of C (1972), the language every later system in this
history was written in or against.

**David Crocker (1982).** David H. Crocker, an Arpanet mail practitioner.
RFC 822 (1982), the mail-format spec whose section 2 everyone cited as "the BNF
in RFC 822" — the citation habit that produced ABNF. IEEE Internet Award, 2004.

**Robert Corbett (1985).** Robert Corbett. Berkeley Yacc (1985), the LALR
engine Bison adopted.

**Richard Stallman (1987).** Richard Stallman (b. 1953). The C grammar of
GCC 1.0 (22 March 1987), fed to Bison; the GNU project and free software.

**Michael Tiemann (1987).** Michael Tiemann (b. 1964). The g++ C++ front end, the
Yacc-based C++ grammar that became the standing lesson in what the machine
could not do.

**Leonard Tower (1987).** Leonard H. Tower Jr. (b. 1949). Parts of the GCC parser, the RTL
generator and definitions, and the VAX machine description.

**Paul Rubin (1987).** Paul Rubin. Most of the GCC preprocessor.

**John Gilmore (1987).** John Gilmore (b. 1955). Compiled the whole BSD source tree with
the VAX GCC in 1987–88 so CSRG could drop pcc — for ANSI C, better code, and a
way out from under the AT&T copyright.

**Keith Bostic (1987).** Keith Bostic (b. 1959), of CSRG. Endorsed the GCC switch that
took Berkeley off pcc.

**Mike Karels (1987).** Michael J. Karels (1956–2024), of CSRG. Endorsed the same switch.

**Terence Parr (1988).** Terence John Parr, at Purdue and later the University
of San Francisco. ANTLR (1988–90), the parser generator that generated the
recursive descent he was already writing by hand, with predicates and
backtracking for what finite lookahead cannot decide.

**Isaac Mozeson (1989).** Isaac Elchanan Mozeson (b. 1951), an Orthodox Jewish linguist. *The
Word* (1989), his Edenics dictionary, traces words across languages to a single
source; he saw language as the thing that brings people together. Chomsky
dismissed him. The descriptive method came around to his side anyway.

**Jeff Fox (1996).** Jeffrey Arthur Fox (1949–2011), of UltraTechnology. A
Forth programmer and a close personal friend of Chuck Moore, the language's
inventor; from 1990 they worked side by side on minimal computing taken to its
limit: Fox commissioned the F21, a "low fat" chip — a 500 MIPS Forth engine
with video, network and analog I/O, a whole workstation on a die he priced at
about a dollar. The discipline this document borrows as its epigraph — do not
solve the hard problem, remove what makes it hard — is his. May he rest in
peace.

**Bryan Ford (2002).** Bryan Ford, at MIT and later EPFL. Packrat parsing
(2002) and Parsing Expression Grammars (2004), recognition-based grammars
where ordered choice makes ambiguity impossible.

**Anders Magnusson (2002).** Anders Magnusson. Revived pcc from the opened 32V
sources from 2002, rewriting half the front end and most of the back end, and
kept the last Yacc-driven C compiler alive.

**Joseph Myers (2004).** Joseph S. Myers, a Cambridge mathematician and the
long-time GNU C front-end maintainer. Wrote the hand-written recursive-descent
C parser that replaced the Bison grammar in GCC 4.1 (2006) — the end of the age
of LALR parsing in the world's most visible C compiler.

**Max Brunsfeld (2014).** Max Brunsfeld, on GitHub's Atom team. Tree-sitter
(2014–18), the incremental GLR parser for editors, now the usual answer
whenever a tool needs a real syntax tree for a language it does not itself
compile.
