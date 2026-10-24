#!/usr/bin/env python3
"""time_py.py TOOL FILE: parse FILE with a Python library and print "ok BYTES MS RSS_KIB".
TOOL: json, tomllib, yaml-c (PyYAML on libyaml), yaml-py (PyYAML in Python).  The file is read
first and the clock is around the parse call; the result is a Python object, as the library
gives it."""
import resource, sys, time

tool, path = sys.argv[1], sys.argv[2]
data = open(path, "rb").read().decode("utf-8")
if tool == "json":
    import json
    fn = lambda: json.loads(data)
elif tool == "tomllib":
    import tomllib
    fn = lambda: tomllib.loads(data)
elif tool == "yaml-c":
    import yaml
    fn = lambda: yaml.load(data, Loader=yaml.CSafeLoader)
elif tool == "yaml-py":
    import yaml
    fn = lambda: yaml.load(data, Loader=yaml.SafeLoader)
else:
    sys.exit(2)
t0 = time.perf_counter()
fn()
ms = (time.perf_counter() - t0) * 1000.0
print("ok %d %.2f %d" % (len(data.encode("utf-8")), ms, resource.getrusage(resource.RUSAGE_SELF).ru_maxrss))
