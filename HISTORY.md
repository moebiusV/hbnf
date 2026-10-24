# HyperBNF: Return of the Metacompiler

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

## Irons, IMP and the two-level grammar

Two ideas run through the early years and they pull in opposite directions: make the
grammar *run*, and make the grammar *say more*.

**Make it run.** Irons's 1961 compiler (E. T. Irons, "A Syntax Directed Compiler for ALGOL 60",
*Communications of the ACM* 4(1), January 1961) drove the parse straight off Naur's BNF.
ALGOL 60's syntax allowed more than one parse for some programs, and Irons's answer was to
add mechanisms that reject the ones that are semantically wrong (Knuth's account of the
history of attribute grammars says as much). The grammar and the rule for
choosing between its parses were one tool from the start. IMP (Irons; the dates
differ by source, from the late 1960s into the 1970s) took the next step: the grammar is the
extension mechanism. A program adds *syntax statements* to the language it is being compiled
in, `<EXP> ::= ABS ( <A> ) ::= "A<0=>-A ELSE A"`, and the parser, which "allows ambiguity in
the syntax", settles it by rule (the 1973 Yale *IMP72 Reference Manual*, section 2.3.4): a
terminal beats an identifier, then the reading that uses the fewest different syntax rules,
then an arbitrary choice. No reserved words, one grammar for the language and for what a
program adds to it. `METACOMPILERS.md` has the comparison with META II and SNOBOL4.

**Make it say more.** BNF cannot say that a name must be declared before it is used, or that
the two sides of an assignment have the same type. Adriaan van Wijngaarden's answer, for the
ALGOL 68 Report, was a grammar of grammars: a first level of *metarules* defining sets of
strings (`MODE :: int ; real ; ref to MODE`), and a second of *hyperrules* whose names
contain them (`MODE list : MODE, comma symbol, MODE list`), so that every consistent
substitution of a metanotion gives an ordinary rule and one hyperrule stands for a family,
usually an infinite one. With unrestricted metanotions the formalism is Turing complete.

**What stopped it.** By the accounts in Lindsey's *A History of ALGOL 68* and Koster's
*The Making of ALGOL 68*, the first thing was the Report itself: from the beginning,
prominent members of the working group complained that two-level grammars were too complicated
to understand, and the 1968 Report was called unreadable (the 1973 Revised Report is a
much more readable grammar, and admits in a famous sentence that its method may be difficult
for the uninitiated reader). The second was that the formalism was too strong to be used:
in its full generality it cannot be the input of a parser generator, so the groups that built
compilers rewrote the grammar by hand into a context-free one and checked the rest in the
compiler, and the Report stopped being the specification anyone actually ran. The third was
the language: large, orthogonal, with coercions and modes that made it slow to implement while
Pascal and C were simple enough to compile in one pass on a small machine. The grammar did not
kill ALGOL 68 alone, and the historians say that "too big" and "unreadable" are oversimplified;
but a grammar nobody could read and no tool could run is a poor basis for a language that has to
spread. (This paragraph is a summary of those two histories and Wikipedia's article on van
Wijngaarden grammars, not of the Report; check them before quoting it.)

