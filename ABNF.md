# hbnf and ABNF

hbnf is not ABNF. It borrows ABNF's rule notation (RFC 5234, and RFC 7405's
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
accepting and rejecting inputs. The Rust backend was spot-checked, and each
construct also went through the interpreter (`HBNF_Match.Match`). Zig was not
available and Ada output was compile-checked only where stated.

## Backends

The four compiled backends are **C**, **Rust**, **Zig** and **Ada**.  Planned,
not yet implemented, the rest of the compiled targets: **D**, **Fortran**,
**Free Pascal**, **Nim**, **Odin**, **Objective-C**, **ATS** and **V** — and,
beyond those, the garbage-collected languages **Go**, **Java**, **JavaScript**,
**Common Lisp** and **newLISP**.

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
read.  ABNF's `/` (union) is taken where it means the same as `|`, between
alternatives of one character each; RFCPLAN.md plans the rest, and the
other steps that let an RFC's ABNF compile as written.  The reader takes
RFC 5234's other forms: `=/`, `%d13.10`, `*m`, a rule going on to an
indented line, newlines inside `( )` and `[ ]`, and `<prose-val>`.

**Extended downward (design):** a schema can describe input below the token:
- characters, through character-level rules and named character classes;
- code points, with UTF-8 decoded on input;
- octets and bits, through `binary` mode and `name:N` bitfields.

In that design the lexer is not a stage of its own. Token definitions are
grammar rules — character-level ABNF or a hand-written jet — and the scanner is
generated from them.

**Extended upward (implemented):**
- a rule's name is its type, and the tree's shape is read from the rules;
- typed core rules (`str`, `word`, `int`, `u16`, `flag`, …);
- jets (scanners written in the target language, inside the schema);
- schema directives and code blocks;
- `--conf` and `--idref` output for OpenBSD daemons.

**Same spelling, different meaning:** alternation is ordered choice (PEG), not
ABNF's union; literals are case-sensitive, like parse.y keywords; a rule
referenced for a field is a type, not just a pattern.

**Left out:** nothing in RFC 5234's syntax is refused by the reader now.
Character classes are named rules (`grammars/core.hbnf`).  Some ABNF
features are not there yet in the backends (§3).

## 2. The layers: design and implementation

| Layer | Design (paper, `grammars/README.md`) | Implemented at this tree |
|---|---|---|
| Bits | `binary` mode: a field is `name:N` with N in bits, packed big-endian in RFC order, read by generated shift-and-mask code (§4.7) | No. `binary` / `a:4` → `unexpected character ':'`. The paper says "design, not yet implemented". |
| Octets | the unit of `binary` mode; `*u8` payloads; `dst:[6]` (§4.7) | No |
| Code points | UTF-8 decoded on the way in; the matcher works on code points; a literal can name `"café"` (§3.3, §5.2) | All four backends: yes. Each lexer's character-layer scanners decode UTF-8 (`hbnf_decode_utf8` in C, `Decode_Utf8` in Ada, `decode_utf8` in Rust/Zig) and match code points, so `%u20AC` (€) and `%x20-10FFFF` match multi-byte sequences. The interpreter still compares bytes (§2, §5). |
| Characters | character-level rules compiled to scanners (`int = ["-"] 1*DIGIT`, `money = 1*DIGIT "." 2DIGIT`); named classes `digit`, `alpha`, `hexdig`; `where` refinements; the lexer generated from these rules, taking the longest match (§4.1–4.3) | Partial. The numeric terminals `%b`/`%d`/`%o`/`%u`/`%x` and ranges parse (into a `Char_Range` element), and every backend compiles character-level rules to scanners with a maximal-munch `char_dispatch` (single-char, multi-char sequence, list elements); named classes come from `grammars/ascii.hbnf`. `where` is still deferred. |
| Tokens | jets as the fast path, each with its character-level fallback written above it; `wordchars` | Yes. The lexer tries the jets first, in declaration order, first match wins; then the character rules, longest match; then a fixed template (`templates/c_lexer.tmpl` and its Rust, Zig and Ada twins) that skips blanks and comments and forms words, numbers, quoted strings and punctuation.  `wordchars` widens the word set. RFCPLAN.md decision 7 replaces the template with grammar. |

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
| Concatenation, alternation, grouping | ✓ | ✓ | Alternation is ordered choice (§4). `\|` separates alternatives, as in BNF and yacc. ABNF's `/` (union) is taken between alternatives that each match one code point, where union and ordered choice are the same (`DIGIT / ALPHA`); between longer ones it is refused, with its line and a caret, until RFCPLAN.md step 5. The check covers only the rules the parser uses. |
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
| `<prose-val>` | ✓ reader | A rule nobody has written yet. If the parser would use it, generation stops with `file:line:col: not written yet, in `rule`: <…>`, the line, and a caret under it, for every such hole. A later `=` that defines the rule, or a jet, fills it. One in a rule the parser does not use is not reported. |
| `%s"…"` (RFC 7405) | ✓ | Means exactly what hbnf's bare `"…"` means |
| `%i"…"` (RFC 7405) | ✓ in all four backends | Any case matches; a `%i` keyword is interned case-insensitively in C. A word written both `%i` and plain is refused. snmpd's `auth` and `enc` use it, as parse.y's strcasecmp does. |
| `%scan{ … }`, `%action{ … }` | ✓ | The spelled-out forms of `name = { code }` (a jet) and `pattern { code }` (an action jet) |

