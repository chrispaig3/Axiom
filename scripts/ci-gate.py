#!/usr/bin/env python3
"""Reuse a successful CI gate only when its recorded inputs still match."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

SCHEMA = 3
MAX_AGE = 7 * 24 * 60 * 60
# The test roots input selection may prune. A root not listed here
# stays in every gate's inputs, so a new `tests/` directory is
# somebody's input everywhere until it is classified by adding it.
KNOWN_TEST_ROOTS = frozenset('agent axir axqlite bootstrap ci compat crypto ddc diagnostics docs embedded ffi fmt frontend fuzz litmus lsp mir net obfuscation parallel platform profile recover region repl replcomp selfhost stdlib tailpos testrunner tools wait'.split())
# Reviewed fixture boundaries. Compiler sources and shared helpers remain
# inputs. Unlisted gates and new test directories use the whole tree.
FIXTURES = {
    'check-axqlite.sh': {'axqlite'},
    'check-contracts.sh': {'diagnostics'},
    'check-crypto.sh': {'crypto'},
    'check-diagnostic-coverage.sh': {'diagnostics'},
    'check-diagnostics.sh': {'diagnostics', 'selfhost', 'stdlib'},
    'check-obfuscation.sh': {'obfuscation'},
    'check-render-selfhost.sh': {'diagnostics', 'selfhost'},
    'check-repl-selfhost.sh': {'repl'},
    'check-self-host.sh': {'selfhost'},
    'check-stdlib-selfhost.sh': {'selfhost', 'stdlib'},
    'check-tail-position.sh': {'tailpos'},
    'check-test-runner.sh': {'testrunner'},
    'check-vscode.sh': {'lsp'},
}
# Top-level areas a gate includes only when its sources name them.
# Everything else (core/, stdlib/, bootstrap/, scripts/, .github/ and
# loose root files) is always an input: the compiler under test is
# built from it, or a census over it is the gate. Prose - docs/ and
# the root Markdown pages - is one area of its own, so a wording fix
# reruns the gates that read documents and no others.
PRUNABLE_AREAS = ('examples', 'compat', 'editors', 'tree-sitter-axiom',
                  'pkg', 'web', 'assets')

# Artifact producers and cache/coverage audits always run.
ALWAYS_RUN = {'check-ci-coverage.sh', 'check-gate-lib.sh', 'check-macro-demand.sh',
              'check-ffi.sh', 'check-windows-hello.sh', 'check-bootstrap.sh',
              'check-poisoned-alloc.sh', 'check-seed-provenance.sh',
              'check-seed-lineage.sh', 'check-seed-supply-chain.sh',
              'check-reproducible.sh', 'check-replcomp.sh'}


def tracked_paths(root):
    result = subprocess.run(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                            cwd=root, check=True, stdout=subprocess.PIPE)
    return sorted(set(os.fsdecode(p) for p in result.stdout.split(b'\0') if p))


_SOURCE_CACHE = {}


def _stripped(path):
    """A script's text with comment lines dropped, read once per
    on-disk version (a gate run can rewrite a script between the
    fingerprint before a gate and the one after it)."""
    stamp = path.stat()
    key = (path, stamp.st_mtime_ns, stamp.st_size)
    if key not in _SOURCE_CACHE:
        _SOURCE_CACHE[key] = '\n'.join(
            line for line in path.read_text().splitlines()
            if not line.lstrip().startswith('#'))
    return _SOURCE_CACHE[key]


def gate_sources(root, gate):
    """(gate names, {name: source}) for a gate, the check scripts it
    calls and the `scripts/lib/` helpers they name, comments stripped.

    The helper closure is part of the gate for input purposes: a
    helper can name the fixtures, documents and version sites the
    gate itself never spells out (`scripts/lib/version-sites.sh` is
    the standing example). `scripts/lib/gate.sh` is the one helper
    left out. Every gate sources it, and what it reads - `core/`,
    `stdlib/`, the toolchain - is always an input anyway; counting
    its text as every gate's mention would prune nothing. A gate
    that *calls* `gate_prose_docs` still shows the call in its own
    source, which `input_paths` reads.

    None when a script names a callee or helper dynamically
    (`check-$x`, `lib/$x`), so the set cannot be known statically."""
    gates = {gate}
    sources = {}
    todo = [('scripts', gate)]
    seen = set()
    while todo:
        where, current = todo.pop()
        if (where, current) in seen:
            continue
        seen.add((where, current))
        path = root / where / current
        if not path.is_file():
            continue
        source = _stripped(path)
        # `lib/` wants a boundary before it: `stdlib/*.ax` is a glob
        # over the library, not a dynamic helper name.
        if (re.search(r'check-[$*{]', source)
                or re.search(r'(?<![A-Za-z0-9_-])lib/[$*{]', source)):
            return None
        sources[current if where == 'scripts' else f'lib/{current}'] = source
        for dependency in re.findall(r'check-[a-z0-9-]+\.sh', source):
            if dependency not in gates and (root / 'scripts' / dependency).is_file():
                gates.add(dependency)
                todo.append(('scripts', dependency))
        for helper in re.findall(r'(?<![A-Za-z0-9_-])(?:scripts/)?lib/([A-Za-z0-9_./-]+)', source):
            if helper == 'gate.sh':
                continue
            if (root / 'scripts/lib' / helper).is_file():
                todo.append(('scripts/lib', helper))
    return gates, sources


def _input_spec(root, gate, paths):
    """The paths whose bytes can change this gate's verdict.

    Selective for every gate, not only reviewed ones. A gate reaches
    its fixtures, documents and area files by naming them in its own
    source, a check script it calls, or a `scripts/lib/` helper, so
    an area none of those names cannot be its input:

    - `tests/<root>/` fixture trees, pruned root by root (a reviewed
      FIXTURES boundary wins when one is recorded, and test roots
      nobody has classified yet stay in every gate's inputs);
    - prose (`docs/` and the root Markdown pages), kept only for
      gates that name a document or ask `gate_prose_docs` for the
      list;
    - the PRUNABLE_AREAS trees, kept only for gates that name them;
    - other gates' scripts, kept only for the callees in the closure.

    Anything the scan cannot resolve statically keeps the whole
    tree: a dynamic callee, `tests/` with no literal root after it,
    the bare `tests` directory used as a path (`tar` of the whole
    tree, `os.walk("tests")`, a symlink to it), an unknown test
    root, or a `git` enumeration (`ls-files`, `grep`, `log`), which
    can see every tracked file whatever the gate spells out. The
    safe direction is always more input, never less: a gate pruned
    wrongly is a failure CI never reports.

    One boundary stays reviewed by hand: a fixture in one test root
    that another root's fixture imports. FIXTURES records the known
    cases, and the nightly full run catches a new one within a day.

    This one definition feeds both the reuse fingerprint and
    `ci-plan.py`'s change selection, so "rerun what changed" and
    "reuse what did not" cannot disagree.

    Returns None for the whole tree, else a spec `_spec_needed`
    applies to one path at a time. Selection needs the spec, not
    just the surviving file list: a deleted fixture is in no file
    list at the new tree, and the gate that read it must still run."""
    got = gate_sources(root, gate)
    if got is None:
        return None
    gates, sources = got
    joined = '\n'.join(sources.values())
    own = '\n'.join(s for n, s in sources.items() if not n.startswith('lib/'))
    # A root counts named with or without a path after it:
    # `tests/crypto/100-sha2.ax` and `"$repo_root/tests/crypto"` (the
    # directory itself, handed to `find` or a fixture variable) name
    # the same tree. `tests/` followed by anything else - `$x`, `*`,
    # a character class - names one the scan cannot know.
    mentioned = set(re.findall(r'tests/([a-zA-Z0-9_-]+)(?=/|[^A-Za-z0-9_-]|$)', joined))
    if re.search(r'tests/(?![a-zA-Z0-9_-]+(?:/|[^A-Za-z0-9_-]|$))', joined):
        return None
    # The bare tests directory as a path, once every literal root is
    # scrubbed out: `tar -cf - stdlib core tests`, `os.walk("tests")`,
    # `ln -s "$repo_root/tests"`. The same word is also a verb in
    # gate messages ("so it tests nothing"), which reads no fixture,
    # so a bare mention counts only in a path-bearing position: a
    # quoted name, a final path component, an assignment value, a
    # loop list, or a line that drives a filesystem command.
    # Variables (`$tests`, `${tests[@]}`) and longer words
    # (`run-stdlib-tests`) are not the directory either way.
    scrubbed = re.sub(r'tests/[a-zA-Z0-9_-]+(?=/|[^A-Za-z0-9_-]|$)', 'TESTSROOT', joined)
    bare = re.compile(r'(?<![A-Za-z0-9_${-])tests(?![A-Za-z0-9_-])')
    for line in scrubbed.splitlines():
        if bare.search(line) and (
                re.search(r'["\']tests["\']|/tests(?![A-Za-z0-9_-])'
                          r'|=\s*tests(?![A-Za-z0-9_-])|\bin\s+tests(?![A-Za-z0-9_-])',
                          line)
                or re.search(r'\b(?:tar|find|cp|mv|ln|ls|rm|mkdir|cat|cd'
                             r'|walk|glob|scandir|listdir)\b', line)):
            return None
    # A git enumeration reads the tracked tree, not the paths the
    # gate happens to spell. Which files exist is then an input.
    if re.search(r'(?:^|[\s;|&(`])git\s+(?:-\S+\s+)*(?:ls-files|grep|log|archive|show)\b',
                 joined, re.M):
        return None
    if not mentioned <= KNOWN_TEST_ROOTS:
        return None
    reviewed = FIXTURES.get(gate)
    # A new reference outside the reviewed boundary disables selective reuse.
    if reviewed is not None and not mentioned <= reviewed:
        return None
    selected = reviewed if reviewed is not None else mentioned

    root_pages = {p for p in paths if '/' not in p and p.endswith('.md')}
    sweeps_prose = 'gate_prose_docs' in own
    # Prose splits in two, because the common mixed change edits one
    # side only: a README wording fix must not rerun every gate that
    # reads the reference, nor the reverse. `gate_prose_docs` lists
    # both sides (and bootstrap's pages, counted with docs/), so a
    # sweep over it keeps everything.
    prose_docs = (
        sweeps_prose
        or 'docs/' in joined
        or re.search(r'(?<![A-Za-z0-9_${-])docs(?![A-Za-z0-9_-])', joined) is not None
    )
    prose_root = sweeps_prose or any(page in joined for page in root_pages)
    areas = {
        area: (f'{area}/' in joined
               or re.search(rf'(?<![A-Za-z0-9_$/.-]){re.escape(area)}(?![A-Za-z0-9_-])',
                            joined) is not None)
        for area in PRUNABLE_AREAS
    }
    # Named callees count even when the file is gone: deleting a
    # script a gate calls must still select the caller.
    named = gates | set(re.findall(r'check-[a-z0-9-]+\.sh', joined))
    return {'gates': named, 'roots': selected, 'prose_docs': prose_docs,
            'prose_root': prose_root, 'areas': areas}


def _spec_needed(spec, p):
    """Whether one path - present, deleted or renamed away - can
    change the verdict of the gate `spec` describes."""
    if p.startswith('scripts/check-') and p.endswith('.sh'):
        return Path(p).name in spec['gates']
    parts = p.split('/')
    if parts[0] == 'tests':
        if len(parts) < 3:
            return True
        return parts[1] not in KNOWN_TEST_ROOTS or parts[1] in spec['roots']
    if parts[0] == 'docs' or (parts[0] == 'bootstrap' and p.endswith('.md')):
        return spec['prose_docs']
    if len(parts) == 1:
        return spec['prose_root'] if (p.endswith('.md') or p == 'LICENSE') else True
    if parts[0] in spec['areas']:
        return spec['areas'][parts[0]]
    return True


def input_paths(root, gate):
    """The tracked paths whose bytes can change this gate's verdict
    (`_input_spec` gives the rule and its fallbacks)."""
    paths = tracked_paths(root)
    spec = _input_spec(root, gate, paths)
    if spec is None:
        return paths
    return [p for p in paths if _spec_needed(spec, p)]


def touches_gate(root, gate, changed):
    """Whether any path in a change set can change this gate's
    verdict. Change sets name deleted and renamed-away paths too,
    which `input_paths` at the new tree no longer lists, so
    selection asks the spec path by path instead of intersecting
    file lists."""
    spec = _input_spec(root, gate, tracked_paths(root))
    if spec is None:
        return True
    return any(_spec_needed(spec, p) for p in changed)


def uses_git(root, gate):
    """Whether the gate, a check script it calls, or a helper invokes
    git as a command, so its verdict can depend on history or the
    index rather than source bytes alone. When the callee set is
    unknowable, assume yes.

    The scan reads comment-stripped sources and wants `git` in
    command position (or as a subprocess argv head). The English
    word must not count: `gate.sh` once mentioned a tree "extracted
    from git at another commit" in a comment, and counting it made
    every gate history-dependent, so no pass ever survived a new
    commit and reuse never happened across pushes."""
    got = gate_sources(root, gate)
    if got is None:
        return True
    joined = '\n'.join(got[1].values())
    return (
        re.search(r'(?:^|[\s;|&(`])git\s', joined, re.M) is not None
        or re.search(r"""['"]git['"]\s*,""", joined) is not None
    )


