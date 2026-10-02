# One notation for daemon configs and RFC grammars — the plan (working note)

Agreed 2026-09-28.  The goal: paste RFC 5234-family ABNF and get a
working parser, and make the nine daemon grammars smaller, clearer and more
coherent on the way.  There is one parsing model, not two profiles, and the
generated parsers stay recursive descent, linear in their input, with no
unbounded backtracking.

Where the tree stands, and what this plan builds on: CHARLAYER.md (numeric
terminals, `'c'` literals, `ascii.hbnf`, UTF-8 scanners in all four
backends).  Where the notation differs from ABNF today: ABNF.md §4.

## Corpora

Two validation corpora, both exercised every step.

**Daemon corpus.**  The nine OpenBSD daemon grammars (bgpd, dhcpleased,
httpd, ldpd, ntpd, pfctl, relayd, snmpd, unwind), each derived from that
daemon's `parse.y`.  These are drop-in replacements: their parsers accept and
reject exactly what parse.y does (byte-identity for ntpd, unwind-identity
elsewhere).

**RFC corpus** (`tests/rfc/`).  The BNF fragments of the RFCs, pulled in whole
where they compile and in pieces where they do not.  Each fragment keeps:

- the RFC's ABNF verbatim — a `.hbnf` when it compiles as-is;
- the error messages hbnf gives and what each means;
- the **fixed-up** version, or — where the repair is involved — a note saying
  how to make it (e.g. a `<prose-val>` that defers its real definition to two
  or three other RFCs is rewritten to the rules those RFCs give, with the
  provenance named).

The corpus is where discoverability is proven: a fragment is "done" when its
messages alone tell the author how to fix what hbnf could not accept
silently.

## Decisions

1. **Two alternation operators, two meanings.**
   - `|` is ordered choice, as in PEG and as parse.y grammars are read:
     the first alternative that matches wins.  The shadowed-alternative
     check stays.
   - `/` is ABNF's union: every alternative is legal.  Between character
     ranges it is a set, the same as `|`.  Between phrases it is compiled
     without search:
     - alternatives whose FIRST sets (and, for an optional or repeated
       part, FIRST and FOLLOW) are disjoint become ordinary one-token
       decisions;
     - alternatives that share a prefix are factored (`p = "a" / "a" "b"`
       becomes `p = "a" [ "b" ]`);
     - anything else is an error that says to write `|`, longest first,
       or to factor it by hand.
2. **Incremental alternatives are `=/`, ABNF's spelling, and nothing
   else.**  No BNF dialect we know has `=|` or `|=`.  (yacc gets the same
   effect by allowing `name :` more than once.)  `=/` extends the current
   definition; an `=/` with no `=` before it is an error.  The new
   alternatives join with `/`, so `=/` is union, and compiles where `/`
   does.
3. **A later `=` overrides.**  It replaces the earlier definition, in the
   same file or another; the rule keeps its place, so an overridden root is
   still the root.  (As built: in one file, or between two included files,
   the rule keeps its place; a file's own rules come before what it
   includes, in the order it writes them, since that order is the jets'
   order.  The root is the top file's first new rule, or, when it has none,
   the root of what it includes.)
4. **Include once.**  A file is read the first time it is included; later
   includes of it (by any path to the same file) do nothing.
