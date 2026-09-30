# HBNF compiler-compiler notes

HBNF is not yacc with a prettier surface syntax.  Its useful combination is:

- EBNF/CFG-style productions for human-readable grammar structure;
- PEG-style ordered choice and recursive descent;
- direct left-recursive grammar forms without forcing authors to rewrite them;
- ABNF/RFC-style character and numeric terminals for exact protocol syntax;
- `%scan{}` for target-language scanner escape hatches;
- `%action{}` for target-language semantic construction.

The next layer makes those mechanisms compiler-quality rather than importing
legacy yacc interfaces: locations, named typed semantic values, explicit
parser/scanner context, scanner modes, input abstraction, recovery, and a
shared semantic IR should *surround* `%scan{}` and `%action{}`.  See
`RFCPLAN.md` §"Compiler-compiler completion criteria" and the Order steps 6–9.

## RFC copy-paste

An RFC's ABNF should compile almost verbatim.  Spelling variants (`::=`, `:=`
for `=`) are accepted silently — silence makes cut-and-paste easier.  Where
hbnf needs something different, the error names the RFC form and says how hbnf
spells it ("you wrote X; if you meant Y, hbnf spells it Z"), so a pasted RFC is
corrected by the messages, not by reading the manual.

## Non-goals

Do not add `yylval`, `$1`, `$$`, global `yyparse`, LR conflict declarations, or
GLR merely for compatibility.  They solve problems caused by yacc's LR
implementation rather than problems HBNF currently has.

## Invariant

Every unbounded repetition must make progress or terminate.  A nullable rule
may be repeated semantically, but the matcher/generator must stop when an
iteration leaves the input position unchanged.

## Backend contract

`HBNF_Match` and every generated backend are implementations of one language.
If a construct cannot be represented by a backend, reject it during schema
validation with a source-located diagnostic — never silently change its
meaning for one backend.

## Backend spectrum

Compiled today: **C** (pinned to C99, output also valid C++11+), **Rust**,
**Zig**, **Ada**.  Planned compiled targets: **D**, **Fortran**, **Free
Pascal**, **Nim**, **Odin**, **Objective-C**, **ATS**, **V**; then the GC
languages **Go**, **Java**, **JavaScript**, **Common Lisp**, **newLISP**.  A
separate C++ backend appears only if C++ needs more than an `extern "C"`
header guard.
