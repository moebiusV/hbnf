# CSS in HyperBNF

`css.hbnf` (the rules, the selectors, the at-rule preludes and the value functions, 74 rules) and `css-tokens.hbnf` (white space and
comments, names and escapes, numbers, strings and urls, 15 rules) are the syntax of a **conforming** style sheet: CSS Syntax Level 3
with CSS Nesting, Selectors Level 4, the preludes of `@media` (Media Queries 4, with the range syntax), `@supports`, `@container`,
`@import`, `@namespace`, `@charset`, `@keyframes` and `@layer`, and the functions every property takes (`calc()` and the other math
functions, `var()`, `env()`, `attr()`, `url()`, `rgb()` and the other color functions).  A declaration's value is checked as a
sequence of component values and nothing more: there is no grammar of `margin` or `grid-template-areas` here (there are hundreds, and
each belongs to the property).

Three roots, for the three places a browser takes CSS from: `stylesheet` (the content of an HTML `<style>` element, and a `.css`
file), `declaration-list` (the value of a `style=""` attribute: declarations only) and `selector-list` (what `querySelector` takes);
`component-value-list` is a fourth, the `any-value` of the Syntax module.  `hbnf corpus/css/css.hbnf --root=declaration-list`.

## Counts

The baseline is the specifications' productions, written down from memory of them and not fetched (no download here):
`originals/css-productions.bnf` (Syntax 3 section 4 as productions, section 5, the An+B microsyntax of section 6, and the grammar of
Selectors 4 with the functional pseudo-classes) and `originals/css-productions-extra.bnf` (Media Queries 4, `@supports`, `@container`,
`@import` and `@layer`, `@namespace`, `@keyframes`, the math functions of Values 4, the color function syntax of Color 4: what
`css.hbnf` accepts beyond the first file).  Counted the way `bench/notation.sh` counts the others (`python3 bench/count.py specbnf` and
`hbnf-code`):

| | rules | lines | symbols | characters |
|---|---:|---:|---:|---:|
| Syntax 3 and Selectors 4 (transcribed) | 103 | 104 | 800 | 5858 |
| the other specifications it also covers (transcribed) | 66 | 66 | 603 | 3866 |
| **the specifications, together** | **169** | **170** | **1403** | **9724** |
| HyperBNF (`css.hbnf`, `css-tokens.hbnf`) | 89 | 112 | 1225 | 6383 |
| **saved** | **47%** | **34%** | **13%** | **34%** |

Against the first file alone (Syntax 3 and Selectors 4) HyperBNF has 14% fewer rules and is longer in lines, symbols and characters, since it
writes down the preludes and the functions as well; the second row is what that costs the specifications.  The transcription is a baseline from
memory: it may have a production too many or too few, and its tokenizer is the specification's algorithm turned into definitions,
with the prose of it ("any code point but ...") kept as a symbol.

Where the saving is:

- **`K` is "may a selector begin with a combinator"**: `rule(K in "abs" | "rel")`, `block(K)`, `selectors(K in "abs" | "rel" | "any")`.
  A style rule inside a style rule takes a relative selector list (`> a`, `& b`, `+ c`), the top level does not, a `:has()` takes
  the relative ones, an `:is()` forgives an empty entry: the specifications write the selector list four times, hbnf once with three
  clauses of `item(K)`.
- **`condition(P)`** is `not P | P and P ... | P or P ...` over a parenthesised P, written once for the media queries, `@supports` and
  `@container` (the three specifications each write it again, five productions each).  `and-list(P)` is the part the media query
  after a media type takes.
- **`at(N)`** is the at-keyword with the end-of-name test; **`enclosed(O, C)`** is the three simple blocks; **`qualified(X)`** is the
  namespace prefix before a type selector and before an attribute name.
- **`numeric`** is the number, the percentage and the dimension in one rule (see below).

## What is covered, and what is not

- **Tokens** (Syntax 3, section 4): comments (white space), white space, identifiers with escapes and the non-ASCII range, at-keywords,
  hash tokens, strings with escapes and escaped line ends, unquoted `url(...)` as a token of its own with its restrictions (and the
  quoted form as a function), numbers, percentages, dimensions, `<!--` and `-->`, delimiters.  `unicode-range` has no rule: `U+0025-00FF`
  and `u+4??` are an identifier, numbers and delimiters, which the component values accept, and nothing could be refused by a rule.
