# ALGOL 60 corpus

The *Revised Report on the Algorithmic Language ALGOL 60* (Naur, ed., 1963), the
language definition in which Backus-Naur form first described a programming
language, and a BNF of it as one file.  Test data for hbnf in the way `corpus/rfc/`,
`corpus/posix/` and `corpus/imp72/` are, and for the same reason as the last:
Ned Irons wrote a syntax-directed compiler for ALGOL 60 in 1961, driven by the
grammar of the original report (*A syntax directed compiler for ALGOL 60*, CACM
4(1), 1961), and a grammar that is a compiler's whole front end is what hbnf is
meant to be able to hold.  See
`METACOMPILERS.md` for IMP and its descent from that work.

## Layout

    corpus/algol60/
      README.md        this file
      SHA256SUMS       the hash of each file, as taken
      report.htm       the Revised Report, as served (HTML, ISO-8859-1)
      syntax.txt       the report's syntax as one file of productions

`cd corpus/algol60 && sha256sum -c SHA256SUMS` checks them.

| file | what |
|---|---|
| `report.htm` | the whole report: the metalanguage (section 1.1), the syntax and semantics of sections 2 to 5, and the examples of procedure declarations.  The productions are inline as `<name> ::= ...` |
| `syntax.txt` | 108 productions, one rule to a line or two, with the keywords written in quotes (`'BEGIN'`, `'GOTO'`), which is a plain-text stropping.  The page that serves it says it was compiled from the report; it does not say by whom |

## Source and attribution

- **Report:** *Revised Report on the Algorithmic Language ALGOL 60*, edited by
  Peter Naur, with J. W. Backus, F. L. Bauer, J. Green, C. Katz, J. McCarthy,
  A. J. Perlis, H. Rutishauser, K. Samelson, B. Vauquois, J. H. Wegstein,
  A. van Wijngaarden and M. Woodger.  Numerische Mathematik 4 (1963) 420-453; also
  Communications of the ACM 6(1), 1963, and the Computer Journal.  The first ALGOL
  60 report (Communications of the ACM 3(5), 1960) is where BNF first appears.
- **These copies:** <https://www.masswerk.at/algol60/report.htm> and
  <https://www.masswerk.at/algol60/syntax.txt>, fetched 2026-10-17.  The text was
  typed in from the report by Erik Schoenfelder (Technical University of
  Braunschweig, October 1990, as a LaTeX-Info file), and converted to HTML by
  N. Landsteiner (mass:werk, February 1999).  Neither is the author, and both say
  so.
- **Permission:** the report ends with this note, quoted from the copy here:

  > Note. This report is published in Numerische Mathematik, in the Communications
  > of the ACM, and in the Journal of the British Computer Soc. Reproduction of
  > this report for any purpose is explicitly permitted; reference should be made
  > to this issue of Numerische Mathematik and to the respective issues of the
  > Communications and the Journal of the British Computer Soc. as the source.
  >
  > W. L. van der Poel (Chairman of Working Group 2.1 on Algol of the International
  > Federation for Information Processing), Technical University Delft

  hbnf keeps the files unchanged, with this attribution; where they and the
  printed report disagree, the printed report is right.

## Known flaws in the copies

The text is a transcription, and shows it.  Before the grammar here is treated as
the report's, check a production against a scan of the printed page.  Seen so far:
`<identifier> ::= letter> | ...` is missing a bracket; `<subscripted list>` is
referred to where the rule is named differently; the editor of the HTML marks
`<unlabelled block>` "missing in original paper".  `syntax.txt` is a separate
transcription and has not been compared with the report here.

## Status: in use (`tests/algol60.sh`)

`algol60.hbnf` is the language of the Report in hbnf, and it is meant to be read
as an example of how short and clear a grammar can be.  It is not a transliteration
of `syntax.txt`; that file is here to compare it against.

| | the Report's BNF (`syntax.txt`) | `algol60.hbnf` |
|---|---|---|
| rules / productions | 108 | 38 |
| code lines (no blanks or comments) | 117 | 65 |
| characters, without comments | 8,724 | 3,361 |

What hbnf let it say once instead of many times:

- **Lists** are `x *( "," x )`: the Report has a rule for each of the
  type list, array list, bound pair list, subscript list, identifier list, for
  list, switch list, actual and formal parameter lists.
- **A block is a compound statement with declarations in front**, so one rule,
  `"'BEGIN'" *( declaration ";" ) statement *( ";" statement ) "'END'"`, replaces
  the Report's block, block head, unlabelled block, compound statement,
  unlabelled compound and compound tail.
- **One expression.**  The Report writes arithmetic, Boolean and designational
  expressions as three grammars, and an assignment as two alternatives that differ
  only in which expression follows.  Which type a name has is for a checking pass
  (an AST walker), not for the parser, so there is one expression, with the
  Report's precedence levels, and a designational expression only where a `GOTO`
  or a switch takes one.
- **A label's colon is a colon that does not start a `:=`**: `label ":" !"="`.  The
  Report's `:=` is one symbol; the test (`!x`, lookahead) says so directly.
- **The characters** (`<letter>`, `<digit>`, identifier, number, string) use the RFC
  core rules and four short lines; `'COMMENT'` text is white space (`ws`), and the
  text after `'END'` up to a `;` or a word symbol is skipped (section 2.3).
