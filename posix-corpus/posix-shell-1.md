# POSIX shell grammar: `posix-shell-1`

`posix-shell-1.y` is the yacc grammar of the POSIX shell command language, as the
standard prints it.

## Source and attribution

- **Standard:** IEEE Std 1003.1-2017 (Revision of IEEE Std 1003.1-2008), The
  Open Group Base Specifications Issue 7, 2018 edition.
- **Section:** Shell Command Language, 2.10.2 Shell Grammar Rules (the
  grammar after 2.10.1 Shell Grammar Lexical Conventions).
- **Authoritative text:**
  <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_10>
  (the section is `tag_18_10_02` on that page).
- **Copyright:** (c) 2001-2018 IEEE and The Open Group, All Rights Reserved.
  The grammar is reproduced here, unchanged, as test data for a parser
  generator and in order to point at the standard; the standard, not this file,
  is the authority.  Where this file and the page disagree, the page is right.
- **How it was taken:** by script from the page's HTML (the two `<pre>` blocks
  of the section, tags removed, character entities decoded), not retyped.  The
  five-line comment at the top of the file is the only addition.

## What hbnf says to it

With `dialect ybnf` it reads, and says, once for each of the thirty-odd
tokens, what to write:

    in rule `and_or`: `AND_IF` is declared `%token` (line 24) but nothing defines it
      yacc leaves a token to its lexer.  hbnf reads characters, so a token is a
      rule: the standard spells it `&&`, so write `AND_IF = "&&"`

The spellings are the ones the standard gives in the comment under each
`%token` line (`DLESS` is `<<`, `Lbrace` is `{`, `If` is `if`).  The classes
(`WORD`, `NAME`, `ASSIGNMENT_WORD`, `IO_NUMBER`, `NEWLINE`) have none and are
said to be a class of text.

## What is not done yet

A working `posix-shell-1.hbnf` needs, beyond defining the tokens:

- **Reserved words (rules 1 and 7a).**  A command name is a `WORD` that is not
  a reserved word.  Without that, `if` is an ordinary command and the
  grammar accepts what it should refuse.  That is the exception `a - b`
  (ISO 14977's), for character rules.
- **`IO_NUMBER`** is digits only when a redirection follows at once.
- **Here-documents** (`<<`) read lines after the command.
- **Quoting and expansion** (`'..'`, `".."`, `$(..)`, `${..}`) nest.

The plan is RFCPLAN.md's POSIX BNF section.
