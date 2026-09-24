#!/usr/bin/env python3
"""Reverse gen_templates: pull each string constant out of templates.ads and
write it back to the source template file it was generated from, so the next
`gen_templates` run reproduces templates.ads exactly (idempotent round-trip)."""

import sys

# constant name -> source template path (the files gen_templates reads)
CONSTANTS = {
    "C_Lexer": "templates/lexer.c",
    "Rust_Lexer": "templates/lexer.rs",
    "Zig_Lexer": "templates/lexer.zig",
    "Ada_Lexer": "templates/lexer.ada",
    "Conf_H": "templates/conf.h",
    "Conf_Tail_C": "templates/conf_tail.c",
    "Conf_H_Typed": "templates/conf_typed.h",
    "Conf_Tail_C_Typed": "templates/conf_tail_typed.c",
    "Conf_Rust": "templates/conf.rs",
    "Conf_Zig": "templates/conf.zig",
    "Conf_Ada": "templates/conf.ada",
}


def extract(ads_text, name):
    marker = f"   {name} : constant String :="
    i = ads_text.index(marker)
    j = ads_text.index("\n", i)
    lines = []
    k = j + 1
    while True:
        e = ads_text.index("\n", k)
        line = ads_text[k:e]
        assert line.startswith('     "'), repr(line)
        body = line[6:]  # strip 5-space indent + opening quote
        if body.endswith(" & LF &"):
            body = body[: -len(" & LF &")]
            assert body.endswith('"'), repr(line)
            body = body[:-1]
            lines.append(body)
            k = e + 1
        else:
            assert body.endswith('";'), repr(line)
            lines.append(body[:-2])
            break
    text = "\n".join(lines) + "\n"
    return text.replace('""', '"')


def main():
    ads = open("templates.ads").read()
    for name, path in CONSTANTS.items():
        try:
            text = extract(ads, name)
        except (ValueError, AssertionError) as exc:
            print(f"FAIL extracting {name}: {exc}", file=sys.stderr)
            sys.exit(1)
        with open(path, "w") as f:
            f.write(text)
        print(f"wrote {path} ({len(text)} bytes)")


if __name__ == "__main__":
    main()