- **Structure**: a style sheet is a list of rules; an at-rule is `@name prelude` and a block or `;`; a block holds declarations and nested
  rules (CSS Nesting) in any order; custom properties (`--x: anything`, and `--x: { ... }` for a value that is one block); `!important`.
- **Selectors 4**: type, universal, class, id, attribute (the six operators and the `i`/`s` flag), the namespaces `ns|name`, `*|*`, `|name`,
  pseudo-classes and pseudo-elements, the functional ones `:not() :is() :where() :has() :nth-child(An+B of S) :nth-last-child()
  :nth-of-type() :nth-last-of-type()` with their own argument and every other `:name(...)` as component values (`:lang(en, "fr")`,
  `:dir(rtl)`, `:host(.a)`, `::part(x)`), the four combinators (`||` too), selector lists, the nesting selector `&`.
- **Preludes**: `@media`, `@supports` (declaration, `selector()`, `not`/`and`/`or`), `@container` (name, size and `style()` queries),
  `@import` (url or string, `layer`, `layer(x.y)`, `supports(...)`, media queries), `@namespace`, `@charset`, `@keyframes` (names and
  `from`/`to`/percentages, also `@-webkit-keyframes`), `@layer` (statement and block).  Any other at-rule (`@font-face`, `@page`,
  `@property`, `@counter-style`, `@scope`, `@starting-style`, `@font-feature-values` ...) is a name, component values and a block or `;`.
- **Values**: `calc()` and the other math functions (the white space on both sides of `+` and `-`), `var()`, `env()`, `attr()`, `url()`
  and the color functions `rgb() rgba() hsl() hsla() hwb() lab() lch() oklab() oklch()` in the comma and the space syntax (separators
  are checked, the number of channels is not: `rgb(var(--c) / 50%)` is one argument that stands for three).

Not covered, or covered more strictly than the Syntax module, by design.  CSS Syntax never refuses: it recovers, and a parse error is a node in
the tree.  This grammar is for style sheets that need no recovery, so it refuses:

- **an end of the text inside a construct**: an unclosed block, string, comment, `url(`, parenthesis or bracket, a backslash that ends the
  text.  The Syntax closes them silently.
- **a `!` in a value that is not `!important`** (`a { b: c ! d }`, `x: y!`), a top-level `{}` block in an ordinary property's value
  (CSS Nesting reads it as a rule), and a custom property whose value starts with a block and holds anything else.
- **a rule with no selector** (`{}`) or with `<!--` or `-->` in its prelude: the Syntax keeps them, a selector cannot.  CDO and CDC are
  ignored between the rules of a style sheet, as the Syntax says.
- **a function of the value functions with the wrong shape**: `calc()`, `calc(1px+2px)`, `var(x)`, `rgb(1 2, 3)`, `rgba()`; and a
  prelude of `@media`, `@supports`, `@container`, `@import`, `@keyframes` or `@layer` that its grammar refuses (`@media {` ...).  The
  Syntax keeps them as component values and the specifications of the features say what a browser does with an invalid one.
- **a declaration list that holds an at-rule** (the root `declaration-list` is for `style=""`: declarations only).
- the entries of `:is()` and `:where()` must be selectors, or empty; Selectors 4 forgives an entry that is not one.  A keyword is matched as
  written (`!impor\74 ant` is not `!important`), a comment between two compound selectors (`a/**/b`) is not a descendant combinator, but
  a comment between the pieces of one (`a/**/.b`) is white space.  The semantics are not here at all: what a property accepts, which
  pseudo-classes exist (an unknown one is a valid selector), the `@charset` rule's position, `@import`'s position, `@namespace` before
  the other rules, a nested `&` that is nowhere.

## Where the grammar is not a plain translation

- **White space is a token of CSS**, so the file skips none (`whitespace none`, as `corpus/xml` and `corpus/html` do) and says where it may
  stand: `ws` (any number of spaces and comments), `blank` (at least one) and `gap` (a real space, with comments as you like; a descendant
  combinator and the white space round `+` of a `calc()`).  Nothing else: the skipping rule of hbnf eats white space *before* the next
  element is tried, so no rule after it could ask whether any was there, which is what a descendant combinator and `calc(1px +2px)`
  need (`tests/` shows both refused).  A comment is white space; between two compound selectors one is not enough (`a/**/b`).
- **Custom properties and any-value.**  `--x:` takes component values up to a top-level `;` or `!`, a block included (`--x: { a: b }`,
  and then nothing else); an ordinary value stops before a `{`, which is what makes `a:hover { ... }` inside a rule a nested rule: the
  declaration is tried first, fails at the `{`, and the rule alternative is taken.  `ending` (`;`, or the lookahead for `}` or `)`, or the
  end of the text) closes a declaration, an at-rule statement and the declarations inside `@supports (...)`.