def add(h, label, data):
    label = os.fsencode(label)
    h.update(len(label).to_bytes(8, 'big') + label)
    h.update(len(data).to_bytes(8, 'big') + data)


def file_hash(h, root, name):
    p = root / name
    if p.is_symlink():
        add(h, name + ':link', os.fsencode(os.readlink(p)))
    if p.is_file():
        add(h, name + ':mode', str(p.stat().st_mode & 0o777).encode())
        add(h, name, p.read_bytes())
    else:
        add(h, name, b'<missing>')


def tool_context():
    result = {'platform': [platform.system(), platform.machine(), platform.release()],
              'image': [os.environ.get('ImageOS'), os.environ.get('ImageVersion')],
              'tools': {}}
    for tool in ('opt', 'llc', 'llvm-extract', 'llvm-readobj', 'llvm-objdump',
                 'llvm-nm', 'cc', 'clang', 'ld.lld', 'lld-link', 'ar', 'nm',
                 'python3', 'node', 'npm', 'cargo', 'rustc', 'rustfmt'):
        path = shutil.which(tool)
        if path is None:
            result['tools'][tool] = None
            continue
        r = subprocess.run([path, '--version'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=15)
        result['tools'][tool] = [str(Path(path).resolve()), r.returncode,
                                 r.stdout.decode('utf-8', errors='replace'),
                                 hashlib.sha256(Path(path).resolve().read_bytes()).hexdigest()]
    for path in ('tree-sitter-axiom/node_modules/tree-sitter-cli/tree-sitter',):
        p = Path(__file__).resolve().parent.parent / path
        result['tools'][path] = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
    return result


def fingerprint(root, gate, args, context):
    h = hashlib.sha256()
    add(h, 'schema', str(SCHEMA).encode())
    add(h, 'command', json.dumps([gate, *args]).encode())
    add(h, 'toolchain', json.dumps(context, sort_keys=True).encode())
    env = {k: v for k, v in os.environ.items()
           if (k.startswith(('AXIOM_', 'RUST', 'CARGO_', 'LLVM', 'LC_')) or
               k in ('LANG', 'CC', 'CXX', 'CI')) and
           k not in ('AXIOM_CI_CACHE', 'AXIOM_CI_FRESH')}
    # Gate-specific switches such as SELF_TEST also affect the verdict.
    source = (root / 'scripts' / gate).read_text()
    helper = root / 'scripts/lib/gate.sh'
    if helper.is_file():
        source += helper.read_text()
    names = set(re.findall(r'\$\{?([A-Z_][A-Z0-9_]*)', source))
    for name in names - {'AXIOM_CI_CACHE', 'AXIOM_CI_FRESH'}:
        env[name] = os.environ.get(name)
    add(h, 'environment', json.dumps(env, sort_keys=True).encode())
    if uses_git(root, gate):
        # A gate that invokes git can inspect history, not just source
        # bytes. One that never does cannot observe HEAD, so a new
        # commit alone must not invalidate its recorded pass - that
        # single inclusion used to defeat reuse for nearly every gate.
        for args in (['rev-parse', 'HEAD'], ['ls-files', '--stage']):
            r = subprocess.run(['git', *args], cwd=root, check=True, stdout=subprocess.PIPE)
            add(h, 'git:' + ' '.join(args), r.stdout)
    for p in input_paths(root, gate):
        file_hash(h, root, p)
    for p in sorted({'.axiom-bin/axiom', '.axiom-shared/axc',
                     os.environ.get('AXIOM') or '.axiom-bin/axiom',
                     os.environ.get('AXIOM_AXC') or '.axiom-shared/axc'}):
        file_hash(h, root, p)
    return h.hexdigest()


def valid_record(path, key, gate, now):
    try:
        r = json.loads(path.read_text())
        return (r['schema'] == SCHEMA and r['key'] == key and r['gate'] == gate and
                r['result'] == 'passed' and
                re.fullmatch(r'[0-9]+', str(r['run_id'])) is not None and
                re.fullmatch(r'[0-9a-f]{40}', r['sha']) is not None and
                0 <= now - r['completed_at'] < MAX_AGE)
    except (OSError, ValueError, TypeError, KeyError):
        return False


def run(root, command):
    gate = Path(command[0]).name
    cache = os.environ.get('AXIOM_CI_CACHE')
    if not cache or gate in ALWAYS_RUN:
        return subprocess.run(command, cwd=root).returncode
    try:
        context = tool_context()
        key = fingerprint(root, gate, command[1:], context)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        print(f'ci: cannot identify inputs; running {gate}: {e}', flush=True)
        return subprocess.run(command, cwd=root).returncode
    record = Path(cache) / f'{key}.json'
    if os.environ.get('AXIOM_CI_FRESH') != '1' and valid_record(record, key, gate, time.time()):
        proof = json.loads(record.read_text())
        message = f"Reused {gate}: unchanged inputs; passed in run {proof['run_id']} at {proof['sha'][:12]}."
        print(message, flush=True)
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as out:
                out.write(message + '\n\n')
        return 0
    # An expired/corrupt success cannot survive a subsequent failure.
    try:
        record.unlink(missing_ok=True)
    except OSError as e:
        print(f'ci: cannot update cached result; running {gate}: {e}', flush=True)
        return subprocess.run(command, cwd=root).returncode
    rc = subprocess.run(command, cwd=root).returncode
    try:
        # A gate that leaves its inputs changed earns no reusable record.
        if rc == 0 and fingerprint(root, gate, command[1:], context) != key:
            print(f'ci: {gate} changed its inputs; success will run again', flush=True)
            return 0
        record.parent.mkdir(parents=True, exist_ok=True)
        proof = dict(schema=SCHEMA, key=key, gate=gate, result='passed' if rc == 0 else 'failed',
                     sha=os.environ.get('GITHUB_SHA', ''),
                     run_id=os.environ.get('GITHUB_RUN_ID', 'local'), completed_at=time.time())
        with tempfile.NamedTemporaryFile('w', dir=record.parent, delete=False) as out:
            json.dump(proof, out)
        os.replace(out.name, record)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        print(f'ci: {gate} finished but its result could not be saved: {e}', flush=True)
    return rc


if __name__ == '__main__':
    if len(sys.argv) < 2 or not re.fullmatch(r'\./scripts/check-[a-z0-9-]+\.sh', sys.argv[1]):
        sys.exit('usage: ci-gate.py ./scripts/check-NAME.sh [args]')
    root = Path(__file__).resolve().parent.parent
    rc = run(root, sys.argv[1:])
    sys.exit(rc if rc >= 0 else 128 - rc)
