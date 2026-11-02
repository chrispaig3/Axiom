#!/usr/bin/env python3
"""Keep the compiler's temporary JSON codec equivalent to the private library copy."""
from pathlib import Path
import re

TOKEN = re.compile(r';[^\n]*|"(?:\\.|[^"\\])*"|[(){}\[\]]|[^\s(){}\[\]"]+')
HELPERS = {
    'rawAlloc': 'memAlloc',
    'rawSetWord': 'memSetWord',
    'rawGetWord': 'memGetWord',
    'rawGetWordStr': 'memGetWordStr',
    'rawGetWordVec': 'memGetWordVec',
    'rawVecGetStr': 'vecGetStr',
}


def forms(source):
    result, current, depth = [], [], 0
    for match in TOKEN.finditer(source):
        token = match.group()
        if token.startswith(';'):
            continue
        if token == '(':
            depth += 1
        current.append(token)
        if token == ')':
            depth -= 1
            if depth == 0:
                result.append(current)
                current = []
    if current or depth:
        raise RuntimeError('unbalanced source while comparing JSON implementations')
    return result


def normal(form):
    # Visibility differs: only the library-internal copy exports shared grammar
    # helpers to Cereal. Runtime helpers have the compiler's established names.
    return [HELPERS.get(token, token) for token in form if token != 'pub']


def functions(root, filenames):
    result = {}
    for filename in filenames:
        for form in forms((root / filename).read_text()):
            value = normal(form)
            if value[1] == 'fn':
                result[value[3]] = value
    return result


def check(root):
    copies = []
    for filename in ('stdlib/Internal/CerealJson.ax', 'core/jsonrpc.ax'):
        copies.append([normal(form) for form in forms((root / filename).read_text())
                       if form[1] != 'import'])
    if copies[0] != copies[1]:
        raise RuntimeError('compiler JSON implementation differs from the private library copy')
    library = functions(root, ('stdlib/Internal/Raw.ax', 'stdlib/Internal/RawVec.ax'))
    compiler = functions(root, ('core/raw.ax',))
    for name in HELPERS.values():
        if library[name] != compiler[name]:
            raise RuntimeError(name + ': compiler and library raw helper bodies differ')
    print(f'ok   {len(copies[0])} JSON declarations and {len(HELPERS)} raw helpers agree')


if __name__ == '__main__':
    check(Path(__file__).resolve().parents[2])
