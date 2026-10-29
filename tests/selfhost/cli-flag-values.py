#!/usr/bin/env python3
"""Check optional CLI values and exact extracted command-selection policies.

Selected main functions are copied verbatim, with their declarations and effect
annotations, into a small native harness. This does not compile the full compiler
or execute native linking. Output-selection expressions and missing-input arms
are extracted from the real dispatcher; successful compilation is a probe marker.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
replace_once = SUPPORT['replace_once']

def parse(s):
 tokens=[];i=0
 while i<len(s):
  c=s[i]
  if c.isspace():i+=1;continue
  if c==';':
   k=s.find('\n',i);i=len(s) if k<0 else k+1;continue
  a=i
  if c=='"':
   i+=1
   while i<len(s):
    if s[i]=='\\':i+=2
    elif s[i]=='"':i+=1;break
    else:i+=1
  elif c in '(){}[]':i+=1
  else:
   while i<len(s) and not s[i].isspace() and s[i] not in '(){}[];"':i+=1
  tokens.append((a,i,s[a:i]))
 stack=[];roots=[]
 for a,b,t in tokens:
  if t in '({[':
   n=[a,b,[],t];(stack[-1][2] if stack else roots).append(n);stack.append(n)
  elif t in ')}]':
   assert stack and '({['[')}]'.index(t)]==stack[-1][3],(a,t)
   stack.pop()[1]=b
  else:(stack[-1][2] if stack else roots).append([a,b,None,t])
 assert not stack
 return roots

def walk(n):
 yield n
 for c in n[2] or []:yield from walk(c)

def value(s, n):
    return s[n[0]:n[1]]


def op(n):
    return n[2][0][3] if n[2] else None


def declaration(source, name):
    pattern = r'\((?:pub\s+)?::\s+' + re.escape(name) + r'(?:\s|\))'
    nodes = parse(source)
    signatures = [n for n in nodes if re.match(pattern, value(source, n))]
    functions = [n for n in nodes if re.match(r'\((?:pub\s+)?fn\s+\(' + re.escape(name) + r'(?:\s|\))', value(source, n))]
    assert len(signatures) == len(functions) == 1, name
    return source[signatures[0][0]:functions[0][1]]


def expression(source, fn, binding):
    source = declaration(source, fn)
    candidates = [n[2][2] for n in walk(parse(source)[-1])
                  if op(n) == 'let' and len(n[2]) == 3 and n[2][1][3] == binding]
    assert len(candidates) == 1, (fn, binding)
    return value(source, candidates[0])


def harness(sources):
    main = sources['main.ax']
    current = '(pub :: inputOperand (Option String))' in main
    manifest = 'manifestEntry' if current else 'manifestEntryOrEmpty'
    names = ['diagFormatArg', 'symbolsCheckFormat', 'testJobs', 'inputOperand',
             'runInputOperand', 'runManifestMode', manifest, 'die', 'testContains']
    program = '''(import driver) (import pkg) (import render) (import Path) (import Fmt)
(import IO (fileExists writeStr stderr stdout)) (import Sys) (import Str) (import Err (isSome))
'''
    program += '\n(:: println (-> String Int))\n;@axiom:effect(io)\n(fn (println text) (writeStr stdout (concat text "\\n")))\n'
    program += '\n\n'.join(declaration(main, name) for name in names)
    program += '\n' + declaration(sources['doc.ax'], 'docOutDir')
    if current:
        program += '\n' + declaration(sources['doc.ax'], 'docDefaultOutDir')
    # The user-facing output values are presented identically to the old API.
    # Raw None versus Some empty is tested separately by cli-flag-values.axp.
    if current:
        program += '''
(:: selectedText (-> (Option String) String))
(fn (selectedText value) (match value ((None) "") ((Some text) text)))
'''
    else:
        program += '''
(:: selectedText (-> String String))
(fn (selectedText value) value)
'''
    for name, expr in [('probeEmitOutput', expression(main, 'runSubcommand', 'out')),
                       ('probeBuildInput', expression(main, 'runSubcommand', 'inp'))]:
        program += f'\n(:: {name} String)\n;@axiom:effect(io)\n(fn ({name}) (selectedText {expr}))\n'
    if '(:: packageBuildOutput' in main:
        program += '\n' + declaration(main, 'packageBuildOutput')
    program += '(:: probeBuildOutput (-> String String))\n;@axiom:effect(io)\n(fn (probeBuildOutput inp) '+expression(main, 'runSubcommand', 'outp')+')\n'
    program += '(:: probeFilter String)\n;@axiom:effect(io)\n(fn (probeFilter) '+expression(main, 'testMain', 'filter')+')\n'
    # Test each dispatcher's original missing arm. Only the successful work is
    # replaced, so these probes cannot compile user code or run native tools.
    dispatch = declaration(main, 'runSubcommand')
    ifs = [n for n in walk(parse(dispatch)[-1]) if op(n) == 'if' and len(n[2]) == 4
           and re.fullmatch(r'\(==\s+\(strLen\s+(f|inp)\)\s+0\)', value(dispatch, n[2][1]))
           and 'needs an input file' in value(dispatch, n[2][2])]
    assert len(ifs) == 5, len(ifs)
    for node in ifs:
        missing = value(dispatch, node[2][2])
        command = re.search(r'error: ([a-z-]+) needs an input file', missing).group(1)
        name = command.replace('-', '_')
        query = 'runInputOperand' if command == 'run' else expression(main, 'runSubcommand', 'inp') if command == 'build' else 'inputOperand'
        # Successful path marker is a valid Int because die/error arms return Int.
        if current:
            body = f'(match {query} ((None) {missing}) ((Some f) (if (== (strLen f) 0) {missing} 0)))'
        else:
            body = f'{{ (let f {query}) (if (== (strLen f) 0) {missing} 0) }}'
        program += f'\n(:: probe_{name} Int)\n;@axiom:effect(io)\n(fn (probe_{name}) {body})\n'
    program += '''
(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (let mode (sysEnv "AXIOM_OPTION_PROBE"))
    (match mode
      ("input" { (let text (selectedText inputOperand)) (println (concat "input=" text)) 0 })
      ("runinput" { (let text (selectedText runInputOperand)) (println (concat "input=" text)) 0 })
      ("manifest" { (let text (selectedText MANIFEST)) (println (concat "input=" text)) 0 })
      ("runmode" { (let mode runManifestMode) (println (concat "manifest=" (if mode "true" "false"))) 0 })
      ("diag" { (let n diagFormatArg) (println (concat "format=" (fmtInt n))) 0 })
      ("symbols" symbolsCheckFormat)
      ("jobs" { (let n testJobs) (println (concat "jobs=" (fmtInt n))) 0 })
      ("opt" { (let n (optLevelArg "")) (println (concat "opt=" (fmtInt n))) 0 })
      ("target" { (let text (targetArg "fallback")) (println (concat "target=" text)) 0 })
      ("docout" { (let text docOutDir) (println (concat "out=" text)) 0 })
      ("emitout" { (let text probeEmitOutput) (println (concat "out=" text)) 0 })
      ("buildout" { (let text (probeBuildOutput "probe.ax")) (println (concat "out=" text)) 0 })
      ("buildinput" { (let text probeBuildInput) (println (concat "input=" text)) 0 })
      ("filter" { (let text probeFilter) (let yes (testContains "example" text)) (println (concat "filter=" (concat text (concat " matches=" (if yes "true" "false"))))) 0 })
      ("check-missing" probe_check)
      ("emit-missing" probe_emit_llvm)
      ("build-missing" probe_build)
      ("symbols-missing" probe_symbols)
      ("run-missing" probe_run)
      (_ 97))
  })
'''.replace('MANIFEST', manifest)
    return program


QUERIES = [
    (['check'], 'None', 'None'),
    (['check', '--input='], 'Some 0:', 'None'),
    (['check', '--input', ''], 'Some 0:', 'None'),
    (['check', '--input', 'probe.ax'], 'Some 8:probe.ax', 'None'),
    (['check', '--input=first', '--input=second'], 'Some 5:first', 'Some 6:second'),
    (['check', '--input=', '--input=second'], 'Some 0:', 'Some 6:second'),
    (['check', '--', '--input=after'], 'Some 5:after', 'Some 5:after'),
    (['check', '--target', '--input=as-value'], 'Some 8:as-value', 'Some 8:as-value'),
    (['check', '--input'], 'None', 'None'),
    (['check', '--input=a=b'], 'Some 3:a=b', 'None'),
    (['--input=before', 'check'], 'Some 6:before', 'None'),
    (['check', '--input', '--input=other'], 'Some 13:--input=other', 'Some 5:other'),
]


def scenarios():
    result = []
    def add(mode, command, variants, fixture='none'):
        result.extend({'mode':mode, 'argv':[command, *args], 'fixture':fixture} for args in variants)
    for mode, command, flag in [('diag','check','--diagnostic-format'), ('jobs','test','--jobs'),
                                ('opt','build','--opt'), ('target','build','--target')]:
        values = {'diag':['ai','json','human','wrong'], 'jobs':['0','-1','2','bad'],
                  'opt':['0','2','3','bad'], 'target':['linux-aarch64','windows-x86_64']}[mode]
        add(mode,command,[[],[flag],[flag+'='],[flag,''],*[ [flag+'='+v] for v in values],
                          [flag+'=',flag+'='+values[0]]])
    add('symbols','symbols',[[],['--diagnostic-format=json'],['--diagnostic-format=ai'],['--diagnostic-format=']])
    add('input','check',[[],[''],['probe.ax'],['--input='],['--input=','probe.ax'],['--input=probe.ax'],
                         ['--input','probe.ax'],['--input=probe.ax','other.ax'],['probe.ax','other.ax'],
                         ['--','-dash.ax'],['--input=','--input=other.ax'],['--input=probe.ax','--input=other.ax']])
    add('runinput','run',[['probe.ax','--input=other.ax'],['--input=probe.ax'],[''],[]])
    add('runmode','run',[[],[''],['probe.ax'],['--','arg'],['--input='],['--input=probe.ax'],['probe.ax','--','arg']])
    for mode,command in [('check-missing','check'),('emit-missing','emit-llvm'),('build-missing','build'),
                          ('symbols-missing','symbols'),('run-missing','run')]:
        add(mode,command,[[],[''],['--input='],['--input=probe.ax']])
    add('docout','doc',[[],['--out='],['--out',''],['--out=html'],['--out=','--out=other']])
    for mode,command in [('emitout','emit-llvm'),('buildout','build')]:
        add(mode,command,[[],['-o='],['--output='],['-o=one'],['--output=two'],['-o=one','--output=two'],
                          ['-o=','--output=two'],['--output=','-o=one'],['--output=','--output=second']])
    add('filter','test',[[],['--filter='],['--filter=amp'],['--filter=absent'],['--filter=','--filter=absent']])
    for fixture in ['valid','broken']:
        add('manifest','build',[[]],fixture)
        add('buildinput','build',[[],['--input='],['--input=probe.ax'],['']],fixture)
        add('runinput','run',[[],['--','arg'],['--input=probe.ax']],fixture)
        add('opt','build',[[],['--opt='],['--opt=0']],fixture)
        add('buildout','build',[[],['-o='],['--output=app']],fixture)
    return result


def check(compiler, root, work, baseline=None):
    sources = {name:(root/'core'/name).read_text() for name in ('driver.ax','doc.ax','main.ax')}
    fixture = (root/'tests/selfhost/cli-flag-values.axp').read_text()
    report = {'builder':str(compiler), 'builder_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()},
              'configurations':[], 'controls':[], 'refusals':[],
              'limits':['Host O0/O2 with allocation poisoning; not target-wide qualification.',
                        'Main policy functions/expressions are extracted verbatim; successful compilation is a probe marker.',
                        'This test does not bootstrap the compiler, link a user program, or run Rust binding generation.',
                        'Positional/subcommand/dashdash indexes and pkgFindManifest remain upstream sentinel APIs.']}
    data=work/'inputs';data.mkdir(exist_ok=True)
    for kind in ('none','valid','broken'):
        folder=data/kind;folder.mkdir(exist_ok=True)
        (folder/'probe.ax').write_text('(:: main Int) (fn (main) 0)\n')
        if kind!='none':
            (folder/'axiom.pkg').write_text('name demo\nversion 0.1.0\nopt 2\nmain Main.ax\n')
        if kind=='valid':(folder/'Main.ax').write_text('(:: main Int) (fn (main) 0)\n')

    def modules(label, edits):
        folder=work/(label+'-modules');folder.mkdir(exist_ok=True)
        for path in (root/'core').iterdir():
            dest=folder/path.name
            if path.name in edits:dest.write_text(edits[path.name])
            elif not dest.exists():dest.symlink_to(path,target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root/'stdlib'))

    def run(label, command, local, kind='none', require=None):
        result=subprocess.run(command,env=local,cwd=data/kind,capture_output=True,timeout=240)
        (work/(label+'.stdout')).write_bytes(result.stdout)
        (work/(label+'.stderr')).write_bytes(result.stderr)
        if require is not None:assert result.returncode==require,(label,result.returncode,result.stderr[-6000:])
        return result

    def native(label, level, edits, program):
        local=modules(label,edits);path=work/(label+'.ax');path.write_text(program);binary=work/label
        run(label+'-build',[str(compiler),'--diagnostic-format=ai','build',str(path),'--opt',str(level),
                           '--alloc-poison','-o',str(binary)],local,require=0)
        return binary,local

    def queries(label,binary,local):
        failed=[]
        for i,(args,first,later) in enumerate(QUERIES):
            result=run(label+'-'+str(i),[str(binary),*args],local,require=0)
            assert not result.stderr,(label,i,result.stderr)
            wanted=[first,'None','None','None',later,'balanced=true']
            if result.stdout.decode().splitlines()!=wanted:failed.append(i)
        return failed

    cases=scenarios()
    def policies(label,binary,local):
        results=[]
        for i,case in enumerate(cases):
            env=dict(local,AXIOM_OPTION_PROBE=case['mode'],XDG_CACHE_HOME='cache')
            result=run(label+'-'+str(i),[str(binary),*case['argv']],env,case['fixture'])
            results.append(dict(case,status=result.returncode,stdout=result.stdout.decode(),stderr=result.stderr.decode()))
        return results

    golden=root/'tests/selfhost/cli-flag-values.golden.json'
    if baseline:
        original={name:(baseline/name).read_text() for name in sources}
        binary,local=native('baseline',0,original,harness(original))
        original_outcomes=policies('baseline',binary,local)
        if golden.exists():assert original_outcomes==json.loads(golden.read_text()),'baseline golden differs'
        else:golden.write_text(json.dumps(original_outcomes,indent=2)+'\n')
        report['baseline_source_sha256']={k:hashlib.sha256(v.encode()).hexdigest() for k,v in original.items()}
    assert golden.exists(),'record original policy behavior before accepting the migration'
    wanted=json.loads(golden.read_text())
    for level in (0,2):
        label='queries-O'+str(level);binary,local=native(label,level,sources,fixture)
        assert not queries(label,binary,local),label
        label='policies-O'+str(level);program=harness(sources);binary,local=native(label,level,sources,program)
        got=policies(label,binary,local)
        differences=[i for i,(a,b) in enumerate(zip(got,wanted)) if a!=b]
        assert not differences,(label,differences)
        report['configurations'].append({'optimization':level,'poison':True,'query_scenarios':len(QUERIES),
                                         'policy_scenarios':len(cases),'harness_sha256':hashlib.sha256(program.encode()).hexdigest()})
        print(f'ok   flag values: {len(QUERIES)} query/ownership and {len(cases)} exact policy cases O{level}',flush=True)
    driver=sources['driver.ax'];fn=declaration(driver,'flagValueAt')
    inline='(Some (strSlice a (strLen eq) (- (strLen a) (strLen eq))))'
    for label,before,after,failures in [
        ('discard-empty',inline,'(if (== (strLen a) (strLen eq)) None '+inline+')',{1,5}),
        ('skip-first-inline',inline,'(flagValueAt name (+ i 1) n)',{1,4,5,9}),
        ('stop-at-separator','(flagValueAt name (+ i 1) n)',
         '(if (strEq a "--") None (flagValueAt name (+ i 1) n))',{6}),
        ('retain-result',inline,'{ (let value (strSlice a (strLen eq) (- (strLen a) (strLen eq)))) (__retainref value) (Some value) }',{4,9}),
    ]:
        changed=replace_once(driver,fn,replace_once(fn,before,after,label),label)
        binary,local=native(label,0,dict(sources,**{'driver.ax':changed}),fixture)
        failed=queries(label,binary,local);assert failures<=set(failed),(label,failed)
        report['controls'].append({'name':label,'failed_queries':failed})
        print(f'ok   counterexample {label}: {failed}',flush=True)
    for label, fn_name, before, after in [
        ('empty-input-suppresses-positional','inputOperand','(> (strLen value) 0)','true'),
        ('reverse-output-priority','runSubcommand',expression(sources['main.ax'],'runSubcommand','out'),
         expression(sources['main.ax'],'runSubcommand','out').replace('"-o"','"SWAP"').replace('"--output"','"-o"').replace('"SWAP"','"--output"')),
    ]:
        fn=declaration(sources['main.ax'],fn_name)
        changed=replace_once(sources['main.ax'],fn,replace_once(fn,before,after,label),label)
        edits=dict(sources,**{'main.ax':changed});binary,local=native(label,0,edits,harness(edits))
        got=policies(label,binary,local);different=[i for i,(a,b) in enumerate(zip(got,wanted)) if a!=b]
        assert different,label
        report['controls'].append({'name':label,'changed_policies':different})
        print(f'ok   counterexample {label}: policy cases {different}',flush=True)
    local=modules('refusals',sources)
    for label,statement,code in [
        ('unchecked-value','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (strLen (flagValue "--input" 1)))','AX3004'),
        ('nonexhaustive-value','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (match (flagValue "--input" 1) ((Some value) (strLen value))))','AX3005'),
        ('unchecked-at','(:: bad String) ;@axiom:effect(io)\n(fn (bad) (flagValueAt "--input" 1 2))','AX3004'),
        ('binding-outside-success','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (if (let (Some value) (flagValue "--input" 1)) 0 (strLen value)))','AX3001'),
    ]:
        path=work/(label+'.ax');path.write_text('(import driver) (import Str)\n'+statement+'\n')
        result=run(label,[str(compiler),'--diagnostic-format=ai','check',str(path)],local)
        errors=[line for line in result.stderr.decode().splitlines() if line.startswith('E ')]
        assert result.returncode!=0 and len(errors)==1 and errors[0].startswith('E '+code+' '),(label,result.stderr)
        report['refusals'].append({'name':label,'code':code})
        print(f'ok   refusal {label}: {code}',flush=True)
    report['golden_sha256']=hashlib.sha256(golden.read_bytes()).hexdigest()
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--axiom',required=True,type=Path)
    parser.add_argument('--work',type=Path)
    parser.add_argument('--baseline-core',type=Path)
    args=parser.parse_args();root=Path(__file__).resolve().parents[2]
    work=args.work or Path(tempfile.mkdtemp(prefix='axiom-cli-flag-values-'));work.mkdir(parents=True,exist_ok=True)
    check(args.axiom.resolve(),root,work.resolve(),args.baseline_core)


if __name__=='__main__':
    main()
