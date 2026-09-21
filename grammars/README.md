# grammars/

OpenBSD daemons' configuration grammars, translated from their `parse.y`
into ASTBNF (the schema notation `hbnf` parses and binds against).  Each file
is a complete grammar for that daemon's config file — the same shape
`parse.y` describes, minus the yacc machinery.

## The translation

`parse.y` splits a grammar across three layers — the `%token` keyword list,
the productions, and the `{ actions }` that build the tree.  ASTBNF keeps only
the productions; the other two layers are implicit.

| parse.y | ASTBNF |
|---|---|
| `%token` keyword + `lookup()` table | a quoted literal `"server"` |
| `STRING` / `NUMBER` (typed via `%type`) | `str` / `int` |
| `x : y z` | `x = y z` |
| `x : y \| z` | `x = y / z` |
| `x_l : x_l y \| y` (list boilerplate) | `x = 1*( y )` |
| `x : y \| /* empty */` | `x = [ y ]` |
| `'{' optnl x_l '}'` (a block) | `"{" [nl] *( x nl ) [nl] "}"` |
| `{ … }` action (TAILQ/alloc/logic) | dropped — the binder builds the tree |

A keyword alias like unwind's `dot`/`DoT`/`tls` → one token becomes a plain
alternation:

```abnf
dot = "dot" / "DoT" / "tls"
```

## Whitespace, lines, comments

Three things, kept distinct:

- **Horizontal whitespace** (spaces/tabs) is skipped by the lexer and never
  appears in a grammar.
- **`nl`** — a newline, `"\n"`.  It is what distinguishes *lines*, so it is
  explicit in block bodies: `"{" [nl] *( option nl ) [nl] "}"`.
- **Comments** — a comment at end-of-line is *trailing* (attached to the entry
  on that line); a comment on its own line is *leading* (attached to the next
  entry).  `ws` is the entry separator, "newline and/or comment":

```abnf
nl = "\n"
ws = 1*( nl / comment )
```

## The win, concretely

httpd's `serveropts_l` list rule is 22 lines of yacc:

```yacc
serveropts_l : serveropts_l serveroptsl nl
             | serveroptsl optnl ;
serveroptsl  : LISTEN ON STRING opttls port { … }
             | ALIAS optmatch STRING          { … }
             | … (18 more alternatives) …
```

Its ASTBNF equivalent is one line, because the list/`nl`/action scaffolding
collapses into `*( … nl )`:

```abnf
server = "server" ["match"] str "{" [nl] *( serveropt nl ) [nl] "}"
```

## Covered so far

| daemon | file | size (parse.y → hbnf) |
|---|---|---|
| ntpd | `ntpd.hbnf` | 841 → 25 lines |
| unwind | `unwind.hbnf` | 975 → 27 lines |
| dhcpleased | `dhcpleased.hbnf` | 863 → 17 lines |
| httpd | `httpd.hbnf` | 2785 → ~100 lines |

`openbgpd.hbnf`, `relayd.hbnf`, `snmpd.hbnf`, `ldpd.hbnf`, `pfctl.hbnf` are the
next candidates (bgpd is the largest at 122 rules).
