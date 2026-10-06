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
8. **Jets, actions and emitters are code — one family of three.**  A
   `%scan{ }`, `%action{ }` or `%emit{ }` block holds the code that runs,
   usually one call to a function the file defines in its epilogue
   (`%scan{ return ipv6_match(s, pos, len); }`), with the function's
   prototype in the preamble.  hbnf never rewrites the code.  Most of the
   remaining 17 jets become character rules instead, which also makes them
   work in Rust, Zig and Ada.

   The family has one member per level, and the levels are the compiler's
   own:

   | | level | runs |
   |---|---|---|
   | `%scan{ }` | lexical | recognize characters at this position |
   | `%action{ }` | semantic | on this node, after the parse |
   | `%emit{ }` | generative | write output for this node |

   **`%emit{ }` is agreed as the third member** (2026-10-03) and is what
   would let a backend be a schema rather than Ada — step 13b.  It is not
   built, and the semantics the three share are not finished: a block
   should be able to sit *between* elements rather than only at the end of
   a rule (step 12), which also gives one block per alternative instead of
   one per rule, and a block may name a template as shorthand for the code
   that renders it.  Those are changes to the family, not to one member,
   which is the test of whether a member belongs in it.
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

## Ordering and token tables

Researched 2026-10-02, because the question deserves an answer and not a
restatement of decision 7: *why did we go against token tables, shouldn't
`foo = "bar"` go into one, and why is `%token` needed at all?*

Three answers, and the first thing to separate is the two different things
"token table" can mean.  A **keyword table** interns the fixed literals a
grammar names and gives each an id.  A **token array** cuts the whole input
into tokens before any rule runs.  hbnf kept the first and dropped the
second, and the confusion between them is doing real damage to this plan.

**1. `foo = "bar"` already goes into a token table.**  `Is_Keyword_Lit`
in the C backend: a literal led by a letter or `_` is a keyword, and when a
grammar has no `keywords { }` table **every** such literal is one.  So
`"bar"` is already interned, already in the generated `kwid_t` enum, and
already looked up by `kw_lookup`.  The user's instinct is the
implementation; nothing needs adding.

The `keywords { }` directive only ever *narrows* that default, and it
exists for exactly one reason: parse.y's `lookup()` reserves a word
**everywhere in the file**, so a word in the table does not match `STRING`
anywhere.  Byte-identity with parse.y therefore requires hbnf to reserve
the same set, no more and no less — which a default of "every letter-led
literal" does not give, because the daemon grammars name literals parse.y
does not reserve.  The POSIX shell grammar shows the other edge of the same
tool: `if` is reserved only in command position, so a table that reserves
everywhere is the wrong instrument there and the rules must spell `if` as
an alternative instead.

**2. What was dropped was the token array, and the reason was correctness,
not speed.**  Decision 7 has it: the pre-cut array imposed a tokenization
the grammar never asked for.  `"x" "y"` accepted `x y` and rejected `xy` —
the exact opposite of ABNF, where concatenation is adjacency — and
`1*VCHAR` failed on `/x`, because the lexer had already decided `x` was a
word.  For RFC 5234 that is not a performance trade, it is the wrong
language.  The array also put the lexer outside the notation: `wordchars`
was a directive, so a grammar could not say what a word is.  Now it is a
rule (`wordchars = ALPHA | DIGIT | "_" | "-" | "."`) that any grammar
overrides, which is what let pfctl add `$`, `@` and `%` and ntpd not.

So "we went against ordering and token tables" is not what happened.  The
keyword table is still there.  What the array also carried, and what
genuinely went with it, is the subject of the third answer.

