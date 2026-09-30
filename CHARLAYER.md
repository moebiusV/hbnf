# Character + binary layer — implementation plan (working note)

Goal: move hbnf's lexer from a fixed token template to a **generated,
character-level scanner**, so schemas can express JSON (and, later, binary
protocols) directly. Deliverable: a `json.hbnf` grammar that round-trips.

Scope (user directive, 2026-09-26):
- Character layer (char rules, named classes, `where`, maximal-munch lexer).
- UTF-8 code points as primitives (decode on input, match on code points).
- UTF-16 code points as primitives (`\uXXXX` surrogate pairs — what JSON needs).
- Binary/octet layer (`binary` mode, fixed-width whole-byte fields, `*u8`
  payloads) — **defer sub-byte `name:N` bitfield packing** (`version:4`,
  `flags:3`, `ihl:4`).
- Backend order: **C first** (flagship), then Ada, then Rust/Zig.

## Status (2026-09-26)

- **I0 — schema parser: DONE.** Numeric terminals `%b/%d/%o/%u/%x` (binary/
  decimal/octal/hex + `%u` Unicode code point bounded to `10FFFF`), character
  literals `'c'` (with C escapes), and `-` ranges between any two code-point
  designators (`'a'-'c'` = `%x61-63`). Endpoint order-insensitive (normalized
  to `Lo<=Hi`). Dotted concatenation (`%d13.10`) was rejected here at first;
  since RFCPLAN.md step 1 it reads as the code points in sequence. All parse
  into `Char_Range(Lo, Hi)` elements. `%` is the
  reader-macro dispatch prefix (what `#'` is to Lisp). Build clean; 9-daemon
  round-trip + server round-trip pass.
- **`grammars/ascii.hbnf` — DONE.** The ASCII names as a library grammar (no
  emitter code): `NUL`..`US` (C0 controls), `SP` `DEL` `DQUOTE` `HT` `HTAB`,
  and the RFC 5234 App B.1 classes `DIGIT ALPHA ALNUM LOWER UPPER HEXDIG BIT
  CHAR CTL VCHAR OCTET WSP`. Every rule matches one code point. (Uppercase,
  the ASCII/RFC spelling — *not* lowercase as an earlier draft had it.)
  `grammars/core.hbnf` includes it and adds `CRLF`.
- **I1 — C char lexer: DONE.** `Is_Char_Rule` classifies a rule whose pattern
  is an alternation of `Char_Range`; such rules get a `TOK_<name>` token kind,
  a `scan_<name>` scanner, and a `char_dispatch` the lexer calls after jets.
  The parser matches a char-rule reference with `expect_kind`. Verified
  end-to-end (`LF` lexes/parses; no regression).
- **I2 (UTF-8) — C char lexer matches code points: DONE.** `hbnf_decode_utf8`
  (emitted only when some rule is char-level) decodes the code point under the
  cursor; single-char scanners return its byte count, multi-char sequences
  advance a running byte offset. `%u20AC` (€) and `%x20-10FFFF` now match
  multi-byte sequences. `tests/utf8-test.sh` covers single-char, sequence,
  control and invalid-UTF-8 cases. (`where` is still deferred.)
- **I5 (Ada) — char lexer ported to the Ada backend: DONE.** `Atom_Cond` renders
  code-point conditions; `Decode_Utf8` + `Scan_<name>` + `Char_Dispatch` mirror
  the C scanners (maximal munch).  A char rule classifies as scalar
  `Unbounded_String`, and `Analyze`/`Is_Struct`/`Emit_Rule_Decl`/`Emit_Seq`/
  `Emit_Rule_Parser` handle it.  Verified end-to-end (`item = EURO | HIRAGANA |
  DIGIT` lexes `€あ7` as 3 tokens; `seq = EURO DIGIT` matches `€7` and rejects
  `€`/`7€`).  Rust and Zig then followed.
