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

## Status: paused

Saved on 2026-10-17 so the sources are in the repository.  Nothing has been run
through hbnf yet.  The order is the same as for the other corpora: they resume when
hbnf is feature complete (`RFCPLAN.md`, "Order").  What reading it needs:

- `dialect bnf` reads the `<name> ::= a | b` form directly.
- **Stropping.**  The report's keywords are underlined or bold, a typographic
  distinction a text file cannot have.  `syntax.txt` quotes them; a test program
  would use the same.  The grammar has no reserved words in the sense hbnf's
  keyword rules mean, because `'BEGIN'` is a symbol, not an identifier.
- **`comment`.**  The report's rules for comments (a comment is text up to the next
  `;`, and `end` is followed by any text up to `end`, `else` or `;`) are a lexical
  matter written as productions.
- The dangling `else` is settled by the structure of the grammar (an `if` statement
  may not be the statement after `then`), so it should need nothing beyond ordered
  choice; to be checked when it is run.
- **Test programs.**  The report's own examples of procedure declarations
  (Euler, Innerproduct and the rest), and Knuth's "man or boy" program.
