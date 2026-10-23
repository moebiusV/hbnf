# hbnf beside META II, IMP72 and SNOBOL4

> **2026-10-22:** hbnf will not read or bootstrap the IMP72 compiler (the user: IMP72 "is its
> own thing and will get its own compiler"), so the sections below that ask whether hbnf
> could be its kernel are history, not a plan.  What hbnf took from IMP72's manual stands.
> The ALGOL 68 experiments they mention are far in the future.

hbnf is a meta-compiler: a program that takes a description of a language and
produces the thing that processes it.  Configuration files were where it
started, not where it stops.  Three older systems made the same bet from
different directions, and each is a precedent for something in hbnf's
`%scan{ }`, `%action{ }`, planned `%where{ }` and `%emit{ }`.  This reads them
against hbnf, from the primary sources, and ends with what hbnf could take.

Sources, all read for this note (the first two as scans with a text layer):

- **META II** — D. V. Schorre, "META II: A Syntax-Oriented Compiler Writing
  Language", UCLA, 1964.
  [PDF](https://ibm1401.computerhistory.org/Meta-II-schorre.pdf)
- **IMP72** — Walter Bilofsky, *IMP72 Reference Manual*, Yale, 1973 (DECUS
  10-198a, PDP-10 IMP72 compiler version 1.5; the language is E. T. Irons's
  IMP, extended).
  [PDF, Computer History Museum](https://archive.computerhistory.org/resources/access/text/2024/09/102737513-05-0002-acc.pdf)
- **SNOBOL4** — Griswold, Poage and Polonsky, *The SNOBOL4 Programming
  Language* (Bell Labs), as scanned at
  [Bitsavers](https://www.mirrorservice.org/sites/www.bitsavers.org/pdf/att/Bell_Labs/snobol4/Griswold_SNOBOL4_Programming_Language_1968.pdf).

IMP72 is not a descendant of META II.  It is Irons's line (his syntax-directed
compiler is 1961, three years before META II), which makes it an independent
answer to the same question.

## What each one is

**META II** is a language of *syntax equations* that also emit code.  "Each
syntax equation is translated into a recursive subroutine which tests the input
string for a particular phrase structure, and deletes it if found.  Backup is
avoided by the extensive use of factoring in the syntax equations."  Tokens are
three built-in recognizers, `.ID`, `.NUMBER` and `.STRING`.  Output is written
inside the equation: `.OUT('BFP' *1)` emits an instruction, `*` stands for the
token just matched, and `*1` and `*2` are labels the system invents afresh each
time the equation runs.  The compiler is written in itself.  The target is the
assembly language of a small interpreter, "the META II machine".

**IMP72** is an extensible systems-programming language.  Its grammar is not
fixed: a program can add productions to the syntax it is being compiled with, as
*syntax statements* of the form

    <class> ::= syntax-part ::= semantic-part

The semantic part is either a *quoted expression* in the language already
defined (`<EXP> ::= ABS ( <A> ) ::= "A<0=>-A ELSE A"`, which the compiler
rewrites into every use) or a call to a *semantic routine*, "normal compiler
subroutines which are also available to the syntax writer in a limited sense"
(§2.3.3.1), working on a stack of typed objects that carry the code computed so
far.  Syntax statements "with no semantic part" just discard all but the first
argument.  The parser "allows ambiguity in the syntax" and resolves it by rule
(§2.3.4): a terminal beats an identifier, then the fewest different syntax rules
wins, then an arbitrary choice.  There are no reserved words.  The compiler
compiles itself, and its own syntax is a list of such statements (Appendix II).

**SNOBOL4** is a string-processing language whose patterns are values.  A
pattern is built from primitives (`ARB`, `BAL`, `FENCE`, `ABORT`, `FAIL`,
`SUCCEED`, `REM`; and the pattern functions `ANY`, `ARBNO`, `BREAK`, `LEN`,
`NOTANY`, `POS`, `RPOS`, `RTAB`, `SPAN`, `TAB`), combined by concatenation and
alternation, and matched by a scanner that backtracks: when a part fails "the
scanner backs up seeking alternatives".  Side effects come in two timings:
`P . V` is *conditional value assignment*, made "upon successful completion of
pattern matching"; `P $ V` and `@X` are *immediate*, made "when the scanner
encounters" them, "not following successful completion".  And `*E` "postpones the
evaluation of its operand": it is evaluated when the scanner reaches it, its
value becomes part of the pattern, and "if evaluation of the expression fails,
the scanner backs up seeking alternatives".  That one operator gives recursive
patterns (context-free grammars) and lets a function decide a match.  The manual
itself advises that conditional assignment be used "whenever possible".

## Side by side

| | META II (1964) | IMP72 (1973) | SNOBOL4 | hbnf |
|---|---|---|---|---|
| **A rule is** | a recursive subroutine that recognizes and consumes | a production stored in a table; every parse carried until resolved | a pattern value, matched by a backtracking scanner | a rule; a generated recognizer per backend |
| **Choice** | ordered `/`, no backup, so factor by hand | ambiguity allowed, resolved by three rules | ordered alternation with full backtracking; `FENCE` and `ABORT` cut it | ordered `\|`; `/` is a union hbnf orders (or refuses with a witness); prefix factoring done by the tool |
| **Tokens** | built-in `.ID` `.NUMBER` `.STRING` | classes `<NAME>`, `<VBL>`, ...; no reserved words | primitives `SPAN` `BREAK` `LEN` `ANY` ... | character-level grammar; `%scan` scanner actions; a rule is a token (automaton) when an exception names it |
| **Code, when** | `.OUT` inline, as the parse proceeds | semantics run as productions reduce, held back until context settles which special case applies; `PRIORITY` forces them now | `.` after the match succeeds; `$` and `*f()` during it | `%action` once, after the parse, bottom-up; `%where` (planned) during it, each try; `%emit` (planned) |
| **Code is written in** | META II's own output language (assembly for its machine) | IMP itself (quoted), or compiler subroutines in IMP | SNOBOL4 itself (`DEFINE`d functions) | any language with a backend: C, Rust, Zig and Ada today, once per backend; there is no rule against assembly |
| **Output** | assembly for an interpreter | object code through typed objects | none (strings) | a typed tree; round-trip printing; `%emit` planned |
| **Fresh names** | `*1`, `*2` per run of an equation | `LOCAL R IN "..."`: a unique name per use | n/a | none yet |
| **Grammar grows** | edit the compiler's own source | syntax statements inside the program | patterns built at run time | `include`, `dialect`, `%grammar "file"` |
| **Self-hosting** | yes | yes | no | not yet (`hbnf_schema.hbnf` is a grammar for config files, not for hbnf's own notation) |

## Your hunch about `%scan` and `%action`: yes, and the names are precedent

The three levels hbnf already distinguishes (decision 8 in `RFCPLAN.md`) each
have an old counterpart.

- **`%scan{ }` (lexical, runs at a position and returns how much it took)** is
  META II's built-in recognizers and SNOBOL4's primitive pattern functions: code
  in the system's runtime that recognizes a piece of the input, standing in for
  something the notation could not or should not say.  META II calls them
  built-in; SNOBOL4, primitives.
- **`%action{ }` (semantic, once, after the match)** is SNOBOL4's *conditional*
  assignment `.`, exactly: an effect made only when the whole match has
  succeeded.  It is also yacc's semantic action, and IMP72's semantic part when
  it runs after context is known.
- **`%where{ }` (decision 13: each time an alternative is tried, may fail it)** is
  SNOBOL4's *immediate* assignment `$` plus `*f()`: it runs during the match,
  its failure backtracks, and it may run on a branch later abandoned.  SNOBOL4's
  manual warns about the cost of that timing and tells you to prefer the
  conditional one, which is the argument for `%action` being the default and
  `%where` being deferred "until a grammar actually needs it".
- **`%emit{ }` (generative)** is META II's `.OUT`, and IMP72's quoted
  semantics: write the target.

IMP72's `PRIORITY` semantics (§2.3.3.5) is the same axis a third time: by default
a semantic action waits until the surrounding context has chosen between special
cases, and `PRIORITY n` runs it the moment the production is recognized.  Three
systems, three spellings of "after, or now".

## Names for hand-written scanner code

hbnf has one word for code the grammar calls out to: an *action* (`%scan` for a
scanner, `%action` after the parse, `%where` as a predicate, `%emit` when
writing).  Other systems name it differently, which is only a reading aid:

| system | term |
|---|---|
| yacc/bison | *semantic action* (code on a rule); the tokenizer `yylex()` is the *lexical analyzer* |
| META II | *built-in recognizers* (`.ID`, `.NUMBER`, `.STRING`) |
| IMP72 | *semantic routines* (subroutines of the compiler available to the syntax writer; "as a last resort go into the compiler to add new ones") |
| SNOBOL4 | *primitive patterns* and *primitive functions*; user-defined functions called from a pattern with `*` |
| tree-sitter | *external scanner* |

Two uses are worth telling apart when it matters: code with no grammar behind
it (META II's `.ID`, SNOBOL4's `SPAN`), and code that implements a rule the
grammar *also* defines, as an optimization one may drop.  hbnf says which in
the sentence, not with another term.

## W-grammars (van Wijngaarden), and what they add that is not planned

A two-level grammar (the ALGOL 68 Revised Report is written in one).  Level
one is *metarules* that define *metanotions* (`MODE :: int ; real ; ref to MODE`
...), each a set of strings.  Level two is *hyperrules* whose names contain
metanotions: `MODE list : MODE, comma symbol, MODE list`.  Every consistent
substitution of a metanotion by one of its strings gives an ordinary rule, so a
hyperrule stands for a (usually infinite) family, and `where MODE1 is MODE2`
makes two spots in one rule agree.  With unrestricted metanotions this is
Turing complete, so parsing *may* be undecidable, but in practice it is not:
the Report's grammar is a real, finite working description, and parsers and
checkers for it and for other W-grammars have been written, because a grammar
written to be read is not an adversarial one.  The Report uses it for what a
context-free grammar cannot say (identifiers declared before use, types
agreeing).  What descended from it and was
made practical: Koster's *affix grammars* and *extended affix grammars*
(finite-domain parameters, the CDL compiler-description language), Prolog DCGs
(arguments on nonterminals), attribute grammars, Fischer's *macro grammars*.

hbnf already has the other answers to "context": decision 13 (named persistent
context, `?`, `%bind`, `%scope`, `%where`), the wire layer's expressions over
earlier fields (`len(field)`, `?(cond)`), and decision 14 (detected forks).  What
W-grammars give beyond those, kept to the decidable subset:

1. **Parameterised rules over a finite set, expanded when the parser is
   generated.**  `list(X) := X *( "," X )`; `binary(N) := binary(N+1) *( op(N)
   binary(N+1) )` for the 17 precedence levels of C++, with the operators per
   level in a table; a parameter ranging over an enum (`value(int)`,
   `value(string)`).  The family is finite, so it expands into ordinary rules:
   no runtime cost, no new parser, no undecidability.  Today a repeated shape
   is written out each time (or lifted into hidden rules by hand).  The C++
   standard's own grammar leans on this (`-list`, `-opt`, the declarator
   families).  This is LBNF's indexed categories and Menhir's parameterised
   nonterminals under another name, and it is the one idea here that is both
   useful and cheap.  *Built 2026-10-19 (every backend, since the uses are expanded into ordinary rules when the grammar is read): `list(X)`, number parameters over a domain, clauses for single values, a growth check; `tests/params.sh`.*
2. **Consistent substitution as a back-reference: this text must repeat that
   earlier text.**  `where TAG is TAG` is XML's `<a> ... </a>`, a here-document's
   terminator (`<<EOF ... EOF`, which the POSIX shell corpus needs), C++
   raw strings `R"delim( ... )delim"`, Rust `r#"..."#`, Lua long brackets
   `[==[ ... ]==]`, Markdown fences.  hbnf cannot say any of them declaratively
   today; decision 13 would do them with a `%bind` and a `%where` in code.  The
   wire layer already names earlier fields and tests them (`?(len(f) == n)`);
   the same for text (`d:delim ... ?(text == d)`, or a back-reference spelled
   like a rule name) is the declarative form, and is what regexes call a
   back-reference.  *Built for text in C (2026-10-19): `x %as tag` ... `%same tag`, local to a sequence (ABNF.md; `tests/backref.sh`, `corpus/mustache`).  Planned for the wire layer.*
3. **Domains checked at generation time.**  An affix grammar's parameters have
   declared finite domains, so a use that cannot match is an error when the
   grammar is read, not a failed parse.  If hbnf takes (1), it should check
   the arguments the same way, with the helpful errors it already promises.
   *Named domains (the metarule, `::=`; a hyperrule is `:=`, an ordinary rule `=`) are built too: a finite set of
   numbers or words, joined from other domains, never one that names itself.*
   *Built with (1): a number outside its domain, a word not in its list, the wrong number of
   arguments, a rule that is not parameterised, and a chain that needs ever bigger instances of
   itself are errors when the grammar is read, each naming the chain of uses.*

**Efficiency.**  The three above cost nothing the grammar does not already pay.
(1) is expansion before the parser is generated: the parser it produces is the
one you would have written by hand, with no runtime parameter passing; the cost
is generator time and parser size, bounded by sharing identical instances and
building only the ones used (17 precedence levels are 17 rules, as by hand).
(2) is a slice of the input (a pointer and a length, no copy) kept in the parse
state and compared with `memcmp` where it is repeated; a backtrack restores it
with the position, and only a token that holds a back-reference leaves the
table-driven scanner for a short loop, as a scanner action would, so only
grammars that use it pay.  It does mean a memoized result must be keyed by the
captured text or not memoized (the same hazard as decision 13's context).
(3) is generation time only.  Because each expands into an ordinary grammar,
the first-match rule, the union analysis and the detected forks of decision 14
run unchanged.  Full W-grammars are undecidable only in the worst case, not in
the grammars people write, so how far past this subset hbnf can go without
losing efficiency is a question for the ALGOL 68 step (parsing the Report's own
W-grammar), not something to rule out here; the subset above is decidable by
construction and costs nothing, which is why it comes first.

What not to take yet: unrestricted metanotions and open-ended hyperrule families
(they can fail to terminate in the worst case, and the Report's own grammar was
written to be read by a human, not run; whether the practical ones can be run is
the ALGOL 68 experiment); the notation (hyperrule
names with spaces and consistent substitution across a whole rule is a reading
puzzle, against hbnf's "not surprising to a BNF user" bar); symbol-spelling
rules (`letter a symbol`).  Affix/inherited attributes as the answer to context
were weighed in decision 13 and stay a second choice to persistent context.

## What hbnf could learn

In order of how much it would change hbnf.

1. **Hooks in any language, and a portable default for the common case.**  In
   all three, the code that customizes the system is written in the system's own
   language: META II's output operators, IMP72's quoted expressions, SNOBOL4's
   `DEFINE`d functions.  hbnf deliberately does not pick one.  A hook is code in
   whatever language a backend targets, and that is open-ended: C, Rust, Zig and
   Ada today; D, Fortran, Free Pascal, Nim, Odin, Objective-C, ATS and V planned
   next, then the garbage-collected languages (`COMPILER-COMPILER.md`, "Backend
   spectrum"); and nothing stops a backend for assembly, or past it for raw
   machine-code bytes.  Assembly is what META II emitted, and what makes a
   compiler-compiler a *true* metacompiler is that its product is a translator to
   a machine's own language, whose hooks can be that language's instructions.
   Machine code is the limiting case, and it joins up with the planned binary
   layer (`OCTET` is a byte; bit-precise syntax is planned): a grammar that can
   read bytes by their fields can have an emitter that writes them, so the same
   notation describes an instruction encoding going in and coming out.  The cost of that openness is that a hook is written
   once per backend (decision 13: "`%where Rust { }`"), so a grammar that needs a
   predicate in four languages is four programs.  IMP72 shows what would cut that
   cost without closing the door: most semantics were a *template* in the language
   being compiled, with holes for the arguments, and compiler subroutines were the
   exception ("as a last resort").  A small portable action and emit notation,
   compiled to every backend, with host-language code (assembly included) as the
   escape hatch, would make `%action`, `%where` and `%emit` portable by default
   without taking away the freedom to drop to the machine.

2. **Output templates with hygienic fresh names.**  `*1`/`*2` in META II and
   `LOCAL R IN "..."` in IMP72 exist because generating code needs labels and
   temporaries that cannot collide.  `%emit{ }` is planned without it.  A
   `gensym`-like facility in the emit language (unique per node and per use) is
   the smallest thing that makes it able to write a loop or a conditional.

3. **User-defined syntactic sugar, by rewriting.**  IMP72's `ABS ( <A> )` defined
   as an expression over existing syntax is a *syntactic macro*: a new notation
   whose meaning is a rewrite into the old one.  hbnf already has a few built-in
   sugars it compiles away (`n#m`, `#x`, `a - b`, prefix factoring) and the
   `macros` directive for configs.  A grammar-level `=>` that rewrites a matched
   phrase into another phrase of the same grammar would let authors define such
   sugar themselves, and hbnf's own would become instances of it.  This is the
   "mechanically rewrite, don't make people rewrite" principle, made available to
   grammar authors.

4. **Cases on the shape of what matched.**  IMP72's conditional semantics
   (§2.3.3.2: `NOT` applied to a constant is folded by a compile-time routine, any
   other `NOT` generates an instruction) pick different semantics when the matched
   thing is a constant, a register, a variable, or has a particular constant value.  That is tree-pattern matching
   for code generation, and it is why a language implemented this way could
   generate good code for special cases without touching the syntax.  hbnf has a
   typed tree and `kind` tags; an `%action` (or `%emit`) written as *cases on
   node shapes* would give constant folding and peephole rules a home.  IMP72's
   own warning applies: an inner node must already be reduced to one object for a
   case to see it (§2.3.5), so the order in which actions run is part of the
   contract.

5. **One semantics, many productions.**  IMP72's `CASE (...) OF SHIFTS`
   (§2.3.3.3) lumps productions that differ only in constants under one general
   semantics with a parameter list (`PAR(0)`).  hbnf's equivalent is an action
   shared by several rules, with arguments: `%action binop("ADD")`.  Small, and it
   removes the copy-and-edit that makes four-backend hooks expensive.

6. **Say when something is expensive, as the parser runs.**  IMP72 reports, at the
   foot of every listing, the parser's maximum space, and tells the author what it
   means: a production that must read far before it can choose "may require
   inordinate amounts of space and time" (§2.3.5).  hbnf already finds this
   statically (a union whose branches share unbounded text is refused with a
   witness), which is better than IMP72's runtime symptom.  The cheap addition is
   the runtime one for what static analysis cannot see: a `--stats` run reporting
   backtracks and deepest lookahead per rule.

7. **Self-hosting as the test.**  META II compiles itself and IMP72 compiles
   itself; both define their own syntax in their own notation.  hbnf's notation
   is read by Ada code.  A grammar of hbnf's notation, in hbnf, whose generated
   parser reads the grammars hbnf is built from, would be the strongest
   conformance test the project could have, and it is what makes a system a
   meta-compiler in the original sense.

## What not to take

- **IMP72's ambiguity.**  Carrying every parse and picking by rule is the opposite
  of hbnf's guarantee that a grammar is never ambiguous and that a choice that
  cannot be ordered is refused with a witness.  IMP72's own advice
  ("Peaceful Co-Existence", §2.3.5) is a list of ways to write syntax so the
  ambiguity does not bite, which is the discipline hbnf makes mechanical.
- **SNOBOL4's unrestricted backtracking with side effects.**  Its manual spends
  pages on immediate assignment's surprises.  `%where` should stay the exception,
  with its running order stated, as decision 13 already does.
- **META II's hand factoring.**  "Backup is avoided by the extensive use of
  factoring" is a burden placed on the author; hbnf's prefix factoring and union
  ordering take it back.

## Open questions this raises

- Is the portable notation (lesson 1) a separate language, or hbnf's own
  notation extended with expressions, and is an assembly backend the first test
  of "any language" (it has no runtime to lean on, only what `%emit` writes)?  IMP72 chose the object language itself;
  that is the cheapest and the one that keeps a grammar a single file.
- Should `%scan` for a body-less rule and for a rule that has a body be spelled
  differently (code with no grammar behind it, and code the grammar also defines)?  Today they are one directive.
- If grammars can define rewrites (lesson 3), the exception `a - b`, `n#m` and the
  rest of hbnf's sugar could be defined in the standard library of the notation
  and not in the Ada reader.  That is an invitation to bootstrap, and a risk to
  error messages, which currently speak the sugar's own language.

## Could hbnf be the minimal compiler IMP72 grew from?

The question is whether hbnf could play the part of IMP72's bootstrap kernel and
grow into the full compiler from the DECUS material.  The tape and the manual
answer most of it.

### What the material contains

DECUS program 10-198 is on the library tape 10-LIB-3, and the PDP-10 archive's
[extracted listing](https://pdp-10.trailing-edge.com/decuslib10-03/index.html)
(directory `43,50306`) has all of it as text and binary: 22 compiler modules as
`.imc` source (about 44,000 36-bit words, roughly 220 KB, on the order of five
thousand lines of IMP), `syntax.imc`, `impsyn.imc`, `rsyn.imc`, the compiler
binary (`imp.low`, `imp.shr`), the I/O library (`implib.lib`, with
`fortio.mac`, which is PDP-10 assembler), and `imp.rno`, the manual's source.
The archive states that use of files from the DECUS tapes is unrestricted.  The
PDF of the manual used elsewhere in this note is a scan of the same submission;
it does *not* contain the compiler source, only the manual and unrelated
documents, so the tape is the source of the code.

### How IMP72 actually bootstraps (manual §3.4, §4.4, and the code)

IMP72 does not start from a minimal compiler and grow.  It starts from a
*minimal syntax reader* and a long file:

1. **`rsyn.imc`, 327 lines of IMP, is the kernel.**  It has one syntax built in:
   `<CLASS> ::= element element <CLASS,name> 'c' ... ::= ( routine, routine ) ;`,
   a production whose semantics is a comma-separated list of semantic-routine
   names, ended by `;`, the whole file by `%`.  It registers fourteen routines
   (`SYNT`, `SYTRM`, `SYNTS`, `SYNTAX`, `SEMR`, `SEMP`, `SEMANTICS`, `QUOSEM`,
   `EQUOSE`, `DEFCASE`, `SEMBIT`, `VALU`, `REPVAL`, `ENSTACK`) that enter a
   production into the syntax graph and compile its semantic part.  Its own
   header apologises for the coding.
2. **`syntax.imc`, 450 lines, 177 syntax statements in 30 classes (and the lexer's two, `NAM` and `SYM`), is the
   language.**  Its first thirty lines are written in the kernel's tiny notation
   and define the *full* syntax-statement notation (quoted semantics, `ELSE`,
   `CASE`, `PRIORITY`, `VALUE`, `LOCAL`).  The rest, now read with that fuller
   notation, defines the base language: expressions, declarations, `GO TO`,
   conditionals, loops, subroutine calls, bytes and registers, and a few
   DECsystem-10 synonyms.  Most semantics are calls to semantic routines
   (`DEWOP(254B,0,A)` emits the PDP-10 opcode `JRST`); others are quoted IMP
   templates.
3. **The compiler is then saved as a core image.**  Everything but lexical
   conventions and the kernel's notation comes from `syntax.imc` and the
   semantic routines it names.

What it does not do is compile those semantic routines itself from nothing.  The
routines (`code`, `impsem`, `cotree`, `entree`, `dosem`, `parse`, `graph`,
`ercor`, `amod`, `rmod`, `omod`, ...) are IMP source, compiled with the syntax in
`impsyn.imc` by an IMP72 compiler that already exists; §3.4's "from scratch"
procedure begins with "make a version of the compiler" from a running one.  The
tape's `imp.low` and `imp.shr` are that running compiler, as a PDP-10 binary.
So a true bootstrap from nothing has to supply, outside the tape, what the first
IMP compiler was.

### What hbnf has, and what it would take

| IMP72 piece | what it does | hbnf today |
|---|---|---|
| `rsyn`'s notation, and `syntax.imc`'s statements | `<C> ::= elements ::= semantics ;` | a reader for BNF, EBNF, ABNF and YBNF dialects: a dialect `imp72` is small |
| `parse`, `graph`, `ercor` | Irons's bottom-up parser carrying every parse; ambiguity resolved by rule; syntax errors repaired | a generated ordered-choice parser; ambiguity refused with a witness; no repair |
| `rsyn`/`graph` adding productions at run time | a program extends its own syntax and uses it at once | grammar fixed when the parser is generated |
| `cotree`, `entree`, `dosem`, `stack` | semantics held back until context decides the special case; quoted semantics re-fed to the parser as a rewrite | `%action` once, after the parse |
| `code*`, `impsem`, `amod`, `rmod`, `omod` | PDP-10 code generation, register allocation, DEC relocatable object files | none |
| `implib`, `fortio.mac` | runtime, in IMP and in assembler | none |

Three routes, from cheapest.

**1. Read the language as data.**  Add a reader for the kernel's notation and
load `syntax.imc` as an hbnf grammar, semantic parts kept as text.  Nothing in
hbnf's design rules this out, it is small, and it answers the question that
decides everything else: how ambiguous is IMP72's syntax?  IMP72 leans on
ambiguity on purpose (no reserved words; `ABS(<A>)` both a defined construct and
a call), and resolves it with three rules (§2.3.4).  hbnf's union checker reports
every ambiguity it finds, with a witness.  A count of those, and whether ordered
choice with first-match-wins can be made to give IMP72's resolution, says whether
a *static* IMP grammar is enough.

**2. Translate the compiler, not bootstrap it.**  If route 1 says the static
grammar is workable, the compiler's own sources only use the syntax in
`syntax.imc` and `impsyn.imc`, both finite.  An IMP front end generated by hbnf,
with emit templates, translating `.imc` to C over a small 36-bit-word runtime
(half-word fields `<L>`/`<R>`, byte pointers, registers, `COMMON`, `REMOTE`),
would reproduce the whole IMP72 compiler on a modern machine, emitting PDP-10
`.REL` files, with no PDP-10 binary needed to build it.  The tape is the test
corpus (the way `corpus/rfc/` is for ABNF): every `.imc` file must parse, and
the translated compiler must compile the compiler's sources.  Validation against
the original needs the original running, which means a PDP-10 emulator (SIMH)
and a TOPS-10 or TENEX image from the same archive, and the comparison is of
behaviour, since object files will differ in incidental ways.

**3. Be the kernel.**  The literal reading of the question: hbnf *is* `rsyn` and
the machinery behind it, and IMP72 grows out of it.  That is the large one, and
it is the one that exercises every lesson above.  It needs a second engine
inside hbnf: a run-time grammar interpreter with an add-production operation, a
general parser that carries parses and resolves ambiguity by rule (in an explicit
dialect, so the main guarantee of ordered choice stays where it is), the
object-stack and special-case matching of `cotree`/`entree`, quoted semantics as
rewriting, `PRIORITY`/`VALUE`/`CASE`, and a place to put the semantic routines.
The modules that do this in IMP72 (`parse`, `graph`, `ercor`, `cotree`, `entree`,
`dosem`, `stack`, `rsyn`, `lex`, `dir`, `free`) are about 22,000 words, a few
thousand lines of IMP: the size of the job is moderate, not huge, and it is the
design that is new.  The back end (`code`, `impsem`, `amod`, `rmod`, `omod`) is
a second job of about the same size and is PDP-10 specific; `syntax.imc` embeds
PDP-10 opcodes in its semantics, so it does not retarget for free.

### Translate `rsyn` and run from there

This is route 2 started at the kernel, and the size of it was measured on the
tape's sources (a name-based call closure; it over-counts a little, since a name
in an error path counts, and it counts code lines with comments and blanks
removed).  The whole compiler is 290 subroutines and about 3,400 lines of IMP.

| stage | what runs | subroutines | code lines | modules |
|---|---|---:|---:|---|
| 1 | `rsyn` alone: the built-in notation, enough to read the first thirty lines of `syntax.imc` | 83 | about 900 | `rsyn`, `free`, `dosem`, `dir`, `stack`, `entree`, `graph` (3), `lex` (1), and a few routines each of `impsem`, `impm`, `code`, `cotree` |
| 2 | the rest of the front half, enough to read all of `syntax.imc` and `impsyn.imc` | 178 | about 2,200 | adds `parse` and `cotree`; the driver `impm` pulls in much of the back end, so this over-counts |
| all | the compiler | 290 | about 3,400 | adds the code generator, register and assembly passes |

So the kernel is not large, and the manual's own design helps: §4 says there is
"no common data base in the compiler" and that modules reach each other's data
by subroutine calls.  That makes the system replaceable one module at a time: run
`rsyn` translated; later replace `parse` and `graph` with an hbnf-generated
engine behind the same calls; keep the rest until it is worth replacing.

What translating it needs:

1. **An IMP front end.**  To translate IMP source one must parse IMP source.  That
   is the static grammar of route 1, read from `syntax.imc`'s base-language
   statements plus `impsyn.imc`, which the compiler's own sources use.  The
   syntax statements' *semantic parts* produce PDP-10 code; for a C target each
   construct needs an emit written by hand, which for the base language is a
   couple of hundred productions of which a smaller core is used in these
   subroutines.
2. **A 36-bit word model in C.**  Half-word fields (`<L>`, `<R>`), byte pointers,
   `REGISTER`/`SCRATCH` declarations, `COMMON` and `REMOTE`, `LONG` arrays, and
   the compiler's habit of passing directory indices as negative numbers.
3. **A small replacement for the I/O library.**  `rsyn` reads through `lex`, which
   reads through `implib` (IMP and `fortio.mac`, PDP-10 assembler); the reading
   and printing routines are short (`tbin`, `tprin`, `traed`).
4. **Care about PDP-10 tricks.**  They are few and local.  `rsyn` itself checks
   its own code size with `LOC(QUIT)-LOC(RSYNLO)<280`, a comparison of code
   addresses, and exits through a monitor call (`CALLI(12B,0)`).  These are
   stubbed or replaced, not translated.

The check is built in: the kernel either reads the first thirty lines without
`?ERROR IN INITIAL SYNTAX`, or it does not, and the manual's own message is
`SYNTAX BOOTSTRAPPED` once it has.  Stage 2 is checked by finishing `syntax.imc`
and `impsyn.imc` and then compiling a small IMP program; the fixed-point check
(the compiler compiling its own sources twice to the same output) is last.

The translator is where hbnf comes in first: the generated IMP parser and its
emit templates are the tool.  Running the translated `rsyn` is the kernel.  The
two meet when the translated parser is replaced by a generated one.

### What not to expect

- No route here starts from nothing.  Route 2 starts from the tape's sources and
  hbnf's front end; route 3 from the sources and a kernel that hbnf would have to
  grow.  Only the original has a binary that compiled itself.
- A match with the original is behavioural.  What can be checked exactly is
  that the compiler compiles its own sources to a fixed point: the translated
  compiler's output compiling the same sources again gives the same output.
- Error correction (`ercor`, after Irons 1963) is a research-grade piece and can
  wait; the language does not need it to be correct on correct programs.

### Where to start

Route 1, as a measurement: fetch the files from the archive into a cache pinned by
hash (as `bench/` does for the ntpd sources, and for the same reason: the tape is
not ours to commit), read `syntax.imc` with a small `dialect imp72`, and report
the classes, the productions, and the ambiguities hbnf finds.  It is the only
step whose result changes what the next one is.

## IMP72 and Ada, both from ALGOL

Ada is hbnf's implementation language and one of its four backends, and IMP is
the language of the compiler in `corpus/imp72/`.  Both are ALGOL's descendants
by different roads: Ada through Pascal, with ALGOL 68's influence on its
types; IMP through Irons, whose syntax-directed compiler for ALGOL 60 (1961) is
where his line of work begins.  The IMP72 manual describes the language as "a
simple higher-level language intended primarily for system programming",
"roughly at the level of FORTRAN II" in power with "a bit like ALGOL in
flavor".  Same family, opposite bets.  What follows is read from the manual
(section numbers are its), and the Ada side is the language as published.

| | IMP72 | Ada |
|---|---|---|
| **Aim** | system programming on one machine, the PDP-10, with all its registers and instructions in reach (§1.1) | systems and embedded programming, portable across machines, checked at compile time |
| **Statements** | none: "no distinction is made between expressions and statements", so `;` is a binary operator whose value is its second operand, and parentheses group (§2.1.2) | statements and expressions are separate; `;` ends a statement |
| **Reserved words** | none (§1.1, item 4); a word is a keyword where a syntax statement says so | about seventy |
| **Types** | integer and real only, plus what the programmer does with words; variables need no declaration unless they are arrays (§1.3) | strong, declared, user-defined: records, enumerations, ranges, access types, tagged types, generics |
| **Scope** | one global scope for a compilation; `LOCAL` renames a variable to a unique name within one subroutine (§2.1.4) | nested blocks, packages, private parts; scope is lexical and checked |
| **Precedence** | all binary operators equal, evaluated right to left, "as in APL"; relations after those (§2.2) | the conventional levels |
| **Control** | `A=>B ELSE C`, `A FOR I IN 0,1,N`, `WHILE`, `GO TO`; labels are variables and can be stored into: `T:G0 TO T` writes an instruction into the next word (§2.1.3) | `if`, `case`, three loops, `exit`, `goto`, exceptions |
| **Calling** | FORTRAN's convention, so IMP and FORTRAN call each other (§2.1.4) | its own, with `in`, `out` and `in out` modes, and `pragma Import` with `Convention => Fortran` and others |
| **Machine access** | registers `0R`..`15R` are names; "if you write down an expression which can be evaluated with a single instruction, that instruction will almost always be used" (§2.1.3); instructions the compiler lacks are added as syntax | `System.Machine_Code` for inline assembly, `Address` clauses, representation clauses; the compiler is not required to emit any particular instruction |
| **Bit fields** | `A<B,C>`: B bits, C bits from the right of word A, an expression either side, usable on the left of an assignment; `A<L>`, `A<R>` the half words; `BYTEP` makes a byte pointer that can be stepped (§2.2.6) | a record representation clause: `for R use record F at 0 range 3 .. 7; end record;`, with `Bit_Order` and `Scalar_Storage_Order`; the compiler generates every access |
| **Extension** | the language is extended by the program: syntax statements add productions with their semantics, mid-file (§2.3) | generics, overloading, user-defined operators, child packages, pragmas; the grammar is fixed |
| **Special cases** | stated by the programmer as conditional semantics (`A+1` as a register increment) (§2.3.3.2) | left to the optimizer; `pragma Inline` and instantiation are the programmer's levers |
| **Compile-time check** | little: a mistaken program compiles | the point of the language |
| **Error handling** | none in the language; syntax errors are repaired by the compiler and compilation goes on (§4.1) | exceptions; the compiler refuses what is wrong |

The two answer one question, how do you get machine-level control without
writing assembler, in opposite directions.

- **Ada puts the knowledge in the type.**  The layout of a record is declared
  once, by a representation clause, and every access the compiler writes follows
  it; a mistake is a compile error.  The cost is a fixed language and a compiler
  that must be taught each machine.
- **IMP72 puts the knowledge in the grammar.**  There are almost no types, so
  the programmer states the field at every access (`A<9,I>`), and when the
  compiler would do something wasteful the programmer writes a syntax statement
  that does better.  The cost is that nothing is checked; the gain is that the
  compiler can be taught anything, by the person using it, without modifying it.

## What this says for hbnf

1. **The bit-field notation is an old, good one, and a design question.**  hbnf's
   wire layer (step 7b: widths, signedness, endianness, bit-precise syntax, an
   `OCTET` that is a byte) needs a way to say "B bits at C".  IMP72's `A<B,C>` is
   that, imperative and per access.  Ada's representation clause is that,
   declarative and per type.  A grammar is declarative, so Ada's shape is the
   closer fit: a rule says its layout once, and both directions, reading and
   writing, follow from it.  What IMP72 adds that Ada does not is that its B and
   C may be *expressions*: a length field read earlier in the same record can
   say how wide the next field is, which binary formats do constantly (length
   prefixed fields, TLV).  The wire layer should allow it, and `%where`-style
   code is the wrong place for it.
2. **Right-to-left evaluation of equal precedence is IMP72's, and a trap.**  A
   grammar that accepts `A*B+C` must say which way it nests, and hbnf's ordered
   choice with left-recursive loops gives left to right.  A grammar for IMP in
   hbnf has to reproduce the right-to-left rule, and `syntax.imc` does it by
   writing `<EXP> ::= <ATOM,A> + <EXP,B>`, the right operand a whole `<EXP>`.
3. **"No reserved words" is a lexer property, and hbnf has the option already.**
   An identifier is a keyword only where a rule says so, which is what hbnf's
   `keywords { }` table opts into and what a grammar without one already does.
   Ada's reserved words, by contrast, are the reason the generated Ada needs the
   prefix hbnf now puts on every rule.
4. **IMP is not a translation target for the Ada backend.**  A flat global
   memory of 36-bit words, labels that are variables, instruction words stored by
   the program, and registers named in expressions have no counterpart in Ada's
   type model.  Translating the IMP72 compiler's own source is best done to C
   over a small word-model runtime (see the section above), where a word is an
   integer and a label is a number, and Ada stays what it is for hbnf: the
   language its compiler is written in and a typed target for generated parsers.
