# C11 in hbnf

`c11.hbnf` is the grammar of ISO/IEC 9899:2011 Annex A with the standard's rule names, plus the GNU
forms system headers use; `c-words.hbnf` has the tokens as rules of characters.  It is the first piece
of a small C compiler written in hbnf (parse, check, lower, write), and it parses what a C preprocessor
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
