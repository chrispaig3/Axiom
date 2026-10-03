#!/usr/bin/env python3
"""Exercise boundary roles, source identity and resolved caller edges."""

import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'unsafe_inventory', Path(__file__).resolve().parents[2] / 'scripts/lib/unsafe-inventory.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

source = '''F borrow stdlib/Ffi.ax:3:9 "Int" @1 #effect=unsafe #effects=Unsafe #unsafe=trusted #calls=__load64
F borrow other/Ffi.ax:3:9 "Int" @2 #effect=unsafe #effects=Unsafe #unsafe=trusted #calls=__load64
F free stdlib/Ffi.ax:9:9 "Int" @3 #effect=unsafe #precondition=live%20buffer%20%E2%89%A5%201%20byte #effects=IO,Unsafe #unsafe=precondition #calls=raw
F free stdlib/Ffi.ax:9:9 "Int" #effect=unsafe #unsafe=precondition
F use app.ax:2:5 "Int" @4 #calls=Ffi$free
F local stdlib/Ffi.ax:12:5 "Int" @5 #calls=borrow
'''
rows = tool.inventory(tool.read_rows(source.splitlines()))['boundaries']
assert len(rows) == 3
free = next(row for row in rows if row['name'] == 'free')
assert free['precondition'] == 'live buffer ≥ 1 byte'
assert free['callers'] == [{'name': 'use', 'location': 'app.ax:2:5'}]
local = next(row for row in rows if row['location'] == 'stdlib/Ffi.ax:3:9')
assert local['callers'] == [{'name': 'local', 'location': 'stdlib/Ffi.ax:12:5'}]
other = next(row for row in rows if row['location'] == 'other/Ffi.ax:3:9')
assert other['callers'] == []

for invalid in ['', 'F f f.ax:1:1 "Int" #unsafe=trusted',
                'F f f.ax:1:1 "Int" #calls=g #effect=unsafe',
                'F f f.ax:1:1 "Int" #calls=g #unsafe=precondition',
                'F f f.ax:1:1 "Int" #calls=g #unsafe=unknown',
                'F malformed']:
    try:
        tool.inventory(tool.read_rows(invalid.splitlines()))
    except ValueError:
        pass
    else:
        raise AssertionError(f'invalid inventory accepted: {invalid!r}')
print('ok   unsafe inventory: roles, duplicate rows, escaped text and caller identity')
