# HBNF: decisions and status

## About this ledger

- What it is: for each design and implementation choice the author made about hbnf over time, where it stands now against the current docs and code: what is done, what is left to do, what was rejected, and what is left in the air.
- Precedence (the author's rule): more recent decisions have greater precedence; each subject's status follows its latest standing line.
- Each subject: `Status`, `Decided` (the latest standing line with its source `[thread#message]`), `Evidence` (file, line, quote or commit) or `not found: searched ...`, `Doc differs` where a doc or code says something else, `Left` for what remains.
- Checked, not guessed: a status of DONE needs evidence; what could not be checked is IN THE AIR and says why.
- `Rationale` is why he chose it, in his own words; `Precedent` is a system, language, standard or design named as a referent, with whether his choice follows it (chosen), he turned it down (rejected) or it was only compared (considered), and who named it (the author, or the assistant and he accepted it or did not take it up). Only what the messages say: nothing is added from outside. The precedents are indexed by name near the end.
- The chains behind it are in the decision log of the same project; the evidence is as of the repositories read on 2026-11-10.

## Contents

- [Summary](#summary)
- [Left to do (38)](#left-to-do-38)
- [Left in the air (59)](#left-in-the-air-59)
- [Rejected or replaced (5)](#rejected-or-replaced-5)
- [Done (176)](#done-176)
- [Precedents, by name](#precedents-by-name)
- [Where the current docs or code differ from the decisions (62)](#where-the-current-docs-or-code-differ-from-the-decisions-62)
- [Decision briefing: open notation questions](#decision-briefing-open-notation-questions)
- [Briefing E: hbnf, items Q18 to Q21](#briefing-e-hbnf-items-q18-to-q21)
- [Q18 Namespaces and qualified names (REVIEW)](#q18-namespaces-and-qualified-names-review)
- [Q19 Slice syntax (REVIEW)](#q19-slice-syntax-review)
- [Q20 Library headers (REVIEW)](#q20-library-headers-review)
- [Q21 The C standard (REVIEW)](#q21-the-c-standard-review)

# Summary

- Left to do: 38 of 278 subjects
- Left in the air: 59 of 278 subjects
- Rejected or replaced: 5 of 278 subjects
- Done: 176 of 278 subjects

# Left to do (38)

- Decided, and not yet in the current code or docs (or only partly).

## Other

### Attic
- Status: TO DO — .txt files and tarballs are still loose; no Attic in the repository (latest decision 2026-09-29 \[silentpc:c14a13ff:431#1\])
- Decided: 2026-09-29 decided: "clean up the tarballs but the .txt files should all go in an Attic" \[silentpc:c14a13ff:431#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: git ls-files has no Attic directory; TODO.md section 6 lists "hbnf-\*.tar.gz files and hbnf15.txt untracked" in the repository root
- Evidence: uncommitted (silentpc): hbnf15.txt, 9 hbnf-\*-2026-10-0N.tar.gz, hbnf.old, 13 core.\* files, HISTORY.draft.md still loose in the repository root (copy of 2026-11-09), and no Attic directory; the packaging repo .gitignore lists Attic/ for ada-on-alpine only
- Left: move the .txt files to an Attic and delete the tarballs (on his machine; the clone cannot show it)

### Documentation style and upkeep
- Status: TO DO — README and doc files are not all current (latest decision 2026-10-31 \[silentpc-opusplan:4a4c3021:j80540#1\])
- Decided: 2026-10-31 decided: "fix all the readme and doc files make them perfectly up to date". \[silentpc-opusplan:4a4c3021:j80540#1\]
- Rationale: "always update the docs as you go" \[silentpc-opusplan:4a4c3021:5279\]
- Rationale: "fix all the readme and doc files make them perfectly up to date" \[silentpc-opusplan:4a4c3021:j80540\]
- Rationale: "none of that self-referential ai slop" \[silentpc:c14a13ff:21297\]
- Rationale: "deslop the readme. no mdash" \[silentpc:c14a13ff:j8228\]
- Evidence: TODO.md section 5: "README, WHY.md, HISTORY.md benchmark blocks ... should be re-read against the new numbers"; "HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md (untracked): fold into HISTORY.md or delete"; bench/tokens.sh broken, so the token figures are the 10-27 ones; README Status line is dated "31 October 2026" while the bench note is 2026-11-05; README.md:54 still says "the daemons it was written for"
- Evidence: uncommitted (silentpc): HISTORY.draft.md (1702 lines, 2026-10-01), RESUME-9b.md and RESUME-9c.md (header "done, committed and pushed (historical)") are still untracked and not folded or deleted
- Left: re-read the prose against the 11-05 numbers; fix tokens.sh; README Contributing out/in out wording

### Working rules and workflow
- Status: TO DO — fourteen finished agents' worktrees are still on silentpc (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j89400#1\])
- Decided: 2026-11-03 decided: "and remove the finished agents work trees" \[silentpc-opusplan:4a4c3021:j89400#1\]
- Rationale: "stop rewriting shit and just fix what isn't implemented. don't work around absent features" \[silentpc-opusplan:4a4c3021:j11067\]
- Rationale: "why are you doing the fixes on a branch? merge them and push them" \[hist-silentpc:fd13bc5f:h302\]
- Rationale: modify stock BNF "as little as possible ... as long as it feel natural, and is not shocking or supringing to a human" \[silentpc-opusplan:4a4c3021:83530\]
- Precedent: stock BNF (chosen; named by author): extend with minimal change for context switching \[silentpc-opusplan:4a4c3021:83530\]
- Precedent: COBOL embedded JCL, SQL, CICS, PICTURE (considered; named by author): motivates a syntax for switching context \[silentpc-opusplan:4a4c3021:83530\]
- Evidence: not checked: a fresh clone has one worktree (git worktree list shows only main); TODO.md section 1 says the paused speed agent's worktree .claude/worktrees/agent-a62ce11167790e13f is intact (paused, not finished)
- Evidence: uncommitted (silentpc): .claude/worktrees/ holds 15 agent-\* directories (594 MB per TODO.md:121); only agent-a62ce11167790e13f is the paused one (TODO.md:9)
- Left: remove the 14 finished worktrees

## 01 Goals and priorities

### Feature bundle
- Status: TO DO — macros, include and statements are built (C only); the HBNF\_LIST\_\* defines were not found (latest decision 2026-09-22 \[578:4#1\])
- Decided: 2026-09-22 decided: Implement the #5 bundle (macros, include, httpd braced blocks, scalar cycle, libc typedef clashes, HBNF\_LIST\_\* defines) "while keeping cpu and memory usage minimal" \[578:4#1\]
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:347 "\`statements\`, \`macros \<rule\>\`, \`includes \<rule\>\` ... C only"; ABNF.md:342 "\`include\` is relative to the including file", \`prefix "pf\_"\`; not found: searched ABNF.md, grammars/README.md, hbnf\_c.adb, templates for "HBNF\_LIST" (only \`List\_Override\` in hbnf\_c.adb:212-234) \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): not found in any of them: HBNF\_LIST (snapshot RFCPLAN.md only has the \`listops\` directive); packaging repo: testing/hbnf/APKBUILD pins 0.7.0\_git20261022, older than the bundle work
- Left: HBNF\_LIST\_\* defines not found under that name; scalar cycle and libc typedef clashes not separately verified; macros/statements warn and are ignored in the other backends

### Priority list
- Status: TO DO — the deferrals are recorded, but the queue of older fixes is still open (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:61606#1\])
- Decided: 2026-10-27 decided: Fix hidden and unfinished things; leave c17 and c23, the 4-backend benchmark, and error recovery for later; bench only glibc/amd64 and C; do older queue items, "no new work till those are satisfactory". \[silentpc-opusplan:4a4c3021:61606#1\]
- Rationale: "no new work till those are satisfactory"; "i want proper benchmakr results, i want to see if we can beat the json/yaml/toml resuilts" \[silentpc-opusplan:4a4c3021:61606\]
- Rationale: "leave error recovery for after the speedup and benching is done" \[silentpc-opusplan:4a4c3021:61606\]
- Precedent: Common Lisp restart (considered; named by author): "only for you to think about then make recommendtions" \[silentpc-opusplan:4a4c3021:61606\]
- Precedent: JSON/TOML/YAML libraries (considered; named by author): to beat in proper benchmarks \[silentpc-opusplan:4a4c3021:61606\]
- Precedent: tree-sitter (chosen; named by author): done first, then the Zig emitter \[silentpc-opusplan:4a4c3021:31435\]
- Evidence: README.md:19-23 "Next: ... C17 and C23 ... error recovery ... benchmark of the four backends" (kept as later); commits e837fbf "bench: every table of the C parsers measured again, on glibc"; commit e5a464e hidden token; TODO.md:56-84 (queue of CONTEXTS items 1-63 and open decisions) \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence; the untracked handoffs RESUME-9b/9c are dated 2026-10-05/06, before this decision
- Left: TODO.md section 3 queued reader and generator fixes (items 1-63) and section 2 XML items are unchecked boxes; Prio/Note lines empty

## 02 Notation and grammar design

### Ascii hbnf
- Status: TO DO — CRLF and WSP exist (in common.hbnf); LWSP is missing (latest decision 2026-09-28 \[704:4#2\])
- Decided: 2026-09-28 decided: "ascii.hbnf should definitely have CRLF, WSP and LWSP" \[704:4#2\]
- Rationale: "those can be implemented in an ascii.hbnf very simply without touching the ada code" \[silentpc:6ec412b3:j32451\]
- Precedent: ABNF (chosen; named by author): "ascii.hbnf should definitely have CRLF, WSP and LWSP" \[704:4\]
- Evidence: grammars/common.hbnf:22-24 \`WSP = SP \| HTAB\`, \`CRLF = CR LF\`; grammars/ascii.hbnf has the named characters; ABNF.md:196 "\`LWSP\` ... Not yet: a character rule cannot repeat"; not found: LWSP in any grammars/\*.hbnf \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): LWSP absent from grammars/ at HEAD; uncommitted (silentpc) snapshot RFCPLAN.md:126 says "\`LWSP\` waits for repetition" (2026-10-03), same state
- Doc differs: RFCPLAN.md:178 puts the classes in common.hbnf, ascii.hbnf only the named characters (as the 2026-10-02 file split decided)
- Left: define LWSP (corpus/rfc/rfc5234-1.hbnf:42 has its own copy); ABNF.md:196 "character rule cannot repeat" may be stale since \`\*~LF\` is accepted in rules of characters

### Column access
- Status: TO DO — \`col\` is only proposed, 0-based and \`where (cond)\` unconfirmed, nothing built (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j87250#1\])
- Decided: 2026-11-03 decided: "a rule should be able to access its col value" \[silentpc-opusplan:4a4c3021:j87250#1\]
- Rationale and precedent: none stated in the sources
- Evidence: CONTEXTS.md:20 "\`col\` and \`where (cond)\`; \`30WS\` ... \*\*proposed\*\* ... to be confirmed"; TODO.md:78; \`%col\` exists only as the old frame-of-numbers form (ABNF.md:106) ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: confirm the spelling and build \`col\`; fixed-format COBOL waits on it (CONTEXTS.md:21)

### Core number types
- Status: TO DO — number terminals are in the reader, but no C-number rules were put in the shared grammars (latest decision 2026-09-30 \[silentpc:c14a13ff:3298#1\])
- Decided: 2026-09-30 decided: "not lexer change; just grammar rules on core.hbnf and jets" \[silentpc:c14a13ff:3298#1\]
- Rationale: "since our core includes all the whitespace classes, the control characters, etc, why not the number types? all the c representations" \[silentpc:c14a13ff:3180\]
- Rationale: "not lexer change; just grammar rules on core.hbnf and jets" \[silentpc:c14a13ff:3298\]
- Precedent: C numbers (chosen; named by author): as core number types \[silentpc:c14a13ff:3180\]
- Evidence: grammars/common.hbnf has only the RFC 5234 classes; grammars/obconf.hbnf:36 \`int = 1\*DIGIT \| "-" 1\*DIGIT\`; ABNF.md:178 \`0x41\`, \`0b1000001\` are reader notation for code points, not number token rules \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: rules for 0x, 0b, 0o, 0 and \\0 style C numbers in common.hbnf; per-language versions exist only in corpus/c

### Example rules
- Status: TO DO — floating point and an inline money example exist, a shipped money rule and UTF-16 input were not found (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h194#1\])
- Decided: 2026-09-21 decided: wants example rules for money (2 digit decimal), floating point etc.; accept astbnf in utf8 and utf16 form, output utf8 \[hist-silentpc:fd13bc5f:h194#1\]
- Rationale: example rules for money and floating point "so people see how it can be used" \[hist-silentpc:fd13bc5f:h194\]
- Precedent: ABNF (chosen; named by author): to confirm it sweetly represents these character sequences \[hist-silentpc:fd13bc5f:h194\]
- Evidence: not found: grep "money" over \*.md and \*.hbnf found USENIXSUBMISSION.md (the first pass missed ABNF.md:127); CHARLAYER.md:8 and :17 "UTF-16 ... not built"; floats appear in corpus/json, toml, c grammars \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): ABNF.md:127 does show \`money = 1\*DIGIT "." 2DIGIT\` as an inline character-rule example (committed, missed by the first pass), but no shipped example grammar file has it; UTF-16 still not built, no astbnf in any source
- Left: a shipped money (2-digit decimal) example rule beyond the inline ABNF.md:127 example; UTF-16 input (astbnf itself is absent)

### Facts stored by matched rules
- Status: TO DO — decided yes, nothing built (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:84907#2\])
- Decided: 2026-11-03 decided: Q9: "yes to facts". \[silentpc-opusplan:4a4c3021:84907#2\]
- Rationale: "such as the typedef thing in C. and I'm sure it will have a lot of use in COBOL." \[silentpc-opusplan:4a4c3021:84030\]
- Precedent: C typedef (considered; named by author): example of a fact stored by a matched rule \[silentpc-opusplan:4a4c3021:84030\]
- Precedent: COBOL (considered; named by author): expected to use facts heavily \[silentpc-opusplan:4a4c3021:84030\]
- Evidence: CONTEXTS.md:17 "Facts ... \*\*decided yes\*\*; nothing built"; TODO.md:77 "Facts ... decided yes, nothing built (13)" ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: design the syntax and build facts keyed by name

### Grammar for HBNF itself
- Status: TO DO — planned as step 13a, not built (latest decision 2026-10-02 \[578:136#3\])
- Decided: 2026-10-02 decided: Final step: a grammar for hbnf itself plus round trip pretty printer preserving comments, normalizing to = rules and ; comments unless passed "--preserve"; output in various historical styles \[578:136#3\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:2427 "13a. A grammar for the notation, and a round-trip pretty printer ... call it \`hbnf.hbnf\`"; not found: hbnf.hbnf (find over the repository), "--preserve" in hbnf.adb \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no hbnf.hbnf in HEAD or in any snapshot tarball (only plan text); \`--preserve\` not found in hbnf.adb
- Left: write hbnf.hbnf, the \`--preserve\` printer and the historical styles; hbnf\_schema.hbnf is a different grammar (the config format)

### HTML islands
- Status: TO DO — a variant \`html-islands.hbnf\` reads \`\<script\>\` with a stub JS grammar; CSS and the real js grammar are not wired in, island items open (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j91739#1\])
- Decided: 2026-11-03 decided: "js and css should be in their own grammar files" \[silentpc-opusplan:4a4c3021:j91739#1\]
- Rationale and precedent: none stated in the sources
- Evidence: corpus/html/html-islands.hbnf:6 \`include "js-stub.hbnf" as js\`; corpus/js/ and corpus/css/ exist as separate grammars; TODO.md:97 "JS and CSS as islands (CONTEXTS 27); the island 26/27, 30, 31 items"; CONTEXTS.md:952 item 31 \`=\> grammar(js)\` after \`\<script\>\` generates nothing ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: islands in html for the full js and css grammars (items 27, 30, 31)

### Hyper rules and meta rules
- Status: TO DO — frame (unbounded) and expanded forms both exist, but no benchmark confirming the choice was found (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j55276#1\])
- Decided: 2026-10-24 decided: "bench it though, confirm". \[silentpc-opusplan:4a4c3021:j55276#1\]
- Rationale: "well shit, unbounded is faster? do that even for bounded!" \[silentpc-opusplan:4a4c3021:55264\]
- Rationale: "i'm ok with mixing every kind in a single rule (unless you show some theoretical reason why that is wrong)" \[silentpc-opusplan:4a4c3021:55210\]
- Rationale: "bench it though, confirm" \[silentpc-opusplan:4a4c3021:j55276\]
- Precedent: ::= := = and : (considered; named by author): "we have precedent"; which marks hyper-rule and meta-rule \[644:77\]
- Precedent: CDL (considered; named by author): named in the grammar lineage \[594:6\]
- Precedent: DCG (considered; named by author): named in the grammar lineage \[594:6\]
- Precedent: PEG / ANTLR (considered; named by author): asked whether ANTLR is PEG \[594:6\]
- Evidence: ABNF.md:106 "\*\*expanded\*\* ... or \*\*run\*\* ... numbers are expanded when they form a small table (up to 16 values ...) and run otherwise; \`--expand-params\` and \`--run-params\` choose"; not found: a benchmark of run against expand in bench/ or bench/results \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): tests/params-modes.sh (committed) checks that --expand-params and --run-params accept and refuse the same texts; it is a correctness test, not a timing benchmark, so the confirming bench is still not found
- Left: bench expanded against run for bounded domains and set the rule from it; open potentials (\`\$\`, toml/yaml use of w-grammar, cdl/dcg, C++ overloading) are undecided

### Keywords without % and fewer sigils
- Status: TO DO — numbers and strings lost their \`%\` (8328962) but the reserved-word spellings (\`%label\`, \`%num\`, \`%action\`...) are open and unbuilt (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j87090#1\])
- Decided: 2026-11-03 decided: Dislikes % noise "especially for keywords". \[silentpc-opusplan:4a4c3021:j87090#1\]
- Rationale: "I'm tired of % for keywords; we already have \\"\\" and '' literals, we can have keywords in hyperbnf too without the % as long as it looks natural to read." \[silentpc-opusplan:4a4c3021:j83799\]
- Rationale: "the less we need to use % @ and \$ in our grammars the better" \[silentpc-opusplan:4a4c3021:81831\]
- Evidence: CONTEXTS.md:15 "decided as to reserved words; the spellings of \`%label\`, \`%num\`, \`%action\` and the rest are \*\*open\*\*; nothing built"; TODO.md:70 same; ABNF.md:123 still shows \`%label\` ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: choose and build the spellings of the remaining \`%\` words

### Scan and action blocks, predicates and terminology
- Status: TO DO — the family exists, but "jets" is still in the docs and in code names (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:j19397#1\])
- Decided: 2026-10-18 decided: "remove 'jets' from the docs, from now on there are only 'actions'" plus ad hoc terminology. \[silentpc-opusplan:4a4c3021:j19397#1\]
- Rationale: "almost all %scan{} and %action {} blocks should be a single function call or simple expression. keeps the grammar readable to humans" \[578:83\]
- Precedent: angle-bracket \<\> terminals (BNF, RFC 822 uses) (considered; named by assistant, accepted): he builds on \<\> as terminal naming a scanner function \[silentpc-opusplan:4a4c3021:4752\]
- Evidence: RFCPLAN.md:129 (decision 8) "one family of three" \`%scan{}\` \`%action{}\` \`%emit{}\`; ABNF.md:183 \`%scan{ … }\`, \`%action{ … }\`; README.md, WHY.md, HISTORY.md, TUTORIAL.md, ABNF.md have no "jet" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): the committed docs still carry the three \`jet\` mentions (METACOMPILERS.md:268, RFCPLAN.md:1787, :2750); uncommitted (silentpc): RESUME-9b.md:119 and RESUME-9c.md:15 still say jet/jets (2026-10-05/06, before the 2026-10-18 decision)
- Doc differs: RFCPLAN.md:1787 "a scanner written in C (a \`jet\`)"; RFCPLAN.md:2750 "jet or a scanner action"; METACOMPILERS.md:268 "a scanner jet that replaces a page of rules"; templates/c\_rule\_jet.tmpl and "jet" in hbnf\_c.adb are code names
- Left: remove the three remaining doc mentions (and decide whether to rename the code); open potentials (\`%where\` predicates, \`\<foo\>\` terminals, \`%scope\`) are not decided

### Up-references and rewrite rules
- Status: TO DO — up references are built, silent variants and rewrite rules are not built or benched (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:95293#1\])
- Decided: 2026-11-04 decided: "we won't know until we implement and bench. which we will do. no stone unturned. readable AND fast." \[silentpc-opusplan:4a4c3021:95293#1\]
- Rationale: "we won't know until we implement and bench. which we will do. no stone unturned. readable AND fast." \[silentpc-opusplan:4a4c3021:95293\]
- Evidence: a4f96d9 "Up references \`\$K^\` and \`\$K^R\`"; ABNF.md:122 (up reference); TODO.md:55 "Silent variants and rewrite rules (CONTEXTS 26/64): build them and bench them on the XML grammar"; CONTEXTS.md section 25 "a proposal ... nothing built" ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: build silent variants and rewrite rules, bench on the XML grammar (TODO.md section 7 question 4 asks the order)

### Word boundary with string literals
- Status: TO DO — the boundary defect under \`sensitivity string %i\` is recorded as a known reader/generator defect, not fixed (latest decision 2026-10-21 \[1889:1796#1\])
- Decided: 2026-10-21 decided: hbnf word-boundary problem is "insane, it should work with string literals too! fix hbnf". \[1889:1796#1\]
- Rationale: "that's insane, it should work with string literals too! fix hbnf" \[1889:1796\]
- Evidence: CONTEXTS.md:990 "Under \`sensitivity string %i\` keywords have no word boundary ... so \`ID\` matched the front of \`IDREF\`"; CONTEXTS.md:930 item 13 (\`word\` renamed, boundary breaks); TODO.md:64 lists items 13,14,15 as queued ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: fix items 13 and 34 of CONTEXTS.md section 26 so a string literal gets a word boundary without naming \`word\`/\`keywords\`

## 03 Parser generation and back ends

### Back ends: Zig, Rust and Ada ports
- Status: TO DO — walker, dump, writer, spans/parents were ported, but the Ada "status return" rewrite is not found (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:46422#1\])
- Decided: 2026-10-23 approved-proposal: do the Ada "status return" rewrite first \[silentpc-opusplan:4a4c3021:46422#1\]
- Rationale: Port the walker, dump and pretty printer "so people can see how it is done" \[silentpc-opusplan:4a4c3021:j39901\]
- Evidence: not found: searched README.md, TUTORIAL.md, RFCPLAN.md, hbnf\_ada.adb for a status-return API; templates/ada\_parser\_spec.tmpl:9 still declares \`Parse\_Error : exception;\` and TUTORIAL.md:158 handles \`when E : Parse\_Error\`; ports present: commit 4a20c92 "Writer layout hook in Zig, Rust and Ada", tests/spans/main.{adb,rs,zig} ; recheck: packaging repo: the hbnf aport check() builds only C and Ada backends (SCHEMA\_BACKENDS="c ada") and has no status-return test; uncommitted (silentpc): RESUME-9b.md shows the free walk in all four backends but no Ada status-return rewrite
- Left: the Ada status-return (non-exception) rewrite

### Build order of the context work
- Status: TO DO — stage 1 islands and stage 2 \`=\> grammar(x)\` are partly built; condensing the C and COBOL grammars and finishing COBOL are not (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:85635#1\])
- Decided: 2026-11-03 decided: Continue the context work "so we can finish cobol and reduce the c and cobol grammars". \[silentpc-opusplan:4a4c3021:85635#1\]
- Rationale: Continue the context work "so we can finish cobol and reduce the c and cobol grammars" \[silentpc-opusplan:4a4c3021:85635\]
- Rationale: "when stage 1 is done, do stage 2; then use it to condense the c and cobol grammars" \[silentpc-opusplan:4a4c3021:85082\]
- Evidence: CONTEXTS.md:624 "Order of work (the user, 2026-11-02). Stage 1: islands ... Stage 2: \`=\> grammar(x)\` ... Then use both to condense the C and COBOL grammars"; TODO.md:3 items 27, 30, 31 (islands) and "\`=\>\` as the one arrow ... nothing built"; TODO.md section 4 "COBOL ... 5 gaps in the scan suite against cobc, 1 in NIST" ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: islands items 27/30/31, \`=\>\` arrow, switch phases 2 and 3, tree-sitter external scanner for switches, COBOL gaps, then the condensed C and COBOL grammars

### C++ compatibility
- Status: TO DO — the C output is meant to be C++-clean, but the C++ grammar and the lessons for parsing C++ are not started (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:19019#1\])
- Decided: 2026-10-18 decided: Wants lessons from hbnf15.txt that "benefit the goal of making hbnf suitable to use to efficiently parse C++ into an ast". \[silentpc-opusplan:4a4c3021:19019#1\]
- Rationale: "the C backend will always emit code in a form that C++ can use directly without modification or shim" \[silentpc:c14a13ff:j4680\]
- Rationale: "make the C output C++-clean; we used to but at some point I think you removed it, without me ever telling you to" \[silentpc:c14a13ff:4699\]
- Rationale: Wants lessons that "benefit the goal of making hbnf suitable to use to efficiently parse C++ into an ast" \[silentpc-opusplan:4a4c3021:19019\]
- Precedent: GLR (considered; named by author): "I'm ok with glr" as a way to add context for parsing C++ \[646:16\]
- Precedent: symbol table lookups (considered; named by author): "I'm ok with symbol table lookups" for C++ context \[646:16\]
- Evidence: RFCPLAN.md:2123 "The C backend stays C99 and C++-clean"; TODO.md:104 "ALGOL 68, C++ grammars: not started"; README.md:21 "grammars for ... C++ (full GLR where they need it)"; not found: a g++ compile test of generated C in tests/ (g++ only in tests/e2e.sh header) ; recheck: uncommitted (silentpc): hbnf15.txt:573-893 is the 2026-10-18 C++ discussion (symbol-table lookups, local fork instead of global GLR, \`--forks\`) that the decision cites, but it records no C++ grammar or g++ compile test; packaging repo: no g++ check of generated C in the hbnf aport check()
- Left: the C++ grammar, GLR, typedef context; a test that the C output compiles as C++

### Emitters
- Status: TO DO — the standing rule is C first then port, and a long list of C-only features is still unported (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h249#1\])
- Decided: 2026-09-22 decided: "yes of course port the C corrections to the other languages" \[hist-silentpc:fd13bc5f:h249#1\]
- Rationale and precedent: none stated in the sources
- Evidence: TODO.md:89 "Port the C-only features to Rust, Zig, Ada, tree-sitter: \`as K\`/\`\$K\`, up references, \`^.rule\`, \`bol\`/\`eol\`, the scanned lookahead, overlay, unwind marks, the arena, the tape captures, the SSE2 loop, the context-set hash"; TODO.md:41 Rust and Zig emit \`compile\_error!\` on the XML grammar ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: the unported C features listed in TODO.md section 3; recursion handling in Rust/Zig for the conforming XML grammar

### Error messages
- Status: TO DO — line, column and offset in every message are built, but the end point of a long construct is not (latest decision 2026-10-21 \[silentpc-opusplan:4a4c3021:j39144#1\])
- Decided: 2026-10-21 decided: "err messages shoould also have line numbers and offsets, sed compatible" \[silentpc-opusplan:4a4c3021:j39144#1\]
- Rationale: "anything that takes more than a couple lines should show beginning and ending point of the error." \[silentpc-opusplan:4a4c3021:j37939\]
- Rationale: "err messages shoould also have line numbers and offsets, sed compatible" \[silentpc-opusplan:4a4c3021:j39144\]
- Precedent: sed (chosen; named by author): line numbers and offsets in messages "sed compatible" \[silentpc-opusplan:4a4c3021:j39144\]
- Precedent: ALGOL 60 (considered; named by author): example: a missing "end" should show the unterminated begin \[silentpc-opusplan:4a4c3021:j37939\]
- Evidence: RFCPLAN.md:1818 "every message now begins \`LINE:COLUMN:OFFSET:\`"; RFCPLAN.md:1820 "a conf reader prints \`file:LINE:COLUMN:OFFSET: ...\`.  Not yet: an end point for a construct that ..."; tests/errors.sh ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: beginning and ending point for errors spanning more than a couple of lines (unterminated begin/end), per the 2026-10-21 decision \[silentpc-opusplan:4a4c3021:j37939#1\]

### Error messages and reporting
- Status: TO DO — helpful messages and carets are built; error recovery and restarts, which the latest line defers until after speed and benching, are not started (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:61606#2\])
- Decided: 2026-10-27 decided: Common lisp restart was "only for you to think about then make recommendations"; error recovery comes after the speedup and benching. \[silentpc-opusplan:4a4c3021:61606#2\]
- Rationale: "hbnf is all about helpful error messages and recoverable/restartable failure modes" \[silentpc-opusplan:4a4c3021:60958\]
- Rationale: Error messages "so good" that RFC BNF is "ALMOST like you can cut and paste the rfc into hbnf" \[silentpc:c14a13ff:j4471\]
- Rationale: For RFC BNF snippets, "either it should compile directly or hbnf should have a good error message" \[silentpc-opusplan:4a4c3021:j4129\]
- Precedent: Common Lisp restart (considered; named by author): "only for you to think about then make recommendations" \[silentpc-opusplan:4a4c3021:61606\]
- Precedent: RFC BNF (chosen; named by author): near cut-and-paste of RFC grammars \[silentpc:c14a13ff:j4471\]
- Precedent: yacc/bison (considered; named by author): end goal: on par, but better and more modern \[silentpc:c14a13ff:j4471\]
- Precedent: OpenBSD daemons (chosen; named by author): test cases as drop-in replacements \[silentpc:c14a13ff:j4471\]
- Precedent: gcc error recovery productions (considered; named by author): asked for explanation \[silentpc-opusplan:4a4c3021:60958\]
- Evidence: ABNF.md:176 "generation stops with \`file:line:col: not written yet, in \`rule\`: \<...\>\`, the line, a caret under it, and what it probably means"; RFCPLAN.md:179 caret under the line; TODO.md:83 "Error recovery and restarts, with the Common Lisp restart system as the model (idea; not started)"; README.md:20 "error recovery" under Next ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: error recovery and restarts (RFCPLAN.md step 8, "opt-in")

### LR, left recursion, GLR and match strategy
- Status: TO DO — direct left recursion and no shift/reduce conflicts are built; the "heavier stuff when needed" (GLR) is not started (latest decision 2026-10-18 \[646:20#1\])
- Decided: 2026-10-18 decided: Where full GLR isn't needed, "don't want to lose cpu or memory efficiency"; "heavier stuff to kick in when needed". \[646:20#1\]
- Rationale: "I don't want to lose cpu or memory efficiency, I just want the heavier stuff to kick in when needed" \[646:20\]
- Rationale: "why avoid LR in the rules if it is more human readable?" \[578:97\]
- Rationale: "can't we implement that with iterative loops too?" \[silentpc:c14a13ff:9039\]
- Precedent: iterative LR (chosen; named by author): "i'm leaning iterative but open to recommendations" \[578:60\]
- Precedent: GLR (considered; named by author): only where full GLR is needed \[646:20\]
- Precedent: yacc, EBNF and ABNF (considered; named by author): compared on human usability and ease of modification \[726:2\]
- Precedent: ANTLR (considered; named by assistant, not taken up): assistant said it handles indirect left recursion \[silentpc:c14a13ff:9039\]
- Precedent: IMP72 (considered; named by assistant, not taken up): semantic arbitration of ambiguity, no full GLR everywhere \[646:20\]
- Evidence: ABNF.md:158 "Direct left recursion ... read as a loop ... Indirect left recursion is refused"; CONTEXTS.md:22 "GLR ... allowed by the scope note, pay only for what is used; not started"; TODO.md:82 "GLR ... not started"; WHY.md:7 shift/reduce conflicts as an LR artifact ; recheck: uncommitted (silentpc): hbnf15.txt:629,801-893 keeps GLR "as a possible later escape hatch" and prefers local fork over global GLR (the --forks option in hbnf.old's usage), consistent with the decision; GLR itself is still not built
- Left: GLR for C++ and ALGOL 68; indirect left recursion still refused

### conf removal
- Status: TO DO — \`--conf\` was removed from the CLI (3ab7fd5) and README no longer mentions it, but TODO.md still names the conf glue and it sits in the templates (latest decision 2026-10-28 \[silentpc-opusplan:4a4c3021:j67540#1\])
- Decided: 2026-10-28 decided: "just not in the docs" \[silentpc-opusplan:4a4c3021:j67540#1\]
- Rationale: "I thought we run over a grammar, it emits a parser. end of story" \[hist-silentpc:fd13bc5f:h447\]
- Precedent: OpenBSD conf.c/conf.h (considered; named by author): lexer and parser in one file populating a conf variable \[hist-silentpc:fd13bc5f:h173\]
- Evidence: 3ab7fd5 "Remove --conf: a config grammar writes its entry point in its own epilogue"; bindings/README.md "\`conf\_error\` comes from \`runtime/hbnf\_conf.h\`" ; recheck: uncommitted (silentpc): RESUME-9c.md records the retirement of HBNF\_Config (hbnf\_config.ad\[sb\]) and the rename to libhbnf.gpr, not the --conf option; packaging repo: testing/hbnf/APKBUILD has no --conf and its check() never calls it; TODO.md:88 wording is unchanged at ff3c5d0
- Doc differs: TODO.md:88 says "The conf glue (\`--conf\`) out of the templates into an included C header", which puts \`--conf\` in a doc
- Left: scrub the \`--conf\` mention from TODO.md and finish moving the glue out of the templates

## 04 Wire layer and bit rules

### Wire protocols: imsg and magic numbers
- Status: TO DO — no imsg wire grammar exists; only prose about imsg in IDREF.md and USENIXSUBMISSION.md (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h326#1\])
- Decided: 2026-09-22 decided: "magic numbers in headers should be explict, not comments" \[hist-silentpc:fd13bc5f:h326#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched grammars/, tests/wire/, tests/daemons/ for an imsg grammar (hits only IDREF.md:125 \`emit(IMSG\_NODE ...)\` and USENIXSUBMISSION.md:76); WIRE.md has no imsg section ; recheck: packaging repo: ada-on-alpine/testing/imsg-ada and README.md:134 package imsg-ada, the OpenBSD imsg message-passing library in Ada, which is a library and not an hbnf wire grammar with explicit magic numbers; no imsg grammar in the uncommitted files either
- Left: an imsg header grammar with explicit magic numbers as the binary-protocol test case

## 05 Templates and output

### Emit only used
- Status: TO DO — no optimisation step for emitting only used tokens and rules is found (latest decision 2026-10-06 \[silentpc:331154d6:1200#1\])
- Decided: 2026-10-06 decided: Write points 1 to 5 "as an optimization step at the end of rfcplan"; "emitted code should only care about tokens/rules that are used, not any that aren't" \[silentpc:331154d6:1200#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched RFCPLAN.md (last step is 20, COBOL/ALGOL 68/C++, at line 2943) for such a step; only the general policy at RFCPLAN.md:2952 "nothing is paid for unused" and commit d1fd743 (a rule used only in a lookahead was left out, a bug fix) ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: write the five points as the final RFCPLAN step and implement dropping unused tokens and rules in the emitters

### Mustache templating in the emitters
- Status: TO DO — the templates are to go away with rewrite rules; the repository still renders them with its own Mustache package and rewrite rules are unbuilt (latest decision 2026-11-05 \[1882:307#1\])
- Decided: 2026-11-05 decided: With rewrite rules etc, "the mustache templates are going away"; asks whether hbnf already uses its own built-in mustache. \[1882:307#1\]
- Rationale: "hbnf should be using mustache on the backend by now" \[1892:j673\]
- Rationale: "mustache is provided by mustache-ada that is the canonical source and we must use it" \[578:136\]
- Rationale: accepted from the assistant: Mustache style is right to eliminate the ~200 \`Append\` calls and enforce a functional style in Ada \[silentpc:c14a13ff:5957\]
- Rationale: "with rewrite rules etc, the mustache templates are going away" \[1882:307\]
- Precedent: Mustache (chosen; named by author): thought all emitters already switched to mustache on tmpl snippets \[578:128\]
- Precedent: mustache-ada (chosen; named by author): his own Ada port, canonical source, must be used \[578:136\]
- Precedent: \${} and \$\$ templating (rejected; named by assistant, accepted): never fully specified; Mustache-style preferred \[silentpc:c14a13ff:5957\]
- Precedent: rewrite rules (chosen; named by author): will replace the mustache templates \[1882:307\]
- Evidence: commit f1ab596 "rendered by hbnf's own Mustache package; mustache-ada is no longer a dependency" (the built-in answer); hbnf\_template.ads, grammars/template.hbnf; README.md:16 "the project's own Mustache package, \`HBNF\_Template\`"; CONTEXTS.md:824 rewrite rules "a sketch, not accepted by any reader"; CONTEXTS.md:1029 item 64 (to be built and benched) ; recheck: packaging repo: ada-on-alpine/testing/hbnf/APKBUILD pins cd94a16 (2026-10-22) and says "the code templates are rendered by mustache-ada" with depends=mustache-ada, build.sh and README.md still chain mustache-ada -\> hbnf; that is older than f1ab596 (2026-10-31, own Mustache package), so it is stale packaging, not a reversal; rewrite rules still unbuilt, templates still in use
- Left: build rewrite rules and retire the templates/ directory; the 2026-10-31 memory blowup of mustache is not mentioned in TODO.md

## 06 Testing and conformance

### Benchmark results and reporting
- Status: TO DO — benchmark results are rerun and published, but the per-backend, per-arch, per-grammar, per-suite reporting is not built (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:63830#1\])
- Decided: 2026-10-27 decided: Wants "the latest benchmark results" on how much the hidden and simd changes sped things up. \[silentpc-opusplan:4a4c3021:63830#1\]
- Rationale: "so we can track progress at a reasonably fine grained level, say, per backend language, per cpu arch, per grammar, per test suite." \[silentpc-opusplan:4a4c3021:63107\]
- Evidence: commits 4a796e4, c4d9370, 4d2f65a (benchmarks rerun, 2026-11-05); bench/results/; tests/check.sh:3 "per backend where a suite names them"; TODO.md:87 "Granular check reporting: per-item results (backend / arch / grammar / suite), sequential, easy to run one item" ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: granular check reporting; a quiet-machine rerun (TODO.md section 1)

### Benchmark runs and rebuilds
- Status: TO DO — rebuild and refresh done; the failing trial is only half done in a paused worktree (latest decision 2026-11-05 \[silentpc-opusplan:4a4c3021:96043#1\])
- Decided: 2026-11-05 approved-proposal: "rebuild, refresh, then fix the failing trial" \[silentpc-opusplan:4a4c3021:96043#1\]
- Rationale and precedent: none stated in the sources
- Evidence: 9884a84 arena/context-set patch, 4a796e4 refresh; TODO.md:5-8 static ./hbnf built from 9884a84; TODO.md:39 "Half done in the paused worktree (it compiled; not measured)"
- Left: the failing-trial precheck (HBNF\_Lookahead.Branch\_First) merged and measured; quiet rerun

### XML benchmark, speed and conformance
- Status: TO DO — conformance table, red-cross marking and kept verdicts are done; the 'fastest conforming' claim waits for a quiet run (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:95737#1\])
- Decided: 2026-11-04 decided: "as long as we are the fastest conforming implementation i'm happy" \[silentpc-opusplan:4a4c3021:95737#1\]
- Rationale: "as long as we are the fastest conforming implementation i'm happy" \[silentpc-opusplan:4a4c3021:95737\]
- Rationale: "pugixml should be written up as non-conformant to the xml standard" \[silentpc-opusplan:4a4c3021:j94728\]
- Rationale: "a couple of the most popular xml parsers in the mix for speed testing" \[silentpc-opusplan:4a4c3021:j91571\]
- Precedent: pugixml (considered; named by author): written up as non-conformant; no trusted mode \[silentpc-opusplan:4a4c3021:j94728\]
- Precedent: libxml2 SAX2 (considered; named by assistant, accepted): speed comparison point for hbnf tree and tape \[silentpc-opusplan:4a4c3021:95737\]
- Precedent: expat (considered; named by assistant, not taken up): catches the checks pugixml skips \[silentpc-opusplan:4a4c3021:j94728\]
- Precedent: Python XML parser (considered; named by author): hbnf's C XML grammar was slower than it; fix it \[silentpc-opusplan:4a4c3021:j91570\]
- Evidence: bench/xml-conformance.sh (kept verdicts, rerun when key changes); README.md:251 red cross for pugixml etc.; bench/results/libs.html pale red rows (8d3317f); 094c8c9 grammar refuses 34 of 34
- Doc differs: TODO.md:46 "The README claim: 'fastest conforming XML parser' only after a quiet run shows it for the tree (the tape already is)"; busy-machine tree 4.3 ms against libxml2 SAX2 4.8
- Left: quiet rerun and, if it holds, the claim; the failing-trial speed work (TODO.md section 2)

## 07 Packaging and release

### Continuous integration
- Status: TO DO — CI exists in ada-on-alpine with checkpoint and resume, but the gdb diagnostic for the s390x check failure path is not found (latest decision 2026-11-05 \[silentpc-opusplan:f7e53777:17568#1\])
- Decided: 2026-11-05 approved-proposal: "do it": add gdb diagnostic to check failure path, push tagged \[ci only: s390x\] \[silentpc-opusplan:f7e53777:17568#1\]
- Rationale: "so it can be done in multiple runs" \[silentpc-opusplan:f7e53777:j12612\]
- Rationale: "can't you checkpoint after every unit that compiles?" \[silentpc-opusplan:f7e53777:17533\]
- Precedent: local QEMU (considered; named by author): run riscv64 and s390x locally and attach to the gdb port \[silentpc-opusplan:f7e53777:12597\]
- Precedent: self-hosted runner (considered; named by assistant, not taken up): no 6-hour cap \[silentpc-opusplan:f7e53777:12597\]
- Evidence: not found: no .github directory or workflow among tracked files; CI belongs to ada-on-alpine
- Evidence: packaging repo: .github/workflows/ci.yml, build-arch.yml, ci-resume.yml (checkpoint a stage before the job limit, resume automatically); not found: searched .github, build.sh, tools/ for gdb (only tools/diagnose/ada\_language\_server.sh exists); s390x and riscv64 are off by default (b0264a2)
- Left: the gdb diagnostic on the s390x check failure; HEAD 77daf37 shows none

### Which hbnf version to use
- Status: TO DO — the hbnf aport is pinned to cd94a16 (2026-10-22), 205 commits behind HEAD ff3c5d0 (latest decision 2026-11-04 \[1882:j2701#2\])
- Decided: 2026-11-04 decided: "use latest hbnf" \[1882:j2701#2\]
- Rationale: "i said grammar is the source of truth; undo your pivot to python. use latest hbnf" \[1882:j2701\]
- Rationale: "hbnf has changed a little, best to update the grammar to use the current version of hbnf" \[silentpc:ae5c3348:3067\]
- Precedent: Python pivot (rejected; named by author): grammar is the source of truth \[1882:j2701\]
- Precedent: hbnf main (git HEAD) (chosen; named by assistant, accepted): chosen over v0.7.0 or tagging v0.6.14 \[1889:2818\]
- Evidence: not checked: consumers are in other repositories; HEAD ff3c5d0 is the latest here
- Evidence: packaging repo: testing/hbnf/APKBUILD \_commit=cd94a1621dcc, pkgver 0.7.0\_git20261022; committed clone: git log cd94a16..HEAD shows 205 commits; testing/buildabook/APKBUILD pins buildabook 96160fb with "hbnf main of 2026-10-22 or later"
- Left: bump the hbnf aport pin (and drop the mustache-ada dependency and libhbnf-sources.patch, both stale at HEAD); other consumers not seen

## Relation to imp72, pcc and other projects

### Algol68 hbnf
- Status: TO DO — not started; no algol68 corpus directory (latest decision 2026-10-18 \[644:67#1\])
- Decided: 2026-10-18 decided: "I do want an hbnf grammar that fully specifies algol68"; "%where predicates are a fundamental part of hbnf" \[644:67#1\]
- Rationale: "%where predicates are a fundamental part of hbnf"; "I do want an hbnf grammar that fully specifies algol68" \[644:67\]
- Precedent: W-grammar (considered; named by author): asked how W-grammar handled what %where predicates do \[644:67\]
- Evidence: corpus/README.md "\`algol68/\` \| the Revised Report's W-grammar \| not started"; TODO.md:117 "ALGOL 68, C++ grammars: not started"; RFCPLAN.md:39 "algol68 to far in the future"; metarules \`::=\` and hyperrules \`:=\` exist (ABNF.md:353)
- Left: write the algol68 grammar (needs the W-grammar facilities, partly built as parameterised rules)

### Buildabook hbnf
- Status: TO DO — the overlay builds buildabook and mustache-ada against an old hbnf pin, not the latest; hbnf has since dropped mustache-ada and fixed libhbnf.gpr, so the overlay is stale (latest decision 2026-10-23 \[silentpc-opusplan:f7e53777:j11262#1\])
- Decided: 2026-10-23 decided: "make sure buildabook and muststache etc all work with the latest hbnf" \[silentpc-opusplan:f7e53777:j11262#1\]
- Rationale and precedent: none stated in the sources
- Evidence: packaging repo: ada-on-alpine/testing/hbnf/APKBUILD \`\_commit="cd94a1621dcc..."\` (2026-10-22), \`depends="mustache-ada"\`, carries libhbnf-sources.patch; packaging repo: ada-on-alpine/testing/buildabook/APKBUILD pinned 96160fb (2026-10-23), check() runs grammars/regen.sh against the installed hbnf and diffs; packaging repo: ada-on-alpine README.md:156 "mustache-ada ──► hbnf ──► buildabook"; hbnf clone HEAD ff3c5d0 is 205 commits past cd94a16: commit f1ab596 "mustache-ada is no longer a dependency", libhbnf.gpr:26-30 now lists hbnf\_wire-zig, hbnf\_lookahead, hbnf\_tree\_sitter (patch obsolete); packaging repo: mustache-ada/README.md:11 still says "the engine \`hbnf\` uses"
- Left: bump the hbnf pin and drop the patch and the mustache-ada dependency in testing/hbnf/APKBUILD; rebuild buildabook against it (regen.sh diff); update mustache-ada/README.md:11; the buildabook APKBUILD comment "only built where GNAT has 128-bit integers" contradicts hbnf's arch="all"

### C helpers abstraction
- Status: TO DO — shared runtime headers exist, but the C helpers all backends use are not all in one file; the conf glue is still in templates (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:63263#1\])
- Decided: 2026-10-27 decided: "the c helpers that all backends use, should be abstracted out into their own file" \[silentpc-opusplan:4a4c3021:63263#1\]
- Rationale and precedent: none stated in the sources
- Evidence: runtime/hbnf\_conf.c, hbnf\_scalar.h, hbnf\_tape.h exist; TODO.md:97 "The conf glue (\`--conf\`) out of the templates into an included C header" open; not found: a helpers file in templates/ or runtime/ (searched README.md, RFCPLAN.md, hbnf\_c.adb)
- Left: move the helpers the C backend emits into a runtime file

### Character encodings
- Status: TO DO — the design is written in the plan; no charset directive or iconv linking is built (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:19260#4\])
- Decided: 2026-10-18 decided: "utf8 maps to codepoints. should be transparent and painless." \[silentpc-opusplan:4a4c3021:19260#4\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:1534-1610 "Character sets (the user, 2026-10-18; decisions still to be taken)" with round trip and iconv rules; not found: "charset" in hbnf\_grammar.adb, hbnf\_c.adb (0 hits)
- Left: build the charset directive, generated tables, optional iconv link and round-trip writing; UTF-8 to code points already works

### Corpus layout
- Status: TO DO — algol60, imp72 and bip39 exist; ipv4, arp, ipv6, icmp, obconf have no corpus directories (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j16200#1\])
- Decided: 2026-10-17 decided: "we should structure it as corpus/{algol60,imp72,bip39,ipv4,arp,ipv6,icmp,obconf} etc" \[silentpc-opusplan:4a4c3021:j16200#1\]
- Rationale and precedent: none stated in the sources
- Evidence: corpus/ has algol60 bech32 bip39 imp72 ...; corpus/README.md "Planned ... \`ipv4/\`, \`arp/\`, \`ipv6/\`, \`icmp/\`, \`obconf/\`.  Their grammars exist today in other places: \`tests/wire/net.hbnf\`"
- Left: create corpus/{ipv4,arp,ipv6,icmp,obconf} (the grammars live in tests/wire/ and grammars/obconf\*.hbnf)

# Left in the air (59)

- Only ideas, open questions, conflicting decisions, or points the record and the repository do not settle.

## Other

### Branching
- Status: IN THE AIR — branches are not carried by a clone (latest decision 2026-10-02 \[silentpc:c14a13ff:17677#1\])
- Decided: 2026-10-02 decided: "why delete the branches? just abandon when done, when they're merged with main and main is pushed, that is good enough" \[silentpc:c14a13ff:17677#1\]
- Rationale: "just abandon when done, when they're merged with main and main is pushed, that is good enough" \[silentpc:c14a13ff:17677\]
- Rationale: asks why still on two branches: "isn't 4c complete now and should be merged and new work goes on 4d or some new branch?" \[silentpc:c14a13ff:j17646\]
- Evidence: not checked: the clone has only main and origin/main (git branch -a), which neither shows nor contradicts the rule that merged branches are left alone
- Evidence: searched uncommitted (silentpc) and packaging repo: no branch information; ada-on-alpine seed-gcc-\<arch\> orphan branches exist by design
- Left: whether his local branches (4c, 4d, others) still exist

### Bug fixing policy
- Status: IN THE AIR — policy; the open defects are queued in TODO.md rather than fixed (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j856#1\])
- Decided: 2026-10-06 decided: "fix the remaining bugs unless the fix would be pointless in light of future changes laid out in the plan" \[silentpc-opusplan:4a4c3021:j856#1\]
- Rationale: Fix the bugs "unless the fix would be pointless in light of future changes laid out in the plan" \[silentpc-opusplan:4a4c3021:j856\]
- Evidence: not checked as a policy; TODO.md section 3 lists the reader and generator fixes by CONTEXTS section 26 number as "Queued"; no sign of which were judged pointless
- Left: which queued bugs are held back as pointless in light of the plan

### Buildabook
- Status: IN THE AIR — buildabook is another repository; hbnf side only partly seen (latest decision 2026-10-04 \[1892:j490#1\])
- Decided: 2026-10-04 decided: "with hbnf grammar for the toc etc, we shouldn't need mustache except as a dependenct of hbnf itself" \[1892:j490#1\]
- Rationale: "with hbnf grammar for the toc etc, we shouldn't need mustache except as a dependenct of hbnf itself" \[1892:j490\]
- Rationale: "perhaps instead of mustache, we should use hbnf to parse our config files" \[1892:j447\]
- Precedent: Mustache (rejected; named by author): not needed beyond being hbnf's own dependency \[1892:j490\]
- Precedent: TOML for config (considered; named by assistant, not taken up): idea replaced by an obconf-style config parsed by hbnf \[1892:j490\]
- Evidence: not checked: buildabook; in hbnf, mustache-ada is no longer a dependency (RFCPLAN.md:3b "the renderer is now HBNF\_Template ... the external mustache-ada library is no longer a dependency"), so the dependency exception named in the decision has been replaced
- Evidence: packaging repo: testing/buildabook/APKBUILD checks the checked-in parsers against hbnf-generated ones (grammars/regen.sh) but still has depends="libgnat mustache-ada", so buildabook's own use of mustache is not dropped; buildabook repository itself not available
- Left: whether buildabook has dropped mustache for an hbnf grammar

### Commit and push approvals
- Status: IN THE AIR — commit/push approvals are one-off permissions, not design (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:17517#1\])
- Decided: 2026-10-17 approved-proposal: "commit it and push" \[silentpc-opusplan:4a4c3021:17517#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: approvals of 2026-10-17 are session actions; the matching commits exist in history (git log, 400 commits) but are not mapped to the approvals one by one
- Left: nothing to implement

### Config parsing
- Status: IN THE AIR — the harness config file is in another project (latest decision 2026-09-30 \[silentpc:6ec412b3:66087#1\])
- Decided: 2026-09-30 decided: the harness config file "should be parsed with hbnf if it isn't already" \[silentpc:6ec412b3:66087#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: the harness is not in this repository
- Evidence: searched uncommitted (silentpc) and packaging repo: harness config not present
- Left: whether the harness config is parsed with hbnf

### Decision log
- Status: IN THE AIR — the decision log is made outside the repository, and dated after HEAD (latest decision 2026-11-10 \[1882:j4687#1\])
- Decided: 2026-11-10 decided: "after that, the same thing for hbnf too" \[1882:j4687#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: the decision log lives in ~/claude/pdp64/docs/decision-log, not in hbnf; the decision (2026-11-10) is later than HEAD (2026-11-07); this ledger is part of that work
- Evidence: searched: nothing new in the silentpc or packaging copies
- Left: whether the decision-log pass for hbnf is finished

### Edits to the hbnf repo
- Status: IN THE AIR — a permission rule about another repository, not checkable in hbnf's code (latest decision 2026-10-06 \[silentpc:331154d6:j3147#1\])
- Decided: 2026-10-06 decided: Asks "not modifying hbnf, right?" \[silentpc:331154d6:j3147#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: it concerns edits made from other projects' sessions; git log of hbnf shows only David Walther as author and committer
- Left: nothing to implement

### Patches and tarballs
- Status: IN THE AIR — process rule about applying patches; no trace in the code (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:92228#1\])
- Decided: 2026-11-03 decided: "apply the patches, don't run the check until all patches are merged" \[silentpc-opusplan:4a4c3021:92228#1\]
- Rationale: "will they make the grammars smaller, or more complicated" \[578:64\]
- Rationale: "use \| instead of / for concat, in line with other BNF dialects" \[578:64\]
- Precedent: Other BNF dialects (chosen; named by author): \| for alternation \[578:64\]
- Precedent: C syntax for strings (chosen; named by author): terminals as quoted strings \[578:64\]
- Precedent: ABNF (chosen; named by author): %d13.10, %x20-7E, %b00001101 and core rules \[578:64\]
- Precedent: Python PEG (considered; named by assistant, not taken up): needs a memo table hbnf lacks; iterative LR chosen \[578:64\]
- Evidence: not checked: patch application and the check run are session actions; git log shows 400 commits all by David Walther and none naming claude (git log --grep=claude finds none), so the strip-attribution step is consistent
- Left: nothing to verify in the repository

### Telegram bot and parser
- Status: IN THE AIR — no standing decision; potential decisions only (latest decision none \[none\])
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: not checked: the telegram bot is another project; hbnf has no telegram grammar (grep over grammars, corpus finds none)
- Evidence: searched uncommitted (silentpc) hbnf15.txt, packaging repo: no telegram grammar
- Left: whether hbnf generates the telegram parser

### Work strategy: Sonnet and Opus
- Status: IN THE AIR — no standing decision; the Sonnet/Opus strategy was only asked about (latest decision none \[none\])
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched README, RFCPLAN, TODO for a work-split strategy; none
- Left: he described hbnf as a 10000 loc meta compiler and sought a strategy; none was decided

## 01 Goals and priorities

### End goal
- Status: IN THE AIR — an open-ended goal with no completion test; the repository shows progress and listed gaps (latest decision 2026-09-30 \[silentpc:c14a13ff:j4471#1\])
- Decided: 2026-09-30 decided: END goal is a compiler-compiler "on par with yacc/bison, but better"; modern, fast, efficient, using the best of modern computer science \[silentpc:c14a13ff:j4471#1\]
- Rationale: "the END goal is to be a compiler-compiler on par with yacc/bison, but better; more modern, fast, efficient" \[silentpc:c14a13ff:j4471\]
- Rationale: error messages so good that "it is ALMOST like you can cut and paste the rfc into hbnf" \[silentpc:c14a13ff:j4471\]
- Precedent: yacc/bison (chosen; named by author): the bar to match and beat \[silentpc:c14a13ff:j4471\]
- Precedent: RFC BNF (chosen; named by author): test case with very trivial modifications \[silentpc:c14a13ff:j4471\]
- Precedent: OpenBSD daemons (chosen; named by author): drop-in replacement as test case \[silentpc:c14a13ff:j4471\]
- Evidence: README.md notation and speed tables against yacc, bison, tree-sitter, ANTLR; TODO.md section 3 (error recovery, GLR, ports to Rust/Zig/Ada not done) \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: no criterion for "on par"; error recovery and GLR not started (TODO.md:84-85)

### Tree-sitter as a goal
- Status: IN THE AIR — only a question was recorded; a tree-sitter backend exists but as one output among several (latest decision none)
- Decided: no standing decision (only potential decisions)
- Precedent: tree-sitter (considered; named by author): asked whether hbnf should become a tree-sitter with extended abnf syntax \[578:105\]
- Precedent: ABNF (considered; named by author): as the syntax of such a tree-sitter \[578:105\]
- Evidence: hbnf\_tree\_sitter.ads/.adb exist; tests/treesitter.sh; commits 602541b, e133141 (tree-sitter scanner work 2026-10-19) \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no decision found; hbnf15.txt and HISTORY.draft.md are AI research text on tree-sitter and PEG, not author decisions
- Left: whether hbnf should become "a tree-sitter with an extended abnf syntax" was never decided

## 02 Notation and grammar design

### AST node types and atoms
- Status: IN THE AIR — the astbnf layer these decisions describe is not in the repository (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h122#1\])
- Decided: 2026-09-21 decided: "let astbnf do the rest of the lifting" beyond the node types already told \[hist-silentpc:fd13bc5f:h122#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched \*.md, \*.ads, \*.adb and git log -S"astbnf" (no hit); the reader works at character level (CHARLAYER.md), with no preparsed AST of comment/block/string/atom \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): astbnf: no hit in any source, tarball or hbnf.old strings
- Left: records show astbnf designed but a later decision (2026-09-21 character level, \[hist-silentpc:fd13bc5f:h198#1\]) moved lexing into the grammar; the repository history starts 2026-10-01 so earlier code is not available

### Abnf numeric
- Status: IN THE AIR — only questions were recorded, and a later decision on number spelling (2026-11-03) dealt with the same point, but not with the \`=/\` question as a decision (latest decision none standing)
- Decided: no standing decision (only potential decisions)
- Precedent: ABNF (considered; named by author): asked why hbnf lacks them \[hist-silentpc:fd13bc5f:h236\]
- Precedent: printf format specifiers (considered; named by author): said %d %x %b resemble them \[hist-silentpc:fd13bc5f:h237\]
- Precedent: int16 int32 hexint decint octint (considered; named by author): readable identifiers as the alternative \[hist-silentpc:fd13bc5f:h237\]
- Evidence: ABNF.md:174 "%b/%d/%o/%u/%x, ranges ✓ in \`dialect abnf\` ... hbnf's own notation refuses them"; ABNF.md:146 "\`=/\` incremental alternatives ✓ reader" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: the repository has both: %-forms in the abnf dialect, C numbers in hbnf's own notation; \`=/\` is built; no record settles the readable-identifiers option (int16, hexint)

### Block templates
- Status: IN THE AIR — only potential decisions; syntax never discussed to a decision (latest decision 2026-10-03 \[silentpc:c14a13ff:j21934#1\])
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:~190 (decision 8) "a block may name a template as shorthand for the code that renders it" listed as not finished; not found: a template reference syntax in ABNF.md \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: syntax for blocks that name templates

### Char rules
- Status: IN THE AIR — no standing decision; repetition in rules of characters is partly there (latest decision 2026-09-30 \[silentpc:c14a13ff:3336#1\])
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:351 "\`\*~x\` is a run of them" and RFCPLAN.md:~190 \`comment = "#" \*~LF\`; ABNF.md:196 "a character rule cannot repeat"; ABNF.md:181 \`r"…"\` regular expressions \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: the potential (repetition and string literals in char rules) was never decided; the repository both allows \`\*~x\` and says "cannot repeat"

### Comma list operator
- Status: IN THE AIR — no standing decision in the chain, but \`#\` is built (latest decision 2026-10-01 \[silentpc:c14a13ff:9967#1\])
- Decided: no standing decision (only potential decisions)
- Rationale: "i'm ok with having # as the operator if we don't have another use for it" \[silentpc:c14a13ff:9967\]
- Precedent: parse.y (considered; named by assistant, not taken up): uses # for input comments; hbnf grammar uses ; as ABNF does \[silentpc:c14a13ff:9967\]
- Precedent: ABNF (considered; named by assistant, not taken up): comments the grammar with ; \[silentpc:c14a13ff:9967\]
- Evidence: RFCPLAN.md:~290 (decision 12) "Comma lists are \`#\`. \*Built 2026-10-18 (\`tests/commalist.sh\`).\*"; commit 70bca4d "comma lists n#m" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: the chain holds only "i'm ok with having # ... if we don't have another use for it"; the repository treats it as decided

### Core rules
- Status: IN THE AIR — no standing decision on this subject; the repository already ships them (latest decision 2026-09-24 \[578:64#5\])
- Decided: no standing decision (only potential decisions)
- Precedent: ABNF (considered; named by author): "Core rules shipped with the spec" proposed for evaluation \[578:64\]
- Evidence: grammars/common.hbnf:11-24 DIGIT ALPHA HEXDIG BIT CHAR CTL VCHAR OCTET WSP CRLF; RFCPLAN.md:178 (decision 10) "Core rules. \`common.hbnf\` includes \`ascii.hbnf\`"; ABNF.md:196 "\`LWSP\` ... Not yet" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence; LWSP still missing
- Left: the author never confirmed the 2026-09-24 proposal as a decision (later file layout decisions of 2026-10-02 cover it); LWSP is missing

### Cstring sugar
- Status: IN THE AIR — only a remark was recorded (latest decision none)
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:173 treats quoted strings as terminals with C escapes; no CSTRING-as-sugar rule found in grammars/ascii.hbnf \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: whether CSTRING is to be a character-stream rule in the library was never decided

### EBNF or PEG instead of yacc
- Status: IN THE AIR — only a question was recorded; the design is PEG-like ordered choice with recursive descent (latest decision none)
- Decided: no standing decision (only potential decisions)
- Precedent: EBNF (considered; named by author): "should be do it in EBNF?" alongside HBNF packages \[hist-silentpc:fd13bc5f:h70\]
- Precedent: PEG (considered; named by author): asked whether better than EBNF for this \[hist-silentpc:fd13bc5f:h70\]
- Precedent: yacc/bison (considered; named by author): asked if Ada has something superior; yacc quirks versus RFC EBNF \[hist-silentpc:fd13bc5f:h70\]
- Evidence: COMPILER-COMPILER.md:5-7 "PEG-style ordered choice and recursive descent"; README.md:71 \`--lint\` for \`\|\` against \`/\` \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): hbnf15.txt:189 and :457 (AI text) call \`\|\` first-match, PEG-style, which is not an author decision
- Left: no decision to adopt PEG as such

### Extend ebnf
- Status: IN THE AIR — only a question was recorded; HyperBNF later took ABNF as the base and extended that (latest decision none)
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: README.md:27 "a superset of BNF, EBNF, ABNF and YBNF"; ABNF.md:353 \`dialect ebnf\` exists \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: whether the railroad-diagram ideas were ever to be taken into EBNF itself was never decided

### List operations (listops)
- Status: IN THE AIR — no standing decision; every recorded listops design was superseded (latest decision 2026-09-23 \[hist-silentpc:fd13bc5f:h422#1\])
- Decided: no standing decision (only potential decisions)
- Rationale: "so our generator will output the exact same thing that parse.y does. byte for byte"; without listops "whatever is most efficient" \[hist-silentpc:fd13bc5f:h422\]
- Precedent: parse.y (chosen; named by author): listops reproduce its output byte for byte \[hist-silentpc:fd13bc5f:h422\]
- Evidence: ABNF.md:342 "\`layout NAME\` reads \`layouts/NAME/layout.hbnf\` ... \`layout\_ops { head { … } entry { … } … }\`"; layouts/tailq, layouts/rb; not found: a \`listops { }\` block \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): uncommitted (silentpc): snapshot RFCPLAN.md:75-76 (2026-10-03) has \`listops\` as a whole-parser directive set by tailq.hbnf, and hbnf.old contains \`hbnf\_c\_\_has\_listops\`, older than the current \`layout\` form
- Left: the 2026-09-23 "listops { }" line was superseded 2026-10-29 by a decision the chain does not show; the repository uses \`layout\` and \`layout\_ops\`, which the chain does not record as decided

### Macros
- Status: IN THE AIR — the decision excludes OpenBSD's macros while a \`macros\` directive for them exists, and later potentials ask for grammar-level macros (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h212#1\])
- Decided: 2026-09-21 decided: "but without those macros that openbsd uses" \[hist-silentpc:fd13bc5f:h212#1\]
- Rationale: "keep a trail so we know where values come from and where they are invoked" instead of "silently substituting them for text" \[578:8\]
- Precedent: OpenBSD pf macros (text substitution) (rejected; named by author): "without those macros that openbsd uses" \[hist-silentpc:fd13bc5f:h212\]
- Precedent: pfctl rule macros at grammar level (considered; named by author): wants token-stream substitution leaving an expansion marker \[578:8\]
- Evidence: obconf.md:53 "No macros, no includes, no arithmetic, no conditionals"; ABNF.md:347 \`macros \<rule\>\` directive (C only); grammars/README.md:147 "\`macros varset\` and \`includes include\` name the rules whose statements define a macro" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence; the conflict between the chain and the \`macros\` directive stands
- Left: the chain (no macros) and the repository (a \`macros\` directive, built for the 2026-09-22 bundle) disagree; the records do not say which stands

### Meta II ideas
- Status: IN THE AIR — recorded as open and unscheduled (latest decision 2026-10-03 \[578:163#2\])
- Decided: no standing decision (only potential decisions)
- Rationale: "it must feel natural when incorporated, not a bolt on. probably fits with the %scan{} %action{} family" \[578:163\]
- Precedent: META II (considered; named by author): quoted: closing its loop needs classification expressible in the notation \[578:163\]
- Precedent: VALGOL (considered; named by assistant, not taken up): hbnf could reproduce it with a translator backend \[578:163\]
- Evidence: RFCPLAN.md:2492 "13b. Closing META II's loop: the classification in the notation. \*Open, and open to argument.\* Not scheduled" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: how to express Analyze/Rule\_Info/classification in the grammar language

### Parsing model, packrat and parse path
- Status: IN THE AIR — grammars still mostly use \`\|\`; whether ordered choice is needed at all is open (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:j78176#1\])
- Decided: 2026-10-29 decided: "i'm ok with rewriting grammars to use / instead of \|". \[silentpc-opusplan:4a4c3021:j78176#1\]
- Rationale: "Don't make packrat a semantic requirement. Make memoization an implementation optimization." \[silentpc:c14a13ff:5639\]
- Rationale: Asked whether ordered choice is needed: "are there any benefits or is it making optimization harder?" \[silentpc-opusplan:4a4c3021:j78176\]
- Precedent: packrat (rejected; named by author): not as a semantic requirement; memoization only an optimization \[silentpc:c14a13ff:5639\]
- Precedent: recursive descent (considered; named by author): hbnf, being recursive descent, does no reductions \[610:4\]
- Precedent: ANTLR / LL(\*) / PEG (considered; named by assistant, not taken up): top-down parsers also have no reductions \[610:6\]
- Precedent: tree-sitter (considered; named by assistant, not taken up): has reductions because GLR-based \[610:4\]
- Evidence: grammars/obconf\_pfctl.hbnf has 294 \` \| \` and 14 \` / \`; RFCPLAN.md:~84 "\`/\` is ABNF's union ... compiles without backtracking"; README.md:71 "ordered choice \`\|\` could be a union \`/\`, and \`--no-factor\` and \`--no-ladder\`" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: no rewrite recorded; memoization stays an optimization (no packrat requirement found stated); the question "does hbnf need \`\|\` at all" (2026-10-29 \[silentpc-opusplan:4a4c3021:j78176#2\]) is open

### Rule typing and typed values
- Status: IN THE AIR — chain says a Rust or Zig type prefix; the repository has no type prefix at all and infers the types (latest decision 2026-09-25 \[726:2#1\])
- Decided: 2026-09-23 decided: "if language is rust or zig it will be a rust or zig type" \[hist-silentpc:fd13bc5f:h434#1\]
- Rationale: "surely the %action and %scan embody that knowledge?" so grammars "look like the BNF found in the RFCs again" \[578:80\]
- Precedent: RFC BNF (chosen; named by author): revert the C type prefix to match it \[578:80\]
- Precedent: yacc, EBNF, ABNF (considered; named by author): compared on human comprehension and ease of modification \[726:2\]
- Precedent: yacc (considered; named by author): asked if %scan and %action match what it did \[726:2\]
- Evidence: grammars/obconf\_ntpd.hbnf:44 \`rtable     = "rtable" int\` (no type prefix); README.md:25 "emits a parser and its typed tree in C, Rust, Zig or Ada"; RFCPLAN.md:530 "Semantic values are typed and named"; not found: \`int a = b c d\` syntax \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): uncommitted (silentpc): RESUME-9b.md shows typed pointer fields per backend (\`T \*f\`, \`Option\<Box\<T\>\>\`), inferred, still no type prefix
- Left: the records do not show whether the 2026-09-24 "revert the c type prefix" was decided; typed semantic values (2026-09-25) are only partly there (typed tree, no per-rule type declarations)

### String quote syntax
- Status: IN THE AIR — only potential decisions; the queued fixes \`'c'\` is \`"c"\` and \`'\\'\` are marked "(the user)" in CONTEXTS but not built (latest decision none)
- Decided: no standing decision (only potential decisions)
- Rationale: "'' is just a special case of \\"\\" syntactically, why are you treating it semantically different?" \[silentpc-opusplan:4a4c3021:j90546\]
- Rationale: "we have '' as well as \\"\\" why not use '" \[silentpc-opusplan:4a4c3021:j90478\]
- Evidence: CONTEXTS.md:911-914 "\`'c'\` is \`"c"\` (the user)", "\`'\\'\` for a backslash (the user)"; TODO.md:57 items 1, 2 queued ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: the author's records hold no decision; the repository's queue treats items 1 and 2 as wanted, which no record settles

### Token tables and tree-sitter appendix
- Status: IN THE AIR — only potential questions; the token-table question was answered in the plan (latest decision 2026-10-02 \[578:136#5\])
- Decided: no standing decision (only potential decisions)
- Rationale: "I'm not opposed to it in principle if there is a benefit" (token tables) \[578:136\]
- Rationale: Wanted an appendix on folding in tree-sitter's efficiency "while keeping our current extended abnf grammar" \[silentpc:c14a13ff:17213\]
- Precedent: tree-sitter (considered; named by author): fold in its efficiency improvements \[silentpc:c14a13ff:17213\]
- Precedent: Knuth (considered; named by author): match it somewhat \[silentpc:c14a13ff:17213\]
- Precedent: token tables (considered; named by author): asked why hbnf went against them \[578:136\]
- Evidence: RFCPLAN.md:416 "Ordering and token tables ... Researched 2026-10-02"; Tree-sitter backend exists (README.md:218 benchmark rows); not found: an appendix on folding tree-sitter's efficiency \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): no new evidence
- Left: the author has not said whether the answer settles it, nor asked for the appendix as a decision

### W-grammar termination and cycle detection
- Status: IN THE AIR — only potential decisions; checks exist for growth but the cycle-detector idea is not recorded as decided (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:j34300#1\])
- Decided: no standing decision (only potential decisions)
- Rationale: "you sure you can't detect cycles in applications of metanotions to themselves? a human can see it by visual inspection." \[silentpc-opusplan:4a4c3021:j34170\]
- Rationale: "in practice, a hyper rule will only be expanded 2 or 3 times except in a handful of cases" \[644:57\]
- Rationale: "if we track the hyperrule that is invoked, can't we cycle detect?" \[silentpc-opusplan:4a4c3021:j34300\]
- Precedent: lazy evaluation (considered; named by author): metanotion not instantiated until needed \[silentpc-opusplan:4a4c3021:j34203\]
- Evidence: HISTORY.md:261 "Can the cycle be detected? Often, yes, and tracking which hyperrule is being instantiated is the ..."; ABNF.md:106 "a use that needs the same rule with a longer pattern again is refused like any use that grows without end"; ABNF.md:106 "An open end (\`0..\`) is not checked" \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): uncommitted (silentpc): RESUME-9b.md's cycle detector (HBNF\_Compilable.Back\_Edges) is for recursive struct fields, not for hyperrule termination, so it does not settle this
- Left: whether to add cycle detection or lazy instantiation for unbounded metanotions

### astbnf and its split from hbnf
- Status: IN THE AIR — no astbnf in the repository; hbnf does its own lexing and parsing (latest decision 2026-09-20 \[hist-silentpc:fd13bc5f:h78#1\])
- Decided: 2026-09-20 decided: "astbnf should be fully general, not specific to hbnf" \[hist-silentpc:fd13bc5f:h78#1\]
- Rationale: "it emits code from an ast, it matches on a preparsed ast, all lexing/tokenizing already done." \[hist-silentpc:fd13bc5f:h75\]
- Rationale: "there is no collision; the scheme will not be in hbnf" \[hist-silentpc:fd13bc5f:h76\]
- Precedent: ABNF (chosen; named by author): "go with abnf flavor" for astbnf \[hist-silentpc:fd13bc5f:h75\]
- Evidence: not found: searched \*.md, Ada sources, grammars/, git log -S"astbnf"; hbnf\_schema.hbnf is the notation's own grammar \| recheck hbnf-recheck-12: searched packaging repo (ada-on-alpine, mustache-ada), uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md, hbnf15.txt, nine hbnf-\*.tar.gz snapshots (2026-10-02..04), hbnf.old, and clone HEAD ff3c5d0 (only README link commits since 2026-11-05): astbnf: no hit in any source, tarball, packaging repo or hbnf.old strings; the ada-on-alpine README lists only hbnf, mustache-ada, buildabook as packages
- Left: chain and repository disagree and the records do not settle whether astbnf was dropped or lives elsewhere

## 03 Parser generation and back ends

### Astbnf cli lexer
- Status: IN THE AIR — no \`astbnf\` program or name exists in the repository and no later record says it was renamed or dropped (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h162#1\])
- Decided: 2026-09-21 decided: "add the astbnf cli but I want you to emit the lexer as well. better translate that to c/rust/zig also" \[hist-silentpc:fd13bc5f:h162#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: grep -ri astbnf over the whole repository returns nothing; the \`--ast\`, \`--ast-tools\`, \`--writer\` options in hbnf.adb:174 may have replaced it ; recheck: uncommitted (silentpc): hbnf.old (Nov 4 binary) has no \`astbnf\` string and its usage line lists --ast, --ast-tools, --writer; packaging repo: no astbnf in ada-on-alpine or mustache-ada; the successor claim is still unrecorded
- Left: whether the \`--writer\`/\`--ast\` family is the successor is not recorded

### Brace counting
- Status: IN THE AIR — statement splitting counts braces, quotes and comments in the C backend only; no per-language round-trip brace counting found (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h227#1\])
- Decided: 2026-09-21 decided: "make sure you do proper brace counting for each of the 4 languages" \[hist-silentpc:fd13bc5f:h227#1\]
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:347 "A statement ends at a newline outside braces, quotes and comments ... C only (the other backends warn and parse the whole file)"; not found: the C/Rust/Zig/Ada round-trip tool the records mean (no astbnf), searched tests/, tools/, ABNF.md ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: the records' subject (the round-tripping tool) is absent, so the four-language claim cannot be checked

### Char type subtypes
- Status: IN THE AIR — only a potential (a HBNF\_CharType container); nothing in the repository uses that name (latest decision 2026-10-01 \[silentpc:c14a13ff:j16135#1\])
- Decided: no standing decision (only potential decisions)
- Rationale: Only "if emitting subtypes is noisy" would they go in a container package. \[silentpc:c14a13ff:j16135\]
- Evidence: not found: searched all files for "HBNF\_CharType"; templates/ada\_scalar.tmpl emits plain \`subtype {{&name}} is {{&type}};\` ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: decide whether emitted char subtypes are noisy enough to need a container package

### Dfa emission
- Status: IN THE AIR — only a potential; token DFAs are built inside the C scanners but no whole-grammar DFA back end is decided (latest decision none)
- Decided: no standing decision (only potential decisions)
- Rationale: "if we can do regex as dfa, why not do hbnf as dfa?" \[704:24\]
- Precedent: regex as DFA (considered; named by author): raised as the model for a whole-grammar DFA \[704:24\]
- Evidence: 3350417 "Generator: token DFAs are minimized"; TODO.md:26 "the name DFA fast path" as a speed item; not found: any grammar-as-DFA emitter ; recheck: uncommitted (silentpc): hbnf15.txt:1007-1030 confirms hbnf builds an automaton per \`/\` alternative to find shared text (generation-time analysis, RFCPLAN.md), so DFAs exist in the analysis and in C token scanners, but no whole-grammar DFA back end; the 2026-09-29 question stays unanswered in the records
- Left: the 2026-09-29 question \[704:24#1\] "why not do hbnf as dfa?" is unanswered

### Hash table and interning
- Status: IN THE AIR — only a potential (rbtree) and an unclear record; the repository interns keywords and uses its own table without a recorded choice (latest decision none)
- Decided: no standing decision (only potential decisions)
- Precedent: rbtree instead of hash table (considered; named by author): asked; no answer recorded \[576:22\]
- Evidence: ABNF.md:182 "a \`%i\` keyword is interned case-insensitively in C"; ABNF.md:348 keyword table interned; not found: any rbtree or hash-table design note ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: the rbtree question of 2026-09-22 \[576:22#1\] is unanswered

### Refusal messages
- Status: IN THE AIR — the 'refusal messages and pointers' referred to cannot be identified in the repository (latest decision 2026-10-28 \[silentpc-opusplan:4a4c3021:j67241#1\])
- Decided: 2026-10-28 decided: "no need for refusal messages and pointers; noone but us ever used them." \[silentpc-opusplan:4a4c3021:j67241#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched \*.md and hbnf\*.adb for refusal wording; "refusal" appears only for the %emit refusal analysis (RFCPLAN.md:2736) and layout refusals (CONTEXTS.md:722), which are different things ; recheck: uncommitted (silentpc): RESUME-9b.md uses "refusal" only for the cycle-detector refusal (hbnf\_c.adb Back\_Edges), not for the messages meant; hbnf.old strings show no separate refusal-message feature
- Left: the records do not say which messages were meant, so whether any are still carried cannot be settled

## 04 Wire layer and bit rules

### Layout grammar for opcodes and charts
- Status: IN THE AIR — only potentials; no opcode/layout-chart grammar or svg emitter exists (latest decision 2026-11-05 \[1882:329#1\])
- Decided: no standing decision (only potential decisions)
- Rationale: "the one grammar matches the opcodes and the bit layouts, but what is emitted can be either the assembler/linker or the svg charts." \[1882:299\]
- Rationale: "this is the type of application where \\"rewrite rules\\" and \\"text transforms\\" come into their own in hbnf." \[1882:304\]
- Evidence: not found: searched TODO.md, CONTEXTS.md, README.md, RFCPLAN.md for svg, chart, opcode ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: whether rewrite rules, or %emit with prologue/epilogue C, will produce the svg charts; depends on rewrite rules (CONTEXTS.md item 64) being built

### Slice syntax for strings and bits
- Status: IN THE AIR — the repository's built spelling is \`name:N\` and \`name@K:N\` for bit rules; the ":bits@offset" order and string slicing are not as the record says, and the records do not settle it (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:19158#1\])
- Decided: 2026-10-18 decided: Use the ":bits@offset syntax we discussed" to say what bits a text field's words stand for. \[silentpc-opusplan:4a4c3021:19158#1\]
- Rationale: "we do need to distinguish bits from bytes from codepoints, and some platforms had different word sizes." \[silentpc-opusplan:4a4c3021:j14841\]
- Rationale: "@Off:Len syntax shoudl work on strings too." \[silentpc-opusplan:4a4c3021:j14778\]
- Rationale: Prefers a cleaner syntax "especially if there is historical precedent" \[silentpc-opusplan:4a4c3021:j17540\]
- Evidence: WIRE.md:68-71 \`name:N\` and \`name@K:N\`; \`words:bitsof(phrase)\` is what spells text words as bits (RFCPLAN.md:1497 "replaced by \`name:bitsof(rule)\`"); WIRE.md:341-347 still presents \`@Off:Len\` slicing of strings and units as "The design" ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Doc differs: RFCPLAN.md:1514 says "\`foo:4\` is 4 units and \`foo@1:4\` is 4 units at offset 1" (offset, then length after the colon), not ":bits@offset"
- Left: whether string slices with a unit suffix get built; the "N bits at a time" stream directive (\`byte 9\`, \`word 18\`, RFCPLAN.md:1537) is listed as undecided

## 05 Templates and output

### Object file naming
- Status: IN THE AIR — only a potential (hbnfconf.o); no object file of either name is produced (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h183#1\])
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched the repository for "libserver" and "hbnfconf.o" (only tests/e2e.sh:64 \`libhbnfconf.so\` and bindings/\*/hbnfconf.\*, which are shared-library and binding names) ; recheck: searched uncommitted (silentpc) HISTORY.draft.md (a general BNF history essay), RESUME-9b.md and RESUME-9c.md (Oct 5-6 handoffs), hbnf15.txt, the nine Oct 2-4 snapshot tarballs and hbnf.old (Nov 4 binary, usage and strings), packaging repo ada-on-alpine and mustache-ada, and the committed clone at ff3c5d0 (only README/Pages/Markdown-corpus/benchmark commits since the first pass); nothing there settles it
- Left: whether the config runtime object is named hbnfconf.o

## 06 Testing and conformance

### Bench speed
- Status: IN THE AIR — a policy for which benches to run; the repository ran every stage after it, and a quiet rerun is pending (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:95435#1\])
- Decided: 2026-11-04 decided: "not 'no benchmarks' but 'only the xml benchmarks'" \[silentpc-opusplan:4a4c3021:95435#1\]
- Rationale and precedent: none stated in the sources
- Evidence: 4a796e4 (2026-11-05) "Benchmark: every stage of bench/run.sh again"; TODO.md:20-34 reruns on a quiet machine pending
- Doc differs: TODO.md:12 says everything was rerun on 2026-11-05 on a busy machine; no doc states an xml-only bench rule
- Evidence: searched uncommitted (silentpc) RESUME-9b.md, HISTORY.draft.md: no xml-only bench rule
- Left: whether 'only the xml benchmarks' was a one-time scope or a standing rule is not recorded

### Check policy
- Status: IN THE AIR — a working rule about when to run checks; TODO.md says reruns wait for a quiet machine (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:j95269#1\])
- Decided: 2026-11-04 decided: "don't rerun the checks/benches till the correctness work is done" \[silentpc-opusplan:4a4c3021:j95269#1\]
- Rationale: "seems kind of spendy when a few choice tests could reassure us enough; tired of work being interrupted for these expensive checks when some light checks would do" \[silentpc-opusplan:4a4c3021:94231\]
- Rationale: "don't rerun the checks/benches till the correctness work is done" \[silentpc-opusplan:4a4c3021:j95269\]
- Evidence: TODO.md:20-34 reruns pending; tests/check.sh runs only stale slices
- Evidence: searched uncommitted (silentpc) files and packaging repo: no rule beyond TODO.md
- Left: standing policy, not code

### Debug policy
- Status: IN THE AIR — a working rule for sessions, not stated in code or docs (latest decision 2026-10-09 \[silentpc-opusplan:34019d9b:j2025#1\])
- Decided: 2026-10-09 decided: "whenever you hit a bug, do a little digging then search the bug trackers for similar stuff" \[silentpc-opusplan:34019d9b:j2025#1\]
- Precedent: Debian bug report system (chosen; named by author): search for known issue with gnat 15.2 \[silentpc-opusplan:34019d9b:j1632\]
- Evidence: not found: searched README.md, TODO.md, STYLE.md for a debugging or bug-tracker policy
- Evidence: searched uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, RESUME-9c.md and packaging repo README.md, tools/README.md: no debugging or bug-tracker policy
- Left: nothing to compare; keep as a process rule

### Evaluation of the latest hbnf
- Status: IN THE AIR — a one-off request; no output in the repository can be tied to it (latest decision 2026-10-25 \[594:0#1\])
- Decided: 2026-10-25 decided: Asks to clone and evaluate the latest moebiusV hbnf from github. \[594:0#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: the evaluation was a conversation in another project
- Evidence: searched uncommitted (silentpc) hbnf15.txt (a 2026-10-18 chat on labeled BNF vs hbnf and imp72), not the 10-25 evaluation
- Left: nothing to verify

### Recheck of known bugs
- Status: IN THE AIR — one-off action; the repository only shows the bugs that are listed now (latest decision 2026-10-04 \[1892:165#2\])
- Decided: 2026-10-04 decided: "pull hbnf again and see if the two bugs are still there" \[1892:165#2\]
- Rationale and precedent: none stated in the sources
- Evidence: TODO.md:57-76 lists the open reader and generator fixes by number (CONTEXTS 26)
- Evidence: searched packaging repo docs/bugs/ (hbnf-libhbnf-sources is the only hbnf bug, fixed in libhbnf.gpr) and uncommitted (silentpc) RESUME-9b.md, RESUME-9c.md: which two bugs were meant is still not recorded
- Left: which two bugs were meant is not recorded; TODO.md section 3 is the current list

## 07 Packaging and release

### Library headers (bip39.h, per-function .h)
- Status: IN THE AIR — per-function headers were made (15383d6) and then removed (0cc3bc0) in favour of system libraries; the records do not settle it (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j16491#1\])
- Decided: 2026-10-17 decided: "instead of hbnf\_sum.h which is opaque, each function should get it's own .h file, sha256.h crc.h etc" \[silentpc-opusplan:4a4c3021:j16491#1\]
- Rationale: "hbnf\_sum.h ... is opaque, each function should get it's own .h file, sha256.h crc.h etc" \[silentpc-opusplan:4a4c3021:j16491\]
- Evidence: 15383d6 "lib/: one header for each function"; 0cc3bc0 deleted lib/\*.h; corpus/bip39/bip39.h remains
- Doc differs: RFCPLAN.md:1464 "by their own names, with corpus/bip39/bip39.h using SHA256"; no lib/ directory at HEAD
- Evidence: searched uncommitted (silentpc) lib-hbnf/ (only .ali files and libhbnf.a), obj-\*/ and the packaging repo: no per-function .h files
- Left: whether sha256.h/crc.h style headers are still wanted or the later 'link the standard library' decision replaced them

## 08 Documentation and process

### Demo of astbnf
- Status: IN THE AIR — astbnf no longer exists as a name; the demo cannot be identified (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h111#1\])
- Decided: 2026-09-21 approved-proposal: "yes, include it, it is an awesome demo of astbnf at work" \[hist-silentpc:fd13bc5f:h111#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: grep astbnf finds nothing; searched tutorial/, README.md, TUTORIAL.md for a demo of that name
- Evidence: searched uncommitted (silentpc) HISTORY.draft.md, RESUME-9b.md, hbnf15.txt and packaging repo README.md for astbnf: no match
- Left: which doc or example was the demo

## Relation to imp72, pcc and other projects

### Arena zeroing
- Status: IN THE AIR — no standing decision; the arena is used but zeroing was not decided (latest decision no standing decision)
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched README.md, WHY.md, RFCPLAN.md for zeroing of freed cells (RFCPLAN.md:1962 is about alternatives' fields)
- Left: whether freed cells need zeroing or a bit

### C only items
- Status: IN THE AIR — the "C-only items" are not identified in the records, and TODO lists the port of C-only features as open (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:33333#1\])
- Decided: 2026-10-19 approved-proposal: "continue with the rest of the C-only items" \[silentpc-opusplan:4a4c3021:33333#1\]
- Rationale and precedent: none stated in the sources
- Evidence: TODO.md:98 "Port the C-only features to Rust, Zig, Ada, tree-sitter ... as K/\$K, up references, bol/eol, ... the arena"; ABNF.md:112-115 "C only"
- Left: which list "the rest of the C-only items" meant; if it is the port to the other backends it is TO DO

### C79 facetlang
- Status: IN THE AIR — no standing decision; step 16 describes the plan and says not started (latest decision no standing decision)
- Decided: no standing decision (only potential decisions)
- Precedent: LLVM ORC JIT and liblld (considered; named by author): target for action/emit, as the imp72 project does \[silentpc-opusplan:4a4c3021:70575\]
- Precedent: facet language (considered; named by author): later project to translate c79 code \[silentpc-opusplan:4a4c3021:70575\]
- Evidence: RFCPLAN.md:2788 "16. The C grammar through LLVM: ORC and lld ... not started"; TODO.md:118 "The C compiler: action/emit into LLVM ORC and liblld ... then c79 to facetlang: not started"
- Left: only potential

### Cdl history
- Status: IN THE AIR — no standing decision; the affix grammar and CDL history is told in HISTORY.md (latest decision no standing decision)
- Decided: no standing decision (only potential decisions)
- Precedent: CDL (considered; named by author): confirmed he meant CDL \[silentpc-opusplan:4a4c3021:57015\]
- Precedent: affix grammars (considered; named by assistant, not taken up): attribute values on rules \[silentpc-opusplan:4a4c3021:57015\]
- Evidence: HISTORY.md:333 "Parameters on rules: affix grammars, CDL and Prolog"
- Left: no decision to implement

### Col
- Status: IN THE AIR — no standing decision; %col exists but a col postfix and its use for fixed-format COBOL and YAML are open (latest decision no standing decision)
- Decided: no standing decision (only potential decisions)
- Rationale and precedent: none stated in the sources
- Evidence: TODO.md:75 "\`col\` (0-based?) and \`where (cond)\` as a postfix: proposed, to be confirmed (24)"; corpus/cobol/README.md:34 "Not yet: fixed format"
- Left: whether col(N) compacts the yaml grammar

### Dead code
- Status: IN THE AIR — the proposal "yes" answered is not visible, so no dead-code item can be tied to it (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j17541#1\])
- Decided: 2026-10-17 unclear: "yes delete dead code"; the assistant proposal it answers is not visible in the shown text. \[silentpc-opusplan:4a4c3021:j17541#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched git log for "dead code" and the \*.md notes; no commit or note names the cleanup
- Left: which dead code was meant is unknown

### Generator project
- Status: IN THE AIR — not checked: pdp10-ki and the generator project are in other repositories (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:70763#1\])
- Decided: 2026-10-29 approved-proposal: "yes pin pdp10-ki, then start the generator project" \[silentpc-opusplan:4a4c3021:70763#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched the hbnf clone for pdp10-ki (only IMP72/PDP-10 history in METACOMPILERS.md)
- Left: belongs to another project

### Other projects
- Status: IN THE AIR — not checked: the pdp64 ABI and as64/ld64 work live in the pdp64 repository, not in hbnf (latest decision 2026-10-29 \[silentpc-opusplan:f7e53777:15924#1\])
- Decided: 2026-10-29 approved-proposal: "delete it" (the imp-mips64 container). \[silentpc-opusplan:f7e53777:15924#1\]
- Precedent: pcc IR (considered; named by author): asked how hard to emit it instead of LLVM IR \[644:21\]
- Precedent: facet language (considered; named by author): operator set and precedence of imp to match it \[644:19\]
- Evidence: not found: searched \*.md in the hbnf clone for pdp64, as64, ABI
- Left: status belongs to the pdp64 ledger

### Other projects
- Status: IN THE AIR — not checked: the ld64 widening and the imp-mips64 container are not in the hbnf repository (latest decision 2026-10-29 \[silentpc-opusplan:f7e53777:15924#1\])
- Decided: 2026-10-29 approved-proposal: "delete it" (the imp-mips64 container). \[silentpc-opusplan:f7e53777:15924#1\]
- Precedent: pcc IR (considered; named by author): asked how hard to emit it instead of LLVM IR \[644:21\]
- Precedent: facet language (considered; named by author): operator set and precedence of imp to match it \[644:19\]
- Evidence: not found: searched the hbnf clone for imp-mips64, ld64
- Left: belongs to the pdp64 and imp projects

### Port ordering
- Status: IN THE AIR — the chain says ports at the very end, which projects is not settled; RFCPLAN puts optimization last and TODO still lists the backend ports as open (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j10012#1\])
- Decided: 2026-10-17 decided: "then we do the hbnf ports at the very end" \[silentpc-opusplan:4a4c3021:j10012#1\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:891 "4f is last of the work, by policy"; TODO.md:98 "Port the C-only features to Rust, Zig, Ada, tree-sitter"
- Left: "hbnf ports" is ambiguous (the posix and imp72 ports versus the C-only features to the other backends); imp72 was cancelled after it

### Use hbnf for IRC and soju
- Status: IN THE AIR — the soju/IRC project is not in the hbnf clone; hbnf has no IRC grammar (latest decision 2026-10-06 \[silentpc:331154d6:j3497#1\])
- Decided: 2026-10-06 decided: "is the config using hbnf?" expects config uses hbnf \[silentpc:331154d6:j3497#1\]
- Rationale: "wouldn't irc protocol be perfect use of hbnf? does hbnf have everything needed?" \[silentpc:331154d6:j880\]
- Rationale: "stick with hbnf unless there is a very good reason not to" \[silentpc:331154d6:j989\]
- Rationale: "whatever needs parsing in the soju project, the wire protocol, the config file, etc, use hbnf for it" \[silentpc:331154d6:2227\]
- Precedent: irc.v4 (Go IRC library) (considered; named by assistant, not taken up): its parsing quirks versus RFC-strict behaviour \[silentpc:331154d6:j989\]
- Evidence: not found: searched README.md, \*.md, grammars/, corpus/, tests/ for irc/soju; not checked: the soju repository is elsewhere
- Left: whether the soju config and wire grammars were written with hbnf lives in that project

### hbnf JSON parser for the watchers
- Status: IN THE AIR — no standing decision; the watchers are another project; hbnf has a JSON grammar and parser (latest decision no standing decision)
- Decided: no standing decision (only potential decisions)
- Precedent: cJSON and jansson (considered; named by assistant, not taken up): JSON library options; author asked about the hbnf JSON parser instead \[silentpc-opusplan:5d3dc9cf:978\]
- Evidence: corpus/json/json.hbnf; README.md:269 benchmark row "cJSON \| 12 ms"; not checked: the watchers repository
- Left: whether the watchers use the hbnf JSON parser instead of cJSON

### hbnf grammars as single source of truth elsewhere
- Status: IN THE AIR — not checked: the grammars and generators that use hbnf as the source of truth are in the pdp64 repository (latest decision 2026-11-04 \[1882:j2701#1\])
- Decided: 2026-11-04 decided: "grammar is the source of truth; undo your pivot to python" \[1882:j2701#1\]
- Rationale: "one change to the grammar, and nothing drifts downstream" \[1889:j70736\]
- Rationale: "if you have hbnf why do you need a json spec?" \[1889:1718\]
- Rationale: "grammar is the source of truth; undo your pivot to python" \[1882:j2701\]
- Precedent: hbnf grammar as source of truth (chosen; named by author): use latest hbnf \[1882:j2701\]
- Precedent: JSON spec (rejected; named by author): questioned why it is needed alongside hbnf \[1889:1718\]
- Precedent: Python pivot (rejected; named by author): told assistant to undo it \[1882:j2701\]
- Evidence: not found: searched the hbnf clone for pdp64/opcode/ISA grammars (none; hbnf only provides the tool)
- Left: the "skip hbnf for now" versus "use the hbnf grammar" decisions (2026-10-21) and the 2026-11-04 decision are settled by the later one, but their state is in the pdp64 repository

# Rejected or replaced (5)

- Rejected, reversed, or replaced by a later decision (the later one has precedence).

## 02 Notation and grammar design

### Commonconf stdlib
- Status: REJECTED — renamed obconf.hbnf on 2026-10-02 \[silentpc:c14a13ff:18620#2\]; the repository carries the new name only, not stale (latest decision 2026-10-02 \[silentpc:c14a13ff:18620#2\])
- Decided: 2026-09-22 decided: "stdlib is a namespace collision just call it commonconf.hbnf or commconf.hbnf" \[hist-silentpc:fd13bc5f:h377#1\]
- Rationale and precedent: none stated in the sources
- Evidence: grammars/obconf.hbnf exists; not found: any file named commonconf\* and no mention of "commonconf" in \*.md

### Namespaces
- Status: REJECTED — rejected 2026-10-01 \[silentpc:c14a13ff:j10318#1\]; no per-file namespaces in the repository, but qualified island names exist (latest decision 2026-10-01 \[silentpc:c14a13ff:j10318#1\])
- Decided: not in force (rejected 2026-10-01) \[silentpc:c14a13ff:j10318#1\]
- Rationale: "if you understand now and don'tneed to implement namespaces, then leave that alone. don't do that if we can at all avoid it" \[silentpc:c14a13ff:j10318\]
- Evidence: not found: "namespace" in RFCPLAN.md or CONTEXTS.md; CONTEXTS.md:7 islands \`include "f" as x\`, \`x.rule\` (built aff3de9, 2026-11-02) are scopes for embedded languages
- Doc differs: CONTEXTS.md:7 "the dot is scope and never part of a name, strict lookup" (qualified names, close to what was rejected, from a later user decision not in this chain)

### Rule definition operators
- Status: REJECTED — replaced on 2026-10-18/19: \`=\` rule, \`:=\` hyperrule, \`::=\` domain; all-equal only under \`dialect bnf\` etc. (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:34497#1\], after 2026-10-18 \[644:79#1\])
- Decided: 2026-10-06 decided: "::= := : and = must all be treated equally? they mean the same thing" \[silentpc-opusplan:4a4c3021:j5011#1\]
- Rationale: "::= := : and = must all be treated equally? they mean the same thing" \[silentpc-opusplan:4a4c3021:j5011\]
- Rationale: "silence makes cut'n'paste easier" \[silentpc:c14a13ff:j4526\]
- Precedent: BNF spellings (chosen; named by author): accepted as equivalent to =; later only under dialect bnf \[704:16\]
- Precedent: W-grammar (chosen; named by assistant, accepted): "add named domains and the wgrammar dialect" \[silentpc-opusplan:4a4c3021:34497\]
- Precedent: RBNF (rejected; named by assistant, accepted): "don't bother with rbnf" \[704:16\]
- Evidence: ABNF.md:221 "\`=\` defines a rule, \`:=\` a rule with parameters, \`::=\` a domain ... \`dialect bnf\` ... reads \`::=\`, \`:=\`, \`:\` and \`=\` as one operator"; commit e0d7009 (2026-10-19) "= defines a rule, := a rule with parameters, ::= a domain (a metarule) in hbnf"; RFCPLAN.md:~95 decision 2 \`=/\` only, built
- Doc differs: no stale text; the old all-equal rule survives only as the dialect behaviour

### name:type syntax
- Status: REJECTED — "not taken for now" on 2026-09-20 \[hist-silentpc:fd13bc5f:h77#2\]; no later decision revived it (latest decision 2026-09-20 \[hist-silentpc:fd13bc5f:h77#2\])
- Decided: not in force (rejected 2026-09-20) \[hist-silentpc:fd13bc5f:h77#2\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched ABNF.md, WIRE.md, README.md for a \`name:type\` rule syntax (the only \`:\` forms are WIRE.md:110 widths \`ttl:8\` and \`:\` as definition, which are different features); the repository carries no stale name:type syntax

## 07 Packaging and release

### Container languages
- Status: REJECTED — replaced by the 2026-10-12 retirement of the fpc, odin and vlang aports (Alpine ships them); the repository no longer carries them in testing/ (latest decision 2026-09-24 \[hist-silentpc:fd13bc5f:h500#1\])
- Decided: 2026-09-24 decided: "freepascal odin and v need their own aports now" \[hist-silentpc:fd13bc5f:h500#1\]
- Precedent: D, Fortran, Free Pascal, Nim, Odin, Objective C, ATS, vlang (chosen; named by author): added to the container, aports if available \[hist-silentpc:fd13bc5f:h498\]
- Precedent: Alpine aports (chosen; named by author): Free Pascal, Odin and V need their own aports \[hist-silentpc:fd13bc5f:h500\]
- Evidence: not checked: no Dockerfile of that container in the clone (only bench/\*/Dockerfile.glibc)
- Evidence: packaging repo: commit 6e53848 (2026-10-12) "Retire the odin and vlang aports; Alpine already ships both"; b123ee8 (2026-10-12) "Retire the fpc aport; Alpine's is older and better"; README.md:39-41 table rows odin, vlang, fpc "retired"; ls testing has none of them
- Doc differs: build-full-image.sh:13-18 still lists fpc, odin, vlang as "this repo's aports" (stale)

# Done (176)

- Implemented in the current code or stated in the current docs, with the evidence.

## Other

### Abnf rationale
- Status: DONE — README and WHY.md state the RFC-reader audience and why ABNF is the start (latest decision 2026-10-01 \[silentpc:c14a13ff:j8417#1\])
- Decided: 2026-10-01 decided: emphasize the design is for anyone comfortable reading the RFCs; explain why ABNF is the starting point: "used in many new rfc and has its own rfc itself" \[silentpc:c14a13ff:j8417#1\]
- Rationale: ABNF chosen "since it is used in many new rfc and has its own rfc itself" \[silentpc:c14a13ff:j8417\]
- Rationale: the design is for anyone comfortable reading the RFCs; "it makes BNF natural and readable the way the RFCs do" \[silentpc:c14a13ff:j8417\]
- Precedent: ABNF (chosen; named by author): the starting point; has its own RFC \[silentpc:c14a13ff:j8417\]
- Precedent: RFC BNF (chosen; named by author): readers comfortable with RFC notation are the audience \[silentpc:c14a13ff:j8417\]
- Evidence: README.md:28-30 "The design is for anyone who is comfortable reading the RFCs"; README.md:40-44 "ABNF is the starting point because it is the notation the RFCs actually use: RFC 5234 defines it, RFC 7405 ... dozens of newer RFCs"

### Abnf relation
- Status: DONE — relation to ABNF is documented in its own file (latest decision 2026-09-23 \[578:16#1\])
- Decided: 2026-09-23 decided: "we are both an extension and a simplification of abnf, but I'd like the shape of that thoroughly documented" \[578:16#1\]
- Precedent: ABNF (chosen; named by author): hbnf is both an extension and a simplification of it \[578:16\]
- Precedent: ABNF (considered; named by assistant, not taken up): feature list to test hbnf against \[578:16\]
- Evidence: ABNF.md:1-12 "hbnf ... is not ABNF. It borrows ABNF's rule notation ... extends the notation downward ... upward" and lists what is kept, added, left out
- Doc differs: ABNF.md never uses the word "simplification"; it says "what it leaves out, by design or not yet"

### Ada style
- Status: DONE — ada-on-alpine points to the guidelines for contributors (latest decision 2026-10-04 \[silentpc:fa150405:j871#1\])
- Decided: 2026-10-04 decided: "ada-on-alpine should also point to the style guidelines for contributors and anyone wanting to make new ada packages" \[silentpc:fa150405:j871#1\]
- Rationale: "ada isn't a \\"pure\\" language and the types of things we use it for are not \\"pure\\" so \\"in out\\" is needed sometimes"; "perhaps minimize it yes" \[silentpc:fa150405:343\]
- Rationale: "we should have an authoritative source for the guidelines then the other repos point to it/refer to it by URL" \[silentpc:fa150405:343\]
- Rationale: wants the functional guidelines in every Ada repo "so we get a consistently concise ada style" \[silentpc:fa150405:j313\]
- Rationale: should point "for contributors and anyone wanting to make new ada packages" \[silentpc:fa150405:j871\]
- Precedent: pure functional style (ban on in out) (rejected; named by author): "i would never agree to that"; minimize rather than ban \[silentpc:fa150405:343\]
- Evidence: not checked: ada-on-alpine; STYLE.md in hbnf is a pointer only ("See the canonical guide: https://moebiusv.github.io/ada-style-guidelines.html"), as decided 2026-10-04 (one authoritative source, other repos refer by URL)
- Doc differs: README.md Contributing says "no \`out\`/\`in out\` parameters", while the 2026-10-04 \[silentpc:fa150405:343#1\] decision rejected a ban (minimize only)
- Evidence: packaging repo: README.md:329 "Ada functional style guide at https://moebiusv.github.io/ada-style-guidelines.html. Each Ada repo carries a STYLE.md that points at it."; mustache-ada/STYLE.md present (commit "STYLE.md points at the canonical Ada style guide")
- Doc differs: hbnf README.md:464 still says "no \`out\`/\`in out\` parameters" (rejected as a ban 2026-10-04 \[silentpc:fa150405:343#1\])

### Benchmark documentation and scripts
- Status: DONE — benchmarks are scripts that write the tables the documents quote (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:8640#1\])
- Decided: 2026-10-17 approved-proposal: "fix those and do the final full run" (benchmark memory and ntpd figure bugs). \[silentpc-opusplan:4a4c3021:8640#1\]
- Rationale: "i want the performance test to be a script so the document updates can just insert the results of the script" \[silentpc-opusplan:4a4c3021:j7441\]
- Rationale: wants "final full run" after fixing the output bugs, accepted so every table comes from the same conditions \[silentpc-opusplan:4a4c3021:8640\]
- Precedent: byacc (chosen; named by assistant, accepted): comparator for hbnf's generated C parser \[silentpc-opusplan:4a4c3021:j7440\]
- Precedent: bison (chosen; named by assistant, accepted): comparator \[silentpc-opusplan:4a4c3021:j7440\]
- Precedent: tree-sitter (chosen; named by assistant, accepted): comparator \[silentpc-opusplan:4a4c3021:j7440\]
- Precedent: ANTLR (chosen; named by assistant, accepted): comparator \[silentpc-opusplan:4a4c3021:j7440\]
- Precedent: parse.y (chosen; named by assistant, accepted): toy plus a real parse.y as the test input \[silentpc-opusplan:4a4c3021:j7440\]
- Evidence: bench/run.sh, bench/update-docs.sh ("sh bench/update-docs.sh --check"), bench/README.md:3 "No figure in those documents is typed by hand"; comparators byacc/bison+flex, tree-sitter, ANTLR, PEG in bench/stage-\*.sh; WHY.md, README.md, USENIXSUBMISSION.md section 6

### Bit, octet and string layering
- Status: DONE — the generator prints one note for text after fields ending inside an octet (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:20419#1\])
- Decided: 2026-10-18 decided: If a bit shift offsets all octets, print "ONE notification" when generating the parser, since it is "most often an error... but it may not be". \[silentpc-opusplan:4a4c3021:20419#1\]
- Rationale: "any string is already a bit stream; we just need to be able to access it as such." \[silentpc-opusplan:4a4c3021:j15241\]
- Rationale: "i treat strings as arrays of bits/bytes" \[silentpc-opusplan:4a4c3021:j14842\]
- Rationale: "we should have literally bit-precise syntax at some point. octet is actually a byte, by definition." \[silentpc-opusplan:4a4c3021:5279\]
- Rationale: print ONE notice on bit shift "because it is most often an error... but it may not be" \[silentpc-opusplan:4a4c3021:20419\]
- Precedent: ABNF (considered; named by assistant, accepted): a code point in hbnf, a byte in ABNF; he says octet is a byte \[silentpc-opusplan:4a4c3021:5279\]
- Evidence: WIRE.md:64-69 "hbnf prints one note to standard error when it generates such a parser, naming the first rule where text follows fields that end inside an octet; it is only a note"; WIRE.md:346-352 units design (9-bit bytes, 36-bit words) is stated as design
- Doc differs: WIRE.md:340-352 describes the Units design (b, B, c, W suffixes, \`byte 9\`, \`word 36\`) as a design; not checked whether it is built, so 9- and 18-bit machines are stated, not shown

### Bitfield syntax
- Status: DONE — bitsof works in Rust, Zig and Ada (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:32550#1\])
- Decided: 2026-10-19 approved-proposal: "continue with bitsof in Rust, Zig and Ada" \[silentpc-opusplan:4a4c3021:32550#1\]
- Rationale: asked for options "based on principle of least astonishment" \[silentpc-opusplan:4a4c3021:j13158\]
- Rationale: accepted from the assistant: keep ":" for widths, since Erlang and C both use it, so it is least surprising \[silentpc-opusplan:4a4c3021:13175\]
- Rationale: suggests "\[\]" for indexing and slicing "instead of the @ syntax" if unused \[silentpc-opusplan:4a4c3021:15224\]
- Precedent: IMP72 (considered; named by author): "i didn't know about imp72 at the time"; asked for historical options \[silentpc-opusplan:4a4c3021:j13158\]
- Precedent: Erlang bit syntax (chosen; named by assistant, accepted): colon for widths \[silentpc-opusplan:4a4c3021:13175\]
- Precedent: C bit-field colon (chosen; named by assistant, accepted): colon for widths \[silentpc-opusplan:4a4c3021:13175\]
- Precedent: RFC packet diagrams (chosen; named by assistant, accepted): bit 0 is the most significant bit; option A taken \[silentpc-opusplan:4a4c3021:13175\]
- Precedent: Bison term\[lhs\] (considered; named by assistant, not taken up): ruled out because \[ \] is the optional \[silentpc-opusplan:4a4c3021:13175\]
- Evidence: WIRE.md:226 "Rust, Zig and Ada read \`bitsof\` too"; WIRE.md:81-82 "\`bitsof\` anywhere in a rule, over any text rule, works in Zig, Ada and Rust"; hbnf\_wire-zig.adb:317 Seq\_Has\_Bitsof

### Book toolchain
- Status: DONE — ada-toolchain:edge installs every aport built by build.sh, hbnf and buildabook included (latest decision 2026-10-23 \[1889:2744#1\])
- Decided: 2026-10-23 decided: "use the alpine docker image with hbnf and buildabook installed already NOT go about reimplementing stuff!" \[1889:2744#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: buildabook not available here; the clone has bench/Dockerfile.glibc and bench/\*/Dockerfile.glibc only
- Evidence: packaging repo: build-image.sh "plain alpine:edge with the whole toolchain installed" (apk add /pkgs/\*.apk); testing/buildabook/APKBUILD makedepends hbnf; build-arch.yml:78 builds hbnf then buildabook
- Doc differs: the image definition does not name hbnf or buildabook explicitly

### Bug reports
- Status: DONE — each bug has a directory with its write-up, reproducer and patch in ada-on-alpine (latest decision 2026-10-09 \[silentpc-opusplan:34019d9b:2065#1\])
- Decided: 2026-10-09 decided: "for each bug save the patch and the detailed writeup together" \[silentpc-opusplan:34019d9b:2065#1\]
- Rationale: save the bug report as a .txt "so I can submit it upstream later and the appropriate port should know about it" \[silentpc-opusplan:34019d9b:1059\]
- Rationale: "for each bug save the patch and the detailed writeup together" \[silentpc-opusplan:34019d9b:2065\]
- Evidence: not found: git ls-files has no bug .txt write-ups or patch pairs; not checked: the upstream-bound files live outside hbnf (the tree has none of them)
- Evidence: packaging repo: docs/bugs/README.txt "One directory per bug ... report.txt, a reproducer, and the patch"; docs/bugs/hbnf-libhbnf-sources/{report.txt,libhbnf-sources.patch}; commit c54d6a4 (2026-10-08)

### Cleanup
- Status: DONE — the file is deleted (latest decision 2026-10-31 \[silentpc-opusplan:4a4c3021:81310#1\])
- Decided: 2026-10-31 decided: "delete tools/sync\_templates.py". \[silentpc-opusplan:4a4c3021:81310#1\]
- Rationale and precedent: none stated in the sources
- Evidence: commit a6ab1f0 "Remove tools/sync\_templates.py"; ls tools has no sync\_templates.py

### Commit and push policy
- Status: DONE — the 725cc55 commit subject was left as it is (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:92779#1\])
- Decided: 2026-11-04 decided: "leave it" (do not rewrite the 725cc55 commit subject) \[silentpc-opusplan:4a4c3021:92779#1\]
- Rationale: accepted from the assistant: leave the subject; the body is accurate and a rewrite would change every later hash \[silentpc-opusplan:4a4c3021:92779\]
- Rationale: "commit it when the regression passes"; "commit and push when check.sh passes" \[silentpc-opusplan:4a4c3021:65390\]
- Evidence: git log: 725cc55 "corpus/markdown/markdown.hbnf reads headings, paragraphs, ..." still the long subject, not rewritten (checked in the log of HEAD ff3c5d0)

### Contexts md
- Status: DONE — CONTEXTS.md carries a reviewed status table (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:88813#1\])
- Decided: 2026-11-03 decided: "contexts.md is reviewed, just keep it up to date with decisions made and implemented" \[silentpc-opusplan:4a4c3021:88813#1\]
- Rationale and precedent: none stated in the sources
- Evidence: CONTEXTS.md:3 "Status (reviewed; kept up to date with what is decided and what is built, last 2026-11-05)"; TODO.md section 5 repeats the rule

### Contexts survey
- Status: DONE — the metacompiler comparison table is in METACOMPILERS.md with unverified points marked (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:84504#1\])
- Decided: 2026-11-03 decided: Make sure the entire metacompiler comparison table is in the doc, "but also go and verify it." \[silentpc-opusplan:4a4c3021:84504#1\]
- Rationale and precedent: none stated in the sources
- Evidence: METACOMPILERS.md:80 comparison table ("A rule is ..." row across META II, Earley/GLR, Raku, hbnf); METACOMPILERS.md:252 "Not verified: whether a left-recursive rule is supported or loops (no source found) ..."

### Credits
- Status: DONE — all parse.y copyright authors are listed by date, now in obconf.md (README moved the obconf material there on 2026-10-28) (latest decision 2026-10-01 \[silentpc:c14a13ff:j14006#1\])
- Decided: 2026-10-01 decided: README to list "ALL contributors names that were ever put in the parse.y copyright", in order of date added, not limited to those in two or more files \[silentpc:c14a13ff:j14006#1\]
- Rationale: "truly, ALL contributors are to get mention in the README"; not limited to those in 2 or more \[silentpc:c14a13ff:j14006\]
- Rationale: obconf material moved out of the README into obconf.md, linked in \[silentpc-opusplan:4a4c3021:67405\]
- Precedent: parse.y (chosen; named by author): all names ever in the copyright, in order of date added \[silentpc:c14a13ff:j14006\]
- Evidence: obconf.md:103 "## Credits" with a table of 19 authors in order of first appearance (2001 Markus Friedl ... 2020 Matthias Pressfreund)
- Doc differs: README.md has no Credits section; the later move of obconf material \[silentpc-opusplan:4a4c3021:67405#1\] put it in obconf.md

### Design notes
- Status: DONE — design notes are saved in the repository (latest decision 2026-10-02 \[silentpc:c14a13ff:j18570#1\])
- Decided: 2026-10-02 decided: "obviously save the design notes" \[silentpc:c14a13ff:j18570#1\]
- Rationale and precedent: none stated in the sources
- Evidence: CONTEXTS.md (1029 lines, "Status (reviewed; kept up to date ..." line 3), RFCPLAN.md, WIRE.md, CHARLAYER.md, IDREF.md; commit d9ae2a4 "CONTEXTS.md: the design notes on contexts, islands and switches"

### Emit syntax and actions
- Status: DONE — YAML is built in all four backends, and %emit, %action and the :: notation are built (latest decision 2026-10-28 \[silentpc-opusplan:4a4c3021:69163#1\])
- Decided: 2026-10-28 approved-proposal: "go ahead with YAML" \[silentpc-opusplan:4a4c3021:69163#1\]
- Rationale: "we need to do %emit anyway so we can make parsers drop in replacements for arbitrary things" \[silentpc-opusplan:4a4c3021:j66364\]
- Rationale: "everything combines with everything unless you find a very good reason why not. no artificial restrictions!" \[silentpc-opusplan:4a4c3021:67729\]
- Precedent: Go syntax (considered; named by author): "why not just use golang syntax, object uint32\_t =\> ..." \[silentpc-opusplan:4a4c3021:67736\]
- Precedent: W-grammar (considered; named by author): asked whether its support needs multiple tokens on the left side \[silentpc-opusplan:4a4c3021:67736\]
- Precedent: ALGOL 68 (considered; named by author): same question about left-hand side \[silentpc-opusplan:4a4c3021:67736\]
- Precedent: yacc (considered; named by assistant, not taken up): bare colon in a rule head; reason for the type-line choice \[silentpc-opusplan:4a4c3021:67736\]
- Evidence: README.md:5-6 "JSON, TOML and YAML are built and tested in all four backends"; WIRE.md:248-251 "%emit{ code }" and "name :: type = ..."; commits d36abec "C code generation for %emit", eac77a0 "rollback { } for %emit ... TOML and YAML tape grammars"; corpus/yaml
- Doc differs: WIRE.md:251 says %emit with a declared value runs during the read "in the C backend only"

### Git hooks
- Status: DONE — the hooks are copied: hbnf's .git/hooks files are byte-identical to ada-on-alpine's (latest decision 2026-10-02 \[silentpc:c14a13ff:j16778#1\])
- Decided: 2026-10-02 decided: "copy the ada-on-alpine hooks to all the new repos" \[silentpc:c14a13ff:j16778#1\]
- Rationale: "this is cleanup for pushhing to a remote origin"; author and committer must be "proper (not claude)"; "find a way to make sure git am doesn't bypass the hooks" \[silentpc:c14a13ff:318\]
- Rationale: "I don't want it ignoring my hooks" \[silentpc:c14a13ff:j214\]
- Rationale: asks "why isn't it set up so these hooks are default for all new repos?" \[silentpc:c14a13ff:j16791\]
- Evidence: not checked: .git/hooks of the clone holds applypatch-msg, commit-msg and pre-push; the ada-on-alpine repo is not available here; commit d13ee66 removed the markdown corpus's own pre-commit hook
- Evidence: packaging repo: .git/hooks/applypatch-msg, commit-msg, pre-push; committed clone ff3c5d0: same three files, cmp reports identical

### Grammar size and line-savings tables
- Status: DONE — size tables count tokens and symbols, with two public tokenizers (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:88760#1\])
- Decided: 2026-11-03 decided: "often it is more about token/rule/concept savings, not raw line/character savings. reduce cognitive load." \[silentpc-opusplan:4a4c3021:88760#1\]
- Rationale: "often it is more about token/rule/concept savings, not raw line/character savings. reduce cognitive load." \[silentpc-opusplan:4a4c3021:88760\]
- Rationale: "I want the grammar comparisons all redone, lines, tokens, characters hbnf vs old style" \[silentpc-opusplan:4a4c3021:59383\]
- Precedent: old-style grammar notation (yacc) (chosen; named by author): the baseline hbnf is compared against \[silentpc-opusplan:4a4c3021:59383\]
- Precedent: ABNF (chosen; named by assistant, accepted): JSON comparison baseline in the savings table \[silentpc-opusplan:4a4c3021:30995\]
- Precedent: W-grammar (considered; named by assistant, not taken up): scope-end("ADD") weighed for size versus a single terminator definition \[silentpc-opusplan:4a4c3021:88760\]
- Evidence: commit 3a12ad1 "bench: a grammar's size in tokens, with two public tokenizers"; scripts/grammar-size.py; bench/notation.sh; README.md:148 "A symbol is a whitespace-separated word"; WHY.md:158 "counted in tokens"

### HISTORY.md article
- Status: DONE — HISTORY.md carries the Cornell/Hebrew University quote and the rest of the outline (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:j59773#1\])
- Decided: 2026-10-27 decided: History must include the Cornell/Hebrew University quote ("structural predictor") in support of mozeson. \[silentpc-opusplan:4a4c3021:j59773#1\]
- Rationale: "formal grammars are a way for humans and machines to interact more easily" as a theme to weave throughout \[silentpc:c14a13ff:17150\]
- Rationale: "principle of least astonishment is very important for human readability" as the reason for C syntax in literals \[silentpc:c14a13ff:18071\]
- Rationale: quoted Knuth: "first make it correct, then make it fast. premature optimization is the root of all evil." \[578:124\]
- Rationale: the Cornell/Hebrew University "structural predictor" text goes in "in support of mozeson" \[silentpc-opusplan:4a4c3021:j59773\]
- Precedent: Mozeson (chosen; named by author): supported with the Cornell/Hebrew University study \[silentpc-opusplan:4a4c3021:j59773\]
- Precedent: Sitaker's metacircular compiler (chosen; named by author): corrected the text to his actual words \[578:124\]
- Precedent: Knuth (chosen; named by author): correct first, then fast \[578:124\]
- Precedent: principle of least astonishment (chosen; named by author): explains C-style literals \[silentpc:c14a13ff:18071\]
- Precedent: Theodore Beale's writing style (chosen; named by author): concise, no AI slop \[silentpc:c14a13ff:17055\]
- Evidence: HISTORY.md:734-738 "The recent work behind this comes from Cornell University, the Hebrew University of Jerusalem ..."; HISTORY.md:1-8 title "HyperBNF: Return of the Metacompiler", names line by year; CDL at HISTORY.md:333-396; pcc/1994 at HISTORY.md:510; W-grammar and halting at HISTORY.md:271; META II at HISTORY.md:99; appendix of bios at HISTORY.md:1016
- Doc differs: HISTORY.md header says "1 October 2026" and the names line is by year ("name(year) · ..." as decided)

### LLM token measurement and constrained decoding
- Status: DONE — tokenizer measurement exists and constrained decoding is on the roadmap (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:j59641#1\])
- Decided: 2026-10-27 decided: Add a tokenizer measurement of real LLM tokens; add constrained decoding driven by HyperBNF grammars to the roadmap. \[silentpc-opusplan:4a4c3021:j59641#1\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:2595 "14. Grammars for constrained decoding. Added 2026-10-27; not started"; commit 3a12ad1 tokenizer measurement; README.md:37 "step 14 of RFCPLAN.md plans the emitter that would hand the same grammar to a model's decoder"
- Doc differs: TODO.md:24 says bench/tokens.sh is broken (empties tokens.md) and the token figures are the 10-27 ones

### Other documents and notes
- Status: DONE — benches were rerun on 2026-11-05 and the docs pushed (latest decision 2026-11-05 \[silentpc-opusplan:4a4c3021:96315#1\])
- Decided: 2026-11-05 decided: "just do the benches the machine is as quiet as it will be, compensate as best you can, then push the docs and pause" \[silentpc-opusplan:4a4c3021:96315#1\]
- Rationale: "\[\] as optional matches manpages and the usage text of almost every command line utility ever, so it is established syntax" \[silentpc:c14a13ff:16623\]
- Rationale: "the machine is as quiet as it will be, compensate as best you can" \[silentpc-opusplan:4a4c3021:96315\]
- Precedent: manpages and usage text (chosen; named by author): \[\] for optional is established syntax \[silentpc:c14a13ff:16623\]
- Precedent: ANTLR (considered; named by assistant, accepted): comparison recorded in WHY.md; no C, Rust, Zig or Ada targets \[silentpc:c14a13ff:9039\]
- Evidence: README.md:318 "\_2026-11-05; glibc 2.41 ... hbnf f95d41d" and the note on the busy machine; TODO.md:1 "What is left to implement or fix (2026-11-05)" written at the pause

### Other projects
- Status: DONE — hbnf names its C grammar pcc99 (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:63066#1\])
- Decided: 2026-10-27 decided: "don't call it pcc call it pcc99" \[silentpc-opusplan:4a4c3021:63066#1\]
- Precedent: pcc IR (considered; named by author): asked how hard to emit it instead of LLVM IR \[644:21\]
- Precedent: facet language (considered; named by author): operator set and precedence of imp to match it \[644:19\]
- Evidence: README.md:7-9 "\`pcc99\` (what PCC's \`cgram.y\` reads)"; corpus/c
- Doc differs: TODO.md section 4 "RFCPLAN step 20 (ALGOL 68, C++, COBOL on the list; IMP72 cancelled)" while the 2026-10-18 \[644:0#1\] decision planned an imp72 port (separate project, pdp64)

### Plan documents and step order
- Status: DONE — decisions, json grammars and later steps are recorded in RFCPLAN.md (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:70600#1\])
- Decided: 2026-10-29 decided: Commit docs, then work on json "but don't just save it as a memory put it in the rfcplan" \[silentpc-opusplan:4a4c3021:70600#1\]
- Rationale: "don't just save it as a memory put it in the rfcplan" \[silentpc-opusplan:4a4c3021:70600\]
- Rationale: accepted from the assistant: the notation decisions must land before step 13 freezes the notation, so they go earlier on the critical path \[578:165\]
- Rationale: "in this step, no code changes, only updates to the plan" \[578:136\]
- Precedent: mustache-ada (chosen; named by author): "the canonical source and we must use it" for mustache \[578:136\]
- Precedent: tree-sitter (chosen; named by assistant, accepted): "i like your idea, step 8 borrowing error recovery stuff" \[578:109\]
- Precedent: tree-sitter (considered; named by author): asked what generality it takes to handle the languages tree sitter does \[578:109\]
- Precedent: Sitaker's metacircular compiler (considered; named by assistant, not taken up): reason given for a self-describing grammar for hbnf \[578:165\]
- Evidence: RFCPLAN.md:783 "## Order", steps 0-3b marked Done with dates, step 14 "Added 2026-10-27; not started", "Shipped grammars" (RFCPLAN.md:577) names JSON, TOML, YAML and obconf as built; the gate rule at RFCPLAN.md:787 names the old mechanism and asserts it gone

### README content, style and tables
- Status: DONE — README presents JSON, TOML, YAML and C together (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:j77302#1\])
- Decided: 2026-10-29 decided: "json/toml/yaml/c all together into the readme" \[silentpc-opusplan:4a4c3021:j77302#1\]
- Rationale: split packages into three tables: "this is to make it easier to get the ada toolchain into Alpine" \[silentpc-opusplan:34019d9b:4\]
- Rationale: first paragraph should give the motivation: gprbuild led to noticing "a bunch of other stuff common in an ada development environment wasn't yet in alpine" \[silentpc-opusplan:34019d9b:435\]
- Rationale: imsg-ada "should be pointed out imsg is the protocol needed to do privsep security" \[silentpc-opusplan:34019d9b:418\]
- Rationale: "since mustache-ada is only needed by hbnf it can also go in personal projects table" \[silentpc-opusplan:34019d9b:114\]
- Evidence: README.md:5-21 status paragraph "JSON, TOML and YAML are built and tested in all four backends ... C is a family of grammars"; README.md:202 "## Performance" with JSON/TOML/YAML/XML tables and C against gcc

### Tutorial document
- Status: DONE — TUTORIAL.md exists and is tested (latest decision 2026-10-21 \[silentpc-opusplan:4a4c3021:j38972#1\])
- Decided: 2026-10-21 decided: "we need a tutorial doc showing people how to use hbnf to parse things and use those parsed ast"; asks which AST helper functions are universal \[silentpc-opusplan:4a4c3021:j38972#1\]
- Rationale: "we need a tutorial doc showing people how to use hbnf to parse things and use those parsed ast" \[silentpc-opusplan:4a4c3021:j38972\]
- Evidence: TUTORIAL.md:1 "Tutorial: from a grammar to a tree you can use"; tutorial/ directory; tests/tutorial.sh named at TUTORIAL.md:10; README.md lists it under "Start here"

### USENIX paper
- Status: DONE — paper is in the repo as USENIXSUBMISSION.md, with no we/our/naive/simply/Urbit (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h344#1\])
- Decided: 2026-09-22 decided: "line 111 is fine, fix 514. also, expect instead of assume" \[hist-silentpc:fd13bc5f:h344#1\]
- Rationale: "document it in the usenix paper as a benefit of this approach, jets plus actual hbnf fallback in readable grammar" \[hist-silentpc:fd13bc5f:h245\]
- Rationale: "well, maybe not about urbit. i think that guy is still persona non grata" \[hist-silentpc:fd13bc5f:h255\]
- Precedent: ABNF (chosen; named by author): starting point; extended and made nicer \[hist-silentpc:fd13bc5f:h207\]
- Precedent: yacc (chosen; named by author): jets for speed equal to that of yacc \[hist-silentpc:fd13bc5f:h207\]
- Precedent: Urbit (rejected; named by author): dropped from the paper \[hist-silentpc:fd13bc5f:h255\]
- Evidence: USENIXSUBMISSION.md:1 "HyperBNF: Compact, Fast Configuration Parsers from Extended ABNF"; sections 4 (lexing into the parser), 6 (evaluation), 8 "Conclusion and future research"; grep for we/our/naive/simply/urbit finds none; PAPER.md absent
- Doc differs: USENIXSUBMISSION.md:372 says "the rule a human already assumes" (one "assumes" remains; the line numbers of the decision are of an older text)

### hbnf versus obconf: distinction and naming
- Status: DONE — obconf is the name everywhere and kept distinct from hbnf (latest decision 2026-10-08 \[silentpc-opusplan:34019d9b:99#1\])
- Decided: 2026-10-08 decided: "it is obconf not oconf (the OpenBSD server configuration style)" \[silentpc-opusplan:34019d9b:99#1\]
- Rationale: "hbnf was a project to implement oconf as pleasantly as possible for a project that needed a config file. this exposed how bad the state of parser generating is." \[silentpc:c14a13ff:j8386\]
- Rationale: "oconf is hte grammar; hbnf is the grammar language. don't mix up the two." \[silentpc:c14a13ff:j14131\]
- Rationale: "noone talks about parse.y style, it isn't a thing" \[silentpc:c14a13ff:j14039\]
- Precedent: parse.y (rejected; named by author): not a real term; use "OpenBSD configuration style" instead \[silentpc:c14a13ff:j14039\]
- Precedent: OpenBSD configuration style (obconf) (chosen; named by author): the name is obconf, not oconf \[silentpc-opusplan:34019d9b:99\]
- Evidence: grep -i oconf (not obconf) over \*.md finds none; README.md:51-54 "The OpenBSD configuration file format was the initial inspiration ... in obconf.md"; grammars/obconf\*.hbnf

### obconf wording in the docs
- Status: DONE — docs say OpenBSD's default format for new projects, not daemons (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j52045#1\])
- Decided: 2026-10-24 changed: Instead of daemons say "the config file format that OpenBSD uses by default for new projects". \[silentpc-opusplan:4a4c3021:j52045#1\]
- Rationale: called the assistant's wording "slop": "the wish to implement obconf ... is what inspired it" \[silentpc-opusplan:4a4c3021:j51919\]
- Precedent: OpenBSD httpd, relayd, ntpd (considered; named by author): named as flagship programs using the config file type \[silentpc-opusplan:4a4c3021:j51777\]
- Evidence: RFCPLAN.md:580 "obconf (the config file format OpenBSD uses by default for new projects; built, grammars/obconf.hbnf)"; README.md:51 "The OpenBSD configuration file format was the initial inspiration"
- Doc differs: README.md:54 and README.md:12 still say "the daemons it was written for" / "the daemons' own sys/queue.h" (literal use of the word, not the format's description)

## 01 Goals and priorities

### Capability: wire protocols and JSON
- Status: DONE — JSON grammar works and wire/bit-field layer is built (latest decision 2026-10-24 \[silentpc-opusplan:cfaaa115:1163#1\])
- Decided: 2026-10-24 decided: "i thought hbnf already had a json parser that worked, why would I fix it" \[silentpc-opusplan:cfaaa115:1163#1\]
- Rationale: "hbnf can parse any wire protocol and has all the regex nice things in there" \[silentpc:331154d6:1019\]
- Rationale: "irc can be expressed in hbnf without jets" \[silentpc:331154d6:j1819\]
- Rationale: "it should be very usable right now as is" \[silentpc:331154d6:j2243\]
- Evidence: corpus/json/json.hbnf (README.md:108 "JSON in 14 rules, checked against Python's json"); WIRE.md; tests/wire.sh

### Closing the speed gap with rapidyaml and simdjson
- Status: DONE — hbnf is ahead of rapidyaml and level with simdjson on tape (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:77361#1\])
- Decided: 2026-10-29 decided: "doing apples to apples, how does tape json compare to simdjson." \[silentpc-opusplan:4a4c3021:77361#1\]
- Rationale: "why would you leave out a 1% speed increase?" \[silentpc-opusplan:4a4c3021:65734\]
- Rationale: "doing apples to apples, how does tape json compare to simdjson." \[silentpc-opusplan:4a4c3021:77361\]
- Precedent: simdjson (chosen; named by author): tape JSON compared apples to apples \[silentpc-opusplan:4a4c3021:77361\]
- Precedent: rapidyaml (considered; named by assistant, not taken up): YAML gap named as candidate to keep closing \[silentpc-opusplan:4a4c3021:65734\]
- Evidence: bench/results/libs.md:5-6 (tape 2.2 ms against simdjson 2.3 ms), libs.md:31-33 (YAML tape 7.5 ms against rapidyaml 21 ms); README.md:323-326 "close to the SIMD parser simdjson ... both are ahead of rapidyaml"
- Doc differs: TODO.md:11 says simdjson and rapidyaml read 20-35% high on the busy machine; hbnf rows are upper bounds; a quiet rerun is pending. AVX2/AVX-512 (potential) not in the repository (TODO.md:89 mentions only an SSE2 loop)

### Compact C grammar
- Status: DONE — C grammars have fewer rules than the yacc grammars they are checked against (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:75557#1\])
- Decided: 2026-10-29 decided: "inlining is ok but does it make the rule more readable? shorter rules is also desirable" \[silentpc-opusplan:4a4c3021:75557#1\]
- Rationale: "c parser speedup is nice, but more important is fewer rules/tokens while being readable" \[silentpc-opusplan:4a4c3021:75290\]
- Rationale: "inlining is ok but does it make the rule more readable? shorter rules is also desirable" \[silentpc-opusplan:4a4c3021:75557\]
- Rationale: "c grammars small shorter fewer rules and tokens compared to yacc" \[silentpc-opusplan:4a4c3021:j74683\]
- Precedent: yacc (chosen; named by author): the baseline to have fewer rules and tokens than \[silentpc-opusplan:4a4c3021:j74683\]
- Precedent: W-grammar (rejected; named by author): "didn't give much win" for C grammar size \[silentpc-opusplan:4a4c3021:j74683\]
- Precedent: table syntax (rejected; named by author): "looked gross, unfit" \[silentpc-opusplan:4a4c3021:j74683\]
- Evidence: README.md:176-188 c79 51 rules against 55, gnu99 80 against GCC 172, pcc99 79 against 84; corpus/c/c79.hbnf, gnu99.hbnf

### Comparison with yacc
- Status: DONE — W-grammar hyper-rules and IMP are studied and used (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:48436#1\])
- Decided: 2026-10-23 decided: "I mean w-grammar and IMP" as what to learn from \[silentpc-opusplan:4a4c3021:48436#1\]
- Rationale: "as capable as yacc means it can generate parsers and even a c compiler, not that it should copie yaccs actual features" \[silentpc-opusplan:4a4c3021:48397\]
- Rationale: wants to learn from HyperBNF and IMP "to do the same things as yacc, but smarter, terser, nicer" \[silentpc-opusplan:4a4c3021:48397\]
- Precedent: yacc (considered; named by author): capability to match, features not to copy \[silentpc-opusplan:4a4c3021:48397\]
- Precedent: W-grammar (chosen; named by author): "I mean w-grammar and IMP" as what to learn from \[silentpc-opusplan:4a4c3021:48436\]
- Precedent: IMP (chosen; named by author): "I mean w-grammar and IMP" as what to learn from \[silentpc-opusplan:4a4c3021:48436\]
- Evidence: README.md:25-26 "an homage to the W-grammar and its hyper-rules"; METACOMPILERS.md ("W-grammars", IMP72); COMPILER-COMPILER.md "Non-goals" (no yacc features copied); ABNF.md:353 hyperrules \`:=\`
- Doc differs: README.md:63 lists corpus/imp72 as "cancelled as a target: IMP72 will get its own compiler"

### Compiler compiler
- Status: DONE — visitor and fold generated per rule (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h260#1\])
- Decided: 2026-09-22 approved-proposal: "go the visitor/fold route" \[hist-silentpc:fd13bc5f:h260#1\]
- Precedent: yacc (considered; named by author): compared on human comprehension and ease of modification \[726:2\]
- Precedent: EBNF (considered; named by author): compared with hbnf for usability \[726:2\]
- Precedent: ABNF (considered; named by author): hbnf already includes the abnf primitives for byte-precise wire work \[726:2\]
- Evidence: TUTORIAL.md:175-176 "visit, parent before children \| \`visit\_\<rule\>\` ... rebuild, children first \| \`map\_\<rule\>\` / \`fold\_\<rule\>\` (\`Visitor\`, \`Folder\`)"; COMPILER-COMPILER.md (the yacc conveniences question is answered as non-goals)
- Doc differs: TUTORIAL.md:175 says the Ada column is "none yet" for visit/fold

### Correctness first
- Status: DONE — the work since 2026-11-04 is conformance first (XML 34 of 34), speed second (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:94706#1\])
- Decided: 2026-11-04 decided: "fix hbnf to be more correct. correctness first, then speed." \[silentpc-opusplan:4a4c3021:94706#1\]
- Rationale: "first make it correct, then make it fast. premature optimization is the root of all evil. (Knuth)." \[578:124\]
- Rationale: "as we get more accurate and add more features, loss of performance is predictable" \[578:155\]
- Precedent: Knuth, premature optimization (chosen; named by author): quoted as the rule \[578:124\]
- Precedent: Sitaker's metacircular compiler (considered; named by author): quoted for the update to history.md \[578:124\]
- Evidence: bench/results/xml-conformance.md; TODO.md:20 "hbnf 34 of 34, 11 of 11 with the real generator"; commit acadd88 2026-11-04 "XML in C: 5.55 to 3.46 ms ..." after the grammar was made conforming
- Left: the open correctness items are tracked under Priority list

### Name: HBNF and HyperBNF
- Status: DONE — docs name HyperBNF as the language and hbnf as the program, and list ybnf among the dialects as ours (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:51441#1\])
- Decided: 2026-10-24 decided: Wording rule: "HyperBNF is ours"; ybnf was to be silently included in the list of bnf, ebnf, abnf, ybnf; not framed as somebody else's notation. \[silentpc-opusplan:4a4c3021:51441#1\]
- Rationale: "the project and grammar language is hyperbnf in homage to w-grammar and its hyper rules"; hbnf just the program name \[silentpc-opusplan:4a4c3021:j50678\]
- Rationale: "A grammar written in YBNF is somebody else’s notation; HyperBNF is ours." \[silentpc-opusplan:4a4c3021:51441\]
- Precedent: W-grammar (chosen; named by author): HyperBNF named in homage to it \[silentpc-opusplan:4a4c3021:j50678\]
- Precedent: yacc (considered; named by author): ybnf is the yacc grammar, ours is hyperbnf \[silentpc-opusplan:4a4c3021:j50844\]
- Precedent: bnf, ebnf, abnf, ybnf (considered; named by author): to be silently included in the dialect list \[silentpc-opusplan:4a4c3021:51441\]
- Evidence: README.md:24-27 "HyperBNF is a grammar language, and \`hbnf\` is the program that reads it ... superset of BNF, EBNF, ABNF and YBNF"; ABNF.md:353 "\`dialect bnf \| ebnf \| abnf \| ybnf \| hbnf\`"; ABNF.md:3 "named for Hartmeier, Brauer, Norby and Floeter, and read as HyperBNF"
- Doc differs: README.md:27 says "YBNF (yacc's grammar language)", which names ybnf as yacc's notation, as the 2026-10-23 decision allowed; no "ybnf is ours" framing found

### Never let the general case penalize the fast case
- Status: DONE — optimizations were fixed rather than reverted and the shared reading is switchable only for lint (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:63091#1\])
- Decided: 2026-10-27 decided: Asks whether "you are fixing rather than reverting the optimizations, right?" - expects fixing, not reverting. \[silentpc-opusplan:4a4c3021:63091#1\]
- Rationale: "never making a slow general case penalize a faster special case." \[silentpc-opusplan:4a4c3021:j54836\]
- Evidence: commit e3025f7 2026-10-27 "rules fill their caller's output directly, small rule bodies are inline"; commit acadd88 "unwind only at trial points"; TODO.md:33-41 further speed items stay as queued work
- Left: principle, no single artifact; no counter-example found

### Pay only for what is used
- Status: DONE — unwind is done only at trial points, found by analysis (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:94204#1\])
- Decided: 2026-11-04 decided: "try the static analysis now" for pay-for-use unwind; asks what the time limit was \[silentpc-opusplan:4a4c3021:94204#1\]
- Rationale: "shouldn't we only pay for what we use? shouldn't we only do overlay and unwind if they are needed?" \[silentpc-opusplan:4a4c3021:93957\]
- Rationale: "remember the policy, we only pay for what we use." \[silentpc-opusplan:4a4c3021:j81605\]
- Precedent: COBOL, ALGOL 68, C++ grammars (chosen; named by author): to add, compact and "as much like pure bnf as possible" \[silentpc-opusplan:4a4c3021:j81605\]
- Precedent: GLR (chosen; named by author): "we can do full glr" under the pay-for-use policy \[silentpc-opusplan:4a4c3021:j81605\]
- Evidence: commit acadd88 2026-11-04 "XML in C: 5.55 to 3.46 ms ...; unwind only at trial points"; TODO.md:89 lists "unwind marks" among C-only features to port
- Left: port to Rust, Zig, Ada, tree-sitter is queued (TODO.md:89)

### Purpose and goal
- Status: DONE — fewer rules and lines than yacc grammars, errors with caret, comments kept, obconf grammars built (latest decision 2026-10-21 \[silentpc-opusplan:4a4c3021:j38973#1\])
- Decided: 2026-10-21 decided: "our goal is to be way easier than ycc, and more powerful too." \[silentpc-opusplan:4a4c3021:j38973#1\]
- Rationale: "our goal is to be way easier than ycc, and more powerful too." \[silentpc-opusplan:4a4c3021:j38973\]
- Rationale: "helpful error messages and source text round-tripping" \[silentpc:c14a13ff:8114\]
- Rationale: "the whole point of hbnf to make an obconf parser is so our tradingharness.conf can tell you where all the bits of data live" \[silentpc:ae5c3348:j840\]
- Precedent: yacc (considered; named by author): benchmark to be easier and more powerful than \[silentpc-opusplan:4a4c3021:j38973\]
- Evidence: README.md:168-200 notation table (gnu99 80 rules against GCC's 172, lines saved 87%); WHY.md:105-112 "Helpful errors ... Comments are preserved and come back out"; grammars/obconf\*.hbnf

### RFC friendliness
- Status: DONE — RFC and ALGOL 60 grammars read near verbatim, dialect directives present (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:j50648#1\])
- Decided: 2026-10-23 decided: "for algol60 we can probably implement that directly"; "our ybnf ebnf abnf and bnf dialect directives are fine" \[silentpc-opusplan:4a4c3021:j50648#1\]
- Rationale: "translate them into hyperbnf in the most optimal form we can as far as lines of code goes, then optimize the resulting parse code" \[silentpc-opusplan:4a4c3021:j50593\]
- Rationale: "I don't want to lose theh performance benefits of recursive descent" \[704:8\]
- Precedent: ALGOL 60 (chosen; named by author): "we can probably impleent that directly" \[silentpc-opusplan:4a4c3021:j50648\]
- Precedent: ABNF (chosen; named by author): RFC grammars taken as they are \[silentpc-opusplan:4a4c3021:j50593\]
- Precedent: ybnf/ebnf/abnf/bnf dialect directives (chosen; named by author): "are fine" \[silentpc-opusplan:4a4c3021:j50648\]
- Precedent: recursive descent (chosen; named by author): performance benefits not to be lost \[704:8\]
- Evidence: corpus/algol60/ (README.md:168 ALGOL 60 BNF 108 rules to 47); ABNF.md:353 dialect directives; COMPILER-COMPILER.md "RFC copy-paste ... should compile almost verbatim"; corpus/rfc/ README

### Round tripping
- Status: DONE — docs say a grammar can round-trip, not hbnf itself; Jeff Fox is described as Chuck Moore's close friend (latest decision 2026-10-02 \[silentpc:c14a13ff:19056#1\])
- Decided: 2026-10-02 decided: "fix the same in WHY.md and README.md too"; Jeff Fox was a close personal friend of Chuck Moore \[silentpc:c14a13ff:19056#1\]
- Rationale: "hbnf does not round trip"; instead "hbnf allows its grammars to easily do round tripping, which makes pretty printing and debug printouts very simple and pleasant" \[silentpc:c14a13ff:19009\]
- Precedent: Jeff Fox (Forth) (considered; named by author): close personal friend of Chuck Moore, inventor of Forth \[silentpc:c14a13ff:19056\]
- Evidence: HISTORY.md:1095-1096 "a close personal friend of Chuck Moore"; WHY.md:109 "a grammar that wants to can round-trip exactly"; not found: any "hbnf round trips" claim in README.md

### Scope: a meta compiler, hooks in any language
- Status: DONE — stated in the design notes (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j9344#1\])
- Decided: 2026-10-17 decided: Hooks not only assembly "even raw machine language bytes." \[silentpc-opusplan:4a4c3021:j9344#1\]
- Rationale: "hbnf seeks to be a meta compiler, not a \\"narrow niche\\" for config files. config files was just the starting point." \[silentpc-opusplan:4a4c3021:j8543\]
- Rationale: "assembler makes it closer to a true metacompiler"; hooks can be any language \[silentpc-opusplan:4a4c3021:j9289\]
- Rationale: "that shape actually would allow us to emit binary machine code" \[hist-silentpc:fd13bc5f:h450\]
- Precedent: META II (considered; named by author): asked to compare with hbnf; design may learn from it \[silentpc-opusplan:4a4c3021:j8543\]
- Precedent: IMP72 (considered; named by author): compared with %scan/%action directives \[silentpc-opusplan:4a4c3021:j8543\]
- Precedent: SNOBOL4 (considered; named by author): compared with hbnf and META II \[silentpc-opusplan:4a4c3021:j8543\]
- Evidence: METACOMPILERS.md:280 "Hooks in any language, and a portable default for the common case"; METACOMPILERS.md:289-294 a true metacompiler's hooks "can be that language's instructions"; WIRE.md writes bytes back
- Left: none for the statement; the machine-code emitter itself (the 2026-09-23 potential) is not built

### Scope: characters, octets, bit fields and real languages
- Status: DONE — characters, octets, bit fields and real languages (C, JS, COBOL, HTML, XML) are all in the repository (latest decision 2026-10-02 \[578:117#1\])
- Decided: 2026-10-02 decided: "I do want to be able to parse actual real programming languages, including those ones that are not \\"regular\\""; initial use is config files, then rfc wire protocols \[578:117#1\]
- Rationale: "I do want to be able to parse actual real programming languages, including those ones that are not \\"regular\\"" \[578:117\]
- Rationale: "we do characters/octets even bitfields and single bits.... all the way up to tokens" \[578:20\]
- Rationale: "all we want is an openbsd config parser" for now, general lexing later \[hist-silentpc:fd13bc5f:h166\]
- Precedent: tree-sitter (considered; named by author): wants hbnf general enough for all the real languages it handles \[578:109\]
- Precedent: parse.y (chosen; named by author): initial use case \[hist-silentpc:fd13bc5f:h166\]
- Precedent: EBNF (considered; named by author): wanted too, for variations within the hbnf family \[hist-silentpc:fd13bc5f:h166\]
- Evidence: WIRE.md "octets and bit fields (\`ttl:8\`, \`version@0:4\`)"; corpus/c/README.md:71 "Typedefs. \`typedef-name = known-type ?! vars\`" (the typedef-vs-struct context); corpus/js, corpus/cobol, corpus/html exist; CONTEXTS.md table "Islands"

### Shipped grammars (JSON, TOML, YAML, obconf)
- Status: DONE — all four grammars are in the repository with test suites (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:51282#2\])
- Decided: 2026-10-24 decided: "hyperbnf ships with json, toml, yaml, and obconf as fundamental gramars that people can drop in and use immediately." \[silentpc-opusplan:4a4c3021:51282#2\]
- Rationale and precedent: none stated in the sources
- Evidence: corpus/json/json.hbnf, corpus/toml/toml.hbnf, corpus/yaml/ (README.md:123-125 toml-test 208 files, YAML suite 308 valid), grammars/obconf.hbnf plus obconf\_\*.hbnf; tests/json-diff.sh, tests/toml.sh, tests/yaml.sh
- Doc differs: README.md:39 says "HyperBNF ships with the basic formats ready to use: JSON, TOML and YAML" (obconf not named there; it is in grammars/ and obconf.md)

### Speed goals against the top parsers
- Status: DONE — fast\_float compiled and compared; simdjson matched on tape JSON (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:77847#1\])
- Decided: 2026-10-29 decided: "go ahead with compiling fast\_float"; look into its per-element work "so all hbnf grammars benefit". \[silentpc-opusplan:4a4c3021:77847#1\]
- Rationale: "I want us to at least match the top performing parsers in those 3 categories toml/yaml/json" \[silentpc-opusplan:4a4c3021:70482\]
- Rationale: "we should optimize those routines the way simdjson does, or better" \[silentpc-opusplan:4a4c3021:j77397\]
- Rationale: copy fast\_float's per-element work "so all hbnf grammars benefit" \[silentpc-opusplan:4a4c3021:77847\]
- Precedent: simdjson (rejected; named by author): "we can ignore simdjson" while finding why others beat hbnf \[silentpc-opusplan:4a4c3021:56942\]
- Precedent: simdjson (chosen; named by author): number conversion and string unescape optimized its way or better \[silentpc-opusplan:4a4c3021:j77397\]
- Precedent: rapidyaml (chosen; named by author): the faster YAML parser to match \[silentpc-opusplan:4a4c3021:70482\]
- Precedent: fast\_float (chosen; named by author): "go ahead with compiling fast\_float" \[silentpc-opusplan:4a4c3021:77847\]
- Precedent: JSON/TOML/YAML libraries (considered; named by author): find why they beat hbnf \[silentpc-opusplan:4a4c3021:56942\]
- Evidence: commit 9031246 "runtime/hbnf\_scalar.h: number and string conversions ... as fast as fast\_float"; bench/scalar.sh; bench/results/libs.md:5-6 "hbnf %emit tape 2.2 ms \| simdjson (DOM) 2.3 ms"; Node JSON.parse 9.6 ms
- Left: none for this subject; a quiet-machine rerun is a TODO.md item

### Speed requirement for large inputs
- Status: DONE — measured at 100,000 and 1,000,000 rules and on the pfctl grammar (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h203#1\])
- Decided: 2026-09-21 decided: "some pf rulesets have over 100,000 rules in them so they need to parse and load fast" \[hist-silentpc:fd13bc5f:h203#1\]
- Rationale and precedent: none stated in the sources
- Evidence: README.md:205-211 "100,000 rules (7.68 MB, the same file for every tool)"; bench/results/hbnf-pfctl.md and bench/results/pfctl\_yacc.md

### String views as the default
- Status: DONE — views are the default in the C backend; \`--no-views\` keeps copies (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:59206#1\])
- Decided: 2026-10-24 decided: "make them the default". \[silentpc-opusplan:4a4c3021:59206#1\]
- Rationale: "how can views hurt, a single char\* and a length does it get any cheaper than that?" \[silentpc-opusplan:4a4c3021:59067\]
- Rationale: "string views... isn't that a principle i told you to follow way back at the beginning of this project?" \[silentpc-opusplan:4a4c3021:j58695\]
- Precedent: string views (chosen; named by author): "make them the default" \[silentpc-opusplan:4a4c3021:59206\]
- Evidence: ABNF.md:353 "a string in the tree is a slice of the input (\`hbnf\_sp(v)\` ... \`--no-views\` keeps the copies"; tests/views.sh

### What hbnf is
- Status: DONE — README states the compiler-compiler framing; obconf.md says obconf is not hbnf (latest decision 2026-10-01 \[silentpc:c14a13ff:j14398#1\])
- Decided: 2026-10-01 decided: "hbnf was invented to allow using oconf with other programs without requiring learning yacc/lex/bison/flex" \[silentpc:c14a13ff:j14398#1\]
- Rationale: "hbnf was invented to allow using oconf with other programs without requiring learning yacc/lex/bison/flex" \[silentpc:c14a13ff:j14398\]
- Rationale: "almost noone uses yacc for anything serious because it is a pain to use" \[silentpc:c14a13ff:8103\]
- Rationale: "without giving up speed, performance, or your favorite programming language" \[silentpc:c14a13ff:8104\]
- Rationale: "readable and pleasant for humans to use; anyone familiar with the rfc series should be able to use it" \[silentpc:c14a13ff:8078\]
- Precedent: yacc/bison (rejected; named by author): hbnf avoids having to learn them \[silentpc:c14a13ff:j14398\]
- Precedent: RFC BNF (chosen; named by author): familiar users should need minimal adjustment \[silentpc:c14a13ff:8078\]
- Precedent: OpenBSD configuration language (oconf) (chosen; named by author): first use case, not hbnf itself \[silentpc:c14a13ff:8078\]
- Evidence: README.md:24-26 "a parser generator (a compiler compiler) that emits a parser and its typed tree in C, Rust, Zig or Ada"; README.md:50-54 "The OpenBSD configuration file format was the initial inspiration"; WHY.md yacc section

## 02 Notation and grammar design

### Alternatives, ordered choice and phrase exceptions
- Status: DONE — union orders found automatically, first-match for IPv4address/host, phrase exceptions and \`\_alt\` in trees built (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j53523#1\])
- Decided: 2026-10-24 decided: "if we can't handle a union of a lot of ordered choices that sounds like a bug in hbnf to me." \[silentpc-opusplan:4a4c3021:j53523#1\]
- Rationale: "if we can't handle a union of a lot of ordered choices that soundsl ike a bug in hbnf to me." \[silentpc-opusplan:4a4c3021:j53523\]
- Precedent: RFC 3986 first-match-wins (host/IPv4address) (chosen; named by assistant, accepted): "yep do that": try alternatives in order \[silentpc-opusplan:4a4c3021:5385\]
- Evidence: RFCPLAN.md:70-86 (decision 1) automaton search for an order, first match followed by what can follow the choice; ABNF.md:219 phrase exception; commits ea279fe, 86ada96 (2026-10-17); ABNF.md:114 \`\_alt\`; tests/factor.sh union ladder "must be accepted without a warning"

### Brace blocks
- Status: DONE — \`{}\` braces carry code blocks and the four emitters exist (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h221#1\])
- Decided: 2026-09-21 changed: "switch to {} braces and do the rust/zig/ada emitters" \[hist-silentpc:fd13bc5f:h221#1\]
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:183 "\`%scan{ … }\`, \`%action{ … }\` ... the spelled-out forms of \`name = { code }\`"; hbnf\_rust.adb, hbnf\_zig.adb, hbnf\_ada.adb; README.md:24 C, Rust, Zig or Ada

### C strings
- Status: DONE — quoted terminals take C escapes (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h104#1\])
- Decided: 2026-09-21 decided: "the c-strings accepted are the full C23 syntax for escaping" \[hist-silentpc:fd13bc5f:h104#1\]
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:173 "C's escapes, octal and \`\\?\` included, which every emitter re-escapes for its target language"; ABNF.md:175 \`'\\x41'\`, \`'\\\\'\`, \`'é'\`; tests/literal.sh
- Left: not checked whether the C23-only escapes (\`\\o{}\`, \`\\u{}\`) are accepted: no mention in ABNF.md

### Case sensitivity
- Status: DONE — \`sensitivity %i\|%s\`, with \`rule-name\` and \`string\` axes, is built (latest decision 2026-09-28 \[704:6#1\])
- Decided: 2026-09-28 decided: Top-of-grammar directive: "sensitivity %i / %s / ( rule-name %i / %s ) / (string %i / %s )" \[704:6#1\]
- Rationale: "case sensitive is the default... just make sure %i works when we want case insensitivity" \[578:70\]
- Precedent: ABNF (chosen; named by assistant, accepted): his sensitivity directive uses %i and %s \[704:6\]
- Precedent: ABNF (chosen; named by assistant, accepted): rule-name axis in his directive \[704:6\]
- Evidence: RFCPLAN.md:120 "\`sensitivity\`, per file, two independent axes"; tests/abnf.sh:507-515 "sensitivity string %i" / "sensitivity rule-name %i"; ABNF.md:243

### Char literals
- Status: DONE — \`'c'\` is one code point as decided (latest decision 2026-09-29 \[578:103#1\])
- Decided: 2026-09-29 decided: Use ',' not ","; "'' is a single char", an idiom he prefers; may return to a comma rule later \[578:103#1\]
- Rationale: "'' is a single char", "using '' for single chars rather than \\"\\" is an idiom i prefer"; "looks better" \[578:103\]
- Evidence: ABNF.md:175 "\`'c'\` (character literal) ... one code point"; RFCPLAN.md:352-356 POSIX \`'\|'\` is "hbnf's \`'c'\`"
- Doc differs: CONTEXTS.md:909 (section 26 item 1, "the user", 2026-11-03) and TODO.md:44 "\`'c'\` is \`"c"\`" queue a change that makes the two spellings one thing; not built

### Character-level lexing
- Status: DONE — character rules, ranges and UTF-8 scanners in all backends (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h235#1\])
- Decided: 2026-09-21 decided: "what do you mean character level composition is gone? I never agreed to that!" \[hist-silentpc:fd13bc5f:h235#1\]
- Rationale: "if chars are tokens, then yacc should work all the way down." \[hist-silentpc:fd13bc5f:h186\]
- Precedent: yacc/lex split (considered; named by author): asked why lexing was separated from yaccing \[hist-silentpc:fd13bc5f:h186\]
- Precedent: RBNF (rejected; named by author): "don't bother with rbnf" \[704:16\]
- Precedent: BNF spellings (chosen; named by author): made equivalent and all allowed \[704:16\]
- Evidence: CHARLAYER.md ("character rules, numeric terminals and UTF-8"); grammars/ascii.hbnf; ABNF.md:128 "there is no token array and no fixed lexer"; CHARLAYER.md and RFCPLAN.md:11 "UTF-8 scanners in all four"

### Choice and alternation operators
- Status: DONE — \`\|\` ordered, \`/\` union, and shared prefixes are factored (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:3880#1\])
- Decided: 2026-10-06 changed: "add the prefix factoring on top"; do not make people rewrite when "we can mechanically rewrite ourselves"; a two codepoint lookahead limitation is "surprising" \[silentpc-opusplan:4a4c3021:3880#1\]
- Rationale: "use \| instead of / for concat, in line with other BNF dialects" \[578:64\]
- Rationale: "i don't want to make people rewrite when we can mechanically rewrite ourselves; this is about human readable syntax, and principle of least astonishment" \[silentpc-opusplan:4a4c3021:3880\]
- Rationale: "not sure why ABNF chose it, breaking compat with everyone else" \[578:83\]
- Precedent: Other BNF dialects (chosen; named by author): \| for choice \[578:64\]
- Precedent: ABNF (considered; named by author): later kept as union, \| as ordered choice \[578:89\]
- Precedent: RFC BNF (considered; named by author): asked how compatible ABNF is with it \[704:4\]
- Evidence: RFCPLAN.md:2921 "\`HBNF\_Lookahead.Factor\` works out once which adjacent ... \`--no-factor\` writes the plain chain"; tests/factor.sh "Alternatives that begin with the same elements are read once"; ABNF.md:221 "\`\|\` ordered choice; \`/\` union"
- Doc differs: RFCPLAN.md:92 (amended 2026-10-06) says "The automaton check needs no factoring" for ordering a union, while factoring is a separate built step

### Comments
- Status: DONE — the Ada backend writes comments out as Ada comment blocks (latest decision 2026-10-02 \[silentpc:c14a13ff:16737#1\])
- Decided: 2026-10-02 approved-proposal: "finish the Ada backend comment port" \[silentpc:c14a13ff:16737#1\]
- Rationale: "comments are not whitespace. they don't turn into code, but they are their own thing" \[silentpc:c14a13ff:j16162\]
- Rationale: "comments should be their own token and then astbnf should decide where the comments belong" \[hist-silentpc:fd13bc5f:h119\]
- Rationale: "the nice comment round tripping should be a characteristic of the grammar, not hbnf" \[silentpc:c14a13ff:j15910\]
- Precedent: yacc (chosen; named by author): spirit: output .c compiled to the metal, no intermediary ast \[hist-silentpc:fd13bc5f:h70\]
- Evidence: hbnf\_ada.adb:830-832 "Append Text as an Ada comment block, one \\"-- \\" per line"; WHY.md:110 "Comments are preserved and come back out in the right places"; commit 36a275b "comments are tree nodes"

### Common grammar files (common, obconf, ascii)
- Status: DONE — ascii.hbnf, common.hbnf and obconf.hbnf exist with the named punctuation (latest decision 2026-10-02 \[silentpc:c14a13ff:19473#1\])
- Decided: 2026-10-02 decided: "add the other named printable punctuation to ascii.hbnf" \[silentpc:c14a13ff:19473#1\]
- Rationale: "we really only want ascii.hbnf for the non-printable characters, DEL ESC SP ENTER BEL NAK etc" \[silentpc:c14a13ff:j18687\]
- Evidence: grammars/ascii.hbnf EXCLAIM DQUOTE HASH ... LBRACKET (named printable punctuation); grammars/common.hbnf:8 \`include "ascii.hbnf"\`; grammars/obconf.hbnf
- Doc differs: the 2026-10-02 line "include all ascii.hbnf stuff in common; ascii.hbnf only for non-printable" \[silentpc:c14a13ff:j18687#1\] conflicts with the later punctuation line; the repository follows the later one

### Contexts, islands and grammar switching
- Status: DONE — the stated rule (no optimization lost by switching) is in the design and phase 1 of islands and switch is built; later phases are separate open items (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:85949#1\])
- Decided: 2026-11-03 decided: "grammars shouldn't lose optimization by switching; optimization only goes away if it becomes invalid for some other reason." \[silentpc-opusplan:4a4c3021:85949#1\]
- Rationale: "grammars shouldn't lose optimization by switching; optimization only goes away if it becomes invalid for some other reason." \[silentpc-opusplan:4a4c3021:85949\]
- Rationale: Wants switching syntax that modifies "stock BNF as little as possible" so it feels "natural, and is not shocking or supringing to a human" \[silentpc-opusplan:4a4c3021:83530\]
- Precedent: stock BNF (chosen; named by author): modify it as little as possible, extend semantics a tiny bit \[silentpc-opusplan:4a4c3021:83530\]
- Precedent: COBOL embedding JCL, SQL, CICS (considered; named by author): embedded languages and the picture clause DSL motivate switching syntax \[silentpc-opusplan:4a4c3021:83530\]
- Precedent: yacc (rejected; named by author): "yacc isn't hbnf"; no dialect clash \[silentpc-opusplan:4a4c3021:84827\]
- Precedent: Raku slangs (considered; named by assistant, accepted): asked to verify and add the comparison to METACOMPILERS.md \[silentpc-opusplan:4a4c3021:85182\]
- Evidence: CONTEXTS.md:717 "\*\*No optimization is given up by switching\*\*"; CONTEXTS.md:8-9 islands \`include "f" as x\` and \`=\> grammar(x)\` built (aff3de9), C, Rust, Zig, Ada; CONTEXTS.md:733 \`skip\_ws\` one dispatch on the current grammar
- Doc differs: CONTEXTS.md:9 "built, phase 1: white space only ... tree-sitter refuses a switch"; TODO.md:79-80 switch phase 2 and 3, labels, bounded island not built

### Dotted words
- Status: DONE — dotted runs are single words (latest decision 2026-10-01 \[silentpc:c14a13ff:9583#1\])
- Decided: 2026-10-01 decided: "extend the model, keep dotted runs as single words" \[silentpc:c14a13ff:9583#1\]
- Rationale: "don't we have regex type constructs that can handle this?" (chose to extend the model, keep dotted runs single words) \[silentpc:c14a13ff:9583\]
- Precedent: regex type constructs (considered; named by author): asked whether they could handle dotted runs \[silentpc:c14a13ff:9583\]
- Evidence: grammars/obconf.hbnf:25 \`wordchars = ALPHA \| DIGIT \| "\_" \| "-" \| "."\`; grammars/obconf.hbnf:30-39 \`word = word\_start \*wordchars \| 1\*DIGIT word\_non\_digit \*wordchars\` (the digit-led dotted run)

### Expr rule
- Status: DONE — left recursion is read as a loop and the daemon parsers are drop-in (latest decision 2026-10-03 \[578:163#1\])
- Decided: 2026-10-03 decided: "hbnf should allow expr  term '+' term; if it doesn't, that is a bug in the design"; still must emit drop-in parsers for openbsd parse.y daemons \[578:163#1\]
- Rationale: "hbnf should allow expr  term '+' term; if it doesn't ,that is a bug in the design"; must still emit drop-in parsers for OpenBSD parse.y daemons \[578:163\]
- Precedent: parse.y (chosen; named by author): emit drop-in parsers for them \[578:163\]
- Evidence: tests/leftrec.sh "Left recursion ... which hbnf reads as a loop"; tests/daemons.sh; README.md:43 "Parameterised rules, back-references and context sets carry what a yacc grammar leaves to"; not found: a test named for \`expr = term '+' term\`

### Extensions beyond ABNF and code blocks
- Status: DONE — code blocks are in, and the docs state the aim of the smallest total ruleset (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j85318#1\])
- Decided: 2026-11-03 decided: hbnf has always had { code } blocks; "we aren't against code"; goal is to minimize total ruleset size, lines, chars, tokens, rules, so code should further that goal. \[silentpc-opusplan:4a4c3021:j85318#1\]
- Rationale: "we aren't against code, we just want to minimize total ruleset size, lines, chars, tokens, rules, so code should be used in a way that furthers that goal." \[silentpc-opusplan:4a4c3021:j85318\]
- Precedent: ABNF (considered; named by author): has no {} prologue/epilogue blocks nor %scan{} %action{} \[silentpc:c14a13ff:j8913\]
- Precedent: yacc (considered; named by author): asked how %action fails to do what yacc actions do \[594:22\]
- Evidence: METACOMPILERS.md:267 "the aim is the smallest total ruleset, in lines, characters, tokens and rules, and code belongs where it shortens that"; ABNF.md:183 \`%scan{ … }\`, \`%action{ … }\`; ABNF.md section 5 "What HyperBNF adds"

### Include and overrides
- Status: DONE — \`include\` is built and a later \`=\` overrides without error (latest decision 2026-09-29 \[578:89#3\])
- Decided: 2026-09-29 decided: "no need for cross file override"; "second = is always an override, not an error" \[578:89#3\]
- Rationale: "boilerplate library of rules/definitions/jets we can "include" then just do the stuff specific to our program" \[hist-silentpc:fd13bc5f:h253\]
- Rationale: "abstract out all the common rules so each daemon includes the common core" \[hist-silentpc:fd13bc5f:h265\]
- Rationale: "second = is always an override, not an error" \[578:89\]
- Precedent: yacc (considered; named by author): asked whether yacc has an include statement \[hist-silentpc:fd13bc5f:h253\]
- Evidence: RFCPLAN.md:100 "A later \`=\` overrides ... the rule keeps its place"; ABNF.md:342 "A later \`=\` overrides: a file's own rule overrides an included one"; tests/include/ (once.hbnf, late.hbnf, prefix\_clash.hbnf); \`%grammar "foo.hbnf"\` (potential 2026-10-06) not built
- Doc differs: RFCPLAN.md:100 says the override works "in the same file or another" (cross-file override is supported, though he said it was not needed)

### Input encoding and tokens
- Status: DONE — the fixed token array is gone; a rule that is only text is one token scanned at the position (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:12124#1\])
- Decided: 2026-10-17 approved-proposal: "start on the tokens-everywhere change" \[silentpc-opusplan:4a4c3021:12124#1\]
- Rationale: "grammars operate on tokens, and tokens are sequences of octets at the lowest level, a char is either a unicode codepoint or an octet" \[silentpc-opusplan:4a4c3021:j6618\]
- Rationale: "rules to be utf8 but the input stream can by bytes or codepoints, it should be able to choose" \[hist-silentpc:fd13bc5f:h270\]
- Evidence: ABNF.md:275 "A text rule is one token: hbnf builds a deterministic automaton from it"; CHARLAYER.md:3 "The fixed lexer it replaces is gone"; commit d12c75c "docs: tokens and the exception; the plan for tokens everywhere, octets and the prefix"; WIRE.md:64 text is octets read as UTF-8

### Jets (inline functions in the grammar)
- Status: DONE — scanner actions are emitted with the parser, each with a fallback line above (latest decision 2026-10-01 \[silentpc:c14a13ff:j16114#1\])
- Decided: 2026-10-01 decided: "when we emit the parser function we emit the lexing functions too... that is what jets and actions are" \[silentpc:c14a13ff:j16114#1\]
- Rationale: "when we emit the parser function we emit the lexing functions too... that is what jets and actions are" \[silentpc:c14a13ff:j16114\]
- Evidence: ABNF.md:128 "scanner actions as the fast path, each with its character-level fallback written above it"; grammars/README.md:104 "Every jet carries a fallback line above it"; ABNF.md:183 \`%scan{ }\`; METACOMPILERS.md:84

### Keyword table for keywords as values
- Status: DONE — letter-led literals are interned in a keyword table (latest decision 2026-09-24 \[578:60#1\])
- Decided: 2026-09-24 decided: "option 1, keyword table" \[578:60#1\]
- Rationale: accepted from assistant: option 1 is "the only one where "drop-in for parse.y" is something a test can check" \[578:60\]
- Precedent: parse.y (chosen; named by assistant, accepted): drop-in behaviour tested against it \[578:60\]
- Evidence: RFCPLAN.md "Ordering and token tables" (line 416) "\`foo = "bar"\` already goes into a token table ... \`kwid\_t\` enum ... \`kw\_lookup\`"; RFCPLAN.md:115 \`keywords\` is a whole-parser directive

### Language header
- Status: DONE — \`language C\|Rust\|Zig\|Ada\` is read per file and selects the code language (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h213#1\])
- Decided: 2026-09-21 decided: for now just C, but allow as first non-comment in the file a language header "C\|Rust\|Zig\|Ada"; it affects how code is emitted \[hist-silentpc:fd13bc5f:h213#1\]
- Precedent: C (chosen; named by author): "this stage we just go with C" \[hist-silentpc:fd13bc5f:h213\]
- Precedent: Rust, Zig, Ada (considered; named by author): allowed later as header values \[hist-silentpc:fd13bc5f:h213\]
- Evidence: hbnf\_grammar.adb:939 "Find the \`language X\` declaration ... defaults to C"; ABNF.md:342 "\`language C\|Rust\|Zig\|Ada\`"; grammars/obconf\_ldpd.hbnf:16 "language C"
- Doc differs: hbnf\_grammar.adb:945 finds the first word "language" anywhere, not only as the first non-comment; RFCPLAN.md:112 says "\`language\` (the language of the file's code blocks)"

### Lexer folded into the grammar
- Status: DONE — \`int\`, \`str\`, \`word\` are character rules in an included grammar; no fallback lexer in Ada (latest decision 2026-10-01 \[silentpc:c14a13ff:13969#1\])
- Decided: 2026-10-01 decided: "the whole point of doing things in the grammar is to remove code from the ada side": no lexer left as "fallback defaults" \[silentpc:c14a13ff:13969#1\]
- Rationale: "the whole point of doing things in the grammar is to remove code from the ada side of things" \[silentpc:c14a13ff:13969\]
- Rationale: "we don't need a lexer because it is folded in" \[578:22\]
- Precedent: ABNF (considered; named by author): "hbnf isn't abnf... we have extensions" \[578:22\]
- Evidence: grammars/obconf.hbnf:4 "The lexer is grammar here: the core types \`int\`, \`str\` and \`word\` are char rules"; CHARLAYER.md:4 "\`TOK\_\<name\>\` token kinds, \`char\_dispatch\` ... no longer exist"
- Doc differs: the decision of 2026-09-30 \[silentpc:6ec412b3:j66646#1\] named "core.hbnf"; the file is grammars/obconf.hbnf plus common.hbnf (tests/include/core.hbnf is only a test)

### Literals and number syntax
- Status: DONE — C numbers in hbnf's own notation, % forms kept for the abnf dialect (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j87038#1\])
- Decided: 2026-11-03 decided: "numbers take C syntax instead of abnf % syntax" \[silentpc-opusplan:4a4c3021:j87038#1\]
- Rationale: "principle of least astonishment is very important for human readability" (why so much C syntax for literals) \[silentpc:c14a13ff:18071\]
- Precedent: C syntax for numbers and strings (chosen; named by author): "numbers take C syntax" \[silentpc-opusplan:4a4c3021:j87038\]
- Precedent: ABNF (rejected; named by author): "instead of abnf % syntax" \[silentpc-opusplan:4a4c3021:j87038\]
- Precedent: ABNF (considered; named by author): proposed with ranges, to be evaluated for grammar size \[578:64\]
- Evidence: commit 8328962 (CONTEXTS.md status table "Notation \`i"..."\`, \`s"..."\`, \`r"..."\`, C numbers; the \`%\` forms kept for the ABNF dialect only ... built (8328962)"); ABNF.md:353 "\`0x41\`, \`65\`, \`0b1000001\`, \`0x41..0x5A\`"; ABNF.md:175 \`'x'\` literals kept

### Negation
- Status: DONE — \`~\` negation built in all four backends (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:11640#1\])
- Decided: 2026-10-17 approved-proposal: "start on ~ negation" \[silentpc-opusplan:4a4c3021:11640#1\]
- Rationale: "i think negation would be very useful to have a shorthand for" \[silentpc:c14a13ff:9824\]
- Rationale: Accepted from the assistant: ~ is the one symbol whose whole prior art is negation, while ^ would fight three existing readings (chose "~"). \[silentpc:c14a13ff:9886\]
- Rationale: "unary conjunction implies 0 implies negation" \[silentpc:c14a13ff:j9899\]
- Precedent: PEG, regex, SNOBOL (considered; named by author): asked what their bit/byte/char/string matching offers hbnf \[silentpc:c14a13ff:9824\]
- Precedent: regex ^ complement (Perl, MUMPS) (rejected; named by author): liked "^foo" reading, then chose ~ \[silentpc:c14a13ff:9861\]
- Precedent: APL NOT ~ (chosen; named by assistant, accepted): ~x means not x \[silentpc:c14a13ff:9886\]
- Precedent: C bitwise complement ~ (chosen; named by assistant, accepted): ~x is complement \[silentpc:c14a13ff:9886\]
- Evidence: RFCPLAN.md:~270 (decision 11) "Negation is \`~\`. \*Done 2026-10-17\* (tests/schema.sh, in all four backends)"; ABNF.md:351 "\`~x\`, \`\*~x\`"

### Newlines, whitespace and the hidden directive
- Status: DONE — \`hidden\` is built and documented, in both line and declaration forms (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:62044#1\])
- Decided: 2026-10-27 decided: "do hidden next". \[silentpc-opusplan:4a4c3021:62044#1\]
- Rationale: accepted from assistant: declaration form "sits next to the definition and survives renames"; directive line hides rules in included files \[silentpc-opusplan:4a4c3021:58100\]
- Rationale: "nl means newline to distinguish "lines"; a comment attaches to the line if it is trailing" \[hist-silentpc:fd13bc5f:h197\]
- Rationale: "ws is structure" (objecting that hidden rejects structure) \[silentpc-opusplan:4a4c3021:j90734\]
- Precedent: W-grammar (considered; named by author): asked whether declaration-time hidden conflicts with hyper and meta rules \[silentpc-opusplan:4a4c3021:58075\]
- Evidence: ABNF.md:353 "\`hidden nl gap\` (a line) or \`hidden nl = ...\` (at the rule)"; commit 9da3c7f "hidden is documented"; commit e5a464e; tests/hidden.sh
- Doc differs: CONTEXTS.md:917 and TODO.md items 4, 5 say \`hidden\` still accepts only pure-text rules, and "ws is structure" (2026-11-03 potential) needs a silent variant, not built

### Operator table
- Status: DONE — the table was reverted, context parameters kept, and the docs say so (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:74711#1\])
- Decided: 2026-10-29 decided: "revert the table, keep context params, commit when check passes" \[silentpc-opusplan:4a4c3021:74711#1\]
- Rationale: "w-grammar didn't give much win, and table syntax looked gross, unfit" (aim: C grammars with fewer rules and tokens than yacc) \[silentpc-opusplan:4a4c3021:j74683\]
- Precedent: yacc (considered; named by author): size comparison target: fewer rules and tokens \[silentpc-opusplan:4a4c3021:j74683\]
- Precedent: W-grammar (considered; named by author): tried for operator rule count; little gain \[silentpc-opusplan:4a4c3021:74201\]
- Evidence: RFCPLAN.md:2907 "Context parameters; operator tables tried ... \*Set aside:\* a table of binary-operator levels ... the user judged it unfit"; no \`operators\` table construct in ABNF.md

### POSIX BNF and yacc grammars
- Status: DONE — the standard's yacc text is read, with messages for missing token definitions, and measured (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:j50549#1\])
- Decided: 2026-10-23 decided: hbnf need not support posix yacc grammars as cut and paste, just give "how to translate" error messages; translate them into hyperbnf and measure fewer rules and tokens \[silentpc-opusplan:4a4c3021:j50549#1\]
- Rationale: "didn't mean hbnf should support them as direct cut and pastes, just give 'how to translate' error messages", then measure fewer rules and tokens \[silentpc-opusplan:4a4c3021:j50549\]
- Rationale: Alterations should be "of kinds we can emit as helpful error messages pointing to correct solutions" \[silentpc:c14a13ff:j20893\]
- Precedent: POSIX BNF / yacc grammars (chosen; named by author): translate to hyperbnf with how-to-translate messages \[silentpc-opusplan:4a4c3021:j50549\]
- Precedent: POSIX shell grammar (chosen; named by author): test case \[silentpc:c14a13ff:j20894\]
- Precedent: ::= := = and (\* \*) /\* \*/ comments (chosen; named by author): support alongside ; comments \[578:130\]
- Evidence: corpus/posix/shell.md "\`shell.y\` ... the one in \`posix-shell-1.y\` as the standard prints it and included unchanged"; ABNF.md:232 "a token that nothing defines is reported once with how to write it (\`DLESS = "\<\<"\`)"; corpus/posix/shell-native.hbnf; bench/results/parsey.md
- Doc differs: corpus/posix/shell.md reads yacc as pasted, more than "need not support cut and paste"

### Parse.y examples
- Status: DONE — parse.y daemon grammars and the POSIX yacc grammar are translated and compared (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h195#1\])
- Decided: 2026-09-21 decided: wants examples translating parse.y to hbnf; disputes lexer "noise": "we need the right lexer/parser boundary" \[hist-silentpc:fd13bc5f:h195#1\]
- Rationale and precedent: none stated in the sources
- Evidence: grammars/obconf\_ntpd.hbnf, obconf\_pfctl.hbnf (nine daemons, tests/daemons.sh); corpus/posix/shell.y; bench/parsey.py; README.md:144 "their grammars against \`parse.y\` (\[parsey\](bench/results/parsey.md))"

### Pattern features (phrases, end splice, plural, join)
- Status: DONE — \`phrases(...)\` pattern arguments and the \`+\` join are built and used in COBOL (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:86354#1\])
- Decided: 2026-11-03 decided: "build the two pattern features, use + for the join" \[silentpc-opusplan:4a4c3021:86354#1\]
- Rationale: "wouldn't that allow a lot of such compression?" (asked of regex support, after the phrase and END- savings) \[silentpc-opusplan:4a4c3021:86330\]
- Evidence: 09b966c "Rules that take a pattern, and a join of literals: phrases("SIZE" "ERROR"), "END-" + K"; CONTEXTS.md:10; corpus/cobol/cobol.hbnf:308 \`phrases(W) :=\`
- Doc differs: CONTEXTS.md:19 phase 3 (phrase variants in \`ast\`, the tape case) "decided design; not built", which is the approved 85990/86079 follow-up, outside the Now line

### Percent prefix and suffix
- Status: DONE — no \`%\` suffix; plain multiplier only, as decided (latest decision 2026-09-30 \[silentpc:6ec412b3:67001#1\])
- Decided: 2026-09-30 changed: "we'll leave % alone until the other hbnf sesh is done, for now just straight multiplier" \[silentpc:6ec412b3:67001#1\]
- Rationale: "8% gets stored in the tree as a struct so representation round trips, but it is actually used as 0.08" \[silentpc:c14a13ff:j3202\]
- Rationale: "we'll leave % alone until the other hbnf sesh is done, for now just straight multiplier" \[silentpc:6ec412b3:67001\]
- Precedent: Common Lisp #' (considered; named by author): "% is to hbnf what #' is to common lisp" \[silentpc:6ec412b3:j32167\]
- Evidence: not found: a \`pct = number '%'\` rule or \`%\` suffix in README.md, RFCPLAN.md, ABNF.md; ABNF.md:353 \`%x\`/\`%d\` forms are refused in hbnf's own notation (replaced by \`0x41\`, \`i"…"\`; kept for \`dialect abnf\`)
- Doc differs: CONTEXTS.md:23 (decision of 2026-11-02) retires the \`%\` forms in hbnf's own notation, beyond "leave % alone"

### Preamble and epilogue, prose values and rbnf
- Status: DONE — \`\<prose-val\>\` is built with file:line:col and a caret; rbnf was dropped (latest decision 2026-09-29 \[578:93#1\])
- Decided: 2026-09-29 approved-proposal: "i especially like \<prose-val\> support"; caret points at "you still need to finish thihs part" \[578:93#1\]
- Rationale: prose-val is "better than putting XXX you are not expected to understand this in theh comments"; reader points with a caret \[578:93\]
- Precedent: ABNF (chosen; named by assistant, accepted): "i especially like \<prose-val\> support" \[578:93\]
- Precedent: RBNF (rejected; named by assistant, accepted): "don't bother with rbnf" \[704:16\]
- Precedent: "you are not expected to understand this" comments (rejected; named by author): cited as the worse alternative to prose-val \[578:93\]
- Evidence: RFCPLAN.md:9 (decision 9) "\`\<prose-val\>\` reads as a rule nobody has written yet: generation stops with \`file:line:col\`"; hbnf\_grammar.adb:9224 "not written yet, which Check\_Prose reports"; tests/abnf.sh:522 "== \<prose-val\> =="; not found: "rbnf" in \*.md and hbnf\_grammar.adb (consistent with the 2026-09-29 rejection \[704:16#1\])

### RFC ebnf and obsolete forms
- Status: DONE — obsolete RFC forms are accepted and ebnf mistakes get messages (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:5279#1\])
- Decided: 2026-10-06 decided: Obsolete forms: "support them unless you have a good reason not to" \[silentpc-opusplan:4a4c3021:5279#1\]
- Precedent: EBNF (considered; named by author): some RFC ebnf may be incorrect; explain why \[silentpc-opusplan:4a4c3021:j4381\]
- Precedent: ABNF (considered; named by author): "octet is actually a byte, by definition" \[silentpc-opusplan:4a4c3021:5279\]
- Evidence: corpus/rfc/rfc5322-1.hbnf (the obs- rules of RFC 5322 kept); ABNF.md:219 "under \`dialect ebnf\` \`? words ?\`: a rule nothing defines, 'not written yet', with the rule it probably means"; not checked in detail: whether each incorrect-ebnf message explains WHY

### Readability and syntax principles
- Status: DONE — notation reads like the RFC notation, as a superset of ABNF (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j4131#1\])
- Decided: 2026-10-06 decided: Part of the point of hbnf is "comfortable abstractions" making rules clearer for humans "while still being compilable for the computer" \[silentpc-opusplan:4a4c3021:j4131#1\]
- Rationale: "part of the point of hbnf is to have comfortable abstractions that let us make the rules even more clear and understandable for humans, while still being compilable for the computer" \[silentpc-opusplan:4a4c3021:j4131\]
- Rationale: "i want something immediately readable to anyone familiar with rfc ebnf" \[hist-silentpc:fd13bc5f:h80\]
- Rationale: "i don't plan to be limited to abnf, rather, a superset" \[704:14\]
- Precedent: ABNF (chosen; named by author): hbnf is a superset of it \[704:14\]
- Precedent: EBNF (chosen; named by author): notation must read immediately to those who know it \[hist-silentpc:fd13bc5f:h80\]
- Precedent: token level grammar with RFC clothing (chosen; named by author): "sounds good to me" \[704:18\]
- Evidence: README.md:30-34 "a grammar reads like the notation RFCs have used for decades"; README.md:27 superset; WHY.md; ABNF.md:213 notation comparison table

### Regex strings
- Status: DONE — \`r"..."\`, \`i"..."\`, \`s"..."\`, C numbers built, \`%\` forms kept for the ABNF dialect only (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:87073#1\])
- Decided: 2026-11-03 decided: "keep % for abnf only, build all three"; "r"" instead of re"""; 0x5A instead of %x5A because "i don't like using % much it looks noisy". \[silentpc-opusplan:4a4c3021:87073#1\]
- Rationale: "i don't like using % much it looks noisy" \[silentpc-opusplan:4a4c3021:87073\]
- Rationale: Asked for regex inside a string for compression: "wouldn't that allow a lot of such compression?" \[silentpc-opusplan:4a4c3021:86330\]
- Precedent: Python re/r strings (chosen; named by author): wanted "re\\"\\" like python"; settled as r"..." \[silentpc-opusplan:4a4c3021:87028\]
- Precedent: ABNF (chosen; named by assistant, accepted): kept for the ABNF dialect only \[silentpc-opusplan:4a4c3021:87073\]
- Precedent: C numbers (chosen; named by author): instead of %x5A \[silentpc-opusplan:4a4c3021:87073\]
- Evidence: 8328962 "Quieter notation: i"..." for insensitive strings, r"..." for regular expressions, C numbers for code points; the % forms are ABNF's"; ABNF.md:174,181,353

### Section comments
- Status: DONE — no section-comment detection exists; comments are kept per rule where they land (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h123#1\])
- Decided: 2026-09-21 changed: "maybe it doesn't matter about sections and file scope etc; just let the comment blocks land where they do" \[hist-silentpc:fd13bc5f:h123#1\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:2440 "The reader already keeps a leading and a trailing comment per rule"; not found: grep "section comment" in \*.md and \*.adb returns nothing

### Semicolon, newline and whitespace tokens
- Status: DONE — \`wordchars\` is a grammar rule and the whitespace names follow ABNF (latest decision 2026-10-01 \[silentpc:c14a13ff:9529#1\])
- Decided: 2026-10-01 decided: "wordchars doesn't go away it becomes a grammar rule" \[silentpc:c14a13ff:9529#1\]
- Rationale: "semicolon and newline are tokens needed for the round trip pretty printer" \[hist-silentpc:fd13bc5f:h102\]
- Rationale: "where abnf defined a name for a whitespace token, let's use it. no need to rename things without a benefit" \[578:14\]
- Rationale: "NL TAB WS SPACE LF CR were always meant to be tokens that matched specific whitespace characteers" \[578:12\]
- Precedent: ABNF (chosen; named by author): reuse ABNF names where defined \[578:14\]
- Evidence: grammars/obconf.hbnf:25 \`wordchars = ALPHA \| DIGIT \| "\_" \| "-" \| "."\`; RFCPLAN.md:141 "\`wordchars\` becomes a grammar rule"; grammars/ascii.hbnf and common.hbnf use SP, HTAB, WSP, CRLF (ABNF names)
- Doc differs: ABNF.md:342 still lists a \`wordchars "…"\` directive and RFCPLAN.md:116 lists \`wordchars\` among whole-parser directives

### Skip directive notation
- Status: DONE — factoring over the whole grammar set and the ladder with a byte-identical-types regression test are built (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:78037#1\])
- Decided: 2026-10-29 approved-proposal: "whole meal deal. 1 and 2": widen to the whole grammar set, and require byte-identical type declarations plus the 54-fold ladder regression test. \[silentpc-opusplan:4a4c3021:78037#1\]
- Rationale: "i want it as unobtrusive as possible, be clean looking, not messy" \[silentpc-opusplan:4a4c3021:77361\]
- Rationale: "so we just need to optimize the tgrammar instead of new syntax?" \[silentpc-opusplan:4a4c3021:j77991\]
- Rationale: Accepted from the assistant: "whole meal deal. 1 and 2", i.e. byte-identical type declarations plus the ladder regression test. \[silentpc-opusplan:4a4c3021:78037\]
- Precedent: simdjson (considered; named by author): apples-to-apples comparison with tape JSON \[silentpc-opusplan:4a4c3021:77361\]
- Precedent: fast\_float (considered; named by author): copy its approach so all grammars benefit \[silentpc-opusplan:4a4c3021:77847\]
- Evidence: tests/ladder.sh "the types they declare are the same" (cmp of fast-types and plain-types); bad5b34 "C backend: a ladder of binary operators looks once past its first operand"; RFCPLAN.md:2919 item 19 (Factor in C, Rust, Zig, Ada; tests/factor.sh)
- Doc differs: tests/ladder/cases.txt has 27 inputs and the test finds six levels, not a 54-fold ladder; RFCPLAN.md item 19 "Not done: ... the same ladder fast path in Rust, Zig and Ada"

### W-grammar adoption
- Status: DONE — named domains and hyperrules built (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:34497#1\])
- Decided: 2026-10-19 approved-proposal: "yes, add named domains and the wgrammar dialect" \[silentpc-opusplan:4a4c3021:34497#1\]
- Rationale: "w-grammar sounds pretty sweet!" \[644:63\]
- Rationale: "best to stick with historical and precedented syntax where possible" \[644:37\]
- Rationale: "it doesn't look any different, which is exactly what I was hoping for. smooth sipping, clear, minimal sntax chnge" \[644:53\]
- Precedent: W-grammar (chosen; named by author): asked what can be learned from it \[644:37\]
- Precedent: ALGOL 68 (considered; named by author): would look cleaner with C-style strings and chars \[644:91\]
- Precedent: \$ prefix for metanotions (considered; named by assistant, not taken up): he found existing syntax already sufficient \[644:53\]
- Evidence: commit d1ba338 (2026-10-19) "Parameterised rules: list(X), number parameters over a domain, clauses for single values"; commit e0d7009 (2026-10-19) "::= a domain (a metarule) ... named domains"; ABNF.md:106; tests/params/ (bad\_domain.hbnf)
- Doc differs: the chain says "wgrammar dialect"; no \`dialect wgrammar\` exists, the notation is part of the default hbnf one (ABNF.md:353 dialects: bnf, ebnf, abnf, ybnf, hbnf)

### W-grammar notation and readability
- Status: DONE — \`=\` defines a rule, \`:=\` a hyperrule, \`::=\` a domain, stated in the docs and used by the grammars (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:j34638#1\])
- Decided: 2026-10-19 decided: "make sure all hbnf files use the proper ::= := or =" \[silentpc-opusplan:4a4c3021:j34638#1\]
- Rationale: "since we default to = for normal rules, we can bring in := and ::= to mean meta and hyper", other meanings via the dialect directive \[silentpc-opusplan:4a4c3021:j34637\]
- Rationale: "make sure all hbnf files use the proper ::= := or =" \[silentpc-opusplan:4a4c3021:j34638\]
- Precedent: ::= := = (chosen; named by author): meta and hyper rule spellings \[silentpc-opusplan:4a4c3021:j34480\]
- Precedent: ALGOL 68 (considered; named by author): would look cleaner with C-style strings and char notation \[644:91\]
- Evidence: ABNF.md:353 "In hbnf \`=\` defines a rule, \`:=\` a rule with parameters ... and \`::=\` a domain (\`level ::= 1..17\`...)"; corpus/cobol/cobol.hbnf:308 "phrases(W) := W statements ..."

### bol and eol
- Status: DONE — built-in zero-width rules, no \`^\`/\`\$\` in \`r"..."\` (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j88601#1\])
- Decided: 2026-11-03 decided: "bol eol would be rules in the regular grammar; ^ and \$ would work as normal inside r""" \[silentpc-opusplan:4a4c3021:j88601#1\]
- Rationale: "maybe if we have bol eol then ^\$ aren't needed inside r\\"\\"" \[silentpc-opusplan:4a4c3021:j88602\]
- Evidence: b0f0302 "\`bol\` and \`eol\`, and the fix of a letter rule that became a keyword"; CONTEXTS.md:13 "built-in zero-width rules; no \`^\` or \`\$\` in \`r"..."\`"; ABNF.md:121 "a bare \`\$\` in a regular expression is refused as an anchor, \`eol\` being the test"
- Doc differs: ABNF.md:121 refuses \`^\`/\`\$\` in \`r"..."\`, where the Now line says they "work as normal"; the later bol/eol design (CONTEXTS.md:13) is the standing state

## 03 Parser generation and back ends

### Arena chunks
- Status: DONE — the arena was circled back to and reworked (mapped chunks, sized from input) (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h386#1\])
- Decided: 2026-09-22 decided: "do the other things first, we'll circle around to arena chunks later" \[hist-silentpc:fd13bc5f:h386#1\]
- Rationale and precedent: none stated in the sources
- Evidence: 60093b6 "C arena: big chunks are mapped, aligned for huge pages"; 9884a84 "an arena sized from the input and backed ahead of use"; dd34982 "an arena that takes back a failed attempt"; ABNF.md:362 "the arena chunk size is an \`enum\`"

### Ast as ir
- Status: DONE — the generator emits a typed tree and a parse function from the grammar with no separate IR stage (latest decision 2026-09-20 \[hist-silentpc:fd13bc5f:h71#1\])
- Decided: 2026-09-20 decided: "i don't think we need an ir. the ast is the ir"; wants a "nice schema format" mapping the AST to types and a parse function that allocates and populates them \[hist-silentpc:fd13bc5f:h71#1\]
- Rationale and precedent: none stated in the sources
- Evidence: README.md:23 "emits a parser and its typed tree in C, Rust, Zig or Ada"; hbnf\_schema.hbnf and hbnf\_shape.ads (what the code generators share, 5ad9a08)

### Back end spectrum and future back ends
- Status: DONE — the Ada comment bug was fixed and the planned-backend list is in the docs (latest decision 2026-10-02 \[silentpc:c14a13ff:19602#1\])
- Decided: 2026-10-02 approved-proposal: "fix the Ada Comment bug" \[silentpc:c14a13ff:19602#1\]
- Rationale: "if C++ support becomes more than a simple extern \\"C\\" header guard, we can make a separate C++ backend." \[silentpc:c14a13ff:4769\]
- Precedent: Go, Java, JavaScript, Common Lisp, newLISP (chosen; named by author): future GC-language back ends beside the compiled spectrum \[silentpc:c14a13ff:4652\]
- Precedent: ANTLR target languages (considered; named by assistant, accepted): comparison in WHY.md; he asked to list planned backends \[silentpc:c14a13ff:9209\]
- Precedent: C++ extern "C" header (considered; named by author): enough for now; separate backend only if needed \[silentpc:c14a13ff:4769\]
- Evidence: 4cff20c (2026-10-01) "ada lexer: skip # comments like the other backends"; RFCPLAN.md:2119-2124 "fill out the compiled targets (D, Fortran, ...) and the GC languages (Go, Java, JavaScript, C#, F#, Julia, Common Lisp, newLISP)"; no swift or mojo in RFCPLAN.md or README.md (dropped)
- Doc differs: the comment fix commit predates the 2026-10-02 approval by a day, so it may be a different Ada comment bug; no later commit names "Comment" for Ada

### C standard
- Status: DONE — the C backend is stated as C99 and C++-clean (latest decision 2026-09-30 \[silentpc:c14a13ff:j4748#1\])
- Decided: 2026-09-30 decided: "we pin C at C99 (for OpenBSD kernel compatibility) and for C++ we want to support any reasonable version" \[silentpc:c14a13ff:j4748#1\]
- Rationale: "we pin C at C99 (for OpenBSD kernel compatibility)" \[silentpc:c14a13ff:j4748\]
- Rationale: "for C++ we want to support any reasonable version (obviously we don't care about cfront)" \[silentpc:c14a13ff:j4748\]
- Precedent: C99 (chosen; named by author): C is pinned at C99 \[silentpc:c14a13ff:j4748\]
- Precedent: OpenBSD (chosen; named by author): the reason for the C99 pin: kernel compatibility \[silentpc:c14a13ff:j4748\]
- Precedent: C++11 and later (any reasonable version) (chosen; named by assistant, accepted): support any C++ standard, not only C++20 \[silentpc:c14a13ff:j4748\]
- Precedent: cfront (rejected; named by author): "we don't care about cfront" \[silentpc:c14a13ff:j4748\]
- Evidence: RFCPLAN.md:2123 "The C backend stays C99 and C++-clean"
- Doc differs: tests/backref.sh and tests/ladder.sh compile generated C with \`-std=gnu11\`, not C99; README.md:20 plans "C17 and C23 for the C family" (grammars, not the backend)

### C struct tags
- Status: DONE — the generated tags use \`\_s\` (latest decision 2026-09-30 \[silentpc:c14a13ff:5200#1\])
- Decided: 2026-09-30 changed: "\_s is better than \_st you should do that instead" \[silentpc:c14a13ff:5200#1\]
- Rationale: "\_s is better than \_st you should do that instead" \[silentpc:c14a13ff:5200\]
- Evidence: RFCPLAN.md:2302 "\`struct mid\_s { size\_t \_line; };\`"; tests/hidden.sh:27 \`struct bnf\_doc\_s\`

### Daemon grammars
- Status: DONE — obconf.hbnf plus per-daemon files that include the common file, jets in the common file (latest decision 2026-10-02 \[silentpc:c14a13ff:18556#1\])
- Decided: 2026-10-02 decided: Merge 4d; "\$\_" was a handwave at "the value in question"; jets go in the common file; obconf.hbnf plus per daemon "obconf\_httpd.hbnf" etc, each including it \[silentpc:c14a13ff:18556#1\]
- Rationale: "I like you putting the jets into the common file where possible" \[silentpc:c14a13ff:18556\]
- Rationale: "I expect theh daemon grammars to change, and change for the better, smaller, clearer, more cohherent." \[578:89\]
- Precedent: Other BNF dialects (considered; named by author): only support =/ unless present in other BNF grammars \[578:89\]
- Evidence: grammars/obconf.hbnf, grammars/obconf\_{bgpd,dhcpleased,httpd,ldpd,ntpd,pfctl,relayd,snmpd,unwind}.hbnf, grammars/common.hbnf; tests/daemons.sh and tests/daemons/{bgpd,httpd,ntpd,pfctl,relayd,snmpd,unwind}; obconf.md

### Data structures: rbtree or hash table
- Status: DONE — layout rb uses OpenBSD's red-black trees (the real tree.h); no hash-table layout exists (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j53350#1\])
- Decided: 2026-10-24 decided: Objects to hashing: "didn't we agree on rb trees?" \[silentpc-opusplan:4a4c3021:j53350#1\]
- Rationale: "hash table? why not rbtree? I love rbtrees." \[silentpc-opusplan:4a4c3021:j49705\]
- Rationale: Hash tables only "unless you were computing a perfect hash table for each instance where a hash table was needed" \[silentpc-opusplan:4a4c3021:j49706\]
- Precedent: red-black trees (chosen; named by author): "didn't we agree on rb trees?" \[silentpc-opusplan:4a4c3021:j53350\]
- Precedent: hash table (rejected; named by assistant, not taken up): he asked why not rbtree instead \[silentpc-opusplan:4a4c3021:j49705\]
- Precedent: perfect hash table (considered; named by author): acceptable only if computed per instance \[silentpc-opusplan:4a4c3021:j49706\]
- Evidence: commit 1751171 "layout rb: the lists are OpenBSD's red-black trees"; layouts/rb/sys/tree.h; RFCPLAN.md:2903 "\`rb\` (built, as \`layouts/rb\` ...)"; not found: no hash-table layout in layouts/ (the only hash is the internal context-set cache, TODO.md section 2)

### Defines
- Status: DONE — OpenBSD macros used for the compatible output; own structures avoid defines (latest decision 2026-09-23 \[hist-silentpc:fd13bc5f:h409#1\])
- Decided: 2026-09-23 decided: "since we are going for openbsd compatibility, we use the defines. for the data structures we come up with ourselves, no defines." \[hist-silentpc:fd13bc5f:h409#1\]
- Rationale: "since we are going for openbsd compatibility, we use the defines. for the data structures we come up with ourselves, no defines." \[hist-silentpc:fd13bc5f:h409\]
- Precedent: OpenBSD defines (chosen; named by author): used for compatible output only \[hist-silentpc:fd13bc5f:h409\]
- Evidence: ABNF.md:362 "the arena chunk size is an \`enum\`, not a \`#define\`"; ABNF.md:359 \`TAILQ\_\*\` macros used under \`layout tailq\`; templates/c\_no\_macros.tmpl exists beside c\_macros.tmpl

### Dispatch efficiency
- Status: DONE — recursive descent kept with first-byte dispatch, table-driven runs and shared-prefix factoring; backtracking minimized not forbidden (latest decision 2026-09-22 \[576:18#1\])
- Decided: 2026-09-22 decided: Keep recursive descent if more efficient; need "table lookup efficiency" for many alternatives; "some backtracking is ok; we want to minimize it, not forbid it" \[576:18#1\]
- Rationale: "if the recrusive descent you were emitting was more efficient then stick with that; but we need some way to get the table lookup efficiency" \[hist-silentpc:fd13bc5f:h372\]
- Rationale: "some backtracking is ok; we want to minimize it, not forbid it." \[hist-silentpc:fd13bc5f:h372\]
- Precedent: recursive descent (chosen; named by author): keep if more efficient \[hist-silentpc:fd13bc5f:h372\]
- Precedent: table lookup (chosen; named by author): for grammars with many alternatives \[hist-silentpc:fd13bc5f:h372\]
- Precedent: yacc and PEG (considered; named by author): asked how they compare with hbnf on efficiency and approach \[576:18\]
- Evidence: 4e93ce8 "Faster generated parsers: first-character dispatch, skip\_ws early exit"; 139c102 "table-driven runs and whitespace"; RFCPLAN.md:2919 item 19 (shared beginnings, \`HBNF\_Lookahead.Factor\`); README.md:17 "read alternatives that begin alike once"

### Ffi bindings
- Status: DONE — example bindings for python, ruby, perl and newlisp ship in bindings/ (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h181#1\])
- Decided: 2026-09-21 decided: dynamic languages use the C backend with ffi; "make sure it works with ffi and produce bindings for python ruby perl and newlisp" \[hist-silentpc:fd13bc5f:h181#1\]
- Rationale and precedent: none stated in the sources
- Evidence: bindings/{python,ruby,perl,newlisp}; bindings/README.md "any language with an FFI can drive it directly"; 1c3807c "The daemon bindings write parse\_config themselves, around a shipped runtime"

### Generated-name prefix
- Status: DONE — every generated identifier carries the dialect prefix (latest decision 2026-10-07 \[silentpc-opusplan:4a4c3021:j6671#1\])
- Decided: 2026-10-07 decided: Generated-name prefix: "Dialect name, every rule" (answer to multiple-choice question) \[silentpc-opusplan:4a4c3021:j6671#1\]
- Rationale: A prefix such as h\_ or bnf\_ means "we don't keep hitting reserved words in generated code" \[silentpc-opusplan:4a4c3021:j4247\]
- Rationale: "its easier than name mangling the other way on an adhoc basis" \[silentpc-opusplan:4a4c3021:j6632\]
- Evidence: commit 26bf159 "The dialect prefix: ybnf\_if, abnf\_host, on every generated identifier"; commit adadfef "Default prefix bnf\_ on generated identifiers; prefix none opts out"

### Implementation language
- Status: DONE — the generator is Ada (hbnf.adb, hbnf\_c.adb and the other Ada units) (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h169#1\])
- Decided: 2026-09-21 decided: "this is an ada program, no python!" \[hist-silentpc:fd13bc5f:h169#1\]
- Rationale and precedent: none stated in the sources
- Evidence: hbnf.adb, hbnf.gpr, libhbnf.gpr; README.md:12 "depends on nothing outside the GNAT runtime"
- Doc differs: helper scripts in Python remain outside the generator (tools/hbnf\_modernize.py, tools/cobol\_extract.py, scripts/grammar-size.py)

### Layouts (tailq, rb, ast)
- Status: DONE — layouts live in layouts/NAME/layout.hbnf, use the real tree.h and queue.h, and tests build against the real queue.h (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:76053#1\])
- Decided: 2026-10-29 approved-proposal: "switch": tests use the real queue.h. \[silentpc-opusplan:4a4c3021:76053#1\]
- Rationale: accepted from the assistant: tailq still compiled against a small stand-in queue.h; switch the tests to the real queue.h \[silentpc-opusplan:4a4c3021:76053\]
- Precedent: OpenBSD queue.h and RB\_HEAD tree (chosen; named by assistant, accepted): tests use the real header, not a test double \[silentpc-opusplan:4a4c3021:76053\]
- Evidence: commit 2670c04 "Layouts as directories (layouts/NAME/layout.hbnf), the default layout is named ast"; commit 9120364 "layout tape and layout tailq; layout\_ops replaces listops"; tests/bsdinc/sys/queue.h:1 "\$OpenBSD: queue.h,v 1.47"; layouts/rb/sys/tree.h; RFCPLAN.md:2886 "(it was \`listops\` ..." (old spelling gone from the repo)

### Memoization
- Status: DONE — the scan-once-per-position cache was prototyped and carried into the C generator (latest decision 2026-10-01 \[silentpc:c14a13ff:15173#1\])
- Decided: 2026-10-01 approved-proposal: "start on the memoization fix" \[silentpc:c14a13ff:15173#1\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:482 "Scan once per position (4c's deferred memoization). Prototyped 2026-10-02 ... 306.6M -\> 258.7M instructions"; RFCPLAN.md:1186-1198 (4f numbers)

### Output shaped like OpenBSD parse.y
- Status: DONE — typed structs, tailq/rb layouts and byte-identity tests against the daemons' parse.y output (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h178#1\])
- Decided: 2026-09-21 decided: "to the extent it is reasonable, hbnf output should follow the shape of what parse.y does in openbsd" \[hist-silentpc:fd13bc5f:h178#1\]
- Rationale: "i want the output to match openbsd as much as is reasonable and efficient in each language" \[hist-silentpc:fd13bc5f:h147\]
- Rationale: "to the extent it is reasonable, hbnf output should follow the shape of what parse.y does in openbsd" \[hist-silentpc:fd13bc5f:h178\]
- Precedent: parse.y (chosen; named by author): output follows its shape, specialized linked structs \[hist-silentpc:fd13bc5f:h178\]
- Precedent: tree-walking interpreter vs state machine (considered; named by author): "I can tolerate the tree walking interpreter" \[hist-silentpc:fd13bc5f:h147\]
- Evidence: README.md:13 "the daemons' own \`sys/queue.h\` and \`sys/tree.h\` containers (\`tailq\`, \`rb\`)"; RFCPLAN.md:827 "the obconf daemons' byte-identity tests"; tests/daemons.sh; obconf.md

### Performance patches (ladder, compact, memory, XML)
- Status: DONE — compact default, ladder fast path, memory/speed patches (arena, context set, SSE2 run loop) are all committed (latest decision 2026-11-05 \[silentpc-opusplan:4a4c3021:96020#1\])
- Decided: 2026-11-05 approved-proposal: "apply push" (speed patch xml3) \[silentpc-opusplan:4a4c3021:96020#1\]
- Rationale and precedent: none stated in the sources
- Evidence: commit eb40679 "Compact nodes are the default in C"; commit 9884a84 "a faster context set, an arena sized from the input"; commit acadd88 "XML in C: 5.55 to 3.46 ms"; commit ce1d973 "SSE2 ... 16 bytes at a time"; RFCPLAN.md:828 "Built 2026-10-29/31: 19, shared beginnings, the ladder"; the remaining speed ideas are listed in TODO.md section 2

### Performance work
- Status: DONE — shared prefixes in a tree of runs and the --lint for \`\|\` that could be \`/\` are built, with the ladder, compact nodes and the scan work (latest decision 2026-10-31 \[silentpc-opusplan:4a4c3021:79623#1\])
- Decided: 2026-10-31 decided: "do the nested prefix runs and the \| to / lint". \[silentpc-opusplan:4a4c3021:79623#1\]
- Precedent: DFA (chosen; named by author): table-driven scanner first, "if possible use dfa" \[silentpc-opusplan:4a4c3021:6714\]
- Precedent: std library functions (chosen; named by author): alternative to a hand-built scanner where possible \[silentpc-opusplan:4a4c3021:6714\]
- Evidence: commit e0094f0 "Shared beginnings in a tree of runs; --lint says where a \`\|\` could be a \`/\`"; README.md:70 "\`--lint\` says where an ordered choice \`\|\` could be a union \`/\`"; commit eb40679 "Compact nodes are the default in C"; commit 139c102 "table-driven runs and whitespace"

### Plan steps 4, 9b and the Ada free walk
- Status: DONE — step 9b landed with a Free\_\<rule\> walk in Ada's child parser package; RFCPLAN lists 4a-4e and 9b as done (latest decision 2026-10-06 \[silentpc:f7933077:j975#1\])
- Decided: 2026-10-06 decided: Ada free walk: "Child Parser package" home for Free\_\<rule\>; "Consumer-called walk", parser untouched \[silentpc:f7933077:j975#1\]
- Rationale and precedent: none stated in the sources
- Evidence: hbnf\_ada.adb:3143 "Free\_\<rule\>: release a tree the parse functions built. A consumer calls Free\_\<root\>" in the child package; RFCPLAN.md:822 "Done: 0, 1, 2, 3, 3b, 4a–4e, 5, 7a, 9a, 9b, 9c"; commit 9b61471 "9b: Ada gains the free walk the generated trees never had"

### Pretty printer back end and printconf
- Status: DONE — a writer (\`--writer\`, \`Write\_\<root\>\`) exists in the generator; the latest standing line is the 2026-09-20 decision, the 09-22 potential asks whether it already counts (latest decision 2026-09-20 \[hist-silentpc:fd13bc5f:h70#1\])
- Decided: 2026-09-20 decided: hbnf gets a "pretty printer" backend for C and Ada turning the AST into "structs and constants and enums", compiled "right down to the metal, no intermediary ast" \[hist-silentpc:fd13bc5f:h70#1\]
- Rationale: The writer "fits the spirit of the yacc.c": output a .c file "compiled right down to the metal, no intermediary ast" \[hist-silentpc:fd13bc5f:h70\]
- Precedent: yacc (chosen; named by author): output compiled C, no intermediary ast \[hist-silentpc:fd13bc5f:h70\]
- Precedent: PEG (considered; named by author): asked if a better alternative to EBNF \[hist-silentpc:fd13bc5f:h70\]
- Precedent: EBNF (considered; named by author): asked whether to do it in EBNF, as in the RFCs \[hist-silentpc:fd13bc5f:h70\]
- Evidence: hbnf.adb:262 \`--writer\`; hbnf\_ada.adb:222 \`Writer\_On ... Write\_\<root\>\`; RFCPLAN.md:1690 pretty-printer contract; hbnf.adb:387 messages naming "and Ada so far, without --writer"
- Doc differs: no \`printconf\` found anywhere in the repository

### Retiring the interpreter and HBNF\_Config
- Status: DONE — the interpreter and HBNF\_Config are gone from the sources (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j1166#1\])
- Decided: 2026-10-06 decided: Retire HBNF\_Config "as the plan says" (answer to multiple-choice question) \[silentpc-opusplan:4a4c3021:j1166#1\]
- Rationale: "eventually we shouldn't need the interpeter at all; hbnf combines lexer and parser in one grammar file" \[silentpc:c14a13ff:15999\]
- Rationale: "is there any reason to keep the interpreter at all? ... since we have the aport now" \[578:142\]
- Precedent: Mustache (rejected; named by author): "vestigial mustache is to be retired" \[578:142\]
- Evidence: c426707 "9c: retire the interpreter, and the reader beside it"; not found: grep HBNF\_Config over \*.ad\[bs\] returns nothing and no hbnf\_config unit exists
- Doc differs: RFCPLAN.md:546,565 still say "the interpreter and every backend" in older criteria text (stale history)

### Rollback and trusted mode
- Status: DONE — rollback is built for %emit and trusted mode was dropped, with no trace left (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:71520#1\])
- Decided: 2026-10-29 approved-proposal: "go with option 2, rollback" \[silentpc-opusplan:4a4c3021:71520#1\]
- Rationale: accepted from the assistant: rollback "implements the thing properly instead of working around its absence", matching his rule against working around a missing feature \[silentpc-opusplan:4a4c3021:71520\]
- Precedent: Forth "drop" (considered; named by author): asked if it gives extremely efficient rollback \[silentpc-opusplan:4a4c3021:71520\]
- Precedent: pugixml (considered; named by author): to be written up as non-conformant to the XML standard \[silentpc-opusplan:4a4c3021:j94728\]
- Evidence: commit eac77a0 "rollback { } for %emit, a sharper refusal analysis"; RFCPLAN.md:828 "\`rollback { }\`, the refusal analysis"; not found: "trusted" in RFCPLAN.md, CONTEXTS.md, TODO.md (consistent with the 2026-11-04 rejection)

### Rust and Zig back ends, visitor and fold
- Status: DONE — Rust and Zig back ends exist and alternation tags are built as alternative labels (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h358#1\])
- Decided: 2026-09-22 decided: "tag alternations next" \[hist-silentpc:fd13bc5f:h358#1\]
- Rationale and precedent: none stated in the sources
- Evidence: hbnf\_rust.adb, hbnf\_zig.adb; ABNF.md:123 "Alternative labels \| \`x = "set" a b %label assign \| ...\`"; ABNF.md:~119 \`\_alt\` number of the alternative taken

### Statement-at-a-time parsing
- Status: DONE — \`statements\` mode reads one statement at a time, file read a block at a time (latest decision 2026-09-24 \[578:55#1\])
- Decided: 2026-09-24 decided: "now do the grammar gaps, statement-at-a-time redesign"; wants best 3 options for keywords used as values; patches as tar.gz \[578:55#1\]
- Rationale: "why are we still doing whole file read in instead of statement at a time?" \[578:60\]
- Rationale: accepted from the assistant: option 1 (keyword table) is "the only one where 'drop-in for parse.y' is something a test can check" \[578:60\]
- Precedent: keyword table (chosen; named by assistant, accepted): option 1 for keywords used as values \[578:60\]
- Evidence: ABNF.md:347 "\`statements\` ... the parser reads one statement at a time ... A file ... is read a block at a time, not whole"; USENIXSUBMISSION.md:230
- Doc differs: ABNF.md:347 "C only (the other backends warn and parse the whole file)"

### TAILQ handling and parse.y drop-in output
- Status: DONE — tailq is a layout and the daemon grammars' output, not hardwired in the generator core (latest decision 2026-09-23 \[hist-silentpc:fd13bc5f:h405#1\])
- Decided: 2026-09-23 decided: "I said don't hardwire it in; so it should be in the preamble/epilogue and jets in the grammar" \[hist-silentpc:fd13bc5f:h405#1\]
- Rationale: "it has to be possible to emit a parse() that will generate a conf that the openbsd daemons can consume directly without modification" \[578:24\]
- Rationale: "TAILQ shouldn't be hardwired in"; it is "a proof that we can make a drop in replacement for parse.y" \[578:26\]
- Rationale: "that is specific to openbsd config stuff; that should be somewhere in the jets and preamble" \[hist-silentpc:fd13bc5f:h332\]
- Precedent: TAILQ (chosen; named by author): emitted for the daemon grammars only \[578:24\]
- Precedent: parse.y (chosen; named by author): drop-in replacement with no source changes \[578:26\]
- Precedent: red-black trees (considered; named by author): "i love rbtrees"; a good solution in many places \[578:24\]
- Precedent: something superior to tailq (considered; named by author): would be good to emit and drop in \[hist-silentpc:fd13bc5f:h327\]
- Evidence: ABNF.md:359 "the daemon grammars take OpenBSD's \`TAILQ\_\*\` from \`layout tailq\`"; README.md:69 "\`--layout=ast\|tape\|tailq\|rb\|NAME\` ... layouts are directories"; 9120364 "layout tape and layout tailq; layout\_ops replaces listops"
- Doc differs: the mechanism is \`layout tailq\` (layout directories), not literally preamble/epilogue and jets as the Now line says

### Tape layout
- Status: DONE — layout tape derives a tape from a plain grammar, with up references and captures working (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:94054#1\])
- Decided: 2026-11-04 decided: "fix tape. the uprefs shouldn't regress anything" \[silentpc-opusplan:4a4c3021:94054#1\]
- Rationale: "two grammars; the ones that just go to straight ast, and the %emit versions that use custom data structures for efficiency", to compare lines of code, rules, tokens \[silentpc-opusplan:4a4c3021:j70413\]
- Rationale: Wants a tree/tape directive "so we wouldn't need all those %emit rules" \[silentpc-opusplan:4a4c3021:j71726\]
- Rationale: accepted from the assistant: tape is faster than tree for YAML (6.5 vs 9.3 ms), so fix the tape's captures \[silentpc-opusplan:4a4c3021:94054\]
- Evidence: RFCPLAN.md:2842 "What the tape layout does, built. \`layout tape\` in a grammar, or \`--layout=tape\`, rewrites the ..."; commit 005b9be "layout tape reads the C grammar: five fixes"; commit acadd88 "the tape reads captures"; tests/tapecap.sh, tests/upref.sh; the remaining tape refusals (items 17, 63, 37-39) are queued in TODO.md section 3

### The --idref serializer and multiple trees
- Status: DONE — \`--idref\` is implemented and no grammar must populate a single conf (latest decision 2026-09-23 \[hist-silentpc:fd13bc5f:h448#1\])
- Decided: 2026-09-23 decided: Not all grammars populate a conf\*; "some of them populate multiple trees or structs" \[hist-silentpc:fd13bc5f:h448#1\]
- Rationale: "I thought we run over a grammar, it emits a parser. end of story" \[hist-silentpc:fd13bc5f:h447\]
- Rationale: "not all grammers populate a conf\* some of them populate multiple trees or structs" \[hist-silentpc:fd13bc5f:h448\]
- Evidence: IDREF.md:3 "implemented as \`hbnf --backend=c --idref\`"; hbnf.adb:174 \`\[--idref\]\`; 3ab7fd5 grammar writes its own entry point in its epilogue
- Doc differs: IDREF.md says "The per-type \`\*\_find()\` helpers and the merge side ... are not generated"

### Tree-sitter back end and limits
- Status: DONE — the limit was raised and then removed altogether in the generated scanner (latest decision 2026-10-19 \[silentpc-opusplan:4a4c3021:j32337#1\])
- Decided: 2026-10-19 decided: "raise tree sitter to 500 levels" \[silentpc-opusplan:4a4c3021:j32337#1\]
- Rationale: "why such a limit? why have any limit?" \[silentpc-opusplan:4a4c3021:j32423\]
- Precedent: tree-sitter (chosen; named by author): emit a tree-sitter backend parser from an hbnf grammar; asked to add to roadmap \[704:30\]
- Evidence: commit 78debd1 "Tree-sitter scanner: tags in a table ... 512 open at once (was about 80)"; commit 602541b "open tags are a persistent stack in memory the scanner owns ... no limit on depth"; hbnf\_tree\_sitter.adb:317 "a stack of open tags, with no limit on depth"
- Doc differs: hbnf\_tree\_sitter.adb:336 says "There is no limit on depth" (beyond the 500 asked for, which also answers the 'why have any limit' question)

### Whole-document writer and shape extraction
- Status: DONE — the writer and HBNF\_Shape exist, and the tree and tape layouts have since changed freely (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:93559#1\])
- Decided: 2026-11-04 decided: Other than the obconf stuff, "tree and tape structure is free to change" \[silentpc-opusplan:4a4c3021:93559#1\]
- Rationale and precedent: none stated in the sources
- Evidence: hbnf\_shape.ads/.adb; tests/writer/; commit 4a20c92 "Writer layout hook in Zig, Rust and Ada"; commit 6748de9 "Tape layout: wrapper elision, span entries" (structure changed after the decision's predecessors)

### YAML and TOML grammars
- Status: DONE — YAML and TOML grammars are built with no indentation cap and the slowdown and memory reductions were landed (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:93515#1\])
- Decided: 2026-11-04 decided: "push it then do the mem reduction" \[silentpc-opusplan:4a4c3021:93515#1\]
- Rationale: "indentation should be simple recursive descent even if the whole file was nothing but indentation, that shouldn't cause any blowups" \[silentpc-opusplan:4a4c3021:53016\]
- Rationale: "something linear is being turned exponential"; fix the recursion problem \[silentpc-opusplan:4a4c3021:j52939\]
- Rationale: "neither mem nor cpu should blow up with yaml", so the 128 cap goes \[silentpc-opusplan:4a4c3021:j53231\]
- Precedent: recursive descent (chosen; named by author): indentation level is just a nested block \[silentpc-opusplan:4a4c3021:53016\]
- Evidence: commits b512012 (YAML 1.2 grammar), c9e0955 (TOML 1.0); corpus/yaml/README.md:34 "the C parsers stop at \`HBNF\_MAX\_DEPTH\` rules open at once (4096 by default ...)" (a stack bound, not a 128 cap); commit 9884a84 (arena sized from input); README.md:291 YAML timing tables; TODO.md:21 "YAML tree 12 (8.5)" ms; further memory idea (list links in arrays) is TODO.md section 2, not built

### obconf parser: drop-in for parse.y and --conf
- Status: DONE — --conf is gone; a config grammar writes its entry point in its own epilogue around runtime/hbnf\_conf.h/.c, and obconf is a grammar (latest decision 2026-10-28 \[silentpc-opusplan:4a4c3021:j66223#1\])
- Decided: 2026-10-28 decided: "instead of using templates, now our parser can just link in any utility.c we've written to hold our utility functions" \[silentpc-opusplan:4a4c3021:j66223#1\]
- Rationale: "the obconf case should illustrate how we can parse any grammar and stuff it into any data structure on disk"; the same pattern can fix json and yaml "so they also use ondisk types that allow greater speed" \[silentpc-opusplan:4a4c3021:65954\]
- Rationale: "instead of using templates, now our parser can just link in any utility.c we've written to hold our utility functions" \[silentpc-opusplan:4a4c3021:j66223\]
- Rationale: "the nice comment round tripping should be a characteristic of the grammar, not hbnf" \[silentpc:c14a13ff:j15910\]
- Rationale: "the hbnf binary reading the oconf grammar files should be all we need" \[silentpc:c14a13ff:j15910\]
- Evidence: commit 3ab7fd5 "Remove --conf: a config grammar writes its entry point in its own epilogue"; grammars/README.md:200 "\`parse\_config\` in its epilogue around the driver in \`runtime/hbnf\_conf.h\`"; runtime/hbnf\_conf.c; grammars/obconf.hbnf:2 "the including schema owns \`language\`, the preamble and the epilogue"; grammars/obconf\_roundtrip.hbnf (comments kept, tests/writer.sh)
- Doc differs: TODO.md:88 says "The conf glue (\`--conf\`) out of the templates into an included C header." as still open

## 04 Wire layer and bit rules

### Bit fields and mixed text and bit rules
- Status: DONE — bit fields and mixed text/bit grammars with %action work in C, Rust, Zig and Ada (latest decision 2026-10-21 \[silentpc-opusplan:4a4c3021:36261#1\])
- Decided: 2026-10-21 approved-proposal: "push it and continue with %action in the mixed grammars" \[silentpc-opusplan:4a4c3021:36261#1\]
- Rationale and precedent: none stated in the sources
- Evidence: WIRE.md:7 "the C, Rust, Zig and Ada backends read and write bit rules"; WIRE.md "\`%action\` works in them too: after the whole text has been read, a walk over the tree"; tests/wire/mixed\*\_main.{c,rs,zig,adb}

### C backend first
- Status: DONE — the standing rule is stated in the docs and the C-only features are queued for porting (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:94266#1\])
- Decided: 2026-11-04 decided: "while we are landing new features and optimizations, we stick to the c backend, then when it passes, we expand to other backends" \[silentpc-opusplan:4a4c3021:94266#1\]
- Rationale and precedent: none stated in the sources
- Evidence: TODO.md:89 "Port the C-only features to Rust, Zig, Ada, tree-sitter (the standing rule is C first, then the rest)"; CONTEXTS.md:616 "The C backend first ..., then Rust, Zig and Ada"; RFCPLAN.md:828 "Built, C backend only: 15 ... 17 ... 18"

### Index base
- Status: DONE — indexes and bit offsets count from zero and the doc cites C and IMP72 (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:15185#1\])
- Decided: 2026-10-17 decided: "our index are 0 based because C and IMP72 agree, right or left follows the RFC"; commit and push. \[silentpc-opusplan:4a4c3021:15185#1\]
- Rationale: "our index are 0 based because C and IMP72 agree, right or left follows the RFC" \[silentpc-opusplan:4a4c3021:15185\]
- Precedent: C (chosen; named by author): 0-based index \[silentpc-opusplan:4a4c3021:15185\]
- Precedent: IMP72 (chosen; named by author): 0-based index agrees with C \[silentpc-opusplan:4a4c3021:15185\]
- Precedent: RFC packet diagrams (chosen; named by author): bit direction (left or right) follows the RFC \[silentpc-opusplan:4a4c3021:15185\]
- Precedent: ALGOL 60 (considered; named by author): asked whether it used 0-based offsets \[silentpc-opusplan:4a4c3021:j15142\]
- Precedent: Python (considered; named by assistant, not taken up): also 0-based \[silentpc-opusplan:4a4c3021:15185\]
- Precedent: BLISS and hardware manuals (considered; named by assistant, not taken up): count bits from the right \[silentpc-opusplan:4a4c3021:15185\]
- Evidence: WIRE.md:113 "Both count from zero, as C and IMP72 do"; WIRE.md:115 "bit 0 is the most significant bit, the leftmost"

### Packet demos
- Status: DONE — Ethernet, ARP, IPv4, IPv6, TCP and UDP grammars with byte fixtures exist (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h322#1\])
- Decided: 2026-09-22 decided: "after imsg, do examples of ethernet packets, ip and tcp and udp and arp packets" as demos \[hist-silentpc:fd13bc5f:h322#1\]
- Rationale and precedent: none stated in the sources
- Evidence: WIRE.md:23 "\`tests/wire/net.hbnf\` (Ethernet, ARP, IPv4, IPv6, TCP, UDP) and \`tests/wire.sh\` ... are the worked examples"; tests/wire/net.hbnf, tests/wire/net.expected

### Text writer
- Status: DONE — a general writer exists with canonical-then-lossless output, round-tripped over the suites (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:j19949#2\])
- Decided: 2026-10-18 decided: Writer proved correct by "Round-trip over every grammar's tests". \[silentpc-opusplan:4a4c3021:j19949#2\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:1691 "first, then lossless. \`write (tree)\` re-parses to the same tree"; RFCPLAN.md:563 "Round-trip and byte-identity gates are mandatory"; tests/writer.sh, tests/writer/

### Unified text and binary syntax, retiring units
- Status: DONE — \`units\` is gone and text and bit rules mix in one notation with \`bitsof\` (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:j19192#1\])
- Decided: 2026-10-18 approved-proposal: Retire \`units\`: a field takes a slice of numbered words, "name:src@Off:Len", unit is src's layer, "b" suffix gives bits. \[silentpc-opusplan:4a4c3021:j19192#1\]
- Rationale: "text and binary should be freely mixable" \[silentpc-opusplan:4a4c3021:j16844\]
- Rationale: "how is this different from a text grammar? i thought we had a single unified syntax?" \[silentpc-opusplan:4a4c3021:j16781\]
- Rationale: "why read and ignore binary? eliminate it. what is \\"units\\"? why is it there?" \[silentpc-opusplan:4a4c3021:j17709\]
- Precedent: BIP-39 and bech32 (chosen; named by assistant, accepted): use cases for the text-to-bits bridge he asked to start \[silentpc-opusplan:4a4c3021:15224\]
- Evidence: RFCPLAN.md:1496 "(\`units\`, a directive that spelled a message as words, was a stopgap and is gone: 2026-10-18, replaced by \`name:bitsof(rule)\`)"; WIRE.md:1-9 "There is no binary mode and no separate file type"; not found: any \`units\` directive in hbnf\_wire.adb or hbnf\_grammar.adb
- Doc differs: WIRE.md:341 "Units. ... a number may carry a unit, \`b\` bits, \`B\` bytes, \`c\` code points, \`W\` words" as a design (the \`b\`/\`B\`/\`c\`/\`W\` suffixes are not built)

## 05 Templates and output

### Markdown grammar and rendering
- Status: DONE — the grammar was changed rather than the program: corpus/markdown has the grammar with Typst and HTML back ends (latest decision 2026-11-06 \[silentpc-opusplan:e3c27aa1:330#1\])
- Decided: 2026-11-06 decided: "why change hbnf instead of just changing the grammar?" \[silentpc-opusplan:e3c27aa1:330#1\]
- Precedent: Typst (chosen; named by author): C back-end transforming markdown into typst \[silentpc-opusplan:4a4c3021:90278\]
- Precedent: rewrite rules (considered; named by author): if sufficiently advanced, use them for the transform \[silentpc-opusplan:4a4c3021:90278\]
- Precedent: md2html.py standalone renderer (considered; named by assistant, not taken up): alternative to changing hbnf \[silentpc-opusplan:e3c27aa1:330\]
- Precedent: pandoc (considered; named by assistant, not taken up): offered as renderer to install \[silentpc-opusplan:e3c27aa1:308\]
- Evidence: commit 725cc55 "corpus/markdown/markdown.hbnf reads headings, paragraphs, bullet and numbered lists ... 44 rules"; commit 63674ce "Markdown corpus: HTML output"; corpus/markdown/README.md:2 "to Typst and HTML"; tests/markdown.sh; known \`%spaces\` bug 26/6 still open in TODO.md:100

### Runtime templates and search path
- Status: DONE — templates load at startup from --templates, HBNF\_TEMPLATES or the share directories (latest decision 2026-09-30 \[silentpc:c14a13ff:2120#1\])
- Decided: 2026-09-30 decided: "default dir plus flag /usr/share/hbnf + ~/.local/share/hbnf etc" \[silentpc:c14a13ff:2120#1\]
- Rationale: "putting things in tmpl files makes them easy to modify at runtime" \[silentpc:c14a13ff:2097\]
- Rationale: "no compiled in defaults; it is all runtime templating, templates loaded at startup" \[silentpc:c14a13ff:2109\]
- Rationale: "I definitely don't want to recreate a minilanguage; just simple templating, fill a \${hole} with a \\"value\\"" \[silentpc:c14a13ff:j2070\]
- Precedent: compiled-in default templates (rejected; named by assistant, not taken up): he wants no compiled in defaults \[silentpc:c14a13ff:2109\]
- Precedent: /usr/share/hbnf and ~/.local/share/hbnf (chosen; named by author): default dir plus flag \[silentpc:c14a13ff:2120\]
- Evidence: hbnf.adb:81-113 "--templates=DIR, else ... ~/.local/share, then each \$XDG\_DATA\_DIRS entry (/usr/local/share and /usr/share)"; templates/\*.tmpl (70+ files)

### Template engine
- Status: DONE — the emitters work through .tmpl files with filled holes; the Emit\_Rule\_Parser and Emit\_Alternation conversion was carried through (latest decision 2026-09-30 \[silentpc:c14a13ff:2988#1\])
- Decided: 2026-09-30 approved-proposal: "keep going into Emit\_Rule\_Parser and Emit\_Alternation" \[silentpc:c14a13ff:2988#1\]
- Rationale: "this simple substituter could save a lot of code and make things much more readable and easy to edit" \[578:72\]
- Rationale: "I want a bunch of Append and Put\_line gone from the Ada code" \[silentpc:c14a13ff:1171\]
- Rationale: "too much ada code, and ada string handling is ugly and clumsy" \[silentpc:c14a13ff:854\]
- Rationale: "looping over function calls should reduce most of the dsl hell" \[silentpc:c14a13ff:870\]
- Precedent: \${foo} template style (considered; named by author): asked if superior to the @foo@ style then in use \[silentpc:c14a13ff:854\]
- Precedent: @foo@ template style (considered; named by author): the style in use, compared against \${foo} \[silentpc:c14a13ff:854\]
- Evidence: templates/c\_rule\_head.tmpl, c\_rule\_line.tmpl, c\_alt\_kind.tmpl, c\_seq\_ref.tmpl and rust\_/zig\_/ada\_ equivalents; commit f1ab596 "The code templates are rendered by hbnf's own Mustache package"
- Doc differs: the mechanism is now Mustache \`{{ }}\` rather than the \`\${hole}\` of the 2026-09-30 decisions (see the next subject)

## 06 Testing and conformance

### BIP39 tests
- Status: DONE — word lists as include files, bitfield mnemonic grammar, 12/24 normal and others warn; rewrite-rule idea stays potential (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j15536#1\])
- Decided: 2026-10-17 changed: "no, stick to the bip standard, warn for anything allowed but isn't 12 or 24" \[silentpc-opusplan:4a4c3021:j15536#1\]
- Rationale: "stick to the bip standard, warn for anything allowed but isn't 12 or 24" \[silentpc-opusplan:4a4c3021:j15536\]
- Rationale: "in practice only 12 18 and 24 word keys are allowed, and most wallets don't support 18" \[silentpc-opusplan:4a4c3021:15477\]
- Rationale: "something that explicitly emits the number matching each word, that is clearer" \[silentpc-opusplan:4a4c3021:81831\]
- Precedent: BIP-39 (chosen; named by author): follow the standard, warn on allowed lengths other than 12 or 24 \[silentpc-opusplan:4a4c3021:j15536\]
- Precedent: rewrite rules (considered; named by author): asked whether they could help the bip39 implementation \[silentpc-opusplan:4a4c3021:81831\]
- Evidence: tests/wire/mnemonic\_ada.hbnf:15-16 "Wallets mostly make 12 and 24, and not all can import the others, so those read with a warning"; corpus/bip39/wordlists/\*.txt, grammars/bip39/english.hbnf (ten lists), tests/wire.sh:179 word-list test, tests/wire/mnemonic.hbnf \`include "../../grammars/bip39/english.hbnf"\`
- Doc differs: tests/wire/bip39\_phrase.hbnf:1 says "12 to 24 words" with no warning (an older, simpler test)

### Bech32 test
- Status: DONE — the segwit address data part (symbols, 5-bit words, witness version, program, padding, 6-symbol checksum) is read and written by a wire test in all four backends; the human-readable part is not covered (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j14221#1\])
- Decided: 2026-10-17 approved-proposal: "sweet, yes do a bech parser too" \[silentpc-opusplan:4a4c3021:j14221#1\]
- Rationale and precedent: none stated in the sources
- Evidence: grammars/bech32.hbnf (the 32 symbols, \`bech32-symbol\`); corpus/bech32/segwit\_addr.c (Wuille reference); not found: searched tests/\*.sh and tests/wire for a bech32 address test (no match)
- Evidence: committed clone ff3c5d0: tests/wire/segwit.hbnf, tests/wire/segwit\_in.hbnf, tests/wire.sh:125-153 (check\_rust/check\_zig/check\_ada segwit); 566aa3c "Retire units: ... BIP-39 and segwit on it, read and written"; RFCPLAN.md:1664 "the segwit data part run on it (\`tests/wire/mnemonic\`, \`segwit\`)"; the first pass missed these

### Benchmarks against yacc and parser efficiency
- Status: DONE — json/toml/yaml/xml/c/pfctl benches against yacc and libraries exist for tape and tree versions (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:j77120#1\])
- Decided: 2026-10-29 decided: "bench json/toml/yacc see how the changes might have affected their tape versions and tree versions" \[silentpc-opusplan:4a4c3021:j77120#1\]
- Rationale: "since you are optimizing tree now" \[silentpc-opusplan:4a4c3021:j77120\]
- Precedent: yacc (chosen; named by author): pfctl benchmark against yacc \[silentpc-opusplan:4a4c3021:42373\]
- Precedent: PEG (considered; named by assistant, not taken up): put on the same input as comparison \[576:20\]
- Evidence: bench/libs.sh, bench/stage-yacc.sh, bench/stage-pfctl.sh, bench/cspeed.sh; commit 96ac67b "Library comparison rerun: JSON, TOML and YAML against the libraries"; TODO.md:21 "hbnf JSON tree 2.8 ms ... YAML tree 12 (8.5), XML tape 3.5, tree 4.3"; a quiet-machine rerun is open in TODO.md section 1

### Byte identity against parse.y
- Status: DONE — the harness runs each daemon's parse.y and hbnf's parser on the same configs and compares byte for byte (latest decision 2026-10-06 \[silentpc:afd90154:j1075#1\])
- Decided: 2026-10-06 decided: Rust snapshot gate: "Keep fix and also fix cnt" \[silentpc:afd90154:j1075#1\]
- Rationale: "are they creating the same data structures in memory" \[hist-silentpc:fd13bc5f:h418\]
- Rationale: "it must end up with byte identical \*conf trees to the parse.y output" \[hist-silentpc:fd13bc5f:h420\]
- Precedent: parse.y (chosen; named by author): compare against what bison/parse.y generates \[hist-silentpc:fd13bc5f:h474\]
- Precedent: TAILQ (chosen; named by author): conf trees byte identical when using TAILQ \[hist-silentpc:fd13bc5f:h420\]
- Evidence: tests/bytetest/README.md "byte-identity harness against OpenBSD parse.y ... nine OpenBSD config parsers"; tests/bytetest/daemons.tsv; RFCPLAN.md:2325 "a deliberate, proven correction to generated ... unused \`cnt\`" (the cnt fix); RFCPLAN.md:1901 "the 132-file snapshot is byte-identical"

### C parser bakeoff
- Status: DONE — c99 plus gnu (pcc99, gnu99) grammars compared with pcc; tree shrinking and shared beginnings built (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:77098#1\])
- Decided: 2026-10-29 approved-proposal: "do the shrink and skip on trees see how it helps" \[silentpc-opusplan:4a4c3021:77098#1\]
- Rationale: "since pcc is c99 plus gnu extensions, it is comparable to gcc" \[silentpc-opusplan:4a4c3021:60776\]
- Rationale: "we should do apples to apples here" \[silentpc-opusplan:4a4c3021:j60523\]
- Rationale: "32v cgram.y is wrong comparison ... c11 is a different dialect." \[silentpc-opusplan:4a4c3021:60176\]
- Rationale: "hbnf is all about helpful error messages and recoverable/restartable failure modes" \[silentpc-opusplan:4a4c3021:60958\]
- Precedent: pcc (c99 plus gnu extensions) (chosen; named by author): modern pcc is c99, so the comparable \[silentpc-opusplan:4a4c3021:j60523\]
- Precedent: gcc bison grammar (chosen; named by author): c99 era grammar with its gnu extensions \[silentpc-opusplan:4a4c3021:60776\]
- Precedent: 32V cgram.y (rejected; named by author): wrong comparison \[silentpc-opusplan:4a4c3021:60176\]
- Precedent: C11/C17/C23 (rejected; named by author): wanted for himself, useless for the yacc bakeoff \[silentpc-opusplan:4a4c3021:j60523\]
- Precedent: Common Lisp restart (considered; named by author): to examine for ideas on restartable failures \[silentpc-opusplan:4a4c3021:60958\]
- Evidence: dd34982 "The C tree is smaller: overlaid choice nodes, small members by value, and an arena that takes back a failed attempt"; e0094f0 "Shared beginnings in a tree of runs"; tests/pcc99.sh, tests/gnu99.sh; README.md:154-159 compares 32V, PCC and GCC yacc grammars

### CPU pinning
- Status: DONE — benchmarks run on cpuset core 5 by default (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:j70289#2\])
- Decided: 2026-10-29 decided: Pin enforcement: "Keep as is, plus my own timings (Recommended)" \[silentpc-opusplan:4a4c3021:j70289#2\]
- Rationale: "we should lock our benches to a cpu and not let anything else use it" \[silentpc-opusplan:4a4c3021:j61955\]
- Rationale: "that one is left alone by fuzzy search" \[silentpc-opusplan:4a4c3021:j65257\]
- Precedent: taskset / docker --cpuset-cpus (chosen; named by assistant, accepted): pin benches to one core \[silentpc-opusplan:4a4c3021:61979\]
- Precedent: cset shield / isolcpus (considered; named by assistant, not taken up): real reservation offered, he did not take it \[silentpc-opusplan:4a4c3021:61979\]
- Evidence: bench/libs.sh:53, bench/cspeed.sh:34, bench/haskell.sh:43, bench/raku.sh:49 \`--cpuset-cpus="\${BENCH\_CPUS:-5}"\`

### Check timings and makefile style
- Status: DONE — check.sh stamps each backend, skips fresh ones, records timings, runs four slices at once (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:72990#1\])
- Decided: 2026-10-29 approved-proposal: "yes, do the parallel check slices" to speed up the check. \[silentpc-opusplan:4a4c3021:72990#1\]
- Rationale: "the check script should be like a makefile, only redo the tests if something changed that could affect them" \[silentpc-opusplan:4a4c3021:63180\]
- Rationale: "the check test timings should also be recorded to use as supplementary benching before the official benching." \[silentpc-opusplan:4a4c3021:64600\]
- Precedent: makefile (chosen; named by author): rebuild only what changed \[silentpc-opusplan:4a4c3021:63180\]
- Evidence: tests/check.sh:16 "--serial one slice at a time (the default is four; --jobs=N sets it)"; :120 stamps; :187 fresh(); :31 records CPU time and flags big speed changes; commit 5ad9a08

### Compiler flags
- Status: DONE — same flags for every native library in the tables (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:j64180#1\])
- Decided: 2026-10-27 decided: Asks "you are compiling with gcc -Os right?"; then "as long as its the same flags that's fine". \[silentpc-opusplan:4a4c3021:j64180#1\]
- Rationale and precedent: none stated in the sources
- Evidence: README.md:318 "\`-O2\`, the same sources and flags for every native library"
- Doc differs: README says -O2; the question named -Os, and he accepted any flags as long as they are the same

### Differential test
- Status: DONE — the differential harness exists (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h318#1\])
- Decided: 2026-09-22 decided: "build the differential test; we must emit a drop in replacement or at least something the daemons can use with minimal changes" \[hist-silentpc:fd13bc5f:h318#1\]
- Rationale and precedent: none stated in the sources
- Evidence: tests/bytetest/bytetest.sh, tests/bytetest/byteident.sh, tests/bytetest/unwind-ident.sh; bench/stage-pfctl.sh (pfctl against byacc)

### Docker toolchain
- Status: DONE — ada-on-alpine builds the :edge-full image with zig and the other toolchains (latest decision 2026-10-06 \[silentpc:afd90154:j255#1\])
- Decided: 2026-10-06 decided: ":edge-full has zig etc" \[silentpc:afd90154:j255#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: no image definition for edge-full in the clone (bench/Dockerfile.glibc is Debian)
- Evidence: packaging repo: build-full-image.sh:1-3,41 "Build the ada-toolchain:edge-full image ... apk add --no-cache rust cargo zig g++ gcc-gdc ldc dub gfortran nim ..."

### Drop in replacement
- Status: DONE — the bytetest harness compares the generated parser's conf tree with parse.y's for the daemons (latest decision 2026-09-22 \[hist-silentpc:fd13bc5f:h353#1\])
- Decided: 2026-09-22 decided: "if our tailq struct conf output is identical that parse.y then the drop in compatbility is done" \[hist-silentpc:fd13bc5f:h353#1\]
- Rationale: "the whole point of building the tree is that it is consumable by the daemon directly" \[hist-silentpc:fd13bc5f:h319\]
- Rationale: "that is the actual test case for this; drop in replacement for the output of parse.y" \[hist-silentpc:fd13bc5f:h211\]
- Rationale: "if our tailq struct conf output is identical that parse.y then the drop in compatbility is done" \[hist-silentpc:fd13bc5f:h353\]
- Precedent: parse.y (chosen; named by author): output to be matched by hbnf grammars \[hist-silentpc:fd13bc5f:h210\]
- Precedent: OpenBSD daemons (chosen; named by author): single hbnf grammars for all daemons using parse.y \[hist-silentpc:fd13bc5f:h210\]
- Precedent: TAILQ conf struct (chosen; named by author): identical tailq output defines compatibility \[hist-silentpc:fd13bc5f:h353\]
- Evidence: tests/bytetest/README.md:1-9 "the parser hbnf generates produces the same bytes as parse.y does for the same input"; layouts/tailq/layout.hbnf; tests/bytetest/daemons.tsv; tests/bytetest/ntpd-proof.sh

### Haskell happy/alex benchmark
- Status: DONE — rig built, pinned to cpu 5, results in README (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:72222#1\])
- Decided: 2026-10-29 approved-proposal: "run the haskell rig pinned to cpu 5; glad you included aeson." \[silentpc-opusplan:4a4c3021:72222#1\]
- Rationale: "how well do they do against hbnf" \[silentpc-opusplan:4a4c3021:j71717\]
- Rationale: "when the happy/alex grammar is already done by others, re-use it, but put a few tokens into optimizing them" \[silentpc-opusplan:4a4c3021:71967\]
- Rationale: "only want the haskell stuff tested on amd64, as the rest of the benchmarks" \[silentpc-opusplan:4a4c3021:72030\]
- Precedent: Haskell Happy/Alex (chosen; named by author): bench best tape grammars against equivalents \[silentpc-opusplan:4a4c3021:j71717\]
- Precedent: aeson (chosen; named by assistant, accepted): glad it was included \[silentpc-opusplan:4a4c3021:72222\]
- Evidence: bench/haskell.sh, bench/haskell/ (json, toml, yaml, Timer.hs), bench/results/haskell.md, README.md:351 "Against Haskell's Alex and Happy" (includes aeson)

### Library benchmarks (JSON, TOML, YAML)
- Status: DONE — bench/libs.sh measures hbnf against the popular libraries per format (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j56970#1\])
- Decided: 2026-10-24 decided: Also bench hbnf against the most commonly used libraries for each format, "where people will notice speedups the most". \[silentpc-opusplan:4a4c3021:j56970#1\]
- Rationale: "since that is where people will notice speedups the most" \[silentpc-opusplan:4a4c3021:j56970\]
- Precedent: most commonly used libraries per format (chosen; named by author): bench hbnf against them \[silentpc-opusplan:4a4c3021:j56970\]
- Evidence: bench/libs.sh; README.md:239-241 "The libraries were picked by GitHub stars"; bench/results/libs.md

### POSIX shell grammar
- Status: DONE — written natively and as the standard's yacc text, tested in all four backends (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:47026#1\])
- Decided: 2026-10-23 approved-proposal: "do it": write the POSIX shell grammar \[silentpc-opusplan:4a4c3021:47026#1\]
- Precedent: POSIX shell grammar (chosen; named by author): core corpus, not paused \[silentpc-opusplan:4a4c3021:46422\]
- Evidence: tests/posix.sh, tests/check.sh:54 lists posix; commits 2db6f18 "POSIX shell: the standard's grammar reads shell scripts (580 of 581...)", 2def6a4 "POSIX shell is core corpus, not paused", 8b74ede (41 lines native)

### Raku comparison and benchmark
- Status: DONE — Raku rig, README section with auto-updated block, METACOMPILERS comparison (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:85485#1\])
- Decided: 2026-11-03 decided: Add raku results to the README; "make sure they are automated like the other ones, readme updated every time". \[silentpc-opusplan:4a4c3021:85485#1\]
- Rationale: "make sure they are automated like the other ones, readme updated every time" \[silentpc-opusplan:4a4c3021:85485\]
- Precedent: Raku grammars (chosen; named by author): benchmarked against hbnf \[silentpc-opusplan:4a4c3021:j85257\]
- Precedent: Haskell (considered; named by author): earlier benchmark used as the model for the Raku one \[silentpc-opusplan:4a4c3021:j85257\]
- Precedent: META II, IMP72, SNOBOL4 (considered; named by assistant, not taken up): METACOMPILERS.md already compares hbnf with these; he asked the Raku comparison go there \[silentpc-opusplan:4a4c3021:85182\]
- Evidence: bench/raku.sh; README.md:392 "Against Raku's grammars" with \`\<!-- bench:raku --\>\` block (:401-427), filled by bench/update-docs.sh; METACOMPILERS.md:220 "## Raku grammars"

### Test corpora
- Status: DONE — RFC, POSIX, C and sqlite3.c corpora are in the repository and run as tests (latest decision 2026-10-29 \[silentpc-opusplan:4a4c3021:76645#1\])
- Decided: 2026-10-29 approved-proposal: "add it as a test" \[silentpc-opusplan:4a4c3021:76645#1\]
- Rationale: "document the error messages and expectations, and also provide the \\"fixed up\\" versions" \[silentpc:c14a13ff:4969\]
- Rationale: "the error messages of hbnf should be so good ... it is ALMOST like you can cut and paste the rfc into hbnf" \[silentpc:c14a13ff:j4471\]
- Rationale: "we don't have to worry about c89 or k&rc so the whole corpus of c files should be usable for testing our C parser" \[silentpc-opusplan:4a4c3021:j50519\]
- Precedent: RFC BNF (chosen; named by author): second corpus beside the OpenBSD daemons \[silentpc:c14a13ff:4969\]
- Precedent: parse.y (chosen; named by author): drop in replacement test case \[silentpc:c14a13ff:j4471\]
- Precedent: POSIX bnf/yacc corpus (chosen; named by author): same treatment as the rfc corpus \[silentpc-opusplan:4a4c3021:j4653\]
- Precedent: yacc/bison (considered; named by author): goal: compiler-compiler on par with them, but better \[silentpc:c14a13ff:j4471\]
- Precedent: pcc (considered; named by author): unlike it, no need to care about different arches \[silentpc-opusplan:4a4c3021:j50519\]
- Evidence: corpus/rfc/rfc3986-1.bnf and rfc3986-1.hbnf (the naming scheme); corpus/posix/ (shell.y, posix-shell-1.md); tests/sqlite.sh:2 "the SQLite amalgamation (sqlite3.c ...)"; tests/rfc.sh, tests/posix.sh, tests/c.sh, tests/c99.sh, scripts/c-corpus.sh
- Doc differs: corpus/posix has no README.md (the attribution and back-link note asked for on 2026-10-07 was not verified there)

### Test environment and harness
- Status: DONE — the edge-full image carries g++, rust and zig and the scripts assume it (latest decision 2026-09-30 \[silentpc:c14a13ff:j5514#1\])
- Decided: 2026-09-30 decided: "make sure edge-full has g++" \[silentpc:c14a13ff:j5514#1\]
- Rationale: "since we're already running inside docker (right?) why not update the script to know/assume that?" \[silentpc:c14a13ff:j15243\]
- Precedent: alpine:edge (chosen; named by author): install rust and zig in it \[hist-silentpc:fd13bc5f:h264\]
- Evidence: ABNF.md:22 "ada-toolchain:edge-full container (gcc-gnat, g++, rust and zig)"; tests/e2e.sh:4 same; tests/bytetest/ntpd-proof.sh:41 \`docker run ... ada-toolchain:edge-full\`; tests/bytetest/strict-cc.sh

### libc benchmark: musl and glibc
- Status: DONE — benches run on glibc only (latest decision 2026-10-24 \[silentpc-opusplan:4a4c3021:j58267#1\])
- Decided: 2026-10-24 changed: "for the next bench, no need to test with musl, just glibc." \[silentpc-opusplan:4a4c3021:j58267#1\]
- Precedent: musl (rejected; named by author): no need to test with musl next bench \[silentpc-opusplan:4a4c3021:j58267\]
- Precedent: glibc (chosen; named by author): just glibc \[silentpc-opusplan:4a4c3021:j58267\]
- Evidence: README.md:241 "All of it runs on glibc (Debian)"; bench/README.md:17 "Everything is measured on glibc"; bench/Dockerfile.glibc. Old musl commits (0fc6d42, dbf93f9) are history, no musl stage remains

## 07 Packaging and release

### Alpine aports
- Status: DONE — the overlay builds hbnf, mustache-ada, imsg-ada, libsodium-ada and buildabook from a git commit, not a release; the pin is bumped by hand and now lags HEAD (latest decision 2026-10-23 \[silentpc-opusplan:f7e53777:11237#1\])
- Decided: 2026-10-23 decided: aports for hbnf, mustache etc must track "the most recent versions (not releases, but git HEAD)" \[silentpc-opusplan:f7e53777:11237#1\]
- Rationale: "shared where feasible and sensible. stay in line with alpine praxis and ethos" \[hist-silentpc:1ea8e55b:h7\]
- Rationale: "if it crashes and doesn't run, we aren't providing an aport" \[silentpc-opusplan:aaaf0cf4:360\]
- Rationale: "no stale packages to be distributed!" \[silentpc-opusplan:aaaf0cf4:433\]
- Precedent: Alpine praxis and ethos (chosen; named by author): packaging follows Alpine practice \[hist-silentpc:1ea8e55b:h7\]
- Evidence: not checked: no APKBUILD in the clone (git ls-files finds none)
- Doc differs: README.md:450 "Packaged for Alpine by the ada-on-alpine aports overlay as testing/hbnf"
- Evidence: packaging repo: commit aa4cc00 (2026-10-23) "hbnf, mustache-ada, libsodium-ada, imsg-ada, buildabook: build git HEAD, not releases"; testing/hbnf/APKBUILD pkgver=0.7.0\_git20261022 \_commit=cd94a16

### Binary name
- Status: DONE — the program is hbnf, no hbnf\_cli (latest decision 2026-10-01 \[silentpc:c14a13ff:j15637#1\])
- Decided: 2026-10-01 decided: "hbnf is a cli, don't put \_cli in the name" \[silentpc:c14a13ff:j15637#1\]
- Rationale: "you don't call yacc as yacc\_cli after all" \[silentpc:c14a13ff:j8216\]
- Rationale: "hbnf is a cli, don't put \_cli in the name" \[silentpc:c14a13ff:j15637\]
- Precedent: yacc (chosen; named by author): program is called plain yacc, not yacc\_cli; same for hbnf \[silentpc:c14a13ff:j8216\]
- Evidence: hbnf.gpr:12 \`for Main use ("hbnf.adb")\`, :15 Exec\_Dir "."; not found: hbnf\_cli in any current file

### Build sh
- Status: DONE — ada-on-alpine/build.sh exists and was reworked repeatedly after the decision (latest decision 2026-10-01 \[silentpc:c14a13ff:8784#2\])
- Decided: 2026-10-01 decided: "yes, tighten build.sh" \[silentpc:c14a13ff:8784#2\]
- Precedent: RFC BNF (chosen; named by author): \| should mean roughly what it does in the early RFCs \[silentpc:c14a13ff:8784\]
- Precedent: ABNF (considered; named by author): / means what it means in the later RFCs \[silentpc:c14a13ff:8784\]
- Evidence: not found: ls build.sh; git log --diff-filter=D for build.sh; builds use gprbuild -P libhbnf.gpr (README.md:446)
- Evidence: packaging repo: build.sh; commits from 2026-10-11 to 2026-11-07 e.g. 57850dd "run abuild step by step with a ledger; keep the tree on failure", 74aefc1 "resume only once prepare has finished", 817249f "delete a build tree that cannot be resumed", bee85e9 "run tools/diagnose/\<package\>.sh after a failed step"

### Checksum automation
- Status: DONE — the release helper and the Ada program are in ada-on-alpine and generic for every aport (latest decision 2026-10-04 \[silentpc:fa150405:582#1\])
- Decided: 2026-10-04 decided: Release helper script and Ada program live in ada-on-alpine, "all 4 of our ada aports should be wired to use it" \[silentpc:fa150405:582#1\]
- Rationale: "either be a shell script, or an ada program, or an ada program that the shell script uses to make things simpler/clearer/more robust" \[silentpc:fa150405:363\]
- Evidence: not checked: ada-on-alpine is not available; nothing in this clone
- Evidence: packaging repo: tools/release-checksum.sh, tools/apkbuild\_bump.adb (commit 571dab2, 2026-10-04); tools/README.md "works for any aport under testing/, so hbnf, libsodium-ada and imsg-ada follow the same invocation"; README.md:256-263

### Gcc seed
- Status: DONE — the seed route is built: make-seed.sh and seed-restore.sh, CI seed stage for s390x and riscv64 (latest decision 2026-10-21 \[silentpc-opusplan:f7e53777:10312#1\])
- Decided: 2026-10-21 approved-proposal: "do the seed route": packages built locally stand in for the CI gcc build on s390x and riscv64 \[silentpc-opusplan:f7e53777:10312#1\]
- Rationale: accepted from the assistant: the simpler seed route, packages built locally stand in for the CI gcc build, which would otherwise hit the 6-hour limit \[silentpc-opusplan:f7e53777:10312\]
- Precedent: seed route (chosen; named by assistant, accepted): local packages replace CI gcc build on s390x and riscv64 \[silentpc-opusplan:f7e53777:10312\]
- Precedent: resume inside gcc build (considered; named by assistant, not taken up): several GB tree, near artifact limits, fragile \[silentpc-opusplan:f7e53777:10312\]
- Evidence: not checked: not in this clone
- Evidence: packaging repo: tools/make-seed.sh "Seeds exist for s390x and riscv64"; tools/seed-restore.sh; build-arch.yml:61 seed: "true"; commits 5f4cbb5, 82fe0cf "riscv64 has a gcc seed; run it"

### Library and binary names
- Status: DONE — the library is libhbnf, the binary hbnf (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j1211#1\])
- Decided: 2026-10-06 changed: Correction of the name: "libhbnf i mean" \[silentpc-opusplan:4a4c3021:j1211#1\]
- Rationale: "libbnf is supposed to be what the hbnf executable is a thin cli wrapper over" \[silentpc-opusplan:4a4c3021:j1202\]
- Rationale: "the hbnf binary reading the oconf grammar files should be all we need" \[silentpc:c14a13ff:j15910\]
- Rationale: "comment round tripping should be a characteristic of the grammar, not hbnf" \[silentpc:c14a13ff:j15910\]
- Evidence: libhbnf.gpr:36 \`for Library\_Name use "hbnf"\` (libhbnf.a); README.md:434 "libhbnf: the static Ada library (libhbnf.a, project libhbnf.gpr)"; hbnf.gpr Main hbnf

### Merging astbnf into hbnf
- Status: DONE — one package, one source tree, templates dir holds lexer, parser, grammar (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h234#1\])
- Decided: 2026-09-21 decided: "we've folded them together, there is no more astbnf just hbnf hbnf now covers all of astbnf" \[hist-silentpc:fd13bc5f:h234#1\]
- Rationale: "the hbnf grammar for astbnf lives where it should" \[hist-silentpc:fd13bc5f:h134\]
- Rationale: "as long as we can swap out grammars, hbnf is a good enough name" \[hist-silentpc:fd13bc5f:h184\]
- Rationale: "one package, one source tree" \[hist-silentpc:fd13bc5f:h138\]
- Evidence: hbnf.gpr and libhbnf.gpr; templates/ (ada\_\*.tmpl, c\_\*.tmpl); grammars/template.hbnf; no astbnf references anywhere

### Own-upstream aports (imsg, mustache-ada)
- Status: DONE — both aports exist and run their own checks in check() (latest decision 2026-10-01 \[silentpc:c14a13ff:j6577#1\])
- Decided: 2026-10-01 decided: exposed api should be "sweet simple and easy to use, human friendly, not verbose" \[silentpc:c14a13ff:j6577#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: mustache-ada and imsg-ada are separate repositories; f1ab596 notes hbnf no longer depends on mustache-ada (templates rendered by hbnf's own Mustache)
- Evidence: packaging repo: testing/mustache-ada/APKBUILD check() runs tests/mustache\_check and tests/spec\_check; testing/imsg-ada/APKBUILD (imsg-ada 0.4.1, commit c5669d0); mustache-ada HEAD c2d5967 is 7 README-only commits past the aport pin 35e3b1d; mustache.ads Render (Source, View) is the small API

### Pushing hbnf patches upstream
- Status: DONE — upstream hbnf now lists the four units the patch added; the aport still carries the patch (stale) (latest decision 2026-10-21 \[1889:1735#1\])
- Decided: 2026-10-21 approved-proposal: "yes, push the hbnf patch upstream" \[1889:1735#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not checked: upstream tracker not consulted
- Evidence: packaging repo: docs/bugs/hbnf-libhbnf-sources/report.txt "for the maintainer to commit in moebiusV/hbnf"; committed clone ff3c5d0: libhbnf.gpr:26-30 lists hbnf\_lookahead, hbnf\_tree\_sitter, hbnf\_wire-zig, hbnf\_wire-ada\_lang

### Releases, tagging and versions
- Status: DONE — v0.8.0 is tagged (latest decision 2026-10-23 \[silentpc-opusplan:4a4c3021:46977#1\])
- Decided: 2026-10-23 approved-proposal: "cut" the v0.8.0 release \[silentpc-opusplan:4a4c3021:46977#1\]
- Rationale: "hold the version bump until we stabilize" \[silentpc:c14a13ff:j15995\]
- Evidence: git tag lists v0.7.0 and v0.8.0; v0.8.0 dated 2026-10-23 11:43

### Repository location and split
- Status: DONE — hbnf is its own repository at moebiusV/hbnf; the cleaned history is the one in use (latest decision 2026-10-02 \[silentpc:c14a13ff:16975#1\])
- Decided: 2026-10-02 decided: Do "the rename dance; copy main to new branch while cleaning each commit, then rename the new branch to main, and push it, then drop the old main" \[silentpc:c14a13ff:16975#1\]
- Rationale: "ada-on-alpine is the repo for all my public ada projects, so hbnf goes there" \[hist-silentpc:3105d871:h164\]
- Rationale: "now we have to clean this repo and repush" \[silentpc:c14a13ff:j16779\]
- Precedent: one repo per package (chosen; named by assistant, accepted): cleanest, matches aports conventions; he then split hbnf out \[silentpc:c14a13ff:7729\]
- Precedent: ada-on-alpine repo (considered; named by author): first home for public Ada projects, later split out \[hist-silentpc:3105d871:h164\]
- Precedent: single ada-libs repo (considered; named by assistant, not taken up): alternative with independent tags \[silentpc:c14a13ff:7729\]
- Evidence: README.md:3 "Git Repo: github.com/moebiusV/hbnf", 8371d08 "README: link the repository and add a clone line"; the clone has hbnf at the root with 400 commits

### Single library, static binary, portability
- Status: DONE — one libhbnf library, the binary links fully static (latest decision 2026-09-26 \[silentpc:6ec412b3:j27839#1\])
- Decided: 2026-09-26 decided: "the hbnf binary must be static and shipped that way" \[silentpc:6ec412b3:j27839#1\]
- Rationale: "if it costs portability, forget it. unless there is some massive speedup efficiency win" \[hist-silentpc:1ea8e55b:h10\]
- Rationale: "the hbnf binary must be static and shipped that way" \[silentpc:6ec412b3:j27839\]
- Rationale: "single lib" \[hist-silentpc:fd13bc5f:h269\]
- Precedent: musl (chosen; named by assistant, accepted): portable; runs unchanged on the Debian host \[silentpc:6ec412b3:j27839\]
- Precedent: Debian gnat-14 toolchain (considered; named by assistant, not taken up): glibc rebuild on the host; he chose the static fix \[silentpc:6ec412b3:j27839\]
- Evidence: hbnf.gpr:28-31 "Fully static executable (musl)... for Switches (\\"Ada\\") use (\\"-static\\")"; libhbnf.gpr Library\_Name "hbnf"; README.md:60 "libhbnf, a static Ada library"

### Upstream and third-party code
- Status: DONE — checksums are the system libraries' own functions, borrowed code is attributed (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j16595#1\])
- Decided: 2026-10-17 decided: "stop renaming shit, crc32 is a standard function in a standard library that our generated parser should be linking in." \[silentpc-opusplan:4a4c3021:j16595#1\]
- Rationale: "if someone else already wrote them, just grab them with proper attribution" \[silentpc-opusplan:4a4c3021:j16576\]
- Rationale: "crc32 is a standard function in a standard library that our generated parser should be linking in" \[silentpc-opusplan:4a4c3021:j16595\]
- Rationale: "I should do an MR because we fixed a bug, but we aren't taking over maintainership" \[silentpc-opusplan:34019d9b:j2135\]
- Precedent: standard library crc32 (chosen; named by author): link it in by its own name, no renaming \[silentpc-opusplan:4a4c3021:j16595\]
- Precedent: afl++ in Alpine (chosen; named by author): send a merge request upstream, not take over maintainership \[silentpc-opusplan:34019d9b:j2135\]
- Evidence: 0cc3bc0 "Checksums come from the system's libraries, by their own names"; corpus/bech32/README.md:14 "Source and attribution" (Wuille, MIT); RFCPLAN.md:1464 (zlib, OpenSSL, the bech32 reference)

### astbnf aport and removal
- Status: DONE — no astbnf name remains in the repository (latest decision 2026-09-21 \[hist-silentpc:fd13bc5f:h239#1\])
- Decided: 2026-09-21 decided: "anywhere astbnf is referenced, in filenames, etc, deal with it; hbnf is the only thing that has ever existed" \[hist-silentpc:fd13bc5f:h239#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: grep -rli astbnf over the whole clone (excluding .git) returns no file

### gprbuild and gpr2-tools
- Status: DONE — the GPR2 tools are installed with a 2 suffix beside classic gprbuild (latest decision 2026-10-07 \[silentpc-opusplan:aaaf0cf4:j109#1\])
- Decided: 2026-10-07 decided: gprbuild and gpr2-tools relate by "Suffix GPR2 tools" \[silentpc-opusplan:aaaf0cf4:j109#1\]
- Rationale: accepted from the assistant: provides="gprbuild" would be wrong since gpr2-tools lacks gprname, gprls, gprlib/gprbind, \_default.gpr and the KB XML; chose "Suffix GPR2 tools" \[silentpc-opusplan:aaaf0cf4:j109\]
- Evidence: not checked: no aport in the clone
- Evidence: packaging repo: testing/gpr2-tools/APKBUILD "installed with a \`2\` suffix (gprbuild2, gprclean2, gprconfig2, gprinstall2 ...)"; README.md:37 gprbuild; arch="" (disabled, gprbuild2 crashes on library projects)

### mktemp fix
- Status: DONE — the hbnf aport check() generates into a mktemp -d directory, not a fixed /tmp path (latest decision 2026-09-22 \[hist-silentpc:1ea8e55b:h3#1\])
- Decided: 2026-09-22 decided: "apply the hbnf mktemp fix now" \[hist-silentpc:1ea8e55b:h3#1\]
- Rationale and precedent: none stated in the sources
- Evidence: not found: searched hbnf.adb, tests/\*.sh, bench/\*.sh, RFCPLAN.md and the commit subjects for mktemp (only \`mktemp -d\` uses in bench scripts)
- Evidence: packaging repo: testing/hbnf/APKBUILD check(): "Generate into a mktemp dir (the djb dance) rather than a fixed /tmp path, so two concurrent builds can't collide"; tmpdir=\$(mktemp -d)

## Relation to imp72, pcc and other projects

### Ada compact nodes
- Status: DONE — compact nodes are the default in C, Rust and Zig, and Ada holds records by access (latest decision 2026-10-31 \[silentpc-opusplan:4a4c3021:81480#1\])
- Decided: 2026-10-31 approved-proposal: "do it": hold remaining string and list fields by pointer, limited to choices with many such fields. \[silentpc-opusplan:4a4c3021:81480#1\]
- Rationale: accepted from the assistant: limit pointer-held fields to choices with many such fields so narrow nodes don't get bigger \[silentpc-opusplan:4a4c3021:81480\]
- Evidence: ABNF.md:113 "Compact nodes \| on by default; \`--no-compact\` for the old layout ... C, Rust (\`Option\<Box\<T\>\>\`) and Zig (\`?\*T\`); Ada's records already hold records by access"; commits eb40679, cd94a16, 6b41c3e; RFCPLAN.md:2932

### Algol60 corpus
- Status: DONE — the corpus directory exists with the report, the BNF and a grammar (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j16199#1\])
- Decided: 2026-10-17 decided: "make the algol60 corpus dir and commit it; save our sources so we can work on them later" \[silentpc-opusplan:4a4c3021:j16199#1\]
- Rationale: "since ned irons made an algol compiler from the bnf we should be able to as well" \[silentpc-opusplan:4a4c3021:j16198\]
- Rationale: Save the sources "so we can work on them later right now they are just wip" \[silentpc-opusplan:4a4c3021:j16199\]
- Precedent: Ned Irons' ALGOL compiler from the BNF (considered; named by author): precedent that a compiler can be built from the BNF \[silentpc-opusplan:4a4c3021:j16198\]
- Precedent: IMP65 (considered; named by author): said Irons later modified it into imp65; assistant could not verify \[silentpc-opusplan:4a4c3021:j16198\]
- Precedent: ALGOL 60 (chosen; named by author): asked if available as corpora \[silentpc-opusplan:4a4c3021:j16138\]
- Evidence: corpus/algol60/ (README.md, report.htm, syntax.txt, algol60.hbnf, SHA256SUMS); corpus/README.md:13 "in use (\`tests/algol60.sh\`)"

### Angle bracket rules
- Status: DONE — \<name\> is a rule, spaces allowed, a prose-val is an unwritten rule, all three answers built (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:5083#1\])
- Decided: 2026-10-06 decided: "yes to all three" assistant questions (punctuated names, %include body or whole rules, bare words terminals) \[silentpc-opusplan:4a4c3021:5083#1\]
- Rationale: "why limit \<\> to character terminals? can't a terminal be any type of token?" \[silentpc-opusplan:4a4c3021:4733\]
- Rationale: "if \<\> means a terminal which is a scanner, doesn't that mean we don't need %scan{} syntax?" \[silentpc-opusplan:4a4c3021:4752\]
- Rationale: Took the \<\> terminal out: "im not invertin naur's syntax" \[silentpc-opusplan:4a4c3021:j4996\]
- Precedent: Naur's BNF \<name\> nonterminal (chosen; named by author): refused to invert Naur's syntax \[silentpc-opusplan:4a4c3021:j4996\]
- Precedent: POSIX \<newline\> character names (considered; named by assistant, not taken up): POSIX writes \<...\> as terminal for characters \[silentpc-opusplan:4a4c3021:4733\]
- Precedent: ABNF (considered; named by assistant, not taken up): \<...\> as prose description or repeat count \[silentpc-opusplan:4a4c3021:4752\]
- Evidence: ABNF.md:176 "\`\<...\>\` \| ✓ reader \| A rule, as Backus and Naur write a nonterminal ... it may have spaces"; ABNF.md:345 "A name with a dot or a space in it is written in angle brackets"

### Ast walker
- Status: DONE — the AST walker is built in the four backends, with a size target of about 2 KB (latest decision 2026-10-18 \[silentpc-opusplan:4a4c3021:j21413#1\])
- Decided: 2026-10-18 decided: "a decent walker shouldn't add more than 2k to the output; very few things are deeply nested". \[silentpc-opusplan:4a4c3021:j21413#1\]
- Rationale: "a decent walker shouldn't add more than 2k to the output; very few things are deeply nested" \[silentpc-opusplan:4a4c3021:j21413\]
- Rationale: "the general case is to make an ast with useful walker functions"; obconf only shows arbitrary output \[silentpc-opusplan:4a4c3021:j21050\]
- Precedent: LBNF alternative labels (considered; named by assistant, not taken up): optional label on an alternative, not yet in \[silentpc-opusplan:4a4c3021:j21413\]
- Evidence: RFCPLAN.md:1755 "7d. The AST and its walkers (the user, 2026-10-18). Built in C 2026-10-18"; RFCPLAN.md:1769 "a walker should add no more than about 2 KB"; commits 415b07d, 30c612b, cbc0369

### Backreference
- Status: DONE — as K and \$K are built, named only, documented in contexts, \$K keeps the case property (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:90027#1\])
- Decided: 2026-11-03 decided: "how about do the as K / \$K next?" (before committing the reserved-word change) \[silentpc-opusplan:4a4c3021:90027#1\]
- Rationale: "if it is backreferencign a i"" then it should keep that same property" \[silentpc-opusplan:4a4c3021:j91711\]
- Rationale: accepted from the assistant: as K and \$K free %as and %same from the % sigil, consistent with the reserved-words decision \[silentpc-opusplan:4a4c3021:89039\]
- Precedent: regex-style backrefs with \$ (chosen; named by author): asked if rules could have regex style backrefs with \$ \[silentpc-opusplan:4a4c3021:89020\]
- Evidence: ABNF.md:121 "x as K ... \$K ... K is a name, never a number"; commit 1c9c7ac "Back-references are \`as K\` and \`\$K\`"; commit a4f96d9 "\`\$K\` keeps the case property"; tests/backref.sh

### Bare words
- Status: DONE — a bare word is a rule, terminals are quoted (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j5105#1\])
- Decided: 2026-10-06 changed: "bare words can be terminals or non terminals, i never separated them like that. a rule is a rule." \[silentpc-opusplan:4a4c3021:j5105#1\]
- Rationale and precedent: none stated in the sources
- Evidence: ABNF.md:213 "a bare word is a rule, a bare number or symbol gets a message saying to quote it"; ABNF.md:210 "a bare name and \`\<name\>\` are the same"

### C and C++ grammars and compiler
- Status: DONE — COBOL was factored; C factoring is done by the generator; C++ is not started (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:85677#1\])
- Decided: 2026-11-03 decided: "factor the fuck out of cobol and c" while continuing the triage. \[silentpc-opusplan:4a4c3021:85677#1\]
- Rationale: "unlike the pcc project we don't care about the different arches, and we don't have to worry about c89 or k&r c so the whole corpus of c files should be usable for testing" \[silentpc-opusplan:4a4c3021:j50519\]
- Rationale: "what is wrong with 17 nested rules? i liked your earlier plan just now of starting with a small c compiler" \[silentpc-opusplan:4a4c3021:48450\]
- Rationale: Try W-grammar to make the c and cpp grammars "more compact while maintaining readability" \[silentpc-opusplan:4a4c3021:j50519\]
- Precedent: pcc (considered; named by author): contrast: hbnf does not need multiple arches or c89/K&R \[silentpc-opusplan:4a4c3021:j50519\]
- Precedent: gcc and clang (considered; named by author): speed to beat \[silentpc-opusplan:4a4c3021:j50519\]
- Precedent: W-grammar (considered; named by author): possible way to compact C and C++ grammars \[silentpc-opusplan:4a4c3021:j50519\]
- Precedent: IMP72 rewrite rules and %emit templates (considered; named by assistant, not taken up): needed for the back half of the compiler \[silentpc-opusplan:4a4c3021:j49467\]
- Evidence: commit 146c138 "COBOL: 44 gaps; the grammar factored (4.6% fewer characters) with the same verdict on all 1,572 programs"; corpus/c/README.md:67 "alternatives that begin alike read that beginning once (\`tests/factor.sh\`, \`--no-factor\`)"; TODO.md:57 "automatic left-factoring through captures (26/48)" still open
- Doc differs: TODO.md:117 "ALGOL 68, C++ grammars: not started"; the C preprocessor grammar is not built (RFCPLAN.md:2940)

### COBOL grammar
- Status: DONE — the COBOL grammar exists and the koopa and proleap sets were looked at (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:87740#1\])
- Decided: 2026-11-03 decided: After committing, "do koopa and proleap sets"; asks why gnucobol fails some of the 9708 tests. \[silentpc-opusplan:4a4c3021:87740#1\]
- Rationale: "we need to be able to represent these languages in a compact, idiomatic way so it looks as much like pure bnf as possible." \[silentpc-opusplan:4a4c3021:j81605\]
- Rationale: "we can do full glr; remember the policy, we only pay for what we use." \[silentpc-opusplan:4a4c3021:j81605\]
- Precedent: pure BNF (chosen; named by author): grammars should look as much like pure bnf as possible \[silentpc-opusplan:4a4c3021:j81605\]
- Precedent: ALGOL 68 and C++ grammars (considered; named by author): listed beside COBOL as languages to represent compactly \[silentpc-opusplan:4a4c3021:j81605\]
- Precedent: GnuCOBOL (cobc, its test suite) (considered; named by author): asks why gnucobol fails some of the 9708 tests \[silentpc-opusplan:4a4c3021:87740\]
- Precedent: Koopa test sources (chosen; named by assistant, accepted): "do koopa and proleap sets" \[silentpc-opusplan:4a4c3021:87740\]
- Precedent: ProLeap COBOL parser test sources (chosen; named by assistant, accepted): "do koopa and proleap sets" \[silentpc-opusplan:4a4c3021:87740\]
- Evidence: corpus/cobol/README.md:49 "The ProLeap and Koopa test sources were looked at and add nothing"; tests/cobol/scan-baseline.txt, nist-baseline.txt
- Doc differs: corpus/cobol/README.md:8 "vendor extensions are left out", the chain's challenge about vendor forms is not settled in the code

### Character model
- Status: DONE — the plan lists step 9c as done (latest decision 2026-10-06 \[silentpc-opusplan:4a4c3021:j1426#1\])
- Decided: 2026-10-06 decided: "Pull the character model into 9c" (answer to multiple-choice question) \[silentpc-opusplan:4a4c3021:j1426#1\]
- Rationale and precedent: none stated in the sources
- Evidence: RFCPLAN.md:822 "Done: 0, 1, 2, 3, 3b, 4a–4e, 5, 7a, 9a, 9b, 9c, 12"; RFCPLAN.md:553 "step 9c retires it" (the second model)

### Checksum functions
- Status: DONE — a checksum is a library function that actions call, not built into hbnf (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j15851#1\])
- Decided: 2026-10-17 decided: Checksum-like code "should either be in the epilogue or in a separate library then our actions just call those functions from their library" \[silentpc-opusplan:4a4c3021:j15851#1\]
- Rationale and precedent: none stated in the sources
- Evidence: WIRE.md:279 "A checksum is a function in a library somebody else wrote and tested, and an action calls it by its own name"; corpus/bip39/bip39.h \`bip39\_checksum\` (WIRE.md:291)

### Cobol terminators
- Status: DONE — COBOL has the single scope-end rule using the up reference (latest decision 2026-11-04 \[silentpc-opusplan:4a4c3021:92785#1\])
- Decided: 2026-11-04 approved-proposal: "do it" (rebuild hbnf and convert COBOL to the single scope-end) \[silentpc-opusplan:4a4c3021:92785#1\]
- Rationale: accepted from the assistant: keep scope-end and build the up reference, rather than the conversion costing 125 more symbols \[silentpc-opusplan:4a4c3021:91799\]
- Rationale: "isn't that what meta/hyper rules are for?" (questioning the assistant's view that END-+K reads worse) \[silentpc-opusplan:4a4c3021:88733\]
- Precedent: W-grammar (considered; named by author): argued the END-+K terminator is what such rules are for \[silentpc-opusplan:4a4c3021:88733\]
- Precedent: as K conversion of terminators (rejected; named by assistant, accepted): "i was wrong, do the alternataive to scope-end()" \[silentpc-opusplan:4a4c3021:91843\]
- Evidence: corpus/cobol/cobol.hbnf:306 \`scope-end = \[ "END-" + \$K^ \]\`; commits dafb450, c64a60a; ABNF.md:122

### Code block purity
- Status: DONE — the plan says code blocks are not required to be pure (latest decision 2026-10-07 \[silentpc-opusplan:4a4c3021:5598#1\])
- Decided: 2026-10-07 decided: "i never said %where was pure. nor %scan. and especially not %action" \[silentpc-opusplan:4a4c3021:5598#1\]
- Rationale: "i never said %where was pure. nor %scan. and especially not %action" \[silentpc-opusplan:4a4c3021:5598\]
- Evidence: RFCPLAN.md:1338 "\`%where { }\` (decision 13): code, not required to be pure"

### Codepoints
- Status: DONE — the character layer treats a char as a code point decoded from UTF-8 (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j17538#2\])
- Decided: 2026-10-17 decided: "codepoints and chars are the same things; a utf8 char is a string that maps to a codepoint". \[silentpc-opusplan:4a4c3021:j17538#2\]
- Rationale: "doing it by layers should allow us to have 9 and 18 bit words, not just octets" \[silentpc-opusplan:4a4c3021:j17538\]
- Rationale: "codepoints and chars are the same things; a utf8 char is a string that maps to a codepoint" \[silentpc-opusplan:4a4c3021:j17538\]
- Evidence: ABNF.md:78 "code points, with UTF-8 decoded on input"; CHARLAYER.md:16 "UTF-8 code points as primitives (decode on input, match on code points)"

### Context sensitivity
- Status: DONE — the README claims context-sensitive languages and contexts are built (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:16373#1\])
- Decided: 2026-10-17 decided: "surely imp72 could have parsed c++?"; "I never agreed to 'context free' grammars. ever."; semantic actions store context; question is the right unjarring way to access it. \[silentpc-opusplan:4a4c3021:16373#1\]
- Rationale: "isn't the point of semantic actions to store data in a way that can be later accessed to provide context to the parser?" \[silentpc-opusplan:4a4c3021:16373\]
- Rationale: "I never agreed to \\"context free\\" grammars. ever." \[silentpc-opusplan:4a4c3021:16373\]
- Rationale: Access to context should be one "that isn't jarring or surprising to bnf users, and that is pleasant and easy to use" \[silentpc-opusplan:4a4c3021:16373\]
- Precedent: IMP72 (considered; named by author): "surely imp72 could have parsed c++?" \[silentpc-opusplan:4a4c3021:16373\]
- Evidence: README.md:44 "hand-written lexer hacks, which is what context-sensitive languages need"; CONTEXTS.md (status table, \`context\`, \`%bind\`, \`%where\`), corpus/c/README.md "typedef context"

### Default prefix
- Status: DONE — bnf\_ is the default prefix and the daemon grammars say prefix none (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j9200#1\])
- Decided: 2026-10-17 decided: With bnf\_ as default prefix: "Everything, but daemon grammars opt out". \[silentpc-opusplan:4a4c3021:j9200#1\]
- Precedent: META II, SNOBOL4, IMP72 (considered; named by author): compare to hbnf's %scan/%action; design might learn from them \[silentpc-opusplan:4a4c3021:j8543\]
- Evidence: ABNF.md:254 "\`bnf\_\` when it names none"; ABNF.md:262 "\`prefix none\` ... the nine daemon grammars say so"

### Enum index
- Status: DONE — "foo"@7 is the enum number spelling (latest decision 2026-10-17 \[silentpc-opusplan:4a4c3021:j14453#1\])
- Decided: 2026-10-17 decided: "don't overload =; how about '"foo"@7' ?" \[silentpc-opusplan:4a4c3021:j14453#1\]
- Rationale: "don't overload =" \[silentpc-opusplan:4a4c3021:j14453\]
- Rationale: Wanted to specify an enum index "the way C does, so we don't have to rely on ordering", "in case of sparse lists" \[silentpc-opusplan:4a4c3021:j14258\]
- Precedent: C enum explicit values (chosen; named by author): index number given per enumerator \[silentpc-opusplan:4a4c3021:j14258\]
- Evidence: WIRE.md:316 \`proto = "icmp"@1 \| "tcp"@6 \| "udp"@17 \| "sctp"@0x84\`; README.md:79 "enum numbers (\`"icmp"@1\`)"; tests/enumval/

### Extra parsers
- Status: DONE — xml, sgml, html and graphql grammars exist (latest decision 2026-11-03 \[silentpc-opusplan:4a4c3021:j90610#1\])
- Decided: 2026-11-03 decided: "you might as well do xml sgml html and gql parsers also" \[silentpc-opusplan:4a4c3021:j90610#1\]
- Rationale and precedent: none stated in the sources
- Evidence: corpus/xml, corpus/sgml, corpus/html, corpus/graphql (corpus/README.md rows); commits 4df02d2 XML 1.0, f770a26 SGML, ffb261d GraphQL

### Fork autodetect
- Status: DONE — forks are found by the generator and listed on stderr, but only under --forks (latest decision 2026-10-18 \[646:24#1\])
- Decided: 2026-10-18 decided: "The fork points can be logged to stout when generating the parser". \[646:24#1\]
- Rationale: "I want the ambiguous forks to be autodetected. I don't want to need to annotate them." \[646:22\]
- Precedent: IMP72 keep-alternatives-alive parsing (considered; named by assistant, not taken up): alternatives kept until semantics decide \[646:22\]
- Evidence: ABNF.md:112 "Local forks \| \`--forks\` \| A rule whose alternatives can start alike ... The forks are listed on stderr (\`--quiet-forks\` silences them)"; tests/forks/
- Doc differs: ABNF.md:112 says "Off by default" and "listed on stderr" (the decision says stdout and no annotation; annotation is not needed, so only the default and the stream differ)

### Grammar dialects
- Status: DONE — c79 is the name everywhere; the dialect line exists (latest decision 2026-10-27 \[silentpc-opusplan:4a4c3021:j60440#1\])
- Decided: 2026-10-27 decided: "call it c79 instead of c32v". \[silentpc-opusplan:4a4c3021:j60440#1\]
- Rationale: HBNF "can be Hyper BNF", "while retaning the earlier hartmeier brauer etc meaning" \[silentpc-opusplan:4a4c3021:j5848\]
- Rationale: "the spaced form is bogus"; if --ebnf is passed, use the EBNF syntax "3 \* x" \[silentpc-opusplan:4a4c3021:5836\]
- Precedent: ISO EBNF (chosen; named by assistant, accepted): used only when --ebnf is passed \[silentpc-opusplan:4a4c3021:5836\]
- Precedent: ABNF (considered; named by author): asked how ABNF represents exactly 3 \[silentpc-opusplan:4a4c3021:5836\]
- Precedent: yacc (chosen; named by author): call yacc the YBNF dialect \[silentpc-opusplan:4a4c3021:j5847\]
- Evidence: corpus/c/c79.hbnf, corpus/c/README.md:8 "\`c79.hbnf\`, \`c79-words.hbnf\` \| the C of UNIX/32V (1979)"; no "c32v" file or text in the clone; ABNF.md:353 "\`dialect bnf \| ebnf \| abnf \| ybnf \| hbnf\`, a line like \`language\` and \`include\`"; ABNF.md:3 "named for Hartmeier, Brauer, Norby and Floeter, and read as HyperBNF"
- Doc differs: corpus/c/README.md:16 says "C11, C17 and C23 are not in it: no yacc grammar of theirs exists to measure", RFCPLAN.md:2940 lists "C17 and C23 grammars" as unbuilt (the 2026-10-24 "upgrade to c23 parsing" is not built; c11.hbnf is the newest)

### IMP72 relation
- Status: DONE — the cancellation is stated in the plan, the corpus index and METACOMPILERS.md (latest decision 2026-10-22 \[silentpc-opusplan:4a4c3021:j42626#2\])
- Decided: 2026-10-22 decided: "cancel imp72 altogether. imp72 is its own thing and will get its own compiler" \[silentpc-opusplan:4a4c3021:j42626#2\]
- Rationale: "imp72 is its own thing and will get its own compiler" \[silentpc-opusplan:4a4c3021:j42626\]
- Rationale: Sources may go in the repo corpus: "it was gov't research which is public domain" (before the cancellation) \[silentpc-opusplan:4a4c3021:9833\]
- Precedent: IMP72 as an hbnf corpus (rejected; named by author): cancelled; gets its own compiler \[silentpc-opusplan:4a4c3021:j42626\]
- Precedent: IMP72 bootstrapped from a minimal BNF compiler (considered; named by author): asked if hbnf could fill that role \[silentpc-opusplan:4a4c3021:9515\]
- Precedent: translating rsyn and running it (considered; named by author): asked if rsyn could be translated \[silentpc-opusplan:4a4c3021:9741\]
- Precedent: Ada (considered; named by author): compare imp72 to Ada, both based on algol \[silentpc-opusplan:4a4c3021:j11314\]
- Evidence: RFCPLAN.md:842 "The IMP72 sources (\`corpus/imp72/\`) are cancelled (the user, 2026-10-22: IMP72 \\"is its own thing and will get its own compiler\\")"; corpus/README.md "cancelled: IMP72 gets its own compiler"; METACOMPILERS.md:3

# Precedents, by name

- The systems, languages, standards and designs named as referents, with the subjects they shaped; chosen = his choice follows it, rejected = he turned it down, considered = compared or cited.

- ABNF: chosen in RFC friendliness; astbnf and its split from hbnf; Readability and syntax principles; Example rules; Semicolon, newline and whitespace tokens; Preamble and epilogue, prose values and rbnf and 8 more, rejected in Literals and number syntax, considered in Compiler compiler; Tree-sitter as a goal; Abnf numeric; Literals and number syntax; Lexer folded into the grammar; Choice and alternation operators and 9 more
- yacc: chosen in Compact C grammar; Comments; Pretty printer back end and printconf; Benchmarks against yacc and parser efficiency; Binary name; USENIX paper and 1 more, rejected in Contexts, islands and grammar switching, considered in Name: HBNF and HyperBNF; Compiler compiler; Purpose and goal; Comparison with yacc; Include and overrides; Rule typing and typed values and 3 more
- parse.y: chosen in Scope: characters, octets, bit fields and real languages; List operations (listops); Keyword table for keywords as values; Expr rule; Output shaped like OpenBSD parse.y; TAILQ handling and parse.y drop-in output and 5 more, rejected in hbnf versus obconf: distinction and naming, considered in Comma list operator
- W-grammar: chosen in Name: HBNF and HyperBNF; Comparison with yacc; Rule definition operators; W-grammar adoption, rejected in Compact C grammar, considered in Newlines, whitespace and the hidden directive; Operator table; Grammar size and line-savings tables; Emit syntax and actions; C and C++ grammars and compiler; Algol68 hbnf and 1 more
- tree-sitter: chosen in Priority list; Tree-sitter back end and limits; Plan documents and step order; Benchmark documentation and scripts, considered in Scope: characters, octets, bit fields and real languages; Tree-sitter as a goal; Parsing model, packrat and parse path; Token tables and tree-sitter appendix; Plan documents and step order
- RFC BNF: chosen in End goal; What hbnf is; Rule typing and typed values; Error messages and reporting; Test corpora; Build sh and 1 more, considered in Choice and alternation operators
- EBNF: chosen in Readability and syntax principles, considered in Scope: characters, octets, bit fields and real languages; Compiler compiler; EBNF or PEG instead of yacc; RFC ebnf and obsolete forms; Pretty printer back end and printconf
- IMP72: chosen in Index base, considered in Scope: a meta compiler, hooks in any language; LR, left recursion, GLR and match strategy; Bitfield syntax; Context sensitivity
- yacc/bison: chosen in End goal, rejected in What hbnf is, considered in EBNF or PEG instead of yacc; Error messages and reporting; Test corpora
- ALGOL 60: chosen in RFC friendliness; Algol60 corpus, considered in Error messages; Index base
- facet language: considered in Other projects; C79 facetlang
- recursive descent: chosen in RFC friendliness; Dispatch efficiency; YAML and TOML grammars, considered in Parsing model, packrat and parse path
- simdjson: chosen in Speed goals against the top parsers; Closing the speed gap with rapidyaml and simdjson, rejected in Speed goals against the top parsers, considered in Skip directive notation
- ALGOL 68: considered in W-grammar adoption; W-grammar notation and readability; Emit syntax and actions
- ANTLR: chosen in Benchmark documentation and scripts, considered in LR, left recursion, GLR and match strategy; Other documents and notes
- Common Lisp restart: considered in Priority list; Error messages and reporting; C parser bakeoff
- GLR: chosen in Pay only for what is used, considered in LR, left recursion, GLR and match strategy; C++ compatibility
- Mustache: chosen in Mustache templating in the emitters, rejected in Retiring the interpreter and HBNF\_Config; Buildabook
- OpenBSD daemons: chosen in End goal; Error messages and reporting; Drop in replacement
- Other BNF dialects: chosen in Choice and alternation operators; Patches and tarballs, considered in Daemon grammars
- pcc IR: considered in Other projects
- PEG: considered in EBNF or PEG instead of yacc; Pretty printer back end and printconf; Benchmarks against yacc and parser efficiency
- RBNF: rejected in Character-level lexing; Preamble and epilogue, prose values and rbnf; Rule definition operators
- rewrite rules: chosen in Mustache templating in the emitters, considered in Markdown grammar and rendering; BIP39 tests
- Sitaker's metacircular compiler: chosen in HISTORY.md article, considered in Correctness first; Plan documents and step order
- BNF spellings: chosen in Character-level lexing; Rule definition operators
- C: chosen in Language header; Index base
- C numbers: chosen in Core number types; Regex strings
- CDL: considered in Hyper rules and meta rules; Cdl history
- fast\_float: chosen in Speed goals against the top parsers, considered in Skip directive notation
- \${foo} template style: considered in Template engine
- JSON/TOML/YAML libraries: considered in Priority list; Speed goals against the top parsers
- Knuth: chosen in HISTORY.md article, considered in Token tables and tree-sitter appendix
- META II: considered in Scope: a meta compiler, hooks in any language; Meta II ideas
- musl: chosen in Single library, static binary, portability, rejected in libc benchmark: musl and glibc
- mustache-ada: chosen in Mustache templating in the emitters; Plan documents and step order
- pcc: considered in Test corpora; C and C++ grammars and compiler
- POSIX shell grammar: chosen in POSIX BNF and yacc grammars; POSIX shell grammar
- pugixml: considered in Rollback and trusted mode; XML benchmark, speed and conformance
- Python pivot: rejected in Which hbnf version to use; hbnf grammars as single source of truth elsewhere
- rapidyaml: chosen in Speed goals against the top parsers, considered in Closing the speed gap with rapidyaml and simdjson
- red-black trees: chosen in Data structures: rbtree or hash table, considered in TAILQ handling and parse.y drop-in output
- RFC packet diagrams: chosen in Index base; Bitfield syntax
- stock BNF: chosen in Contexts, islands and grammar switching; Working rules and workflow
- TAILQ: chosen in TAILQ handling and parse.y drop-in output; Byte identity against parse.y
- ::= := =: chosen in W-grammar notation and readability
- 32V cgram.y: rejected in C parser bakeoff
- Ada: considered in IMP72 relation
- ada-on-alpine repo: considered in Repository location and split
- aeson: chosen in Haskell happy/alex benchmark
- affix grammars: considered in Cdl history
- afl++ in Alpine: chosen in Upstream and third-party code
- ALGOL 68 and C++ grammars: considered in COBOL grammar
- Alpine aports: chosen in Container languages
- alpine:edge: chosen in Test environment and harness
- Alpine praxis and ethos: chosen in Alpine aports
- ::= := = and :: considered in Hyper rules and meta rules
- ::= := = and (\* \*) /\* \*/ comments: chosen in POSIX BNF and yacc grammars
- \${} and \$\$ templating: rejected in Mustache templating in the emitters
- angle-bracket \<\> terminals (BNF, RFC 822 uses): considered in Scan and action blocks, predicates and terminology
- ANTLR / LL(\*) / PEG: considered in Parsing model, packrat and parse path
- ANTLR target languages: considered in Back end spectrum and future back ends
- APL NOT ~: chosen in Negation
- as K conversion of terminators: rejected in Cobol terminators
- BIP-39: chosen in BIP39 tests
- BIP-39 and bech32: chosen in Unified text and binary syntax, retiring units
- bison: chosen in Benchmark documentation and scripts
- Bison term\[lhs\]: considered in Bitfield syntax
- BLISS and hardware manuals: considered in Index base
- bnf, ebnf, abnf, ybnf: considered in Name: HBNF and HyperBNF
- byacc: chosen in Benchmark documentation and scripts
- C++11 and later (any reasonable version): chosen in C standard
- C bit-field colon: chosen in Bitfield syntax
- C bitwise complement ~: chosen in Negation
- C enum explicit values: chosen in Enum index
- C++ extern "C" header: considered in Back end spectrum and future back ends
- C syntax for numbers and strings: chosen in Literals and number syntax
- C syntax for strings: chosen in Patches and tarballs
- C typedef: considered in Facts stored by matched rules
- C11/C17/C23: rejected in C parser bakeoff
- C99: chosen in C standard
- cfront: rejected in C standard
- cJSON and jansson: considered in hbnf JSON parser for the watchers
- COBOL: considered in Facts stored by matched rules
- COBOL, ALGOL 68, C++ grammars: chosen in Pay only for what is used
- COBOL embedded JCL, SQL, CICS, PICTURE: considered in Working rules and workflow
- COBOL embedding JCL, SQL, CICS: considered in Contexts, islands and grammar switching
- Common Lisp #': considered in Percent prefix and suffix
- compiled-in default templates: rejected in Runtime templates and search path
- cset shield / isolcpus: considered in CPU pinning
- D, Fortran, Free Pascal, Nim, Odin, Objective C, ATS, vlang: chosen in Container languages
- DCG: considered in Hyper rules and meta rules
- Debian bug report system: chosen in Debug policy
- Debian gnat-14 toolchain: considered in Single library, static binary, portability
- DFA: chosen in Performance work
- Erlang bit syntax: chosen in Bitfield syntax
- expat: considered in XML benchmark, speed and conformance
- Forth "drop": considered in Rollback and trusted mode
- gcc and clang: considered in C and C++ grammars and compiler
- gcc bison grammar: chosen in C parser bakeoff
- gcc error recovery productions: considered in Error messages and reporting
- glibc: chosen in libc benchmark: musl and glibc
- GnuCOBOL (cobc, its test suite): considered in COBOL grammar
- Go, Java, JavaScript, Common Lisp, newLISP: chosen in Back end spectrum and future back ends
- Go syntax: considered in Emit syntax and actions
- hash table: rejected in Data structures: rbtree or hash table
- Haskell: considered in Raku comparison and benchmark
- Haskell Happy/Alex: chosen in Haskell happy/alex benchmark
- hbnf grammar as source of truth: chosen in hbnf grammars as single source of truth elsewhere
- hbnf main (git HEAD): chosen in Which hbnf version to use
- IMP: chosen in Comparison with yacc
- IMP65: considered in Algol60 corpus
- IMP72 as an hbnf corpus: rejected in IMP72 relation
- IMP72 bootstrapped from a minimal BNF compiler: considered in IMP72 relation
- IMP72 keep-alternatives-alive parsing: considered in Fork autodetect
- IMP72 rewrite rules and %emit templates: considered in C and C++ grammars and compiler
- int16 int32 hexint decint octint: considered in Abnf numeric
- irc.v4 (Go IRC library): considered in Use hbnf for IRC and soju
- ISO EBNF: chosen in Grammar dialects
- iterative LR: chosen in LR, left recursion, GLR and match strategy
- Jeff Fox (Forth): considered in Round tripping
- JSON spec: rejected in hbnf grammars as single source of truth elsewhere
- keyword table: chosen in Statement-at-a-time parsing
- Knuth, premature optimization: chosen in Correctness first
- Koopa test sources: chosen in COBOL grammar
- lazy evaluation: considered in W-grammar termination and cycle detection
- LBNF alternative labels: considered in Ast walker
- libxml2 SAX2: considered in XML benchmark, speed and conformance
- LLVM ORC JIT and liblld: considered in C79 facetlang
- local QEMU: considered in Continuous integration
- makefile: chosen in Check timings and makefile style
- manpages and usage text: chosen in Other documents and notes
- md2html.py standalone renderer: considered in Markdown grammar and rendering
- META II, IMP72, SNOBOL4: considered in Raku comparison and benchmark
- META II, SNOBOL4, IMP72: considered in Default prefix
- most commonly used libraries per format: chosen in Library benchmarks (JSON, TOML, YAML)
- Mozeson: chosen in HISTORY.md article
- Naur's BNF \<name\> nonterminal: chosen in Angle bracket rules
- Ned Irons' ALGOL compiler from the BNF: considered in Algol60 corpus
- old-style grammar notation (yacc): chosen in Grammar size and line-savings tables
- one repo per package: chosen in Repository location and split
- OpenBSD: chosen in C standard
- OpenBSD conf.c/conf.h: considered in conf removal
- OpenBSD configuration language (oconf): chosen in What hbnf is
- OpenBSD configuration style (obconf): chosen in hbnf versus obconf: distinction and naming
- OpenBSD defines: chosen in Defines
- OpenBSD httpd, relayd, ntpd: considered in obconf wording in the docs
- OpenBSD pf macros (text substitution): rejected in Macros
- OpenBSD queue.h and RB\_HEAD tree: chosen in Layouts (tailq, rb, ast)
- packrat: rejected in Parsing model, packrat and parse path
- pandoc: considered in Markdown grammar and rendering
- pcc (c99 plus gnu extensions): chosen in C parser bakeoff
- PEG / ANTLR: considered in Hyper rules and meta rules
- PEG, regex, SNOBOL: considered in Negation
- perfect hash table: considered in Data structures: rbtree or hash table
- pfctl rule macros at grammar level: considered in Macros
- POSIX bnf/yacc corpus: chosen in Test corpora
- POSIX BNF / yacc grammars: chosen in POSIX BNF and yacc grammars
- POSIX \<newline\> character names: considered in Angle bracket rules
- \$ prefix for metanotions: considered in W-grammar adoption
- principle of least astonishment: chosen in HISTORY.md article
- printf format specifiers: considered in Abnf numeric
- ProLeap COBOL parser test sources: chosen in COBOL grammar
- pure BNF: chosen in COBOL grammar
- pure functional style (ban on in out): rejected in Ada style
- Python: considered in Index base
- Python PEG: considered in Patches and tarballs
- Python re/r strings: chosen in Regex strings
- Python XML parser: considered in XML benchmark, speed and conformance
- Raku grammars: chosen in Raku comparison and benchmark
- Raku slangs: considered in Contexts, islands and grammar switching
- rbtree instead of hash table: considered in Hash table and interning
- regex as DFA: considered in Dfa emission
- regex ^ complement (Perl, MUMPS): rejected in Negation
- regex-style backrefs with \$: chosen in Backreference
- regex type constructs: considered in Dotted words
- resume inside gcc build: considered in Gcc seed
- RFC 3986 first-match-wins (host/IPv4address): chosen in Alternatives, ordered choice and phrase exceptions
- Rust, Zig, Ada: considered in Language header
- sed: chosen in Error messages
- seed route: chosen in Gcc seed
- self-hosted runner: considered in Continuous integration
- single ada-libs repo: considered in Repository location and split
- SNOBOL4: considered in Scope: a meta compiler, hooks in any language
- something superior to tailq: considered in TAILQ handling and parse.y drop-in output
- standard library crc32: chosen in Upstream and third-party code
- std library functions: chosen in Performance work
- string views: chosen in String views as the default
- symbol table lookups: considered in C++ compatibility
- table lookup: chosen in Dispatch efficiency
- table syntax: rejected in Compact C grammar
- TAILQ conf struct: chosen in Drop in replacement
- taskset / docker --cpuset-cpus: chosen in CPU pinning
- Theodore Beale's writing style: chosen in HISTORY.md article
- token level grammar with RFC clothing: chosen in Readability and syntax principles
- token tables: considered in Token tables and tree-sitter appendix
- TOML for config: considered in Buildabook
- translating rsyn and running it: considered in IMP72 relation
- tree-walking interpreter vs state machine: considered in Output shaped like OpenBSD parse.y
- Typst: chosen in Markdown grammar and rendering
- Urbit: rejected in USENIX paper
- /usr/share/hbnf and ~/.local/share/hbnf: chosen in Runtime templates and search path
- VALGOL: considered in Meta II ideas
- yacc and PEG: considered in Dispatch efficiency
- yacc, EBNF, ABNF: considered in Rule typing and typed values
- yacc, EBNF and ABNF: considered in LR, left recursion, GLR and match strategy
- yacc/lex split: considered in Character-level lexing
- ybnf/ebnf/abnf/bnf dialect directives: chosen in RFC friendliness
- "you are not expected to understand this" comments: rejected in Preamble and epilogue, prose values and rbnf

# Where the current docs or code differ from the decisions (62)

- Name: HBNF and HyperBNF: README.md:27 says "YBNF (yacc's grammar language)", which names ybnf as yacc's notation, as the 2026-10-23 decision allowed; no "ybnf is ours" framing found
- Compiler compiler: TUTORIAL.md:175 says the Ada column is "none yet" for visit/fold
- Shipped grammars (JSON, TOML, YAML, obconf): README.md:39 says "HyperBNF ships with the basic formats ready to use: JSON, TOML and YAML" (obconf not named there; it is in grammars/ and obconf.md)
- Comparison with yacc: README.md:63 lists corpus/imp72 as "cancelled as a target: IMP72 will get its own compiler"
- Closing the speed gap with rapidyaml and simdjson: TODO.md:11 says simdjson and rapidyaml read 20-35% high on the busy machine; hbnf rows are upper bounds; a quiet rerun is pending. AVX2/AVX-512 (potential) not in the repository (TODO.md:89 mentions only an SSE2 loop)
- Newlines, whitespace and the hidden directive: CONTEXTS.md:917 and TODO.md items 4, 5 say \`hidden\` still accepts only pure-text rules, and "ws is structure" (2026-11-03 potential) needs a silent variant, not built
- Language header: hbnf\_grammar.adb:945 finds the first word "language" anywhere, not only as the first non-comment; RFCPLAN.md:112 says "\`language\` (the language of the file's code blocks)"
- Semicolon, newline and whitespace tokens: ABNF.md:342 still lists a \`wordchars "…"\` directive and RFCPLAN.md:116 lists \`wordchars\` among whole-parser directives
- Include and overrides: RFCPLAN.md:100 says the override works "in the same file or another" (cross-file override is supported, though he said it was not needed)
- Lexer folded into the grammar: the decision of 2026-09-30 \[silentpc:6ec412b3:j66646#1\] named "core.hbnf"; the file is grammars/obconf.hbnf plus common.hbnf (tests/include/core.hbnf is only a test)
- Choice and alternation operators: RFCPLAN.md:92 (amended 2026-10-06) says "The automaton check needs no factoring" for ordering a union, while factoring is a separate built step
- Scan and action blocks, predicates and terminology: RFCPLAN.md:1787 "a scanner written in C (a \`jet\`)"; RFCPLAN.md:2750 "jet or a scanner action"; METACOMPILERS.md:268 "a scanner jet that replaces a page of rules"; templates/c\_rule\_jet.tmpl and "jet" in hbnf\_c.adb are code names
- Ascii hbnf: RFCPLAN.md:178 puts the classes in common.hbnf, ascii.hbnf only the named characters (as the 2026-10-02 file split decided)
- Percent prefix and suffix: CONTEXTS.md:23 (decision of 2026-11-02) retires the \`%\` forms in hbnf's own notation, beyond "leave % alone"
- Char literals: CONTEXTS.md:909 (section 26 item 1, "the user", 2026-11-03) and TODO.md:44 "\`'c'\` is \`"c"\`" queue a change that makes the two spellings one thing; not built
- Rule definition operators: no stale text; the old all-equal rule survives only as the dialect behaviour
- Namespaces: CONTEXTS.md:7 "the dot is scope and never part of a name, strict lookup" (qualified names, close to what was rejected, from a later user decision not in this chain)
- Common grammar files (common, obconf, ascii): the 2026-10-02 line "include all ascii.hbnf stuff in common; ascii.hbnf only for non-printable" \[silentpc:c14a13ff:j18687#1\] conflicts with the later punctuation line; the repository follows the later one
- POSIX BNF and yacc grammars: corpus/posix/shell.md reads yacc as pasted, more than "need not support cut and paste"
- W-grammar adoption: the chain says "wgrammar dialect"; no \`dialect wgrammar\` exists, the notation is part of the default hbnf one (ABNF.md:353 dialects: bnf, ebnf, abnf, ybnf, hbnf)
- Skip directive notation: tests/ladder/cases.txt has 27 inputs and the test finds six levels, not a 54-fold ladder; RFCPLAN.md item 19 "Not done: ... the same ladder fast path in Rust, Zig and Ada"
- Contexts, islands and grammar switching: CONTEXTS.md:9 "built, phase 1: white space only ... tree-sitter refuses a switch"; TODO.md:79-80 switch phase 2 and 3, labels, bounded island not built
- Pattern features (phrases, end splice, plural, join): CONTEXTS.md:19 phase 3 (phrase variants in \`ast\`, the tape case) "decided design; not built", which is the approved 85990/86079 follow-up, outside the Now line
- bol and eol: ABNF.md:121 refuses \`^\`/\`\$\` in \`r"..."\`, where the Now line says they "work as normal"; the later bol/eol design (CONTEXTS.md:13) is the standing state
- Pretty printer back end and printconf: no \`printconf\` found anywhere in the repository
- conf removal: TODO.md:88 says "The conf glue (\`--conf\`) out of the templates into an included C header", which puts \`--conf\` in a doc
- Implementation language: helper scripts in Python remain outside the generator (tools/hbnf\_modernize.py, tools/cobol\_extract.py, scripts/grammar-size.py)
- The --idref serializer and multiple trees: IDREF.md says "The per-type \`\*\_find()\` helpers and the merge side ... are not generated"
- TAILQ handling and parse.y drop-in output: the mechanism is \`layout tailq\` (layout directories), not literally preamble/epilogue and jets as the Now line says
- Back end spectrum and future back ends: the comment fix commit predates the 2026-10-02 approval by a day, so it may be a different Ada comment bug; no later commit names "Comment" for Ada
- Statement-at-a-time parsing: ABNF.md:347 "C only (the other backends warn and parse the whole file)"
- Retiring the interpreter and HBNF\_Config: RFCPLAN.md:546,565 still say "the interpreter and every backend" in older criteria text (stale history)
- C standard: tests/backref.sh and tests/ladder.sh compile generated C with \`-std=gnu11\`, not C99; README.md:20 plans "C17 and C23 for the C family" (grammars, not the backend)
- obconf parser: drop-in for parse.y and --conf: TODO.md:88 says "The conf glue (\`--conf\`) out of the templates into an included C header." as still open
- Tree-sitter back end and limits: hbnf\_tree\_sitter.adb:336 says "There is no limit on depth" (beyond the 500 asked for, which also answers the 'why have any limit' question)
- Slice syntax for strings and bits: RFCPLAN.md:1514 says "\`foo:4\` is 4 units and \`foo@1:4\` is 4 units at offset 1" (offset, then length after the colon), not ":bits@offset"
- Unified text and binary syntax, retiring units: WIRE.md:341 "Units. ... a number may carry a unit, \`b\` bits, \`B\` bytes, \`c\` code points, \`W\` words" as a design (the \`b\`/\`B\`/\`c\`/\`W\` suffixes are not built)
- Template engine: the mechanism is now Mustache \`{{ }}\` rather than the \`\${hole}\` of the 2026-09-30 decisions (see the next subject)
- Test corpora: corpus/posix has no README.md (the attribution and back-link note asked for on 2026-10-07 was not verified there)
- BIP39 tests: tests/wire/bip39\_phrase.hbnf:1 says "12 to 24 words" with no warning (an older, simpler test)
- Bench speed: TODO.md:12 says everything was rerun on 2026-11-05 on a busy machine; no doc states an xml-only bench rule
- Compiler flags: README says -O2; the question named -Os, and he accepted any flags as long as they are the same
- XML benchmark, speed and conformance: TODO.md:46 "The README claim: 'fastest conforming XML parser' only after a quiet run shows it for the tree (the tape already is)"; busy-machine tree 4.3 ms against libxml2 SAX2 4.8
- Alpine aports: README.md:450 "Packaged for Alpine by the ada-on-alpine aports overlay as testing/hbnf"
- Container languages: build-full-image.sh:13-18 still lists fpc, odin, vlang as "this repo's aports" (stale)
- Library headers (bip39.h, per-function .h): RFCPLAN.md:1464 "by their own names, with corpus/bip39/bip39.h using SHA256"; no lib/ directory at HEAD
- USENIX paper: USENIXSUBMISSION.md:372 says "the rule a human already assumes" (one "assumes" remains; the line numbers of the decision are of an older text)
- Abnf relation: ABNF.md never uses the word "simplification"; it says "what it leaves out, by design or not yet"
- Ada style: README.md Contributing says "no \`out\`/\`in out\` parameters", while the 2026-10-04 \[silentpc:fa150405:343#1\] decision rejected a ban (minimize only)
- Ada style: hbnf README.md:464 still says "no \`out\`/\`in out\` parameters" (rejected as a ban 2026-10-04 \[silentpc:fa150405:343#1\])
- Credits: README.md has no Credits section; the later move of obconf material \[silentpc-opusplan:4a4c3021:67405#1\] put it in obconf.md
- HISTORY.md article: HISTORY.md header says "1 October 2026" and the names line is by year ("name(year) · ..." as decided)
- Book toolchain: the image definition does not name hbnf or buildabook explicitly
- obconf wording in the docs: README.md:54 and README.md:12 still say "the daemons it was written for" / "the daemons' own sys/queue.h" (literal use of the word, not the format's description)
- LLM token measurement and constrained decoding: TODO.md:24 says bench/tokens.sh is broken (empties tokens.md) and the token figures are the 10-27 ones
- Bit, octet and string layering: WIRE.md:340-352 describes the Units design (b, B, c, W suffixes, \`byte 9\`, \`word 36\`) as a design; not checked whether it is built, so 9- and 18-bit machines are stated, not shown
- Emit syntax and actions: WIRE.md:251 says %emit with a declared value runs during the read "in the C backend only"
- Other projects: TODO.md section 4 "RFCPLAN step 20 (ALGOL 68, C++, COBOL on the list; IMP72 cancelled)" while the 2026-10-18 \[644:0#1\] decision planned an imp72 port (separate project, pdp64)
- Grammar dialects: corpus/c/README.md:16 says "C11, C17 and C23 are not in it: no yacc grammar of theirs exists to measure", RFCPLAN.md:2940 lists "C17 and C23 grammars" as unbuilt (the 2026-10-24 "upgrade to c23 parsing" is not built; c11.hbnf is the newest)
- C and C++ grammars and compiler: TODO.md:117 "ALGOL 68, C++ grammars: not started"; the C preprocessor grammar is not built (RFCPLAN.md:2940)
- Fork autodetect: ABNF.md:112 says "Off by default" and "listed on stderr" (the decision says stdout and no annotation; annotation is not needed, so only the default and the stream differ)
- COBOL grammar: corpus/cobol/README.md:8 "vendor extensions are left out", the chain's challenge about vendor forms is not settled in the code

# Decision briefing: open notation questions

- Each item gives where things stand, the referents you named or liked, options with rationale and precedents, and a recommendation that is the briefing agent's, not a decision
- Precedents are marked verified (checked in the clone or on disk) or unverified (general knowledge); `(your referent [id])` marks one you named yourself

## Briefing E: hbnf, items Q18 to Q21

Project: hbnf (HyperBNF, the author's grammar notation and parser/code generator in Ada), clone status-check/hbnf at HEAD 1133cf1. Per the change to the standard prompt, options are fitted to hbnf's own stated principles, not the pdp64 priority list. The principles used, with where they are stated:
- P-RFC: "a grammar reads like the notation RFCs have used for decades, not like a yacc file with embedded C actions" (README.md:25-27); the start is ABNF, "the notation people already read fluently" (README.md:46-50).
- P-LOAD: "what lessens a person's mental load lessens a model's token usage"; "a grammar short enough for a person to hold in mind" (README.md:29-33; WHY.md:157 "Fewer words to read, for a person or a model").
- P-DEP: libhbnf "depends on nothing outside the GNAT runtime" (README.md:19-20); "change it to fit your own needs means editing a few lines, not learning a generator" (README.md:38-40).
- P-GATE: no syntax is implemented before it has been shown and approved (CONTEXTS.md:3); round-trip and byte-identity gates are mandatory (RFCPLAN.md:563); a grammar whose output does not re-parse is refused, never emitted as something close (RFCPLAN.md:1466-1469 region).
- P-OCCAM: the author's rule on namespaces: "if you understand now and don't need to implement namespaces, then leave that alone. don't do that if we can at all avoid it" [silentpc:c14a13ff:j10318].
- P-HIST: he prefers "a cleaner syntax especially if there is historical precedent" [silentpc-opusplan:4a4c3021:j17540]; the WIRE.md notation table cites a precedent for every character (WIRE.md:106-120).
- STYLE.md is only a pointer to an external Ada guide (STYLE.md:1-7); it has nothing on these four items. WHY.md is about token counts and bench results, not these four items. HISTORY.md is the BNF essay; nothing on these items found (searched for namespace, slice, header, C99).
- Verification notes: the repository's own tests were not run; counts below are from grep. The decision-log file is docs/decision-log/hbnf-status.md.

---

### Q18 Namespaces and qualified names (REVIEW)
- What it is: a namespace (a named scope that lets two things with the same name coexist, written `ns.name`) was rejected by the author on 2026-10-01, yet islands (embedded sub-grammars such as SQL inside COBOL) are built with `include "f" as x`, referred to as `x.rule`, plus `^.rule` to reach out to the including grammar and `^.^.rule` two levels up.
- What it is: CONTEXTS.md:7 itself says "the dot is scope and never part of a name, strict lookup (a missing name is missing)", so the built feature is a qualified name (a name with a path prefix) with lexical scope (the name means what the nearest enclosing definition says), which is what the rejected feature would have been.
- Why it matters: the generator must map `x.rule` to a C/Rust/Zig/Ada identifier in four backends without clashes, and the manual must not tell the reader there are no namespaces while showing the dot; the author's rule is to avoid new machinery, so the question is whether this is new machinery or the old machinery under another name.
- Where things stand: hbnf-status.md:919-924 "Namespaces: REJECTED ... no per-file namespaces in the repository, but qualified island names exist"; "Doc differs: CONTEXTS.md:7 ... (qualified names, close to what was rejected, from a later user decision not in this chain)". Built in aff3de9 (2026-11-02), `^.rule` built 2026-11-03 (tests/upscope.sh), four backends, tree-sitter refuses a scope that skips white space differently (CONTEXTS.md:7). "namespace" does not occur in RFCPLAN.md or CONTEXTS.md (hbnf-status.md:923). Author's words: [silentpc:c14a13ff:j10318#1] (rejection); the island decision itself is "from a later user decision not in this chain" (no source id). Related: 2026-09-22 "stdlib is a namespace collision just call it commonconf.hbnf" [hist-silentpc:fd13bc5f:h377#1], i.e. he solved a name clash by renaming, not by scoping.
- Referents you named or liked:
  - namespaces, from no named system: "if you understand now and don'tneed to implement namespaces, then leave that alone. don't do that if we can at all avoid it" [silentpc:c14a13ff:j10318]; stance: rejected
  - qualified reference, from no named system: "qualified reference that comes last might be ok" [silentpc-opusplan:4a4c3021:84827]; stance: considered
  - embedded languages (JCL, SQL, CICS), from COBOL: "since cobol allows to embed jcl sql cics and other languages inside it ... we should have some clear, smooth, simple syntax to indicate when we are switching syntax" [silentpc-opusplan:4a4c3021:83530]; stance: considered
  - stock BNF, as the base: modify it as little as possible, extend the semantics a tiny bit [silentpc-opusplan:4a4c3021:83530]; stance: chosen
  - include of common rules, source system not named (he asked whether yacc has an include statement): "a boilerplate library of rules/definitions/jets we can include" [hist-silentpc:fd13bc5f:h253]; stance: chosen
  - name clash solved by renaming: "stdlib is a namespace collision just call it commonconf.hbnf or commconf.hbnf" [hist-silentpc:fd13bc5f:h377]; stance: chosen
  - missing names are missing (strict lookup), from no named system: "missing names are missing; why would you look for them in previous live rulesets?" [silentpc-opusplan:4a4c3021:85182]; stance: chosen
  - yacc: "yacc isn't hbnf" [silentpc-opusplan:4a4c3021:84827]; stance: rejected
- Option 1 - CURRENT: keep qualified names for islands only, and say so: the manual states that the dot exists only after an `include ... as x` and nowhere else; no per-file namespaces, no nesting rules beyond `^`.
  - Rationale: matches what is built and tested; honours the rejection for the general case (a file's own rules stay in one flat space); smallest change (one sentence in README and CONTEXTS).
  - Precedent: C struct member access `a.b` and Ada's `Pkg.Name` are lexical prefixes not requiring a namespace feature in the language of the file itself; closest in spirit is yacc's `$$`/`$1` (positional, no names). (unverified: general knowledge)
  - Cost and risk: one wording change; the risk is that "islands only" is a rule the author must police later when someone wants `include "common.hbnf"` with a clash (WIRE.md:57 already does `include "common.hbnf"` unqualified, so two include forms already exist).
  - Fit: P-OCCAM and P-GATE satisfied; slight tension with P-LOAD (two include forms to learn).
- Option 2 - Reword to avoid "scope" and "qualified": describe `x.rule` as "a rule of the island x" and `^.rule` as "a rule of the including grammar"; never use the words scope, qualified, namespace.
  - Rationale: the contradiction is partly in vocabulary; the thing is a pointer to a sub-grammar, which a reader can hold without a theory of scoping.
  - Precedent: the repository itself uses "island" and "include ... as" (CONTEXTS.md:7); ABNF (RFC 5234) has no scoping at all and RFC 7405 only adds string case flags. (unverified: general knowledge for RFC content)
  - Cost and risk: no code; cosmetic, and `%scope` is also an existing keyword with another meaning (RFCPLAN.md:251, 282: bindings made inside vanish at `}`), so the word "scope" is already overloaded and rewording helps that clash too; risk is that it hides the identity of the feature (it IS a namespace).
  - Fit: P-LOAD good (one fewer concept word); P-OCCAM fine; slightly evasive.
- Option 3 - Make namespaces a real feature: every file is a namespace, `include "f"` makes `f.rule`, rules in the same file see each other unqualified, with `export` or similar.
  - Rationale: removes the "islands only" special case and the unqualified `include "common.hbnf"` second form; clash-free libraries (the `commonconf` problem of 2026-09-22 would not have arisen).
  - Precedent: Ada child packages and C++ namespaces; Erlang/Rust modules (see Option 6). (unverified: general knowledge)
  - Cost and risk: design, parser, four backends and tree-sitter emitter changes, name mangling, tests; reverses a stated author rejection ("don't do that if we can at all avoid it"); P-GATE says it must be shown and approved first.
  - Fit: violates P-OCCAM; only worth it if grammars libraries (`common.hbnf`, `bip39/english.hbnf`) are expected to multiply.
  - Note: you said "don't do that if we can at all avoid it": [silentpc:c14a13ff:j10318]
- Option 4 - Drop qualified names and use prefixes: the island's rules get a mechanical prefix (`sql-select`), the dot is removed; `include "f" as sql` means "every rule of f is renamed sql-NAME".
  - Rationale: hbnf names already carry hyphens (`bip39-word`, `scope-end`, `phrases`), so a prefix is the existing idiom; it needs no scope concept and no strict-lookup rule beyond ordinary missing-name errors.
  - Precedent: C libraries prefix by convention (`sqlite3_`, `SHA256_`); the repository's own `Pfx` variable in hbnf_c.adb (e.g. `struct " & Pfx & CN`) already prefixes generated names (verified: hbnf_c.adb:2919-2925); lemon and sqlite use `sqlite3` prefixing. (unverified: lemon behaviour, general knowledge)
  - Cost and risk: `^.rule` (the way out) has no prefix equivalent and would have to go or become `up-rule`; built tests (tests/upscope.sh) rewritten; a user can now write an island rule that collides by accident with an including rule (strict lookup was a safety).
  - Fit: P-OCCAM best; P-RFC fair (RFCs use hyphenated names such as `IPv6address`); loses a built feature.
- Option 5 - Include-with-prefix directive, explicitly named: `include "f" prefix "x-"` is a textual rename at include time and the dot disappears, but keeps strict lookup because the including file may refer only to the prefixed names.
  - Rationale: same effect as Option 4 but the rename is a visible directive in the grammar, searchable and documented in one place, and the generated names stay plain identifiers (no dots in C, Rust, Zig, Ada).
  - Precedent: Python `from m import *` is the opposite; the closer ones are C's `#include` inside a `namespace`-like wrapper and Ada's `use`-free `with`; Erlang's `-import`. (unverified: general knowledge)
  - Cost and risk: still a new directive (counts against P-OCCAM exactly as much as a namespace would, in a smaller size); `^` is not served; tests change.
  - Fit: P-LOAD fair; P-GATE requires approval; essentially Option 4 plus syntax.
- Option 6 - A module system like Ada's packages or Rust's modules: named units with explicit interface (`export`) and `with`/`use` style imports, plus `use` to open a module so names go unqualified.
  - Rationale: the most complete answer; it is what a language community expects from a tool that targets Ada and Rust (hbnf_ada.adb, hbnf_rust.adb exist).
  - Precedent: Ada 95 child packages (Pkg.Child.Name, `with`/`use`); Rust `mod`/`use`; Erlang's `module:function`. (unverified: general knowledge; Ada rules are well known but not checked against a reference manual on this machine)
  - Cost and risk: largest design and docs cost; mismatches hbnf's one-file-one-grammar shape; pulls in visibility and cyclic-import problems; the exact opposite of the author's rule.
  - Fit: P-OCCAM strongly against; mention only because he asked for the spectrum.
  - Note: you said "don't do that if we can at all avoid it": [silentpc:c14a13ff:j10318]
- Recommendation: MINE (P): Option 1 plus Option 2's wording: keep the built islands, state in one place that the dot exists only after `include ... as`, and replace "scope" by "island" in CONTEXTS.md:7 so it does not collide with `%scope` (RFCPLAN.md:251). It honours the rejection (no general namespace), costs one sentence, and keeps four-backend tests green. What would change my mind: if grammar libraries multiply (a second `common`-style file needing the same names), Option 5 becomes cheaper than clashes; if he dislikes `^.` he should look at Option 4.
- Would help you decide: `grep -rn 'include ".*" as' grammars tests corpus` to count island uses versus plain `include` uses; `grep -rn '\^\.' ... ` for the count of `^.` uses; whether any grammar has a rule-name clash today.

---

### Q19 Slice syntax (REVIEW)
- What it is: the notation for "which bits or units of a field": the built form is `name@K:N` (a place K, then a width N: `version@0:4` is 4 bits starting at bit 0, bit 0 being the most significant bit of the record's first octet), and `name:N` for a width only (`ttl:8`).
- What it is: the author's 2026-10-18 decision says ":bits@offset" (width first, then place); the same day's approved proposal says "name:src@Off:Len" (a source, then place, then length), so his own words contain two orders.
- Why it matters: this is the notation of every bit-level grammar (IPv4, BIP-39), the one a reader of a packet diagram sees first, and what the model must produce; changing it later rewrites grammars, tests, WIRE.md and RFCPLAN.md.
- Where things stand: hbnf-status.md:718-727 "IN THE AIR ... the built spelling is `name:N` and `name@K:N` ... the ':bits@offset' order ... is not as the record says". Author's words: "Use the ':bits@offset syntax we discussed' to say what bits a text field's words stand for" [silentpc-opusplan:4a4c3021:19158#1]; "@Off:Len syntax shoudl work on strings too" [silentpc-opusplan:4a4c3021:j14778]; "we do need to distinguish bits from bytes from codepoints, and some platforms had different word sizes" [silentpc-opusplan:4a4c3021:j14841]; approved proposal "name:src@Off:Len, unit is src's layer, 'b' suffix gives bits" [silentpc-opusplan:4a4c3021:j19192#1]. In the repository: WIRE.md:15 `ipv4 = version@0:4 ihl:4 tos:8 total_length:16`; WIRE.md:106-111 the table of precedents (`:` is C's bit-field and Erlang's bit syntax; `@` is Ada's `F at 0 range 3 .. 7`, BLISS and IMP72 `A<p,s>`); WIRE.md:130 `name@K:N`; WIRE.md:341-351 `@Off:Len` also on strings and units, `name@4B:4B`, `name@4:4`; RFCPLAN.md:1514 "`foo:4` is 4 units and `foo@1:4` is 4 units at offset 1"; RFCPLAN.md:1331 region says the built spelling. The notation "was weighed against COBOL's `foo(2:4)`, BLISS's `foo<p,s>`, Ada's `foo(2..5)` and Python's `foo[1:5]`; `@offset:length` is the nearest to COBOL's" (RFCPLAN.md:1514-1520, read at 1514-1520). Open item: "string slices with a unit suffix" and the stream directive `byte 9`, `word 18` (RFCPLAN.md:1537 per hbnf-status.md:726).
- Referents you named or liked:
  - colon for widths, from Erlang bit syntax and the C bit-field: "Keep colon, expressions in, go with A" [silentpc-opusplan:4a4c3021:13175]; stance: chosen
  - bit 0 is the most significant bit and direction, from RFC packet diagrams: "right or left follows the RFC" [silentpc-opusplan:4a4c3021:15185]; stance: chosen
  - 0-based index, from C and IMP72: "our index are 0 based because C and IMP72 agree" [silentpc-opusplan:4a4c3021:15185]; stance: chosen
  - IMP72 bit fields: "i didn't know about imp72 at the time" [silentpc-opusplan:4a4c3021:j13158]; stance: considered
  - @Off:Len, source system not named: "@Off:Len syntax shoudl work on strings too." [silentpc-opusplan:4a4c3021:j14778]; stance: chosen
  - bits versus bytes versus codepoints, source system not named: "we do need to distinguish bits from bytes from codepoints, and some platforms had different word sizes" [silentpc-opusplan:4a4c3021:j14841]; stance: chosen
  - the :bits@offset order, source system not named: "are you forgetting that :bits@offset syntax we discussed?" [silentpc-opusplan:4a4c3021:19158]; stance: chosen
  - name:src@Off:Len with a b suffix for bits (the BIP-39 and bech32 use case), approved the same day [silentpc-opusplan:4a4c3021:j19192]; stance: chosen
- Option 1 - CURRENT in code and docs: keep `@K:N` (place, then width), width-only `:N`, `B` unit suffix; record in the decision log that ":bits@offset" meant the same notation.
  - Rationale: it is built, tested in four backends, documented with a precedent per character in WIRE.md:106-120; the one slice syntax serves bits, octets and chars (WIRE.md:341-351); reads as "field at K width N", and `@` also numbers enum literals ("at this value", WIRE.md:120).
  - Precedent: COBOL reference modification `foo(2:4)` is start:length (verified: stated in RFCPLAN.md:1514-1520 as the nearest precedent; COBOL itself unverified); Ada representation clause `F at 0 range 3 .. 7` (verified as the author's stated precedent, WIRE.md:111).
  - Cost and risk: zero code; the decision record then contradicts the code and must be corrected; width-last order is opposite to how the author spoke it.
  - Fit: P-RFC and P-HIST good; P-OCCAM best (nothing changes).
  - Note: you said ":bits@offset" (width first): [silentpc-opusplan:4a4c3021:19158]; this option keeps place first
- Option 2 - Change the notation in code and docs to `:bits@offset` (`version:4@0`): width first, then place.
  - Rationale: follows the author's literal words; the common case (width only) is a prefix of the full form, so `ttl:8` upgrades to `ttl:8@16` by appending, which is a cleaner grammar (the place is an optional suffix).
  - Precedent: Erlang bit syntax `<<Ttl:8>>` puts the width after a colon; C bit-field `unsigned ttl : 8`. A place after the width has no direct precedent I can name. (verified: both are quoted in WIRE.md:108; the combined order is unverified) (your referent [silentpc-opusplan:4a4c3021:13175])
  - Cost and risk: every grammar using `@K:N` (grep below), WIRE.md, RFCPLAN.md, the tests, and the parser in hbnf_wire.adb change; breaks the "bit 0" examples; `@` after `:` conflicts with the enum literal form `"x"@N` only visually.
  - Fit: P-HIST fair; P-OCCAM against (churn for a spelling).
- Option 3 - Accept both orders: `name@K:N` and `name:N@K` mean the same.
  - Rationale: ends the record-versus-code disagreement without rewriting anything; each order reads naturally to a different reader.
  - Precedent: PEG and ABNF dialects often accept alternate spellings (ABNF `%x41` vs `%d65` in RFC 5234); two forms of one idea is also what C allows for `a[i]` and `i[a]`. (unverified: general knowledge; ABNF forms are RFC 5234 content)
  - Cost and risk: two spellings for the writer to emit (the grammar writer of `write (tree)` must pick one, RFCPLAN.md:1466 region says canonical first), bigger parser, docs and model prompts doubled; P-LOAD is violated by every doubled form.
  - Fit: P-GATE requires a canonical output, so this needs a canonical spelling too: effectively Option 1 or 2 plus a tolerance.
- Option 4 - A range notation `name[K..K+N]` or `name(2..5)`: Ada slices and Python's `foo[1:5]` (the author weighed Ada's `foo(2..5)` and Python's, RFCPLAN.md:1514-1520).
  - Rationale: readers of Ada, Python, Rust (`a[2..5]`) already read it; the end is explicit, so no "is N a width or an end" doubt.
  - Precedent: Ada `A(2..5)`, Python `a[1:5]` (end exclusive), Rust `a[2..5]` (end exclusive), COBOL `foo(2:4)` (start:length). End inclusive or exclusive differs between them: a hazard. (unverified: general knowledge; the weighing of these is verified as an author consideration, RFCPLAN.md:1514-1520)
  - Cost and risk: brackets and parentheses are used for lists, groups, optional items in ABNF/EBNF (RFC 5234 uses `[ ]` for optional); `(2..5)` collides with the group; width-only `ttl:8` still needed; inclusive/exclusive is a standing error source.
  - Fit: P-RFC against (RFC grammars use `[]` for options); P-LOAD against.
  - Note: you said "Keep colon, expressions in": [silentpc-opusplan:4a4c3021:13175]; this option drops the colon form for brackets
- Option 5 - P4-style or Erlang bit-syntax declaration: a header with fields and widths, `bit<4> version;` (P4) or `<<Version:4, Ihl:4, Tos:8>>` (Erlang), place implied by order, with explicit places only for the rare check.
  - Rationale: the order of fields already fixes the place (hbnf proves `@` only as a check, WIRE.md:130: "It writes nothing new; it checks the author's arithmetic against the RFC"), so most grammars need no `@` at all.
  - Precedent: P4 `header ipv4_t { bit<4> version; bit<4> ihl; ... }` and Erlang `<<A:4, B:4>>` are both well known; neither was checked on this machine. (unverified: general knowledge) (your referent [silentpc-opusplan:4a4c3021:13175])
  - Cost and risk: `bit<4>` clashes with hbnf's angle-free rule notation and its parameterised rules; Erlang's `<<...>>` has the width on each variable, which is already `name:N`, i.e. nothing new; no solution for the offset-with-gaps case (WIRE.md:350 registers read in any order with gaps and overlaps).
  - Fit: P-RFC against (not RFC notation); P-OCCAM against.
- Option 6 - The RFC packet-picture notation: accept a pasted ASCII diagram (the 32-bit-wide `+-+-+` boxes of RFC 791 and others) as the source of field widths and order.
  - Rationale: the most RFC-natural way a person reads a header; the README's premise is that a grammar reads like the RFCs.
  - Precedent: RFC 791 (IPv4), RFC 793 (TCP) and RFC 8650-era drafts' diagrams; the `art2bytes`-like tools and Kaitai's `.ksy` (YAML with `type: b4`) are the machine-readable cousins. (unverified: general knowledge; none of these tools is on this machine) (your referent [silentpc-opusplan:4a4c3021:15185])
  - Cost and risk: parsing ASCII art is fragile (variable-width fields, labels cut across rows), cannot say a layer other than bits (no `B` suffix, no chars), and cannot carry actions; a very different parser; the diagram is documentation, not the grammar.
  - Fit: P-RFC good, P-LOAD good for humans; P-GATE (round trip) poor; best as a generator output (emit a diagram from the grammar) than an input.
- Recommendation: MINE (P): Option 1 (keep `@K:N`), and correct the decision record by quoting the code: ":bits@offset" becomes "`name:N` for width, `name@K:N` for place and width" with a note of the 2026-10-18 wording, since the WIRE.md table already gives a precedent for each character and the same day's approved proposal uses `@Off:Len`. If he truly prefers width first, Option 2 is a mechanical sed over a known set of files, best done before more grammars exist. What would change my mind: if few grammars use `@` (the check) the churn is cheap and the "optional suffix" argument wins.
- Would help you decide: `grep -rn '@[0-9]*:[0-9]' status-check/hbnf --include=*.hbnf | wc -l` (count of places); `grep -c '@' WIRE.md`; the number of grammars with a width-only field and no place; whether string slices (`name@4B:4B`) have a built form (hbnf-status.md:726 says not decided).

---

### Q20 Library headers (REVIEW)
- What it is: where the helper code for actions and emitters (hash functions such as SHA-256, checksums such as CRC) comes from when a generated program uses it: today the system's libraries are linked, and a single hand-written header `corpus/bip39/bip39.h` wraps OpenSSL's SHA256.
- What it is: the author's 2026-10-17 decision wanted one `.h` file per function ("sha256.h crc.h etc"), instead of one opaque `hbnf_sum.h`; commit 15383d6 made per-function headers, 0cc3bc0 removed them in favour of linking system libraries.
- Why it matters: it decides whether a generated parser can be built with nothing but a C compiler (P-DEP), whether the tests need OpenSSL installed, and how a reader finds the helper they call.
- Where things stand: hbnf-status.md:783-790 "IN THE AIR". Author's words: "instead of hbnf_sum.h which is opaque, each function should get it's own .h file, sha256.h crc.h etc" [silentpc-opusplan:4a4c3021:j16491#1]. Repository: corpus/bip39/bip39.h:1-24 includes `<openssl/sha.h>`, defines one `static unsigned bip39_checksum` using `SHA256`, "the program links -lcrypto" (verified: corpus/bip39/bip39.h); RFCPLAN.md:1282 and :1464 "using SHA256"; no lib/ directory at HEAD; runtime/ holds hbnf_conf.c/.h, hbnf_pow5.h, hbnf_scalar.h, hbnf_tape.h (verified: ls runtime). Also TODO.md:88-97 "The conf glue out of the templates into an included C header" is open (hbnf-status.md:375).
- Referents you named or liked:
  - one header per function, source system not named: "instead of hbnf_sum.h which is opaque, each function should get it's own .h file, sha256.h crc.h etc" [silentpc-opusplan:4a4c3021:j16491]; stance: chosen
  - standard library crc32, from the standard library: "stop renaming shit, crc32 is a standard function in a standard library that our generated parser should be linking in." [silentpc-opusplan:4a4c3021:j16595]; stance: chosen
  - OpenBSD queue.h, from OpenBSD: "bring in sys/queue.h and use hte tailq macros. do it right. use the provided interface" [hist-silentpc:fd13bc5f:h404]; stance: chosen
  - real headers in the preamble, from OpenBSD: "this tailq stuff should live in the jets and preamble and epilogue. possibly re-using the openbsd .h files" [hist-silentpc:fd13bc5f:h351]; stance: chosen
  - one static binary, from musl: "the hbnf binary must be static and shipped that way" [silentpc:6ec412b3:j27839]; stance: chosen
  - std library functions over hand-built code: "table-driven scanner first if possible use dfa or std library functions" [silentpc-opusplan:4a4c3021:6714]; stance: chosen
- Option 1 - CURRENT: keep linking the system libraries (libcrypto for SHA-256, libc elsewhere) and one hand-written header per use such as bip39.h.
  - Rationale: no hand-copied crypto (a copy of SHA-256 written here would be code the author must trust and test); smallest code; what is built.
  - Precedent: OpenBSD's own tools link `libcrypto`/libc rather than copying (unverified: general knowledge); the BIP-39 reference implementations call a hash library (unverified).
  - Cost and risk: the build needs OpenSSL headers and `-lcrypto`; the generated code is not self-contained; the decision record is contradicted; an interface change in OpenSSL (the 3.0 deprecation of `SHA256()` one-shot is widely reported, unverified) can turn into warnings under `-Werror` (tests use `-Wall -Werror`, e.g. tests/backref.sh:22).
  - Fit: P-DEP is weakened for generated code (libhbnf itself is clean); P-OCCAM good.
  - Note: you said "each function should get it's own .h file": [silentpc-opusplan:4a4c3021:j16491]
- Option 2 - Restore per-function headers (the author's 2026-10-17 words): `sha256.h`, `crc.h`, `bech32.h`, each one function, in `runtime/` or `lib/`.
  - Rationale: the author's own, explicit decision; each header is small, named for what it does, readable, copyable on its own ("not opaque").
  - Precedent: Plan 9's convention of a header per library and `#include <u.h>` / `<libc.h>`; OpenBSD `sha2.h`, `crc.h`-style per-algorithm headers. (unverified: general knowledge; the commit 15383d6 is the repository's own earlier evidence, verified only through hbnf-status.md:787)
  - Cost and risk: the code for SHA-256 has to be written or vendored with a licence (ISC is the repository's, corpus/bip39/bip39.h:8) and tested against NIST vectors; many tiny files; reversal of 0cc3bc0 (the removal was presumably done for a reason the records do not state).
  - Fit: matches P-LOAD (short, named, readable); P-DEP best (self-contained output).
- Option 3 - One header per library: `hbnf_hash.h` (sha256, crc), `hbnf_bits.h`: grouped by domain, not by function.
  - Rationale: a middle path: fewer files than per-function, not one opaque blob; each header is documented with a table of what it holds.
  - Precedent: C's `<string.h>` and `<stdint.h>` group related functions; the repository's own `hbnf_scalar.h`, `hbnf_tape.h` are of this size (verified: runtime/ listing); the author called `hbnf_sum.h` "opaque", so the grouping must be named well.
  - Cost and risk: it is exactly the shape the author rejected on 2026-10-17 unless it is named by contents; moderate.
  - Fit: P-OCCAM good; P-LOAD fair; partial conflict with the author's own words.
  - Note: you called a grouped header "opaque": [silentpc-opusplan:4a4c3021:j16491]
- Option 4 - Header-only inline library: all helpers `static inline` in headers, no `.c` to link, no `-l` flag.
  - Rationale: generated parsers stay one compile command; no link order; inlining helps the hot loop of a hash over a field.
  - Precedent: the repository's own `static unsigned bip39_checksum` in bip39.h is already header-only (verified: corpus/bip39/bip39.h); stb-style single-header libraries (unverified: general knowledge).
  - Cost and risk: every translation unit gets its own copy (code bloat with `static`), `-Wunused-function` noise (the tests pass `-Wno-unused-function` in several places, verified: tests/backref.sh:22, tests/forks.sh:21); compatible with C99 `inline` rules only if done carefully (C99 `inline` semantics differ from GNU89; the repository's output already uses `static`).
  - Fit: P-DEP good; combines with Option 2 or 3 as the packaging.
- Option 5 - A generated amalgamated header, like SQLite: the generator emits one self-contained file containing only the helpers the grammar uses, in its output.
  - Rationale: the generator already knows which helpers are used; the output has no external headers at all; SQLite's amalgamation is the proof the style is livable and is already in the author's corpus (tests/sqlite.sh:2 parses it; verified: corpora/sqlite-amalgamation-3460100/sqlite3.c exists).
  - Precedent: SQLite's `sqlite3.c`/`sqlite3.h` amalgamation (verified: file present; the amalgamation's build process is general knowledge); bison and flex already emit the whole runtime into the generated file (bison's yacc.c skeleton is a template for that, verified: /usr/share/bison/skeletons/yacc.c exists).
  - Cost and risk: generator code to include helpers conditionally (the Mustache templates exist for this, README.md:19-20); the helper source must still live somewhere in the repository; harder to read for a person ("not opaque" was the author's objection).
  - Fit: P-DEP best; P-LOAD weak for the output file; P-OCCAM fair.
  - Note: you called a single bundled header "opaque": [silentpc-opusplan:4a4c3021:j16491]
- Option 6 - An include-what-you-use convention: each action file lists the headers it needs with plain `#include`, the library author documents "this header needs -lcrypto" at the top (as bip39.h does), and the generator never inserts includes.
  - Rationale: no policy at all in the generator; what is used is visible at the top of the file that uses it; the same as how C programs have always been written.
  - Precedent: the IWYU tool and Google's C++ style rule of it; the C standard library's own per-header model. (unverified: general knowledge)
  - Cost and risk: nothing built, only a rule in the manual; a convention is a soft rule that drifts; does not choose between Options 1 to 5.
  - Fit: P-OCCAM best; it is a rule and not a design, so it should accompany another option.
- Recommendation: MINE (P): Option 1 now (state it in the docs and amend the decision log to 'superseded by the later link-the-library decision'), with Option 4's header-only shape for anything that is not cryptography (CRC, bech32 checksum, bit helpers: a dozen lines each, no external dependency, in per-function headers as the author wanted), and keep SHA-256 from the system. That keeps the author's wish ("sha256.h crc.h", readable names) where it is cheap and avoids owning crypto code. What would change my mind: if tests must run on a machine with no OpenSSL headers, Option 2 or 5 for SHA-256 as well.
- Would help you decide: `ls lib 2>&1` and `git -C status-check/hbnf show 0cc3bc0 --stat` plus its message (the reason for the removal); `git show 15383d6 --stat`; whether any test fails when `-lcrypto` is absent; the list of helper functions the grammars call (`grep -rn '#include' tests/wire corpus --include=*.hbnf`).

---

### Q21 The C standard (REVIEW)
- What it is: which edition of C the generated parser must be written in (C99 is 1999's ISO standard; C11 adds `_Thread_local` and `_Static_assert`; `gnu11` is C11 plus GCC's extensions) and which edition the tests compile with.
- What it is: the docs and the decision say "pinned at C99 (for OpenBSD kernel compatibility)", but 64 test scripts compile with `-std=gnu11` and the generator emits `static _Thread_local` (C11) for forks and switch events.
- Why it matters: a pinned standard is a promise that the output compiles on an old or small compiler (OpenBSD base's compiler, tcc, a kernel build with `-std=gnu99`); the tests are what decides whether the promise is ever checked; the generator's use of GNU `__attribute__` and `__builtin_expect` means "C99" is already "GNU C99".
- Where things stand: hbnf-status.md:1736-1747 "DONE ... the C backend is stated as C99 and C++-clean", "Doc differs: tests/backref.sh and tests/ladder.sh compile generated C with -std=gnu11". Author's words: "we pin C at C99 (for OpenBSD kernel compatibility) and for C++ we want to support any reasonable version (obviously we don't care about cfront)" [silentpc:c14a13ff:j4748#1]; for the grammars (not the output): "c11 is a different dialect", C11/C17/C23 "wanted for himself, useless for the yacc bakeoff" [silentpc-opusplan:4a4c3021:60176, j60523]; README.md:20 plans "C17 and C23 for the C family" (grammars). Repository facts (verified by grep in status-check/hbnf): RFCPLAN.md:2123 "The C backend stays C99 and C++-clean"; hbnf_c.adb:807-808 `static _Thread_local hbnf_ev_t *hbnf_ev;` and `static _Thread_local size_t hbnf_cev;` (emitted when a grammar uses a switch), hbnf_c.adb:10424 `static _Thread_local size_t hbnf_fork_start, hbnf_fork_used;` (emitted when forks are used); `__attribute__((unused))` at hbnf_c.adb:267, 2919-2928, 4912; `__builtin_expect` at 4819; `grep -l "std=gnu11" tests/*.sh | wc -l` gives 64; only tests/c99.sh, tests/gnu99.sh and tests/sqlite.sh mention `-std=c99` or `gnu99`, and those run gcc as a reference on the C grammar's input, not on the generated output (tests/c99.sh:4,30); tests also pass `-D_GNU_SOURCE`.
- Referents you named or liked:
  - C99 pin, from OpenBSD: "we pin C at C99 (for OpenBSD kernel compatibility) and for C++ we want to support any reasonable version (obviously we don't care about cfront)" [silentpc:c14a13ff:j4748]; stance: chosen
  - C++ through an extern "C" header guard: "if C++ support becomes more than a simple extern \"C\" header guard, we can make a separate C++ backend" [silentpc:c14a13ff:4769]; stance: chosen
  - pcc as c99 plus gnu extensions: "modern pcc is c99 so that should be the comparable" [silentpc-opusplan:4a4c3021:j60523] and "pcc is c99 plus gnu extensions" [silentpc-opusplan:4a4c3021:60776]; stance: chosen
  - gcc bison grammar, c99 era with its gnu extensions [silentpc-opusplan:4a4c3021:60776]; stance: chosen
  - c11, c17 and c23 (grammars): "i want c11 c17 and c23 for my own personal satisfaction and use, but they are useless for the yacc bakeoff" [silentpc-opusplan:4a4c3021:j60523]; stance: rejected for the bakeoff, wanted otherwise
  - c11 is a different dialect: "c11 is a different dialect" [silentpc-opusplan:4a4c3021:60176]; stance: considered
  - language header, from no named system: "this stage we just go with C; but we can include as first non-comment in the file, a language C|Rust|Zig|Ada" [hist-silentpc:fd13bc5f:h213]; stance: chosen (C), considered (Rust, Zig, Ada)
- Option 1 - Say C11 in the docs: change README/RFCPLAN to "C11 with GNU extensions (gnu11)", matching the tests and the generator.
  - Rationale: the shortest path to truth: docs follow what exists and what is tested; every supported compiler today (GCC, Clang, OpenBSD's clang) defaults to gnu17 or newer.
  - Precedent: GCC's default dialect is `gnu17` since GCC 8 (unverified: general knowledge) and clang's is `gnu17` (unverified); the decision log's own "pcc is c99 plus gnu extensions" (hbnf-status.md:2076) shows he thinks of C99 as the old-compiler floor. (your referent [silentpc-opusplan:4a4c3021:j60523])
  - Cost and risk: abandons the "OpenBSD kernel compatibility" reason the author gave; if the kernel is compiled with `-std=gnu99` then forks and switches fail to compile there.
  - Fit: P-OCCAM best (no work); contradicts the author's stated pin, so it needs his explicit change.
  - Note: you said "we pin C at C99": [silentpc:c14a13ff:j4748]
- Option 2 - Make the generator C99 and test with `-std=c99` (or gnu99): replace `_Thread_local` by a `__thread` fallback macro or a context pointer, flip the tests to `-std=gnu99`/`-std=c99 -pedantic`.
  - Rationale: makes the pin true and checked; a promise that is tested stays a promise; the one real C11 feature is a handful of lines.
  - Precedent: SQLite builds without any C11 feature and states portability as a goal (unverified: only the file's presence is verified, corpora/sqlite-amalgamation-3460100/sqlite3.c; its macros such as `SQLITE_HAVE_C99_MATH_FUNCS` at line 239 are verified); GNU bison's own skeleton chooses C99 integer types only `#if defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__` (verified: /usr/share/bison/skeletons/c.m4:230) and carries pre-C99 fallbacks; this is the style of a tool that must run in old environments.
  - Cost and risk: need an alternative to thread-local state: either a per-parser struct field (clean, and the right design for re-entrancy and for out-of-order or threaded use, since `parser_t *p` is already passed) or `__thread` (a GNU extension, not C99 either); `__attribute__` and `__builtin_expect` must be hidden behind macros to be C99-pedantic; 64 test lines change; `-pedantic-errors` would then expose more.
  - Fit: P-DEP good; honours the author's pin; moderate effort.
- Option 3 - C17 (or C23) for the grammars and C99 for the output: accept two meanings of "C standard": the C family of grammars grows to C17 and C23 (README.md:20), the generator's own output stays C99.
  - Rationale: the two questions are different (what language the grammar parses, what language the generated code is written in) and the repository already uses the word for both; stating the two separately removes the confusion; C23 is also the first standard with `#embed`, `bool` and `typeof` as keywords, which the grammar must parse. (unverified: general knowledge)
  - Precedent: Bison's documentation distinguishes the generated parser's C dialect from the grammar language (unverified: general knowledge); the author's own split "c11 is a different dialect" (hbnf-status.md:2078). (your referent [silentpc-opusplan:4a4c3021:j60523])
  - Cost and risk: needs Option 2 (or 1) as well for the output side; new grammars c17/c23 (not started: hbnf-status.md:2483, RFCPLAN.md:2940) and a yacc/gcc reference for each; the word "C standard" must always carry its subject.
  - Fit: P-LOAD good (a precise sentence); an add-on, not a full answer.
- Option 4 - A switch that selects the standard: `--std=c99|c11|gnu11` (or a `language` header value, the existing "Language header" idea `C|Rust|Zig|Ada` of 2026-09-21 [hist-silentpc:fd13bc5f:h213#1], e.g. `language C99`) and the generator picks `_Thread_local`, `__thread` or a struct field accordingly.
  - Rationale: lets a kernel user have C99 and a modern user have C23 features such as `thread_local` keyword, `static_assert`; the author already planned a language header.
  - Precedent: flex and bison have switches for output dialect (bison's `%language "C"`/`"C++"`, verified only as present: /usr/share/bison/skeletons/c++.m4, c.m4, glr.cc); ANTLR's `-Dlanguage=` target option (unverified: general knowledge); lemon has no such switch (unverified). (your referent [hist-silentpc:fd13bc5f:h213])
  - Cost and risk: a feature and a matrix to test (each standard times four backends times every grammar): the opposite of Occam; each option doubles `check.sh` time (which already runs four slices at once, tests/check.sh:16).
  - Fit: P-OCCAM against; P-LOAD against; worth it only if two audiences really exist.
- Option 5 - Drop `_Thread_local` for a portable fallback and keep everything else as is: a macro in the emitted prologue chooses `_Thread_local` when `__STDC_VERSION__ >= 201112L`, else `__thread`, else nothing (single-threaded).
  - Rationale: the minimum change that makes the generated file compile under `-std=c99` for the forks and switch cases without redesigning state; the feature test macro pattern (`__STDC_VERSION__`) is exactly what bison's skeleton does (verified: c.m4:230).
  - Precedent: glibc and many projects use `#if defined __STDC_VERSION__ && __STDC_VERSION__ >= 201112L` for `_Thread_local` and `__thread` for GNU compilers (unverified: general knowledge); the C feature test macros are `__STDC_VERSION__` (199901L, 201112L, 201710L, 202311L) (unverified for the exact values of C23 on this machine: gcc/clang here were not queried).
  - Cost and risk: a few lines in hbnf_c.adb (3 sites: 807, 808, 10424) plus one test with `-std=c99`; if the fallback is "nothing" then two parsers in two threads share state silently: a latent error of exactly the kind hbnf's gates refuse, so the fallback should be "refuse to compile" (`#error`), not silent.
  - Fit: P-GATE good if the failure is loud; P-OCCAM good.
- Option 6 - Put the standard in one place and test it: keep C99 as the claim for the output, add `tests/std99.sh` that compiles every generated parser with `-std=c99 -Wall -Werror` (or `-std=gnu99`) and make the failures the work list, without deciding the solutions in advance.
  - Rationale: first measure what actually breaks, then choose among 2, 5 and 1 with numbers; the prior claim has been unchecked for weeks (the docs say C99, the tests say gnu11).
  - Precedent: the repository's own c99.sh test uses `gcc -std=c99 -pedantic-errors -fsyntax-only` as the reference for grammar acceptance (verified: tests/c99.sh:4,30), so the pattern is already used on the grammar side.
  - Cost and risk: one new test script; may reveal many failures; no behaviour change until decided.
  - Fit: P-GATE best (a claim should have a gate); P-OCCAM good.
- Recommendation: MINE (P): Option 6 first (run the generated C of the standard grammars with `-std=gnu99` and `-std=c99 -pedantic` to see what breaks), then Option 5 for the three `_Thread_local` sites (with `#error` rather than a silent fallback), and say in the docs "output: C99 with the GNU attributes (`__attribute__`, `__builtin_expect`), tested at gnu99 and gnu11; grammars: C79 to C11 built, C17 and C23 planned" (Option 3's sentence). If the measurement shows only the three thread-local sites fail, this is a small job; if it shows `__attribute__` and other things everywhere, declare gnu99 (GNU extensions allowed) rather than strict C99. What would change my mind: if OpenBSD's base compiler is now clang with gnu17 as default and the kernel target is no longer a use, Option 1 (say C11) is honest and cheapest.
- Would help you decide: `cd status-check/hbnf && grep -l 'std=gnu11' tests/*.sh | wc -l` (64) and replace `-std=gnu11` by `-std=gnu99` in a scratch copy of a few tests (backref.sh, forks.sh, ladder.sh) to see which fail; `grep -n '_Thread_local\|__thread' hbnf_c.adb runtime/*.h` (the three sites); `gcc -std=c99 -pedantic-errors -fsyntax-only` over one generated parser; `echo | gcc -dM -E - | grep STDC_VERSION` for the default dialect of the installed gcc and clang.
