# YAML 1.2 in HyperBNF

`yaml.hbnf` (the structure: documents, block mappings and sequences, flow collections, block
and multi-line scalars) and `yaml-tokens.hbnf` (the characters: line breaks, plain, quoted and
anchor/tag/alias text, where no blank is skipped) are the whole syntax of YAML 1.2.

## Onto a tape, with no tree

`yaml-tape.hbnf` is the same language with an `%emit{ }` where the tree would have made a node, on the
tape of `runtime/hbnf_tape.h`: a document, a mapping and a sequence are opened where they begin and
closed where they end, a scalar, an alias, an anchor and a tag are one tag and their text, and a node
a mapping entry lacks is an explicit null entry, so keys and values stay paired.  YAML is read by
trying a form and, when it does not fit, the next one, so the grammar says `rollback { tape_n }`: the
generated parser puts the tape back, one store, whenever a form that has written to it is given up.

`sh tests/emit.sh` checks it twice against the YAML test suite: the same cases accepted and refused as
for `yaml.hbnf`, and, for every valid case, the tape read back as events (documents, mappings,
sequences, scalars, aliases) has the suite's `test.event`.  Three cases of the suite are listed in
`tape-gaps.txt`; the structure they get is the grammar's, the typed parser's as well, and the acceptance
tests could not see it.  Writing the tape found and fixed one more: a document that began with `---`
on the line after another `---` was read as a plain scalar of the first.

`yaml.hbnf` also makes a tape with no `%emit` in it, under `--layout=tape`: its `flat` and `hidden` lines
say which rules write no node and which are matched and kept by nothing (`tests/layout.sh` checks the tape
of a small document and runs the YAML test suite with it).

## Indentation is a number, not a copy of the rules

YAML's productions take the indentation `n` as a parameter, and a document may nest as deep as
it likes.  A parameter written `k in 0..` is a number the parser works out as it reads, so
`bmap(K)`, `child(M)` and the rest are written once and the parser and the grammar stay the same
size at any depth.  `%spaces k` is exactly k spaces, `%col j` names the column the parser is at,
and `x %num j` the number x matched (the digit of `|2`).  A nested block is a nested call; a
document of 2,500 levels parses when the C parser is built with `-DHBNF_MAX_DEPTH=100000` and
the stack is large: the C parsers stop at `HBNF_MAX_DEPTH` rules open at once (4096 by default, about 585
levels of YAML, because the parser recurses and a document of 50,000 `[` would otherwise overflow the stack).
(ABNF.md, "Parameterised rule".)

This replaced a first version in which every column was a rule of its own, which made the grammar
and the generated parser grow with the deepest column allowed, and a generator that took minutes.  The
same grammar now generates in seconds, and has no limit on depth (the stack has).

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
