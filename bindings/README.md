# astbnf FFI bindings

The C backend (`astbnf --backend=c --conf`) emits a plain-C `conf.h`/`conf.c`
with a `parse_config(filename)` entry, a global `conf` root and an overridable
`conf_error` handler.  Because that output is ordinary C (no runtime, no
macros, no opaque types), any language with an FFI can drive it directly.

This directory holds example bindings for the `tests/server.astbnf` schema.
The struct layout they mirror is schema-specific — regenerate them for a
different schema (the C `typedef struct` in `conf.h` is the source of truth).

## Build the shared library

```sh
astbnf schema.astbnf --backend=c --conf > conf-out.txt
# split conf.h / conf.c (see tests/e2e.sh), then:
cc -shared -fPIC conf.c -o libhbnfconf.so
```

## Languages

| language | file              | FFI mechanism                     |
|----------|-------------------|-----------------------------------|
| Python   | `python/hbnfconf.py`  | `ctypes` (stdlib)                 |
| Ruby     | `ruby/hbnfconf.rb`    | `Fiddle` (stdlib)                 |
| Perl     | `perl/hbnfconf.pm`    | `FFI::Platypus` (`cpanm` it first)|
| newLISP  | `newlisp/hbnfconf.lsp`| `(import)`                        |

Each binding exposes the same shape: load `libhbnfconf.so`, call
`parse_config`, return the config as a native dict/hash/…, and let you override
the error handler instead of the default `exit(1)`.

`libhbnfconf.so` must be on the load path (`LD_LIBRARY_PATH=.` on Linux) or
placed alongside the binding.
