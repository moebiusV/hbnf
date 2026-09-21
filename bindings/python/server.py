#!/usr/bin/env python3
"""ctypes binding for the astbnf C config parser (tests/server.astbnf schema).

Build libserver.so first (see bindings/README.md), then either import this
module or run it directly:

    LD_LIBRARY_PATH=. python3 server.py valid.conf
"""
import ctypes
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
lib = ctypes.CDLL(os.path.join(_HERE, "libserver.so"))


class Listen(ctypes.Structure):
    _fields_ = [("iface", ctypes.c_char_p), ("port", ctypes.c_uint16)]


class Redirects(ctypes.Structure):
    pass


class Aliases(ctypes.Structure):
    pass


Redirects._fields_ = [
    ("next", ctypes.POINTER(Redirects)),
    ("dest", ctypes.c_char_p),
    ("group", ctypes.c_char_p),
]
Aliases._fields_ = [
    ("next", ctypes.POINTER(Aliases)),
    ("alias", ctypes.c_char_p),
]


class Server(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char_p),
        ("listen", Listen),
        ("root", ctypes.c_char_p),
        ("redirects", ctypes.POINTER(Redirects)),
        ("aliases", ctypes.POINTER(Aliases)),
        ("tls", ctypes.c_bool),
    ]


lib.parse_config.restype = ctypes.c_int
lib.parse_config.argtypes = [ctypes.c_char_p]
lib.conf_ptr.restype = ctypes.POINTER(Server)
lib.conf_ptr.argtypes = []


def _str(p):
    return p.decode() if p else None


def _walk(node, field):
    out = []
    while node:
        out.append(field(node.contents))
        node = node.contents.next
    return out


def parse_config(path):
    if lib.parse_config(path.encode()) != 0:
        return None
    s = lib.conf_ptr().contents
    return {
        "name": _str(s.name),
        "listen": {"iface": _str(s.listen.iface), "port": s.listen.port},
        "root": _str(s.root),
        "redirects": _walk(
            s.redirects, lambda n: {"dest": _str(n.dest), "group": _str(n.group)}
        ),
        "aliases": _walk(s.aliases, lambda n: _str(n.alias)),
        "tls": bool(s.tls),
    }


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "valid.conf"
    cfg = parse_config(path)
    print(json.dumps(cfg, indent=2) if cfg else "parse failed")