- **A function is not a name and a parenthesis.**  `foo(` is a token (the name and the `(` side by side); `foo (` is an identifier and a block.
  `url(` is a url token if it holds no quote and a function if it does; the others that have a grammar of their own (`calc`, `var`, the color
  functions) are *excluded* from the generic function by a token exception (`ident - special-fn`), or the generic alternative would
  accept what the specific one refused (an alternative that matches is kept even if what follows fails, and a later alternative is tried only when the earlier one itself fails).  The same holds for `other-at` (`ident - known-at`) and `other-fn`.
- **The `+` and `-` of `calc()`.**  `sum = product *( gap sign gap product )`: both operators need a real white space on both sides; `*` and `/` need none.
  `1px+2px` is the dimension `1px` and a number; `1px-2px` is one dimension (`px-2px` is its unit) and is accepted, as it is by the tokenizer.
- **An+B.**  The tokenizer reads `2n+1` as a dimension and a number, `2n-1` as one dimension, `n- 1` as an identifier and a number, so the
  specification lists seventeen forms.  Here it is read as characters: `[sign] [digits] n [ws sign ws digits] | even | odd | [sign] digits`,
  which accepts the same text (the 128 cases of css-parsing-tests' `An+B.json`, 61 valid and 67 invalid, all agree).  `+ n` and `2 n`
  are refused because the white space is not in the rule.  An escape for the `n` or the sign (`\6e`) is not read.
- **`numeric`.**  `number [ "%" | ident ]` is one rule so that the longest text wins, as in the tokenizer: written as `dimension | percentage | number`, the
  first alternative takes `2.5e` of `2.5e+2` (a number and the unit `e`) and leaves `+2`.  Ordered choice between rules is not longest match; a
  rule that holds the choice inside one automaton is.
- **CDO and CDC.**  `<!--` and `-->` are tokens between the rules of a style sheet (an HTML `<style>` element used to be wrapped in them) and
  component values elsewhere; in `cv` they come before the identifier, or `-->` would be read as the identifier `--` and a `>`.
- **Escapes** are in one rule (`escape`), used by the names, the strings and the unquoted urls; a `\` before a line end is an error
  outside a string and a line continuation inside one.
- **A delimiter** is every character that begins no other token, written as the negation of the ones that do (`delim`): without that,
  `calc` that did not parse as a function would be read as five delimiters.  A quote, a backslash and a lone `/*` begin something
  and are not delimiters, so an unterminated string or comment is an error.

## Island readiness

`include "../css/css.hbnf" as css` in `corpus/html` would call, for the content of a `<style>` element, **`css.stylesheet`** (it ends where
nothing fits, at `</style`: no rule begins with `<` and a CDO is `<!--`), for the value of a `style=""` attribute **`css.declaration-list`**
(after the character references are decoded), and `css.selector-list` is what a script's `querySelector` string would be.  The file has no
skipping `ws`: its `ws` is an ordinary rule (`whitespace none`), so the known limit of an island with its own white space rule is not the
one met.  **What stops it today is the other one**: a hyperrule defined in an included-as grammar cannot be used (`rule N is not defined in
grammar css (it is used by css--at(N))`), and this grammar is made of hyperrules (`rule(K)`, `block(K)`, `selectors(K)`, `at(N)`,
`condition(P)`, `qualified(X)`, `enclosed(O, C)`, `quoted(Q)`); the smallest case is in `CONTEXTS.md` section 26 (27).  With
`sensitivity string %i` in the guest the message names the line of that directive instead (`corpus/css/css-tokens.hbnf: 6: 13`).

## The tests

`tests/css.sh` runs the hand-written files of `corpus/css/tests` through C, Rust, Zig and Ada, once for each root:
`good/` and `bad/` (132 and 113 style sheets), `declarations/` (16 and 9) and `selectors/` (32 and 28): 180 good files and 150 bad ones, each
bad one saying in its first line, a comment, what is wrong with it.  `tests/css-diff.sh` asks two parsers other people wrote
(`tests/css/oracle.py`; it needs `tinycss2` and `soupsieve`, `PYTHON=` names a python that has them, and it runs without):

- **css-parsing-tests** (Simon Sapin's, the data of tinycss2, rust-cssparser and Crass), commit
  `203ce36bffd617db7f118c551e32794561fb273d` of https://github.com/SimonSapin/css-parsing-tests (tarball sha256
  `54592ac53f24afd4fe3dab113b5d04a84fc524975419ca0ef7eeededd66e6144`; the nine files used are in `tests/css-parsing-tests/`
  with `SHA256SUMS` and the CC0 licence).  An expected tree with no `error` node is a style sheet the grammar must accept, one with
  an error must be refused.  277 cases: 131 both accept, 92 both refuse, **1 the grammar accepts** (`div {} -->` as a list of rules:
  the top-level flag), **32 it refuses** (`tests/css-parsing-tests.expect` lists each with its reason: 21 unclosed at the end of the
  text, 4 a `!` that is not `!important`, 3 a backslash at the end, 2 a rule with no selector, 1 `rgba()`, 1 an at-rule in a
  declaration list), and 21 expected-error cases of the "exactly one" files are not a test of a root that takes a list.
  The 9 color files (`color_*.json`: `<color>` as a value type, with values) and the byte-stream file are not used.
- **soupsieve's own test suite** (the 397 selectors its tests give `assert_selector` and `assert_raises`, from the sdist
  `soupsieve-4.0.tar.gz`, sha256 `ccd6470b256394ac44b08b86fd94b30a17d335a5335c8a3d15565f7b03d3c8cf`, MIT): `tests/selectors-soupsieve.txt`
  files each with soupsieve's verdict and the grammar's.  The grammar differs on 25: nine `[a!=b]` (not CSS), eight `:--custom`,
  `:before`, `:not-implemented`, `::first-line` (valid syntax, unknown or unsupported names), four `:has()` with a complex selector
  (soupsieve's "strict rules"), one that ends in a backslash.
- **generated style sheets** (every at-rule, value function and selector of the grammar: 2000 of them) must all be accepted by tinycss2
  (no error at any level, everything closed, no `!` that is not `!important`, no block in an ordinary value) and by soupsieve (each
  style rule's prelude compiles); **mutations** of other generated sheets (a character deleted, inserted, replaced, swapped, doubled, the
  text cut) must get the same answer from the grammar and the two, except where soupsieve refuses or accepts for what a selector means
  (an unknown pseudo-class or a pseudo-element, a `:has()` with a complex selector, an entry of `:is()` that is no selector): at 2000, 1541
  agree, 459 are of that kind, none differs.
- **16 style sheets of well-known projects**, pinned by sha256 in `tests/real-world.txt` and fetched once into `bench/cache/css-real`
  (`CSS_REAL=1 sh tests/css-diff.sh`): bootstrap 3 and 5, bulma, font-awesome 4.7, foundation, animate.css, pico, normalize, modern-normalize,
  tailwind's base, highlight.js's github theme, prism, purecss, github-markdown-css, jquery-ui and Material Design Icons (418 KB).  All 16
  are accepted, and tinycss2 finds no parse error in any.  (An IE hack such as `*zoom: 1` or `filter: progid:...` would not be.)

## Speed

The C backend, `gcc -O2`, one core (pinned), best of nine, a 1.05 MB style sheet.  The hand-written good files repeated (1057092 bytes): **39 MB/s**
for the typed tree (27.0 ms), 48 MB/s for `--layout=tape` (21.9 ms, with `ws` renamed: see the first limit below).  1050892 bytes of
generated sheets (more comments and escapes, fewer rules): 69 MB/s for the tree (15.3 ms), 61 for the tape (17.2 ms).  Real sheets are
mostly long runs of plain declarations and go faster: bootstrap 5 (281046 bytes) in 2.0 ms, **144 MB/s**; bulma (763189 bytes) in 5.2 ms, 147 MB/s.

## Limits met writing it (not in `CONTEXTS.md` section 26)

1. **`--layout=tape` and a rule called `ws`**: the C does not compile (`parse_rule_ws` undefined in `parse_loud_keyframe`); the same
   grammar with `ws` renamed compiles and runs.  Not shrunk: a small grammar with a hidden `ws` is fine.
2. **A pattern instance with a lookahead is a character-at-a-time token**: `at(N) := "@" N !name-char ws` is fine for `N` a literal and warns
   for `N` written `[ vendor ] i"keyframes"` ("`at-vendor_i_keyframes` is only text, but its lookahead ..."): the keyframes alternative
   spells the lookahead out.
3. **The misleading message for a hyperrule in an island** (above): with `sensitivity string %i` in the guest it names that directive.