### 3.4 Core rules (RFC 5234 Appendix B.1)

`include "core.hbnf"` defines them, from `grammars/`; it includes
`ascii.hbnf`, which names every ASCII code point.  A grammar may define any
of them again (a later `=` overrides).

| Name | ABNF | In hbnf |
|---|---|---|
| `SP`, `HTAB`, `CR`, `LF` | `%x20`, `%x09`, `%x0D`, `%x0A` | `ascii.hbnf`. Whitespace tokens, significant only where the grammar references them (§6). `LF` is parse.y's `'\n'`. |
| `WSP`, `CRLF` | `SP / HTAB`, `CR LF` | `WSP` in `ascii.hbnf` (one code point), `CRLF` in `core.hbnf` |
| `LWSP` | `*(WSP / CRLF WSP)` | Not yet: a character rule cannot repeat (RFC 5234 itself warns about `LWSP`) |
| `ALPHA`, `DIGIT`, `HEXDIG`, `BIT`, `CHAR`, `CTL`, `VCHAR`, `OCTET`, `DQUOTE` | character classes | `ascii.hbnf`; the character layer (§2). A file with `sensitivity rule-name %i` may write them `alpha`, `digit`, `hexdig`. |

## 4. Same spelling, different meaning

| Construct | ABNF | hbnf | Observed | Writing it in hbnf |
|---|---|---|---|---|
| The unit a rule matches | characters | tokens today (a fixed lexer); characters and below in the design | — | — |
| `"abc"` | case-insensitive | case-sensitive, like parse.y keywords | `ABC x` is rejected by both engines | `%s"abc"` is the ABNF spelling of hbnf's meaning |
| `"a b"`, `"!="` | a sequence of characters | exactly one token | never matches | `"a" "b"`; a multi-character operator is a character rule (`NE = '!' '='`) or a jet (pfctl's `ne`/`le`/`ge` still are) |
| `A / B` | union | hbnf writes `A \| B`: ordered choice, the first alternative that matches is kept, and a later failure does not come back for the next.  `/` is taken only between alternatives of one code point each, where the two agree. | `e = p "c"`, `p = "a" \| "a" "b"` rejects `a b c` in the interpreter; the compiled backends refuse the schema, since `"a" "b"` begins with the whole of `"a"` before it and can never match | longest alternative first |
| `*x x` | at least one `x` | never matches: `*x` takes every `x` | rejected by C, Rust and the interpreter | `1*x`, or restructure |
| A rule referenced twice in one alternative | two occurrences | one field named after the rule | *rejected* with a suggested alias. Previously the second value overwrote the first, in 37 places across the daemon grammars. | an alias rule: `port_hi = port` |
| Lowercase core names (`int`, `str`, `word`, …) | ordinary rule names | reserved types | — | don't define rules with those names |

## 5. What hbnf adds

| Extension | Syntax | Status and caveats |
|---|---|---|
| Typed core rules | `str`, `atom`/`word`, `int`, `bool`, `flag`, `u8…u64`, `i8…i64`; `dec`, `float` | C and Rust lack `dec` and `float` (interpreter only). `atom` rejects numbers in both engines. `bool` accepts any word (`maybe` → false). The compiled lexers reject `-5` for `int`/`iN`; the interpreter accepts it. Compiled `u16` accepts `70000`, truncated. `u7` emits `uint7_t`, which doesn't compile. |
| Tree typing from rule shape | — | Literal alternation → enum; single core type → scalar; `*( x )` → list (a whole rule); sequence → struct; keyword-led alternations get a kind tag; alias rules (`src = host`) name a field with another rule's type. Plus `free_<rule>`, visit/map, `--conf`, `--idref`. |
| Jets | `name = %scan{ code }`, or `name = { code }` | Code in the schema's `language`, which sees `s`, `pos` and `len` and returns the length it matched. The other backends get stubs that return 0: pfctl's C jets make `port != 80` parse in C and fail in Rust. A character rule does the same job in all four backends. |
| Actions | `pattern %action{ code }`, `pattern { code }`, or `action name { code }` | C only. Run bottom-up after a statement parses, with the rule's node as `n`; `bind_error()` reports as parse.y's `yyerror` does. The ntpd and unwind bindings (`grammars/bind/`) are built from them. |
| Schema directives | `language C\|Rust\|Zig\|Ada`, `wordchars "…"`, `include "file"`, `listops { … }`, `prefix "pf_"`, `conf struct …`, `entry name` | `include` is relative to the including file and goes before the file's first rule; a file is read once however often it is included. A later `=` overrides: a file's own rule overrides an included one, and of two included files the later one's wins. `language` is per file, the language of that file's own code blocks (C when absent), and a backend emits only the blocks in its language. The others describe the one generated parser: any file may set one, and two different values are an error; `keywords` lists merge; code blocks join in include order, included files' first. `prefix` goes in front of every generated C type and struct tag (`--prefix=` overrides it). `listops { head { … } entry { … } … }` names each of the eight list operations and its raw C, with `@name@`/`@elem@`/`@h@`/`@e@`/`@v@` substituted in; the nine daemon grammars set them to OpenBSD's `TAILQ_*` from `<sys/queue.h>`. An operation without an override falls back to hbnf's own head/tail singly-linked list. |
| Statements, macros, includes | `statements`, `macros <rule>`, `includes <rule>` | C only (the other backends warn and parse the whole file). `statements`: the root must be a list, `*( … )` or parse.y's own `config = | config entry`; the parser reads one statement at a time, one root entry each, as parse.y's `grammar : grammar entry '\n'`. A statement ends at a newline outside braces, quotes and comments; backslash-newline and a next line starting with `{` continue it. A failed statement is reported and the parse goes on. `macros varset`: a statement the rule matches whole defines a macro (first token the name, the tokens after `=` joined by spaces the value), and `$name` at the start of a word, outside quotes and comments, expands to it, glued to what follows; `cmdline_symset("n=v")` defines one the config cannot redefine. `includes include`: a statement the rule matches whole reads the file its last token names, relative to the working directory, as parse.y does. A file (`parse_file`, `parse_config`, an include) is read a block at a time, not whole. |
| Keyword table | `keywords { all any anchor … }` | C only. The words the lexer reserves, as parse.y's `lookup()` table: a letter-led literal in the table is a keyword (interned, refused as a `word`, dispatched on by id); any other literal matches a word by its text and reserves nothing, as parse.y's `STRING` compared with `strcmp`. A listed word no rule uses is still reserved. Without the directive every letter-led literal is a keyword. The nine daemon grammars carry their parse.y's table; `tests/bytetest/keywords.sh` checks that they match. |
| Code blocks | `{ … }` before the rules (preamble) and after (epilogue) | Copied verbatim |
| Escapes in literals | `\a \b \f \n \r \t \v \\ \" \' \xHH` | `\xHH` reads hex digits greedily, as in C |
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
| The character layer | done in all four backends (CHARLAYER.md); converting the daemons' jets to character rules retires the C-only jet stubs | same as a hand-written jet |
| `/` and `=/` between longer alternatives | union compiled without search (RFCPLAN.md decision 1, step 5) | none |

Checks at generation time for the §4 differences, turning silent mismatches
into schema errors:
- an alternative shadowed by an earlier one that matches a prefix of it;
- `*x x`;
- a literal that can never be one token.

## 8. Documentation that disagrees with the code

| Where | Says | Code |
|---|---|---|
| `USENIXSUBMISSION.md` §4.1–§4.3 | a code-point lexer generated from grammar rules, `where`, longest match | character rules compile to scanners with UTF-8 decode and maximal munch, but a fixed template still forms words, numbers and strings, and `where` is not implemented. Jets are first match, in declaration order. |
