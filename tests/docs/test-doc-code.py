#!/usr/bin/env python3
"""Check that explicit documentation run contracts fail when evidence drifts."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('doc_code', HERE / 'verify-doc-code.py')
CODE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CODE)


class Contracts(unittest.TestCase):
    def contract(self, marker='<!-- doc-gate:run -->', info='', output='answer\n'):
        src = '%s\n```scheme%s\n(fn (main) 0)\n```\n' % (marker, info)
        if output is not None:
            src += '```text\n%s```\n' % output
        failures = []
        result = CODE.run_contract(src, CODE.FENCE.search(src), 'guide:1', failures)
        return result, failures

    def test_explicit_stdin_and_exit_status(self):
        contract, failures = self.contract(
            '<!-- doc-gate:run {"stdin":"body\\r\\n", "status":7} -->')
        self.assertEqual(contract, ('body\r\n', 7, 'answer\n'))
        self.assertEqual(failures, [])

    def test_unmarked_examples_are_not_executed(self):
        self.assertEqual(self.contract(marker=''), (None, []))

    def test_refused_fragments_and_missing_output_are_errors(self):
        for info in (' fragment', ' refused', ' excerpt'):
            with self.subTest(info=info):
                contract, failures = self.contract(info=info)
                self.assertIsNone(contract)
                self.assertTrue(failures)
        self.assertTrue(self.contract(output=None)[1])

    def test_invalid_options_are_errors(self):
        for options in ('{"stdin":3}', '{"status":true}', '{"status":256}',
                        '{"status":-1}', '{"shell":"echo forged"}', '{bad}'):
            with self.subTest(options=options):
                contract, failures = self.contract('<!-- doc-gate:run %s -->' % options)
                self.assertIsNone(contract)
                self.assertTrue(failures)

    def test_output_and_status_are_independent_checks(self):
        with tempfile.TemporaryDirectory() as work:
            for status, stdout, expected_success in (
                    (0, 'answer\n', 1), (0, 'wrong\n', 0),
                    (1, 'answer\n', 0), (-11, 'answer\n', 0)):
                with self.subTest(status=status, stdout=stdout):
                    result = subprocess.CompletedProcess([], status, stdout, '')
                    failures = []
                    with patch.object(CODE.subprocess, 'run', return_value=result):
                        ok = CODE.run_block('axiom', ('input', 0, 'answer\n'),
                                            'guide:1', failures, work)
                    self.assertEqual(ok, expected_success)
                    self.assertEqual(bool(failures), not expected_success)

    def test_stdin_is_forwarded_and_execution_is_bounded(self):
        result = subprocess.CompletedProcess([], 7, 'answer\n', '')
        with tempfile.TemporaryDirectory() as work:
            with patch.object(CODE.subprocess, 'run', return_value=result) as run:
                self.assertEqual(CODE.run_block('axiom', ('input\r\n', 7, 'answer\n'),
                                               'guide:1', [], work), 1)
                self.assertEqual(run.call_args.kwargs['input'], 'input\r\n')
                self.assertEqual(run.call_args.kwargs['cwd'], work)
                self.assertEqual(run.call_args.kwargs['timeout'], 30)


if __name__ == '__main__':
    unittest.main()
