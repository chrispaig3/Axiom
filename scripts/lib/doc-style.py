#!/usr/bin/env python3
"""Check a Markdown document against the house style and the doc gates.

The style is `.claude/skills/docs-style/SKILL.md`. This tool is what
lets a writer, human or agent, find out whether a page follows it
before CI does. It reports two kinds of finding:

  error    something a CI gate will reject, or a fact the rewrite lost:
           a code example that does not compile, a link or fixture
           path that does not resolve, a gated sentence that is gone,
           a rule identifier that was dropped or duplicated.
  style    a pattern the style guide asks writers to avoid: dates in
           running prose, spaced hyphens used as dashes, shouted
           words, very long sentences and paragraphs, stock phrases.

Style findings are advice. Errors are not.

Usage:

  python3 scripts/lib/doc-style.py FILE...
  python3 scripts/lib/doc-style.py --axiom .axiom-bin/axiom FILE...
  python3 scripts/lib/doc-style.py --before OLD.md --dest docs/x.md NEW.md

  --axiom PATH   compile every documented program (a ```scheme block
                 that declares `main`) with `PATH check`
  --before OLD   compare against an earlier version of the same text:
                 rule ids, gated sentences and generated blocks must
                 survive, and dropped codes and paths are listed
  --dest PATH    where the file will live in the repository, when it
                 is being checked from somewhere else; links and
                 inbound anchors are resolved as if it were there
  --quiet-style  print errors only

Exit status is 1 if any error was found, 0 otherwise.
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))

# ---------------------------------------------------------------- text

FENCE = re.compile(r'^```([^\n]*)\n(.*?)^```[ \t]*$', re.S | re.M)
AXIOM_FENCE = re.compile(r'^(scheme|axiom)\b')


def strip_code(text):
    """Prose only: fenced blocks, inline code, HTML comments and URLs removed."""
    text = FENCE.sub(lambda m: '\n' * m.group(0).count('\n'), text)
    text = re.sub(r'<!--.*?-->', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    text = re.sub(r'`[^`\n]*`', 'code', text)
    text = re.sub(r'\]\([^)]*\)', ']', text)
    text = re.sub(r'https?://\S+', 'url', text)
    return text


def paragraphs(text):
    """(line number, paragraph) pairs, split on blank lines."""
    out, start, buf = [], 1, []
    for i, line in enumerate(text.split('\n'), 1):
        if line.strip():
            if not buf:
                start = i
            buf.append(line)
        elif buf:
            out.append((start, '\n'.join(buf)))
            buf = []
    if buf:
        out.append((start, '\n'.join(buf)))
    return out


def slug(heading):
    """GitHub's anchor for a heading."""
    h = heading.strip().lower()
    h = re.sub(r'<[^>]+>', '', h)
    h = h.replace('`', '')
    h = re.sub(r'[^\w\- ]', '', h)
    return h.replace(' ', '-')


def anchors_of(text):
    body = FENCE.sub('', text)
    found = set()
    counts = {}
    for m in re.finditer(r'^#{1,6} +(.+?)\s*#*\s*$', body, re.M):
        s = slug(m.group(1))
        n = counts.get(s, 0)
        counts[s] = n + 1
        found.add(s if n == 0 else '%s-%d' % (s, n))
    found |= set(re.findall(r'<a (?:id|name)="([^"]+)"', body))
    return found

# ---------------------------------------------------------- the gates

# The same patterns `scripts/check-doc-drift.sh` uses. Kept in step by
# hand; if that gate changes one, change it here.
EXT = (r'axbad|axp|ax|py|sh|out|golden|axdl|human|json|in|allow|axir|bad|err|'
       r'exit|hist|lines|markers|mir|optstable|pending|policy|repl|session')
TESTS_PATH = re.compile(r'tests/[\w./-]+\.(?:' + EXT + r')(?![\w])')
BARE_NAME = re.compile(r'(?<![\w/.-])(\d{3}-[\w-]+\.(?:' + EXT + r'))(?![\w])')
NEG_CORPUS = re.compile(
    r'\b(?:no|No|nothing|Nothing|never|Never|cannot|only|Only)\b'
    r'[^.\n]{0,60}?'
    r'\b(?:fixture|fixtures|probe|probes|test case|test cases|corpus)\b')
HAS_PATH = re.compile(r'\b(?:tests|scripts)/[A-Za-z0-9_./-]+')
NEG_MARK = re.compile(r'<!--\s*doc-gate:negative(?:-exempt)?\s+\S')
OPENISH = re.compile(r'still open|no gate|nothing would notice|stays a defect'
                     r'|is unknown|not measured|ungated', re.I)
