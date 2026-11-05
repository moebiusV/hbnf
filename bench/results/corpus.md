| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 27 files x 424 | 30.0 MB | 13 ms | 14 ms | 0.98x | 33 MB | 33 MB | 1.00x |
| mustache | 25 files x 20000 | 7.4 MB | 52 ms | 43 ms | 1.22x | 75 MB | 43 MB | 1.76x |
| algol60 | 5 files x 12615 | 30.0 MB | 358 ms | 330 ms | 1.09x | 390 MB | 285 MB | 1.37x |
| bgpd | 4 files x 20000 | 19.7 MB | 408 ms | 377 ms | 1.08x | 346 MB | 257 MB | 1.34x |
| httpd | 1 files x 20000 | 15.9 MB | 247 ms | 203 ms | 1.22x | 197 MB | 86 MB | 2.29x |
| ntpd | 1 files x 20000 | 6.9 MB | 57 ms | 56 ms | 1.00x | 32 MB | 32 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 633 ms | 478 ms | 1.32x | 740 MB | 229 MB | 3.22x |
| relayd | 2 files x 20000 | 15.2 MB | 188 ms | 183 ms | 1.03x | 65 MB | 49 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 110 ms | 107 ms | 1.03x | 59 MB | 46 MB | 1.29x |
| unwind | 1 files x 20000 | 4.7 MB | 48 ms | 48 ms | 1.01x | 16 MB | 15 MB | 1.07x |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
