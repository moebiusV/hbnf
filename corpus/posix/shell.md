# The POSIX shell command language in hbnf

`shell.y` reads shell scripts with the grammar of POSIX.1-2017 section 2.10.2, the one in
`posix-shell-1.y` as the standard prints it and **included unchanged**, plus three small files:

| file | what |
|---|---|
| `shell-words.hbnf` | the tokens as rules of characters: operators, reserved words, `NAME`, `IO_NUMBER`, `ASSIGNMENT_WORD`, and `WORD` (quotes, escapes, `$name`, `${..}`, `$(..)`, `$((..))`, back-quotes), and `NEWLINE`, which carries the bodies of here-documents |
| `shell-fixes.hbnf` | what yacc's tables and lexer feedback settle, written out for a parser that takes the first alternative that matches: the white space (`ws`), `$( program )`, a reserved word is not a command name, and where one alternative is the front of another the longer one first |
| `shell.y` | the three together |

`check.c` is the driver `tests/posix.sh` builds: it reads each file named and says whether the
generated C parser accepts it.

## What it does today

- **Agrees with dash.**  Of the 581 shell scripts on the machine it was written on (`/etc/init.d`,
  `/usr/bin`, ...), 580 are accepted, as `dash -n` accepts them.  Of 1,692 mutations of them (a
  character, a line or a stray `fi` `;;` `)` quote removed or added) the grammar and `dash -n`
  agree on all but three.  `scripts/posix-scan.sh` repeats this on any machine.
- `tests/posix.sh` runs a small hand-written corpus, 31 good scripts and 25 bad ones, through the C, Rust,
  Zig and Ada parsers, and checks that dash gives the same verdicts.

## What it took

Pasted unchanged, the standard's grammar needed these, and hbnf's messages named the first of
them:

1. **Definitions for the `%token` names.**  `AND_IF = "&&"` and the rest.
2. **Names that differ only in case.**  The standard has a rule `name` and a token `NAME`, a rule
   `in` and a token `In`.  hbnf's names ignore case, so under a dialect with case-sensitive names the
   reader now calls the token `NAME-token`, `In-token`, and says so, instead of refusing.
3. **Reserved words by position** (rules 1 and 7a): `cmd_name = WORD - reserved`, the exception.  A
   word is reserved only when it is exactly the word, so `iffy` and `if/x` are words.
4. **Ordered choice.**  yacc's tables look ahead to choose between `compound_command` and
   `compound_command redirect_list`; hbnf takes the first that matches, so the longer is written first
   (`command`, `function_body`, `compound_list`, `else_part`, `case_item_ns`).
5. **`;` and `;;`, `&` and `&&`** are different tokens; a lone `;` is `SEMI`, `";" !";"` in a rule
   that skips nothing, so `; ;;` is a separator then a `;;`.
6. **Here-documents** (rule 3).  The body comes after the line, so `NEWLINE` is a scanner that looks
   back at the line it ends for each `<<` and `<<-` outside quotes, comments and `$(( ))` and takes the
   lines after it up to each delimiter, in order.  It is a scanner written once for each of the four
   backends, so all four read here-documents (`tests/posix.sh` runs the 56 files through each).  The same
   goes for the balanced parentheses of `$(( ))`.

A bug the grammar found: `$( program )` uses the root rule inside another rule, and freeing a failed
attempt at it freed the arena the parse was still using.  A root used as a field is now freed by its
`_fields` function.

## Not done

- **Alias substitution** (rule 10) rewrites the input before the parser sees it, and is out of scope.
- **Back-quotes** are matched, not parsed: a syntax error inside `` `...` `` is not found.
- **A line that begins inside a multi-line quotation** does not see a here-document on it.
- **Bytes that are not UTF-8** are not accepted (`~LF` matches code points).
- dash accepts a function body that is not a compound command (`f () g () { :; }`); POSIX does not,
  and the grammar follows POSIX.
