# A Short History of the Parser Generator

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
intention into the machine without losing it.

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

## The machine: Yacc

BNF describes a language. It does not build a parser. For a decade the two were
separate jobs: a language was specified in BNF, and a compiler was written by
hand against the specification.

Stephen Johnson ended the division. At Bell Labs in the early 1970s he wanted
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

## The return to top-down: ANTLR and GCC

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

The industrial confirmation came from a compiler project. In 2004–06 GCC threw
out its Bison LALR grammars for C and C++ and went back to hand-written
recursive descent. Joseph Myers wrote the C front end the way Ritchie had
written the original — shift and reduce became calls and returns, error messages
became ordinary C, and the typedef hack became a real symbol table. The dogma
that a production compiler must use an LALR generator died there. Clang followed.

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

## The incremental tree: Tree-sitter

The last turn was not about compilers at all. Max Brunsfeld built Tree-sitter
(2014–18) for the editor: a syntax tree that updates from an edit instead of
re-parsing the whole file, and that still returns something when the buffer is
briefly illegal. It uses generalized LR, keeping a stack of stacks so local
ambiguity can be represented, and writes ERROR and MISSING nodes into the tree
rather than failing. The grammar is a JavaScript DSL that compiles to C. Atom
is gone; Tree-sitter is now the usual answer whenever a tool needs a real
syntax tree for a language it does not itself compile.

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

**Where it succeeds.** An RFC grammar compiles nearly verbatim: `=`, `|`, `/`,
`*`, `1*`, `n*m`, `[ ]`, and the core character classes all mean what an RFC
reader already expects. Character-level rules compile to scanners — `int = 1*DIGIT`,
`comment = "#" *comment_char` — so there is no separate lexer grammar and no
regex. Direct left recursion is read as a loop, not rejected. Ordered choice
keeps conflicts impossible, and a shadowed alternative is refused at schema time
with a diagnostic rather than failing at runtime. The tree is typed from the
shape of the rule — enum, scalar, list, struct — with no visitor to write. And
the thing HBNF does that none of its ancestors did: it round-trips. Comments are
first-class tokens, not whitespace, so a config file comes back out with its
comments in the right places, and a value written `0xFF` comes back as `0xFF`,
not 255. A parse failure is a line, a column, and a caret under the token that
was expected.

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
comments and exact spellings. HBNF tries to be both at once, and its round trip
is the proof: the text a person reads is what the machine runs, and the machine
hands it back unchanged. The writer's intention arrives whole, and no earlier
tool managed that.

The line ends where it began, and it ends against Chomsky. Generative grammar
started as a claim about the mind: a language is a set of rules that produces
its sentences. That method drove the early years — BNF and Yacc both generate.
But the useful work drifted the other way. ABNF defines a language without an
automaton; PEG replaces generation with ordered recognition; the grammar stopped
producing strings and started describing the ones that exist. Generation lost.
Description won.

Isaac Mozeson would be pleased. Chomsky was cruel to him — an Orthodox Jewish
linguist who described the actual words, tracing them back to their roots,
instead of generating abstract sentences from rules — and Chomsky dismissed him
as he dismissed everyone who disagreed. The field came around to Mozeson's side
anyway. The descriptive method, looking at the language as it is and naming
what is there, is the one that now runs the software. Chomsky was nasty, and
Chomsky was wrong. Mozeson's way proved more useful in the end.
