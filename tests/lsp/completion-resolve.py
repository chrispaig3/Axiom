#!/usr/bin/env python3
"""Negotiate and resolve completion metadata over the real stdio protocol."""
import copy
from pathlib import Path
import runpy
import sys
import tempfile

Client = runpy.run_path(str(Path(__file__).with_name('workspace-overlays.py')))['Client']

SOURCE = '''(import Helper)
;; Add one to the supplied value. é😀
(:: helper (-> Int Int))
(fn (helper x) (+ x 1))
;; Colours available to callers.
(data Colour (Red) (Green))
;; A small record.
(struct Point (x :: Int))
(:: main Int)
(fn (main) (helper 2))
'''
IMPORTED = ''';; Imported documentation from the unsaved module. π😀
(pub :: remote (-> Int Int))
(pub fn (remote x) (+ x 2))
;; This imported name is shadowed locally.
(pub :: helper (-> Int Int))
(pub fn (helper x) (+ x 9))
;; Imported colours.
(pub data Shade (Blue))
'''


def capabilities(properties):
    return {'textDocument': {'completion': {'completionItem': {
        'resolveSupport': {'properties': properties}}}}}


def response(client, method, params):
    """Retain protocol errors so stale and malformed items can be asserted."""
    client.serial += 1
    identity = 'request/%d' % client.serial
    client.send(method, params, identity)
    while True:
        message = client.inbox.get(timeout=45)
        if isinstance(message, BaseException):
            raise message
        if message.get('method') == 'textDocument/publishDiagnostics':
            client.publications.append(message['params'])
        else:
            assert message.get('id') == identity, message
            return message


