**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 1.8 ms | 1136 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| JSON::Fast (hand-written Raku) | 291 ms | 7 MB/s | 168 MB | differs from the corpus on: bom.json leading-zero.json; a Raku tree, text and numbers converted |
| JSON::Tiny (a Raku grammar) | 4.29 s | 0 MB/s | 463 MB | differs from the corpus on: bom.json form-feed.json nbsp.json vertical-tab.json; a Raku tree, text and numbers converted |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 4.5 ms | 440 MB/s | 7 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| TOML (a Raku grammar) | 4.49 s | 0 MB/s | 193 MB | differs from the corpus on: arrays.toml dates.toml dotted.toml inline.toml numbers.toml bare-cr.toml inline-newline.toml inline-trailing-comma.toml; a Raku Hash tree, text and numbers converted |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | what it builds, and the corpus |
|---|---:|---:|---:|---|
| hbnf (C backend), %emit tape | 7.0 ms | 285 MB/s | 5 MB | checked by tests/emit.sh against the corpus; a tape, text as offsets |
| YAMLish (a Raku grammar) | refused: the module refused the document  | | | differs from the corpus on: anchors.yaml comment.yaml empty.yaml explicit-key.yaml literal.yaml double-yaml.yaml flow-dedent.yaml marker-in-flow.yaml; a Raku tree, text converted |

_2026-11-02; amd64, glibc (Debian), Rakudo v2024.09; hbnf d9f7a84.  The Raku modules are the syntax alone, as hbnf's are: the tree each builds is complete when the clock stops.  A run over 20 s is not repeated.  The grammar-based modules build Raku values and convert text and numbers; hbnf's tape holds offsets._
