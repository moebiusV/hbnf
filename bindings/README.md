# hbnf FFI bindings

A grammar writes its own entry points in its epilogue, and the C backend's output is ordinary
C (no runtime, no macros, no opaque types), so any language with an FFI can drive it directly.
`tests/server_ffi.hbnf` is the example: its epilogue defines `parse_config(filename)`, a global
`conf` root, `conf_ptr()` and `free_conf()`, and the error handler `conf_error` comes from
`runtime/hbnf_conf.h`.

This directory holds example bindings for that schema.  The struct layout they mirror is
schema-specific — regenerate them for a different schema (the C `typedef struct` in the
generated file is the source of truth).

## Build the shared library

```sh
hbnf tests/server_ffi.hbnf --backend=c --no-views > server_ffi.c
cc -shared -fPIC -Iruntime server_ffi.c runtime/hbnf_conf.c -o libhbnfconf.so
```

(`--no-views` makes the strings NUL-terminated copies, which the bindings read as C strings.)

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
