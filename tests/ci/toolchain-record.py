#!/usr/bin/env python3
"""A saved build record binds its compiler and records exact native inputs."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('toolchain_record', ROOT / 'scripts/record-toolchain.py')
record = importlib.util.module_from_spec(spec)
spec.loader.exec_module(record)


class ToolchainRecordTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.compiler = self.root / 'axiom'
        self.compiler.write_bytes(b'compiler bytes')
        self.tool = self.root / 'native-tool'
        self.tool.write_bytes(b'native tool bytes')
        self.document = {
            'schema': 1, 'target': 'linux-aarch64',
            'compiler': {'sha256': record.digest(self.compiler), 'version': 'Axiom 0.8.0 (build test)'},
            'tools': {name: {'path': str(self.tool), 'sha256': record.digest(self.tool),
                             'version': 'tool 18.1.8', 'version_status': 0}
                      for name in (*record.TOOLS, *record.OPTIONAL_TOOLS, 'native-linker')},
            'environment': {key: None for key in record.ENVIRONMENT},
            'source': {'revision': 'a' * 40, 'sha256': 'b' * 64,
                       'recipe_and_seed_sha256': {name: 'c' * 64 for name in
                           (*record.RECIPES, 'bootstrap/axiom-linux-aarch64.ll')}},
            'host': {'os_release': 'test OS', 'packages': 'test-package\t1.0'},
        }

    def test_archive_verification_binds_exact_compiler(self):
        record.verify(self.document, self.compiler, 'linux-aarch64')
        self.compiler.write_bytes(b'a different compiler')
        with self.assertRaisesRegex(ValueError, 'compiler digest'):
            record.verify(self.document, self.compiler, 'linux-aarch64')

    def test_refuse_missing_schema_target_and_tools(self):
        for label, mutate in (
            ('schema', lambda d: d.update(schema=2)),
            ('target', lambda d: d.update(target='darwin-aarch64')),
            ('missing tool', lambda d: d['tools'].pop('llc')),
            ('missing digest', lambda d: d['tools']['llc'].pop('sha256')),
            ('empty version', lambda d: d['tools']['llc'].update(version='')),
            ('native linker', lambda d: d['tools'].pop('native-linker')),
            ('split tool', lambda d: d['tools'].pop('llvm-split')),
            ('parallel codegen', lambda d: d['environment'].pop('AXIOM_CODEGEN_JOBS')),
            ('source', lambda d: d.pop('source')),
            ('seed', lambda d: d['source']['recipe_and_seed_sha256'].pop('bootstrap/axiom-linux-aarch64.ll')),
            ('packages', lambda d: d['host'].pop('packages')),
        ):
            with self.subTest(label=label):
                document = copy.deepcopy(self.document)
                mutate(document)
                with self.assertRaises(ValueError):
                    record.verify(document, self.compiler, 'linux-aarch64')

    def test_native_tool_records_resolved_file_and_full_version(self):
        link = self.root / 'llc'
        link.symlink_to(self.tool.name)
        with patch.object(record.shutil, 'which', return_value=str(link)), \
                patch.object(record, 'command', return_value=(0, 'LLVM version 18.1.8\nTarget: aarch64\n')) as probe:
            got = record.tool_record('llc')
        probe.assert_called_once_with([str(link), '--version'])
        self.assertEqual(got['path'], str(self.tool))
        self.assertEqual(got['sha256'], record.digest(self.tool))
        self.assertIn('Target: aarch64', got['version'])

    def test_missing_or_failed_native_tool_refuses_record(self):
        with patch.object(record.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'missing native tool'):
                record.tool_record('llc')

    def test_optional_split_tool_absence_is_recorded_explicitly(self):
        with patch.object(record.shutil, 'which', return_value=None):
            self.assertIsNone(record.tool_record('llvm-split', optional=True))
        self.document['tools']['llvm-split'] = None
        self.document['environment']['AXIOM_CODEGEN_JOBS'] = '1'
        record.verify(self.document, self.compiler, 'linux-aarch64')
        with patch.object(record.shutil, 'which', return_value=str(self.tool)), \
                patch.object(record, 'command', return_value=(1, 'broken')):
            with self.assertRaisesRegex(ValueError, 'version probe failed'):
                record.tool_record('llc')

    def test_source_identity_moves_on_rename_and_bytes(self):
        (self.root / 'core').mkdir()
        (self.root / 'stdlib').mkdir()
        source = self.root / 'core/main.ax'
        source.write_text('first')
        first = record.source_digest(self.root)
        source.write_text('second')
        self.assertNotEqual(record.source_digest(self.root), first)
        second = record.source_digest(self.root)
        source.rename(self.root / 'core/other.ax')
        self.assertNotEqual(record.source_digest(self.root), second)

    def test_source_identity_matches_build_stamp_recipe(self):
        import subprocess
        expected = subprocess.check_output(
            ['bash', '-c', 'source "$1"; gate_seed_source_stamp "$2"',
             'toolchain-test', str(ROOT / 'scripts/lib/gate.sh'), str(ROOT)], text=True).strip()
        self.assertEqual(record.source_digest(ROOT), expected)

    def test_host_target_cannot_be_guessed_from_requested_name(self):
        with patch.object(record.platform, 'system', return_value='Darwin'), \
                patch.object(record.platform, 'machine', return_value='arm64'):
            self.assertEqual(record.host_target(), 'darwin-aarch64')
        with patch.object(record.platform, 'system', return_value='Linux'), \
                patch.object(record.platform, 'machine', return_value='unexpected'):
            with self.assertRaises(ValueError):
                record.host_target()

    def test_canonical_write_has_no_clock_and_is_atomic_on_bad_data(self):
        path = self.root / 'record.json'
        record.save(path, self.document)
        first = path.read_bytes()
        record.save(path, self.document)
        self.assertEqual(path.read_bytes(), first)
        self.assertEqual(json.loads(first), self.document)
        with self.assertRaises(TypeError):
            record.save(path, {'bad': object()})
        self.assertEqual(path.read_bytes(), first)

    def test_release_refuses_dirty_sources_and_unrelated_compilers(self):
        for dirty, message in ((' M core/main.ax', 'clean checkout'), ('', 'source build stamp')):
            def probe(argv, cwd=None):
                if argv[0] == 'git':
                    if 'status' in argv:
                        return 0, dirty
                    return 0, 'a' * (12 if '--short=12' in argv else 40)
                return 0, 'Axiom 0.8.0 (build unrelated)'
            with self.subTest(dirty=dirty), \
                    patch.object(record, 'command', side_effect=probe), \
                    patch.object(record, 'source_digest', return_value='b' * 64), \
                    patch.object(record, 'host_target', return_value='linux-aarch64'):
                with self.assertRaisesRegex(ValueError, message):
                    record.create(self.root, 'linux-aarch64', self.compiler, release=True)

    def test_release_archive_contains_and_verifies_record(self):
        reader_spec = importlib.util.spec_from_file_location('ci_reader', ROOT / 'scripts/lib/ci-native-seeds.py')
        reader = importlib.util.module_from_spec(reader_spec)
        reader_spec.loader.exec_module(reader)
        workflow = reader.parse((ROOT / '.github/workflows/release.yml').read_text())
        steps = workflow['jobs']['build']['steps']
        runs = [step.get('run', '') for step in steps]
        recorder = next(i for i, run in enumerate(runs) if 'record-toolchain.py --release' in run)
        archive = next(i for i, run in enumerate(runs) if 'tar -czf' in run)
        unpack = next(i for i, run in enumerate(runs) if 'tar -xzf' in run)
        self.assertLess(recorder, archive)
        self.assertLess(archive, unpack)
        self.assertIn('cp "$RUNNER_TEMP/out/toolchain.json" "$d/toolchain.json"', runs[archive])
        self.assertIn('--verify "$RUNNER_TEMP/unpack/$d/toolchain.json"', runs[unpack])
        self.assertIn('--compiler "$RUNNER_TEMP/unpack/$d/bin/axiom"', runs[unpack])

    def test_untracked_source_cannot_claim_a_clean_release_revision(self):
        import subprocess
        for command in (
            ['git', 'init', '-q'], ['git', 'add', '.'],
            ['git', '-c', 'user.name=Toolchain probe', '-c', 'user.email=toolchain@example.invalid',
             'commit', '-qm', 'Fixture'],
        ):
            subprocess.run(command, cwd=self.root, check=True)
        (self.root / 'core').mkdir()
        (self.root / 'core/untracked.ax').write_text('(:: added Int)\n(fn (added) 1)\n')
        with patch.object(record, 'host_target', return_value='linux-aarch64'):
            with self.assertRaisesRegex(ValueError, 'clean checkout'):
                record.create(self.root, 'linux-aarch64', self.compiler, release=True)


if __name__ == '__main__':
    unittest.main()