- **I6 (Rust) — char lexer ported to the Rust backend: DONE.** `Atom_Cond` renders
  code-point conditions; `decode_utf8` + `scan_<name>` + `char_dispatch` mirror
  the C scanners (maximal munch).  A char rule is scalar `String`; `Analyze`/
  `Emit_Seq`/`Emit_Rule_Parser` handle it, and the `Kind` enum gains a variant
  per char rule.  Naming: `Rust_Snake` now lowercases (UPPERCASE char names like
  `EURO`/`DIGIT` become `parse_euro`/`scan_euro`), and `Atom_Cond` drops the
  useless `c >= 0` lower bound that `-D unused-comparisons` rejects.  Verified
  end-to-end (the same grammars as Ada/C) plus `ascii.hbnf` compiles under
  `rustc -D warnings`.
- **I7 (Zig) — char lexer ported to the Zig backend: DONE.** Mirrors the Rust
  port (`decode_utf8` + `scan_<name>` + `char_dispatch` maximal munch; a char
  rule is scalar `[]const u8`; `Analyze`/`Emit_Seq`/`Emit_Rule_Parser` plus the
  `Kind` enum).  `Zig_Snake` lowercases and `Atom_Cond` drops the `c >= 0` bound,
  matching the Rust fixes; the Zig lexer template calls `char_dispatch` after
  `jet_dispatch`.  Verified end-to-end (single-char, sequence, control) +
  `ascii.hbnf` compiles + `portable.sh` passes all four backends.

## Loose ends (next)

1. ~~Dead field~~ **DONE** — char rules behave exactly like jets (scanner +
   `parse_rule` matching the token and capturing the text).
2. ~~Lists of char rules~~ **DONE** — `1*DIGIT` flows through `parse_rule_<name>`.
   ~~Root/alias edge case~~ **DONE** — `parse_rule_<name>` is correct, and an
   all-scalar schema emits `NODE_NONE` so `node_kind_t` is never empty.
3. ~~Multi-char char rules~~ **DONE** — `CRLF = CR LF` compiles to a >1-code-point
   scanner; `char_dispatch` does maximal-munch (longest match, ties by order).
   `Is_Char_Rule` moved to `HBNF_Compilable` (shared by C and Ada).
4. ~~UTF-8 / `%u` > 0xFF~~ **DONE** — scanners match decoded UTF-8 code points.
   A `hbnf_decode_utf8` helper decodes the code point under the cursor; a
   single-char scanner returns its byte count, a multi-char sequence advances
   a running byte offset; maximal munch is unchanged.  `%u20AC` (€) and
   `%x20-10FFFF` match multi-byte sequences.  This exposed a classification
   bug, now fixed: `Is_Char_Rule` rejects a repeated/optional element, so a
   list rule (`doc = 1*item`) is no longer mis-read as a char rule.  The
   stale `tests/syntax.sh` refusal (`%x41-5A`) became a `%d13.10` refusal.
5. ~~Ada backend~~ **DONE** — the char lexer is ported to Ada (`Decode_Utf8` +
   `Scan_<name>` + `Char_Dispatch` maximal munch; char rules are scalar
   `Unbounded_String`, handled by `Analyze`/`Is_Struct`/`Emit_Seq`/
   `Emit_Rule_Parser`).  ~~Rust and Zig~~ **DONE** — ported with the same
   shape (`decode_utf8`/`scan_<name>`/`char_dispatch`; scalar `String` in Rust,
   `[]const u8` in Zig), plus the naming fixes `Rust_Snake`/`Zig_Snake`
   lowercasing and the `c >= 0` bound dropped from `Atom_Cond`.  All four
   backends now pass `portable.sh` and `ascii.hbnf`.

## Remaining increments

- **I2 — `where`** refinements in the C lexer (UTF-8 code-point decode already
  landed above).
- **I3 — `json.hbnf`** flagship + round-trip test (`\uXXXX` via `utf16`).
- **I4 — binary/octet mode** (`binary`, fixed-width whole-byte fields, `*u8`).
- **I5 — Rust/Zig backends** — ~~port the char lexer~~ **DONE** (Ada, Rust, Zig
  all ported).

## Design decisions (settled)

1. **Numeric terminals / ranges** — `%b`/`%d`/`%o`/`%x` + `%u` (Unicode-bounded),
   `-` ranges, order-insensitive, dotted concatenation read as a sequence.
   See I0.
2. **Character literals** — `'a'` is a code point (C escapes), ranges with `-`.
3. **Named chars / classes as grammar, not code** — `ascii.hbnf` defines them
   as ordinary rules; the emitters stay generic.
