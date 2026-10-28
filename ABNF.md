# HyperBNF and ABNF

hbnf (named for Hartmeier, Brauer, Norby and Floeter, and read as HyperBNF)
is not ABNF. It borrows ABNF's rule notation (RFC 5234, and RFC 7405's
case-sensitive strings) and builds a different language on it. It extends the
notation downward, below characters to code points, octets and bits, and
upward, to types, trees and hand-written scanners. It also folds the lexer
into the grammar: there is no separate token stage to specify. This document
sets out that relationship precisely:

- what hbnf keeps from ABNF;
- what it adds;
- what it leaves out, by design or not yet;
- where it keeps ABNF's spelling but changes the meaning;
- for each layer of the design, what the code does today.

Statuses were checked by running them against this tree. Each ABNF construct
was written as a two- or three-rule schema and pushed through the schema
parser, the C emitter and `gcc`, then through the generated parser on
accepting and rejecting inputs.  The C, Rust, Zig and Ada backends are checked
end-to-end by tests/e2e.sh and tests/portable.sh, run in the
ada-toolchain:edge-full container (gcc-gnat, g++, rust and zig).

## Backends

The four compiled backends are **C**, **Rust**, **Zig** and **Ada**.  Planned,
not yet implemented, the rest of the compiled targets: **D**, **Fortran**,
**Free Pascal**, **Nim**, **Odin**, **Objective-C**, **ATS** and **V** — and,
beyond those, the garbage-collected languages **Go**, **Java**, **JavaScript**,
**C#**, **F#**, **Julia**, **Common Lisp** and **newLISP**.