def run(compiler):
    checks = 0
    with tempfile.TemporaryDirectory(prefix='axiom-completion-resolve-') as temporary:
        directory = Path(temporary) / 'unsaved π space'
        directory.mkdir()
        (directory / 'Hello.ax').write_text('')
        uri = (directory / 'Main.ax').as_uri()
        imported_uri = (directory / 'Helper.ax').as_uri()
        # No saved Helper.ax: the import must use the open overlay.
        for properties in [None, [], ['detail'], ['documentation'],
                           ['detail', 'documentation'], ['documentation', 'detail', 'other']]:
            deferred = properties is not None and set(properties) >= {'detail', 'documentation'}
            client = Client(compiler, cwd=directory)
            try:
                caps = {} if properties is None else capabilities(properties)
                initial = client.request('initialize', {'capabilities': caps})
                assert initial['capabilities']['completionProvider'] == {
                    'resolveProvider': deferred, 'triggerCharacters': ['(']}, initial
                client.opening(imported_uri, IMPORTED)
                client.opening(uri, SOURCE)

                def completion(source=SOURCE, anchor='(helper 2)', prefix=0):
                    off = source.index(anchor) + prefix if anchor else len(source)
                    before = source[:off]
                    result = client.request('textDocument/completion', {
                        'textDocument': {'uri': uri}, 'position': {
                            'line': before.count('\n'),
                            'character': len(before.rsplit('\n', 1)[-1].encode('utf-16-le')) // 2}})
                    assert result['isIncomplete'] is True and len(result['items']) <= 200, result
                    return {item['label']: item for item in result['items']}

                items = completion()
                assert len(items) >= 10, items
                assert items['remote']['detail'] == 'Helper', items['remote']
                helper = items['helper']
                if not deferred:
                    assert helper['detail'] == '(-> Int Int)', helper
                    assert all('data' not in item and 'documentation' not in item
                               for item in items.values()), items
                    assert client.request('completionItem/resolve', helper) == helper
                    checks += 1
                    continue

                assert 'detail' not in helper and 'documentation' not in helper, helper
                assert helper['data']['uri'] == uri, helper
                assert all('data' not in items[word] for word in ['fn', 'if']), items
                for name, doc in [('helper', 'Add one to the supplied value. é😀'),
                                  ('remote', 'Imported documentation from the unsaved module. π😀'),
                                  ('Colour', 'Colours available to callers.'),
                                  ('Red', 'Colours available to callers.'),
                                  ('Point', 'A small record.'),
                                  ('Blue', 'Imported colours.')]:
                    original = items[name]
                    supplied = dict(original, sortText='client-sort', insertText=name,
                                    additionalTextEdits=[], custom={'keep': 'é😀'})
                    resolved = client.request('completionItem/resolve', supplied)
                    assert all(resolved.get(key) == value for key, value in supplied.items()), resolved
                    assert resolved['documentation'].rstrip('\n') == doc, resolved
                    if name == 'helper':
                        assert resolved['detail'] == '(-> Int Int)', resolved
                    assert client.request('completionItem/resolve', resolved) == resolved
                    checks += 1

                assert list(completion(anchor='(helper 2)', prefix=3)) == ['helper']
                assert client.request('completionItem/resolve', items['if']) == items['if']
                assert client.request('completionItem/resolve', {'label': 'external',
                                      'data': {'owner': 'another-client'}}) == {
                                          'label': 'external', 'data': {'owner': 'another-client'}}
                bad = copy.deepcopy(helper)
                bad['data']['start'] = -1
                assert response(client, 'completionItem/resolve', bad)['error']['code'] == -32602
                bad = copy.deepcopy(helper)
                bad['label'] = 'remote'
                assert response(client, 'completionItem/resolve', bad)['error']['code'] == -32602
                for malformed in [None, [], 12, {'data': helper['data']}]:
                    assert response(client, 'completionItem/resolve', malformed)['error']['code'] == -32602
                checks += 8

                # An accepted edit of either the entry or a dependency expires old data.
                client.change(imported_uri, IMPORTED.replace('unsaved module', 'updated module'), 2)
                assert response(client, 'completionItem/resolve', items['remote'])['error']['code'] == -32801
                current = completion()['remote']
                assert 'updated module' in client.request('completionItem/resolve', current)['documentation']
                current = completion()['helper']
                client.change(uri, SOURCE + '\n', 2)
                assert response(client, 'completionItem/resolve', current)['error']['code'] == -32801
                current = completion()['helper']
                client.send('textDocument/didClose', {'textDocument': {'uri': uri}})
                client.opening(uri, SOURCE, 1)
                assert response(client, 'completionItem/resolve', current)['error']['code'] == -32801
                current = completion()['helper']
                client.send('workspace/didChangeWatchedFiles', {'changes': []})
                client.barrier()
                assert response(client, 'completionItem/resolve', current)['error']['code'] == -32801
                checks += 5

                # Incomplete source and import-path completion remain immediately usable.
                broken = '(fn (unfinished) (hel'
                client.change(uri, broken, 2)
                assert 'fn' in completion(broken, anchor='(fn', prefix=1)
                import_path = '(import Hel'
                client.change(uri, import_path, 3)
                module = completion(import_path, anchor=None)['Hello']
                assert 'data' not in module, module
                checks += 2

                # The menu cap still applies when each declaration carries data.
                large = ''.join(f'(:: item{i} Int)\n(fn (item{i}) {i})\n' for i in range(220))
                client.change(uri, large, 4)
                capped = completion(large, anchor=None)
                assert len(capped) == 200, len(capped)
                assert all('detail' not in item for item in capped.values()
                           if 'data' in item), capped
                selected = next(item for item in capped.values() if 'data' in item)
                resolved = client.request('completionItem/resolve', selected)
                assert resolved['detail'] == 'Int' and 'documentation' not in resolved, resolved
                checks += 1
            finally:
                if client.process.poll() is None:
                    client.close()
                assert client.process.stderr.read() == b''
    print(f'ok   completion resolution: {checks} protocol checks, eager and deferred clients')


if __name__ == '__main__':
    run(str(Path(sys.argv[1]).resolve()))
