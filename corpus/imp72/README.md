# IMP72 corpus

The source of the IMP72 compiler, as distributed through the DECUS library: a
real metacompiler, written in its own language, that bootstraps from a small
syntax reader (`rsyn.imc`) and a file that defines the language (`syntax.imc`).
It is test data for hbnf in the way `corpus/rfc/` and `corpus/posix/` are, and
the subject of `METACOMPILERS.md`, which compares it with META II, SNOBOL4 and
hbnf and asks what it would take for hbnf to play the part of its kernel.

## Layout

    corpus/imp72/
      README.md        this file
      SHA256SUMS       the hash of every file in tape/, as taken
      tape/            the files of DECUS 10-198, unchanged
      (later)          imp72.hbnf, the syntax statements read as a grammar,
                       and what hbnf says to them

`tape/` holds the 30 text files of the program (`cd tape && sha256sum -c
../SHA256SUMS`).  They are byte-for-byte what the archive serves, including the
DEC-10 text conventions (CRLF line ends, upper case):

| files | what |
|---|---|
| `syntax.imc` | the syntax and semantics of the language, in syntax statements: 177 statements in 30 classes, as `tools/imp72_to_hbnf.py` counts them |
| `impsyn.imc` | the extra syntax the compiler's own sources are written with |
| `rsyn.imc` | the bootstrap: a reader for a tiny built-in syntax-statement notation, and the fourteen routines that enter productions into the syntax graph |
| `lex`, `parse`, `graph`, `ercor` | input and lexical analysis; Irons's parser; the syntax graph; error repair and ambiguity |
| `cotree`, `entree`, `dosem`, `stack` | the code-generation tree and special-case matching; semantics; the semantic stack |
| `impsem`, `impm`, `dir`, `free`, `debug` | machine-independent semantic routines; the driver; the directory; free storage; debugging |
| `code`, `code2`, `code3`, `amod`, `rmod`, `omod` | PDP-10 code generation, assembly, register allocation, relocatable object output |
| `tbin.iml`, `tprin.iml`, `traed.iml`, `fortio.mac`, `fortio.hlp` | the I/O library: IMP and PDP-10 assembler |
| `imp.rno` | the source of the reference manual (RUNOFF) |
| `r.cmd`, `198.inf` | the loader command file; the tape's one-line description |

The binaries on the tape (`imp.low`, `imp.shr`, `implib.lib`: the compiler and
the library, as PDP-10 memory images) are not here.  They are not text, hbnf has
no use for them yet, and the archive keeps them (see below).

## Source and attribution

- **Program:** DECUS program 10-198a, *IMP - PDP-10 IMP72 Compiler, Version
  1.5*, October 3, 1973.  **Author:** Walter Bilofsky, Yale University,
  Department of Computer Science.  **Submitted by:** Sonya Shapiro, Bolt Beranek
  and Newman, Inc.  Source language: IMP72.
- **The language:** IMP, by Edgar T. (Ned) Irons; the compiler is described in
  Bilofsky's *IMP72 Reference Manual* (DECUS 10-198, 1973; the scan at the
  [Computer History Museum](https://archive.computerhistory.org/resources/access/text/2024/09/102737513-05-0002-acc.pdf))
  and in "Syntax Extension and the IMP72 Programming Language" (SIGPLAN
  Notices, 1974).
- **Where these files came from:** the PDP-10 archive's extracted listing of the
  DECUS library tape 10-LIB-3, directory `[43,50306]`:
  <https://pdp-10.trailing-edge.com/decuslib10-03/index.html>.  A file is
  `https://pdp-10.trailing-edge.com/decuslib10-03/01/43,50306/<name>`.  The
  files carry the tape's own dates (September 1973).
- **Licence:** the archive states of the DECUS software that it "was donated by
  PDP-10 users to the DECUS library over the past 5 decades ... and was put into
  public domain at the time of donation", and that "use and distribution of files
  from the DECUS tapes is completely unrestricted" (<https://pdp-10.trailing-edge.com/>,
  as read 2026-10-17).  The manual's own notice says the same in other words: the
  program is a user contribution, offered as it is, with no warranty.  hbnf keeps
  the files unchanged, with this attribution, and points at the archive as the
  authority: where a file here and the archive disagree, the archive is right.

## Status: paused

Work on this corpus stopped on 2026-10-17, by decision, until hbnf is feature
complete (see `RFCPLAN.md`, "Order"; bit fields and the wire layer are step 7b).
What exists: the tape's files with their hashes, this note, and
`tools/imp72_to_hbnf.py`, which reads the syntax statements of `syntax.imc` and
`impsyn.imc` and writes an hbnf grammar of them.  A first run of that grammar
through hbnf stopped on things hbnf does not have yet (`~` negation for the
comment rule, decision 11; an alias of a list rule) and, before that, reported a
dozen unions whose alternatives it cannot tell apart, which is the ambiguity the
measurement was after.  The numbers are not final, and are not recorded here, for
that reason; the converter re-runs in a second.

## What it is for

`syntax.imc` is a compiler's language, defined by 177 productions each carrying
its semantics, in a notation (`<CLASS> ::= elements ::= semantics ;`) that is one
of the family hbnf reads.  Reading it is the first measurement in
`METACOMPILERS.md`: what hbnf makes of it, and in particular how many of its
ambiguities hbnf's union analysis finds, because IMP72's syntax is ambiguous on
purpose and resolved by rule.  The other modules are the IMP source that a
translator written with hbnf would have to read; each of them must parse, which
is the corpus's acceptance test in the way every `corpus/rfc` snippet's vectors
are.
