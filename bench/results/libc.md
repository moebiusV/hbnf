| document | musl | glibc |
|---|---:|---:|
| json (2 MB) | 13.21 ms | 9.95 ms |
| toml (2 MB) | 30.25 ms | 20.19 ms |
| yaml (2 MB) | 145.90 ms | 112.82 ms |

_2026-10-24; musl: musl libc (x86_64), gcc 15.2.0; glibc: glibc 2.41, gcc 14.2.0; `-O2`, best of 7 runs, hbnf 7497dad.  The two builds use different gcc versions, as the container and the host do._
