# TOML 1.0 in HyperBNF

`toml.hbnf` (the structure: a document of key/value lines, tables, arrays and inline tables) and
`toml-tokens.hbnf` (strings, numbers, dates, bare keys, where no blank may fall inside one) are
the whole syntax of TOML 1.0.  The four string forms are two hyperrules, `line(Q, C)` and
`lines(Q, C, X)`, each given its quote and its characters; the three based integers share
`digits(D)`.

## Onto a tape, with no tree

`toml-tape.hbnf` is the same language with an `%emit{ }` where the tree would have made a node, and
the tape of `runtime/hbnf_tape.h` that JSON's does: a table, a key with its value, an array and an
inline table are opened where they begin and closed where they end, and a key part or a value is one
tag and its text.  `sh tests/emit.sh` generates it, asks it the questions `tests/toml-diff.sh` asks
the typed parser (`TOML_GRAMMAR=corpus/toml/toml-tape.hbnf`: the same answers as `tomllib` on random
documents and mutations of them), and checks that the tape holds as many strings, integers, floats,
booleans and dates as `tomllib` finds in every good document of `tests/good`.  The array's trailing
comma is `&"]"` after the comma, and the two table-header brackets are two alternatives that begin
`"[["` and `"["` and a key, so that nothing that has begun is given up and begun again.

## Size

Measured with `scripts/grammar-size.py`, comments and blank lines left out:

| | rules | alternatives | symbols | lines |
|---|---:|---:|---:|---:|
| `toml.abnf` (toml-lang/toml, 1.0) | 124 | 77 | 292 | 126 |
| `toml.hbnf` + `toml-tokens.hbnf` | 46 | 116 | 283 | 49 |

## Checked

- **toml-test** (the TOML project's own suite, `files-toml-1.0.0`): all 208 valid files are
  accepted, and every invalid file that is invalid by its syntax is refused (a control character,
  a bad escape, a surrogate or out-of-range `\u`, a malformed date, a multi-line key, an inline
  table over several lines, a trailing comma in an inline table, and the rest).
- **tomllib**: `sh tests/toml-diff.sh [N [SEED]]` generates N random valid documents (bare,
  quoted and dotted keys; the four string forms; every integer base; floats; every date form;
  nested arrays and inline tables; comments; LF and CRLF) and N mutations of them, and asks the
  parser HyperBNF makes and Python's `tomllib` about each.  Every valid document is accepted and
  every mutation gets the same answer, except the texts `tomllib` refuses for what they mean,
  where either answer is counted as agreement.
- `sh tests/toml.sh`: the cases in `tests/good` and `tests/bad` through the C, Rust, Zig and Ada
  parsers.

## What a grammar of the syntax leaves to a second pass

A key or a table defined twice (`a = 1` and `a = 2`; `[a]` twice; a dotted key that reopens a
table an inline table closed) is a statement about the meaning of the document, and `toml.hbnf`
accepts it, as the TOML ABNF does.  63 of toml-test's invalid files are of this kind.  Texts
with a NUL byte cannot be handed to the C `parse_text`, which takes a C string.