A fifth output is not a language but a grammar for another tool: **`--backend=tree-sitter`**
writes the `grammar.js` the [tree-sitter](https://tree-sitter.github.io/) generator reads.
A phrase rule becomes `seq`/`choice`/`repeat`/`optional`; a character rule (a token in
hbnf) becomes one regular expression (a choice among single code points is one class); the
file's `ws` rule becomes `extras`; a rule that can match nothing, which tree-sitter refuses,
is defined by what it matches that is not empty and named with `optional`; a rule that is
only a choice among other tokens (`label = identifier / digits`) stays a choice of rules, so
the parser, not the lexer, decides.  What tree-sitter cannot say is left out and listed in
the file's head and as warnings: context tests and bindings, actions, scanners written in C
(unless `--ts-scanner=FILE` is given, see below).  Two things have a form with an external
scanner, and `--ts-scanner=FILE` writes it (the `externals` in the `grammar.js` and a `scanner.c`
for `src/`): a back-reference (`x %as tag` ... `%same tag`: the scanner holds the captured text in
its state and accepts only the same text again, as Mustache's closing tag needs; the tagged name
must be a token the C backend scans as an automaton, with no limit on how many are open: the scanner's state is one number, the top of a stack of
tags kept in memory the scanner owns, so a saved state is only good with the parser whose scanner
made it), and a lookahead `!x` / `&x` of literals and such tokens (a
zero-width token that looks at the text, and takes a literal that follows it into the test).
Where several lookaheads could hold at once, the first that does is taken.  Ordered choice has no form in tree-sitter: `--ts-ordered`
gives each alternative a `prec.dynamic` (the first the most), and `--ts-conflicts=a,b;c,d`
declares the groups of rules tree-sitter may fork between, which `tree-sitter generate`
names one at a time (`tests/ts-build.sh` loops until it succeeds).  Checked with the real
generator: ALGOL 60 needs 4 conflicts, parses every program of `tests/algol60` and 500 of
500 random sentences of the Report (`tests/treesitter.sh`, `tests/treesitter-diff.sh`; they
need a tree-sitter binary and a node, and skip without them).  Most of `grammars/` and
`corpus/rfc` generate too.

The C backend is pinned to **C99** (OpenBSD-kernel compatible) and always emits
code that C++ can consume directly — valid C++11 onward, no modification and no
shim — so a C++ codebase can use a generated parser as-is.  Should C++ support
ever need more than that (idiomatic C++ types, exceptions, anything beyond a
simple `extern "C"` header guard), a separate C++ backend takes over rather
than complicating the C backend.

## 1. The shape

**Borrowed from ABNF:** the rule syntax — `name = elements`, concatenation,
`( )`, `[ ]`, `n*m` repetition, `"…"` literals, `;` comments.  Alternatives
are separated by `|`, ordered choice, as in PEG and as parse.y grammars are
read.  ABNF's `/` (union) is taken wherever ordered choice, in some order of the
alternatives, accepts the same language (§3.2); the other steps in RFCPLAN.md
let the rest of an RFC's ABNF compile as written.  The reader takes
RFC 5234's other forms: `=/`, `%d13.10`, `*m`, a rule going on to an
indented line, newlines inside `( )` and `[ ]`, and `<prose-val>`.

**Extended downward (design):** a schema can describe input below the token:
- characters, through character-level rules and named character classes;
- code points, with UTF-8 decoded on input;
- octets and bits, through `name:N` bit fields.

In that design the lexer is not a stage of its own. Token definitions are
grammar rules — character-level ABNF or a hand-written scanner action — and the scanner is
generated from them.

**Extended upward (implemented):**
- a rule's name is its type, and the tree's shape is read from the rules;
- typed core rules (`str`, `word`, `int`, `u16`, `flag`, …);
- scanner actions (scanners written in the target language, inside the schema);
- schema directives and code blocks;
- `--idref` output for OpenBSD daemons, and the runtime they link (`runtime/hbnf_conf.h` and `.c`) under a `parse_config` the grammar writes in its epilogue.

**Same spelling, different meaning:** alternation is ordered choice (PEG), not
ABNF's union; literals are case-sensitive, like parse.y keywords; a rule
referenced for a field is a type, not just a pattern.

**Left out:** nothing in RFC 5234's syntax is refused by the reader now.
Character classes are named rules (`grammars/common.hbnf`).  Some ABNF
features are not there yet in the backends (§3).

## 2. The layers: design and implementation

| Layer | Design (paper, `grammars/README.md`) | Implemented at this tree |
|---|---|---|
| Bits | a field is `name:N` with N in bits, packed big-endian in RFC order, read by generated shift-and-mask code (§4.7) | C and Rust, 2026-10-17, in the one notation (a rule with a bit field is a bit rule; there is no binary mode): `name:N`, `name:16le`, `name:8s`, `name@K:N` (the field must start at bit K), `name:bits(expr)`, constants (`0x0800`, `0b101`), value sets, guarded choices, arrays of records, expressions over earlier fields, and the other direction (a tree to bytes).  Zig and Ada follow.  `WIRE.md` is the reference; `tests/wire.sh` the tests. |
| Octets | the unit between bits and chars; `*u8` payloads; `dst:[6]` (§4.7) | C and Rust: `name:[expr]` (a slice of the input; Rust owns a copy), `name:*u8` (the rest), octets that start inside a byte (copied).  `WIRE.md` |
| Parameterised rule | `list(X) := X *( "," X )`; `level ::= 1..17`; `binary(N in 1..17) := binary(N+1) *( op(N) binary(N+1) )`; `binary(17) := unary`; `op(1) := "||"`; `block(K in 0..) := entry(K) *( nl %spaces K entry(K) )`; `x %num D` | A rule with parameters is a schema over the values of its parameters (a hyperrule).  A parameter has a domain (`N in 1..17`, a word list `K in "int" \| "string"`, or `K in 0..`, which has no end), a clause that gives constants (`binary(17)`) wins over the general one, and a number outside the domain is an error where it is written down.  There are two ways to make it a parser, chosen by the generator and the same in effect: **expanded**, one ordinary rule for each value (`list(item)` and `binary(1)` become rules when the grammar is read, so no backend sees a parameter), or **run**, one rule that keeps its numbers in a frame, the parameters first and then the names `%col j` and `x %num j` set, with each clause an alternative that begins with a test of them (`B_Guard`), the rules a group inside it lifts running in the same frame.  Words and rule names are always expanded; numbers are expanded when they form a small table (up to 16 values, with a clause for particular ones: a call that does little is cheaper without a frame) and run otherwise (a call that scans, and any domain with no end: the grammar and the parser do not grow with the values, and the text may nest as deep as it likes); `--expand-params` and `--run-params` choose.  `%spaces k` is exactly k spaces (k a number, `%spaces(k + 1)` an expression), `%col j` names the column the parser is at, `x %num j` the decimal number x matched.  A rule with number parameters cannot start a parse.  An open end (`0..`) is not checked.  Run: C, Rust, Zig and Ada (not Tree-sitter, `--writer`, `--ast`).  `corpus/yaml/yaml.hbnf` reads YAML's indentation this way.  `RFCPLAN.md`, `HISTORY.md` |
| Context (symbol tables) | `context types`; `name ? types`; `name ?! types` (the text is not in the set); `%bind types += decl.name`; `%scope`; `%where { code }` | The parser keeps named sets of names; a test asks one, a bind adds to it, a scope ends what is added, and a wrong guess puts every set back.  C.  `RFCPLAN.md` decision 13 |
| Lookahead | `":" !"="`, `name &";"` | `!x`: x must not match here; `&x`: it must; nothing is consumed.  x is a literal, a token or alternatives of those.  A failed test says what it wanted (`expected something other than `=``) |
| Local forks | `--forks` | A rule whose alternatives can start alike (`"<" | "<" "="`, `x | x y`) is retried with its next alternative when something later in the same sequence fails, instead of keeping the first that matched.  Off by default (the output is as it was).  C only.  The forks are listed on stderr (`--quiet-forks` silences them), and an alternative that an earlier one shadows is no longer an error, except in a choice among single literals alone (`"<" / "<="`), which is read as a word set and stays longest first.  Only a failure later in the same sequence is retried, not one in the caller of the caller. |
| Compact nodes | on by default; `--no-compact` for the old layout | A struct that gathers the fields of a choice (a statement that is one of many kinds, an option that is one of forty) holds each field as a pointer, allocated from the arena when that alternative is taken and given back when the attempt fails, so a node costs the alternative taken and not all of them.  The generated types differ (`r.pfrule.action` is `r.pfrule->action`).  C, Rust (`Option<Box<T>>`) and Zig (`?*T`); Ada's records already hold records by access.  Off with `--forks` in C.  pfctl: 0.50 s and 275 MB per 200,000 rules instead of 0.78 s and 845 MB; across the corpus memory falls or stays, and speed is mixed (see WHY.md). |
| Reserved rule names | `comment`, `eol_comment` | A rule called `comment` is the own-line comment of a config grammar (`#` to the end of the line, only blanks before it on its line) and `eol_comment` the same-line one; the parser anchors them that way.  A grammar whose own `comment` is something else (ALGOL 60's `'COMMENT' text ;`) calls it something else (`remark`). |
| Back-reference | `x %as tag` ... `%same tag` | `%same tag` is the text `x %as tag` matched, again, in the same sequence: a closing tag that repeats the opening one (`"<" name %as t ">" *node "</" %same t ">"`), a here-document's terminator, a raw string's delimiter.  The tag is local to the sequence, so nesting and backtracking cannot mix two of them up.  A `%same` is also written by the writer.  C only; the Tree-sitter backend leaves it out and says so.  `tests/backref.sh`; `corpus/mustache`. |
| Alternative labels | `x = "set" a b %label assign \| "run" a %label execute` | A name for an alternative, which `node_alt_name` gives (`--ast`); without one the name is the alternative's first literal or rule.  `RFCPLAN.md` 7d |
| Text from bits | a message written as symbols or words: `words:bitsof(data)` with `data = 1*bech32-symbol` | C.  The text rule is read as text; its words' enum numbers are the bits the rest of the rule reads, and writing spells the bits back.  `WIRE.md` |
| Enum numbers | `"icmp"@1`, the way C writes `ICMP = 1` | All four backends.  An alternative without a number is the one before plus 1.  Names are declared in value order with an explicit number only where it is not the previous plus 1 (a C `= 17`, a Zig `enum(u8)` that is open when it has no tag for 0, a Rust discriminant, an Ada representation clause).  A union of words keeps the values in the order written, whatever order it is matched in.  `WIRE.md` |
| Code points | UTF-8 decoded on the way in; the matcher works on code points; a literal can name `"café"` (§3.3, §5.2) | All four backends: yes. Each backend's character-layer scanners decode UTF-8 (`hbnf_decode_utf8` in C, `Decode_Utf8` in Ada, `decode_utf8` in Rust/Zig) and match code points, so `%u20AC` (€) and `%x20-10FFFF` match multi-byte sequences (§2, §5). |
| Characters | character-level rules compiled to scanners (`int = ["-"] 1*DIGIT`, `money = 1*DIGIT "." 2DIGIT`); named classes `digit`, `alpha`, `hexdig`; `where` refinements; the lexer generated from these rules, taking the longest match (§4.1–4.3) | Partial. The numeric terminals `%b`/`%d`/`%o`/`%u`/`%x` and ranges parse (into a `Char_Range` element), and every backend compiles character-level rules to scanners that take the longest branch (single-char, multi-char sequence, list elements); named classes come from `grammars/common.hbnf`. `where` is still deferred. |
| Tokens | scanner actions as the fast path, each with its character-level fallback written above it; `wordchars` | Yes, in all four backends: there is no token array and no fixed lexer.  A phrase rule reads the text at a position and runs the scanner a rule names there; whitespace is the grammar's `ws` rule, skipped between elements; a letter-led literal is matched by the `word` scanner, so it never matches the front of a longer word.  `word`, `int`, `str` and `ws` are grammar rules (`grammars/obconf.hbnf`) or, where the grammar leaves one undefined, a built-in scanner.  A `%scan{}` scanner action is C code, so only the C backend runs it; the others generate a stub that matches nothing.  `wordchars` widens the word set. |

The rest of this document describes the implemented token layer, and marks
where the design says otherwise.

## 3. ABNF, feature by feature

✓ supported · ✗ not supported · *rejected* = the compiled backends refuse the
schema with a message naming the rule and the fix. Until this series, those
shapes compiled into parsers for a different language.

### 3.1 Rule definition (RFC 5234 §2, §3.3, §4)

| ABNF | Compiled backends | Interpreter | Notes |
|---|---|---|---|
| `name = elements` | ✓ | ✓ | |
| Rule name `ALPHA *(ALPHA / DIGIT / "-")` | ✓ | ✓ | hbnf also allows `_` |
| Case-insensitive rule names (§2.1) | with `sensitivity rule-name %i` | same | Per file: a reference finds its rule whatever the case (`digit` finds `DIGIT`) and takes the definition's spelling; one that finds two rules is an error. Without it `E` does not find `e`. Two rules whose names differ only in case are refused either way: the generated identifiers would be one name. |
| `=/` incremental alternatives (§3.3) | ✓ reader | ✓ reader | Adds alternatives to the definition that stands, in the same file or one it includes, joined with `/` (union), so the same limit applies as to `/` (§3.2). An `=/` with no `=` before it is an error. |
| One definition per rule | a later `=` overrides | same | ABNF gives no meaning to a second `=`.  hbnf's later definition replaces the earlier one in its place, in the same file or across `include` (so an overridden root is still the root). |
| Continuation by indentation (§4 `c-wsp`) | ✓ | ✓ | A rule goes on to an indented line, and to one that starts with `\|`. A comment inside a rule is dropped; the last one on the rule's last line is its trailing comment. |
| Newline inside `( … )` | ✓ | ✓ | And inside `[ … ]`; a comment there is dropped |
| `;` comments | ✓ | ✓ | hbnf also copies them into the generated code |
| At least one element per alternative | accepts empty | accepts empty | `e = "a" word \|` is accepted; ABNF forbids it |

### 3.2 Operators (RFC 5234 §3)

| ABNF | Compiled backends | Interpreter | Notes |
|---|---|---|---|
| Concatenation, alternation, grouping | ✓ | ✓ | Alternation is ordered choice (§4). `\|` separates alternatives, as in BNF and yacc. ABNF's `/` (union) is taken wherever ordered choice, in some order of the alternatives, accepts the same language: between one-code-point alternatives (`DIGIT / ALPHA`); in a character rule, whose scanner takes the longest alternative (`dec-octet` in the RFC's own order); and between longer alternatives. The reader looks for an order in which no alternative can match text that a later one matches more of, and writes the choice in that order, so `"a" / "a" "b"` and `h16 ":" h16 / IPv4address` need no rewriting by the author and no tree type changes; one that can match nothing goes last, and is refused if what follows the choice could begin another. It is decided on the alternatives' text, with no limit on how far into the input they look. Where a union needs backtracking (two alternatives match the same text and go on differently: `host = IP-literal / IPv4address / reg-name`), hbnf takes the first alternative that matches and is followed by something that can follow the choice, which is how RFC 3986 section 3.2.2 settles `host` (first match wins), and says so in a warning naming the two; an alternative that could never be chosen is not reordered ahead of the one written before it.  Where ABNF's backtracking would choose differently, write `\|` with the one to prefer first.  If what follows is not known (a scanner), it is refused. The check covers only the rules the parser uses. |
| Direct left recursion, `a = a x \| y` | ✓ read as a loop, `y x*`, in all four backends | ✓ | The first entry of the list comes from the bases, each later one from the tails. Indirect left recursion is refused. |
| `( a \| b )` inside a sequence | ✓ lifted into a rule of its own | ✓ | `x = a ( b \| c ) d` is read as `x = a x_1 d`, `x_1 = b \| c` before code generation (`Lift`), so all four backends take it; a literal-only alternation is an enum. A plain `( a b )` is spliced in. Before RFCPLAN.md step 2 it was refused, and before that flattened to `a b` |
| `[ … ]` as a whole rule | ✓ | ✓ | |
| `[ … ]` inside a sequence | ✓ lifted | ✓ | `x = a [ b c ] d` is `x = a x_1 d`, `x_1 = [ b c ]`: a list of none or one entry, which records whether it was there (`[ "log" ]` too). Before step 2 refused, and before that it became required |
| Repeated group or reference inside a sequence | ✓ lifted | ✓ | `x = a *( ',' b )` is `x = a x_1`, `x_1 = *( ',' b )`, and `1*alias` likewise; the repetition bounds hold in all four backends. A lifted rule is named `<rule>_<n>`, numbered within its rule: give the part a rule of its own where the tree's field name matters (a binding). Before step 2 refused, and before that it matched once, or did not compile |
| `*`, `1*`, `n*`, `n*m`, `n` on a list rule | ✓ bounds enforced in all four backends | ✓ | Previously `1*` accepted an empty list in every backend |
| A list of a core type (`ws = 1*word`) | ✓ | ✓ | Previously failed to link; Rust, Zig and Ada called a parse function that does not exist |
| A list of literals only (`log = 0*1( "log" )`) | ✓ one entry, without a field, per match | ✓ | How a grammar records an optional word |
| `*m` (`*2w`) | ✓ | ✓ | Zero to m |
| Precedence (§3.10) | same | same | |

### 3.3 Terminal values (RFC 5234 §2.3, §3.4; RFC 7405)

| ABNF | Status | Notes |
|---|---|---|
| `"…"` | ✓ | Case-sensitive, unless the file says `sensitivity string %i` (then `%s"…"` is how to ask for case), and must be exactly one token (§4). C's escapes, octal and `\?` included, which every emitter re-escapes for its target language. |
| `%b` / `%d` / `%o` / `%u` / `%x`, ranges | ✓ | Numeric terminals — binary/decimal/octal/hex, plus `%u` for an encoding-agnostic Unicode code point (bounded to `10FFFF`) — and code-point ranges, read into a `Char_Range` element. The endpoint order does not matter (`%x39-30` = `%x30-39`). Every backend compiles them to scanners that match decoded UTF-8 code points (§2). `%d13.10` is the code points in sequence, two elements of the rule. `%X41` is `%x41`. |
| `'c'` (character literal) | ✓ | A yacc-style character literal: one code point, with C escapes (`'\n'`, `'\x41'`). `'a'-'c'` is a code-point range — the same `Char_Range` as `%x61-63`. Non-ASCII code points work via the UTF-8 decode in every backend (§2). In a rule that is not a character rule, a single code point (`','`, `%x2C`) is the one-character literal; before, the backends dropped it without a word. A range there is refused until the character model. |
| `<...>` | ✓ reader | A rule, as Backus and Naur write a nonterminal, and as a section is named in literate programming: it may have spaces, `<table reference>` being the rule `table-reference`, and `<pchar>` is the rule `pchar`.  At the start of a line it names the rule being defined; anywhere else it refers to one.  ABNF's prose-val (`<host, see [URI]>`, words describing a rule) is the same thing, a rule nobody has written yet: if the parser would use it, generation stops with `file:line:col: not written yet, in `rule`: <…>`, the line, a caret under it, and what it probably means and what to write.  A later `=` that defines the rule fills it. |
| `name = %grammar "file"` | ✓ reader | The rule's body is in a file (`~/` is the home directory, any other path is beside the file that names it): a section of a literate grammar kept on its own.  The file holds what follows `=`, not whole rules; whole rules are `include`d. |
| `%s"…"` (RFC 7405) | ✓ | Means exactly what hbnf's bare `"…"` means |
| `%i"…"` (RFC 7405) | ✓ in all four backends | Any case matches; a `%i` keyword is interned case-insensitively in C. A word written both `%i` and plain is refused. snmpd's `auth` and `enc` use it, as parse.y's strcasecmp does. |
| `%scan{ … }`, `%action{ … }` | ✓ | The spelled-out forms of `name = { code }` (a scanner action) and `pattern { code }` (an action) |

### 3.4 Core rules (RFC 5234 Appendix B.1)

`include "common.hbnf"` defines them, from `grammars/`; it includes
`ascii.hbnf`, which names the non-printable code points.  A grammar may define any
of them again (a later `=` overrides).

| Name | ABNF | In hbnf |
|---|---|---|
| `SP`, `HTAB`, `CR`, `LF`, `DQUOTE` | `%x20`, `%x09`, `%x0D`, `%x0A`, `%x22` | `ascii.hbnf` — the named single characters. The whitespace ones are significant only where the grammar references them (§6); `LF` is parse.y's `'\n'`, `DQUOTE` a named double quote. |
| `WSP`, `CRLF` | `SP / HTAB`, `CR LF` | both in `common.hbnf` |
| `LWSP` | `*(WSP / CRLF WSP)` | Not yet: a character rule cannot repeat (RFC 5234 itself warns about `LWSP`) |
| `ALPHA`, `DIGIT`, `HEXDIG`, `BIT`, `CHAR`, `CTL`, `VCHAR`, `OCTET` | character classes | `common.hbnf`; the character layer (§2). A file with `sensitivity rule-name %i` may write them `alpha`, `digit`, `hexdig`. |

## Dialects: one notation

BNF, EBNF, ABNF and YBNF (the grammar language of yacc and bison) are dialects that HyperBNF
(this notation, the language `hbnf` is named for) reads alongside its own spelling, and `hbnf` reads the
superset: a spelling any of them uses is accepted wherever it cannot be taken
for something else, and a line `dialect NAME` (or `--dialect=NAME` for a run) is needed
only where two dialects spell different things the same way.

| Construct | BNF | ISO EBNF | ABNF | In hbnf |
|---|---|---|---|---|
| Assignment | `::=` (YBNF: `:`) | `=` | `=` | `=` defines a rule, `:=` a rule with parameters (a hyperrule), `::=` a domain (a metarule), as in the ALGOL 68 Report's `:` and `::`.  `:` is yacc's and defines a rule.  `dialect bnf` (or `ybnf`, `ebnf`, `abnf`) reads `::=`, `:=`, `:` and `=` as one operator, the one that defines a rule |
| A rule | `<table reference>` | `table reference` | `table-reference` | all three are the rule `table-reference`; a bare name and `<name>` are the same |
| A rule described in words | — | `? words ?` | `<words>` | `<words>`, and under `dialect ebnf` `? words ?`: a rule nothing defines, "not written yet", with the rule it probably means |
| Alternation | `\|` | `\|` | `/` | `\|` ordered choice; `/` union, in whatever order or first-match-wins; a `/` or `\|` in a BNF or EBNF file is read the same |
| A terminal | bare | `'x'`, `"x"` | `"x"` (case-insensitive), `%x41` | quoted, or `%x41`; `'x'` is one code point, and under `dialect ebnf` a string like `"x"`; a bare word is a rule, a bare number or symbol gets a message saying to quote it |
| Optional | — | `[ x ]` | `[ x ]` | `[ x ]` |
| Repetition | recursion | `{ x }`, `n * x` (exactly n) | `*x`, `n*m x`, `nx` (exactly n) | `*x`, `n*m x`, `nx`; under `dialect ebnf`, `{ x }` is `*( x )` and `n * x` is `nx`; in the default notation a spaced `3 * x` is an error that says to write `3x` (`3*x` is three or more) or to read the file as EBNF |
| Concatenation | juxtaposition | `a , b` | juxtaposition | juxtaposition; under `dialect ebnf`, `,` joins; elsewhere `,` gets a message saying so |
| End of a rule | line | `;` | line | end of the line (a line that goes on is indented); `;` starts a comment, so a `;` at the end of a line is harmless; under `dialect ebnf`, `;` ends a rule and a line end is white space |
| Comments | — | `(* *)` | `;` | `;`, `(* *)` and `/* */` |
| Exception | — | `a - b` | — | `x = a - b`, the whole of a rule: what `a` matches, unless `b` matches exactly the text `a` matched (`cmd-name = word - reserved`).  Two forms, chosen by what the operands are: a token exception when both are text hbnf can read exactly, and a phrase exception when either is a rule that skips whitespace or is code.  See "Tokens, and the exception" below |
| Strings | — | no escapes | no escapes | C escapes, except where the file says `dialect abnf` or `dialect ebnf` (or `--abnf`, `--ebnf`) |
| White space | — | skipped | significant | skipped, except where the file says `dialect abnf` (`whitespace none`) |

YBNF, yacc's grammar notation (and bison's), is a dialect of BNF, not of EBNF: a rule
is a production, `name : alt | alt ;`, lists are written by recursion, and it
adds `%token`, `%start`, `%%` and C actions in braces.  Under `dialect ybnf`
(and `dialect bnf`, `dialect ebnf`) a bar is the union, as it is in those
notations, and `/` is the same thing: hbnf finds an order of the alternatives
in which the first that matches is right, or says why none exists.  Without the
line, a `:` rule gets a notice that hbnf's `|` is ordered.  `%token NAME ...` is
read and remembered, `%start NAME` names the rule to start from (`--root=`
wins) and `%%` is dropped.  yacc leaves its tokens to a lexer; hbnf reads
characters, so each token is a rule, and a token that nothing defines is
reported once with how to write it, quoting the spelling the standard gives in
the comment under the declaration (`DLESS = "<<"`).  What stays different is
that yacc's actions run as the parser reduces, where hbnf's `%action{}` runs
once, after the parse.  RFCPLAN.md's POSIX section is the plan for the rest.

