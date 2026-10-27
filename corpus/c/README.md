# C in HyperBNF

One grammar for each dialect of C that has a yacc grammar to be measured against, each a layer on the
last and each checked with the compiler of its own time:

| grammar | dialect | checked against |
|---|---|---|
| `c79.hbnf`, `c79-words.hbnf` | the C of UNIX/32V (1979), as `usr/src/cmd/mip/cgram.y` and `scan.c` read it: no prototypes, `void` or `const`; `=+`; an initializer without its `=` | `tests/c79.sh` (22 small files) and `scripts/c79-scan.sh`: the 32V source tree itself, **901 files preprocessed with the 32V headers, all accepted** (26 more need headers its build generates) |
| `c89.hbnf`, `c89-words.hbnf` | ISO C90, strictly | `tests/c89.sh` (25 files) against `gcc -std=c89 -pedantic-errors` |
| `c99.hbnf`, `c99-words.hbnf` | ISO C99, strictly (no GNU forms) | `tests/c99.sh` (23 files) against `gcc -std=c99 -pedantic-errors`, and `GRAMMAR=c99 STD=c99 scripts/c-scan.sh`: **1,549 of the 1,580 units gcc accepts**; the 31 refused are GNU spellings and one string of bytes that are not UTF-8 |
| `pcc99.hbnf`, `pcc99-words.hbnf` | the C PCC's `cgram.y` (NetBSD trunk) reads: C99, the C11 forms it has (`_Alignas`, `_Atomic`, `_Generic`, `_Static_assert`, `_Noreturn`, `_Thread_local`), and its subset of the GNU extensions; a type may stand as a call's argument | `tests/pcc.sh` (24 files, four kinds: good, bad, only PCC's grammar has, and GNU forms it lacks) and `GRAMMAR=pcc STD=gnu11 scripts/c-scan.sh`: 1,696 of the 1,953 units gcc 14 accepts; the 257 refused are what PCC's grammar has no production for (`__extension__` in glibc's headers, 132 of them; `__real__`, `__label__`, nested functions) and features newer than it |
| `gnu99.hbnf`, `gnu99-words.hbnf` | C99 and the GNU extensions GCC 4.0.4's bison grammar (`gcc/c-parse.in`) reads, which PCC's reads too; attributes and `asm` are in the grammar | `tests/gnu99.sh` (21 files) against `gcc -std=gnu99`, and `GRAMMAR=gnu99 STD=gnu99 scripts/c-scan.sh`: **1,883 of the 1,953 units gcc 14 accepts**; the 70 refused are features newer than GCC 4.0.4 (`_Float128`, `__int128`, `_Static_assert`, `[[ ]]` attributes) and one string of bytes that are not UTF-8 |
| `c11.hbnf`, `c-words.hbnf` | C11 and the GNU forms system headers use | below |

The notation comparison (`bench/notation.sh`) sets 32V's `cgram.y` against `c79`, PCC's against `pcc99` and
GCC 4.0.4's against `gnu99`.  C11, C17 and C23 are not in it: no yacc grammar of theirs exists to measure.

# C11 in HyperBNF

`c11.hbnf` is the grammar of ISO/IEC 9899:2011 Annex A with the standard's rule names, plus the GNU
forms system headers use; `c-words.hbnf` has the tokens as rules of characters.  It is the first piece
of a small C compiler written in HyperBNF (parse, check, lower, write), and it parses what a C preprocessor
produces: hbnf has no preprocessor, so the tools below use gcc's (`gcc -E -P`).

## Checked against gcc

- **`tests/c.sh`**: 57 small files, 38 that `gcc -fsyntax-only` accepts and 19 it refuses with a syntax
  error, all agreed on.  C backend only: the grammar uses the typedef context (`context types`,
  `%bind`, `%scope`, `?` and `?!`), which Rust, Zig and Ada do not have yet.
- **`scripts/c-corpus.sh`** fetches the C corpora the pcc size work used (lua, zlib, lz4, cJSON, chibicc,
  c-testsuite, mbedtls, BearSSL, the SQLite amalgamation and gcc's c-torture execute tests), preprocesses
  every file with `gcc -E`, keeps the ones `gcc -fsyntax-only` accepts, and runs the generated parser.  On
  the day it was run: **2,481 translation units (90 MB), the grammar accepts 2,478**.  The three it refuses
  are a string literal with bytes that are not UTF-8, `register void *p asm ("rbx")` and a decimal-float
  constant (`0.DD`).  By corpus: bearssl 317, c-testsuite 220, lua 40, mbedtls 177, zlib 37, lz4 48, cJSON
  35, chibicc 18, sqlite 1, c-torture 1,588.  (The original pcc work used 900 files that pcc, clang and
  gcc all compiled; those lists are not on this machine, so this is the same projects, regenerated, and
  all the files gcc accepts.)
- **`scripts/c-scan.sh DIR...`**: the same over any directory of sources.  587 units of the prebsd checkouts
  and pcc's own sources (60 MB) and 426 of SIMH (43 MB) are also all accepted.  On 204 mutations of the SIMH
  units (a character, a line or a stray token removed or added), the grammar and gcc agree on every one whose
  gcc error is a syntax error (139 of 204; the rest are type errors, which a grammar does not check).
- Speed, unoptimised: 15 MB of preprocessed C in 2.3 s, building the whole typed tree, against 1.6 s for
  `gcc -fsyntax-only` (which also does semantic analysis).  The profile says where it goes: a typedef
  name is looked for 28 million times in 40 files, because every statement tries a declaration first,
  and each try scans the same word again.

## How it is written

- **Typedefs.**  `typedef-name = known-type ?! vars`, `known-type = identifier ? types`: an identifier
  is a type if a typedef declarator has added it to the context `types`, and a variable if a declarator
  has since added it to `vars` (`int f(instr *instr)`).  A typedef declarator is `identifier %bind types
  += identifier`; a block, a function and a `for` are `%scope`s, so what they bind ends with them.
  `variable-name = identifier ?! types | identifier ? vars` keeps a typedef name from being a variable.
- **Ordered choice without reading twice.**  `assignment-expression = conditional-expression [
  assignment-operator assignment-expression ]` (the standard has `unary-expression assignment-operator
  assignment-expression | conditional-expression`, which reads the left side twice), and likewise for
  `external-declaration` and the specifiers.  The tree has an optional field where the standard has an
  alternative.
- **The expression levels are the standard's nested rules**, seventeen of them.  Nothing was wrong with
  that for correctness; what it costs is in the speed above, and the `operators { }` sugar discussed in
  `RFCPLAN.md` is the way to measure whether it is worth removing.
- **White space is one scanner** (`ws`), written once for each backend: blanks, comments, `#pragma` and
  `# line` (what the preprocessor leaves), and the GNU forms read as white space (`__attribute__((..))`,
  `__asm__("name")`, `__extension__`).

## Not done

Keywords outside the standard and GNU's common ones (`__label__`, `typeof` is done, `_Float128` and
friends are not), a preprocessor, semantic checks (types, undeclared names, constraints such as "two
or more data types"), and the other backends.