CLOSED_ROW = re.compile(r'\|\s*~~`([A-Z][A-Z0-9-]*-[0-9]+[a-z]?)`~~\s*\|\s*\*\*CLOSED')
RULE_DEF = re.compile(r'^\*\*([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+-[0-9]+(?:\.[0-9]+)*[a-z]?)\b', re.M)
INV_DEF = re.compile(r'^\| \*\*(I[0-9]+)\*\*', re.M)
RULE_ANY = re.compile(r'\b((?:MM|ERR|MAC|FFI|LSP|AGT|CA|SUB|US|GEN|MIR|EMB|CON)'
                      r'(?:-[A-Z0-9]+)+-[0-9]+(?:\.[0-9]+)*[a-z]?)\b')
AXCODE = re.compile(r'\bAX[0-9]{4}\b')
SCRIPT_PATH = re.compile(r'scripts/[\w./-]+\.(?:sh|py|mjs)')

# Sentences other gates read by pattern. If the earlier version had one,
# the new one must too, with the same number of matches.
GATED = [
    ('the `.ax` file count', r'\d+ `\.ax` files'),
    ('the compiler line count', r'[\d,]+ lines of it'),
    ('the tree-shape corpus count', r'\d+-case tree-shape corpus'),
    ('the version banner', r'Axiom [0-9]+\.[0-9]+\.[0-9]+ (?:\(build|- REPL)'),
    ('the supported release', r'The supported release is \*\*[0-9.]+\*\*'),
    ('the support window', r'^Support window:'),
    ('the target rule', r'executes what the compiler emits there'),
    ('the README target list', r'^Supported: '),
    ('the reference target list', r'Supported targets: '),
    ('the unexecuted-target excuse', r'executed by no runner|no runner for it'),
    ('the warning allowlist paragraph', r'permitted to render as warnings'),
    ('a not-supported-target bullet', r'^- \*\*[a-z0-9]+-[a-z0-9_]+\.\*\* Not a supported target'),
    ('a proposed-code table row', r'^\| `AX[0-9]{4}` \| `[a-z-]+` \|'),
    ('a trap-status table row', r'^\| (?:7[0-9]|80) \|'),
    ('a CLOSED defect row', r'~~`[A-Z][A-Z0-9-]*-[0-9]+[a-z]?`~~\s*\|\s*\*\*CLOSED'),
    ('a **Complete** status row', r'^\| [^|\n]+ \| \*\*Complete\*\* \|'),
    ('a doc-gate marker', r'<!-- doc-gate:[a-z-]+'),
    ('a link-base declaration', r'doc-links-resolve-from:'),
]

# ------------------------------------------------------------- style

STOCK = [
    # Throat-clearing and filler.
    r'\bcomprehensive\b', r'\bfriendly guide\b', r"\byou're in the right place\b",
    r'\bwalk you through\b', r'\beverything you need to know\b', r'\bIt is worth noting\b',
    r'\bNote that\b', r'\bIn other words\b', r'\bIt should be noted\b',
    # Defensive emphasis this project's docs used to lean on.
    r'\bdeliberately\b', r'\bon purpose\b', r'\bnot an afterthought\b', r'\bthe whole point\b',
    r'\bstated here\b', r'\bsaid out loud\b', r'\bnamed rather than\b', r'\brather than left\b',
    r'\bthe one copy\b', r'\bload-bearing\b', r'\bin those words\b', r'\bhonest(?:ly)?\b',
    r'\bmeasured on\b', r'\bas of this commit\b', r'\bto be clear\b',
    # History narrated in a present-tense page.
    r'\buntil then\b', r'\bwas retired\b', r'\bsince 20\d\d\b',
]
STOCK_RE = re.compile('|'.join(STOCK), re.I)

