**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 1.7 ms | 1150 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| aeson | 41 ms | 49 MB/s | 34 MB | agrees with the corpus (75 files); a Value, text and numbers converted |
| Alex and Happy, tuned | 109 ms | 18 MB/s | 48 MB | agrees with the corpus (75 files); a tree, text as slices of the input |
| Alex and Happy, as the tutorials write it | 204 ms | 10 MB/s | 92 MB | agrees with the corpus (75 files); a tree, text as slices of the input |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 5.3 ms | 377 MB/s | 8 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| toml-parser (Alex, Happy), generators in optimising modes | 291 ms | 7 MB/s | 188 MB | agrees with the corpus (31 files); a list of expressions, text as String |
| toml-parser (Alex, Happy), as Debian ships it | 327 ms | 6 MB/s | 188 MB | agrees with the corpus (31 files); a list of expressions, text as String |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 7.0 ms | 282 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| yaml (libyaml) into a Value | 272 ms | 7 MB/s | 75 MB | differs from the corpus on: docs.yaml explicit-key.yaml flow-dedent.yaml; a Value, text converted |
| HsYAML (events) | 6.02 s | 0 MB/s | 17 MB | agrees with the corpus (36 files); the event stream |

_2026-10-28; amd64, glibc (Debian), GHC 9.6.6, Alex 3.4.0.1, Happy 1.20.1.1; `-O2`; hbnf eac77a0.  The Haskell parsers are the syntax alone, as hbnf's are: every one is walked to the end, so nothing is left lazy when the clock stops.  Text is kept as the input holds it where the parser allows (hbnf's tape and the Alex/Happy JSON); the libraries that convert it say so._
