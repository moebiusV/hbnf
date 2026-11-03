= Parser Report

This document summarises the *COBOL grammar* work: the _syntax_ side is close to `cobc`, with
`snake_case` names left alone and a #link("https://example.com/a_b")[link] kept.

== What changed

- Added the communication section
- Fixed `PIC 99..` with a second token
  - nested item with *bold* text
  - another nested item
    continuing on a second line
- Last item

1. First step
2. Second step
   - a bullet under a number
3. Third step

=== Results

#table(
  columns: 3,
  align: (left, right, center),
  table.header([Corpus], [Programs], [Both ok]),
  [GnuCOBOL], [1,615], [1,113],
  [NIST], [459], [218],
)

#quote(block: true)[
  A quoted note spanning
  two lines.
]

```c
int main(void) {
    return 0;
}
```

#line(length: 100%)

Final paragraph with #strike[strike], an image #image("pic.png", alt: "alt") and an escaped \* star.