4. **`where`** — `u16 = int where (v <= 65535)`; deferred (I2).
5. **UTF-8 / UTF-16** — code-point primitives; deferred (I2).  Encoding is a
   *stream-level* property (a stream is UTF-8 **or** UTF-16, one or the other),
   not a per-terminal one, so `%u` stays "code point, encoding-agnostic" and a
   `%uu` (UTF-16 unit) distinction is deferred — revisit only if a syntax ever
   intermingles the two encodings in one stream.  Code points are stored 32-bit
   (`Natural` = 32-bit already; the scanner is byte-level until I2).
6. **Binary** — `binary` directive + whole-byte fields + `*u8`; no sub-byte
   bitfields; deferred (I4).
7. **Char rules are tokens, expanded to DNF** — a char rule's pattern (a
   sequence/alternation of code-point atoms, string literals and Name
   references) is expanded to disjunctive normal form by `Char_DNF`: a list of
   branches, each a sequence of **atoms** — one code point, or (RFCPLAN.md
   step 4.1) a trailing repetition `n*m` of a character class.  A Name
   reference is inlined (its DNF distributed over the sequence position), so
   `A | B C` becomes two branches `[A]` and `[B, C]`, and `CRLF CRLF` (where
   `CRLF = CR LF`) becomes the single branch `[CR, LF, CR, LF]`.  A literal
   expands to one code point per character.  The scanner matches the longest
   branch — maximal munch — not a flattened `or` of single code points.

## Files touched (verified)

- `hbnf_grammar.ads` — `Element_Kind` + `Char_Range` (Lo, Hi); `Element` variant.
- `hbnf_grammar.adb` — `Lex` (`'`/`-`/`%` tokens), `Parse_Atom` (`%b%d%o%u%x`,
  `'c'`, `-` ranges), `Same_Element`.
- `hbnf_compilable.{ads,adb}` — `Is_Char_Rule` (shared classifier, used by the C
  and Ada backends) + `Walk`/`El_Nullable`/`Same`/`Image` accept Char_Range.
- `hbnf_c.adb` — token enum, `hbnf_decode_utf8`, `scan_*` + `char_dispatch`,
  `Emit_Seq` char-rule branch, `First_Elem`/`Collect` Char_Range arms.
- `templates/*_lexer.tmpl` — all four lexer templates (C, Rust, Zig, Ada) call
  `char_dispatch`/`Char_Dispatch` after jets.
- `hbnf_ada.adb` — full char-lexer port (`Atom_Cond`, `Decode_Utf8`, `Scan_*`,
  `Char_Dispatch`; a char rule is scalar `Unbounded_String`).
- `hbnf_rust.adb` — full char-lexer port (`Atom_Cond`, `decode_utf8`, `scan_*`,
  `char_dispatch`; a char rule is scalar `String`; `Rust_Snake` lowercases).
- `hbnf_zig.adb` — full char-lexer port (`Atom_Cond`, `decode_utf8`, `scan_*`,
  `char_dispatch`; a char rule is scalar `[]const u8`; `Zig_Snake` lowercases).
- `hbnf_match.adb` — exhaustive `case` Char_Range arms.
- `grammars/ascii.hbnf` — the ASCII names + classes.
- `tests/utf8-test.sh` — single-char, sequence, control and invalid-UTF-8 cases
  (run inside the toolchain image).
- `tests/syntax.sh` — the `%x41-5A` refusal became `%d13.10` (numeric terminals
  are supported now).

## Verification

- Build: `docker run --rm -v "$PWD":/work -w /work ada-toolchain:edge gnatmake
  -q -gnat2022 -I. -Itests hbnf_cli.adb -o /tmp/hbnf_cli` (host has gcc, not
  gnat). Then `cp /tmp/hbnf_cli /work/hbnf_cli.new`.
- C compile/run smoke: generate with `hbnf_cli.new … --backend=c`, `gcc
  -std=gnu11 -D_GNU_SOURCE`, run a small main.
- Regression: `sh tests/daemons.sh` (9 daemon grammars) and the `server.hbnf`
  round-trip via `hbnf_cli.new … --backend=c`.
