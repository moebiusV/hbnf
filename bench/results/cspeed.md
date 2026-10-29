**47 translation units, 5.0 MB of preprocessed C** (Lua 5.4.7, zlib 1.3.1, the SQLite 3.45.1 amalgamation; best of 5 runs):

| tool | time | MB/s | peak memory, the largest unit alone |
|---|---:|---:|---:|
| hbnf (C backend), the C11 grammar, typed tree | 0.38 s | 13.1 MB/s | 352 MB (2.5 MB of C) |
| `gcc -fsyntax-only` | 0.43 s | 11.6 MB/s | |

_2026-10-29; gcc (Debian 14.2.0-19) 14.2.0;ldd (Debian GLIBC 2.41-12+deb13u4) 2.41; `-O2`; hbnf 96ac67b.  `gcc -fsyntax-only` also checks types and starts once for each file; the parser reads the whole tree into memory._
