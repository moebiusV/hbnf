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

## 1. The shape

**Borrowed from ABNF:** the rule syntax — `name = elements`, concatenation, `/`,
`( )`, `[ ]`, `n*m` repetition, `"…"` literals, `;` comments.

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

**Left out:** ABNF's `%d`/`%x`/`%b` numeric notation is left out by design
(`grammars/README.md`: "no `%d`/`%x`/`%b` printf-isms"); character classes are
named rules instead. Some other ABNF features are simply not there yet (§3).

## 2. The layers: design and implementation

| Layer | Design (paper, `grammars/README.md`) | Implemented at this tree |
|---|---|---|
| Bits | `binary` mode: a field is `name:N` with N in bits, packed big-endian in RFC order, read by generated shift-and-mask code (§4.7) | No. `binary` / `a:4` → `unexpected character ':'`. The paper says "design, not yet implemented". |
| Octets | the unit of `binary` mode; `*u8` payloads; `dst:[6]` (§4.7) | No |
| Code points | UTF-8 decoded on the way in; the matcher works on code points; a literal can name `"café"` (§3.3, §5.2) | No. Compiled lexers work on bytes (`café x` is rejected in C); the interpreter compares bytes. The paper's Status paragraph lists this as remaining. |
| Characters | character-level rules compiled to scanners (`int = ["-"] 1*DIGIT`, `money = 1*DIGIT "." 2DIGIT`); named classes `digit`, `alpha`, `hexdig`; `where` refinements; the lexer generated from these rules, taking the longest match (§4.1–4.3) | No. `digit`, `alpha`, `hexdig`, `decint`…`binint` → `undefined rule`; `where` → `undefined rule: where`. The Status paragraph lists the character-level grammar as remaining. |
| Tokens | jets as the fast path, each with its character-level fallback written above it; `wordchars` | Yes. A fixed lexer template (`Templates.C_Lexer`) forms words, numbers, strings and punctuation; jets run first, in declaration order, first match wins; `wordchars` widens the word set. |

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
| Case-insensitive rule names (§2.1) | ✗ | ✗ | `E` does not find `e`. Adopting ABNF's rule would make the README's `digit` the same rule as ABNF's `DIGIT`. |
| `=/` incremental alternatives (§3.3) | ✗ (C: `redefinition of struct e`) | ✗ (the first definition wins; the `=/` alternative is dropped) | The schema parser takes it as a second definition |
| One definition per rule | ✗ | ✗ | Duplicates are not diagnosed |
| Continuation by indentation (§4 `c-wsp`) | ✗ `expected '='` | ✗ | hbnf continues a rule only on a newline before `/` |
| Newline inside `( … )` | ✗ `expected ')'` | ✗ | |
| `;` comments | ✓ | ✓ | hbnf also copies them into the generated code |
| At least one element per alternative | accepts empty | accepts empty | `e = "a" word /` is accepted; ABNF forbids it |

### 3.2 Operators (RFC 5234 §3)

| ABNF | Compiled backends | Interpreter | Notes |
|---|---|---|---|
| Concatenation, alternation, grouping | ✓ | ✓ | Alternation is ordered choice (§4) |
| `( a / b )` inside a sequence | *rejected* | ✓ | Previously flattened to `a b` |
| `[ … ]` as a whole rule | ✓ | ✓ | |
| `[ … ]` inside a sequence | *rejected* | ✓ | Previously became required |
| Repeated group or reference inside a sequence | *rejected* | ✓ | Previously matched once, or did not compile |
| `*`, `1*`, `n*`, `n*m`, `n` on a list rule | ✓ bounds enforced in C; Rust/Zig/Ada treat every bound as `*` and the CLI warns | ✓ | Previously `1*` accepted an empty list in every backend |
| A list of a core type (`ws = 1*word`) | ✓ | ✓ | Previously failed to link |
| `*m` (`*2w`) | ✗ `expected a literal, name, or group` | ✗ | |
| Precedence (§3.10) | same | same | |

### 3.3 Terminal values (RFC 5234 §2.3, §3.4; RFC 7405)

