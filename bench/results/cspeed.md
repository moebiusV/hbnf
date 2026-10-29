**47 translation units, 5.0 MB of preprocessed C** (Lua 5.4.7, zlib 1.3.1, the SQLite 3.45.1 amalgamation; best of 5 runs):

| tool | time | MB/s | peak memory, the largest unit alone (2.5 MB of C) |
|---|---:|---:|---:|
| hbnf (C backend), the C11 grammar, typed tree | 0.20 s | 25.0 MB/s | 66 MB |
| hbnf (C backend), the same grammar, `--layout=tape` | 0.17 s | 29.2 MB/s | 14 MB |
| `gcc -fsyntax-only` | 0.41 s | 12.3 MB/s | |

_2026-10-29; gcc (Debian 14.2.0-19) 14.2.0;ldd (Debian GLIBC 2.41-12+deb13u4) 2.41; `-O2`; hbnf bad5b34.  `gcc -fsyntax-only` also checks types and starts once for each file; the tree reads the whole program into memory, the tape a word or two for each token and rule._