**3. The id dispatch is what we lost, and it is recoverable without the
array.**  Measured in the generated pfctl parser: `expect_kind` — the
token-era jump that read a token's interned id and branched on it —
appears **72 times** before 4c and **zero times** after.  `kw_lookup`
survives at three sites, all of them negative ("this word is reserved, so
it is not a `word`").  Nothing dispatches on an id any more.  A wide
alternation instead calls `expect_word` per branch, which re-scans the word
and `memcmp`s it, and `cc89c9e` recovered part of the loss by switching on
the first byte — which separates **7 of pfctl's 35** `filteropt` branches,
because the rest share a leading letter.

That is most of the 1.61x instruction-count gap (190.3M against 306.6M at
5,000 rules): 73 `scan_word` calls and 191 `skip_ws` calls per rule, for a
rule holding 14 words.  Decision 7 predicted exactly this and promised two
remedies — "remembering the last token scanned at a position and branching
on the first byte."  The first byte landed; the remembering did not.

**So the benefit the question asks about is real, and here is the shape it
takes.**  Not a token array: a position-keyed scan, which is the same
economy without the wrong language.

- **Scan once per position** (4c's deferred memoization).  Prototyped
  2026-10-02 in the generated C: a (position -> scan length) table for the
  word scanner with a generation stamp, 306.6M -> 258.7M instructions and
  1.28x -> 1.12x against the token array.  This is "remembering the last
  token scanned at a position", and it is the half of decision 7 still owed.
- **Dispatch on the id, not the first byte.**  Scan the word once at the
  branch position, `kw_lookup` it, and `switch` on the `kwid_t` — the
  token-era `expect_kind` jump, restored over characters.  Correctness
  condition: a case for keyword K may jump to branch N only if no branch
  before N can begin with K, which is a FIRST-set computation hbnf already
  needs for its FIRST/FOLLOW-disjoint compilation.  Branches led by a rule
  rather than a literal stay in the linear chain.
- **Measure it on an input that exercises it.**  A hand-built kwid dispatch
  over `filteropt` measured 307.1M, very slightly *worse* — because
  `bench/gen.sh` emits one rule shape whose only filter option is
  `keep state`, and `keep` is one of the 7 that first-byte dispatch already
  separates.  The gate is being held against an input narrower than the
  thing it measures.  `gen.sh` needs a mode that cycles the filter options
  before any of this is worth doing.

**4. `%token` is not needed at all, and hbnf should never require it.**  In
yacc, `%token NAME` declares a terminal whose *spelling lives in the lexer*,
in C, outside the grammar; the declaration is the only thing tying the
parser to a symbol it cannot see.  hbnf has no outside lexer — the lexer is
grammar — so a `%token` carries no information: either the name has a
definition in the file, and the declaration is redundant, or it has none,
and the grammar is simply incomplete.  `%token` is therefore a **paste
artifact and nothing more**: the reader accepts it so a POSIX or yacc
grammar pastes unchanged, registers the name as declared-but-undefined so
the error can name it by kind (operator, reserved word, lexical class), and
requires it from nobody.  A grammar written in hbnf never writes one.  That
is what the POSIX BNF section above specifies, and the reasoning is this.

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
8. **One semantic model.**  The emitters agree on ordered choice,
   repetition, left recursion, characters and wire values; a backend
   limitation is a generation-time error, never a silent divergence.  This
   criterion used to read "the interpreter and all emitters agree", which
   was the wrong shape of promise: a second implementation cannot be made
   to agree, only kept in step, and it was not — it stayed on the token
   model through all of step 4 (step 9c retires it).  **One model means one
   implementation**, and the gate for that is that no second one exists.
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

**A switchover step's gate must name the old mechanism and assert it is
gone.**  Two switchovers in this plan were marked done while half-finished,
and both times the gate was structurally unable to see it.  Step 3's gate
was "byte-identical output for every schema through every backend" — which
a flat `${name}` substituter passes exactly as well as Mustache does, so a
renderer could be written, wired to nothing, and the step still close.
Step 4's gate was the daemon grammars, byteident and the corpus, all of
which run through the backends — so the interpreter could stay on tokens
and every gate still pass.  Testing the output cannot test the mechanism.
A switchover therefore gates on a count: zero `Templates.Render` callers
and zero `${` in the templates (3b), zero `Token_Vectors` outside the
reader's own lexer (9c).  Those are the assertions that fail loudly while
the old path is still there.

**Correct first, optimize after — and a regression that buys correctness is
expected, not a defect.**  Every step still ahead adds accuracy or adds a
feature: characters where there were tokens, a pointer where a type was
refused, a warning channel, spans, recovery, a wire layer.  Each of those
costs cycles, and the cost is *predictable* — a parser that checks more does
more work.  So a performance number that moves the wrong way after a
correctness step is recorded and left alone; it is not a reason to stop, to
revert, or to interleave optimization into the step that caused it.
Optimization happens once the feature set is settled, against a measurement
taken then, and 4f sits at the end of the running order for that reason.

What does **not** relax is the honesty rule: **paper claims match
measurements.**  A step that moves a number re-measures and updates §6
rather than leaving the old figure standing.  Recording a regression is
cheap; a stale claim is the thing this project does not ship.

The numbers are stable labels — error messages and comments in the code
cite them — so a step that moves keeps its number and this list gives the
running order:

> **Done:** 0, 1, 2, 3, 3b, 4a–4e, 7a, 9a, 9b, 12.
> **Critical path:** **9b** → **9c** → **5** → **6**
> → **7b** → **8** → **4f** → **10** → **13**.  **11** is not gated on
> any of them and can land in any gap.

Six things decide that order, and each one is a dependency rather than a
preference:

- **3b came first because it makes every later step cheaper.**  *Done.*
  The switchover to mustache-ada moved the per-element loops out of the four
  emitters and into the templates.  Every step after it that touches the
  type emitter or the parse emitter — 9b above all, which adds an
  indirection to a field in all four backends — then writes its change
  once instead of four times.  Doing 9b first means doing 9b four times and
  then moving all four into templates anyway.  9a is the evidence: the
  same one-line type decision had to be made in two places before it was
  folded into one `Field_Decl`, and the Rust and Zig cycle checks are a
  third and fourth copy of a detector that should be one.
- **12 is second because its items are cheap and they are load-bearing.**
  One is a crash, one is the warning channel 7a and step 8 both need, and
  one is a build hazard that has already cost an afternoon of false
  results.
- **Notation decisions go before 13a, which is why they are in 12 and not
  near the end.**  13a's pretty printer projects every construct onto four
  historical notations, so anything added to the notation after it is
  written is added in five places.  A rule referenced twice (`expr = term
  '+' term`), a `%action{ }` between elements, an explicit empty
  alternative and an optional terminator are all notation, all small, and
  all cheaper now than later.  The mid-sequence block is also what 13b
  would need.
- **A step waits for what it reads against.**  `where` moved from 5 to 6
  because it reads the IR 6 builds; the wire layer is 7b, behind 6, for the
  same reason; step 8's recovery needs 6's spans and the warning channel
  from 12.
- **9c waits on 9b because 9b is why 9c is possible.**  The interpreter's
  one distinctive capability is running the mutually recursive grammar the
  backends refuse, which is the gap 9b closes.  Retiring it any earlier
  would mean losing a test; retiring it after costs nothing.
- **4f is last of the work, by policy, not by accident.**  Every step
  before it adds correctness and costs cycles, so optimizing earlier means
  optimizing against a shape that is about to change.  It is also blocked
  on its own benchmark: `bench/gen.sh` emits one rule shape, so §6's input
  does not exercise the wide alternation the remaining cost lives in (see
  "Ordering and token tables").

13 is last because it is a claim that the notation is finished, and nothing
should claim that before 10.

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

   3b. **Done 2026-10-02/03: mustache-ada renders the templates and
       `Templates` is gone.**  All four gates met — zero references to
       `Templates`, zero `${` and `@PLACEHOLDER@` in `templates/`,
       `templates.ads` and `templates.adb` deleted, 132 snapshot files
       byte-identical — with e2e 98/0, byte-identity 18 + 24 cases, and the
       corpus unchanged.  965 lines deleted against 485 added; 71 templates
       down to 65.  Six item templates and seven per-element emitter loops
       became sections.  Three findings worth keeping:

       - **Every hole is `{{&name}}`, never `{{name}}`.**  mustache-ada is
         spec-conformant, so the plain form HTML-escapes and a generated C
         type holding `& < > "` comes back corrupted.  Checked with a probe
         before a template was written; `hbnf_emit_check` now asserts both
         halves.
       - **Mustache has no `#each` and no join.**  A section over a list
         iterates it, so it is `{{#items}} … {{/items}}`; Rust's
         `#[default]` on the first variant and Ada's comma-separated enum
         needed a per-row flag (`{{#first}}`, `{{#sep}}`).
       - **An unfilled hole no longer raises.**  `Templates.Render` raised
         `Template_Error`; Mustache renders a missing name as empty, per
         spec.  The byte-identity gate is what catches it now, and it did,
         repeatedly, during the work.  Whether mustache-ada should gain a
         strict mode is a question for that library.

       Left as refinement, not switchover: the C emitter's 25 flat call
       sites go through a local `Fill (template, holes)` adapter rather than
       an inline context block each, and its remaining item loops
       (`c_enum_item`/`_last`, and the `c_struct` field path) are not yet
       sections.

       The finding this step started from, for the record.  Measured
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
       What that costs: the per-element loops `{{#each}}` exists to absorb
       are still written out in Ada in each backend (`for M of
       Info.Members loop ... Append (Items, ...)`), one copy per backend,
       which is also why the step 9a fix had to be made in two places
       before it was folded into one `Field_Decl`.  (It is not the whole of
       the duplication — see below.)

       **Decided 2026-10-02: `moebiusV/mustache-ada` is the canonical
       Mustache and hbnf must use it.**  So the inline subset in
       `templates.adb` is not the renderer to switch the templates onto; it
       is a second implementation to retire — the same judgement as 9c
       makes about the interpreter, for the same reason.  A second
       implementation of something the project already has is not a
       fallback, it is a thing that drifts.  Nothing in the tree references
       the aport today: no `with` clause, no `.gpr` dependency, no
       submodule.

       **And the duplication is larger than "a renderer".**  Read
       2026-10-02 at tag `v0.2.1` (`c7ef6d9`, the version
       `testing/mustache-ada/APKBUILD` builds): `mustache.ads` is 107 lines
       and declares

           type Value_Kind is (Scalar, List, Map);
           New_Scalar / New_List / New_Map / Append / Insert
           type Context;  View / Put / Push / Pop
           Render (Source, View) / Render_File (Name, View)
           Load (Dir) / Define (Name, Source) / Get (Name) / Reset

       — the same `Scalar`/`List`/`Map` model, the same builder names, the
       same scope stack, **and the template store**.  `Load (Dir)` and
       `Get (Name)` are what `Templates` exists to provide.  So hbnf did
       not duplicate a renderer; it duplicated nearly the whole package,
       loader included.  What `Templates` has that `Mustache` does not is
       `Bind`, `Binding_Array`, `Render (Text, Pairs)` and `Substitute` —
       which is to say the `${name}` and `@PLACEHOLDER@` paths, the two
       things this step deletes.  Afterwards there is nothing left in
       `Templates` worth keeping: it is `Mustache` under another name.
       mustache-ada is also pure Ada on the GNAT runtime with no C
       dependencies and no external GPR projects, ships relocatable and
       static, and carries a Mustache **spec** suite
       (`tests/spec_check tests/spec`) — which the inline subset does not
       pass and was never measured against.

       Three things, in order:

       1. **Depend on mustache-ada.**  `hbnf.gpr` withs `mustache.gpr`,
          from the `ada-on-alpine` aport (`testing/mustache-ada`, pkgver
          0.2.1) where it is packaged.  The build instructions gain it as a
          prerequisite.  Note for the Alpine side: hbnf then needs that
          aport installable, so whatever is outstanding there is upstream
          of this step.
       2. **Delete `templates.ads` and `templates.adb`, and `with
          Mustache` directly.**  Not "retire the inline renderer and keep
          the loader" — there is no loader to keep, `Mustache.Load` is the
          loader.  789 lines of upstream library replace about 400 lines of
          hbnf's own, and the `Value`/`Context` types the emitters build
          against become mustache-ada's.  If a thin shim turns out to be
          wanted — for hbnf's own `.tmpl` directory convention, say — it is
          a renaming of `Load` and `Get` and nothing else, and it carries
          no second renderer.
       3. **Move the templates and the emitters.**  52 `${name}` templates
          and 14 `@PLACEHOLDER@` templates become `{{ }}`; each emitter
          builds a context tree instead of a binding table.  The
          per-element loops become `{{#each}}` in the template, which is
          the point of the whole exercise and what makes 9b a one-place
          change.

       **Gate**, under the switchover rule at the head of this section — the
       old mechanism named and asserted gone, not just the output checked:
       **zero references to `Templates` anywhere in the tree**, zero `${`
       and zero `@PLACEHOLDER@` in `templates/`, and `templates.ads` and
       `templates.adb` deleted.  Then step 3's own gate on top:
       byte-identical output for every schema through every backend, all
       132 snapshot files.  Nothing about the generated parsers changes —
       only where the shape of the output is written down.
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

   4f. **Measurements, held for later — not a gate blocking anything.**
       Under "correct first, optimize after" at the head of this section,
       this entry is a record, not an obstacle.  The absolute gate is met:
       re-measured on the author's workstation (Ryzen 5 7600), `parse_file`
       does 100,000 pfctl rules in **0.51 s**, which is the gate as written
       ("about 0.5 s").  What remains is the weaker claim that the
       character model costs about 1.28x what the token array cost for
       pfctl on the same machine with the same inputs — and that is the
       expected shape of the trade, because the character model is the one
       that reads ABNF correctly (decision 7: the token array accepted
       `x y` for `"x" "y"` and rejected `xy`).  A parser that checks more
       does more work.

       **So this number is expected to get worse again** as 9b adds an
       indirection, 12 adds a warning channel, 6 adds spans and 8 adds
       recovery.  Each of those steps re-measures and updates §6, and none
       of them stops for the figure.  The optimization work below waits
       until the feature set is settled, and is then done against a
       measurement taken then rather than against the ratios here.

       The numbers in this entry are from a shared VM roughly 1.6x slower
       than that workstation; only their *ratios* carry over.

       Measured 2026-10-02, the same machine, the same inputs, the
       harness's own best-of-five, pre-4c (c2eb521, token array) against
       current:

       | case | pre-4c | character model | |
       |---|---|---|---|
       | toy 100,000 | 64 ms, 53 MB | **50 ms, 21 MB** | 1.27x faster, 2.5x leaner |
       | toy 1,000,000 | 675 ms, 517 MB | **496 ms, 196 MB** | 1.36x faster, 2.6x leaner |
       | pfctl 100,000 | **666 ms**, 378 MB | 1052 ms, 378 MB | **1.58x slower** |

       The toy improved on both axes, and dropping the token array is why
       the memory more than halved.  pfctl went the other way: 1.58x at the
       time, 1.28x after the three 4f commits below.  On this VM that reads
       as "2x over the 0.5 s gate", which is what an earlier draft of this
       entry said — but the VM is the wrong machine to say it on, and §6's
       own hardware makes the gate.  What is left is the ratio, not the
       absolute.

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

       *Why any of this is a keyword-id dispatch and not a token array* is
       the subject of "Ordering and token tables" above, which answers the
       question this entry keeps circling: the keyword table never went
       away, the pre-cut array went for correctness, and the id jump that
       went with it — `expect_kind`, 72 sites before 4c and zero after —
       is the recoverable part.
5. **`/` between phrases** (decision 1; factoring needs step 2).  Then:
   - RFC excerpts as regression tests: RFC 5234 Appendix B.1 verbatim, RFC
     3986 `scheme` and `host`, RFC 5322 `addr-spec`, RFC 9112
     `request-line`;
   - the character model in Rust, Zig and Ada through the templates.  (The
     interpreter used to be named here too, "on the same rewrites".  It is
     not converted, it is retired — step 9c.)
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

   7a. **Copy-paste syntax.**  *Done 2026-10-02, bar the warning below.*
       Reader-only: no backend touched, and all 132 generated files stayed
       byte-identical.  The point is that a grammar lifted out of an RFC, a
       POSIX spec or a yacc file compiles where it can, and where it cannot
       the message says what to write instead ("you wrote X; if you meant
       Y, hbnf spells it Z").

       *Completed 2026-10-04* by step 12's warning channel: a file whose
       assignment operator is `:` now warns once that `|` is first-match and
       names `/` for the union case.

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
       produce — which is why the missing warning channel is a defect in
       step 12 and not a nicety.

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
       thing to fix.**  (Fixed by 9b, below: one detector, in
       `HBNF_Compilable`.)  9b should not add a fifth.  One detector belongs in
       `HBNF_Compilable`, parameterised by the backend's set of indirect
       constructors (C: a list head and a pointer; Ada: a vector and an
       access type; Rust: `Vec` and `Box`; Zig: a slice and a pointer), so
       that "the four backends accept or refuse the same schemas" holds by
       construction rather than by four hand-kept copies.

   9b. **Break the cycle with a pointer.**  *Done 2026-10-05.*  The dependency graph is already
       computed for emission order; instead of giving up when it cannot be
       topologically sorted, pick a back edge per strongly-connected
       component and emit that one field indirect — `expr_t *expr` in C,
       `Box<Expr>` in Rust, `*Expr` in Zig, an access type in Ada —
       allocating at the commit point and following it in the free function
       and the walkers.  The arena already owns the string leaves and can
       own these.  Choose the back edge deterministically (lowest rule
       index) so output stays byte-stable.

       **What landed.**  One detector, `HBNF_Compilable.Back_Edges`, takes
       each backend's own by-value edges and returns one edge per cycle (the
       algorithm is shared; the graph is not, and is deliberately
       backend-specific: Ada already indirects a direct struct member, so
       its edges run through scalar aliases).  Each backend then emits that
       field indirectly:

       | backend | field | commit point | release |
       |---|---|---|---|
       | C | `T *f` | `hbnf_alloc` | `free_<rule>_fields` |
       | Ada | `<Record>_Access` | `new X_Type'(…)` | new `Free_<rule>` |
       | Rust | `Option<Box<T>>` | `Some(Box::new(parse_x(p)?))` | `drop` |
       | Zig | `?*T` | `try p.box(T, try parse_x(p))` | new `deinit_<rule>` |

       Two things differ from the sketch above.  Rust and Zig use the
       *nullable* form, not a bare `Box<T>` / `*T`: every struct is
       default- or zero-initialised and reset that way, and a bare
       `Box<T>::default()` recurses without end (it compiles, then
       overflows the stack on the first parse).  And "the arena owns these"
       holds only for C: Ada and Zig had no free walk at all, so each gained
       one, and a failed branch's reset must release a box without touching
       the arena (C's `free_arena` ends the public `free_<root>`, and calling
       it mid-parse was a use-after-free that ASan found).

       `tests/recursive.sh` compiles and runs the expression grammar in Ada,
       Rust and Zig (C is `tests/abnf.sh`'s recursive block), plus a fixture
       whose cycle runs through a *direct* member
       (`tests/abnf/recursive-direct.hbnf`) so the walkers must descend
       through the pointer, and Zig's drivers run under a leak-checking
       allocator.  The ten daemon grammars are byte-identical for C, Ada and
       Rust; Zig's gain `deinit_*` functions and lose nothing.

       **Known gaps, none blocking.**  C leaves a failed branch's pointer
       non-NULL in the unused union arm: memory-safe, and Rust and Zig do
       not share it.  Ada's `recursive-via-list` output does
       not compile (a vector of records needs the record's `=` in scope),
       which predates 9b.

   Gate: the four backends accept or refuse the same schemas, the
   expression grammar above compiles and parses in all four, and the nine
   daemon grammars stay byte-identical (none of them recurses, so nothing
   should move).

   This is what an earlier review meant by "not general enough for a real
   language".  It is narrower than it sounded — one mechanism, in the type
   emitter — and it is *not* the typedef problem, which is separate and
   discussed under decision 13.

   9c. **Retire the interpreter.**  There is no reason to keep it, and the
       reason it existed is 9b.

       **What it is.**  `HBNF_Match` (379 lines): "the matcher and binder —
       given a parsed schema and a token stream, recognize whether the
       tokens spell out the schema's root rule and bind them to a parse
       tree."  A grammar run directly instead of compiled.  Beside it,
       `HBNF_Config` (1,266 lines): a **hand-written** reader for
       obconf-format config files, and `HBNF_Match`'s only non-test caller.

       **Nothing ships it.**  `hbnf.adb`, the CLI, withs `Templates`,
       `HBNF_Grammar`, `HBNF_Compilable` and the four backends — and
       nothing else.  `HBNF_Match` is reached only from `HBNF_Config` and
       `tests/hbnf_emit_check.adb`; `HBNF_Config` only from
       `tests/hbnf_check.adb` and `tests/hbnf_match_check.adb`, neither of
       which e2e runs.  So 1,645 lines of token-model code sit in the build
       serving one test.

       **Its one distinctive capability is the gap 9b closes.**
       `hbnf_emit_check` says why it reaches for the matcher, in its own
       words: `hbnf_schema.hbnf` is "checked at the parse level (its
       entry/block rules are mutually recursive, which the
       declaration-only emitters reject as a cyclic reference)".  That is
       step 9, exactly.  `entry = block | statement` and `block = name
       [qualifier] "{" ... *( entry ) ... "}"` is a cycle, the backends
       refuse it, and the interpreter was the way round.  Once 9b emits a
       pointer on a back edge the backends take that schema and the
       interpreter has no job left.  Hence 9c, and hence after 9b.

       **So retire rather than convert**, which is the stronger reading of
       "a switchover should be complete":

       - `HBNF_Config` is a hand-written parser for a grammar hbnf can
         generate — `grammars/obconf.hbnf` through the Ada backend.
         Replace it with generated code.  hbnf eats its own output, and
         ~1,266 hand-written lines go rather than being ported to
         characters.
       - `HBNF_Match` goes with it.  `hbnf_emit_check`'s `Match` assertions
         become what every other schema's already are: generate, compile,
         run.
       - `hbnf_schema.hbnf` is rewritten in character-rule vocabulary.  It
         is refused today for two separate reasons — the token-era
         built-ins (`atom`, `dec`, `percent`; obconf has `word`, and there
         is no `atom` rule anywhere) and the mutual recursion.  9b fixes
         the second; this fixes the first.  Its header still says "as an
         hbnf grammar **over the token stream**", which is the model
         decision 7 removed.
       - **Do not lose what the retired tests prove.**  `hbnf_check` is a
         conformance driver whose "accept" requires round-tripping: parse,
         print, re-parse, re-print, and the printer must be idempotent.
         `hbnf_match_check` asserts the hand-written parser and the
         grammar-driven one produce the same tree, comments in the same
         places.  Both are prior art for step 13's pretty printer, at the
         config-format layer rather than the notation layer.  The
         idempotence driver should be rebuilt against the generated reader
         before `HBNF_Config` is deleted, not after.

       **Also to be clear about the naming**, because it has already caused
       confusion: `hbnf_schema.hbnf` and `grammars/obconf.hbnf` are not two
       names for one thing.  `obconf.hbnf` is the lexical and leaf layer —
       `wordchars`, `word`, `int`, `str`, `ws`, `comment`, plus the shared
       leaves — with no structure rules at all.  `hbnf_schema.hbnf` is pure
       structure — `config`, `entry`, `block`, `statement`, `arg` — with no
       lexical rules at all, because it assumes its leaves are codegen
       built-ins.  They are complements written against different parsing
       models.  And neither is step 13's `hbnf.hbnf`, which describes the
       `.hbnf` notation rather than a config file.

       **Gate.**  Zero `Token_Vectors` outside the reader's own lexer; the
       CLI and the test programs build with `HBNF_Match` and `HBNF_Config`
       deleted; `hbnf_schema.hbnf` generates through all four backends;
       e2e's check count does not drop.

   **It kept the number 9, and it is third on the critical path.**  The
   earlier text here said a programming language was not a goal, so this
   bought generality the product did not need.  That is no longer true:
   parsing real programming languages, including non-regular ones, is a
   stated goal alongside config files and RFC wire formats.  The mechanical
   argument for the old order has expired too — 9b allocates at a rule's
   commit point, and 4c had just rewritten where those are, but 4c through
   4f are done, so the commit points are settled.  And correctness comes
   before speed: 9 is four backends disagreeing about which schemas are
   legal, 4f is a constant factor.

   What it now waits for is 3b and 12, and for a reason, not a preference.
   9b adds an indirection to one field in all four backends and teaches the
   free function and both walkers to follow it.  Written against today's
   emitters that is the same change four times, in Ada, plus a fifth copy
   of the cycle detector.  Written after 3b it is one `{{ }}` template and
   one detector in `HBNF_Compilable`.  9a is the proof of the arithmetic:
   one type decision, two places, before it was folded into a single
   `Field_Decl` — and the Rust and Zig checks that patch added are the
   third and fourth copies of something that should be one.

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

12. **Known defects and notation decisions.**  *Done 2026-10-05* (three of
   the five items on 2026-10-04; the two notation decisions on 2026-10-05).
   Five items, in two groups, and both groups were in the way
   of later steps:

   - Three **defects** — a crash, a missing diagnostic channel, and a build
     hazard.  Found 2026-10-02 while testing 7a; none was caused by it.
     Commits `1e7432a` (repeated bare literal), `244840c` (warning channel),
     `d036c21` (stale object); an earlier draft of this entry quoted
     `32d25df`, `32fae64` and `0444e66`, which do not exist in this tree.
   - Two **notation decisions** — how a rule referenced twice names its
     fields, and where a `%action{ }` may sit (with the empty alternative
     and the terminator riding along).  These are cheap to build and
     expensive to defer: **13a freezes the notation**, and its pretty
     printer has to project every construct onto ALGOL 60, Wirth, yacc and
     ABNF.  A construct added after the printer is written is a construct
     added to five places.  So they land here, well before their size
     suggests.

   - **A repeated bare literal is refused, not crashed on.**  *Done
     (1e7432a).*  The entry said "a group whose whole content is a
     repetition crashes the C backend"; probing found it wider on both
     axes.  The shapes are `*"a"`, `1*"a"`, `( *"a" )`, `"k" *"a"` and
     `3*5"a"` — any repeated bare literal at phrase level, grouped or not —
     and it is not one backend: C raised `CONSTRAINT_ERROR` at
     `hbnf_c.adb:3724` and Zig at `hbnf_zig.adb:1463`, both discriminant
     checks on an `E.Items` the element does not have, while Rust and Ada
     "succeeded" and emitted a parser referencing an entry type they never
     declared (`rustc: cannot find type DocEntry`).  So no backend
     represents it: two crash and two emit code that does not compile.
     Such an entry would hold nothing, so the fix is the backend contract's
     — one check in `HBNF_Compilable`, for all four, naming the two
     spellings that work (`*( "a" )` for a list of entries, or a character
     rule to repeat the character).
   - **A block between elements.**  *Done 2026-10-05.*  This was a property
     of the whole `%scan{ }` / `%action{ }` / `%emit{ }` family (decision 8),
     not of one member: a block had to end its rule, so `expr = term "+"
     %action{ emit("ADD"); } term` was refused at the column after the
     block, and a multi-alternative rule got one action for the whole
     rule, discriminating on `n->kind`.  That is META II's `.OUT` position,
     and it is the difference between a parser generator and a
     compiler-compiler (`COMPILER-COMPILER.md` claims the latter).

     **Built as the same transformation `Lift` already did for a group.**
     `Element_Kind` gains `Block`; `Parse_Pattern` appends one when a
     `%action{ }` sits between elements and further elements follow (a block
     that *ends* the sequence is still not one — it stays the rule's own
     `Action_Code`, which is what keeps every existing grammar's output
     unchanged).  `Lift` then turns each `Block` into a hidden rule
     `<owner>_<n>` whose pattern is empty and whose `Action_Code` is the
     block, and puts a `Name` reference in its place.  One block per
     alternative falls out, because each alternative's block is lifted
     separately.  `%scan{ }` between elements stays refused: a recognizer
     that matches nothing is a contradiction, and the existing message
     ("`%scan{ }` takes the place of a pattern") is the right one.  A
     `Block` never reaches a backend.

     **The `Block` variant is the one thing that touched the backends**, and
     only at compile level: adding a value to `Element_Kind` obliges an arm
     in every exhaustive `case` (the same shape as the existing
     `when Char_Range => null;`), so the four emitters, `HBNF_Compilable`
     and `HBNF_Match` each gained one.  Two of them are semantic rather than
     `null`: `El_Nullable` returns True (a block matches nothing), and
     `Image` renders it as `%action{ ... }`.

     **What the entry claimed and this falsified.**  An earlier draft said
     "reader-only, no backend change".  That was untested and wrong — see
     the empty-rule defect below, which the lift necessarily triggers.

     Still open from this item, and deliberately not built here: an explicit
     **empty alternative** (today a bare leading `|`, as in
     `xs = | xs y`, written ninety times by the lists patch to match
     parse.y's `/* empty */`; META II spelled it `.EMPTY`) and an
     **optional rule terminator**, so a machine-generated or pretty-printed
     schema does not depend on the indentation rule — 7a made yacc's
     trailing `;` survive only because `;` starts a comment.  Neither is
     needed by 13b; both are still wanted before 13a freezes the notation.

   - **A rule whose shape is empty or unassigned breaks three backends.**
     *Found 2026-10-05 by the verify-first step above, and fixed.*  A
     zero-member rule is what the mid-sequence lift produces, so it had to
     be settled first — and it turned out to be a latent cross-backend
     defect that no grammar in the tree exercises (none has an empty rule,
     which is why the suite was green):

     | backend | what an empty rule emitted | |
     |---|---|---|
     | C | `struct mid_s { size_t _line; };` | fine |
     | Ada | `type Mid_Type is record` / `end record;` | **illegal Ada** — "component declaration expected" |
     | Rust | `let mut r = Mid::default();`, unused `p` | fails `-D warnings`, which `portable.sh` passes |
     | Zig | `fn parse_mid(p: *P)` with `p` unused | **hard error**, always |

     Fixed in `ada_struct.tmpl` (`{{^items}} null;`) and in the Rust and Zig
     signature/body emission.  A jet rule also has an empty pattern but does
     read `p`, so the parameter renaming tests *empty pattern and no jet*.

     Two more Rust defects came out of the same thread, both pre-existing and
     both visible only once the daemons' Rust was held to `-D warnings`:
     `let mut r` was emitted whenever the sequence branch was taken, even
     when nothing assigns `r` (`wildcard = "*"`, `doc = "n"`); and the
     scanner's repetition counter, `let mut cnt`, is incremented but never
     read when the repetition is unbounded with no minimum.  Both fixed, and
     **all ten daemon parsers now compile under `-D warnings`; before this
     none of them did.**

     **The byte-identity gate, stated honestly.**  C, Ada and Zig output is
     **byte-identical** to the committed emitters for all ten daemons — the
     empty-struct and Block arms are inert on every grammar in the tree.
     Rust is **not**: 380 lines across the ten files, and every one of them
     is one of those two fixes (`let mut r` -> `let r`, and dropping the
     unused `cnt`).  This is a deliberate, proven correction to generated
     code that did not compile, not drift; it is recorded here rather than
     left to be discovered.  The snapshot baseline for the Rust backend
     moves with it.

   - **A warning channel.**  *Done (244840c).*  `HBNF_Grammar.Warn`,
     `Warn_Once`, `Warnings`, `Reset_Warnings`, `Set_Werror`, and
     `--werror`; the shadowing report moved onto it and 7a's `:` notice is
     its first new user.  The original entry follows.

     The reader had no warning channel, only `Parse_Error`.  That is
     why 7a's one remaining piece is unbuilt: a file whose assignment
     operator is `:` must warn once that `|` is PEG first-match and name
     `/` for the union case, and there is nowhere for that to go.  Step 8's
     linter (nullable repetition, unreachable rules, shadowed ordered
     choice, ambiguous `/`) needs the same channel for every one of its
     findings, so building it here serves both.  It wants: a severity, a
     source span, a once-per-file suppression for the `:` case, and a
     `--werror` for the test harnesses.
   - **`expr = term '+' term` is refused, and that is a design bug.**  All
     four backends raise "rule `term` is referenced twice in one
     alternative; split it into alias rules … so each gets its own field"
     — five copies of the check, two of them in `hbnf_c.adb`, the same
     multi-copy problem as the cycle detector.  The message states the real
     cause: a tree field is named after the rule it references and after
     nothing else, so two references to one rule collide.  The grammar is
     well-formed; the naming scheme is not.  And the case it refuses is the
     canonical expression production — it is META II's own one-line example
     (`EXPR = TERM $( '+' TERM .OUT('ADD') …`), and every arithmetic
     grammar since.  Forcing `lhs = term` / `rhs = term` adds two rules and
     two tree types to say nothing.

     **The hard constraint on any fix: the nine daemon parsers stay
     byte-identical.**  Field names are what the bindings read (`n->host`,
     `n->port`) and what makes `parse_config` a drop-in for `parse.y`, so a
     fix may not rename a field that exists today.  Two parts, and only the
     first is required:

     1. **Positional by default.**  *Done 2026-10-05*, and by a smaller
        route than this entry assumed.  Rather than thread a second name
        through `Member` in all four backends (its `Name` does double duty:
        the field name and the rule the type is looked up on), the split
        happens in `Lift`, as a pass beside the group flattening: the second
        and later references to a rule in one alternative become **alias
        rules** — `expr = term '+' term` is rewritten to
        `expr = term '+' term_2` with `term_2 = term`.  The existing alias
        machinery already resolves such a reference to the target's type,
        so the field is `term_2` and its type is still `term`'s; the first
        reference keeps the bare name, so nothing existing moves, and the
        suffix is the `<rule>_<n>` convention `Lift` already uses.  One
        place, not five, and no change to any `Member` record.  The five
        copies of the old check are now unreachable rather than removed —
        they are left as an invariant, since they fire only if a duplicate
        reaches a backend, which the pass prevents.

        **Character rules are exempt**, and finding that out was the whole
        of the first attempt: `string = DQUOTE *( … ) DQUOTE` names one
        class twice as its normal spelling, has no fields to collide, and
        `Lift` already skips char rules for the same reason.  Without the
        exemption the pass renamed `DQUOTE` in every daemon.

     2. **An optional label where the names matter.**  `term_2` is
        position-dependent and reads badly in a binding, so a grammar that
        cares says so: `expr = lhs:term '+' rhs:term`.  `label:item` is the
        most widely recognised spelling outside yacc, and it reuses a
        character this plan has already committed to disambiguating by
        position — 7b's wire width is a `:` glued to a name and followed by
        a digit, 7a's assignment operator is a `:` surrounded by blanks, so
        a `:` glued to a name and followed by a *name* is the label.  Worth
        saying plainly: three meanings for one character is a lot.  The
        collision-free alternative is Bison's `term[lhs]`, which `[ ]`
        already owns as the optional, so the gluing rule is the lesser
        evil.  If a better spelling turns up before this lands, take it.
        **Still open — deliberately deferred.**  Positional naming alone
        closes the defect below; the label is for readability, and it can
        land before 13a freezes the notation without holding up 9b.

     **The coupling this entry missed: it is not independent of the
     mid-sequence block above.**  That item's canonical example is
     `expr = term "+" %action{ } term` — the same two references — so the
     lift alone still hit this check, and the two land together or the
     example does not compile.  Verified in the tree: with the lift built
     and this not, the example was refused with exactly this message.

   - **Stale `.o` and `.ali` files in the source directory silently win the
     link.**  *Done (d036c21)* — `tests/e2e.sh` clears them and refuses to
     run against a binary older than its newest source; README says to
     build through the project files and why.  `gnatmake -I. -D <tmpdir> hbnf.adb` compiles into the temp
     directory, but `gnatlink` takes `hbnf.ali` from `.`, so a build can
     link yesterday's objects and report success.  They are gitignored, so
     `git status` stays clean while the binary is stale.  This cost a
     confused afternoon: 7a's lexer changes compiled and did nothing, and
     every result taken against that binary had to be re-run.  The fix is
     documentation and a build rule, not code — build through `hbnf.gpr`,
     which keeps its own object directory, or `rm -f *.o *.ali` first — and
     the test harnesses should refuse to run against a binary older than
     its newest source.

13. **hbnf in hbnf.**  The last area, because it is a claim that the
   notation is finished.  13a describes the notation; 13b asks whether the
   notation can describe the tool.

   13a. **A grammar for the notation, and a round-trip pretty printer.**
   The last step, because it is a claim that the notation is finished —
   which is also the sense in which **this step freezes the notation**.  Its
   printer projects every construct onto four historical notations, so a
   construct added after it is written is a construct added in five places.
   Step 12 therefore carries the outstanding notation decisions, small as
   they are, and nothing should arrive here unsettled.

   **Not the file that already exists.**  `hbnf_schema.hbnf` is a grammar
   for *hbnf the configuration format* — `config = *( entry )`, blocks and
   statements, the pf.conf-shaped language — and is for the interpreter;
   all four backends refuse it today (undefined `dec`, `comment`).  This
   step wants the other thing: a grammar for **the `.hbnf` schema notation
   itself**, so hbnf describes the language hbnf is written in.  Different
   file, and the names must not be confused: call it `hbnf.hbnf`.

   That makes hbnf self-describing, which is the thread HISTORY.md follows
   from McCarthy's `eval` onward — and the same caution applies.  A
   self-description is trivial when the defining language is understood,
   so the thing that makes it worth more than a demonstration is the
   second half:

   **A round-trip pretty printer.**  Read a schema, print it, and get the
   same meaning back — with comments preserved, not discarded, because a
   grammar's comments are half of what it is for.  The reader already keeps
   a leading and a trailing comment per rule and round-trips them into
   generated output, which is the foundation; this needs them kept through
   a full re-print.

   There is prior art one layer down, and 9c must not throw it away:
   `tests/hbnf_check.adb` is a conformance driver whose "accept" requires
   exactly this — parse, print, re-parse, re-print, and the printer must be
   idempotent — for the *config format*, against `HBNF_Config`'s printer.
   9c rebuilds that driver against generated code; this step is the same
   discipline applied to the notation.

   - **Normalizing by default.**  One rule per definition, spelled `=`:
     `::=`, `:=` and `:` all print as `=`.  Comments print as `;` to end of
     line: `/* */` and `(* *)` are read and normalized away.  The point is
     that a grammar pasted from anywhere comes out in one house style, and
     a diff between two schemas is about the grammar and not the notation.
   - **`--preserve`** keeps each definition's and each comment's own
     spelling as written, so a pasted RFC or POSIX grammar round-trips
     byte-for-byte.  That is the stronger gate and the one worth testing:
     read, print, compare to the input.
   - **Historical styles on request.**  Print a schema as ALGOL 60 BNF
     (`::=`, angle-bracketed names), as Wirth EBNF (`:=`, `(* *)`,
     `{ }` repetition, `[ ]` option), as yacc/POSIX BNF (`:`, `;`
     terminators, `/* */`, `%token` declarations for the char rules), or as
     RFC 5234 ABNF (`=`, `=/`, `/` union, `*`/`n*m` repetition, `;`
     comments).  Each is a projection of the one grammar onto one notation,
     and each is a test of the reader: whatever the printer emits in style
     X, the reader must read back to the same grammar.
   - **Where it cannot be faithful it says so.**  Not every grammar
     projects onto every notation: ordered choice has no ABNF spelling,
     `n*m` has no yacc spelling, a jet has no spelling anywhere.  The
     printer names the rule and the construct rather than emitting
     something that reads as equivalent and is not — the same rule step 11
     holds for the tree-sitter emitter.

   **Gates.**  `hbnf.hbnf` reads every schema in the tree, including
   itself.  `--preserve` round-trips all of them byte-for-byte.  Normalized
   output of any schema generates parsers byte-identical to the original's
   (the snapshot, run on printed schemas).  And every historical style
   reads back to the grammar it was printed from.

   13b. **Closing META II's loop: the classification in the notation.**
   *Open, and open to argument.*  Not scheduled; recorded because it is
   the one thing between 13a and a self-hosting hbnf, and because the
   shape it should take is a design question worth settling before anyone
   writes code.

   **What stands in the way.**  13a makes hbnf self-*describing*, which is
   weaker than self-*compiling* — `hbnf.hbnf` through hbnf yields a parser
   for hbnf schemas, not hbnf.  What is missing is the part that chooses
   *how a rule is emitted*: `Analyze`, `Rule_Info`, and the
   Scalar/Enum/Struct/List classification, which decide which template a
   rule shape gets.  Those are Ada, and until they are expressible in the
   notation the loop does not close.

   3b moved this much closer than it looks.  The emitters are no longer
   Ada that writes C; they are 65 `{{ }}` templates driven by the tree,
   with the Ada reduced to choosing which template a rule shape gets.  The
   output shape is already data.  Only the choosing is not.

   **The requirement, stated as a constraint and not a wish: it must not
   feel bolted on.**  A per-rule shape declaration would be a bolt-on
   twice over — it adds notation, and it duplicates what the rule's
   pattern already says.  Whatever this becomes has to read like the
   notation grew it.

   **The shape is decided: `%emit{ }`, the family's third member** (agreed
   2026-10-03, decision 8).  The family had two members and a gap at the
   generative level; that is the gap.  What remains open is not *whether*
   but *how*, and the open questions are listed below.

   With `%emit{ }`, a backend stops being Ada and becomes a schema: a
   grammar whose input language is the hbnf notation (`hbnf.hbnf`) and
   whose rules match rule *shapes*, each with an `%emit` block naming the
   template that shape renders through.  Scalar, Enum, Struct and List
   stop being an Ada enumeration and become four alternatives of a rule.
   That is META II's `.OUT`, one level up: output directives inside the
   syntax, which the HISTORY.md passage names as the part of META II that
   did not survive into the parser generators.

   **The semantics it needs are the ones already wanted elsewhere**, which
   is the argument that this is a family extension and not a new feature:

   - **Position-aware**, so a block can sit between elements rather than
     only at the end of a rule — step 12's mid-sequence `%action{}` fix,
     which `Lift` already has the machinery for.
   - **Per-alternative**, which falls out of position-awareness: today one
     action serves a whole rule and discriminates on `n->kind`.
   - **A block may name a template, as shorthand for the code that renders
     it.**  `%emit{ c_struct }` renders that template against the node;
     after 3b this is what the four backends do, just not sayable in a
     schema.  Whether the family is `%emit{ }` only or `%action{ }` too is
     open — `%scan{ }` is not a candidate: a recognizer renders nothing.
   - Available to every backend, not C only, which `%action{}` is today.

   **What it must not break.**  The nine daemon parsers stay byte-identical
   and `parse_config` stays a drop-in for `parse.y`.  A self-hosting path
   that cost the project its only hard external gate would be a bad trade;
   byteident is the gate here as everywhere.

   **And one ordering fact.**  This is second-order — a grammar whose input
   is grammars — so it needs `hbnf.hbnf`'s own tree types to exist, which
   means 9b first.  `hbnf_schema.hbnf`'s mutually recursive `entry`/`block`
   is already the case in point: the backends refuse it today, and that
   refusal is why the interpreter still exists (9c).

   **What is still open, now that the member is settled.**  Four questions,
   and the first is the one that decides whether this feels native:

   1. **How does a rule match a rule *shape*?**  A schema whose input is
      schemas needs to say "a rule that is one reference", "a rule whose
      alternatives are all literals", "a rule with a trailing repetition".
      A second-order *grammar* over `hbnf.hbnf`'s own tree is the most
      BNF-native reading — those four are alternatives of a rule, and
      Scalar/Enum/Struct/List stop being an Ada enumeration.  A
      pattern-matching sublanguage over `Rule_Info` would be more direct
      and less native, which is the trade.
   2. **One schema per backend, or one schema with a language directive?**
      `language C` already exists per file and decides which code blocks a
      backend takes; four schemas sharing an include is the obvious first
      answer and matches how `obconf.hbnf` is shared today.
   3. **How does a block name a template?**  `%emit{ c_struct }` reads
      well, but a bare name inside a block that otherwise holds code is a
      second meaning for the same brackets.  It may want its own spelling.
   4. **Does `%action{ }` change, or only `%emit{ }` differ?**  Position
      and per-alternative behaviour are wanted for both (step 12).  Running
      bottom-up after the parse is right for a binding and wrong for a
      one-pass translator, so the two members may legitimately differ on
      *when*, while sharing *where*.

   **And a standing alternative.**  Leaving the classifier in Ada and
   calling 13a the end is defensible — self-describing is a real property,
   and McCarthy's `eval` was useful without being a compiler.  Reynolds'
   warning in the HISTORY.md passage applies here more than anywhere: a
   self-definition is trivial when the defining language is understood.
   The reason to do it anyway is Sitaker's — a metacircular *compiler* has
   to confront what an interpreter glosses over, and that confrontation is
   where the design errors show up.  `expr = term '+' term` is the
   evidence: it was found by asking what META II could do that hbnf
   cannot, not by any test.

**Code-size optimization, deferred like 4f.**  The generated parser for a
small wire grammar (the IRC message) is ~1,000 lines against ~280
hand-written, and the gap is structural, not a correctness cost.  It is
not a gate; it is recorded here so the shrink lands once the feature set
is settled, against a generated-line-count figure taken then (4f's
byte-identity gate is the cycle analogue).  The five items, in payoff
order:

1. **Emit only reachable rules.**  A grammar may `include "common.hbnf"`
   and reach three of its rules; every backend still emits a `Parse_*`
   function and type for every rule in every included file, dead or not.
   Reachability from the root — through includes, `=/` extensions and
   overrides — decides what is emitted; the rest is never called.  This is
   what lets a grammar keep its includes whole and stay small: a schema
   that includes `common.hbnf` and uses `SP` must not carry `Parse_NUL`
   … `Parse_TILDE`.  The grammar is not expected to trim its own includes
   to work around the emitter.
2. **Optional is a nullable field, not a one-element vector.**  `[ X ]`
   currently becomes a `package …_Vectors` instantiation, an entry record
   and a subtype — three declarations to say "maybe".  A nullable access or
   a discriminant is one.
3. **Repetition reuses one list type.**  Each `*( X )` instantiates a fresh
   `Vectors` plus an entry record; a shared parameterized element list
   collapses that per-rule boilerplate.
4. **Emit the token layer only when a grammar tokens.**  A pure
   character-rule grammar still gets `Token_Kind`, `Token`, `Token_Vectors`,
   `Line_Vectors` and `Parse_Tokens`; gate that layer on the grammar using
   jets/`%scan`, and emit a direct string reader otherwise.
5. **Share the per-rule save/backtrack boilerplate.**  Every `Parse_*`
   repeats save-position / `when Parse_Error => P.Pos := Save`; a single
   helper — or emitting the backtrack only where ordered choice or
   optionals actually need it — removes most of it.

Each item changes no parser's accept/reject behaviour, so the daemon
corpus, e2e and byte-identity gates hold throughout; each is
regression-tested by a generated-line-count figure, the way 4f is by
cycles.

## Not in this plan

- RBNF (RFC 5511's routing BNF).
- GLR, or trying another alternative after a later failure.
- Case-folding non-ASCII rule names.
- Guessing any setting from an include or from seeing `%x`.
