# GraphQL (October 2021) in HyperBNF

`graphql.hbnf` (the executable and type system languages, 32 rules) and `graphql-tokens.hbnf` (names, numbers and
strings, where no blank is allowed inside one, 22 rules) are the whole of the October 2021 specification's
sections 2 (Language) and 3 (Type System) as a parser: queries, mutations and subscriptions, fragments, values,
types and directives, and the schema, scalar, type, interface, union, enum, input and directive definitions
with their `extend` forms, descriptions, `implements A & B` and `repeatable`.

## Counts

The baseline is the specification's grammar blocks, written down from memory of the specification and not
fetched (no network here): `originals/graphql-2021-productions.bnf`, a transcription, one alternative to a line as
the specification prints them, parameter `[Const]` as `(Const)`.  Counted the way `bench/notation.sh` counts the
others (`python3 bench/count.py specbnf` and `hbnf-code`):

| | rules | lines | symbols | characters |
|---|---:|---:|---:|---:|
| the specification's productions (transcribed) | 99 | 200 | 710 | 6316 |
| HyperBNF (`graphql.hbnf`, `graphql-tokens.hbnf`) | 54 | 65 | 566 | 3863 |
| **saved** | **45%** | **68%** | **20%** | **39%** |

Where the saving is: the `Const` pair is one pattern (`value(K in "const" | "var")` with a clause for `"var"`
that adds the variable, and `arguments(K)`, `directives(K)` carry the same parameter), the optional `( ... )`
lists are one pattern (`args`), the `{ ... }` lists another (`braced`, `block`), the `type` and `interface`
definitions are one (`object(K)`), and a definition and its extension are one rule, not two families of seven:
`type-system` says `[ description ] definition-body` and `"extend" definition-body`, and a one-line look ahead
(`adds`) says an extension must add something.  The specification writes each of those again, with its own name.

## What is covered

- The lexical grammar (2.1 to 2.9): the ignored tokens as the `ws` rule (white space, line ends, commas, the byte
  order mark, `#` comments), names, `IntValue` and `FloatValue` with the lookahead that makes `01`, `1.`, `1e`,
  `0x` and `12abc` each one error, strings with their escapes, and block strings with `\"""`.  A block string is
  kept as written: removing its indentation (`BlockStringValue()`) and decoding `\uXXXX` are for a later stage,
  as in `corpus/json`.
- The executable definitions: operations (and the `{ ... }` shorthand), selection sets, fields with aliases and
  arguments, fragment spreads, inline fragments, fragment definitions, variable definitions with defaults and
  directives, directives.
- Values: variables, numbers, strings, `true`, `false`, `null`, enum values, lists, objects; the `Const`
  variants (a default value, a directive in the type system) refuse a variable.
- Types: named, list, non-null.
- The type system definitions and every extension, descriptions, interfaces that implement interfaces, `repeatable`
  and the directive locations.

Not covered: schema coordinates (they are not in the October 2021 edition, only in later drafts), the semantic
rules of the specification (a field exists, a fragment is used, an argument is unique, a directive is in a
valid location; the validation of section 5), and the legacy `implements A, B` form that graphql-js 15 had
as an option (commas are ignored tokens, so it reads as `implements A B`, which the 2021 grammar refuses).
`ExecutableDocument` and `TypeSystemDocument` are not roots of their own: `Document`, which allows both, is
the root.

## Where the grammar is not a plain translation

The specification's productions are context-free and unordered; a parser that takes the first alternative that
matches and never comes back needs these:

- **No word is reserved.**  `query`, `type`, `on`, `fragment`, `extend`, `schema`, `true` ... are quoted words
  only where the specification has them in that place; everywhere else the position takes `name`, so
  `{ query type fragment on }`, `query query { a }`, `fragment fragment on query { a }` and `type type { type: type }`
  are all documents.  What the specification does exclude is a name each time it says "but not": a
  fragment name is a name that is not `on`, and an enum value one that is not `true`, `false` or `null`; both are
  token exceptions (`name - on-word`) in the tokens file.
- **`on` after `...`.**  A fragment spread (`... name`) and an inline fragment (`... on Type { }`) both begin with
  `...` and a name.  `fragment-name` cannot be `on`, so the spread is tried first and fails on `on`, and the
  inline fragment follows.  `... on on { a }` is the inline fragment on a type called `on`.
