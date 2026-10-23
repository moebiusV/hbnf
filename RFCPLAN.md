<!-- {% raw %} -->
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

**RFC corpus** (`corpus/rfc/`).  The BNF fragments of the RFCs, pulled in whole
where they compile and in pieces where they do not.  Each fragment keeps:

- the RFC's ABNF verbatim — `<rfc>-<n>.bnf`, with the form hbnf compiles beside it as `<rfc>-<n>.hbnf`, its `.md`, and `.vectors/`;
- the error messages hbnf gives and what each means;
- the **fixed-up** version, or — where the repair is involved — a note saying
  how to make it (e.g. a `<prose-val>` that defers its real definition to two
  or three other RFCs is rewritten to the rules those RFCs give, with the
  provenance named).

The corpus is where discoverability is proven: a fragment is "done" when its
messages alone tell the author how to fix what hbnf could not accept
silently.

**ALGOL 68, and C++ after it: far in the future (the user, 2026-10-22: "defer c++ and
algol68 to far in the future").**  They were next in the running order (the user, 2026-10-18: "do algol68
before c++"), and nothing else waits on them now.  ALGOL 68 is to be written in an hbnf that has gained what the W-grammar does (the user,
2026-10-18: "we won't do ALGOL 68 in precisely the W-grammar, we'll do it in the
hbnf that is updated to do what a W-grammar does"): parameterised rules for the
Report's NOTION families (**built 2026-10-19**: `list(X)`, number parameters over a domain,
clauses for single values, domain and growth checks, every backend; `tests/params.sh`), a back-reference for consistent substitution, `where`
as the context and `%where` machinery of decision 13, and a checking pass over
the AST for modes and coercion.  `METACOMPILERS.md` ("W-grammars") says what
each is.  **ALGOL 60 first** (done 2026-10-18: `corpus/algol60/algol60.hbnf`,
`tests/algol60.sh`).  What ALGOL 60 taught, to carry into the W-grammar work:
a "not followed by" test and trying the next alternative after a later failure
(decision 14) would let the Report's BNF be used as it is written (its
arithmetic/Boolean split, its `:` and `:=`) instead of rearranged; and two
generator bugs on recursive grammars were found and fixed.  **The test is built
(2026-10-18, C): `!x` and `&x`**, so the grammar says `label ":" !"="` and the
assignment no longer has to be tried first; x is a literal, a token or
alternatives of those (`!( "=" / ":" )`), is read like any element after the
blanks, and leaves no trace if it fails (it runs on a copy of the parser);
`tests/lookahead.sh`.  Still to come: the retry after a later failure, then
parameterised rules.

## Decisions

1. **Two alternation operators, two meanings.**
   - `|` is ordered choice, as in PEG and as parse.y grammars are read:
     the first alternative that matches wins.  The shadowed-alternative
     check stays.
   - `/` is ABNF's union: every alternative is legal.  Between character
     ranges it is a set, the same as `|`; in a character rule the scanner
     takes the longest alternative.  Between phrases it compiles without
     backtracking, and the author writes it as the RFC does:
     - the reader looks for an order of the alternatives in which ordered
       choice accepts the same language — no alternative can match text that a
       later one matches more of, or (when it matches the same text and what
       follows the choice could continue it) less of — and writes the choice in
       that order.  "Longest first" is found, not required of the author; the
       one that can match nothing goes last;
     - this is decided on the alternatives' text, with an automaton per
       alternative searched for the shared text, so there is no limit on how
       many code points it takes to tell two alternatives apart
       (`1*DIGIT "." / 1*DIGIT ":"`, `"a" "b" "c" / "a" "b" "d"`);
     - what no order fixes is a union that needs backtracking: two alternatives
       that match the same text with different continuations
       (`IPv4address / reg-name`).  hbnf takes the first alternative that
       matches and is followed by something that can follow the choice, as
       RFC 3986 section 3.2.2 says for `host` ("first match wins"), with a
       warning naming the two; a `%where { }` block (decision 13) is the
       author-written form of the same check.
     (*Amended 2026-10-06, step 5.*  The plan was FIRST/FOLLOW sets and factoring
     a shared prefix, `p = "a" / "a" "b"` into `p = "a" [ "b" ]`.  A first cut
     with two code points of lookahead resolved the RFC corpus's `/` except
     where the difference came later (`h16 ":" h16 / IPv4address`), and a
     fixed depth is a surprise.  The automaton check needs no factoring, and
     keeps the tree types: reordering does not change them.)
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
   includes, in the order it writes them, since that order is the scanner actions'
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
   position, and a scanner action is called there.
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
8. **Scanners, actions and emitters are code — one family of three.**  A
   `%scan{ }`, `%action{ }` or `%emit{ }` block holds the code that runs,
   usually one call to a function the file defines in its epilogue
   (`%scan{ return ipv6_match(s, pos, len); }`), with the function's
   prototype in the preamble.  hbnf never rewrites the code.  Most of the
   remaining 17 scanner actions become character rules instead, which also makes them
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
   author writes the rule or a scanner action.  A hole left for later is then a
   schema error that points at itself, rather than an `XXX` in a comment.
10. **Core rules.**  `common.hbnf` includes `ascii.hbnf` and holds the RFC 5234
    Appendix B.1 classes (`DIGIT`, `ALPHA`, …, `WSP = SP | HTAB`) and
    `CRLF = CR LF`; `ascii.hbnf` holds the named single characters (the C0
    controls, blanks, `DEL`, `DQUOTE`).  `LWSP` waits for repetition
    inside character rules, which `Is_Char_Rule` refuses today.