- **No reserved words.**  The Report's word symbols are the quoted `'BEGIN'`,
  `'END'`, ... of `syntax.txt`'s stropping, so an identifier can be any word.

Programs in `tests/good` must be accepted and those in `tests/bad` refused (Knuth's
man-or-boy test is among the good ones; a nested `IF` in a `THEN` branch, a
declaration after a statement and an unbalanced parenthesis among the bad).
`sh tests/algol60.sh` generates the parser and runs them.  Not covered: `<code>`
bodies and the standard procedures (`outreal` is just a name here).  The grammar
is a parser, not a checker: an undeclared name, a Boolean where a number is
needed and a label never defined are all accepted.

Reading it also found and fixed two bugs in the generator that only a recursive
grammar of this size reaches (a pass that took exponential time through
`primary = ... "(" expression ")"`, and the wrong pointer for a field that breaks a
cycle).

## Checked against the Report

`sh tests/algol60-diff.sh` compares the grammar with the Report's own BNF, read by an
Earley recognizer (`tests/algol60/reference.py`) that shares nothing with hbnf:

1. random sentences of the Report (up to 400 tokens) must all be accepted, and
2. random mutations of them (a token deleted, doubled, swapped, inserted, replaced)
   must get the same answer from both, except that hbnf may accept more.

The first run found a real bug (`IF b THEN L: FOR ...` was refused: a labelled `FOR`
directly after `THEN`) that eleven hand-written programs had missed, and a second
in the text after `END` (the Report skips any symbols there up to `;`, `END` or
`ELSE`; the first version stopped at the first keyword).  It also found three slips
in `syntax.txt` itself (a `;` missing from `<specification part>`, `letter>`, and a
stray `<factor>` alternative); the reference corrects them and `syntax.txt` is left
as downloaded.  After the fixes: 12,000 sentences accepted, 12,000 mutations,
11,976 the same answer, 24 accepted by hbnf only.  Every one of the 24 is expression
typing (`NOT 7`, `+ TRUE`, `TRUE < TRUE`, an arithmetic operand of `OR`,
a Boolean subscript), the difference chosen on purpose above: the grammar reads
one expression, and a later checking pass would apply the types.  One deliberate
difference remains: names, numbers and strings are tokens, so a blank ends a name.
The Report (2.3) gives blanks no significance, so `i b` would be the name `ib`; no
program written today relies on that, and the printer below needs a name to be one
token.  The reference reads tokens too, and its mutations skip adjacent names and
numbers.

## The pretty-printer

`pp.c` prints an ALGOL 60 program laid out, comments kept, and is the demonstration
that a consumer of the parser can make arbitrary output from the tree:

    hbnf corpus/algol60/algol60.hbnf --backend=c --writer --ast > a60.c
    cc -include a60.c -o pp corpus/algol60/pp.c
    ./pp [--functional] [--clang] program.a60 > pretty.a60     # -c: print it twice over, as a test

The parser reads the program into a tree, in which each `'COMMENT' ... ;` after `BEGIN`
or after a `;` is a node (`remark`, so a program is no longer allowed one anywhere
else; section 2.3 allows those two places), and the generated writer prints it back,
token by token.  `pp.c` supplies a function that is given each token or literal just
before it is written (and the name of each rule entered and left) and answers what goes
before it, and what is written in its place.  The grammar is not repeated in it.
`sh tests/algol60-pp.sh` prints every good program plain and `--functional`, reads
the result and prints it again (the same text), and compares `tests/pretty/layout.a60`
in the three styles with `layout.pretty`, `layout.functional` and `layout.clang`.

- **plain**: one statement to a line, `BEGIN` and `END` on lines of their own, the
  comments where they were.
- **`--functional`**: the style of the [Ada functional guidelines](https://moebiusv.github.io/ada-style-guidelines.html)
  as far as ALGOL 60 goes, by rewriting the tree before it is written, in ways that keep
  the meaning:
  rule 3, `IF c THEN x := a ELSE x := b` is `x := IF c THEN a ELSE b` (a simple variable
  on the left; a chain of `ELSE IF`s is one expression); rule 2/20, `BEGIN s END` with
  nothing but `s` in it is `s` (not when `s` is labelled, empty or conditional, so no
  `ELSE` changes hands and no label changes scope); one declaration per variable.  Not
  done, because ALGOL 60's call by name makes them change the meaning or because it has
  no construct for them: `VALUE` for parameters that are only read (Jensen's device
  needs the name), loops turned into recursion, constants (rule 1), `declare`
  expressions.
- **`--clang`**: braces for `BEGIN`/`END`, `=` for `:=`, `==` for `=`, `!=`, `&&`, `||`,
  `!`, `true`/`false`, `if (c)`, `c ? a : b` for a conditional expression,
  `for (i = 1 step 1 until n)`, the type words in lower case, `/* comments */`, a `;`
  before `}` and `else`.  It looks like C and is not C.

Comments are all kept: the `'COMMENT' ... ;` ones are tree nodes, and so is the text after
`END` (up to the next `;`, `END` or `ELSE`, which section 2.3 also treats as a comment),
as it was written, trimmed of the white space at its ends; `--clang` writes both as
`/* ... */`.  The line breaks inside a comment's text are kept as written.
A label in a `%label` that starts with a repeated or optional element (`[ "'OWN'" ] ...`)
used to be lost when the reader lifted that element into a rule of its own; it is kept
now.