# Upper-case words that are names, not shouting.
CAPS_OK = set('''
ABI ANSI API ARM ASCII AST AXDL AXIR AXSYM AXTAG BSD CLI CPU CRLF CSV DSL EOF FFI FNV GCC GHC
GNU HTTP HTTPS JSON LLVM LSP LTO MIR NUL NID OOM PATH PID POSIX RAII RFC SIMD SIGSEGV SIGABRT
SIGKILL SIGPIPE SIGINT SIGTERM SHA TCG TCP TODO TUI UTF URL UTC XDG YAML MUST SHOULD NOT MAY
REQUIRED SHALL CRLF CLOSED OPEN WONTFIX UB VM IO GC JIT MMIO ISR NMI MMU RISC CISC WASM ELF
MSVC MACH DWARF PDB PE COFF LIFO FIFO TLS PRNG CSPRNG UUID ASCII XOR NAND KAT LSB MSB ISO IEEE
MAC ERR ARG ENV SKIP FAIL PASS NOTE HINT HELP WARN INFO NONE STDIN STDOUT STDERR EINTR EAGAIN
ENOENT EEXIST EPIPE EBADF EINVAL ENOMEM ENOSYS EACCES EPERM EISDIR ENOTDIR MAP GET POST HEAD
PUT DELETE CONNECT OPTIONS TRACE PATCH README CHANGELOG LICENSE SECURITY CONTRIBUTING AGENTS
CLAUDE THREATS STAMP CHAIN SHA256SUMS VERSION DDC REPL HTML TBAA LICM SDK SSA LLDB GDB
NULL CPUS MACOS
'''.split())
CAPS = re.compile(r"(?<![-\w])[A-Z][A-Z']{3,}(?![-\w])")


def style_findings(text):
    prose = strip_code(text)
    out = []
    units = []
    for line_no, para in paragraphs(prose):
        # A list item is its own unit: a bullet list is not one paragraph.
        item, start = [], line_no
        for off, line in enumerate(para.split('\n')):
            if re.match(r'\s*(?:[-*+]|\d+\.)\s', line) and item:
                units.append((start, '\n'.join(item)))
                item, start = [], line_no + off
            item.append(line)
        units.append((start, '\n'.join(item)))
    for line_no, para in units:
        head = para.lstrip()
        if head.startswith('|') or head.startswith('#') or head.startswith('>'):
            continue
        flat = ' '.join(para.split())
        words = len(flat.split())
        if words > 130:
            out.append((line_no, 'long paragraph (%d words); split it' % words))
        for s in re.split(r'(?<=[.!?])\s+(?=[A-Z`*(])', flat):
            n = len(s.split())
            if n > 45:
                out.append((line_no, 'long sentence (%d words): "%s..."' % (n, s[:70])))
        for m in re.finditer(r'\b20\d\d-\d\d-\d\d\b', para):
            out.append((line_no, 'date in running prose (%s); history belongs in CHANGELOG.md' % m.group(0)))
        for m in re.finditer(r'\w - \w', para):
            out.append((line_no, 'spaced hyphen used as a dash: "...%s..."' % para[max(0, m.start() - 20):m.end() + 20].replace('\n', ' ')))
            break
        for m in CAPS.finditer(para):
            w = m.group(0)
            if w.strip("'") not in CAPS_OK and not w.startswith('AX'):
                out.append((line_no, 'shouted word "%s"; use plain case, or italics once' % w))
        for m in STOCK_RE.finditer(para):
            out.append((line_no, 'stock phrase "%s"' % m.group(0)))
    return out

# ----------------------------------------------------------- checks


