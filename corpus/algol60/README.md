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

`algol60.hbnf` is the Report's grammar in hbnf (written 2026-10-18 from
`syntax.txt`, with its transcription slips put right against the printed report),
and `tests/good/*.a60`, `tests/bad/*.a60` are programs the parser must accept and
refuse (Knuth's man-or-boy test among them).  `sh tests/algol60.sh` generates the
parser and runs them.  It uses the apostrophe stropping `'BEGIN'` of `syntax.txt`.

What reading it taught, in the order it happened:

- **Two generator bugs**, found by a real recursive grammar and fixed: the pass that
  decides which fields need their list heads repointed took exponential time on a
  grammar that refers back to itself through parentheses (`expr = primary "*"
  primary | primary`, `primary = ... "(" expr ")"`), and the repointing of a
  field that breaks a cycle passed the wrong kind of pointer.
- **One expression, not three.**  The Report writes arithmetic, Boolean and
  designational expressions as separate grammars, and `<assignment statement>`
  as two alternatives that differ only in which one follows.  Ordered choice,
  having matched the first, does not come back, so the Boolean case never parses.
  The grammar here has one expression of precedence levels (the types are for a
  checking pass) and a designational expression only after `GOTO` and in a switch.
- **A colon is not a `:=`.**  The Report's `:=` is one symbol; a label's colon is a
  colon that does not start one.  Written with the literal `":"`, a label matched
  the first character of `:=`, and because a statement may be empty `i := 1` read as
  the label `i` on an empty statement, and was never tried as an assignment.  The
  grammar puts the assignment first.  A "not followed by" test (`":" !"="`) would
  say it directly, and trying the next alternative after a later failure
  (RFCPLAN.md decision 14) would find it unaided; both are on the list for the
  W-grammar work.
- **Comments** are white space (`ws`), and the text after `END` is skipped to the
  next `;` or word symbol, as in section 2.3.

Not covered: `<code>` bodies, `^` and `E` spellings other than those in the file
header, and the standard procedures (`outreal` is just a name here).  The grammar
is a parser, not a checker: an undeclared name, a Boolean where a number is
needed and a label that is never defined are all accepted.