5. **Directives come in two kinds.**
   - *Per file*: those that change how the text of their own file is read.
     They apply only to that file; an including or included file is not
     affected.  `language` (the language of the file's code blocks) today;
     `sensitivity` and `whitespace` (below) when they land.
   - *Whole parser*: those that describe the one generated parser:
     `statements`, `macros`, `includes`, `keywords`, `conf`, `entry`,
     `prefix`, `listops`, `wordchars`.  Any file may set one (`tailq.hbnf`
     exists to set `listops` for all nine daemons); two files that set one
     differently are an error.  `keywords` lists from several files merge.
     Code blocks (the `{ … }` preamble and epilogue) are joined in include
     order.
6. **`sensitivity`**, per file, two independent axes:

       sensitivity %i                     ; rule names and literals
       sensitivity rule-name %i           ; `digit` finds `DIGIT`
       sensitivity string %i              ; `"HTTP"` matches `http`

   The default is `%s` on both, today's behaviour.  A literal's own `%i` or
   `%s` always wins.  A folded rule name keeps the spelling of its
   definition in generated identifiers; a reference that folds to two
   different rules is an error.
7. **One parsing model: characters, not a hidden lexer.**  Today a
   generated parser cuts its input into words, numbers, quoted strings and
   punctuation first, skipping blanks, and the rules match those tokens.
   So `"x" "y"` accepts `x y` and rejects `xy`, the opposite of ABNF, and
   `1*VCHAR` fails on `/x` because `x` was already made a word.  The
   generated parser will instead read characters: a literal compares bytes
   at the current position, a character rule's scanner runs at the current
   position, and a jet is called there.
   - The old lexer becomes grammar in a shared include: `word`, `number`,
     quoted strings with escapes, `#` comments and backslash continuation,
     as character rules anyone can read and change.  `wordchars` becomes a grammar rule.
   - **`whitespace ws`**, per file: phrase-level rules in that file skip
     the rule `ws` between their elements; character rules never do.
     Daemon grammars say `whitespace ws` with `ws = SP | HTAB | comment`;
     RFC grammars do not, and match `SP`, `WSP` and `CRLF` where they write
     them.
   - Keywords stay a table: a word listed there does not match `word`.
   - Speed: the current lexer is fast because it cuts tokens once and
     branches on keyword ids.  The character model keeps that by
     remembering the last token scanned at a position and branching on the
     first byte.  The §6 numbers (57 ms for the 100,000-rule toy, about
     0.5 s for 100,000 pfctl rules) must not get worse.
8. **Jets and actions are code.**  A `%scan{ }` or `%action{ }` block holds
   the code that runs, usually one call to a function the file defines in
   its epilogue (`%scan{ return ipv6_match(s, pos, len); }`), with the
   function's prototype in the preamble.  hbnf never rewrites the code.
   Most of today's 29 jets become character rules instead, which also makes
   them work in Rust, Zig and Ada.
9. **`<prose-val>`** reads as a rule nobody has written yet: generation
   stops with `file:line:col`, the source line with a caret under the
   `<…>`, and "not written yet:" and the text in the angle brackets.  The
   author writes the rule or a jet.  A hole left for later is then a
   schema error that points at itself, rather than an `XXX` in a comment.
10. **Core rules.**  `common.hbnf` includes `ascii.hbnf` and holds the RFC 5234
    Appendix B.1 classes (`DIGIT`, `ALPHA`, …, `WSP = SP | HTAB`) and
    `CRLF = CR LF`; `ascii.hbnf` holds the named single characters (the C0
    controls, blanks, `DEL`, `DQUOTE`).  `LWSP` waits for repetition
    inside character rules, which `Is_Char_Rule` refuses today.
11. **Negation is `~`.**  `~rule` matches one code point not in the set
    `rule` matches (a complement); repetition composes, so `*~rule` is
    "until rule" (SNOBOL's `BREAK`).  A hbnf extension — ABNF has no
    negation — and it collapses the explicit `%x` complements the lexer
    rules would otherwise spell out: `comment = "#" *~LF`,
    `string = DQUOTE *( "\\" %x00-10FFFF | ~(DQUOTE | "\\") ) DQUOTE`.
12. **Comma lists are `#`.**  `#` is `*` with an implicit comma separator:
    `n#m element` is comma-separated repetition, `#element` is `1#element`.
    It is sugar for `element *("," element)` — the same list the daemon
    grammars write left-recursive — so it inherits parse.y's semantics: no
    trailing comma, no empty elements.  Deliberately stricter than HTTP's
    `#rule`, which allows empty elements (a known server-bug source).

13. **Context-sensitivity: a pure predicate, not a parse-time action.**  C
    is the standing example: with `typedef int A;` in scope, `(A) * 0` is a
    cast of `*0`, and with `int B;` in scope `(B) * 0` is a multiplication.
    The two cannot be told apart without consulting a symbol table *during*
    the parse, so no context-free grammar settles it.

    The bar here is lower than it looks, because tree-sitter does not solve
    this either.  Measured 2026-10-01 against tree-sitter-c: both lines
    produce the *same* tree, `(binary_expression (parenthesized_expression
    (identifier)) (number_literal))`.  The typedef case is simply wrong — it
    has a `cast_expression` rule and cannot tell when to use it, so
    precedence picks multiplication both times.  That is fine for
    highlighting and is not a correct parse.  So "as general as
    tree-sitter" does not require this; being *right* does.

    When it is wanted, the shape is a **predicate**, which is not the
    parse-time action hbnf refuses:

        typedef-name = word &{ hbnf_is_typedef(tok, len) }

    The distinction is the whole reason it is admissible.  An `%action{}` has
    effects, so it must run once, after the parse, bottom-up — ordered choice
    backtracks, and a re-run action would double its effects.  A predicate is
    a *pure query*: no effects, idempotent, safe to evaluate as often as
    backtracking needs.  Rules: it may read state, never write it; its value
    may not depend on evaluation order; and the state it reads is written
    only by `%action{}` after the parse, or by the author's own code before
    it.  A predicate that writes is the yacc lexer hack, with yacc's
    problems, and stays refused.

    This is a separate axis from step 9 and much less certain, so it waits
    until a grammar actually needs it.  It also does not make hbnf ambiguous:
    the predicate decides a branch, it does not explore several.

## POSIX BNF

Step 7's copy-paste goal is for RFC ABNF.  POSIX's own grammars are a
second notation worth the same treatment: the yacc BNF POSIX writes its
standard utilities in — `name : rhs`, `;`-terminated, `%token`
declarations, `/* … */` comments, and left recursion for every list.  The
test case is the **Shell Command Language grammar** (POSIX.1 §2.10, the
Bourne shell): the largest such grammar, and the one that leans hardest on
yacc's tokenizer feedback, so it exercises every difference at once.  It
becomes a third corpus once the reader work below lands.

The bar is the RFC one: a pasted spec is corrected by the messages, not by
reading the manual.  POSIX BNF needs one change to the pasted text — give
each `%token` name a definition — and one rewrite where yacc steers its
lexer from the parser and hbnf's character model makes the steering
unnecessary.  Both are kinds hbnf already knows how to point at.

**Pasted unchanged (reader extensions).**

| POSIX BNF | hbnf | how |
|---|---|---|
| `name : rhs` | `name = rhs` | `:` read as `=` (with `::=` and `:=`, step 7).  `name:N` wire widths are not yet implemented; when they are, a width is `:` glued to the name and a rule's `:` is surrounded by blanks, so the two never clash. |
| `;` after a rule | a `;` comment | `;` already starts a comment and POSIX puts it at end of line, so the rule ends at the newline; a lone `;` line under the last alternative is an indented comment line and is skipped.  `';'` (quoted) stays the semicolon *operator*, distinct from the bare terminator. |
| `'|'`, `'('`, `')'`, `'&'`, `';'`, `'<'`, `'>'` | `'|'` &c. | the one-character literal is hbnf's `'c'`; `'('` and `')'` are quoted, so they do not group. |
| `\|` | `\|` | ordered choice, parse.y's own reading. |
| left recursion | a loop | direct left recursion is already `y (t y)*`, and the shell grammar's is all direct: `pattern : pattern '|' WORD` becomes `WORD *("|" WORD)` — the case pattern with a literal `|`. |
| `/* … */` | a comment | read as a comment alongside `;` (no nesting).  `| /* empty */` is then a trailing empty alternative, which is accepted; the message suggests the plainer `[ … ]`. |
| `%token NAME`, `%start R`, `%%` | declared, root, nothing | `%token` registers the name as declared-but-undefined, `%start` names the root, `%%` is dropped. |

**The one alteration: define the `%token` names.**  A declared name that
no rule defines is an error that names the definition, by kind:

- operators — `%token DLESS` with POSIX's `/* '<<' */`:
  `shell.y:7:10: DLESS is declared %token but not defined; write
  DLESS = "<<"`.  The spelling is the name's known spelling (the quoted
  text in POSIX's comment, or a table): `AND_IF`/`&&`, `OR_IF`/`||`,
  `DSEMI`/`;;`, `DLESS`/`<<`, `DGREAT`/`>>`, `LESSAND`/`<&`,
  `GREATAND`/`>&`, `LESSGREAT`/`<>`, `DLESSDASH`/`<<-`, `CLOBBER`/`>|`.
- reserved words — `%token If`: `If is declared %token but not defined;
  write If = "if"` (the lower-cased name; `Lbrace`/`Rbrace`/`Bang` are
  `"{"`/`"}"`/`"!"`).
- lexical classes — `%token WORD`: `WORD is declared %token but not
  defined; write WORD = …` — a char rule the author supplies (`NEWLINE`
  is `LF` from common.hbnf; `NAME`, `IO_NUMBER`, `WORD` and
  `ASSIGNMENT_WORD` are class rules).

**The one rewrite: tokenizer feedback becomes structure.**  The shell
grammar's rules 1–10 tell the lexer which token a word is — `WORD` or
`ASSIGNMENT_WORD`, a reserved word or not — by parser state.  hbnf has no
lexer to steer; the same distinction is ordered choice over char rules,
and most of the hacks disappear:

- `cmd_prefix` takes `ASSIGNMENT_WORD` where `cmd_word` takes `WORD`.
  Define `ASSIGNMENT_WORD = NAME '=' word` as a char rule — no whitespace,
  as POSIX requires — and `WORD = word`; then `foo=bar` is an assignment
  where the grammar has `cmd_prefix` and a plain word where it has
  `cmd_word`, with no lexer state steering it.  yacc needs the feedback
  because its lexer must cut `foo=bar` into one token before the parser
  sees it; hbnf matches the char rule at the position.
- reserved-word recognition (rules 1 and 6) is positional, so the global
  `keywords` table is the wrong tool: it reserves everywhere.  The message
  says so: `if is reserved only in command position; do not list it in
  keywords — write it as the "if" alternative in the rules that recognize
  it`.  The grammar then spells `if`/`then`/… as literal branches of
  `cmd_name` and `compound_command`, not as a keyword table.

What does not paste is lexical, not grammatical: alias substitution (rule
10) rewrites the input before the parser sees it, and stays out of scope
as it is for the daemon grammars.  The residue that is grammatical but
needs a symbol table mid-parse is decision 13's predicate, deferred — the
shell's reserved words resolve by position, not by name binding, so this
grammar does not need it.

**Order.**  The reader extensions and the `%token` diagnostics ride with
step 7a, which is first in the running order and carries the assignment
operators and the comment styles — `/* … */` here, and `(* … *)` with it,
since a notation whose `:=` hbnf accepts should take its comments too.
The token messages are the RFC-corpus discoverability test applied to
POSIX.  The gate: POSIX.1 §2.10 pastes
with only the definitions the messages name, and the resulting grammar
parses the test suite's own shell command lines.

## Compiler-compiler completion criteria

The end state is deliberately broader than "an ABNF parser generator": one
human-readable grammar describes syntax, lexical boundaries, wire
representation and semantic construction, so the author never maintains a
separate lex spec, yacc semantic-value protocol, AST schema and serializer.
`%scan{}` and `%action{}` stay the escape hatches for target-language code;
the remaining work adds the *interfaces around* them — not yacc's global
state (`yylval`, `yyparse`, `$1`/`$$`), LR tables, or GLR.

A grammar is compiler-compiler ready when:

1. **Source locations are first-class.**  Every node and semantic value keeps
   a source span; diagnostics name file, line/column and the span, not just
   the current token.
2. **Semantic values are typed and named.**  `%action{}` sees named children,
   not positional `$1`/`$2`; impossible assignments are rejected at generation
   time where the target language allows it.
3. **Parser state is reentrant.**  Input position, diagnostics, scanner state
   and semantic state ride in an explicit context; no global parser state.
4. **Scanner modes are first-class.**  `%scan{}` gets a flex-style
   start-condition mechanism with push/pop, for strings, interpolation,
   heredocs and other lexical sublanguages; a small state machine, not a
   second grammar language.
5. **Input sources are abstracted.**  Memory buffer, file stream or
   caller-provided source, with contiguous memory as the fast path.
6. **Error recovery is explicit and opt-in.**  Fail-fast stays the default; a
   grammar may declare synchronization points, and recovery never runs
   `%action{}` side effects speculatively.
7. **Wire values are semantic values.**  Width, signedness, endianness, exact
   byte sequences and range constraints are explicit; `u8`/`u16` mean the same
   in the interpreter and every backend.
8. **One semantic model.**  The interpreter and all emitters agree on ordered
   choice, repetition, left recursion, characters and wire values; a backend
   limitation is a generation-time error, never a silent divergence.
9. **Progress is an invariant.**  Every unbounded repetition and rewritten
   left-recursive tail consumes input or terminates.
10. **The representation is inspectable.**  A shared semantic IR beneath the
    templates, rendered by the Mustache-style `{{ }}` renderer in
    `templates.adb` (a recursive Scalar/List/Map context), so a compiler can
    inspect rules, locations, semantic values and wire values before
    emission.  *The renderer is written; nothing calls it yet, and the
    templates are still `${name}` and `@PLACEHOLDER@* — see step 3b.
11. **Round-trip and byte-identity gates are mandatory.**  Text grammars keep
    their source/value distinctions; wire grammars have byte fixtures; the
    backends agree with the interpreter on acceptance and values.

**RFC copy-paste is a design goal.**  An RFC's ABNF should compile almost
verbatim.  Spelling variants (`::=`, `:=` for `=`) are accepted silently —
silence makes cut-and-paste easier — and where hbnf needs something different,
the error names the RFC form and says how hbnf spells it, so a pasted RFC is
corrected by the messages, not by reading the manual.

## Order

Each step leaves the nine daemon grammars, e2e, byteident (ntpd) and
unwind-ident passing; each lands as reviewed patches.

The numbers are stable labels — error messages and comments in the code
cite them — so a step that moves keeps its number and this list gives the
running order:

> **0, 1, 2, 3, 4a–4e done; 9a done.**  Then **7a first**, then **9b**,
> **3b**, **5**, **6**, **7b**, **8**, **4f**, **10**.  **11** is not gated
> on any of them.

Three principles decide that order.  **Syntax first**: 7a — the
copy-paste assignment operators and comment styles — goes ahead of
everything, because it is reader-only, costs nothing to land, and every
grammar anybody tries after it is cheaper to try.  **Correctness before
speed**, which is why 4f sits near the end holding its measurements rather
than near the front.  And **a step waits for what it reads against**,
which is why `where` moved to 6 and the wire layer (7b) stayed behind it.

0. **Docs and comments that disagree with the code**; include once; the
   two kinds of directive; a later `=` overrides.  *Done 2026-09-28.*  An
   include goes before the file's first rule (so "later" is always
   textual), and a schema error names its file.
1. **Reading grammars** (no backend work):
   - `=/`; `sensitivity`; `/` between character ranges;
   - `%d13.10`, `*m` (`*2DIGIT`), continuation by indentation (ABNF's
     `c-wsp`), newlines inside `( )` and `[ ]`;
   - `<prose-val>`; `WSP`, `CRLF` and `common.hbnf`.

   *Done 2026-09-28.*  Also: `/` is checked only in the rules the parser
   uses, like `<prose-val>`, so an included RFC's rules can be replaced;
   two rules whose names differ only in case are refused (the generated
   identifiers would clash); `%X41` and `%I"…"` read as `%x41` and
   `%i"…"`; and the CLI prints a schema error whole (GNAT keeps 200
   characters of an exception's message).
1b. **Lists as parse.y writes them.**  *Done 2026-09-28.*  The nine
   grammars' lists that parse.y writes left-recursive are left-recursive
   (90 rules), with parse.y's `comma` written out (`xs = xs ',' y | xs y |
   y`; a `comma` rule once the backends can take one).  That also makes the comma lists accept what parse.y accepts: no
   trailing comma, no empty `{ }` list in bgpd, and snmpd's leading comma.  Lists parse.y writes right-recursive stay
   `*( y )`.
2. **Groups, optionals and repetition inside a sequence**: rewritten into
   hidden named rules before code generation, so all four backends get them
   at once and the three rejections go.  (An optional word then records
   whether it was there, instead of `0*1( "log" )`.)  *Done 2026-09-28*
   (`HBNF_Grammar.Lift`): the new rules are named `<rule>_<n>`;
   tests/portable reads one of each through all four backends.  `'c'` in
   a rule of words is the one-character literal, and the list commas read
   `','` (a `comma` rule once the backends take a rule that is only
   literals and an empty alternative).
3. **`${name}` templates** for the emitters: each construct's code in a
   small file per language, `$$` for a literal `$`, an unfilled or unused
   hole an error.  Pilot on Zig; the gate is byte-identical output for
   every schema through every backend.  *Done* — 71 `.tmpl` files loaded
   from disk at startup, nothing baked in.

   3b. **The Mustache renderer is written and nothing uses it.**  Measured
       2026-10-02, in the tree: `Templates.Render_Template` implements the
       subset — `{{var}}`, `{{.}}`, `{{#each}}`, `{{#var}}`/`{{^var}}`
       sections, `{{> partial}}` — over the recursive Scalar/List/Map
       context model in `templates.ads`, with a scope stack that shadows
       and inherits.  **Zero callers.**  No `.tmpl` file contains `{{`.
       The three hole styles as they actually stand:

       | style | templates | emitter calls |
       |---|---|---|
       | `${name}`, flat binding table | 52 | 51 `Templates.Render` |
       | `@PLACEHOLDER@`, plain substitution | 14 | 17 `Templates.Substitute` |
       | `{{ }}`, recursive context | **0** | **0** |

       So completion criterion 10 and step 6 below, which both speak of
       "the Mustache-style renderer in `templates.adb`" as though it were
       in use, describe the renderer correctly and its use not at all.
       That is the gap, and it is the whole of it: the per-element loops
       `{{#each}}` exists to absorb are still written out in Ada in each
       backend (`for M of Info.Members loop ... Append (Items, ...)`), one
       copy per backend, which is also why the step 9a fix had to be made
       in two places before it was folded into one `Field_Decl`.

       The work: move the 52 `${name}` templates and the 14
       `@PLACEHOLDER@` templates to `{{ }}`, build the context tree in each
       emitter instead of a binding table, and delete `Render` and
       `Substitute` once nothing calls them.  The gate is step 3's own:
       byte-identical output for every schema through every backend, all
       132 snapshot files.

       **One decision first, and it is not mine to make.**  `templates.adb`
       carries its own inline implementation of the subset.  There is also
       `moebiusV/mustache-ada`, a real port, with an aport in
       `ada-on-alpine`.  Those are two implementations of the same thing.
       Either hbnf gains a dependency on the aport and `templates.adb`
       keeps only the loader and the context builders, or the inline subset
       stays and the plan stops implying otherwise.  Nothing in the tree
       references the aport today: no `with` clause, no `.gpr` dependency,
       no submodule.
4. **The character model** (decision 7) in C, with `whitespace`:
   - the old lexer moved into a shared include;
   - ntpd converted first (it has the byte-identity proof), then the other
     eight, their jets turned into character rules where they can be;
   - §6 measured again.

   Dependency order within step 4:

   4a. **Char-rule literals and repetition.** Lift `Is_Char_Rule` and
       `Char_DNF` so a char rule may hold a string literal (a fixed run of
       code points) and a repetition (`*`, `1*`, `n*m`) of a character class
       (`word = 1*ALNUM`, `hexnum = "0x" 1*HEXDIG`).  The scanner
       becomes a sequence of atoms, each one code point or a greedy repeat
       loop; maximal munch is unchanged.  First slice: repetition only over a
       single-code-point class (a repetition of a longer sequence such as
       `1*CRLF` stays a list, as before), only as the last atom of a branch
       (nothing after it), no `%i` literal inside a char rule, no nested
       repetition — each a clean generation-time diagnostic, lifted when a
       grammar needs it.  Gate: byte-identical output for the existing char
       rules.

   4b. **Lexer as grammar.** *Done* (c2eb521 and the obconf work).  The old
       lexer's `word`, `number`, quoted strings with escapes, `#` comments
       and backslash continuation are char rules in `obconf.hbnf`, and
       `wordchars` is a grammar rule (`wordchars = ALPHA | DIGIT | "_" |
       "-" | "."`), overridable per daemon, not a directive.  Keywords stay
       a table (a listed word does not match `word`).

   4c. **Character-model parser in C.** *Done* (98f462a, c69574c, 98cbbd2).
       `parser_t` is text/len/pos with no pre-cut token array; a literal
       compares bytes at the position, a char-rule reference runs its
       scanner there, and `whitespace ws` makes phrase-level rules skip `ws`
       between elements (character rules never do).  Keywords still branch
       on the first byte.  Memoization (caching a rule's result at a
       position) was deferred as an implementation optimization, to be added
       **only if the §6 numbers regress**; it never changes what is
       accepted.  They did — see 4f.

   4d. **Convert ntpd first**, then the other eight daemons; jets become
       character rules where they can.  *Done* (26366f1 and the 4d merge):
       the operator, wildcard and AS jets are char rules, and 18 jets remain
       across all nine grammars.

   4e. **Coalesce ASCII char-rule scans into byte loops.** *Done*
       (0de04f6).

   4f. **The gate is not met for pfctl: pay for it with the memoization 4c
       deferred.**  Measured 2026-10-02, the same machine, the same inputs,
       the harness's own best-of-five, pre-4c (c2eb521, token array) against
       current:

       | case | pre-4c | character model | |
       |---|---|---|---|
       | toy 100,000 | 64 ms, 53 MB | **50 ms, 21 MB** | 1.27x faster, 2.5x leaner |
       | toy 1,000,000 | 675 ms, 517 MB | **496 ms, 196 MB** | 1.36x faster, 2.6x leaner |
       | pfctl 100,000 | **666 ms**, 378 MB | 1052 ms, 378 MB | **1.58x slower** |

       The toy improved on both axes, and dropping the token array is why
       the memory more than halved.  pfctl went the other way, and against
       the gate as written ("about 0.5 s for 100,000 pfctl rules") it is now
       about 2x over.

       The cause is the one 4c anticipated.  §6's profile already found
       about 170 literal probes per rule, "most of them failing as ordered
       choice tries each alternative in turn".  With a token array a failing
       probe compared a token that had been cut once; with the character
       model each failing probe re-scans the characters.  pfctl's 35-way
       filter-option alternation pays that on every branch, and the toy —
       one shape, no wide alternation — does not.  So the regression is
       concentrated exactly where the design predicted, which is why the
       remedy was planned rather than invented now:

       - **Cache the scan, not the rule.** Key a char-rule scan by (rule,
         position) and reuse the length and kind.  That is what the token
         array did implicitly, restored without materialising the array.
       - Bound the cache so memory does not go back up (pfctl's 378 MB is
         already the number to beat, and it has not moved).
       - It must not change what is accepted: the gate is the full corpus
         plus byte-identity, unchanged.

       Also: **§6's table was wrong**, which the project's own rule forbids
       — paper claims match measurements.  It has been re-measured and
       corrected on the author's workstation (an AMD Ryzen 5 7600).

       **Measured again 2026-10-02, properly this time, and 4f now waits
       behind step 9.**  Make it correct, then make it fast.  The three 4f
       commits took the pfctl regression from 1.58x to 1.29x, which is
       progress and not the gate; the rest of the gate is bought with work
       that belongs after the correctness items, so this entry records what
       is known and stops.

       *Method, because the first pass got it wrong.*  Wall-clock numbers
       from different sessions are not comparable: this VM ran 1.35x slower
       in the afternoon than in the morning, and the proof is the toy
       parser, whose generated C is byte-identical across all three 4f
       commits — it measured 42.9 ms in the morning and 57.9 ms in the
       afternoon on the same input.  An earlier reading of 940 ms against
       900 ms, which looked like upstream's two commits costing 40 ms, was
       entirely that drift.  So: every comparison interleaves the builds in
       one run (run A, run B, run C, repeat, keep each build's best), and
       `valgrind --tool=callgrind` instruction counts are the noise-free
       metric — deterministic, and they do not care what else the host is
       doing.  `bench/section6.sh` should grow both: a `CLOCK_PROCESS_CPUTIME_ID`
       option and an interleaved A/B mode.

       | build | pfctl 100,000, CPU ms, best of 9, interleaved | vs baseline |
       |---|---|---|
       | c2eb521, pre-4c, token array | **824** | 1.00x |
       | f709353, the skip_ws fast path and the hoist | 1129 | 1.37x |
       | cc89c9e, + first-byte dispatch | 1088 | 1.32x |
       | 598dd10, + per-branch reset | 1054 | 1.28x |

       So upstream's two commits did help, about 7% between them; the
       earlier worry that they had cost time was the drift above.  The
       instruction counts say the same thing without the noise: 190.3M for
       the token array against 306.6M now, 1.61x, at 5,000 rules.

       *Where the extra 116M goes* (callgrind, 5,000 rules).  New in the
       character model: `scan_word` 65.5M, `skip_ws` 40.2M, `fail` 23.8M,
       `expect_word` 13.3M, `scan_int` 5.4M — 124.4M of scanning against
       the token model's `lex` 23.8M plus `lex_word_char` 3.9M.  Everything
       else roughly cancels (`expect_lit` 33.5M -> 21.4M, `parse_tokens`
       8.7M and `expect_kind` 5.5M gone, `parse_rule_address` 3.0M ->
       19.2M).  Per rule, for a rule holding 14 words: **73 `scan_word`
       calls and 191 `skip_ws` calls.**  The cost is the call count, not the
       cost per call — a `skip_ws` that finds nothing is already about 40
       instructions and a word scan about 180 — so the remedy has to probe
       less, not probe cheaper.

       *Three things that do not work*, measured so nobody tries them
       again:

       - **Merging the word scanner's DNF branches.**  `scan_word` expands
         to 15 branches (7 leads for `word_start`, 8 for the digit-led
         form), each re-scanning `*wordchars`.  Hand-merging them to 2 by
         unioning the leading classes: 306.6M -> no change, 1068 ms.  gcc
         already bails out of the branches that cannot match on the first
         byte.
       - **Guarding `skip_ws`'s slow branch on its first byte** (only `#`
         and `\` can start a comment or a continuation, so the `scan_ws`
         call is skippable): 40.15M -> 39.77M.  Nothing.
       - **Memoizing `ws`, `int` and `str` alongside `word`.**  More
         instructions saved (256.6M against 258.7M for `word` alone) and a
         *worse* wall clock, because four tables of 16 KB cleared per
         statement trade instructions for cache traffic.  The `ws` memo hits
         82% of the time and buys nothing, because the calls it serves were
         the ones that were already nearly free.

       *What does work, and it is 4c's own deferred remedy.*  A
       (position -> scan length) table for the word scanner, one generation
       stamp in the high bits so the table retires in a single store with no
       per-statement clear, 12 bits of length so a statement over 4094 bytes
       runs uncached: 306.6M -> 258.7M instructions and 1054 -> 942 ms,
       i.e. **1.28x -> 1.12x**.  Prototyped in the generated C, not in the
       emitter.  When 4f becomes live again, that is the shape to emit, and
       the open question is whether the last 12% is worth a keyword-id
       dispatch (below).

       *One more measurement worth keeping.*  A full keyword-id dispatch
       over the 35-way `filteropt` alternation — scan the word once, look up
       its id, switch, instead of the 7 of 35 branches that first-byte
       dispatch can separate — came out at 307.1M, very slightly worse.  The
       reason is the benchmark, not the idea: `bench/gen.sh` emits one rule
       shape, whose only filter option is `keep state`, and `keep` is one of
       the 7 that already dispatch.  **So §6's input does not exercise the
       wide alternation at all**, and the gate is being held against an
       input narrower than the thing it is meant to measure.  Before any
       more work on the alternation, `gen.sh` needs a mode that cycles
       through the filter options.
5. **`/` between phrases** (decision 1; factoring needs step 2).  Then:
   - RFC excerpts as regression tests: RFC 5234 Appendix B.1 verbatim, RFC
     3986 `scheme` and `host`, RFC 5322 `addr-spec`, RFC 9112
     `request-line`;
   - the character model in Rust, Zig and Ada through the templates, and
     the interpreter (HBNF_Match) on the same rewrites;
   - `json.hbnf`, then binary (CHARLAYER.md I2–I4).  `where` moved to
     step 6, where the IR it reads against is built.

6. **Compiler-compiler interfaces.**  After the character model is stable:
   source-span objects through the shared IR, matcher and all backends; named
   typed `%action{}` bindings executed post-parse/bottom-up; explicit
   reentrant parser/scanner state; scanner modes with push/pop; input-source
   abstraction (contiguous-buffer fast path retained); opt-in recovery with
   tests proving actions are not repeated; and a shared semantic IR below the
   templates, feeding the `{{ }}` renderer once 3b has the emitters using it.

   **`where` clauses** land here, moved out of step 5: a `where` reads
   against the IR this step builds, so doing it earlier means writing it
   twice.

7. **RFC copy-paste and the wire layer.**  Split, because the two halves
   cost very different amounts and only one of them is syntax.

   7a. **Copy-paste syntax — first, ahead of everything.**
       Reader-only: no backend touched, no generated byte moved.  The point
       is that a grammar lifted out of an RFC, a POSIX spec or a yacc file
       compiles where it can, and where it cannot the message says what to
       write instead ("you wrote X; if you meant Y, hbnf spells it Z").
       Cheap to land, and it makes every excerpt step 5 adds as a
       regression test cheaper to try.  It is the next patch.

       None of this is accepted today — checked 2026-10-02, all four
       spellings are refused.

       **Assignment.**  `::=` (Naur/ALGOL), `:=` (Wirth) and `:`
       (yacc/POSIX) all read as `=`.  The POSIX BNF section above has the
       rest of the yacc reader work — `;` as a terminator, `%token`,
       `%start`, `%%`, the token diagnostics — and the Bourne shell
       grammar as its gate; this item is the operators and the comment
       styles, which everything there rests on.

       **Comments: three styles, not two.**  `(* ... *)` (Wirth,
       ISO 14977) alongside `/* ... */` (C/yacc) and `;` to end of line.
       The POSIX section names `/* ... */` only, because its subject is
       yacc; `(* ... *)` is what an ISO 14977 or Wirth-notation grammar
       pastes with, and a notation hbnf accepts the assignment operator of
       should accept its comments too.  Neither new form nests, and both
       may span lines.

       Two things to get right, both already solved for `;`:

       - A `/*` inside a `%scan{ }` or `%action{ }` block is C, not a
         grammar comment.  The brace counter already reads it that way, so
         the grammar-level reader must not reach inside those blocks.
       - A comment inside `( )` or `[ ]` is part of the rule.  The reader
         handles that for `;` today and must handle it the same way for
         the two new forms, including the round-trip of a trailing comment
         into the generated output.

       **One thing not to paper over.**  The POSIX section reads `|` as
       "ordered choice, parse.y's own reading", which holds for the
       OpenBSD grammars this project started from — their `|` is written
       longest-first and parse.y's LALR tables happen to agree.  It does
       not hold for yacc in general: yacc's `|` is unordered and the
       tables resolve it, hbnf's is PEG first-match, and that is the same
       mismatch recorded for tree-sitter under step 11.  So a pasted yacc
       grammar can compile and mean something else.  Accepting `:` is
       therefore not the same as accepting yacc, and the reader says so:
       a file whose assignment operator is `:` warns once that `|` is
       first-match and names `/` for the union case.  Taking a grammar and
       quietly changing its meaning is the one outcome this step must not
       produce.

   7b. **The wire layer — after step 6.**  One cross-backend
       representation for typed scalars and protocol values: exact
       bytes/code points, width, signedness, byte order, range checks,
       with fixtures comparing the interpreter and the backends on bytes
       and on values.  This needs the shared IR and the typed `%action{}`
       bindings step 6 builds, so it cannot move with 7a.

8. **Compiler-quality diagnostics and error recovery.**  Expected-error
   fixtures, source-span diagnostics, rule traces, and a schema linter
   (nullable repetition, unreachable rules, shadowed ordered choice,
   ambiguous `/`, unsupported backend constructs) that runs before
   generation.

   Recovery borrows from tree-sitter, which does this better than anything
   here.  Measured 2026-10-01: given three config rules whose middle one is
   malformed, it recovered and still produced all three, flagging only the
   bad one (`has_error` on that subtree, the siblings clean).  What is worth
   taking:
   - **A cost model, not a panic rule.**  Recovery is a scored search —
     tree-sitter prices a skipped or inserted token and keeps the cheapest
     repair — rather than "discard to the next newline".
   - **Error as a tree node.**  The bad region becomes a node with its own
     span, so the siblings around it stay typed and the caller sees exactly
     what was not understood.  `statements` today reports and moves on, and
     the entry is simply absent.
   - **Per-subtree error marks**, so a caller can ask whether a particular
     entry is trustworthy instead of only whether the file was.

   What is not worth taking: tree-sitter recovers because GLR is already
   exploring alternatives, and this stays ordered choice (see "Not in this
   plan").  So the cost model is reimplemented over backtracking, bounded,
   and the fail-fast default is kept — recovery stays opt-in per the
   compiler-compiler decision, and the test that actions are not re-run
   stands.

9. **Recursive tree types** — the one blocker for a real programming
   language, and **the live item**: parsing real programming languages,
   including the ones that are not regular, is a goal, and make it correct
   before making it fast.  A grammar whose tree contains itself (`prim =
   '(' expr ')' | int`, which is every expression language) cannot be
   emitted, because a rule's value is a struct by value and the struct
   would be infinitely sized.  Measured 2026-10-01, the four backends
   disagreed, which was itself the bug:

   | backend | on `prim = '(' expr ')' \| int`, `expr = prim` |
   |---|---|
   | C | refuses: "by-value cycle in schema (add a `*` repetition)" |
   | Ada | refuses, same message |
   | Rust | generates; `rustc` says `E0072: recursive type has infinite size` |
   | Zig | generates; `zig` says "depends on itself" once a size is needed |

   Two things to fix, one mechanism:

   9a. **The four backends now agree, and the list case was never a cycle.**
       *Done 2026-10-02.*  Two defects, both correctness, both fixed:

       - **A field whose rule is a list holds the list's head.**  The C
         backend declared one of the list's *nodes* there instead, by
         value, so three rules

               sum  = sum '+' term | term
               term = '(' sums ')' | int
               sums = 1*sum

         emitted C that gcc rejected with "field 'sum' has incomplete
         type".  The parse code, the free function and the walkers already
         passed `&n->field` to the list-taking entry points, so the field
         declaration was the only thing out of step.  The struct branch of
         the C type emitter already had the head/node test; the list branch
         did not, and both now share one `Field_Decl`.  With the type right
         the cycle is genuinely broken — a head is two pointers, so a
         forward declaration is enough — and `sums = 1*sum` compiles and the
         four backends all take it.

       - **Rust and Zig refused nothing.**  Both emitted code their own
         compilers reject, which is the worse failure: Rust had no by-value
         cycle check at all (it needs no declaration order, so it had no
         topological sort to fall over), and Zig's sort only orders structs
         and lists, so a cycle through a scalar alias slipped past it.  Both
         now carry an explicit three-colour DFS over by-value edges — a
         struct's non-list members and a scalar's alias, with `Vec<T>` and
         `[]T` counted as indirect — and refuse `recursive.hbnf` with the
         same message C and Ada give.

       `tests/abnf.sh` now asserts both halves across all four backends (42
       checks, up from 34), and the 132-file snapshot is byte-identical:
       no existing schema moved.

       **There are four copies of this detector, and that is the next
       thing to fix.**  9b should not add a fifth.  One detector belongs in
       `HBNF_Compilable`, parameterised by the backend's set of indirect
       constructors (C: a list head and a pointer; Ada: a vector and an
       access type; Rust: `Vec` and `Box`; Zig: a slice and a pointer), so
       that "the four backends accept or refuse the same schemas" holds by
       construction rather than by four hand-kept copies.

   9b. **Break the cycle with a pointer.**  The dependency graph is already
       computed for emission order; instead of giving up when it cannot be
       topologically sorted, pick a back edge per strongly-connected
       component and emit that one field indirect — `expr_t *expr` in C,
       `Box<Expr>` in Rust, `*Expr` in Zig, an access type in Ada —
       allocating at the commit point and following it in the free function
       and the walkers.  The arena already owns the string leaves and can
       own these.  Choose the back edge deterministically (lowest rule
       index) so output stays byte-stable.

   Gate: the four backends accept or refuse the same schemas, the
   expression grammar above compiles and parses in all four, and the nine
   daemon grammars stay byte-identical (none of them recurses, so nothing
   should move).

   This is what an earlier review meant by "not general enough for a real
   language".  It is narrower than it sounded — one mechanism, in the type
   emitter — and it is *not* the typedef problem, which is separate and
   discussed under decision 13.

   **It kept the number 9, but it no longer waits.**  The earlier text here
   said a programming language was not a goal, so this bought generality
   the product did not need.  That is no longer true: parsing real
   programming languages, including non-regular ones, is a stated goal
   alongside config files and RFC wire formats.  The mechanical argument
   for the old order has also expired — 9b allocates at a rule's commit
   point, and 4c had just rewritten where those are, but 4c through 4f are
   done, so the commit points are settled and the allocation is written
   once.  And correctness comes before speed: 9 is four backends
   disagreeing about which schemas are legal, 4f is a constant factor.  9
   is the live item; 4f holds its measurements and waits.

10. **Completion gate and backend spectrum.**  C/Ada/Rust/Zig and the
   interpreter agree on the same corpus, parsers are reentrant, actions have
   named typed inputs and locations, scanner modes work, and the RFC/wire
   fixtures have byte-identity tests.  Then fill out the compiled targets (D,
   Fortran, Free Pascal, Nim, Odin, Objective-C, ATS, V) and the GC languages
   (Go, Java, JavaScript, C#, F#, Julia, Common Lisp, newLISP).  The C backend stays C99 and
   C++-clean; a separate C++ backend appears only if C++ needs more than an
   `extern "C"` guard.

11. **A tree-sitter emitter, as an editor backend.**  Not a replacement for
   the C backend and not gated on anything above: it can land between any
   two other steps.  The idea is to generate a `grammar.js` (and a stub
   `scanner.c` where a jet is needed) from the lifted schema, so one
   grammar gives both the daemon's parser and the editor's highlighting,
   folding and structural selection.  Today a daemon ships a `parse.y` and,
   separately, somebody hand-writes a tree-sitter grammar that drifts from
   it; one source removes the drift.

   The mapping is mostly mechanical, because tree-sitter's `grammar.js` is
   the same shapes under different names:

   | hbnf | grammar.js |
   |---|---|
   | a rule | an entry in `rules` |
   | concatenation | `seq(...)` |
   | `\|` | `choice(...)` — see the catch below |
   | `[ x ]` | `optional(x)` |
   | `*( x )` / `1*( x )` | `repeat(x)` / `repeat1(x)` |
   | a character rule | `token(seq(...))` |
   | a lifted `rule_1` | an `inline:` rule, so the CST keeps the written shape |
   | `whitespace ws` | `extras:` |
   | the keyword table | `word:` |

   **What does not map, stated plainly rather than papered over.**  This
   list is the reason the emitter is a separate backend and not a mode of
   the others:

   - **`choice` is not `|`.**  hbnf's `|` is PEG ordered choice: the first
     branch that matches wins, and that is what makes a parse deterministic
     without annotations.  tree-sitter is GLR; `choice` is unordered, and
     an ambiguity it cannot resolve is a build error demanding hand-written
     `prec()` or `conflicts`.  So a schema hbnf compiles can fail to build
     as a tree-sitter grammar, and the emitter must say so rather than
     guess a precedence.  `/` (ABNF union) maps better than `|` does.
   - **`n*m` bounds.**  tree-sitter has `repeat` and `repeat1` and nothing
     else; `3*5( x )` has to be unrolled, and the unrolling shows up in the
     CST.
   - **Jets** become `externals:` plus a `scanner.c`.  The emitter can stub
     the scanner with the jet's own code where the jet is already C, and
     must otherwise leave a named hole.
   - **`<prose-val>`** has no analogue: an unwritten rule cannot highlight.
     It emits as an `externals:` hole with the prose as its comment.
   - **`sensitivity`/`%i`** has no analogue either; a case-insensitive
     literal becomes a regex, which changes the token boundaries.
   - **Typed fields, `--conf`, actions and bindings are out of scope.**  An
     editor backend produces a CST of named nodes; it does not produce the
     daemon's structs, and nothing in it is byte-identity tested against a
     `parse.y`.

   **Gate:** the nine `obconf` grammars build as tree-sitter grammars, the
   obconf sample configs highlight, and every CST node name is the rule
   name that produced it.  Where a grammar cannot build without a
   hand-written precedence, the emitter names the rule and the conflicting
   branches.

   *Two claims in the original proposal are wrong, and the corrected
   numbers are why this is an editor backend rather than a parser
   strategy.*  Measured 2026-10-01, same grammar, same input, gcc -O2,
   best of 5:

   | input | hbnf | tree-sitter |
   |---|---|---|
   | 7.68 MB | **48.33 ms, 21 MB** | 501.75 ms, 117 MB |
   | 76.9 MB | **488.82 ms, 202 MB** | 5158.51 ms, 1155 MB |

   - "A full parse of a config is in the same league as your RD parser" —
     it is 10x slower and takes 5.6x the memory (~159 MB/s against ~15
     MB/s).
   - "Incremental reparse is the win" — for a config it mostly is not.  A
     one-byte edit in the 7.68 MB file reparses in 87 ms, still worse than
     hbnf's 48 ms cold parse, because a config is a flat list of N siblings
     and an edit prunes nothing.  For deeply nested source tree-sitter wins
     this outright; the conclusion is scoped to the input shape hbnf
     targets.

   *On the size estimate* ("smaller than the Zig backend, a few hundred
   lines, call it a week"): the backends measure `hbnf_rust.adb` 1,952
   lines, `hbnf_zig.adb` 2,167, `hbnf_ada.adb` 2,292, `hbnf_c.adb` 5,650.
   A few hundred lines is plausible for the `grammar.js` emitter alone —
   it writes no types, no free functions, no walkers and no parse functions
   — but the scanner stubs, the conflict reporting and the highlight
   fixtures are the rest of it.

   *On the number:* the proposal filed this as "4b", which is taken (the
   lexer as grammar, done).  It is 11 because it is not on the path to any
   gate above, not because it comes last.

## Not in this plan

- RBNF (RFC 5511's routing BNF).
- GLR, or trying another alternative after a later failure.
- Case-folding non-ASCII rule names.
- Guessing any setting from an include or from seeing `%x`.