def load_scanner():
    path = os.path.join(ROOT, 'tests', 'fmt', 'verify-fmt.py')
    spec = importlib.util.spec_from_file_location('verify_fmt', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def is_program(body):
    return re.search(r'\(\s*(?:pub\s+)?(?:fn|define)\s+\(?\s*main\b', body) is not None


def check_code(text, axiom, errors):
    vf = load_scanner()
    work = tempfile.mkdtemp(prefix='docstyle')
    for m in FENCE.finditer(text):
        info, body = m.group(1).strip(), m.group(2)
        if not AXIOM_FENCE.match(info):
            continue
        line = text.count('\n', 0, m.start()) + 1
        if 'excerpt' not in info:
            depth, under = 0, False
            for d in vf.scan(body)[3]:
                depth += 1 if d in vf.OPENERS else -1
                if depth < 0:
                    under = True
                    break
            if under or depth != 0:
                errors.append((line, 'code block does not balance its delimiters'))
                continue
        if axiom and 'fragment' not in info and is_program(body):
            path = os.path.join(work, 'block.ax')
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(body)
            r = subprocess.run([axiom, '--diagnostic-format=ai', 'check', path],
                               capture_output=True, text=True)
            out = (r.stdout + r.stderr).strip()
            if 'refused' in info:
                if r.returncode == 0:
                    errors.append((line, 'block is marked `refused` but compiles'))
            elif r.returncode != 0:
                errors.append((line, 'program does not compile: %s' % out.split('\n')[0][:160]))


def check_refs(text, dest, errors):
    base = os.path.dirname(dest)
    tests_index = set()
    for r, _d, files in os.walk(os.path.join(ROOT, 'tests')):
        tests_index.update(files)
    for m in TESTS_PATH.finditer(text):
        if not os.path.exists(os.path.join(ROOT, m.group(0))):
            errors.append((text.count('\n', 0, m.start()) + 1, 'names %s, which does not exist' % m.group(0)))
    for m in BARE_NAME.finditer(text):
        if m.group(1) not in tests_index:
            errors.append((text.count('\n', 0, m.start()) + 1, 'names %s, which is not a file under tests/' % m.group(1)))
    retrievable = set(re.findall(r'git show [0-9a-f]{7,40}\^?:(docs/[\w./-]+\.md)', text))
    for m in re.finditer(r'(?<![\w$/\-.])docs/[\w./-]+\.md(?![\w])', text):
        if m.group(0) not in retrievable and not os.path.exists(os.path.join(ROOT, m.group(0))):
            errors.append((text.count('\n', 0, m.start()) + 1, 'names %s, which does not exist' % m.group(0)))
    for m in re.finditer(r'\]\(([^)\s#]+)(#[^)\s]*)?\)', text):
        tgt = m.group(1)
        if re.match(r'[a-z]+:', tgt):
            continue
        resolved = os.path.normpath(os.path.join(ROOT, base, tgt))
        line = text.count('\n', 0, m.start()) + 1
        if not os.path.exists(resolved):
            errors.append((line, 'links to %s, which resolves to %s and does not exist'
                           % (tgt, os.path.relpath(resolved, ROOT))))
            continue
        if m.group(2) and resolved.endswith('.md'):
            if os.path.relpath(resolved, ROOT) == dest:
                target_text = text
            else:
                target_text = open(resolved, encoding='utf-8').read()
            if m.group(2)[1:] not in anchors_of(target_text):
                errors.append((line, 'links to %s%s, and that heading does not exist'
                               % (tgt, m.group(2))))
    for m in re.finditer(r'\]\((#[^)\s]+)\)', text):
        if m.group(1)[1:] not in anchors_of(text):
            errors.append((text.count('\n', 0, m.start()) + 1,
                           'links to %s, and this page has no such heading' % m.group(1)))


def inbound_anchors(dest):
    """Anchors on `dest` that something else in the tree links to."""
    name = os.path.basename(dest)
    pat = re.compile(r'([\w./${}:-]*?)(?<![\w-])' + re.escape(name) + r'#([\w-]+)')
    ref = re.compile(r'\$\{REF\}#([\w-]+)')
    want = {}
    for r, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ('.git', 'node_modules', 'target', '.axiom-bin', 'dist')]
        for fn in files:
            if not fn.endswith(('.md', '.ts', '.tsx', '.ax', '.sh', '.py', '.mjs', '.yml')):
                continue
            rel = os.path.relpath(os.path.join(r, fn), ROOT)
            if rel == dest or rel == 'CHANGELOG.md':
                continue
            try:
                text = open(os.path.join(r, fn), encoding='utf-8', errors='ignore').read()
            except OSError:
                continue
            for m in pat.finditer(text):
                full = m.group(1) + name
                if 'blob/trunk/' in full:
                    cand = full.split('blob/trunk/', 1)[1]
                elif full.startswith('${DOCS}/'):
                    cand = 'docs/' + full[len('${DOCS}/'):]
                elif full.startswith('${BLOB}/'):
                    cand = full[len('${BLOB}/'):]
                elif full.startswith('${LIB}'):
                    cand = full[len('${LIB}'):]
                elif ':' in full or '$' in full:
                    continue
                elif fn.endswith('.md'):
                    cand = os.path.normpath(os.path.join(os.path.dirname(rel), full))
                else:
                    cand = os.path.normpath(full)
                if cand == dest:
                    want.setdefault(m.group(2), set()).add(rel)
            if dest == os.path.join('docs', 'reference.md'):
                for m in ref.finditer(text):
                    want.setdefault(m.group(1), set()).add(rel)
    return want


def check_inbound(text, dest, errors):
    have = anchors_of(text)
    for anchor, users in sorted(inbound_anchors(dest).items()):
        if anchor not in have:
            errors.append((0, '#%s is linked from %s and is not a heading or <a id> here'
                           % (anchor, ', '.join(sorted(users)))))


