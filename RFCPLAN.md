# One notation for daemon configs and RFC grammars — the plan (working note)

Agreed 2026-09-28.  The goal: paste RFC 5234-family ABNF and get a
working parser, and make the nine daemon grammars smaller, clearer and more
coherent on the way.  There is one parsing model, not two profiles, and the
generated parsers stay recursive descent, linear in their input, with no
packrat table and no unbounded backtracking.

Where the tree stands, and what this plan builds on: CHARLAYER.md (numeric
terminals, `'c'` literals, `ascii.hbnf`, UTF-8 scanners in all four
backends).  Where the notation differs from ABNF today: ABNF.md §4.

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
     as character rules anyone can read and change.  `wordchars` goes away.
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
10. **Core rules.**  `WSP = SP | HTAB` joins `ascii.hbnf` (one code point).
    `CRLF = CR LF` goes in a new `core.hbnf`, which includes `ascii.hbnf`:
    RFC 5234 Appendix B.1 in one include.  `LWSP` waits for repetition
    inside character rules, which `Is_Char_Rule` refuses today.

## Order

Each step leaves the nine daemon grammars, e2e, byteident (ntpd) and
unwind-ident passing; each lands as reviewed patches.

0. **Docs and comments that disagree with the code**; include once; the
   two kinds of directive; a later `=` overrides.  *Done 2026-09-28.*  An
   include goes before the file's first rule (so "later" is always
   textual), and a schema error names its file.
1. **Reading grammars** (no backend work):
   - `=/`; `sensitivity`; `/` between character ranges;
   - `%d13.10`, `*m` (`*2DIGIT`), continuation by indentation (ABNF's
     `c-wsp`), newlines inside `( )` and `[ ]`;
   - `<prose-val>`; `WSP`, `CRLF` and `core.hbnf`.

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
   every schema through every backend.
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

   4b. **Lexer as grammar.** The old lexer's `word`, `number`, quoted
       strings with escapes, `#` comments and backslash continuation become
       char rules in a shared include; `wordchars` goes away.  Keywords stay
       a table (a listed word does not match `word`).

   4c. **Character-model parser in C.** `parser_t` becomes text/len/pos
       (no pre-cut token array); a literal compares bytes at the position, a
       char-rule reference runs its scanner there, and `whitespace ws` makes
       phrase-level rules skip `ws` between elements (character rules never
       do).  Keywords still branch on the first byte.  The §6 memoization
       comes later, only if the numbers regress.

   4d. **Convert ntpd first**, then the other eight daemons; jets become
       character rules where they can.

   4e. **Re-measure §6** (57 ms for the 100,000-rule toy, ~0.5 s for 100,000
       pfctl rules) and hold it.
5. **`/` between phrases** (decision 1; factoring needs step 2).  Then:
   - RFC excerpts as regression tests: RFC 5234 Appendix B.1 verbatim, RFC
     3986 `scheme` and `host`, RFC 5322 `addr-spec`, RFC 9112
     `request-line`;
   - the character model in Rust, Zig and Ada through the templates, and
     the interpreter (HBNF_Match) on the same rewrites;
   - `json.hbnf`, `where`, then binary (CHARLAYER.md I2–I4).

## Not in this plan

- HTTP's and RFC 822's `#` list operator, RBNF.
- Packrat, GLR, or trying another alternative after a later failure.
- Case-folding non-ASCII rule names.
- Guessing any setting from an include or from seeing `%x`.
