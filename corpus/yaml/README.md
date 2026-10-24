# YAML 1.2 in HyperBNF

`yaml.hbnf` (the structure: documents, block mappings and sequences, flow collections, block
and multi-line scalars) and `yaml-tokens.hbnf` (the characters: line breaks, plain, quoted and
anchor/tag/alias text, where no blank is skipped) are the whole syntax of YAML 1.2.

## Indentation is a number, not a copy of the rules

YAML's productions take the indentation `n` as a parameter, and a document may nest as deep as
it likes.  A parameter written `k in 0..` is a number the parser works out as it reads, so
`bmap(K)`, `child(M)` and the rest are written once and the parser and the grammar stay the same
size at any depth.  `%spaces k` is exactly k spaces, `%col j` names the column the parser is at,
and `x %num j` the number x matched (the digit of `|2`).  A nested block is a nested call; a
document of 2,500 levels parses in 10 ms.  (ABNF.md, "Numbers worked out while parsing".)

This replaced a first version in which every column was a rule of its own, which made the grammar
and the generated parser grow with the deepest column allowed: 4,000 lines of C for each of 128
columns, and a generator that took minutes.  The same grammar now generates in about two seconds
and 14,800 lines of C, with no limit on depth.

Each backend keeps the frames of numbers in a stack that grows with the nesting; a use of a rule
with such parameters is a push, the call and a pop.

## Checked

- **The YAML test suite** (`sh tests/yaml-suite.sh`, branch `data-2022-01-17`, run through the C parser): all 308 valid
  cases are accepted, and 89 of the 94 invalid ones are refused.  The five that are not are listed
  in `suite-gaps.txt` with why; the run fails if one of them changes.
- **PyYAML** (`sh tests/yaml-diff.sh [N [SEED]]`): random data written by PyYAML in its block and
  flow styles, at several widths and indents, with quoted, literal and folded scalars, anchors
  and directives, must all be accepted; mutations of them are given to both and the answers
  counted.  PyYAML reads YAML 1.1.
- `sh tests/yaml.sh`: the hand-written cases in `tests/good` and `tests/bad`, among them nesting
  300 levels deep.

## What it does not decide

- A blank line before a block scalar's first text line that has more spaces than that line is
  indented (suite cases 5LLU, S98Z, W9L4), and a line of a tab alone after its header (Y79Y/000).
- A tag shorthand `!handle!x` used where its `%TAG` is not in force (QLJ7): that is a statement
  about the meaning of the document, as a duplicate TOML key is.
- C, Rust, Zig and Ada emit it; Tree-sitter has no form for numbers worked out while parsing and
  `--writer`, `--ast`, `--idref` and `--forks` do not know them, and each says so.
