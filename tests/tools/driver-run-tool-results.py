#!/usr/bin/env python3
"""Check synchronous tool Results and their complete driver/fetch/REPL policies."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile

replace_once = runpy.run_path(str(Path(__file__).parents[1] / 'selfhost/emitter-line-buffer.py'))['replace_once']


def bridges(legacy):
    def wrapper(name, params, types, call):
        result = ('{ (let code ' + call + ') (if (< code 0) (Err (- 0 code)) (Ok code)) }') if legacy else ('(match ' + call + ' ((Ok code) (Ok code)) ((Err error) (Err (Err::errCode error))))')
        return f'\n(pub :: {name} (-> {types} (Result Int Int)))\n;@axiom:effect(io)\n;@axiom:effect(spawn)\n;@axiom:effect(block)\n(pub fn ({name} {params}) {result})\n'
    driver = ''.join(wrapper(*args) for args in (
        ('probeRunTool', 'tool args', 'String Strings', '(runTool tool args)'),
        ('probeRunQuiet', 'tool args', 'String Strings', '(runToolQuiet tool args)'),
        ('probeRunErrTo', 'tool args path', 'String Strings String', '(runToolErrTo tool args path)'),
        ('probeBindings', 'dir stem module', 'String String String', '(refreshBindings dir stem module)'),
        ('probeCrate', 'dir pkg', 'String String', '(buildCrate dir pkg)'),
    ))
    main = ''.join(wrapper(*args) for args in (
        ('probeFetchClone', 'url dest', 'String String', '(fetchClone url dest)'),
        ('probeFetchDiscard', 'path', 'String', '(fetchDiscard path)'),
    ))
    return {'driver.ax': driver, 'main.ax': main}


def check(compiler, root, work, baseline, fetch_only=False):
    system = platform.system()
    if system not in ('Darwin', 'Linux', 'FreeBSD'):
        (work / 'report.json').write_text(json.dumps({'status': 'skipped', 'host': system,
            'reason': 'POSIX signal and REPL shell probes require separate Windows native coverage.',
            'configurations': [], 'controls': [], 'refusals': []}, indent=2) + '\n')
        print('skip synchronous tool probes on ' + system, flush=True)
        return
    source_root = baseline or root
    source = {name: (source_root / 'core' / name).read_text() for name in ('driver.ax', 'main.ax', 'repl.ax')}
    hashes = {str(path.relative_to(source_root)): hashlib.sha256(path.read_bytes()).hexdigest()
              for folder in ('core', 'stdlib') for path in sorted((source_root / folder).rglob('*.ax'))}
    builder_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
    report = {'host': system, 'builder_sha256': builder_hash, 'source_sha256': hashes,
              'baseline': bool(baseline), 'fetch_only': fetch_only, 'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Native host O0/O2 with allocation poisoning; no Windows execution claim.',
                         'Sys launch/wait/redirection contracts are trusted and unchanged; Ok uses numeric exit and 128+signal ABI.',
                         'Crate preparation, rustfmt and fetch cleanup retain their existing best-effort policies.',
                         'REPL OS-error wording still mentions a signal; error classification wording is a pre-existing limitation.',
                         'No held ownership, inference or call-emission work is reviewed or validated.']}
    additions = bridges(bool(baseline))
    def modules(label, changed=None):
        folder = work / (label + '-core'); folder.mkdir()
        for path in (source_root / 'core').iterdir():
            target = folder / path.name
            if path.name in source:
                text = (changed or source).get(path.name, source[path.name])
                if path.name == 'main.ax':
                    text = '(import Err (errCode))\n' + text
                target.write_text(text + additions.get(path.name, ''))
            else:
                target.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(source_root / 'stdlib'))
    def build(label, fixture, env, level):
        binary = work / label
        ran = subprocess.run([str(compiler), '--diagnostic-format=ai', 'build', str(fixture),
            '--opt', str(level), '--alloc-poison', '-o', str(binary)], env=env, capture_output=True, timeout=240)
        (work / (label + '.build.stderr')).write_bytes(ran.stderr)
        if ran.returncode or any(line.startswith((b'E ', b'W ')) for line in ran.stderr.splitlines()):
            raise AssertionError((label, ran.returncode, ran.stderr.decode()))
        return binary
    def argv(*args):
        return ''.join(f'{i}:{arg}\n' for i, arg in enumerate(args)).encode()
    def exercise(label, binary, env, child, restricted=None):
        data = work / (label + '-cases'); data.mkdir()
        cases = []
        def add(name, args, tool='native', mode='ok', omitted=None, stdout=b'ok 0\n', stderr=b'', code=0, log=None):
            cases.append((name,args,tool,mode,omitted,stdout,stderr,code,log))
        literal = ('', 'space value', '$(touch forbidden);*')
        add('zero',('run','native'),log=argv('native',*literal))
        add('nonzero',('run','native'),mode='fail7',stdout=b'ok 7\n',log=argv('native',*literal))
        add('exit127',('run','native'),mode='fail127',stdout=b'ok 127\n',log=argv('native',*literal))
        add('signal',('run','native'),mode='signal9',stdout=b'ok 137\n',log=argv('native',*literal))
        add('missing',('run','native'),omitted='native',stdout=b'err 2\n',log=b'')
        add('direct-missing',('run','./absent'),stdout=b'err 2\n',log=b'')
        add('quiet-text',('quiet','native'),mode='text',stdout=b'child stdout\nok 0\n',stderr=b'child stderr\n',log=argv('native','--quiet','','literal;*'))
        add('redirect-text',('redirect','native','captured.err'),mode='text',stdout=b'child stdout\nok 0\n',log=argv('native'))
        add('redirect-failed',('redirect','native','captured.err'),mode='fail7',stdout=b'ok 7\n',log=argv('native'))
        add('redirect-unwritable',('redirect','native','missing/err'),stdout=b'err 2\n',log=b'')
        bindcheck=argv('axiom-bindgen','--src','crate/src','--lib','demo','--module','Demo','--check','crate/axiom/Demo.ax','--quiet')
        bindgen=argv('axiom-bindgen','--src','crate/src','--lib','demo','--module','Demo','-o','crate/axiom')
        bindnote=b'axiom: regenerating crate/axiom/Demo.ax with axiom-bindgen\n'
        add('bindings-current',('bindings',),tool='axiom-bindgen',log=bindcheck)
        add('bindings-missing',('bindings',),omitted='axiom-bindgen',log=b'')
        add('bindings-stale',('bindings',),tool='axiom-bindgen',mode='stale',stderr=bindnote,log=bindcheck+bindgen)
        add('bindings-failed',('bindings',),tool='axiom-bindgen',mode='genfail',stdout=b'ok 19\n',stderr=bindnote,log=bindcheck+bindgen)
        cargolog=argv('cargo','build','--release','--manifest-path','crate/Cargo.toml')
        cargonote=b'axiom: building crate `demo` with cargo (no archive found)\n'
        add('crate-success',('crate',),tool='cargo',stderr=cargonote,log=cargolog)
        add('crate-failed',('crate',),tool='cargo',mode='fail7',stdout=b'ok 7\n',stderr=cargonote,log=cargolog)
        add('crate-missing',('crate',),omitted='cargo',stdout=b'err 2\n',stderr=cargonote,log=b'')
        add('prepare-best-effort',('prepare',),tool='cargo',mode='fail7',stdout=b'status 0\n',stderr=cargonote,log=bindcheck+cargolog)
        add('clone-success',('clone',),tool='git',log=argv('git','clone','url;literal','clone dest'))
        add('clone-failed',('clone',),tool='git',mode='fail7',stdout=b'ok 7\n',log=argv('git','clone','url;literal','clone dest'))
        add('clone-missing',('clone',),omitted='git',stdout=b'err 2\n',log=b'')
        add('clone-exit127',('clone',),tool='git',mode='fail127',stdout=b'ok 127\n',log=argv('git','clone','url;literal','clone dest'))
        add('discard-absent',('discard',),log=b'')
        add('discard-present',('discard',),tool='rm',log=argv('rm','-rf','clone dest'))
        add('discard-missing',('discard',),omitted='rm',stdout=b'err 2\n',log=b'')
        for target, linker in (('native','cc'),('windows','lld-link'),('baremetal','ld.lld'),('archive','ar')):
            for kind in ('success','failed','missing'):
                add('assemble-'+target+'-'+kind,('assemble',target,*(['--emit-staticlib'] if target=='archive' else [])),
                    tool=linker,mode='fail7' if kind=='failed' else 'ok',omitted=linker if kind=='missing' else None,
                    stdout=b'status 0\n' if kind=='success' else b'status 4\n',stderr=None)
        for kind in ('failed','missing'):
            add('assemble-llc-'+kind,('assemble','native'),tool='llc',mode='fail7',omitted='llc' if kind=='missing' else None,stdout=b'status 4\n',stderr=None)
        for kind in ('success','failed','missing'):
            add('implib-'+kind,('implib',),tool='llvm-dlltool',mode='fail7' if kind=='failed' else 'ok',omitted='llvm-dlltool' if kind=='missing' else None,stdout=None)
        for kind in ('success','failed','missing'):
            add('fetch-'+kind,('fetch',),tool='git',mode='fail7' if kind=='failed' else 'ok',omitted='git' if kind=='missing' else None,stdout=None,stderr=None,code=0 if kind=='success' else 4)
        add('fetch-cleanup-missing',('fetch',),tool='git',mode='fail7',omitted='rm',stdout=None,stderr=None,code=4)
        add('fetch-rename-failed',('fetch',),tool='git',stdout=None,stderr=None,code=4)
        for tool in ('llc','cc'):
            for kind in ('failed','missing'):
                add('repl-'+tool+'-'+kind,('repl',),tool=tool,mode='fail7',omitted=tool if kind=='missing' else None,
                    stdout=b'Error: llc rejected the generated code\n' if tool=='llc' else b'Error: linking failed\n')
        for name,mode,stdout in (
            ('repl-value','repl-text',b'result value from child\n'),
            ('repl-exit','repl-exit',b'result 7\n'),
            ('repl-signal','repl-signal',b'result 137\n')):
            add(name,('repl',),tool='cc',mode=mode,stdout=stdout)
        outcomes={}
        for name,args,tool,mode,omitted,stdout,stderr,code,expected_log in cases:
            if restricted and name not in restricted: continue
            if fetch_only and not name.startswith(('clone-', 'discard-', 'fetch-')): continue
            folder=data/name; folder.mkdir(); tools=folder/'bin';tools.mkdir()
            for toolname in ('native','llc','cc','ar','ld.lld','lld-link','llvm-dlltool','axiom-bindgen','cargo','git','rm'):
                if toolname!=omitted: shutil.copy2(child,tools/toolname)
            (folder/'crate/src').mkdir(parents=True);(folder/'crate/axiom').mkdir()
            (folder/'crate/Cargo.toml').write_text('[package]\nname = "demo"\n')
            (folder/'input.ll').write_text('; input\n')
            (folder/'project').mkdir(); (folder/'scratch').mkdir()
            if name=='fetch-rename-failed':
                deps=folder/'project/.axiom/deps';deps.mkdir(parents=True)
                key='example.invalid-repo-'+hashlib.sha256(b'https://example.invalid/repo').hexdigest()[:32]
                (deps/key).write_text('occupied\n')
            if name in ('discard-present','discard-missing'):
                (folder/'clone dest').mkdir();(folder/'clone dest/partial').write_text('partial\n')
            local=dict(env,PATH=str(tools),TMPDIR=str(folder/'scratch'),AXIOM_TEST_RUN_MODE=mode,
                AXIOM_TEST_RUN_TOOL=tool,AXIOM_TEST_LOG=str(folder),AXIOM_TEST_CHILD=str(child),AXIOM_CODEGEN_JOBS='1')
            ran=subprocess.run([str(binary),*args,'--diagnostic-format=ai'],cwd=folder,env=local,capture_output=True,timeout=45)
            (folder/'observed.stdout').write_bytes(ran.stdout);(folder/'observed.stderr').write_bytes(ran.stderr)
            log=(folder/'tools.log').read_bytes() if (folder/'tools.log').exists() else b''
            bad=[]
            if ran.returncode!=code: bad.append('status')
            if stdout is not None and ran.stdout!=stdout: bad.append('stdout')
            if stderr is not None and ran.stderr!=stderr: bad.append('stderr')
            if expected_log is not None and log!=expected_log: bad.append('argv')
            if (folder/'forbidden').exists(): bad.append('shell-expansion')
            if name=='redirect-text' and (folder/'captured.err').read_bytes()!=b'child stderr\n': bad.append('redirected-stderr')
            if name.startswith('assemble-'):
                failed=name.endswith(('failed','missing'))
                wanted=('could not run `'+tool+'`') if omitted else (tool+' failed')
                if failed and (b'E AX4003 ' not in ran.stderr or ('"'+wanted+'"').encode() not in ran.stderr):bad.append('diagnostic')
                if not failed and ran.stderr:bad.append('unexpected-diagnostic')
                if tool=='llc' and any(x in log for x in (b'0:cc\n',b'0:ar\n',b'0:ld.lld\n',b'0:lld-link\n')):bad.append('linked-after-failure')
                if (folder/'output.ld').exists():bad.append('linker-script-cleanup')
            if name.startswith('implib-'):
                expected=(b'ok output.o.kernel32.lib\n' if name.endswith('success') else
                    b'err could not run `llvm-dlltool`, which makes the import libraries; it ships with LLVM - put it on PATH, or put a `kernel32.lib` on a `--link-search` directory\n' if omitted else
                    b'err llvm-dlltool failed to make the kernel32 import library\n')
                if ran.stdout!=expected:bad.append('implib-result')
                if (folder/'output.o.kernel32.def').exists():bad.append('def-cleanup')
            if name.startswith('fetch-'):
                if not ran.stdout.startswith(b'fetching project/.axiom/deps/'):bad.append('fetch-progress')
                if omitted=='git':
                    if ran.stderr!=b'error: `git` was not found on PATH; install git and try again\n':bad.append('fetch-missing')
                elif mode=='fail7':
                    if ran.stderr!=b'error: cloning `https://example.invalid/repo` failed (git exited 7); nothing was checked out\n':bad.append('fetch-failure')
                elif name=='fetch-rename-failed':
                    expected=('error: the clone finished but could not be moved to `project/.axiom/deps/'+key+'/`\n').encode()
                    if ran.stderr!=expected:bad.append('fetch-rename-failure')
                    if (deps/key).read_text()!='occupied\n':bad.append('existing-file-changed')
                elif ran.stderr or not ran.stdout.endswith(b'status 0\n'):bad.append('fetch-success')
                left=list((folder/'project/.axiom/deps').glob('.fetch-*'))
                if name=='fetch-cleanup-missing':
                    if len(left)!=1 or not (left[0]/'partial').exists():bad.append('best-effort-cleanup')
                elif left:bad.append('temporary-clone-cleanup')
            if name.startswith('repl-') and list((folder/'scratch').iterdir()):bad.append('repl-cleanup')
            if name=='discard-present' and (folder/'clone dest').exists():bad.append('discard-cleanup')
            if name=='discard-missing' and not (folder/'clone dest/partial').exists():bad.append('missing-rm-changed-files')
            def normal(data):
                text=data.decode().replace(str(folder),'<CASE>')
                text=re.sub(r'axiom-repl-\d+\.d','axiom-repl-<PID>.d',text)
                text=re.sub(r'(\.fetch-[^/\n]*-)\d+',r'\1<PID>',text)
                return text
            files={str(p.relative_to(folder)):p.read_text() for p in folder.rglob('*') if p.is_file() and not any(part in ('bin',) for part in p.relative_to(folder).parts) and p.name not in ('observed.stdout','observed.stderr','tools.log')}
            outcomes[name]={'passed':not bad,'mismatches':bad,'exit':ran.returncode,'stdout':normal(ran.stdout),'stderr':normal(ran.stderr),'argv':normal(log),'files':files}
            if bad and not restricted:raise AssertionError((label,name,bad,ran.returncode,ran.stdout,ran.stderr,log))
        return outcomes
    env=modules('positive')
    for level in (0,2):
        child=build('child-O'+str(level),root/'tests/tools/driver-run-tool-child.axp',env,level)
        binary=build('results-O'+str(level),root/'tests/tools/driver-run-tool-results.axp',env,level)
        outcomes=exercise('results-O'+str(level),binary,env,child)
        report['configurations'].append({'optimization':level,'allocation_poisoning':True,'cases':outcomes})
        print(f'ok synchronous tool results: {len(outcomes)} policy/argv/output/cleanup cases O{level}',flush=True)
    if not baseline:
        variants=[('os-error-erased','        (sysRunPath tool v sysEnvp)','        (match (sysRunPath tool v sysEnvp) ((Ok code) (Ok code)) ((Err _) (Ok 0)))',('missing','direct-missing','clone-missing','crate-missing')),
                  ('child-status-erased','        (sysRunPath tool v sysEnvp)','        (match (sysRunPath tool v sysEnvp) ((Ok _) (Ok 0)) ((Err e) (Err e)))',('nonzero','exit127','signal','clone-failed')),
                  ('nonzero-success','((Ok code) (== code 0))','((Ok _) true)',('assemble-native-failed','repl-llc-failed','implib-failed'))]
        for label,before,after,required in variants:
            if fetch_only: required=tuple(name for name in required if name.startswith(('clone-', 'discard-', 'fetch-')))
            if not required: continue
            changed=dict(source);changed['driver.ax']=replace_once(source['driver.ax'],before,after,label)
            altered=modules(label,changed); binary=build(label,root/'tests/tools/driver-run-tool-results.axp',altered,0)
            observed=exercise(label,binary,altered,work/'child-O0',required)
            if any(observed[name]['passed'] for name in required):raise AssertionError((label,observed))
            report['controls'].append({'name':label,'failed_cases':list(required)})
            print('ok '+label+': required cases fail',flush=True)
        label='fetch-cleanup-skipped';changed=dict(source)
        # Formatting differs with nesting; replace each complete match by its
        # parsed expression rather than touching another cleanup operation.
        ast=runpy.run_path(str(root/'tests/selfhost/cli-flag-values.py'))
        text=source['main.ax'];fn=ast['declaration'](text,'fetchUrls')
        nodes=[n for n in ast['walk'](ast['parse'](fn)[-1]) if ast['op'](n)=='match'
               and ast['value'](fn,n[2][1])=='(fetchDiscard tmp)']
        assert len(nodes)==4
        altered_fn=fn
        for node in sorted(nodes,key=lambda n:n[0],reverse=True):altered_fn=altered_fn[:node[0]]+'()'+altered_fn[node[1]:]
        changed['main.ax']=replace_once(text,fn,altered_fn,label)
        altered=modules(label,changed);binary=build(label,root/'tests/tools/driver-run-tool-results.axp',altered,0)
        required=('fetch-failed','fetch-rename-failed')
        observed=exercise(label,binary,altered,work/'child-O0',required)
        assert all(not observed[name]['passed'] for name in required),observed
        report['controls'].append({'name':label,'failed_cases':list(required)})
        print('ok '+label+': required cases fail',flush=True)
        for label,body,code in (
            ('erased-result','(runTool "tool" vecNew)','AX3004'),
            ('missing-err','(match (runTool "tool" vecNew) ((Ok code) code))','AX3005'),
            ('missing-ok','(match (runTool "tool" vecNew) ((Err _) 0))','AX3005'),
            ('erased-stderr','(runToolErrTo "tool" vecNew "err")','AX3004'),
            ('erased-quiet','(runToolQuiet "tool" vecNew)','AX3004'),
            ('erased-clone','(fetchClone "url" "path")','AX3004'),
            ('erased-discard','(fetchDiscard "path")','AX3004'),
            ('clone-missing-err','(match (fetchClone "url" "path") ((Ok code) code))','AX3005')):
            fixture=work/(label+'.ax');fixture.write_text('(import driver)\n(import main (fetchClone fetchDiscard))\n(import Err)\n(:: bad Int)\n;@axiom:effect(io)\n;@axiom:effect(spawn)\n;@axiom:effect(block)\n(fn (bad) '+body+')\n(:: main Int) (fn (main) 0)\n')
            ran=subprocess.run([str(compiler),'--diagnostic-format=ai','check',str(fixture)],env=env,capture_output=True,text=True,timeout=90)
            errors=[line for line in ran.stderr.splitlines() if line.startswith('E ')]
            if ran.returncode!=1 or len(errors)!=1 or f'E {code} ' not in errors[0]:raise AssertionError((label,ran.returncode,ran.stderr))
            (work/(label+'.stderr')).write_text(ran.stderr);report['refusals'].append({'name':label,'diagnostic':code})
            print('ok '+label+': '+code,flush=True)
    assert hashlib.sha256(compiler.read_bytes()).hexdigest()==builder_hash
    for name,before in hashes.items():assert hashlib.sha256((source_root/name).read_bytes()).hexdigest()==before,name
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom',required=True,type=Path);parser.add_argument('--work',type=Path)
    parser.add_argument('--baseline-root',type=Path)
    parser.add_argument('--fetch-only',action='store_true',help='Run only fetch/clone/discard policies and their controls')
    args=parser.parse_args();root=Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True,exist_ok=True);check(args.axiom.resolve(),root,args.work.resolve(),args.baseline_root,args.fetch_only)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-run-tool-') as work:check(args.axiom.resolve(),root,Path(work),args.baseline_root,args.fetch_only)

if __name__=='__main__':main()
