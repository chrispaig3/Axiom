#!/usr/bin/env python3
"""Save the exact native build inputs beside a release compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ('opt', 'llc', 'clang', 'cc', 'ld.lld', 'lld-link', 'llvm-ar', 'llvm-readobj')
OPTIONAL_TOOLS = ('llvm-split',)
ENVIRONMENT = ('SDKROOT', 'MACOSX_DEPLOYMENT_TARGET', 'DEVELOPER_DIR', 'CFLAGS', 'LDFLAGS',
               'AXIOM_STDLIB', 'AXIOM_PATH', 'AXIOM_LINK_SEARCH',
               'AXIOM_FRONTEND_JOBS', 'AXIOM_CODEGEN_JOBS')
SUPPORTED = ('linux-aarch64', 'darwin-aarch64')
RECIPES = ('VERSION', 'scripts/bootstrap-from-seed.sh', 'scripts/build-stamped.sh',
           'scripts/lib/gate.sh', 'scripts/lib/seed-toolchain.sh', 'scripts/lib/imports.sh',
           'scripts/record-toolchain.py', '.github/actions/provision/action.yml',
           '.github/workflows/release.yml')


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def command(argv, cwd=None):
    result = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors='replace', timeout=30)
    return result.returncode, result.stdout.strip()


def checked(argv, cwd=None):
    status, output = command(argv, cwd)
    if status or not output:
        raise ValueError(f'command failed ({status}): {argv[0]}: {output}')
    return output


def tool_record(name, arguments=('--version',), allow_status=(), optional=False):
    found = shutil.which(name)
    if found is None:
        if optional:
            return None
        raise ValueError(f'missing native tool: {name}')
    path = Path(found).resolve(strict=True)
    # lld selects its driver from argv[0]; resolving the symlink before
    # executing it would turn ld.lld or lld-link into the generic driver.
    invocation = str(Path(found).absolute())
    status, version = command([invocation, *arguments])
    if (status and status not in allow_status) or not version:
        raise ValueError(f'version probe failed for {name}: {status}: {version}')
    return {'path': str(path), 'invocation': invocation, 'sha256': digest(path), 'version': version,
            'version_status': status}


def host_target():
    system = {'Linux': 'linux', 'Darwin': 'darwin'}.get(platform.system())
    machine = {'aarch64': 'aarch64', 'arm64': 'aarch64', 'x86_64': 'x86_64'}.get(platform.machine())
    if not system or not machine:
        raise ValueError(f'unsupported native host: {platform.system()} {platform.machine()}')
    return f'{system}-{machine}'


def source_digest(root):
    # Keep build-stamped.sh / gate_seed_source_stamp's historical spelling.
    files = sorted(path.relative_to(root).as_posix() for folder in ('core', 'stdlib')
                   for path in (root / folder).rglob('*.ax') if path.is_file() and not path.is_symlink())
    if not files:
        raise ValueError('no compiler or library sources')
    value = hashlib.sha256()
    value.update(('\n'.join(name.replace('core/', 'self_host/', 1) if name.startswith('core/')
                            else name for name in files) + '\n').encode())
    for name in files:
        value.update((root / name).read_bytes())
    return value.hexdigest()


def create(root, target, compiler, release=False):
    if target not in SUPPORTED or target != host_target():
        raise ValueError(f'target {target} does not name a supported native host ({host_target()})')
    revision = checked(['git', 'rev-parse', 'HEAD'], root)
    status, dirty = command(['git', 'status', '--porcelain', '--untracked-files=all'], root)
    if status:
        raise ValueError('could not inspect source changes')
    if release and dirty:
        raise ValueError('release records require a clean checkout')
    source = source_digest(root)
    version = checked([str(compiler.resolve()), 'version'])
    if release:
        short = checked(['git', 'rev-parse', '--short=12', 'HEAD'], root)
        expected = f'(build {source[:12]} {short})'
        if expected not in version:
            raise ValueError(f'compiler does not report the source build stamp: expected {expected}')
    tools = {name: tool_record(name) for name in TOOLS}
    tools.update({name: tool_record(name, optional=True) for name in OPTIONAL_TOOLS})
    linker = checked(['cc', '-print-prog-name=ld'])
    tools['native-linker'] = tool_record(linker, ('-v',) if target.startswith('darwin-')
                                       else ('--version',), (1,) if target.startswith('darwin-') else ())
    host = {'system': platform.system(), 'machine': platform.machine(),
            'release': platform.release(), 'version': platform.version(),
            'runner_image': {key: os.environ.get(key) for key in ('ImageOS', 'ImageVersion')}}
    if target.startswith('darwin-'):
        sdk = Path(checked(['xcrun', '--show-sdk-path']))
        host['sdk'] = {'path': str(sdk), 'version': checked(['xcrun', '--show-sdk-version']),
                       'settings_sha256': digest(sdk / 'SDKSettings.json')}
        host['developer_directory'] = checked(['xcode-select', '-p'])
    else:
        host['os_release'] = Path('/etc/os-release').read_text()
        # Exact installed package versions include the toolchain's shared libraries.
        host['packages'] = checked(['dpkg-query', '-W', '-f=${binary:Package}\t${Version}\n'])
    inputs = {name: digest(root / name) for name in RECIPES}
    seed = f'bootstrap/axiom-{target}.ll'
    inputs[seed] = digest(root / seed)
    return {'schema': 1, 'target': target, 'host': host, 'tools': tools,
            'source': {'revision': revision, 'dirty': bool(dirty), 'sha256': source,
                       'recipe_and_seed_sha256': inputs},
            'compiler': {'sha256': digest(compiler), 'version': version},
            'environment': {key: os.environ.get(key) for key in ENVIRONMENT}}


def verify(document, compiler, target):
    if document.get('schema') != 1:
        raise ValueError('unsupported toolchain record schema')
    if document.get('target') not in SUPPORTED or document['target'] != target:
        raise ValueError('toolchain record target mismatch')
    if document.get('compiler', {}).get('sha256') != digest(compiler):
        raise ValueError('toolchain record compiler digest mismatch')
    tools = document.get('tools', {})
    for name in (*TOOLS, *OPTIONAL_TOOLS, 'native-linker'):
        if name in OPTIONAL_TOOLS and name in tools and tools[name] is None:
            continue
        tool = tools.get(name, {})
        if not tool.get('version') or not re.fullmatch('[0-9a-f]{64}', tool.get('sha256', '')):
            raise ValueError(f'toolchain record lacks an exact version and digest for {name}')
    if not set(ENVIRONMENT) <= document.get('environment', {}).keys():
        raise ValueError('toolchain record lacks build environment settings')
    source = document.get('source', {})
    if not re.fullmatch('[0-9a-f]{40}', source.get('revision', '')) or not re.fullmatch(
            '[0-9a-f]{64}', source.get('sha256', '')):
        raise ValueError('toolchain record lacks source identity')
    inputs = source.get('recipe_and_seed_sha256', {})
    for name in (*RECIPES, f'bootstrap/axiom-{target}.ll'):
        if not re.fullmatch('[0-9a-f]{64}', inputs.get(name, '')):
            raise ValueError(f'toolchain record lacks build input: {name}')
    host = document.get('host', {})
    if target.startswith('darwin-'):
        if not host.get('sdk', {}).get('version') or not re.fullmatch(
                '[0-9a-f]{64}', host.get('sdk', {}).get('settings_sha256', '')):
            raise ValueError('toolchain record lacks the native SDK')
    elif not host.get('os_release') or not host.get('packages'):
        raise ValueError('toolchain record lacks the native package versions')


def save(path, document):
    data = json.dumps(document, indent=2, sort_keys=True) + '\n'
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix=f'.{path.name}.', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=SUPPORTED)
    parser.add_argument('--compiler', required=True, type=Path)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--output', type=Path)
    action.add_argument('--verify', type=Path)
    parser.add_argument('--release', action='store_true', help='require a clean tree and matching build stamp')
    args = parser.parse_args()
    try:
        if args.verify:
            verify(json.loads(args.verify.read_text()), args.compiler, args.target)
            print(f'Verified toolchain record for {args.target}')
        else:
            document = create(ROOT, args.target, args.compiler, args.release)
            verify(document, args.compiler, args.target)
            save(args.output, document)
            print(f'Saved toolchain record for {args.target}: {args.output}')
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'toolchain record: {error}\n')


if __name__ == '__main__':
    main()