| ABNF | Status | Notes |
|---|---|---|
| `"…"` | ✓ | Case-sensitive and must be exactly one token (§4). hbnf adds C escapes, which every emitter now re-escapes for its target language. |
| `%b` / `%d` / `%x`, ranges, `%d13.10` | ✗ by design | "No printf-isms": single characters are `"\xHH"`; classes are named rules (design, §2) |
| `<prose-val>` | ✗ | Jets fill this role: a scanner written in the target language |
| `%s"…"` (RFC 7405) | ✗ | Means exactly what hbnf's bare `"…"` means |
| `%i"…"` (RFC 7405) | ✗ | |

### 3.4 Core rules (RFC 5234 Appendix B.1)

None is defined: `undefined rule` in the compiled backends, an exception in the
interpreter.

| Name | ABNF | Role in hbnf |
|---|---|---|
| `SP`, `HTAB`, `CR`, `LF` | `%x20`, `%x09`, `%x0D`, `%x0A` | Whitespace tokens, significant only where the grammar references them (§6). `LF` is parse.y's `'\n'`. |
| `WSP`, `CRLF`, `LWSP` | `SP / HTAB`, `CR LF`, `*(WSP / CRLF WSP)` | Ordinary rules over the four above (RFC 5234 itself warns about `LWSP`) |
| `ALPHA`, `DIGIT`, `HEXDIG`, `BIT`, `CHAR`, `CTL`, `VCHAR`, `OCTET`, `DQUOTE` | character classes | The character layer (§2). The README spells them `alpha`, `digit`, `hexdig`: the same rules once names are case-insensitive. |

## 4. Same spelling, different meaning

