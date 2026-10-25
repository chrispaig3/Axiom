#!/usr/bin/env python3
"""Check exact Git pins, revision-specific caches and offline verification."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def check(compiler, root, work):
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'), AXIOM_FRONTEND_JOBS='1')
    repo = work / 'repository with spaces'
    repo.mkdir()

    def git(*args):
        result = subprocess.run(['git', '-C', str(repo), *args], env=env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (args, result.stderr)
        return result.stdout.strip()

    git('init', '-q')
    git('config', 'user.name', 'Axiom package test')
    git('config', 'user.email', 'package-test@example.invalid')

    def commit(value):
        (repo / 'Pinned.ax').write_text(
            f'(pub :: answer Int)\n(pub fn (answer) {value})\n')
        git('add', 'Pinned.ax')
        git('commit', '-qm', f'answer {value}')
        return git('rev-parse', 'HEAD')

    first = commit(11)
    second = commit(22)
    url = repo.as_uri()
    project = work / 'project with spaces'
    project.mkdir()
    (project / 'Main.ax').write_text(
        '(import Pinned)\n(:: main Int)\n(fn (main) answer)\n')

    def manifest(revision):
        text = f'name pinned\ndepend {url}\n'
        if revision is not None:
            text += f'pin {url} {revision}\n'
        (project / 'axiom.pkg').write_text(text)

    def cli(*args, expected=0, environment=None):
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', *args],
                                cwd=project, env=environment or env,
                                capture_output=True, text=True, timeout=240)
        assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
        return result

    def checkouts():
        base = project / '.axiom/deps'
        return sorted(p for p in base.iterdir() if not p.name.startswith('.fetch-'))

    def run_answer(value, environment=None):
        target = project / 'program'
        cli('build', 'Main.ax', '-o', str(target), environment=environment)
        result = subprocess.run([str(target)], capture_output=True, timeout=30)
        assert result.returncode == value, (result.returncode, value, result.stderr)

    manifest(first)
    cli('fetch')
    old = checkouts()[0]
    assert (old / '.git/HEAD').read_text().strip() == first
    run_answer(11)
    assert 'present ' in cli('fetch').stdout
    print('ok   an older exact revision is fetched detached and reused', flush=True)

    (old / 'Pinned.ax').write_text('local changes must survive\n')
    manifest(second)
    cli('fetch')
    new = next(p for p in checkouts() if p != old)
    assert (new / '.git/HEAD').read_text().strip() == second
    assert (old / 'Pinned.ax').read_text() == 'local changes must survive\n'
    run_answer(22)
    commit(33)
    assert 'present ' in cli('fetch').stdout
    assert (new / '.git/HEAD').read_text().strip() == second
    print('ok   changing a pin uses another cache; advancing a branch leaves the pin unchanged', flush=True)

    offline = work / 'offline-tools'
    offline.mkdir()
    marker = work / 'unexpected-git-call'
    shim = offline / 'git'
    shim.write_text('#!/bin/sh\nprintf called > "$AXIOM_TEST_GIT_MARKER"\nexit 97\n')
    shim.chmod(0o755)
    offline_env = dict(env, PATH=str(offline) + os.pathsep + env['PATH'],
                       AXIOM_TEST_GIT_MARKER=str(marker))
    cli('check', 'Main.ax', environment=offline_env)
    run_answer(22, offline_env)
    assert not marker.exists(), 'offline check/build invoked git'
    print('ok   checking and building a fetched pin do not invoke git', flush=True)

    (new / '.git/HEAD').write_text(first + '\n')
    assert 'pinned revision' in cli('check', 'Main.ax', expected=3).stderr
    assert 'pinned revision' in cli('fetch', expected=4).stderr
    assert (new / '.git/HEAD').read_text().strip() == first
    (new / '.git/HEAD').write_text(second + '\n')
    print('ok   a mismatched cached HEAD is refused without replacing it', flush=True)

    manifest('f' * 40)
    cli('fetch', expected=4)
    assert len(checkouts()) == 2
    assert not list((project / '.axiom/deps').glob('.fetch-*'))
    print('ok   an unavailable commit leaves no published or partial checkout', flush=True)

    git('tag', '-am', 'annotated package tag', 'package-tag')
    tag = git('rev-parse', 'refs/tags/package-tag')
    manifest(tag)
    assert 'pinned revision' in cli('fetch', expected=4).stderr
    assert len(checkouts()) == 2
    assert not list((project / '.axiom/deps').glob('.fetch-*'))
    print('ok   an annotated tag object is refused before publishing a checkout', flush=True)

    invalid = [
        'pin\n',
        f'pin {url} main\n',
        f'pin {url} {first.upper()}\n',
        f'pin {url} {first[:12]}\n',
        f'pin {url} {first}\npin {url} {second}\n',
        f'pin {url}/unknown {first}\n',
        f'pin vendor/local {first}\n',
    ]
    for line in invalid:
        (project / 'axiom.pkg').write_text(f'name pinned\ndepend {url}\n' + line)
        result = cli('check', 'Main.ax', expected=3)
        assert 'axiom.pkg:3' in result.stderr and 'pin' in result.stderr, result.stderr
    print('ok   malformed, duplicate, undeclared and non-URL pins identify their manifest line', flush=True)

    manifest(None)
    cli('fetch')
    run_answer(33)
    assert len(checkouts()) == 3
    print('ok   existing unpinned URL behavior stays available', flush=True)

    sha256 = work / 'sha256 repository'
    init = subprocess.run(['git', 'init', '-q', '--object-format=sha256', str(sha256)],
                          env=env, capture_output=True, text=True, timeout=30)
    if init.returncode == 0:
        repo = sha256
        git('config', 'user.name', 'Axiom package test')
        git('config', 'user.email', 'package-test@example.invalid')
        revision = commit(44)
        assert len(revision) == 64, revision
        url = repo.as_uri()
        manifest(revision)
        cli('fetch')
        cached = next(p for p in checkouts() if p not in (old, new)
                      and (p / '.git/HEAD').read_text().strip() == revision)
        assert (cached / '.git/HEAD').read_text().strip() == revision
        run_answer(44)
        print('ok   full SHA-256 commit pins fetch and build', flush=True)
    else:
        print('skip SHA-256 repository: local Git does not support its object format', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compiler', type=Path)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='axiom-package-pins-') as folder:
        check(args.compiler.resolve(), args.root.resolve(), Path(folder))
    print('package-pins: exact revisions, isolated caches and offline verification passed')


if __name__ == '__main__':
    main()