- **A keyword is not the front of a longer name.**  `true` must not match the front of `trueish` (an enum value),
  `type` the front of `typeName`.  hbnf reads a letter-led literal against its `word` rule, which is therefore
  the name token (`word = name-start *name-char`, then `name = word`); without a rule called `word` the literals
  match prefixes.  In the token rules (the exponent, the escapes) a letter is the single-character literal
  `'e'`, since `"e"` would be a word and not match `e10`.
- **`type A { f }` is an error, not `type A` and a query `{ f }`.**  The specification's definitions have an
  optional fields list, and the syntax `type A` then `{ f }` (an anonymous query) is also a valid reading, which
  makes it ambiguous as a context-free grammar (its extension forms carry `[lookahead != {]` for exactly this).
  Implementations (graphql-js) and this grammar take the brace as the start of the list: `block(X)` is `braced(X)`
  or no brace at all (`!"{"`).  `scalar S` followed by `{ a }` and `union U = A` followed by `{ a }` have no
  list to take the brace and stay two definitions.
- **An extension adds something.**  `extend type A` alone is refused by the specification (its three forms
  each require a part).  Rather than three forms, `type-system` reads `"extend" definition-body` (all the parts
  optional, as in a definition) after a look ahead, `adds`, that the extension has a directive, a list, a union
  member or `implements` to add.  `extend scalar S` followed by a query is refused, as it should be.
- **A number is a token and its lookahead is part of it.**  `01` would otherwise be `0` and then `1`, two values
  in a list (commas are ignored tokens).  `int-value` and `float-value` end in `!number-end` (a digit, a dot or a
  name start may not follow), as the specification says.  That makes `float-value` a rule read a character at a
  time (hbnf warns: a lookahead keeps a rule from being a single scanned token).
- **`""` and `"""`.**  The empty string is `""` not followed by a quote, as the specification says, so `"""x"` is the
  start of a block string and not two strings.
- **A block string ends at the first `"""` that no backslash escapes.**  `block-char` is a character, a `\"""`,
  a backslash that is not the start of `\"""`, or a quote that is not the start of `"""`.
- **`Const`.**  A word-valued parameter does it: `value("const")` has no variable, `value("var")` has one more
  alternative, and the same parameter goes through `arguments(K)` and `directives(K)`, because a variable in a
  directive's argument is allowed in an operation and not in a type system definition or a default value.
- **An alias** is `[ name ":" ] name`: the optional part is tried, and given back if no colon follows.

## Checked how

No GraphQL library is installed here (the Python module `graphql` is absent; there is no node), so there is no
oracle to ask, and the checks are the specification's own examples and a second reading of its lexical grammar.

- `sh tests/graphql.sh`: the generated parser of every backend (C, Rust, Zig, Ada) must accept all 145 files of
  `tests/good` and refuse all 145 of `tests/bad`.  The good files are the specification's examples, the
  kitchen-sink documents of graphql-js (from memory), every extension form, and the names-that-are-keywords cases;
  each bad file is bad for one reason, stated in its first line, a comment (an unterminated string, `01`, `1.`,
  `.5`, a name that starts with a digit, `{}`, `fragment on on X`, a variable in a default value, `type A {}`,
  `extend type A`, `enum E { true }`, a description on an extension, ...).
- `sh tests/graphql-diff.sh [N [SEED]]`: N random documents `{ a(x: S) }`, S a random run of the pieces that
  hit lexical corners (quotes, backslashes, `\u`, numbers with dots and exponents, names, commas, comments, a
  control character, the byte order mark), asked of the C parser and of `tests/graphql/oracle.py`, a hand-made
  scanner written from the specification's lexical grammar rather than from `graphql.hbnf`.  Run with 900,000
  documents over four seeds: no difference (about 9% of the documents are valid).

Tree-sitter: `--backend=tree-sitter` writes a `grammar.js`, but there is no tree-sitter binary here to run it,
so it is not tested.  Tree-sitter has no lookahead, so it leaves out `adds` and the `!"{"` of `block`: its grammar
accepts an empty extension and does not refuse `type A { f }`.