11. **Negation is `~`.**  *Done 2026-10-17* (tests/schema.sh, in all four
    backends).  `~rule` matches one code point not in the set
    `rule` matches (a complement); repetition composes, so `*~rule` is
    "until rule" (SNOBOL's `BREAK`).  A hbnf extension — ABNF has no
    negation — and it collapses the explicit `%x` complements the lexer
    rules would otherwise spell out: `comment = "#" *~LF`,
    `string = DQUOTE *( "\\" %x00-10FFFF | ~(DQUOTE | "\\") ) DQUOTE`.
12. **Comma lists are `#`.**  *Built 2026-10-18 (`tests/commalist.sh`).*  `#` is `*` with an implicit comma separator:
    `n#m element` is comma-separated repetition, `#element` is `1#element`.
    It is sugar for `element *("," element)` — the same list the daemon
    grammars write left-recursive — so it inherits parse.y's semantics: no
    trailing comma, no empty elements.  Deliberately stricter than HTTP's
    `#rule`, which allows empty elements (a known server-bug source).

13. **Context-sensitivity: a `%where { }` block.**  C is the standing
    example: with `typedef int A;` in scope, `(A) * 0` is a cast of `*0`, and
    with `int B;` in scope `(B) * 0` is a multiplication.  The two cannot be
    told apart without consulting a symbol table *during* the parse, so no
    context-free grammar settles it.  So does a name that parses and still has
    to be looked up (`host` as a DNS name).

    The bar here is lower than it looks, because tree-sitter does not solve
    this either.  Measured 2026-10-01 against tree-sitter-c: both lines
    produce the *same* tree, `(binary_expression (parenthesized_expression
    (identifier)) (number_literal))`.  The typedef case is simply wrong — it
    has a `cast_expression` rule and cannot tell when to use it, so
    precedence picks multiplication both times.  That is fine for
    highlighting and is not a correct parse.  So "as general as
    tree-sitter" does not require this; being *right* does.

    The shape is a block after an alternative, like `%action{}`, that decides
    whether the alternative holds:

        typedef-name = word %where { return is_typedef(text, len); }
        host = IP-literal / IPv4address / reg-name %where { return in_dns(text, len); }

    It is code, and hbnf does not restrict what the code does: it reads state,
    writes it, calls out to the network.  What hbnf owes the author is the
    order it runs in, stated plainly: a `%where` runs each time its
    alternative is tried and has matched, in parse order, and an alternative
    that fails it (or a later element) is backed out of, so the block runs
    again where the parse backtracks and the same alternative is tried
    again.  `%scan{}` is called the same way, at each position its rule is
    tried.  `%action{}` is the one that runs once, after the parse, bottom-up,
    because the tree it reads is only complete then.  Like the scanners, a
    `%where` is written per backend (`%where Rust { }`), and the guard hbnf
    writes itself for a union that needs backtracking (first match wins, see
    decision 1) is the same hook with generated code.

    It does not make hbnf ambiguous: the block decides a branch, it does not
    explore several.

    **Settled direction (2026-10-17, the user's): context is data the grammar
    names, scoped, and the parser threads.**  hbnf was never context-free --
    ordered choice, scanner actions, exceptions and the wire layer's expressions over
    earlier fields are already outside it -- and "context-free" described only
    what BNF alone can decide.  Context is stored by the grammar and consulted
    by the parser, in a notation a BNF reader is not surprised by:

        context types                              ; a scoped set of names
        typedef-name = identifier ? types          ; an identifier that is in `types`
        declaration  = specs declarators ";"  %bind types += declarators.name
        block        = "{" %scope *statement "}"   ; bindings made inside vanish at "}"

    - **A context is a persistent value.**  `%bind` makes a new version and a
      backtrack restores the old one, so a speculative bind costs nothing and
      leaks nothing, and a bind may run *during* the parse, where a later `?`
      test sees it.  (This is the answer to why `%action` waited for the end of
      the parse: side effects a backtrack cannot undo.  A persistent value has
      none to undo.  `%action` stays the post-parse member.)
    - **A definition is a label** (the user, 2026-10-18: "`foo: mv r0,r1` is like
      `foo := lambda mv r0,r1`").  A label, a procedure, a typedef and a macro
      are one thing: a name bound to what follows it.  So the context is not
      only a set of names: an entry may carry a value (the node, or the place in
      the text), a use looks the name up, and a use before the definition (a
      forward `GOTO`) is a lookup that the AST walker does after the parse, where
      every definition is known.  Not built: a value stored with a name.
    - **Code for what the notation cannot say:** `%bind { }` and `%where { }`
      in any language, reading and writing the context through a small API.
    - **Precedents weighed:** Prolog DCG arguments and attribute grammars
      (inherited attributes: pure, but heavy to write), yacc's lexer hack (a
      mutable global; unsafe under backtracking), ANTLR's semantic predicates
      (the author owns the hazard), IMP72's syntax extension (powerful, a much
      bigger machine).
    - **Where it lands:** step 6, with the other compiler-compiler interfaces,
      in C first, tested on `(A) * 0` (a cast when `A` is a typedef name, a
      product when it is not) before a C subset is tried.

    **Built 2026-10-18 (C), in the first spelling, local to the rule that uses
    it** (the user: "keep things local ... but clean and easy to read"):
    `context types templates` declares contexts; `identifier ? types` fails the
    alternative unless the text just matched is in `types`; `%bind types +=
    declarators.name` adds a field's text when that point of the rule is
    reached (or `%bind { code }`); `%scope` makes what is bound after it vanish
    when the rule's alternative ends; `%where { code }` is a test with the
    matched text as `text, len`.  Code reads and writes a context with
    `HBNF_IN (ctx, s, n)` and `HBNF_ADD (ctx, s, n)`.  A context is a stack of
    names with a hash index, so a lookup is a hash and putting it back to a
    mark is a pop; every branch of an alternation, every iteration of a
    repetition and every rule that can fail takes a mark and returns to it when
    it gives up, so what a wrong guess bound is gone with the guess.  Only a
    grammar that declares a context pays for any of it.  `tests/context.sh`
    runs the six cases (cast, product, undeclared, inside a block, after the
    block, a guess that bound and gave up).  C only; the other backends refuse
    `context` with a message.  `%where` and `%bind { }` are in the file's
    language (C).  Not yet: negation (`? !types`), a value stored with a name,
    contexts across the statements of a `statements` parser.

14. **Ambiguity: fork only where it occurs, and settle it in a fixed order.**
    (Decided 2026-10-18, from the study of `hbnf15.txt`, with the user.)
    Ordered choice stays the fast path: a choice the generator can show is
    decidable costs what it costs today.  The generator looks for the choices
    it cannot show are decidable -- alternatives that can match the same
    prefix and are not told apart by a fixed lookahead, conservatively, since
    ambiguity of a context-free grammar is undecidable and a false positive
    costs only a fork -- and gives only those a local fork: both readings are
    kept for the span of the ambiguity, then one is chosen.  Nothing is
    annotated by the author, and the points are reported when the parser is
    generated (to stderr, with the rule, the alternatives and the reason;
    `--quiet-forks` silences it).  The choice is made in this order:

    1. a `%where` or a context test (`?`) that fails removes its reading;
    2. IMP72's first rule: **a terminal over an expression** -- a word that
       appears literally in a pattern beats the same word read as a variable
       (keywords over identifiers, contextual keywords such as `final`);
    3. IMP72's second rule: the reading that uses **the fewest distinct rules**;
    4. where IMP72 picks arbitrarily, hbnf takes **the first alternative in
       the order the grammar wrote them** -- the same first-match rule as the
       rest of the notation, so a fork never introduces a new kind of
       behaviour.

    The memo of a rule's result at a position must be keyed by the context's
    version, or skipped for a rule that reads context, or a cached typedef
    decision would leak across scopes.  This replaces "GLR, or trying another
    alternative after a later failure" under *Not in this plan*.
    Built, in its local form (2026-10-18, C, `--forks`; `tests/forks.sh`): the
    generator lists the rules whose alternatives can start alike (leading
    literals, a prefix counts, a token meets a word), and a call of such a rule
    that is followed by more of its sequence is wrapped in a retry: when the
    rest fails, the fields from there on are freed, the position and the context
    mark restored, and the rule is entered again at its next alternative.  The
    tie-break order above is not built: the first alternative that lets the
    sequence finish wins, which is IMP72's third rule alone.  Not built either:
    a retry across a rule's end (the caller of the caller), forks with `%where`
    or `?` after the fork, and the other backends.

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
verbatim.  An RFC's ABNF uses `=`, which hbnf reads.  A grammar in another notation
(`::=` in BNF, `:` in yacc) names it with `dialect bnf` or `ybnf`, and then every
spelling defines a rule; in hbnf's own notation `::=` and `:=` are the metarule and
the hyperrule (`level ::= 1..17`, `binary(N in level) := ...`), as the ALGOL 68
Report's `::` and `:`, and a BNF rule read as one is refused with the line to add.
Where hbnf needs something different,
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

> **Done:** 0, 1, 2, 3, 3b, 4a–4e, 5, 7a, 9a, 9b, 9c, 12.  **Under way:** 7b (the
> wire layer, in C; see its entry for what is and is not built).
> **The POSIX shell grammar (`corpus/posix/`) is part of the core corpus, not
> paused** (the user, 2026-10-23, correcting this note), and it **reads** (2026-10-23): the
> standard's 2.10.2 grammar included unchanged, with the tokens as rules of characters, the
> exception for reserved words, the longer alternative first where yacc's tables looked
> ahead, and a scanner for here-documents.  580 of 581 shell scripts on the machine are
> accepted as `dash -n` accepts them, and the grammar and dash agree on all but three of 1,692
> mutations of them (`corpus/posix/shell.md`, `tests/posix.sh`, `scripts/posix-scan.sh`).  What
> it found in hbnf: names that differ only in case (`name`, `NAME`) now get a `-token` suffix
> under a case-sensitive dialect, and a root rule used inside another rule freed the arena
> mid-parse.  All four backends read it (the scanners for here-documents and `$(( ))` are written
> once for each).  Not done: aliases, back-quote contents, bytes that are not UTF-8.  The ports of hbnf itself to the remaining backend
> languages (step 10) come at the very end.  **The IMP72
> sources (`corpus/imp72/`) are cancelled** (the user, 2026-10-22: IMP72 "is its own
> thing and will get its own compiler"); hbnf does not read the IMP72 compiler's
> sources or bootstrap it.  The comparison with IMP72 in `METACOMPILERS.md` stays
> as history, and what hbnf took from its manual (the choice rule, `A<pos,len>`)
> stays.  **ALGOL 68 and C++ are far in the future** (the same day).
>
> **Critical path:** **5** → **6**
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
     eight, their scanner actions turned into character rules where they can be;
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

   4d. **Convert ntpd first**, then the other eight daemons; scanner actions become
       character rules where they can.  *Done* (26366f1 and the 4d merge):
       the operator, wildcard and AS scanner actions are char rules, and 18 scanner actions remain
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
       doing.  `bench/run.sh` should grow both: a `CLOCK_PROCESS_CPUTIME_ID`
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
5. **`/` between phrases** (decision 1).  *Done 2026-10-06.*  Then:
   - RFC excerpts as regression tests, in `corpus/rfc/`, one id per snippet
     (`rfc5234-1`, `rfc3986-1`, `rfc5322-1`, `rfc9112-1`): `<id>.bnf` the RFC's
     text as published, `<id>.hbnf` the form hbnf compiles, `<id>.md` the
     account, `<id>.vectors/` the inputs; run by `tests/rfc.sh` (the headline
     rules in `tests/e2e.sh`).  *Done 2026-10-06.*  The policy that came out of
     it: an RFC snippet either compiles as written or hbnf says why not and
     how to write it in hbnf, and where the ABNF is wrong it says why and what
     was probably meant.  Now the `.bnf` itself compiles under `--abnf`, so the
     `.hbnf` is the same text plus the line `dialect abnf` (RFC 5234, 3986 and 5322
     as written; RFC 9112 needs `uri-host = host` and its prose `port` left
     out), and the corpus checks both files on the same vectors.
   - `/` between phrases: the reader finds an order of the alternatives in
     which ordered choice accepts the same language (an automaton per
     alternative, `hbnf_lookahead.ad[sb]`), and where a union needs
     backtracking it is first match wins, as RFC 3986 section 3.2.2 settles
     `host`, with a guard on the alternative that backends check where it
     succeeds; a repetition ABNF would give back is rewritten (`*n( A S ) A`)
     or said; no tree type changes.
   - What the corpus found and this step fixed: `whitespace none`, `dialect abnf` and
     `--abnf`; `--root=RULE`; keywords only in a grammar with words; case
     handling for ABNF's strings; a rule named like a built-in type
     (`atom-rule`); a range in a rule of words becomes a rule; `<...>` is
     always a rule (`<pchar>` is `pchar`, `0<pchar>` compiles) and a
     `<...>` nothing defines is "not written yet" with what it probably
     means; `name = %grammar "file"`; per-language scanners
     (`name = Rust { }`), and a warning, not a silent stub, where a backend has
     none; the four assignment operators are one; messages that say how ABNF,
     BNF, EBNF and hbnf differ.  The dialect table is in ABNF.md.
   - `--ebnf`, and the line `dialect ebnf`, read ISO 14977: `n * x` is exactly n,
     `{ x }` repeats, `,` joins, `;` ends a rule (a line end is white space),
     `'..'` and `".."` are strings without escapes, `? .. ?` is a rule not
     written yet.  In the default notation a spaced `3 * x` is an error that
     says to write `3x`.  *Done 2026-10-07.*  `a - b` (exception) is not read
     yet.
   - **Open, from this step:**
     - YBNF: `%token`, `%start`, `%%` and `|` as the union are read, and an
       undefined token is told how to be written (*done 2026-10-07*); yacc's
       actions are not read.  The POSIX corpus (`corpus/posix/`, same layout)
       reads the standard's grammar verbatim and gets as far as defining the
       tokens; what blocks a working `.hbnf` is below.  RFC 822 as a
       snippet (its `#` lists, `<n>*<m>` counts, prose);
     - the exception `a - b` (ISO 14977, and what POSIX's reserved words need:
       `WORD` but not a reserved word, rules 1 and 7a): done for operands that
       are tokens, with a table-driven scanner (a deterministic automaton
       built from the rule's text, the longest match, in all four backends),
       so groups, nested repeats and alternatives of words work as operands
       (*done 2026-10-07*).  With a phrase on a side (a rule that skips
       whitespace, or contains a built-in or `%scan`) it is a *phrase exception*:
       A is parsed, then B is tried on exactly the text A matched
       (*done 2026-10-17*, all four backends; tests/schema.sh).  Found on the
       way and open: in Ada an alias of a record used in a list entry
       (`x = item`, `1*( x ";" )`) is declared before the record and does not
       compile, with or without an exception.  A rule with no named children is a
       token (*done 2026-10-17*; ABNF.md, "Tokens: a rule that is only text is
       one string"): scanned as text, its value the text, in all four
       backends; none of the nine daemon grammars changes.  **Next**: the octet
       mode of the scanner (edges are numeric, so it skips the UTF-8 decode),
       and a repetition bound past 32 inside a token.  The prefix on every generated
       identifier (`ybnf_if`, `abnf_host`, and `bnf_` when a file names no
       dialect) is *done 2026-10-17*; `prefix none` opts out (the daemon
       grammars, and the tests whose hand-written programs use the generated
       names), and the `atom-rule`/`WORD-rule` renames remain only there;
     - `%where { }` (decision 13): code, not required to be pure;
     - `request-target` (RFC 9112) depends on the method, which a `%where`
       could ask; `path` (RFC 3986) is a documentation rule;
     - `OCTET` is a byte in ABNF and a code point up to U+00FF here: the
       binary layer, with bit-precise syntax, below;
     - generation of RFC 5322's full text takes about nine seconds, most of it
       deciding unions; poor messages for lifted rules ("expected
       IPvFuture_2").
   - the character model in Rust, Zig and Ada through the templates.  *Done
     2026-10-06, inside step 9c*, which could not retire its reader without
     it.  (The interpreter used to be named here too, "on the same
     rewrites".  It is not converted, it is retired — step 9c.)
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

       **Notation, settled 2026-10-17** (the user chose it from the five
       historical forms: C `name:N`, BLISS/IMP72 `A<pos,len>`, Ada
       representation clauses, Verilog/VHDL slices, Erlang bit syntax).  It is
       C's spelling with Erlang's strengths, read top to bottom like an RFC's
       packet diagram.  A rule that holds a field is a bit rule; its input is
       bits and its parser is `parse_bits` (`parse_bytes` for whole octets).

       | write | meaning |
       |---|---|
       | `name:N` | N bits (1-64), first field in the most significant bits, big-endian; adjacent sub-byte fields share octets |
       | `name:16le`, `name:8s`, `name:16sle` | little-endian (`le`, `be` the default), signed (`s`) |
       | `name@K:N` | `@` is the place, `:` the width: the field must start at bit K of its record -- an assertion, checked when hbnf can compute it and by the parser when it cannot, so a transcription error against the RFC's bit numbers is caught.  (`@` is "at", as in Ada's `at 0 range 3 .. 7`; it is also an enum literal's number, `"icmp"@1`.) |
       | `name:[expr]` | `expr` octets, a slice of the input |
       | `name:*u8` | the rest of the input (or of the region it is in) |
       | `name:(expr)` | `expr` bits |
       | `0x0800`, `0b101` | a constant; its width is its digits (0x0800 is 16 bits, 0b101 is 3) |
       | `name:N` where `name` is also a rule of constants | the field's value must be one of them |
       | `?(expr)` | a guard: the alternative is taken only when `expr` is non-zero; this is the tag dispatch (an EtherType choosing the payload) |

       An `expr` is C's integer arithmetic (`+ - * / % << >> & | ^ ~ ! == != < <= > >= && ||`,
       parentheses, decimal and `0x` numbers) over the fields read earlier in
       the same record: `options:[ihl*4-20]`.  Bit 0 is the most significant,
       as in an RFC's diagram.  A name with no width is a rule: its record is
       nested; `|` is ordered choice with the position restored on failure.
       `:` keeps all its meanings by position: the rule operator is
       surrounded by blanks, a width is glued to the name that precedes it.

       *Status 2026-10-17.*  Reader (`hbnf_wire.adb`) and C parser
       (`hbnf_wire-c.adb`) work for fixed and expression-sized fields, octet
       runs, constants, value sets, guarded choices, arrays of records and the
       `@K` check; `tests/wire.sh` has Ethernet/ARP/IPv4 fixtures and nine
       refusals.  A group is written `name:( ... )` and a bit count
       `name:bits(expr)`.  The other direction (tree to bytes) exists
       in C, and so does the text form (`name:bitsof(rule)`: bech32 symbols and
       BIP-39 words as 5- and 11-bit words of a text rule, read and written
       through the text parser), and `%action{ }` on
       a wire rule (C; `HBNF_WARN`, `HBNF_FAIL`), `%emit{ }` (a computed field,
       when writing), `{ }` preamble and epilogue, calls to the system's libraries
       (zlib, OpenSSL, the bech32 reference), by their own names, with
       `corpus/bip39/bip39.h` using SHA256 to check and compute its checksum.  Not yet: Rust, Zig and Ada,
       a bech32 address's human-readable part, byte/word units, layout
       records.

       **Settled later the same day.**  A place is `name@K:N`: `@` before `:`,
       the place before the width (the user's choice over `name:N@K` and over
       `name@K,N`, which avoids a second `:` but reads less like C and Erlang).
       The rule operator `:` is the first `:` after a name in column 1, so no
       spacing has to tell it from a width.  `"literal"@N` numbers an enum
       literal, C's `NAME = N` without overloading `=`.  Documented in
       `WIRE.md`.

       **Designed, not built (the user, 2026-10-17):**
       - `@Off:Len` also slices strings: a string is an array of units.  A unit
         is a bit, a byte, a code point or a machine word, and the notation
         must say which, because some machines had 9-bit bytes and 36-bit
         words.  A number may carry a unit (`b` bits, `B` bytes, `c` code
         points, `W` words); a file may declare `byte N` and `word N`; without
         a suffix the unit is the file's own.
       - A record in which every field has an `@` is a register layout, read in
         any order with gaps and overlaps; elsewhere `@` is only a check.

       **Direction (the user, 2026-10-17): text and binary are freely mixable;
       there is no `binary` mode.**  What was built first was a separate path --
       `hbnf_wire.adb` had its own lexer and parser, a `binary` line picked it,
       and a file was all bit rules -- a shortcut, not the design (stage 1 below
       removed it, 2026-10-17).  The design is one notation, one reader, one
       emitter per backend:

       1. **One reader.**  The bit forms (`name:N`, `name@K:N`, `0x` and `0b`
          constants, `[expr]`, `?( )`, `*u8`, `%action`/`%emit`) are elements of
          the main notation; `language` is a directive of the main reader.  The
          wire emitters stay, fed by lowering the unified rules.  (`units`, a
          directive that spelled a message as words, was a stopgap and is gone:
          2026-10-18, replaced by `name:bitsof(rule)`, below.)
       2. **Rules refer across the boundary** (a text rule holding a bit rule and
          the reverse), through one parse state.
       3. **Interleaving inside a sequence** -- `"GET " len:16 payload:[len]
          "\r\n"`: the input position is an octet and a bit offset; text
          elements run when the offset is 0 (and say so when it is not), bit
          elements run anywhere.  This changes the four text backends, and the
          wire emitters fold into them.

       Everything is bits, octets are runs of bits, text is octets read as UTF-8.
       **Layers, not octets (the user, 2026-10-17).**  Because each layer is a
       run of units of the one below, the unit of the middle layer is not
       fixed at 8 bits: a machine with 9-bit bytes or 18-bit words is the same
       grammar with another width (`byte 9`, `word 18`).  A char is a code
       point; its UTF-8 form is a string of octets that maps to it.  And one
       slice syntax serves every layer: `foo:4` is 4 units and `foo@1:4` is 4
       units at offset 1, the unit being the layer of `foo` (bits for a bit
       field, octets for an octet run, chars for a string).  The notation was
       weighed against COBOL's `foo(2:4)`, BLISS's `foo<p,s>`, Ada's `foo(2..5)`
       and Python's `foo[1:5]`; `@offset:length` is the nearest to COBOL's and
       PL/I's offset-and-length and to Ada's `at`, and stays.

       **The user's formulation, 2026-10-17: octets are tokens over bit arrays,
       and strings are tokens over octets.**  A token is a run of units of the
       layer below (decision 7: a rule with no named children is a token, scanned
       by a table), and the lowest alphabet is the bit.  ABNF already has `BIT`
       and `OCTET` among its core rules, so `ttl = 8BIT` is a bit field and
       `name:8` is a convenient spelling of it.  Three consequences: a token over
       units of width W may start at any bit (an octet is eight bits from
       wherever you are, so text after a 5-bit field is read shifted -- an
       alignment rule was added in stage 2 by mistake and removed 2026-10-18);
       the DFA scanner and the union analysis carry over to a bit
       alphabet, so a value set (`0x0800 | 0x0806`) is a token over bits; and a
       token's value type follows its alphabet (a number for bits, a byte string
       for octets, a string for code points).

       **Character sets (the user, 2026-10-18; decisions still to be taken).**
       The middle layer's width is a file parameter (`byte 6`, `byte 9`,
       `word 18`: "take the stream N bits at a time"), and the layer above it
       is chars, so what a unit *means* as a char is a mapping the file must
       name: ASCII, Latin-1 and the other ISO 8859 and Windows code pages,
       EBCDIC (IBM's 037, 500, 1047 and others), DEC SIXBIT, CDC display
       code, FIELDATA, 9-bit ASCII on the 36-bit machines.  A char is still a
       code point; a character set is a table from unit values to code points
       (many are partial, with holes), and a token over it is scanned the
       way a token over octets is.  Taste decisions to take before building:

       1. **Where the name goes.**  A directive for the file
          (`charset EBCDIC-1047`), a per-rule or per-field override for mixed
          files (an EBCDIC header over an ASCII payload), or both.
       2. **Literals.**  `"GET "` is code points; in an EBCDIC file it must
          become the units that spell them, at generation time, so a literal
          is written once and means the same thing in every set.  `%d13.10`
          and `%x` constants stay unit values, not code points.
       3. **Core rules.**  ALPHA, DIGIT, SP and CRLF are defined over code
          points, so they follow the file's set; `OCTET` and `BIT` do not.
       4. **Standard tables, not our own.**  The tables exist (IBM's CDRA, the
          unicode.org mappings, glibc's `iconv`/gconv tables, ICU's ucm
          files), so, as with checksums, hbnf takes them by their own names
          and attributes them instead of retyping them; whether the generated
          parser links `iconv` or embeds a table is the open point (a
          self-contained parser argues for a table, generated from the
          standard mapping file, per set actually used).
       5. **Holes and errors.**  A unit with no code point is a parse error
          that says which unit and which set; whether a set may declare a
          replacement is for later.
       6. **Output.**  A parser reads a set; a writer writes it; round-trip
          has to be exact, so a set that maps two units to one code point is
          refused for writing.
       7. **Relation to UTF-8.**  UTF-8 is a string of octets that maps to a
          code point, so it is one more set with a variable-width mapping;
          the fixed-width sets are the easy case and come first.

       **Answers (the user, 2026-10-18), and what follows from them:**

       1. **Both.**  `charset NAME` for the file, and a per-literal prefix (like
          C's `u8"..."` and `L"..."`) or per-rule override for mixed files.
       2. **Literals: options.**  (a) *Literals are code points* and are
          transcoded to the file's set at generation time, so `"GET "` in an
          EBCDIC 1047 file is the units C7 C5 E3 40; a character the set lacks
          is a generation-time error naming the character and the set.  (b)
          *Literals are unit values*: only `%xC7.C5.E3.40` is allowed outside
          Unicode files; explicit, no magic, but an RFC's ABNF cannot be pasted
          in.  (c) *A prefix names the set per literal*: `ebcdic"GET "`; exact
          and good for mixed files, verbose for whole ones.  Recommended: (a)
          as the default with (c) as the override, so a file says its set once
          and a literal says otherwise only when it differs.
       3. **Core rules, fleshed out.**  RFC 5234 Appendix B defines ALPHA, DIGIT,
          SP, CRLF, VCHAR and the rest by numeric values *of US-ASCII*, which
          are Unicode code points below 128.  So the rule is: `%x41` and the
          core rules name *characters* (code points), and are transcoded exactly
          as literals are; in an EBCDIC file ALPHA is the units for A-Z and
          a-z (C1-C9 D1-D9 E2-E9 81-89 91-99 A2-A9), not the values 41-5A.
          The raw-unit spelling is the bit-field constant, `0xC1`, which
          already means a value of that many bits, not a character.  So `%x`
          is the character form and `0x` the unit form, with no new syntax.
          `OCTET` and `BIT` are layer names, not characters, and do not change
          (`OCTET` is a unit of the middle layer, 9 bits in a `byte 9` file);
          non-ASCII characters in a core-rule position are written as
          literals or `%x` code points, as now.
       4. **Link nothing unless it is needed.**  ASCII and UTF-8 need no table
          and no library.  A one-unit set (at most 9 bits, so 512 entries) is a
          table generated at hbnf time from the standard mapping file (the
          unicode.org mappings, glibc's charmaps; attributed, not retyped) and
          embedded in the parser.  Only a multi-unit set (Shift-JIS, GBK)
          links `iconv`, and only a grammar that names one pays for it.
       5. **Unassigned units** are not a decision: a unit with no character in
          the set read as text fails with a message naming the unit, the set
          and the position (`unit 0x41 at 17 is not a character of
          EBCDIC-1047`).  Read as bits or octets (`0x41`, `name:8`), it is
          just a value, so a binary field inside an EBCDIC file is no
          problem.
       6. **Round trip is always possible (the user's requirement).**  The
          approach: what was read is kept.  A token's value is its code
          points, and the units it came from stay reachable (they are a slice
          of the input, as strings already are).  Writing a tree that was
          parsed and not changed re-emits those units exactly, whatever the
          set's mapping.  Writing *new* text encodes each code point by the
          set's inverse; where the mapping is not one-to-one the table says
          which unit is canonical (the lowest, unless the standard names
          one).  The examples that make this necessary:
          - *Two units, one character* (illustrative: a vendor table that maps
            two control units to the same code point): reading is fine; an
            unchanged token writes back its own unit, a new one writes the
            canonical unit.
          - *Overlong UTF-8* (`C0 80` and `00` both mean U+0000): the standard
            forbids it, so the reader refuses it with a message rather than
            keep two spellings of one thing.
          - *A character the output set lacks* (U+00E9 into SIXBIT, or into
            EBCDIC 037 variants without it): not recoverable, since no unit
            spells it; the writer fails with a message naming the character,
            the token, and the set.  That is a property of the set, not a
            round-trip failure of anything that was read.
          So no parse is ever unwritable; only new content that the output set
          cannot spell is refused.
       7. **UTF-8 maps to code points, transparently.**  It is the default
          set; a file that never says `charset` reads and writes UTF-8 with no
          table; and a char is a code point at the grammar level in every set.

       The unit-width directive (`byte N`, `word N`) and `charset` go in one
       step, now that `units` is retired.

       **Stage 2, built 2026-10-17 (C):** a text rule may name a bit rule and a
       bit rule a text rule, read by one parser.  The bit rules are emitted
       "hosted" (HBNF_Wire.C.Emit_Hosted): over the text parser's `text`, `pos`
       and a new `bit` (the offset inside the octet at `pos`), its `fail` and its
       arena; the text emitter treats a bit rule's name as a defined rule with a
       type and a reader of the usual signature.  Text must start on an octet and
       says so when it does not.  A rule is a bit rule only if it holds a bit
       field itself; one that names a bit rule is a text rule.  Not yet: the
       writer, actions and emitters, the other backends, a bit rule holding a text
       rule by value.

       **`units` retired, 2026-10-18 (C).**  `name:bitsof(rule)` in a bit rule:
       the text rule is read as text, the **numbers** of the words in it (the enum
       rule it holds, found by the reader: `bip39-word`, `bech32-symbol`) are the
       bits the rest of the rule reads, W bits each (what the largest number
       needs), with `remaining` and `align` over them; the rule must use them all.
       Writing writes the fields as bits and spells them as words, joined by what
       the text rule puts between two.  It is the "slices of a text of numbered
       words" of this entry in sequential form: the rest of the rule reads the
       words' bits in order, where `foo@Off:Len` would address them by place.  The
       sequential form is what writing can invert (the word count follows from
       the fields); explicit slices would need the count solved for, and stay
       designed.  BIP-39 (eighteen phrases read, refused and generated) and the
       segwit data part run on it (`tests/wire/mnemonic`, `segwit`); a parse also
       needs the text rule as an alias root to run the actions (`doc = mnemonic`).
       Limits: C only (Rust refuses `bitsof` and `align`); the phrase's own tree
       is not kept; a `bitsof` is at the top of its rule, not in a choice, and not
       inside another.
       Stage 3 (built, C): a rule holding both kinds is split into hidden
       runs `<rule>_<n>`, one per run of bit fields or text (`tests/wire/mixed4`);
       a group holding both is refused.

       **Acceptance tests (the user's, 2026-10-17):** a BIP-39 mnemonic and a
       wallet address, each both parsed and generated.  A mnemonic is words
       whose 11-bit indices concatenate to entropy plus a SHA-256 checksum; a
       bech32 address (BIP-173) is 5-bit symbols from a 32-character set,
       regrouped to octets, with a BCH checksum.  Both need a text-to-bits
       bridge (a word list or a charset whose position is the value), the
       generating direction and a checksum, so they are the test that the three
       halves meet.

7c. **A writer for text grammars (the user, 2026-10-18: "general writer").**
    *C, first slice built 2026-10-18 (`--writer`, `tests/writer.sh`): every sample
    config of obconf and the seven daemon grammars parses, writes, re-parses to
    the same tree and writes the same text.  The user's framing: this is a
    demonstration that a consumer can make arbitrary output from the tree; the
    general product is an AST with useful walker functions (7d below).*  A parsed tree written back as text, so a mixed
    grammar can generate (a BIP-39 phrase from its entropy, a request from
    its fields), a program can edit and re-emit, and step 13a's pretty
    printer has its engine.  Contract (the user's choice): **canonical
    first, then lossless.**  `write (tree)` re-parses to the same tree and
    `write (parse (write (t)))` is the same text (idempotent); later, with
    spans (step 6b), `--preserve` keeps each node's gaps and comments and
    reproduces the input byte for byte.  Gate (the user's choice): for every
    input of every grammar the suites already parse -- parse, write, re-parse,
    compare trees, write again, compare text.  A grammar whose output does not
    re-parse is refused for writing with the rule and the text, never emitted
    as something close.

    **What the tree keeps today, and the gap.**  The tree is a struct of the
    named children (the union of all alternatives' members), a string for a
    token, a list node for a repetition.  It does not keep the literals (they
    are in the grammar), the blanks, whether an alternative was taken when its
    members are the same as another's (`a = b "x" / b "y"`), or which optional
    part was present when it has no member of its own.  Only a leading literal
    tags an alternative (`Leading_Tags`).  So a writer cannot recover every
    tree; the parser must keep what the grammar does not say.

    **Design.**
    1. *An opt-in `writer` directive (or `--writer`)* makes the generated
       parser record, for each alternation, the number of the alternative
       taken (`_alt`), and for each optional part, whether it was present
       (`_has_N`) -- only where the tree does not already say.  Without it the
       parser, the tree and every byte of generated output are unchanged (the
       byte-identity gate stays).
    2. *A generated `write_<rule>`* per rule, walking the tree by the same
       `Rule_Info` the walkers and free functions use (`Emit_Walk`,
       `Emit_Free`): a literal is written from the grammar, a token from its
       text, a repetition node by node with its separator, an alternation by
       its recorded number.  Blanks: `ws` is not remembered, so between two
       items the writer puts one space where the grammar has a `whitespace`
       rule and the previous character and the next would otherwise run
       together, and nothing where `whitespace none`.
    3. *The check is the gate, built in:* `write_checked` re-parses its own
       output and compares, so a grammar whose canonical text is not what it
       reads (a token that glues to the next, a blank that matters) says so
       in the test and, at run time, refuses.
    4. *Mixed grammars:* a text rule that holds a bit rule calls
       `emit_bits_<rule>` (built), and the octets are written as bytes; a
       bit rule that holds a text rule calls `write_<rule>` at whatever
       bit it is, the octets written shifted.  Numbered-word text (BIP-39, bech32) writes through the same
       path: a token's value is its spelling, so `bitsof` (built) needs only the
       spelling of each number.
    5. *Order of work:* `_alt`/`_has` recording and `write_` for sequences,
       literals, tokens, lists and optional parts; alternations; left-recursive
       lists (`sum = sum "+" n`); then `--writer` on obconf (it has a printer
       to compare with), then the suites' round trip, then mixed grammars.

    **A tree-sitter backend (the user, 2026-10-19, built).**  `--backend=tree-sitter` writes a
`grammar.js` (ABNF.md, *Backends*).  Prior art: BNFC has one (`Backend/TreeSitter.hs`, from
LBNF); kebnf converts KeBNF to tree-sitter; no ABNF or PEG tool does.  The difference to
mind is the one decision 14 is about: tree-sitter forks the LR stack at every conflict and
keeps both readings until one dies, choosing by `prec.dynamic` and error cost, with no
symbol table, so an ordered choice maps onto it only approximately (`--ts-ordered`) and a
lookahead or a context test not at all.

    **A layout hook (2026-10-19, built).**  The generated writer calls an optional
    `hbnf_write_layout (ctx, ev, s)`: with ev 0 and the text before each token or
    literal it writes, and it answers what goes before it (NULL: the writer's own
    blank); with ev 1 and 2 on entering and leaving each node, with the rule's name.
    A pretty-printer is then a policy of about 60 lines over the grammar
    (`corpus/algol60/pp.c`, `tests/algol60-pp.sh`), not a second copy of it.  The
    writer also writes nothing for a test or binding (`!x`, `&x`, `?`, `%bind`).

7d. **The AST and its walkers (the user, 2026-10-18).**  *Built in C 2026-10-18.*
    With `--ast` (default off, so the output of every existing grammar is
    byte for byte what it was): each node whose rule has alternatives records
    which one it took (`_alt`, a number from 1), the generated file has tables
    describing the tree (a row per member, per alternative, per rule) and one
    small shared walker over them: `node_walk (node, kind, fn, ctx)` calls
    `fn (node, kind, enter, ctx)` on entering and leaving each node and the
    callback answers WALK_CONTINUE, WALK_SKIP or WALK_STOP; only the members of
    the alternative a node took are walked.  `node_kind_name`, `node_alt` and
    `node_alt_name` name what a node is.  `--ast-tools` adds `node_kids` (the
    members of a node, leaves too), `node_dump` (an S-expression) and
    `node_equal`.  A grammar's own list container (listops) is read through two
    small functions per list rule.  The user's two constraints (2026-10-18):
    "how did we get here" is for error messages, not for a tree that has
    parsed, so no path is kept or passed; and a walker should add no more than
    about 2 KB, "very few things are deeply nested".  Measured: ntpd, the
    smallest daemon grammar, grows by 2.2 KB compiled with `--ast` (1.2 KB of
    code, 1 KB of tables); pfctl, with 126 node rules, 357 members and about
    700 alternatives, by 12 KB of code and 18 KB of tables, most of it the
    recording of alternatives.  `tests/ast.sh`.  Also built (2026-10-18, C):
    **`--spans`**: every node has `_pos` and `_end`, byte offsets of where it
    is in the text (after the blanks before it, up to the end of its last
    element), `node_span (node, kind, &start, &end)` and `node_where (text,
    pos, &line, &col)`; **`--parents`**: `_up` and `_upk` (the node that holds
    it and its rule), set by `node_link` (`link_<root>` for a list root) and
    read by `node_parent`; and **`%label name`** at the end of an alternative
    (LBNF's constructor, as a suffix, in the notation's own style), which
    `node_alt_name` returns instead of the derived name (`entry[assign]`,
    not `entry[set]`).  Both flags are opt-in; `tests/spans.sh`.  Not yet: spans in a
    `statements` parser (offsets are within the statement).  The writer is in Rust, Zig and Ada too
    (2026-10-22): `tests/writer.sh` round-trips the same corpora in all four (json, obconf, the daemon
    grammars, ALGOL 60 in Rust and Zig), each file written and read back to the same dump; what the
    other three cannot read is a grammar with a scanner written in C (a `jet`).  Back-references
    (`%as`/`%same`) and the lookaheads `!x` / `&x` are parsed in Rust, Zig and Ada too (2026-10-22;
    until then they were silently dropped, which made ALGOL 60 and Mustache parse wrongly there):
    Mustache round-trips in all four, ALGOL 60 in Rust and Zig.
    **2026-10-22: `--ast` in Rust, Zig and Ada** (`tests/ast.sh`, `tutorial/tools.*`): `Node` (a
    record or list element), `node_walk` (enter, leave, skip, stop), `node_kids`, `node_kind_name`,
    `node_alt`, `node_alt_name`, `node_dump` and `node_equal`, written as plain typed code per grammar
    rather than C's tables, and the dump is character for character what C writes (a rule with
    alternatives records `_alt` / `Alt_No`, as `--writer` does).  Spans and parents too (`--spans`, `--parents`: `_pos`/`_end` fields set by a wrapper round each
    rule's parser, `node_span`, `node_where`, and a `Parents` map built by `link_<root>` because a
    Rust or Ada tree cannot point at its parent), `tests/spans.sh`.  `%label` is in the dump's
    alternative names already.

7e. **Error paths (the user, 2026-10-18).**  *Built in C: `--paths`.*  An error
    message says which rules the parser was reading when it got as far as it did:
    `expected a number, found ; (in config > entry > block > entry > value)`.
    The path is for errors only; a tree that has parsed keeps none.  The parser
    keeps a small stack (24 deep, a rule number each) and copies it when it records
    the farthest failure; each rule's parser is wrapped to push and pop.  A rule the
    reader made up for a group or an option is left out of the path.  Opt-in so far
    (`tests/paths.sh`): without it the output is byte for byte what it was.  To
    measure before it is made the default: the wrapper costs a call and two stores
    per rule read, and about 12% of source on pfctl.

   **Error messages that name every way on (2026-10-21, C; `tests/errors.sh`).**  An error used to
   name only the first thing tried at the farthest place (`expected `{`, found ,` for a missing
   value).  It now names every one of them there (`expected one of `{`, `[`, string, number, ...`),
   and a failure in something that took more than a couple of lines (at the end of the input, one
   line; else three) also says where the innermost enclosing rule began, with its line: the
   `'BEGIN'` with no `'END'`.  The rule stack with start positions is kept always (it was
   `--paths` only); `--paths` still adds the `(in a > b)` path.  Built in all four backends
   (2026-10-22), and every message now begins `LINE:COLUMN:OFFSET:` (offset in bytes from 0; in a
   `statements` parser, from the statement's start), which `sed`, `tail -c` and editors take as it is;
   a conf reader prints `file:LINE:COLUMN:OFFSET: ...`.  Not yet: an end point for a construct that
   closed too early.

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

       **Known gaps, none blocking.**  Zig's tree does not own its strings:
       a quoted string's text is its own allocation that nothing frees, and
       `parse_config` never frees the file text the other strings slice.
       Fixing that means the tree owning its strings, which belongs with
       step 6's typed semantic values, not here.

       **Found and fixed on the way.**  C's backtracking reset freed a failed
       branch's fields but zeroed the *next* branch's, so a field only the
       failed branch set read as set in the branch that matched (and a later
       reset could free it twice); it now zeroes the failed branch's, and a
       freed back-edge pointer is nulled.  Ada's `recursive-via-list` output
       did not compile (a vector of vectors needs the element vector's `=`
       in scope) and its `Free_` skipped lists of group entries and lists of
       lists, leaking their access nodes; both fixed, and
       `tests/recursive.sh` builds the fixture under AddressSanitizer.

   Gate: the four backends accept or refuse the same schemas, the
   expression grammar above compiles and parses in all four, and the nine
   daemon grammars stay byte-identical (none of them recurses, so nothing
   should move).

   This is what an earlier review meant by "not general enough for a real
   language".  It is narrower than it sounded — one mechanism, in the type
   emitter — and it is *not* the typedef problem, which is separate and
   discussed under decision 13.

   9c. **Retire the interpreter.**  *Done 2026-10-06.*  There is no reason
       to keep it, and the reason it existed is 9b.

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

       **What landed.**  The plan's replacement for `HBNF_Config` is a parser
       generated from `hbnf_schema.hbnf`, but the Ada backend that would have
       generated it still read tokens: the character model existed in C only,
       and was step 5's second bullet, *after* this step.  So this step took
       it in, rather than retiring a conformant reader for a lenient one (the
       Rust parser accepted an unterminated string):

       - **The character model in Ada, Rust and Zig**, the shape C already
         had: no token array, a parser that reads the text at a position, the
         grammar's `ws` skipped between phrase elements, a letter-led literal
         matched by the `word` scanner so `in` never matches `input`.  `word`,
         `int`, `str` and `ws` are the grammar's own char rules or a built-in
         scanner.  A `%scan{}` scanner action is C code, so the other three get a stub
         that matches nothing (and the daemons' Ada, Rust and Zig output now
         shows it: it still compiles, and no longer parses what its scanner actions did).
       - **`hbnf_schema.hbnf` rewritten** on `grammars/obconf.hbnf`.  `ws`
         excludes the newline, which is how a statement ends at its line
         without C's `statements`.  `tests/schema.sh` runs `tests/accept` and
         `tests/reject` through all four backends, and prints and re-parses
         every accepted file in Ada to a fixed point.  One reject file cannot
         be expressed: `x 1e40`, refused by the old reader's fixed-point
         `Decimal`, a value range a grammar does not have.
       - **Two backend bugs the work found**: a repeated rule that can match
         nothing hung in every backend (decision 9's invariant, which only the
         interpreter had tested), and `*X` in a phrase rule failed in C when
         there was no `X`.  Both fixed, with `Repeated_Body_Nullable` in
         `HBNF_Compilable` and tests in `tests/schema.sh` and `abnf.sh`.
       - **Retired**: `HBNF_Match`, `HBNF_Config`, `tests/hbnf_check.adb` and
         `tests/hbnf_match_check.adb`.  The library project is now
         `libhbnf.gpr` (project `Libhbnf`, still `libhbnf.a`), which the `hbnf`
         command line wraps; the aport builds `-P libhbnf.gpr`.

       **What was given up**, said plainly: `HBNF_Config` was a documented
       Ada API (`Parse`, `Find`, `Value_At`, `As_Decimal`, `Print`).  A
       generated parser has a typed tree instead, no fixed-point `Decimal`,
       and the old printer's comment-preserving round trip, which comes back
       with step 13's printer.  The e2e count is 104 (it was 99).

       *Still open here*: the tree does not own its strings in Zig, which is
       step 6's typed values; and the gate's "`hbnf_schema.hbnf` generates
       through all four backends" is stronger than asked, since all four also
       parse the conformance files.

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
   `scanner.c` where a scanner action is needed) from the lifted schema, so one
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
   - **Scanner actions** become `externals:` plus a `scanner.c`.  The emitter can stub
     the scanner with the scanner action's own code where the scanner action is already C, and
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
     signature/body emission.  A scanner action rule also has an empty pattern but does
     read `p`, so the parameter renaming tests *empty pattern and no scanner action*.

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

   There is prior art one layer down, and 9c did not throw it away:
   `tests/hbnf_check.adb` was a conformance driver whose "accept" required
   exactly this — parse, print, re-parse, re-print, and the printer must be
   idempotent — for the *config format*, against `HBNF_Config`'s printer.
   9c rebuilt that driver against generated code
   (`tests/schema/print_main.adb`, run by `tests/schema.sh`); this step is the
   same discipline applied to the notation.  The old printer also kept
   comments, which the generated tree does not yet: that is this step's.

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
     `n*m` has no yacc spelling, a scanner action has no spelling anywhere.  The
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
   scanner actions/`%scan`, and emit a direct string reader otherwise.
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
- Full GLR (decision 14 is the local, detected fork instead).
- Case-folding non-ASCII rule names.
- Guessing any setting from an include or from seeing `%x`.

<!-- {% endraw %} -->