## 4. Same spelling, different meaning

| Construct | ABNF | hbnf | Observed | Writing it in HyperBNF |
|---|---|---|---|---|
| The unit a rule matches | characters | tokens today (a fixed lexer); characters and below in the design | — | — |
| `"abc"` | case-insensitive | case-sensitive, like parse.y keywords | `ABC x` is rejected by both engines | `%s"abc"` is the ABNF spelling of hbnf's meaning |
| `"a b"`, `"!="` | a sequence of characters | exactly one token | never matches | `"a" "b"`; a multi-character operator is a character rule (`NE = '!' '='`) or a scanner action (pfctl's `ne`/`le`/`ge` still are) |
| `A / B` | union | hbnf writes `A \| B`: ordered choice, the first alternative that matches is kept, and a later failure does not come back for the next.  `/` is taken where the two agree, which the reader decides by finding an order of the alternatives in which none takes input a later one needed (and writing the choice in that order). | `e = p "c"`, `p = "a" \| "a" "b"` rejects `a b c` in the interpreter; the compiled backends refuse the schema, since `"a" "b"` begins with the whole of `"a"` before it and can never match | longest alternative first |
| `*x x` | at least one `x` | never matches: `*x` takes every `x` | rejected by C and Rust | `1*x`, or restructure |
| A rule referenced twice in one alternative | two occurrences | one field named after the rule | *rejected* with a suggested alias. Previously the second value overwrote the first, in 37 places across the daemon grammars. | an alias rule: `port_hi = port` |
| Lowercase core names (`int`, `str`, `word`, …) | ordinary rule names | reserved types | — | don't define rules with those names |

### Generated names carry a prefix

Every identifier hbnf generates from a rule is prefixed, so no rule is ever a
reserved word of the language generated and nothing is renamed one name at a
time.  The prefix is the dialect the file names (`dialect ybnf`, `--dialect=`,
`--abnf`, `--ebnf`), and `bnf_` when it names none: the rule `if` is `ybnf_if`
in a YBNF file and `bnf_if` in a file with no dialect line, in the C types,
functions, enum constants and struct fields and in the Rust, Zig and Ada names.
The built-ins (`word`, `int`, `str`, `u8`, ...) and `ws` keep their names.
Messages always show the rule as the grammar writes it.

`prefix none` (a line in the file, or `--prefix=none`) turns the prefix off, so
the generated names are the rules' own; the nine daemon grammars say so, because
their action code and the programs they link against use the generated names.
(`prefix "pf_"` and `--prefix=` still put their own prefix on the C types, in
front of this one.)  The two renames hbnf used before, `atom` to `atom-rule`
and `WORD` to `WORD-rule`, remain only under `prefix none` and for a file with
no dialect line that opts out; a prefixed name cannot collide with a built-in.

### Tokens: a rule that is only text is one string

A rule with no named children has nothing for a tree to say, so hbnf does not
build one.  A rule is **text** when it is made only of literals, classes,
groups, alternatives and repetitions, and of other rules that are text, with no
built-in type (`int`, `word`, ...) and no code inside it, and when its file skips
no whitespace inside it.  A text rule is one token: hbnf builds a deterministic
automaton from it, the generated scanner takes the longest text that ends in an
accepting state, and its value is that text, a string.  `scheme = ALPHA *( ALPHA
/ DIGIT / "+" / "-" / "." )` and `path = *( "/" segment )` are strings, not lists
of nodes; `x = 1*( "a" / "b" )` is a string, not a list of empty nodes.  A
token that can match the empty text succeeds on it.

What is not text keeps its tree, on purpose:
- an enum (`dir = "in" | "out"`) is an enum, and a lone literal is its string;
- a rule that names a built-in (`int` is a number, `word` a typed word) has a typed
  value in it;
- a rule that refers to an exception (`a - b`) has its own form, below;
- a rule in a file that skips whitespace, with more than one element or a
  repetition, skips whitespace *between* them (and between the entries of a
  repetition), which a token cannot; and a letter-led literal in a grammar with
  keywords is matched as a word, with its boundary, not as characters;
- a rule whose automaton would be too large (a repetition bound past 32, or over
  2000 states) is not approximated and stays a tree.

None of the nine daemon grammars changes: their text-like rules were already
strings or enums.  In `dialect abnf` and any file that says `whitespace none`,
every pure-text rule is a token, which is what an RFC's lexical rules are.

### The exception

`x = a - b` is what `a` matches, unless `b` matches exactly that text.  It comes
in two forms, and hbnf picks the form from the operands, so the notation is the
same.

**A token exception** is for operands that are text hbnf can read exactly: a
built-in scanner (`word`), a rule of characters, or a rule made only of
literals, classes, groups, repetitions and other such rules, in a file where no
whitespace is skipped inside it.  Each such operand is read as a token: hbnf
builds a deterministic automaton from the text, and the generated scanner, in all
four backends, takes the longest text that ends in an accepting state.  It
decides nothing by looking ahead and makes no choice, so no grammar can be
ambiguous or in conflict through it.  `x` scans `a`, then asks whether `b`
matches exactly that text, by scanning `b` with the end of the input moved to
where `a` stopped.  So `word - reserved` rejects `if` and accepts `iff`.  An
operand that cannot be one token (it refers to itself, bounds a repetition past
32, needs more than 2000 states) is not approximated; the exception is then a
phrase exception.

**A phrase exception** is for the rest: an operand that is a rule with several
elements in a file that skips whitespace between them, or one that contains a
`%scan` or a built-in the automaton cannot see into.  `x` parses `a` with its
own parser, which builds a tree; then it tries `b` on the same text, with the
input cut off where `a` ended and `b` required to end there too, and throws the
trial's tree away.  If `b` matched the whole of it, `x` fails and the position
and the tree are put back, so the enclosing rule's ordered choice goes on as if
`x` had not matched.  Whitespace inside the operands is skipped as it is
everywhere else in the file.  The message says `` `a` that is not `b` ``.  `x`
has `a`'s type.  A built-in (`word`) on one side of a phrase exception has no
rule to parse, so hbnf says to give it one: `w = word`.

Neither form is a language difference in the sense of ISO 14977, which would
also take shorter matches of `a`: this is the committed match, which is what a
reserved word needs.

## 5. What HyperBNF adds

| Extension | Syntax | Status and caveats |
|---|---|---|
| Typed core rules | `str`, `atom`/`word`, `int`, `bool`, `flag`, `u8…u64`, `i8…i64`; `dec`, `float` | No backend has `dec` or `float`. `atom` rejects numbers. `bool` accepts any word (`maybe` → false). `int` takes `-5` (a `-` before a digit is part of the number). Compiled `u16` accepts `70000`, truncated. `u7` emits `uint7_t`, which doesn't compile. |
| Tree typing from rule shape | — | Literal alternation → enum; single core type → scalar; `*( x )` → list (a whole rule); sequence → struct; keyword-led alternations get a kind tag; alias rules (`src = host`) name a field with another rule's type. Plus `free_<rule>`, visit/map, `--idref`. |
| Scanner actions (scanners) | `name = %scan{ code }`, `name = { code }`, or `name = C { code }` (a `<name>` works too), `name = Rust { code }`, `name = Zig { code }`, `name = Ada { code }` | A hand-written scanner: code that sees `s`, `pos` and `len` and returns the length it matched (Ada: its declarations and `begin … end`, since its body is a function's).  Each backend takes its own language's line, so one grammar means the same in all four; the plain forms are C's (or the file's `language`).  A scanner with no code for the backend being generated gets a warning ("the scanner `name` has no Rust code, so here it matches nothing…") naming the line to write, where it used to be a silent stub.  A character rule does the same job in all four backends with nothing written per language. |
| Actions | `pattern %action{ code }`, `pattern { code }`, or `action name { code }` | C only. Run bottom-up after a statement parses, with the rule's node as `n`; `bind_error()` reports as parse.y's `yyerror` does. The ntpd and unwind bindings (`grammars/bind/`) are built from them. |
| Schema directives | `language C\|Rust\|Zig\|Ada`, `wordchars "…"`, `include "file"`, `listops { … }`, `prefix "pf_"` | `include` is relative to the including file and goes before the file's first rule; a file is read once however often it is included. A later `=` overrides: a file's own rule overrides an included one, and of two included files the later one's wins. `language` is per file, the language of that file's own code blocks (C when absent), and a backend emits only the blocks in its language. The others describe the one generated parser: any file may set one, and two different values are an error; `keywords` lists merge; code blocks join in include order, included files' first. `prefix` goes in front of every generated C type and struct tag (`--prefix=` overrides it). `listops { head { … } entry { … } … }` names each of the eight list operations and its raw C, with `@name@`/`@elem@`/`@h@`/`@e@`/`@v@` substituted in; the nine daemon grammars set them to OpenBSD's `TAILQ_*` from `<sys/queue.h>`. An operation without an override falls back to hbnf's own head/tail singly-linked list. |
| Statements, macros, includes | `statements`, `macros <rule>`, `includes <rule>` | C only (the other backends warn and parse the whole file). `statements`: the root must be a list, `*( … )` or parse.y's own `config = | config entry`; the parser reads one statement at a time, one root entry each, as parse.y's `grammar : grammar entry '\n'`. A statement ends at a newline outside braces, quotes and comments; backslash-newline and a next line starting with `{` continue it. A failed statement is reported and the parse goes on. `macros varset`: a statement the rule matches whole defines a macro (first token the name, the tokens after `=` joined by spaces the value), and `$name` at the start of a word, outside quotes and comments, expands to it, glued to what follows; `cmdline_symset("n=v")` defines one the config cannot redefine. `includes include`: a statement the rule matches whole reads the file its last token names, relative to the working directory, as parse.y does. A file (`parse_file`, `parse_config`, an include) is read a block at a time, not whole. |
| Keyword table | `keywords { all any anchor … }` | C only. The words the lexer reserves, as parse.y's `lookup()` table: a letter-led literal in the table is a keyword (interned, refused as a `word`, dispatched on by id); any other literal matches a word by its text and reserves nothing, as parse.y's `STRING` compared with `strcmp`. A listed word no rule uses is still reserved. Without the directive every letter-led literal is a keyword. The nine daemon grammars carry their parse.y's table; `tests/bytetest/keywords.sh` checks that they match. |
| Code blocks | `{ … }` before the rules (preamble) and after (epilogue) | Copied verbatim |
| Escapes in literals | `\a \b \f \n \r \t \v \\ \" \' \xHH` | `\xHH` reads hex digits greedily, as in C |
| Negation | `~x`, `*~x` | `~x` matches one code point that `x` does not, and `*~x` is a run of them (SNOBOL's `BREAK`: `comment = "#" *~LF`).  `x` is a class: a one-character string, a range, a rule of those, alternatives of those in a group, or another negation (`~~x` is `x`).  hbnf computes the complement's ranges and reads `~x` as a character rule of them, so every backend scans it without a new case.  Not defined for a longer text (`~"ab"`), a built-in, or a rule that is not one character; the message says which.  A hbnf extension: ABNF has no negation. |
| Comma list | `n#m element`, `#element` | `#` is `*` with an implicit comma separator: `n#m` is comma-separated repetition, `#element` is `1#element`, sugar for `element *("," element)`.  Inherits parse.y's list semantics (no trailing comma, no empty elements); deliberately stricter than HTTP's `#rule`, which allows empty elements.  Built (2026-10-18, C and the others: it is read into ordinary rules).  In the Report's ALGOL 60 it is every list rule (`corpus/algol60/algol60.hbnf`).  The same list written as a rule is `xs = xs "," x | x`, a left-recursive loop; `#` is that, inline. |
| `dialect`, `--dialect=`, `--abnf`, `--ebnf`, `whitespace none`, `sensitivity string %i`, `--root=RULE` | per file; CLI | `dialect bnf \| ebnf \| abnf \| ybnf \| hbnf`, a line like `language` and `include`, names the notation the file is written in; `hbnf` is the default.  In hbnf `=` defines a rule, `:=` a rule with parameters (`binary(N in level) := ...`, a hyperrule) and `::=` a domain (`level ::= 1..17`, `kind ::= "int" \| "string"`, `any ::= level \| 20`, a metarule: a finite set of numbers or words for a parameter to range over; one that names itself is refused).  A file in BNF, where `::=` or `:=` defines an ordinary rule, says `dialect bnf`; a `::=` that no parameter uses is reported with that hint.  `dialect abnf` reads the file as RFC 5234 reads ABNF, and `--abnf` (or `--dialect=abnf`) does the same for every file of a run: nothing is skipped between a rule's elements (`whitespace none`), a string is case-insensitive (`sensitivity string %i`), and a backslash in a string is a backslash (`"\"` is one character).  The two directives may be given alone.  A literal with no letters is never marked case-insensitive.  In a grammar with no `word`/`atom` and no `keywords`, a letter-led literal is its characters, not a keyword; a case-insensitive one matches either case, and inside a character rule (up to four letters) it is both cases.  `hidden nl gap` (a line) or `hidden nl = ...` (at the rule) names a rule that is only text and is to be matched and kept out of the tree: the rule that uses it has no field for it, in any backend, so no copy of its text is made, and a repeated or optional use of it is hidden too; for a hyperrule it hides every instance, and the grammar's start rule and a rule that builds structure cannot be hidden.  In the C backend a string in the tree is a slice of the input (`hbnf_sp(v)` is its text and `hbnf_sn(v)` its length, packed in the 8 bytes a pointer takes), copied only when an escape has to be undone or it is 65535 bytes or more, and a rule that is only a choice among other rules is a union with the number of the alternative taken (`_alt`, from 1); `--no-views` keeps the copies, which `--writer`, `--ast`, `--ast-tools`, `--idref`, `--forks`, `--compare`, grammars with bit fields and grammars with `context` always do.  `--root=RULE` generates from the named rule instead of the first.  Three things the reader does to an RFC's text so it need not be edited: a rule named like a built-in type (`atom`, `word`, `str`, `int`, `bool`, `flag`, `uN`, `iN`) that builds a structure is called `<name>-rule`, in the tree too, with a notice; a range in a rule that also names other rules becomes a rule of its own (`dtext-x21-5A`); and a union that needs backtracking is first-match-wins (above).  See `corpus/rfc/README.md`. |
| Rule names with `_`, comments carried into output, newline-before-`\|` continuation | — | ✓ |
| Left recursion | `xs = xs "," x \| x` | Direct left recursion is read as a loop (`x ("," x)*`) in all four backends; indirect left recursion is refused |

The list container is the one place the generated C is driven by
grammar-supplied fragments: the `listops { … }` block names each list operation
and its C text, so the daemon grammars spell out OpenBSD's `TAILQ_*` there
instead of `#define`ing macros in the preamble. hbnf's own structures are
plain C — the default list is a head/tail singly-linked list written directly,
and the arena chunk size is an `enum`, not a `#define`.

## 6. Whitespace uses ABNF's names

Where RFC 5234 has a name for a whitespace or line token, hbnf uses it rather
than inventing one:

| Name used earlier | ABNF name |
|---|---|
| SPACE | `SP` |
| TAB | `HTAB` |
| WS | `WSP` (`SP / HTAB`) |
| NL | `LF` (config files are LF-terminated; parse.y's `'\n'`) |
| CR, LF | `CR`, `LF` |
| — | `CRLF`, `LWSP` |

In the folded design these are grammar rules like any other:
- **Where whitespace counts:** a whitespace character is significant exactly
  where the grammar references it, and a separator everywhere else. The
  generator decides this when it builds the scanner, so it costs nothing at
  run time.
- **`LF`:** one per line feed. Backslash-newline is a continuation and produces
  none. A `#` comment ends before the line feed, as in parse.y.
- **The daemon grammars:** they use `LF` where parse.y has `'\n'`, and `optnl`
  as `*LF`.
- **Cost:** roughly one more token per line (+5.6% for a 100k-rule pf.conf).
  Matched whitespace is skipped, never stored in the tree.

`ws` in `hbnf_schema.hbnf` (`1*( "\n" / comment )`) is not `WSP`: it is
RFC 5234 §4's `c-nl` (`comment / CRLF`) repeated.

## 7. Closing the gaps

"Generation-time" means the generated parser pays nothing.  RFCPLAN.md
orders this work, and adds what an RFC's ABNF needs beyond it.

| Gap | Proposal | Runtime cost |
|---|---|---|
| Whitespace rules | §6, starting with `LF` | +1 token per line |
| The character layer | done in all four backends (CHARLAYER.md); converting the daemons' scanner actions to character rules retires the C-only scanner action stubs | same as a hand-written scanner action |
| `/` and `=/` between longer alternatives | union compiled without search (RFCPLAN.md decision 1, step 5) | none |

Checks at generation time for the §4 differences, turning silent mismatches
into schema errors:
- an alternative shadowed by an earlier one that matches a prefix of it;
- `*x x`;
- a literal that can never be one token.

## 8. Documentation that disagrees with the code

| Where | Says | Code |
|---|---|---|
| `USENIXSUBMISSION.md` §4.1–§4.3 | a code-point lexer generated from grammar rules, `where`, longest match | character rules compile to scanners with UTF-8 decode and maximal munch, but a fixed template still forms words, numbers and strings, and `where` is not implemented. Scanner actions are first match, in declaration order. |
