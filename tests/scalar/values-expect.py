#!/usr/bin/env python3
"""The tape of a JSON file as values-main.c prints it, made with Python's json module: the independent reference."""
import json, sys
out = sys.stdout.buffer
def line(s): out.write(s.encode('utf-8', 'surrogatepass') + b'\n')
def walk(x):
    if isinstance(x, dict):
        line('obj')
        for k, v in x.items():
            line('key ' + k); walk(v)
    elif isinstance(x, list):
        line('arr')
        for v in x: walk(v)
    elif x is True: line('true')
    elif x is False: line('false')
    elif x is None: line('null')
    elif isinstance(x, int) and -(1 << 63) <= x < (1 << 63): line('int %d' % x)
    elif isinstance(x, (int, float)): line('dbl %.17g' % float(x))
    else: line('str ' + x)
walk(json.load(open(sys.argv[1], encoding='utf-8')))
