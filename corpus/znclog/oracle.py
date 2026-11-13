#!/usr/bin/env python3
"""reader.go's UnmarshalLine (events on), as the canonical lines the znclog transducer makes.  The splits are Go's strings.SplitN."""
import re
import sys

def trim_prefix(s, p): return s[len(p):] if s.startswith(p) else s
def trim_suffix(s, p): return s[:-len(p)] if p and s.endswith(p) else s

def line(l):
    if not re.match(r"\[\d\d:\d\d:\d\d\] ", l):
        raise ValueError("malformed timestamp prefix")
    l = l[11:]
    if l.startswith("*** "):
        parts = l[4:].split(" ", 1)
        if len(parts) != 2: return "SKIP"
        if parts[0] in ("Joins:", "Parts:", "Quits:"):
            args = parts[1].split(" ", 2)
            if len(args) < 2: return "SKIP"
            nick = args[0]
            mask = trim_suffix(trim_prefix(args[1], "("), ")")
            mp = mask.split("@", 1)
            if len(mp) != 2: return "SKIP"
            reason = ""
            if len(args) > 2:
                reason = trim_suffix(trim_prefix(args[2], "("), ")")
            return "\t".join([parts[0], nick, mp[0], mp[1], reason])
        nick, rem = parts
        if rem.startswith("is now known as "):
            return "\t".join(["NICK", nick, rem[len("is now known as "):]])
        if rem.startswith("was kicked by "):
            r = rem[len("was kicked by "):]
            a = r.split(" ", 1)
            if len(a) != 2: return "SKIP"
            return "\t".join(["KICK", nick, a[0], trim_suffix(trim_prefix(a[1], "("), ")")])
        if rem.startswith("changes topic to "):
            r = rem[len("changes topic to "):]
            return "\t".join(["TOPIC", nick, trim_suffix(trim_prefix(r, "'"), "'")])
        if rem.startswith("sets mode: "):
            return "\t".join(["MODE", nick, rem[len("sets mode: "):]])
        return "SKIP"
    if l.startswith("<"):
        p = l[1:].split("> ", 1)
        return "SKIP" if len(p) != 2 else "\t".join(["PRIVMSG", p[0], p[1]])
    if l.startswith("-"):
        p = l[1:].split("- ", 1)
        return "SKIP" if len(p) != 2 else "\t".join(["NOTICE", p[0], p[1]])
    if l.startswith("* "):
        p = l[2:].split(" ", 1)
        return "SKIP" if len(p) != 2 else "\t".join(["ACTION", p[0], p[1]])
    return "SKIP"

if __name__ == "__main__":
    data = open(sys.argv[1], "rb").read().decode("utf-8", "surrogateescape")
    out = []
    lines = data.split("\n")
    if lines and lines[-1] == "": lines.pop()
    for l in lines:
        out.append(line(l))
    sys.stdout.write("\n".join(out) + ("\n" if out else ""))