def check_gate_rules(text, errors):
    for line_no, para in paragraphs(text):
        if NEG_CORPUS.search(para) and not HAS_PATH.search(para) and not NEG_MARK.search(para):
            errors.append((line_no, 'a negative about fixtures/probes/tests/corpus with no tests/ or '
                           'scripts/ path in the paragraph (check-doc-drift.sh rule 5b); '
                           'name the path or reword'))
    closed = set(CLOSED_ROW.findall(text))
    for line_no, para in paragraphs(text):
        if para.lstrip().startswith('|'):
            continue
        m = OPENISH.search(para)
        if m:
            for rid in closed:
                if rid in para:
                    errors.append((line_no, '`%s` is CLOSED in this page\'s register and this paragraph '
                                   'says "%s"' % (rid, m.group(0))))
    seen = {}
    for pat in (RULE_DEF, INV_DEF):
        for m in pat.finditer(text):
            seen.setdefault(m.group(1), []).append(text.count('\n', 0, m.start()) + 1)
    for rid, lines in seen.items():
        if len(lines) > 1:
            errors.append((lines[1], 'rule `%s` is defined %d times' % (rid, len(lines))))


def compare(old, new, errors, info):
    def defs(t):
        return set(RULE_DEF.findall(t)) | set(INV_DEF.findall(t))
    lost = defs(old) - defs(new)
    added = defs(new) - defs(old)
    if lost:
        errors.append((0, 'rule definitions lost: %s' % ', '.join(sorted(lost))))
    if added:
        errors.append((0, 'rule definitions added: %s (a rewrite keeps the rules it was given)'
                       % ', '.join(sorted(added))))
    for label, pat in GATED:
        a = len(re.findall(pat, old, re.M))
        b = len(re.findall(pat, new, re.M))
        if a and b < a:
            errors.append((0, '%s: %d in the earlier text, %d now' % (label, a, b)))
    for m in re.finditer(r'<!-- doc-gate:(?:source|render)[^>]*-->\n```[^\n]*\n.*?^```', old, re.S | re.M):
        if m.group(0) not in new:
            errors.append((0, 'a doc-gate block changed or is gone; copy it byte for byte: %s'
                           % m.group(0).split('\n')[0]))
    for label, pat in (('diagnostic codes', AXCODE), ('tests/ paths', TESTS_PATH),
                       ('scripts/ paths', SCRIPT_PATH), ('rule citations', RULE_ANY)):
        gone = set(pat.findall(old)) - set(pat.findall(new))
        if gone:
            info.append('%s no longer mentioned: %s' % (label, ', '.join(sorted(gone))))
    ao = len(re.findall(r'^```(?:scheme|axiom)', old, re.M))
    an = len(re.findall(r'^```(?:scheme|axiom)', new, re.M))
    if an < ao:
        info.append('Axiom code blocks: %d before, %d now' % (ao, an))
    wo, wn = len(strip_code(old).split()), len(strip_code(new).split())
    info.append('prose words: %d before, %d now (%+d%%)' % (wo, wn, (wn - wo) * 100 // max(wo, 1)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('files', nargs='+')
    ap.add_argument('--axiom')
    ap.add_argument('--before')
    ap.add_argument('--dest')
    ap.add_argument('--quiet-style', action='store_true')
    ap.add_argument('--no-inbound', action='store_true',
                    help='skip the inbound-anchor check (for a fragment of a page)')
    args = ap.parse_args()
    if args.dest and len(args.files) != 1:
        ap.error('--dest takes exactly one file')
    failed = 0
    for f in args.files:
        text = open(f, encoding='utf-8').read()
        dest = args.dest or os.path.relpath(os.path.abspath(f), ROOT)
        errors, info = [], []
        check_code(text, args.axiom, errors)
        check_refs(text, dest, errors)
        check_gate_rules(text, errors)
        if not args.no_inbound:
            check_inbound(text, dest, errors)
        if args.before:
            compare(open(args.before, encoding='utf-8').read(), text, errors, info)
        style = [] if args.quiet_style else style_findings(text)
        for line, msg in sorted(errors):
            print('%s:%d: error: %s' % (dest, line, msg))
        for line, msg in style:
            print('%s:%d: style: %s' % (dest, line, msg))
        for msg in info:
            print('%s: info: %s' % (dest, msg))
        print('%s: %d error(s), %d style note(s)' % (dest, len(errors), len(style)))
        failed += bool(errors)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