| Construct | ABNF | hbnf | Observed | Writing it in hbnf |
|---|---|---|---|---|
| The unit a rule matches | characters | tokens today (a fixed lexer); characters and below in the design | — | — |
| `"abc"` | case-insensitive | case-sensitive, like parse.y keywords | `ABC x` is rejected by both engines | `%s"abc"` is the ABNF spelling of hbnf's meaning |
| `"a b"`, `"!="` | a sequence of characters | exactly one token | never matches | `"a" "b"`; multi-character operators need a jet today (pfctl's `ne`/`le`/`ge`) |
| `A / B` | union | ordered choice: the first alternative that matches is kept, and a later failure does not come back for the next | `e = p "c"`, `p = "a" / "a" "b"` rejects `a b c` in both engines | longest alternative first |
| `*x x` | at least one `x` | never matches: `*x` takes every `x` | rejected by C, Rust and the interpreter | `1*x`, or restructure |
| A rule referenced twice in one alternative | two occurrences | one field named after the rule | *rejected* with a suggested alias. Previously the second value overwrote the first, in 37 places across the daemon grammars. | an alias rule: `port_hi = port` |
| Lowercase core names (`int`, `str`, `word`, …) | ordinary rule names | reserved types | — | don't define rules with those names |

## 5. What hbnf adds

| Extension | Syntax | Status and caveats |
|---|---|---|
| Typed core rules | `str`, `atom`/`word`, `int`, `bool`, `flag`, `u8…u64`, `i8…i64`; `dec`, `float` | C and Rust lack `dec` and `float` (interpreter only). `atom` rejects numbers in both engines, although `hbnf_grammar.ads` says otherwise. `bool` accepts any word (`maybe` → false). The compiled lexers reject `-5` for `int`/`iN`; the interpreter accepts it. Compiled `u16` accepts `70000`, truncated. `u7` emits `uint7_t`, which doesn't compile. |
| Tree typing from rule shape | — | Literal alternation → enum; single core type → scalar; `*( x )` → list (a whole rule); sequence → struct; keyword-led alternations get a kind tag; alias rules (`src = host`) name a field with another rule's type. Plus `free_<rule>`, visit/map, `--conf`, `--idref`. |
| Jets | `name = { code }` | Code in the schema's `language`. The spec comment says `%{ … %}`, which is rejected. The other backends get stubs that return 0: pfctl's C jets make `port != 80` parse in C and fail in Rust. |
| Schema directives | `language C\|Rust\|Zig\|Ada`, `wordchars "…"`, `include "file"`, `list-head`/`list-entry`/…/`list-relink` `{ … }`, `prefix "pf_"` | `include` is relative to the including file, and a local rule overrides an included one. `prefix` goes in front of every generated C type and struct tag (`--prefix=` overrides it). The eight `list-<op> { … }` directives each supply the raw C for one list operation, with `@name@`/`@elem@`/`@h@`/`@e@`/`@v@` substituted in; the nine daemon grammars set them to OpenBSD's `TAILQ_*` from `<sys/queue.h>`. An operation without an override falls back to hbnf's own head/tail singly-linked list. |
| Code blocks | `{ … }` before the rules (preamble) and after (epilogue) | Copied verbatim |
| Escapes in literals | `\a \b \f \n \r \t \v \\ \" \' \xHH` | `\xHH` reads hex digits greedily, as in C |
| Rule names with `_`, comments carried into output, newline-before-`/` continuation | — | ✓ |

The list container is the one place the generated C is driven by
grammar-supplied fragments: the `list-<op> { … }` directives name each list
operation and its C text, so the daemon grammars spell out OpenBSD's `TAILQ_*`
there instead of `#define`ing macros in the preamble. hbnf's own structures
are plain C — the default list is a head/tail singly-linked list written
directly, and the arena chunk size is an `enum`, not a `#define`.

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

"Generation-time" means the generated parser pays nothing.

| Gap | Proposal | Runtime cost |
|---|---|---|
| Whitespace rules | §6, starting with `LF` | +1 token per line |
| Groups, optionals and repetition inside a sequence | Emit them (inline loops, or synthetic rules), then drop the rejection | none |
| Bounds in Rust/Zig/Ada | the counter the C backend now uses | one compare per element |
| The character layer | the design of §2: character-level rules compiled to scanners in every backend, which also retires the C-only jet stubs | same as a hand-written jet |
| `=/` | append alternatives, also across `include`, so a daemon can extend commonconf's `string` | none |
| Duplicate definitions | error | none |
| Case-insensitive rule names | fold for lookup; generated identifiers keep the spelling from the definition | none |
| ABNF continuation; newlines in `( )`; `*m` | adopt | none |
| RFC 7405 | `%s"…"` as a synonym; `%i"…"` as a case-folded keyword | only on `%i` keywords |

Checks at generation time for the §4 differences, turning silent mismatches
into schema errors:
- an alternative shadowed by an earlier one that matches a prefix of it;
- `*x x`;
- a literal that can never be one token.

## 8. Documentation that disagrees with the code

| Where | Says | Code |
|---|---|---|
| `hbnf_grammar.ads` | "The schema notation is plain RFC 5234 ABNF" | §1–§4 |
| `hbnf_grammar.ads` | `atom` is "a symbol or a number" | `atom` rejects numbers |
| `hbnf_grammar.ads` | jets are `name = %{ <code> %}` | `%` is rejected; the syntax is `{ … }` |
| `USENIXSUBMISSION.md` §3.3 | repetition, `[…]`, `;` comments are "extensions over ABNF", with "the usual ABNF semantics" | They are ABNF. Bounds were ignored before this series and still are outside C; `*m` isn't parsed. |
| §3.3 | multi-line rules as an extension | Replaces ABNF's continuation rule rather than extending it |
| §3.3, §5.2 | input decoded to code points | Not yet (§2) |
| §4.1–§4.3 | a code-point lexer, `ALPHA`/`DIGIT`/`DQUOTE`/`%x` in examples, `where`, longest match | Design, not yet implemented (§2). Jets are first match, in declaration order. |
| Status paragraph | zero-copy slices and the arena as "remaining increments" | Both have landed |
| `grammars/README.md` | newline handling is unnecessary because keywords delimit entries | `string` accepts keywords, so pfctl's `a = "em0"` followed by `pass in on em0` parses as one macro |
