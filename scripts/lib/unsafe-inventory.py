#!/usr/bin/env python3
"""Read `axiom symbols --calls` on stdin and inventory its unsafe boundaries."""

import json
import re
import sys
from urllib.parse import unquote


HEADER = re.compile(r'^F (\S+) (\S+) "(?:[^"\\]|\\.)*"(?: (.*))?$')


def read_rows(lines):
    rows = {}
    for line in lines:
        match = HEADER.match(line.rstrip('\n'))
        if not match:
            if line.startswith('F '):
                raise ValueError('malformed AXSYM function row')
            continue
        name, location, tail = match.groups()
        fields = {}
        for token in (tail or '').split():
            if token.startswith('#'):
                key, _, value = token[1:].partition('=')
                fields[key] = unquote(value)
        row = rows.setdefault((name, location), {
            'name': name, 'location': location, 'fields': {}, 'calls': set(),
        })
        row['fields'].update(fields)
        row['calls'].update(filter(None, fields.get('calls', '').split(',')))
    return list(rows.values())


def file_path(location):
    return re.sub(r':(?:\d+:\d+(?:-\d+(?::\d+)?)?|\-)$', '', location)


def is_target(call, caller, target):
    module, separator, name = call.rpartition('$')
    if not separator:
        return call == target['name'] and file_path(caller['location']) == file_path(target['location'])
    path = file_path(target['location']).replace('\\', '/')
    path = re.sub(r'\.(?:darwin|linux|freebsd|windows)-(?:aarch64|x86_64)\.ax$', '.ax', path)
    return name == target['name'] and ('/' + path).endswith('/' + module.replace('.', '/') + '.ax')


def inventory(rows):
    if not rows or not any('calls' in row['fields'] for row in rows):
        raise ValueError('expected AXSYM from `symbols --calls`')
    boundaries = []
    for row in rows:
        fields = row['fields']
        role = fields.get('unsafe')
        if role is None:
            if 'unsafe' in fields.get('effect', '').split(','):
                raise ValueError(f"{row['name']}: unsafe declaration has no boundary role")
            continue
        if role != 'trusted':
            raise ValueError(f"{row['name']}: unknown unsafe role {role!r}")
        callers = [
            {'name': caller['name'], 'location': caller['location']}
            for caller in rows
            if any(is_target(call, caller, row) for call in caller['calls'])
        ]
        boundaries.append({
            'name': row['name'], 'location': row['location'], 'role': role,
            'effects': list(filter(None, fields.get('effects', '').split(','))),
            'calls': sorted(row['calls']),
            'callers': sorted(callers, key=lambda caller: (caller['location'], caller['name'])),
        })
    if not boundaries:
        raise ValueError('the symbol stream contains no unsafe boundaries')
    return {'boundaries': sorted(boundaries, key=lambda row: (row['location'], row['name']))}


def main():
    try:
        result = inventory(read_rows(sys.stdin))
    except ValueError as error:
        print(f'unsafe-inventory: {error}', file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
