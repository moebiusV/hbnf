# Markdown, as Claude Code writes it, to Typst

`markdown.hbnf` reads the Markdown that Claude Code emits for documents; `typst.c` walks the tape it writes and prints Typst.
`tests/markdown.sh` checks that each `tests/good/NAME.md` comes out as `NAME.typ`.

    hbnf corpus/markdown/markdown.hbnf --backend=c --layout=tape > md.c
    cat md.c corpus/markdown/typst.c > m.c && cc -O2 -Iruntime -DOUT_T=document_t m.c -o md2typst
    md2typst report.md > report.typ

## Covered

Headings (`#` to `######`), paragraphs, bullet and numbered lists that nest (the content column of an item is read off its line, so
a child sits where its parent's text does), fenced code with an info string, pipe tables with alignment, block quotes, rules, and the
inline marks: `code`, `**bold**`, `*italic*`, `_italic_`, `~~strike~~`, links with titles, images, `<autolinks>`, backslash escapes.
A mark does not open before a space (`2 * 3 * 4` is text), and an underscore inside a word is part of the word (`snake_case`).

## Not covered (each is a limit of the grammar as written, not of the notation)

- Any text is Markdown, so nothing is refused; what the grammar does not know it reads as text.
- The text ends with a line feed; the driver adds one (`eol` is zero-width and makes a rule no longer pure text, so `hidden` refuses it).
- A fence closes at the first line that starts with three backticks, so a fence of four that holds a fence of three is cut short.
  The closing ticks should be the opening ones; that needs the opening ticks to be visible to the rule that reads a line of code
  (an up reference, `CONTEXTS.md` section 25).
- No setext headings, indented code, HTML blocks, reference links, hard line breaks, or `_` emphasis inside a word.
- A `>` line with nothing after it is not kept, so a paragraph break inside a quote is lost.
- Typst: a tight or loose list is not told apart; links keep their address but not their title.

## Size

|  | rules | lines | symbols | characters |
|---|---:|---:|---:|---:|
| `markdown.hbnf` | 44 | 46 | 439 | 2,161 |
| `typst.c`, comments out | 13 functions | 202 | 1,437 | 7,780 |

The walker is three times the grammar.  `CONTEXTS.md` section 25 works the same conversion as rewrite rules in the grammar itself:
about 540 symbols for both, with no walker.
