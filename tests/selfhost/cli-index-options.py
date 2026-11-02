#!/usr/bin/env python3
"""Check optional argv indexes and preserve command-selection and CLI output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

HERE=Path(__file__).parent
VALUES=runpy.run_path(str(HERE/'cli-flag-values.py'))
CLI=runpy.run_path(str(HERE/'cli-flag-parts-options.py'))
SUPPORT=runpy.run_path(str(HERE/'emitter-line-buffer.py'))
replace_once=SUPPORT['replace_once']
declaration,expression=VALUES['declaration'],VALUES['expression']
QUERIES=[
    ([],None,None,None,None,None,0),
    (['check'],1,'check',1,'check',None,2),
    ([''],1,'',1,None,None,2),
    (['--opt','0','check','probe.ax'],3,'check',3,'check',None,4),
    (['--opt=0','check','probe.ax'],2,'check',2,'check',None,3),
    (['--check','check','probe.ax'],2,'check',2,'check',None,3),
    (['--unknown','probe.ax'],2,'probe.ax',2,None,None,3),
    (['--','-dash.ax'],2,'-dash.ax',2,None,1,3),
    (['check','--','-dash.ax'],1,'check',1,'check',2,2),
    (['--'],None,None,None,None,1,0),
    (['--input'],None,None,None,None,None,0),
    (['-'],None,None,None,None,None,0),
    (['--help'],None,None,1,'--help',None,2),
    (['--version'],None,None,1,'--version',None,2),
    (['--opt','0','--help'],None,None,None,None,None,0),
    (['run','probe.ax','--help'],1,'run',1,'run',None,2),
    (['run','--','--help'],1,'run',1,'run',2,2),
    (['--input=notoperand','build',''],2,'build',2,'build',None,3),
    (['unknown',''],1,'unknown',1,None,None,2),
    (['--unknown=value','check'],2,'check',2,'check',None,3),
]


def index_harness(sources):
    main=sources['main.ax'];current='(pub :: subcommandIndex (Option Int))' in sources['driver.ax']
    program=VALUES['harness'](sources)
    # The entry function and its real rejection/help policy run verbatim. The
    # successful command body prints a marker instead of compiling or spawning.
    entry=declaration(main,'main').replace('(pub :: main Int)','(pub :: probeEntry Int)').replace('(pub fn (main)','(pub fn (probeEntry)')
    # Stubbed dispatch performs IO only; its test caller must not claim the
    # production dispatcher's spawning/blocking/entropy effects.
    for effect in ('spawn','block','entropy'):
        entry=entry.replace(';@axiom:effect('+effect+')\n','')
    extra='\n'+declaration(main,'rejectUnknownCommand')+'\n'+entry+'''
(:: replOut (-> String Int))
;@axiom:effect(io)
(fn (replOut text) (writeStr stdout text))
(:: runSubcommand (-> String Int))
;@axiom:effect(io)
(fn (runSubcommand command) { (println (concat "dispatch=" command)) 0 })
'''
    extra+='\n'+declaration(sources['doc.ax'],'docOperands')
    extra+='''
(:: probeOperands Int)
;@axiom:effect(io)
(fn (probeOperands)
  { (let words docOperands)
    (for i in 0..(vecLen words)
      { (let word (vecGet words i)) (println (concat (fmtInt (strLen word)) (concat ":" word))) })
    0 })
'''
    required=expression(main,'runArgv','extra')
    first='' if current else '(let first (+ (positionalIndex operandStart) 1))'
    extra+='\n(:: probeRunExtra Int)\n;@axiom:effect(io)\n(fn (probeRunExtra) { (let dd (dashDashIndex operandStart)) (let p (positionalIndex operandStart)) '+first+' (let n sysArgc) '+required+' })\n'
    # newProjectCmd validates names/arity; the valid action is a visible marker.
    extra+='\n'+declaration(main,'newProjectCmd')+'''
(:: newProject (-> String Int))
;@axiom:effect(io)
(fn (newProject name) { (println (concat "project=" name)) 0 })
'''
    position=program.index('(:: main Int)')
    program=program[:position]+extra+'\n'+program[position:]
    program=program.replace('(import driver)', '(import core) (import Vec) (import driver)',1)
    program=program.replace('      (_ 97))', '''      ("entry" probeEntry)
      ("operands" probeOperands)
      ("runextra" { (let start probeRunExtra) (println (concat "extra=" (fmtInt start))) 0 })
      ("new" newProjectCmd)
      (_ 97))''')
    return program


def extra_cases():
    result=[]
    for args,*_ in QUERIES:
        result.append({'mode':'entry','argv':args,'fixture':'none'})
    for args in [['doc'],['doc','one','two'],['doc',''],['doc','--','-dash'],
                 ['--opt','0','doc','one'],['doc','--out','out','one']]:
        result.append({'mode':'operands','argv':args,'fixture':'none'})
    for args in [['run'],['run','probe.ax'],['run','probe.ax','one','--','two'],['run','--','one','two'],
                 ['run','--input=probe.ax'],['run','--input=probe.ax','--','one'],['run',''],['--opt','0','run','p','x']]:
        result.append({'mode':'runextra','argv':args,'fixture':'none'})
    for args in [['new'],['new',''],['new','valid-name'],['new','one','two'],['new','.'],
                 ['--opt=0','new','valid'],['new','--','-name']]:
        result.append({'mode':'new','argv':args,'fixture':'none'})
    return result


def check(compiler,root,work,baseline=None):
    names=('driver.ax','doc.ax','main.ax','fmtcli.ax')
    sources={name:(root/'core'/name).read_text() for name in names}
    fixture=(root/'tests/selfhost/cli-index-options.axp').read_text()
    behavior=(root/'tests/selfhost/cli-flag-parts-behavior.axp').read_text()
    report={'builder':str(compiler),'builder_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),
            'source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()},
            'configurations':[],'controls':[],'refusals':[],
            'limits':['Host O0/O2 with allocation poisoning; not target-wide qualification.',
                      'Entry dispatch and new-project success use visible test markers, not real compilation/project creation.',
                      'runArgv selection is tested as its exact extracted extra expression; raw argv allocation/copy code is unchanged.',
                      'Package lookup paths and codegen command-query mirrors are separate APIs.']}
    data=work/'inputs';data.mkdir(exist_ok=True)
    for kind in ('none','valid','broken'):
        folder=data/kind;folder.mkdir(exist_ok=True)
        if kind!='none':(folder/'axiom.pkg').write_text('name demo\nversion 0.1.0\nopt 2\nmain Main.ax\n')
        if kind=='valid':(folder/'Main.ax').write_text('(:: main Int) (fn (main) 0)\n')
    def modules(label,edits):
        folder=work/(label+'-modules/core');folder.mkdir(parents=True, exist_ok=True)
        for path in (root/'core').iterdir():
            dest=folder/path.name
            if path.name in edits:dest.write_text(edits[path.name])
            elif not dest.exists():dest.symlink_to(path,target_is_directory=path.is_dir())
        return dict(os.environ,AXIOM_PATH=str(folder),AXIOM_STDLIB=str(root/'stdlib'))
    def run(label,command,local,kind='none',require=None):
        result=subprocess.run(command,env=local,cwd=data/kind,capture_output=True,timeout=240)
        (work/(label+'.stdout')).write_bytes(result.stdout);(work/(label+'.stderr')).write_bytes(result.stderr)
        if require is not None:assert result.returncode==require,(label,result.returncode,result.stderr[-6000:])
        return result
    def native(label,level,edits,program):
        local=modules(label,edits);path=work/(label+'.ax');path.write_text(program);binary=work/label
        run(label+'-build',[str(compiler),'--diagnostic-format=ai','build',str(path),'--opt',str(level),
                           '--alloc-poison','-o',str(binary)],local,require=0)
        return binary,local
    def query_cases(label,binary,local):
        failed=[]
        integer=lambda n:'None' if n is None else 'Some '+str(n)
        string=lambda s:'None' if s is None else f'Some {len(s)}:{s}'
        for i,(args,p,word,c,command,dd,start) in enumerate(QUERIES):
            got=run(label+'-'+str(i),[str(binary),*args],local,require=0);assert not got.stderr
            wanted=[integer(p),string(word),integer(c),string(command),integer(dd),f'start={start}',
                    'Some 0','None','None','None','None','balanced=true']
            if got.stdout.decode().splitlines()!=wanted:failed.append(i)
        return failed
    cases=VALUES['scenarios']()+extra_cases()
    def policies(label,binary,local):
        results=[]
        for i,case in enumerate(cases):
            env=dict(local,AXIOM_OPTION_PROBE=case['mode'],XDG_CACHE_HOME='cache')
            result=run(label+'-'+str(i),[str(binary),*case['argv']],env,case['fixture'])
            results.append(dict(case,status=result.returncode,stdout=result.stdout.decode(),stderr=result.stderr.decode()))
        return results
    def cli(label,binary,local):
        results=[]
        for i,args in enumerate(CLI['SCENARIOS']):
            for file in ('probe.ax','-dash.ax'):(data/'none'/file).write_text('(:: main Int)\n(fn (main) 3)\n')
            got=run(label+'-'+str(i),[str(binary),*args],local)
            results.append({'argv':args,'status':got.returncode,'stdout':got.stdout.decode(),'stderr':got.stderr.decode(),
                            'files':{file:(data/'none'/file).read_text() for file in ('probe.ax','-dash.ax')}})
        return results
    golden=root/'tests/selfhost/cli-index-options.golden.json'
    if baseline:
        old={name:(baseline/name).read_text() for name in names}
        binary,local=native('baseline',0,old,index_harness(old));got=policies('baseline',binary,local)
        assert got[:len(VALUES['scenarios']())]==json.loads((root/'tests/selfhost/cli-flag-values.golden.json').read_text())
        if golden.exists():assert json.loads(golden.read_text())==got
        else:golden.write_text(json.dumps(got,indent=2)+'\n')
        report['baseline_source_sha256']={k:hashlib.sha256(v.encode()).hexdigest() for k,v in old.items()}
    assert golden.exists(),'record original policy behavior first'
    wanted=json.loads(golden.read_text());cli_wanted=json.loads((root/'tests/selfhost/cli-flag-parts-behavior.golden.json').read_text())
    for level in (0,2):
        label='query-O'+str(level);binary,local=native(label,level,sources,fixture)
        failed=query_cases(label,binary,local);assert not failed,(label,failed)
        label='policy-O'+str(level);program=index_harness(sources);binary,local=native(label,level,sources,program)
        got=policies(label,binary,local);different=[i for i,(a,b) in enumerate(zip(got,wanted)) if a!=b]
        assert not different,(label,different)
        label='cli-O'+str(level);binary,local=native(label,level,sources,behavior)
        got=cli(label,binary,local);assert got==cli_wanted,(label,[i for i,(a,b) in enumerate(zip(got,cli_wanted)) if a!=b])
        report['configurations'].append({'optimization':level,'poison':True,'query_scenarios':len(QUERIES),
                                         'policy_scenarios':len(cases),'cli_scenarios':len(cli_wanted),
                                         'harness_sha256':hashlib.sha256(program.encode()).hexdigest()})
        print(f'ok   argv indexes: {len(QUERIES)} query/ownership, {len(cases)} exact policies and {len(cli_wanted)} CLI cases O{level}',flush=True)
    driver=sources['driver.ax']
    for label,name,before,after,failures in [
        ('discard-zero','positionalIndex','(Some from)','(if (== from 0) None (Some from))',{0,1}),
        ('discard-empty','positionalFrom','(Some (sysArg i))','(if (== (strLen (sysArg i)) 0) None (Some (sysArg i)))',{2}),
        ('ignore-separator','positionalIndex','(strEq a "--")','false',{7}),
        ('skip-command-alias','subcommandIndex','(isSubcommand (sysArg 1))','false',{12,13}),
        ('retain-word','positionalFrom','(Some (sysArg i))','{ (let text (sysArg i)) (__retainref text) (Some text) }',{1,2}),
    ]:
        fn=declaration(driver,name);changed=replace_once(driver,fn,replace_once(fn,before,after,label),label)
        edits=dict(sources,**{'driver.ax':changed});binary,local=native(label,0,edits,fixture)
        failed=query_cases(label,binary,local);assert failures<=set(failed),(label,failed)
        report['controls'].append({'name':label,'failed_queries':failed})
        print(f'ok   counterexample {label}: {failed}',flush=True)
    # A consumer control must change actual argv selection, not just query shape.
    label='forward-from-file';main=sources['main.ax'];fn=declaration(main,'runArgv')
    before=expression(main,'runArgv','extra');after='sysArgc'
    changed=replace_once(main,fn,replace_once(fn,before,after,label),label)
    edits=dict(sources,**{'main.ax':changed});binary,local=native(label,0,edits,index_harness(edits))
    got=policies(label,binary,local);different=[i for i,(a,b) in enumerate(zip(got,wanted)) if a!=b]
    assert different and all(cases[i]['mode']=='runextra' for i in different),different
    report['controls'].append({'name':label,'changed_policies':different})
    print(f'ok   counterexample {label}: policy cases {different}',flush=True)
    local=modules('refusals',sources)
    for label,statement,code in [
        ('unchecked-index','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (+ (positionalIndex 1) 1))','AX3004'),
        ('nonexhaustive-index','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (match (dashDashIndex 1) ((Some i) i)))','AX3005'),
        ('unchecked-command','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (strLen subcommandName))','AX3004'),
        ('nonexhaustive-operand','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (match (positionalFrom 1) ((Some s) (strLen s))))','AX3005'),
        ('command-context','(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (checkArgs "run"))','AX3004'),
    ]:
        path=work/(label+'.ax');path.write_text('(import driver) (import Str)\n'+statement+'\n')
        got=run(label,[str(compiler),'--diagnostic-format=ai','check',str(path)],local)
        errors=[line for line in got.stderr.decode().splitlines() if line.startswith('E ')]
        assert got.returncode!=0 and len(errors)==1 and errors[0].startswith('E '+code+' '),(label,got.stderr)
        report['refusals'].append({'name':label,'code':code});print(f'ok   refusal {label}: {code}',flush=True)
    report['golden_sha256']=hashlib.sha256(golden.read_bytes()).hexdigest()
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')


def main():
    p=argparse.ArgumentParser();p.add_argument('--axiom',required=True,type=Path);p.add_argument('--work',type=Path);p.add_argument('--baseline-core',type=Path)
    args=p.parse_args();root=Path(__file__).resolve().parents[2]
    work=args.work or Path(tempfile.mkdtemp(prefix='axiom-cli-indexes-'));work.mkdir(parents=True,exist_ok=True)
    check(args.axiom.resolve(),root,work.resolve(),args.baseline_core)


if __name__=='__main__':main()
