# Parser Report

This document summarises the **COBOL grammar** work: the *syntax* side is close to `cobc`, with
`snake_case` names left alone and a [link](https://example.com/a_b "title") kept.

## What changed

- Added the communication section
- Fixed `PIC 99..` with a second token
  - nested item with **bold** text
  - another nested item
    continuing on a second line
- Last item

1. First step
2. Second step
   - a bullet under a number
3. Third step

### Results

| Corpus | Programs | Both ok |
|--------|---------:|:-------:|
| GnuCOBOL | 1,615 | 1,113 |
| NIST | 459 | 218 |

> A quoted note spanning
> two lines.

```c
int main(void) {
    return 0;
}
```

---

Final paragraph with ~~strike~~, an image ![alt](pic.png) and an escaped \* star.