*Sources:* [Irons, "A Syntax Directed Compiler for ALGOL 60", CACM 4(1), 1961](https://doi.org/10.1145/366862.366872);
[Knuth, "The genesis of attribute grammars"](https://www.cs.tufts.edu/~nr/cs257/archive/don-knuth/history-of-attribute-grammars.pdf);
[Lindsey, "A history of ALGOL 68"](https://algol68-lang.org/docs/lindsey-history-of-algol68.pdf);
[Koster, "The making of ALGOL 68"](https://algol68-lang.org/docs/koster-making-of-algol68.pdf);
[Van Wijngaarden grammar (Wikipedia)](https://en.wikipedia.org/wiki/Van_Wijngaarden_grammar);
Bilofsky, *IMP72 Reference Manual*, Yale, 1973 (see `METACOMPILERS.md`).

**What hbnf takes from the line.**
- From Irons: the grammar and the choice rule are one document. IMP72's three-step tie-break is
  decision 14's order (a failing test removes a reading, a terminal beats an expression, the
  fewest rules wins, and where IMP72 says "arbitrary" hbnf says "the first written"). And an
  extensible, ambiguous grammar is fine if the ambiguity is *detected and reported* rather than
  silently resolved.
- From van Wijngaarden: the idea that one rule can stand for a family (`list(X) := X *( "," X )`),
  and that two places in a rule can be made to agree (the closing tag equals the opening tag, the
  here-document terminator, a raw string's delimiter).
- From both histories, what not to copy: a notation that only its author can read, and a power
  nobody can bound.

**How hbnf makes the two-level grammar work for real.** By keeping the part that is decidable
and cheap, and handing the rest to tools that already exist (`METACOMPILERS.md`, section on
W-grammars, has the argument; `RFCPLAN.md` has the decisions):
- *Parameterised rules over a finite set* are expanded when the parser is generated, so a
  hyperrule becomes the ordinary rules it stands for, and the parser is the one you would have
  written by hand. No runtime cost, no new parsing algorithm, no undecidability. Domains are
  checked when the grammar is read, so a use that can never match is an error with a message.
  *Built (`tests/params.sh`): see "Why a two-level grammar can fail to end" below.*
- *Consistent substitution* becomes a back-reference: `name %as tag` keeps the text a name
  matched and `%same tag` is that text again, in the same sequence. It is a slice of the input
  (two integers in the generated function, no copy), so a backtrack restores it with the
  position and nesting cannot mix two of them up. Mustache's closing tag, XML's, a here-document's
  terminator are the same rule. *Built, in C (`tests/backref.sh`, `corpus/mustache`).*
- *What a finite domain cannot hold*, the names declared so far, is a **context** (decision 13: a
  persistent set, `? types`, `%bind`, `%scope`, `%where`), kept local to the rule it affects.
  *Built, in C.*
- *Ambiguity* is handled by local forks (decision 14, `--forks`) and by a lookahead test
  (`!x`, `&x`). *Built, in C, in their local form.*
- *Types and modes* are checked by a pass over the tree, not by the grammar. A parser that has
  to be a type checker is why the Report could not be run.
The ALGOL 68 grammar will be written in this hbnf and not in the Report's literal two levels
(the user's decision, 2026-10-18). ALGOL 60 came first as the proving ground, and it has been
checked against the Report's own BNF with an independent recognizer.


### Why a two-level grammar can fail to end, and why it almost never does

A metanotion is a set of strings defined by a context-free grammar of its own, and a hyperrule
name contains metanotions, so a hyperrule is a template for every rule you get by putting a
string in each. Reading a sentence means choosing those strings. Whether a choice exists is
where the trouble is, because the strings are written into rule *names*, not into the text being
read, and nothing about the finite input bounds them.

The smallest example:

    A :: x ; A x.             (A is any run of x's: an infinite set)
    A word : A x word.        (a hyperrule: "A word" is "A x word")

Instantiate `A` with `x` and the rule is `x word : x x word`; with `xx`, `xx word : xxx word`.
Every instance is a rule whose only right-hand side is another instance with a longer name, and no
terminal is consumed on the way. A recogniser asked whether the input holds an `x word` is sent to
`xx word`, then to `xxx word`, and so on, though the input is a few characters long. It is left
recursion, with the difference that every step is a different rule, so there is no repeated state to
catch. In general, consistent substitution lets a grammar copy a string and compare it with another,
and that is enough to encode a Turing machine or Post's correspondence problem. Whether a given
sentence is derivable is undecidable, so no recogniser halts on every grammar and every input.

**Can the cycle be detected?** Often, yes, and tracking which hyperrule is being instantiated is the
way. There are three cases and they differ.
- *The same instance again.* Remembering the instances already made ends it exactly. When every
  parameter ranges over a finite set the number of instances is finite, so every chain either
  repeats an instance or stops (the pigeonhole principle), and the check is complete.
- *The same hyperrule with a strictly bigger argument*, as above. A static check follows the chain of
  instances, sees each argument larger than the last with nothing consumed between, and reports it.
  This is the termination analysis of term-rewriting systems and Prolog programs, and it is sound but
  not complete: a rule whose argument shrinks for a while and then grows, or grows only after a detour
  through other rules, can slip through. No fixed check catches every non-terminating grammar and
  accepts every terminating one; that is the halting problem.
- *The same instance at the same input position, while parsing.* Remembering the pair (instance,
  position) detects it exactly, as it does left recursion in a packrat parser.

**Does laziness help?** Partly, and it is how the practical parsers cope. Instantiate a metanotion
only when the parser needs it at the current position, memoise by (instance, position), and the
work is bounded by the input: when the input can no longer match, nothing more is made. The infinite
family `ref to ref to ... int` is in principle unbounded but any program uses finitely many of its
members. What laziness does not do is stop the cycle above, because there the demand comes from the
rule itself and no input has been matched for it to run out of. The same remedy applies as for left
recursion: require progress, and refuse the rule that makes none.

**How hbnf spells them.** As the Report does, with the operators told apart: `=` defines a rule,
`:=` a rule with parameters (a hyperrule, the Report's `:`) and `::=` a domain (a metarule, the
Report's `::`), so `level ::= 1..17` and `binary(N in level) := binary(N+1) *( op(N) binary(N+1) )`
read as the Report's two levels do. A metarule is a plain context-free production, over the strings
that go into names instead of the sentences of the language, and here it is a finite set of numbers or
words (a domain that names itself would be the infinite family, and is refused). A file in BNF, where
`::=` or `:=` defines an ordinary rule, names its notation with `dialect bnf`; in HyperBNF's own notation
a BNF rule read as a metarule is refused with the line to add.

**What hbnf does.**
- Parameters range over a *finite* set (a number in `1..17`, one of a list of words, or a rule
  name), so the family is finite and is expanded into ordinary rules when the grammar is read: the
  parser is the one you would have written by hand, with no runtime cost and no new algorithm.
- The *domain is checked then*: a use outside it (`binary(18)` when `N` is `1..17`) is an error that
  names the chain of instances that led to it, not a parse that fails on some input.
- A chain that re-enters a hyperrule with a *bigger argument* is refused at once, with the chain,
  instead of running to a limit (there is a limit as well, at 20,000 instances).
- Where the family is open, as Algol 68's modes are, the plan is the lazy, input-driven instantiation
  above, with a no-progress check; it needs support in the parser and is the Algol 68 step's work.
- Consistent substitution is the back-reference (`%as`, `%same`), and what a finite domain cannot
  hold, the names declared so far, is the context of decision 13. Neither needs the infinite family.

**Why real grammars rarely meet it.** A grammar that is written to be read, which the Report's is and
every grammar a programmer writes is, has metanotions that stand for the finite things a language has:
the modes a program uses, the kinds of operand, the precedence levels. Its recursion consumes input at
each step, as any grammar's must if a parser is to run. The non-terminating hyperrule is a construction
made on purpose, to show that the formalism is as strong as a Turing machine; none of the working
descriptions or implementations (Koster's affix grammars and the CDL compiler description language, the
Prolog definite clause grammars, the attribute grammars) needed more than the bounded part. Restricting
parameters to finite domains, as hbnf does, makes the question decidable by construction and costs the
grammars people write nothing.

**Is it a typeclass?** Much of it is, and the comparison is the quickest way to explain the rules to a
programmer. A parameterised rule is a function from arguments to a rule, chosen by pattern: an instance
declaration in Haskell is a function from types to dictionaries, chosen by pattern, and the most
specific wins (`binary(17) := unary` beside the general `binary(N in 1..17)` is overlapping instances).
Expanding every use before the parser runs is monomorphisation, as C++ templates and Rust generics do,
and it costs nothing at run time (Haskell's dictionary passing does). A domain is a closed set of
instances. And the termination trouble is the same trouble: instance resolution in Haskell can chase
its own tail (`instance C [[a]] => C [a]`), and GHC refuses it unless `UndecidableInstances` is on,
because its conservative check, the Paterson conditions (the constraint must be structurally smaller
than the head), is a sufficient condition for finite resolution that rejects some programs that would
in fact end. hbnf's growth check is the same trade. Where it differs is that nothing here is typed: a
parameter is a rule name, a word or a number, not a type, and there is no inference.

**What it saves.** The numbers are in *Measured* below: the grammar text of ALGOL 60 and JSON is
about half the size of the Report's BNF and the RFC's ABNF, and the OpenBSD daemons' `parse.y`
files lose their lexers and C actions. The ALGOL 68 saving has not been measured: it is the point
of the pilot, a chapter of the Report's W-grammar counted before and after.

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

**What Tree-sitter does about context, and what that costs.** A parser generator has three
places to put context-sensitivity, and Tree-sitter uses all of them in its own way. (1) *The
lexer is told what the parser expects.* It lexes by parse state: only the tokens that are valid
in the current LR state can match, so `<` can be an operator in one state and a bracket in
another, and a keyword is a keyword only where one can occur. (2) *The parse forks.* Where the
LR table has a conflict (`a * b;` as a declaration or as a multiplication, `T(x)`, `a < b > c`)
it splits the stack and runs the readings in parallel on the same input; the ones that die are
dropped, and of those that survive the one with the higher `prec.dynamic` and the lower
error cost wins. The author names the conflicts (`conflicts`) and the precedences. (3) *A hand-written
scanner in C*, with state it serializes, for what no regular lexer can do: indentation, heredocs,
raw strings, nested template literals.

The limitation is what none of the three has: **a symbol table.** Tree-sitter cannot know that
`T` was declared a type three screens earlier, so it decides `T * x;` by precedence and by which
reading survives, not by what the program declared, and where the two readings are both valid
it picks by a number the grammar author chose. That is why Tree-sitter's C and C++ trees are
sometimes wrong where it matters (a typedef name taken for a variable), and why a tool that
needs the right answer must run its own semantic pass over the tree afterwards. It is also
the price of what Tree-sitter is for: incremental re-parsing and a tree for text that is
half-written, where a wrong guess is cheap and an error is not allowed.

The other cost is the machinery. In the repository's benchmark (`bench/results/treesitter.md`)
on one toy language at 100,000 rules, Tree-sitter parses the 7.7 MB file in 226 ms with 63 MB
of memory, against hbnf's C parser at 26 ms and 21 MB; at a million rules, 2,302 ms and 620 MB
against 266 ms and 204 MB. That is about nine times the time and three times the memory, on a
grammar with no ambiguity in it, so the forking itself is not in the number: it is the price of
the tables, the tree it builds for editing, and the generality of the lexer.

hbnf's forks (decision 14) are a smaller thing than GLR and should not be confused with it. They
are depth-first: try one alternative to the end of the enclosing sequence and, if something later
in that sequence fails, back up and try the next, with no stack of stacks and no reach past the end
of a rule. Where Tree-sitter keeps both readings alive and decides at the end, hbnf's contexts
decide *at the choice*: a `? types` test on an alternative removes the reading that the declared
names rule out before anything is parsed under it. That is the part of C++ Tree-sitter cannot do,
and the part of C++ that forks are not needed for.

There is a Tree-sitter backend (`--backend=tree-sitter`), and what it shows is the same
difference from the other side. A HyperBNF grammar becomes a `grammar.js` mechanically, ALGOL 60 and
JSON parse the same texts in Tree-sitter as in HyperBNF (JSON: 2,000 documents and 2,000 mutations, no
difference; ALGOL 60: every one of 500 sentences of the Report), but ordered choice has to be
turned into `conflicts` and `prec.dynamic` (four conflicts for ALGOL 60), and a lookahead, a
context test or a back-reference cannot be turned into anything: it is left out, and the nine
mutants out of 500 that only Tree-sitter accepted were all the lookahead that was left out. The
clearest case is Mustache, whose closing tag must repeat the opening one (`{{#a}} ... {{/a}}`):
hbnf says it with `%as` and `%same`, and the Tree-sitter grammar it writes accepts `{{#a}}x{{/b}}`,
because a Tree-sitter grammar cannot make a token repeat another; 106 of 2,000 mutated templates
were accepted by Tree-sitter alone, and 103 of those 106 have a closing tag naming another section.
Tree-sitter's one place for state is the external scanner, a C file with state of its own that
Tree-sitter saves and restores for every fork, and the backend uses it (`--ts-scanner=FILE`): the
scanner holds the name the opening tag captured and accepts the closing tag only if it is the same
text. With it the 106 disagreements are gone (0 of 2,000). The same scanner does the lookahead
`!x` and `&x` (a zero-width token that looks at the text, skipping the white space the grammar skips,
and takes the literal that follows it into the test, because Tree-sitter cannot take a token back):
the nine ALGOL 60 mutants only Tree-sitter accepted are gone too, and 3,000 sentences and 3,000
mutations of the Report agree exactly. What the scanner cannot do is see the parse, only the
characters, so a context test that depends on what the parser has reduced (whether `T` was declared
a type) still has no equivalent.

The thread through all of it: Backus and Naur gave a generative notation,
Johnson mechanized the LR subset of it, Crocker loosened the notation for
protocol writers, Parr and then Myers walked production parsers back to
debuggable top-down code, Ford replaced generative choice with ordered
recognition, and Brunsfeld optimized the tree for a buffer that is never
finished.

It is a pendulum between the two readers, each swing trading one reader's ease
for the other's.

## HyperBNF

HyperBNF starts from where that thread left off and picks a side. Its bet is that
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
HyperBNF makes round-tripping easy: comments are first-class tokens, not
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
existing, and it requires a generalized-LR engine with a stack of stacks. HyperBNF's
design is ordered choice plus maximal munch, the opposite trade; adding GLR
would mean discarding the design. And HyperBNF will not handle genuinely ambiguous
grammars, because that is not a missing feature to add later — it is the thing
the design refuses on purpose. ALL(*) and GLR exist for the languages that need
them. HyperBNF exists for the ones that do not, and for the person who wants the
grammar and the parser to be the same document.

Judged on that single aim — one document that serves both the person and the
machine — the others all pick a side. BNF and ABNF are for people; Yacc and
Tree-sitter are for machines; ANTLR and PEG generate code but drop the writer's
comments and exact spellings. HyperBNF tries to be both at once, and the round trip
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
whole. HyperBNF was not written for AI. That is what will make it useful to AI.

*Sources:* the [hbnf repository](https://github.com/moebiusV/hbnf), and [RFC 5234](https://www.rfc-editor.org/rfc/rfc5234) for the ABNF it compiles.

## Measured: what HyperBNF saves and what it costs

Every number here is produced by a script in the repository, from the files in `corpus/` and
`grammars/`, and can be rerun. For a grammar the comparison is the published notation against the
hbnf, comments and blank lines left out of both. A *symbol* is a whitespace-separated word of the
grammar text, which is what a reader (or a language model) pays for; the count of LLM tokens depends
on the tokenizer and has not been measured, but it follows the characters.

**BNF and ABNF rewritten in HyperBNF: fewer rules, fewer lines, fewer symbols.** Where a grammar is
rewritten rather than pasted, the rewrite says each thing once: a comma list is `x *( "," x )`, a
block is a compound statement with declarations in front, the three expression grammars that exist
to carry a type are one (a checking pass applies the types), a punctuation mark is the quoted
character, the lexical rules share the RFC core rules.

| language | published notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1,246 | 8,064 |
| | hbnf (`corpus/algol60`) | 47 | 72 | 528 | 3,604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | hbnf (`corpus/json`) | 14 | 14 | 129 | 556 |
| | **saved** | **53%** | **69%** | **33%** | **41%** |

The RFC grammars in `corpus/rfc` are not in the table on purpose: they are pasted verbatim, with one
line added, to show that RFC text compiles unchanged, so they save nothing and are not meant to.

**OpenBSD's `parse.y`, translated.** The nine daemons' grammars in `grammars/obconf_*.hbnf` are
faithful translations of the real `parse.y` files (OpenBSD `master`, pinned in `bench/pins.txt`), and
here the answer is less flattering than a whole-file count suggests, so it is worth saying plainly.
A `parse.y` is four things: a prologue (includes, declarations, the token list), the grammar rules, the
C code in braces inside those rules that builds the daemon's structures, and a hand-written lexer with
its keyword table and helpers after the second `%%`. `bench/parsey.py` splits each file that way and
counts lines, comments and blank lines left out:

<!-- bench:parsey -->
| daemon | `parse.y` total | lexer, keywords, C | actions | rule notation | HyperBNF grammar |
|---|---:|---:|---:|---:|---:|
| bgpd | 5,540 | 2,530 | 2,494 | 516 | 501 |
| dhcpleased | 733 | 542 | 159 | 32 | 22 |
| httpd | 2,490 | 1,185 | 1,057 | 248 | 185 |
| ldpd | 1,498 | 868 | 484 | 146 | 114 |
| ntpd | 731 | 377 | 292 | 62 | 22 |
| pfctl | 5,885 | 2,524 | 2,777 | 584 | 492 |
| relayd | 3,426 | 1,266 | 1,814 | 346 | 323 |
| snmpd | 1,867 | 900 | 813 | 154 | 121 |
| unwind | 831 | 593 | 166 | 72 | 67 |
| shared `obconf.hbnf` | | | | | 30 |
| **nine daemons** | **23,001** | **10,785** | **10,056** | **2,160** | **1,877** |

Only the rule notation is directly comparable with the HyperBNF grammar; the
lexer is replaced by hbnf's reader, and the actions only where they are bound:

| daemon | `parse.y` total | HyperBNF grammar + bound actions | saved |
|---|---:|---:|---:|
| ntpd | 731 | 22 + 331 = 353 | **52%** |
| unwind | 831 | 67 + 264 = 331 | **60%** |
<!-- /bench:parsey -->

As a notation the HyperBNF grammar is about the size of yacc's rules (a quoted `"listen"` is longer than
the token name `LISTEN`, and each option list spells out the keyword that tags it). The saving is in the
other 90%: hbnf's reader, `statements` mode and typed tree replace the lexer, keyword table and
include-file stack, which is about 47% of a `parse.y`, and the actions, another 44%, are replaced only
where they are bound.

Only ntpd and unwind have their actions bound so far (`grammars/bind/`), so those are the two rows
that can be compared whole; for the other seven, hbnf parses and builds the tree and the daemon's
own actions are not yet attached.

**Speed and memory.** The repository's benchmark (`bench/results/`) puts the generated C parser at
26 ms and 21 MB on the 7.7 MB toy-language file where byacc plus flex takes 63 ms and 23 MB, bison 84 ms,
Tree-sitter 226 ms and 63 MB, and ANTLR 4 111 to 222 ms and 204 to 530 MB; at a million rules, 266 ms
against Tree-sitter's 2,302 ms. On a real format, a 39 MB JSON document of 250,000 records, parsed
into the typed tree and nothing else (best of three, one machine):

| parser | time | peak memory |
|---|---:|---:|
| hbnf (C, built on Alpine/musl) | 423 ms | 237 MB |
| Python `json.load` (C accelerated) | 391 ms | 179 MB |
| Tree-sitter 0.27 | 1,992 ms | 779 MB |

That is Tree-sitter at 4.7 times hbnf's time and 3.3 times its memory, and hbnf within 8% of Python's
hand-tuned C parser while building a tree typed by the grammar. Running this found a real fault, now
fixed: the generated parser worked out the line and column of every failure that went deeper than the
last, which is a pass over the text each time, so a long input with any backtracking took quadratic
time; the first attempt at this file ran for minutes. The position is now worked out once, if the parse
fails.

## Appendix — Incremental Parsing without Giving Up the Grammar

1. Tree-sitter's two real wins are incremental reparse and error recovery. Both
rest on a concrete tree whose nodes carry byte spans: an edit reuses every
subtree it does not touch, and a broken file still yields a tree with ERROR and
MISSING nodes instead of nothing.

2. Tree-sitter needs generalized LR for this because it must preserve ambiguity
across an edit. HyperBNF has no ambiguity to preserve, because it refuses it up
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
`1*`, `n*m`, `[ ]`, the character classes, the `%scan{}` scanner actions, `whitespace ws`
— remains the single source, read by the person and run by the machine. The
spans and the recovery are added underneath, invisible in the notation.

5. One thing is worth taking back, lost when ABNF dropped it: the angle
brackets. Naur's 1960 report wrote `<expression>` for a non-terminal and the
terminal bare, and Knuth kept the convention in *The Art of Computer
Programming* and WEB. ABNF threw the brackets away to fit ASCII. HyperBNF already
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
