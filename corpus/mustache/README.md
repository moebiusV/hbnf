# Mustache templates in hbnf

`mustache.hbnf` is the syntax of a [Mustache](https://mustache.github.io/mustache.5.html)
template: text, `{{name}}`, `{{{name}}}`, `{{&name}}`, `{{! comment }}`, `{{> partial}}`,
`{{#section}} ... {{/section}}`, `{{^inverted}} ... {{/inverted}}`, `{{=<% %>=}}`, and nothing
of how a template is rendered.  Sixteen rules.

A closing tag has to say the name the opening one did.  That is not context-free, and it is
what the **back-reference** is for: `name %as tag` keeps the text a name matched, and
`%same tag` is that text again, later in the same sequence.  It is local to the rule, so
`{{#a}}{{#a}}x{{/a}}{{/a}}` closes each section with its own tag, and a backtrack
restores it with the position.  The same two words write XML's `<a> ... </a>`, a
here-document's terminator and a raw string's delimiter (`tests/backref.sh`).

The details follow mustache.js: the sigil (`#` `^` `/` `!` `>` `&` `=`) comes right after the
`{{`, so `{{ /a}}` is a variable called `/a`; a variable is anything up to the first `}}`,
with a `}` allowed inside it, but not nothing; `{{{x}}` is a variable called `{x`.

## Checked against chevron

`sh tests/mustache-diff.sh [N [SEED]]` (needs a python with `chevron` installed, `PYTHON=`)
generates random valid templates and mutations of them (a character deleted, inserted,
replaced, swapped, doubled, the text cut) and asks the parser hbnf makes and
`chevron.render` about each (`tests/mustache/oracle.py`).  With 6,000 and 6,000: every
valid template accepted, and the same answer on 5,984 of the 6,000 mutations; the other 16 are
one case, a tag whose text holds a `{{` (`{{>a{{ }}`), which hbnf reads to the first `}}` as
mustache.js does and chevron refuses.  The oracle is chevron plus two rules it lacks: a tag
with nothing in it (`{{#}}`) is an error, and so is a `{{` that is never closed (chevron lets
it end the text, mustache.js says "Unclosed tag").  Finding those, and the generator's own
mistakes (it put blanks before sigils, which mustache.js does not allow), is what the
test is for.

Not done: `{{=<% %>=}}` is read as a tag but does not change the delimiters.

In Tree-sitter (`sh tests/treesitter.sh corpus/mustache/mustache.hbnf corpus/mustache/tests/good
corpus/mustache/tests/bad`) the grammar generates with one declared conflict and parses all 25
good templates, and it is where its limit shows: Tree-sitter cannot make a closing tag repeat
the opening one, so the backend writes the closing name as any name, and the five mismatched
bad cases (`{{#a}}x{{/b}}`) parse.  On 2,000 mutations, hbnf and Tree-sitter agree on
1,894; the other 106 are templates only Tree-sitter accepts, and 103 of them have a closing tag that
names another section (the other three have a name with a stray character in it).

Running it found three faults in hbnf, now fixed: a lookahead inside a rule that is only text
was silently dropped when the rule was compiled to its automaton; a rule used only in a
lookahead was left out of the generated parser; and an alias of an optional token
(`blank_2 = blank`) failed on nothing, where `blank` succeeds on it.
