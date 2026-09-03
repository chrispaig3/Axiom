#!/usr/bin/env python3
"""The public surface of the standard library, as a comparable stream.

WHY THIS EXISTS. `scripts/check-version.sh` proves the version number is
STATED in nineteen places. Nothing proved it was EARNED: every gate in
this repository stayed green while a public name changed type, widened
its effect row, or stopped existing. `CHANGELOG.md`'s 0.2.0
"Compatibility" section named the gap - "a deprecation policy and a
compatibility gate over the symbol stream are the next release's work".

WHY AXSYM IS THE RIGHT SUBSTRATE, measured rather than assumed:

  * the `@nid` is location-independent - the same hash comes back when
    the module is read from a different path;
  * the `@nid` is contract-independent - it did not move when a
    signature went from `(Int -> Int)` to `(Int -> (Int -> Int))`.

So the nid is IDENTITY and the type plus the effect row is the
CONTRACT, and a diff separates "this name is gone" from "this name
changed" without heuristics.

WHAT IS DELIBERATELY DROPPED. `#calls=` is the graph BEHIND the effect
row, not part of the promise - a function may reorganise its callees
freely. `file:line:col` is dropped because a contract does not move when
a declaration moves down its file, and because the path a row carries
comes from module resolution: it reads
`<prefix>/.axiom-bin/../stdlib/Err.ax` and so embeds the compiler's
install location (`docs/agent-harness.md` records this as the
portability hazard it is).

WHAT IS DELIBERATELY KEPT. `Sys/Platform.<target>.ax` folds to one
name. The three platform files declare the same names, and folding them
means the baseline is one file that all three CI legs must agree with -
a stronger claim than the per-name comparison `check-stdlib-api.sh`
already makes, and one that goes red on the leg that disagrees.
"""
import sys, re, os, subprocess

# The modules the surface covers. Named rather than globbed, for the
# reason `scripts/check-stdlib-api.sh` gives: `Sys/Platform` has one
# file per target declaring the same names, so a glob prints it three
# times and the choice of which to carry is a decision worth seeing.
MODULES = ("Agent/Tags Err Fallible Ffi Fmt Html Http IO Intern Job Json Map Mem Path Pre Rpc Show Str Sys "
           "Sys/Platform.darwin Test Tui/Edit Tui/Keys Tui/Term Utf8 Vec").split()

# Visibility is not in AXSYM - `symbols` has no `pub` field - so the
# public set is read from the source, with the rule
# `scripts/check-stdlib-api.sh` already uses for the generated
# reference. The two must agree about what "public" means.
PUB = re.compile(r'^\(pub (?::: |macro |data |struct |trait |type )\(?([A-Za-z0-9_!?*+/<>=-]+)')
EFFECT = re.compile(r'^\(effect ([A-Za-z0-9_]+)')
ROW = re.compile(r'^(\S+) (\S+) (\S+) "(.*?)"(.*)$')
# Everything AXSYM emits that a CALLER can depend on. Measured over the
# whole surface rather than guessed: the keys that appear are
# `#effects=`, `#effect=`, `#effects-overapprox`, `#effect-params=`,
# `#of=`, `#fields=`, `#effects-incomplete`, `#ctors=` and `#methods=`.
#
# `#fields=` and `#methods=` are here because leaving them out was a
# hole: a struct row without them is `"struct Error"` and nothing else,
# so reordering `Error`'s fields, changing one's type, or deleting a
# trait method all read as NO DIFFERENCE. Field ORDER is contract in
# this language - a `struct` is positional and `cast` reinterprets a
# block - which is the miscompile `AX3044` was built for, one module
# along.
#
# Three keys are deliberately out. `#effect=` is the author's AXTAG
# re-emitted, and since 0.3.0 `AX3010` refuses a claim the body does
# not perform - so it is a subset of `#effects=` and carrying it would
# report a tag added over an unchanged body as a breaking change.
# `#effects-overapprox` and `#effects-incomplete` are states of the
# ANALYSIS, not promises to a caller.
CONTRACT_META = ("#effects=", "#ctors=", "#of=", "#effect-params=",
                 "#fields=", "#methods=")

# Carried in the row so the baseline RECORDS it, and stripped by
# `contract()` so it is not compared.
#
# `;@axiom:deprecated(...)` is how a name is retired gracefully: it
# needs no compiler change - the AXTAG key namespace is open, unknown
# keys already parse, are recorded and are re-emitted on the AXSYM line
# as `#deprecated=`. What it gives this gate is the one thing a
# removal rule needs: evidence that the name was marked BEFORE the
# release that removes it, which is exactly what "the baseline carried
# it" means.
#
# It must not be contract. If it were, ADDING a deprecation notice
# would read as a signature change and be refused as breaking - which
# would make the graceful path the forbidden one.
ANNOTATION_META = ("#deprecated=",)

# A stream that stops producing reads as agreement, so it is floored.
# 407 rows on 2026-08-26; the floor is under it with room, and it is a
# floor rather than a count so adding a public name does not fail here.
ROW_FLOOR = 380


class Fatal(Exception):
    """The tree did not compile, or `symbols` answered nothing.

    Kept distinct from every comparison result on purpose. A negative
    probe that BREAKS THE BUILD otherwise satisfies a gate that only
    asks for a non-zero exit - which is how a check comes to pass for
    the wrong reason, the defect this repository produces most.
    """


def public_names(root):
    names = set()
    for m in MODULES:
        path = os.path.join(root, m + ".ax")
        if not os.path.exists(path):
            raise Fatal(f"module named in MODULES is not in the tree: {path}")
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                g = PUB.match(line) or EFFECT.match(line)
                if g:
                    names.add(g.group(1))
    return names


def normalise(text, root, names):
    root = os.path.realpath(root)
    rows = []
    for line in text.split("\n"):
        g = ROW.match(line)
        if not g:
            continue
        kind, name, loc, ty, rest = g.groups()
        if name not in names:
            continue
        if loc == "-":
            module = "-"                      # a compiler builtin has no file
        else:
            real = os.path.realpath(loc.split(":")[0])
            module = ("stdlib/" + os.path.relpath(real, root)
                      if real.startswith(root + os.sep) else real)
            module = re.sub(r'Sys/Platform\.[A-Za-z0-9_-]+\.ax$', 'Sys/Platform.ax', module)
        # Metadata is split on the ` #` that starts each key, NOT on
        # whitespace: a value can contain spaces. `#methods=` carries a
        # method's TYPE, so `show:(a -> String)` tokenises into three
        # words and a whitespace split silently truncates it to
        # `#methods=show:(a` - which compares equal for every change
        # after the first token.
        nid = next((t for t in rest.split() if t.startswith("@")), "-")
        found = [m.strip() for m in re.findall(r'#[a-z-]+(?:=[^#]*)?', rest)]
        meta = sorted(m for m in found if m.startswith(CONTRACT_META))
        note = sorted(m for m in found if m.startswith(ANNOTATION_META))
        rows.append(f'{kind} {name} {module} {nid} "{ty}"'
                    + "".join(" " + m for m in meta)
                    + "".join(" " + m for m in note))
    return sorted(set(rows))


def surface(root, axiom, work):
    """The current public surface, as normalised rows."""
    entry = os.path.join(work, "surface-entry.ax")
    with open(entry, "w", encoding="utf-8") as fh:
        for m in MODULES:
            fh.write("(import %s)\n" % m.replace("/", ".").replace(".darwin", ""))
        fh.write("(fn (main) 0)\n")
    env = dict(os.environ, AXIOM_STDLIB=root)
    r = subprocess.run([axiom, "symbols", "--diagnostic-format=ai", entry],
                       capture_output=True, env=env, cwd=work)
    if r.returncode != 0:
        # `symbols` folds every failure into exit 1 and prints no table
        # (CHANGELOG.md, 0.3.0). An empty stream must never read as
        # "every symbol was removed".
        raise Fatal("symbols exited %d: %s"
                    % (r.returncode, r.stderr.decode("utf-8", "replace").strip()[:300]))
    rows = normalise(r.stdout.decode("utf-8", "replace"), root, public_names(root))
    if len(rows) < ROW_FLOOR:
        raise Fatal(f"the surface is {len(rows)} rows, floor is {ROW_FLOOR}")
    return rows


def identity(row):
    f = row.split()
    return (f[0], f[1])          # kind and name; builtins carry no nid


def contract(row):
    """Everything a caller can depend on: the type and the contract
    metadata, with the annotations stripped."""
    tail = row.split(" ", 4)[4]
    for m in re.findall(r'\s#[a-z-]+(?:=\S*)?', tail):
        if m.strip().startswith(ANNOTATION_META):
            tail = tail.replace(m, "")
    return tail


def deprecated(row):
    return any(t.startswith(ANNOTATION_META) for t in row.split())


def effects(text):
    m = re.search(r'#effects=(\S+)', text)
    return set(m.group(1).split(",")) if m else set()


# `RETIRED` is deliberately absent: a name the previous release
# shipped marked `;@axiom:deprecated` was announced, and removing it is
# the notice being honoured rather than a surprise.
BREAKING = ("REMOVED", "CHANGED", "WIDENED")


def compare(base, cur):
    b = {identity(r): r for r in base}
    c = {identity(r): r for r in cur}
    out = []
    for k in sorted(set(b) | set(c)):
        if k not in c:
            # A name the BASELINE already marked deprecated shipped with
            # that notice in a previous release, which is the whole
            # point of the notice. Removing it is not a surprise, and it
            # needs no line in `compat/BREAKING`.
            kind = "RETIRED" if deprecated(b[k]) else "REMOVED"
            out.append((kind, k, contract(b[k]), ""))
        elif k not in b:
            out.append(("ADDED", k, "", contract(c[k])))
        elif contract(b[k]) != contract(c[k]):
            bt, ct = contract(b[k]), contract(c[k])
            be, ce = effects(bt), effects(ct)
            if ce > be:
                kind = "WIDENED"
            elif be > ce:
                kind = "NARROWED"
            else:
                kind = "CHANGED"
            out.append((kind, k, bt, ct))
    return out


def uncovered(root, axiom, work):
    """Public names the symbol stream does not carry.

    `symbols` HAD no arm for `TAG_D_MACRO` and none for `TAG_D_IMPL`,
    and its `TAG_D_EFFECT` arm registered the effect's OPERATIONS
    rather than the effect. So twelve macros - `println` and `format`
    among them - and one effect declaration were public API that no
    gate over this stream could see. CLOSED 2026-08-26: a macro is a
    kind-`M` row now and an effect declaration carries its own row, so
    `compat/UNCOVERED` is empty and is compared as an empty set. It
    stays load-bearing: the first thing to exercise a macro REMOVAL,
    Html's `for`/`forInt` on 2026-09-03, was refused by check-compat
    until two `M` rows were declared in `compat/BREAKING`.

    That is a hole in the contract, and it is reported as a SET rather
    than a count: a fourteenth invisible name must go red, and the list
    shrinking to nothing is what closing the hole looks like.
    """
    rows = surface(root, axiom, work)
    seen = {r.split()[1] for r in rows}
    return sorted(public_names(root) - seen)


# --- the sentinel census ------------------------------------------
#
# WHAT THIS COUNTS, AND WHY IT STOPPED COUNTING PROSE.
#
# `docs/error-model.md` sizes the `-errno`/`-1` -> `Result` migration and
# tells the reader to RECOMPUTE rather than quote. This is the
# recomputation, and it is now derived from the DECLARED TYPE and the
# BODY. It used to be derived from the doc-comment: a public function
# whose comment block matched
#
#     -errno|answers 0, or|or `-1`|, or -1|negative errno|a negative/errno
#
# was counted. That metric was audited on 2026-08-30 and every one of the
# findings below is why it is gone.
#
#   * IT REWARDED SILENCE. `netListen` (stdlib/Sys.ax) forwards
#     `__syscall3` and answers a raw fd-or-negative-errno. It was
#     UNCOUNTED, because nobody had written the sentence. Writing the
#     house line above it would have taken stdlib/Sys.ax from 3 to 4 and
#     failed `check-compat.sh` for a commit that changed no contract. A
#     metric that goes red when you document an existing sentinel is a
#     metric that asks you not to.
#
#   * IT UNDERCOUNTED BY ROUGHLY FOUR TIMES. The prose rule found 13
#     public functions over 7 modules. Reading bodies finds 38 over 7 -
#     29 that answer a raw syscall result and 9 that answer -1 for "not
#     found" - and stdlib/Sys.ax alone goes from 3 to 26.
#
#   * ONE ALTERNATIVE MATCHED NOTHING AT ALL. `answers 0, or` appears
#     nowhere in stdlib/ (the tree writes "Answers"), so the pattern's
#     only 0-sentinel arm was dead, which is why every 0-sentinel in the
#     library was invisible to it.
#
#   * THE BLOCK WAS "WHATEVER IS ABOVE". The walk climbed through blank
#     lines and `; ---` section banners, so a declaration inherited the
#     banner's prose. That produced the one false positive the old
#     baseline recorded: `sysRandomNum`, which is
#     `(pub fn (sysRandomNum) 33554932)` - the getentropy SYSCALL NUMBER,
#     a constant with no bad path - counted because the "Entropy" banner
#     twelve lines above describes getentropy's `0 or -errno` contract.
#     `docs/error-model.md` and the old `compat/SENTINELS` header both
#     inherited that error and called it one of five failures.
#
#   * THE BLOCK WAS JOINED IN REVERSE SOURCE ORDER, so a phrase spanning
#     a line break could never match. Two exist in the tree today.
#
#   * THE `Result` SKIP WAS A SUBSTRING TEST on the declaration line, not
#     a reading of the return type, and there was no `Option` skip at
#     all - so porting one of the nine absence functions to `(Option Int)`
#     in place would have left the count exactly where it was, which is
#     the regression the `Result` skip was added to prevent.
#
# THE RULE NOW. A public declaration is counted when BOTH hold:
#
#   1. Its declared RETURN carries no channel. The return is the last
#      element of the top-level arrow (or the whole type for a nullary),
#      PARSED rather than substring-matched, and it must not be
#      `(Result ...)`, `(Option ...)` or `Bool`. Reading the type this way
#      is what makes an in-place port to either channel lower the count.
#
#   2. Its body answers a designated value: a `(- 0 n)` literal in RETURN
#      position, or an unwrapped forward of a `__syscallN` / `platform*`
#      primitive.
#
# and it is classified `failure` when the body reaches a syscall and
# `absence` otherwise. That split is the one `docs/error-model.md`
# ERR-REC-3 draws: `Result` is for failure, and "not found" is absence,
# which wants `Option`. Of the nine absence rows, two are in stdlib/Str.ax
# - which CANNOT import `Err`, because `Err` imports `Str` - so counting
# them as `Result` debt was counting work that cannot be done.
#
# WHAT THE RULE DELIBERATELY DOES NOT COUNT, each measured against a real
# declaration that the prose rule got wrong or would have:
#
#   a named CONSTANT - `fallibleSkipped` and `intMin` are Int::MIN, and
#     `pollReadFilter` is -1 because that is EVFILT_READ. Their bodies are
#     a literal with no branch to be the bad path of;
#   a value the CALLER supplies - `symTagFrom` and `netAddrText` each
#     contain a `(- 0 1)` that is the seed ARGUMENT of a fold, and each
#     answers a String. Counting them puts a return-channel migration's
#     name on a parameter, so the enclosing form's head is read: `if`,
#     `match` or a block is an answer, any other name is an argument to
#     it;
#   a call that never comes BACK - `sysExitWith`;
#   a syscall that cannot FAIL - `getpid`, named rather than guessed.
#
# ONE HOP THROUGH A THIN PRIVATE FORWARD, and only a thin one. The public
# name is what a caller depends on, but the sentinel is often produced a
# level down in a private worker: `pathLastSlash` is
# `(pathLastSlashFrom p ...)` and every -1 is in the helper; `internFind`
# is `internFindFrom`. A body with a BRANCH of its own is consuming that
# sentinel rather than passing it on - `pathExt` is
# `(if (< (pathExtIndex p) 0) "" ...)` and answers a String, `mapGet`
# substitutes a caller-supplied default - and those are the migration's
# beneficiaries, not its subjects.
#
# WHAT IT STILL DOES NOT REACH, stated rather than left to be found:
#   * the literal-`0` sentinel. `vecGet`, `vecPop`, `vecLast`, `strByte`,
#     `jsonGet` and `jsonArrGet` answer 0 for absence, and telling that 0
#     from a computed 0 needs the guard read, not the literal;
#   * 114 public MACROS, among them `println` and `eprintln`, whose value
#     is `writeStr`'s bytes-or-errno Int, with 804 expansions in the tree.
#     `PUB` above already matches `macro`; this census does not use it;
#   * members of `pub extern`, `pub trait` and `effect` declarations,
#     which are public and are not `(pub :: ` at column 0.
# Together those are about 21% of the public surface. The number below is
# a floor on the migration, and it is a floor that is now derived from
# what the code DOES.
SENTINEL_DECL = re.compile(r'^\(pub :: ([A-Za-z0-9_!?*+/<>=-]+) (.*)\)\s*$')
SENTINEL_NEG = re.compile(r'\(- 0 \d+\)')
SENTINEL_SYSCALL = re.compile(r'__syscall\d|platform[A-Z]\w*|__winapi')
SENTINEL_BRANCH = re.compile(r'\((?:if|match)[ \n]')
SENTINEL_NORETURN = re.compile(r'sysExit\b|sysExitNum|ExitProcess')
SENTINEL_INFALLIBLE = re.compile(r'sysGetPidNum|sysGetPpidNum')
# A NAME WHOSE CONTRACT IS NOT WHAT ITS BODY'S SYNTAX SAYS, on the
# `SENTINEL_INFALLIBLE` precedent one line above.
#
# `platformExitWith` exits the process, and on NO target does it hand a
# caller an outcome:
#
#   * `stdlib/Sys/Platform.windows.ax:502` is `(winExitProcess code)`,
#     which does not return - and Windows is the only target that
#     implements it, because it is the only one with no syscall ABI;
#   * darwin, freebsd and the two linux files answer `(- 0 78)`,
#     -ENOSYS, under `;@axiom:pure`, and their own comment says the
#     call is "never reached - `Sys.ax` tests this capability first";
#   * its one caller, `sysExitWith` at `stdlib/Sys.ax:303`, puts it in
#     STATEMENT position inside a `{ ... 0 }` that answers `0`, so the
#     value is discarded whatever it is.
#
# The census reads the DARWIN file, so `SENTINEL_NORETURN` - which
# already knows `ExitProcess` - never sees the noreturn implementation,
# and the ENOSYS stub reads as an errno a caller could act on. None
# can: a `(Result Int Error)` here would allocate on the process-exit
# path, break the `pure` claim, and encode an outcome nobody observes.
# This is the `sysRandomNum` shape - a constant in a body read as a
# sentinel - surviving the rewrite that removed `sysRandomNum`, because
# unlike that one it really is a negative in return position, so only a
# fact about its CALLER settles it.
SENTINEL_NO_OBSERVER = ("platformExitWith",)
# `(r (__syscall3 ...))` - a binder whose value is a raw syscall call, so
# that returning `r` counts as returning the syscall's result.
SENTINEL_SYSCALL_BOUND = re.compile(
    r'\(([a-z][A-Za-z0-9_]*) \((?:__syscall\d|platform[A-Z]\w*|__winapi)')


def sentinel_return_type(ty):
    """The declared RETURN: the last element of the top-level arrow, or
    the whole type for a nullary. Parsed, because a substring test on the
    line is what let four `Err.ax` declarations be skipped for mentioning
    `Result` in a PARAMETER."""
    ty = ty.strip()
    if not ty.startswith("(-> "):
        return ty
    inner, depth, parts, cur = ty[4:-1], 0, [], ""
    for ch in inner:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == " " and depth == 0:
            if cur:
                parts.append(cur)
                cur = ""
        else:
            cur += ch
    if cur:
        parts.append(cur)
    return parts[-1] if parts else ty


# WHAT COUNTS AS A CHANNEL, AND THE SECOND REASON A RETURN HAS NONE.
# Two different facts land on the same answer, and both are reasons not
# to count the row.
#
#   * `(Result ...)` and `(Option ...)` carry the outcome in the type
#     already: the row is PORTED, not debt.
#   * every other return except `Int` cannot hold a `(- 0 n)` AT ALL,
#     because the checker refuses it. Measured 2026-09-03:
#
#         (pub :: mkPair (-> Int Pair))
#         (pub fn (mkPair n) (if (< n 0) (- 0 1) (Pair n n)))
#         AX3004: type mismatch: expected Int, found Pair
#
#     so a `Bool`, `String`, `Char`, `Float`, type variable, `struct`
#     or `data` return has no integer sentinel channel and never had
#     one. `Bool` was already skipped for exactly this reason without
#     saying so; the rule is now stated once and covers the rest.
#
# THIS COST TWO PHANTOM ROWS IN `Tui/Term`, and they are why the rule
# is here rather than a note. `mkKeyIn` answers `KeyIn` and `keyNext`
# answers `KeyEv` - structs - and both were counted as `absence` debt
# somebody could pay. Neither can be. The `(- 0 1)` the census found in
# `mkKeyIn` is the `pfd` FIELD, the descriptor-or-`-1` that file's own
# comment describes; the one in `keyNext` is the TIMEOUT ARGUMENT to
# `keyInFill`, meaning "block". Neither is an answer, and no
# `(Option Int)` could have replaced either.
#
# THE IMPRECISION UNDERNEATH IS `in_return_position`, WHICH IS NOT
# TRANSITIVE: it climbs to the enclosing form, sees `if`, and stops
# without asking whether THAT `if` is an answer or an argument. Fixing
# it there is the obvious move and it is WRONG. Measured 2026-09-03, a
# climb that keeps going until it meets a non-`if`/`match`/`{` head
# drops THIRTEEN rows, including `strFindByte`, `utf8DecodeAt` and
# `keyStrEnd` - the realest absence sentinels in the tree - because
# `let` and `fn` are transparent to return position and that climb
# treats them as opaque. Under-reporting is the failure this census was
# rewritten to end (see the header of `compat/SENTINELS`), so the TYPE
# rule is what lands and the position rule stays as it is, named here
# so the next reader does not re-derive the same wrong fix.
#
# A `(type Port = Int)` alias WOULD escape this, since an alias is
# expanded before checking while the declaration still says `Port`.
# There are none - measured 2026-09-03, zero `(type ...)` declarations
# in `stdlib/` - and this paragraph is what the first one has to read.
def sentinel_has_channel(ret):
    r = ret.strip()
    if r.startswith("(Result") or r.startswith("(Option"):
        return True
    return r != "Int"


def sentinel_body(lines, name):
    """The text of `name`'s definition, to its closing paren."""
    pat = re.compile(r'^\(?(?:pub )?fn \(' + re.escape(name) + r'[ )]')
    for i, l in enumerate(lines):
        if pat.match(l):
            depth, out = 0, []
            for l2 in lines[i:]:
                out.append(l2)
                depth += l2.count("(") - l2.count(")")
                if depth <= 0:
                    break
            return "\n".join(out)
    return None


def in_return_position(body, start):
    """Is the form beginning at `start` an ANSWER of `body` rather than an
    argument to something? Decided by climbing to the enclosing form and
    asking what its head is."""
    depth, j, head = 0, start - 1, None
    while j >= 0:
        ch = body[j]
        if ch == ')':
            depth += 1
        elif ch == '(':
            if depth == 0:
                k = j + 1
                while k < len(body) and body[k] in ' \n':
                    k += 1
                e = k
                while e < len(body) and body[e] not in ' \n()':
                    e += 1
                head = body[k:e]
                break
            depth -= 1
        elif ch == '{' and depth == 0:
            head = '{'
            break
        j -= 1
    return head in ('if', 'match', '{', None, '-')


def sentinel_returns(body):
    """Every `(- 0 n)` in RETURN position rather than argument position."""
    return [m for m in re.finditer(r'\(- 0 \d+\)', body)
            if in_return_position(body, m.start())]


def sentinel_syscall_returns(body):
    """Does a RAW SYSCALL RESULT reach this body's answer?

    Two routes, and the second is the one that costs a line. A syscall
    call can sit in return position itself (`netListen`), or its result
    can be bound and the BINDING returned - which is how
    `sysNowMonotonic` forwards `clock_gettime`'s errno:

        (let ((r (__syscall3 sysClockNum clockMonotonicId buf 0)))
          (if (< r 0) r (+ ...)))

    Measured while writing this: following only the first route moved
    `sysNowMonotonic` to `absence` along with `netPollSignalAt`, and it
    is not one - it answers `-errno` from the clock and `-ENOSYS` from
    the capability test. One route was a false positive at a population
    of two, which is the whole argument for following the binding.
    """
    hits = [m for m in SENTINEL_SYSCALL.finditer(body)
            if in_return_position(body, m.start())]
    for b in SENTINEL_SYSCALL_BOUND.finditer(body):
        name = b.group(1)
        for u in re.finditer(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'(?![A-Za-z0-9_])', body):
            if u.start() <= b.end():
                continue
            if in_return_position(body, u.start()):
                hits.append(u)
                break
    return hits


def sentinel_census(root):
    """{module: (failure_count, absence_count)}, from the body."""
    out = {}
    for m in MODULES:
        path = os.path.join(root, m + ".ax")
        if not os.path.exists(path):
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        fail = absent = 0
        for line in lines:
            mt = SENTINEL_DECL.match(line)
            if not mt:
                continue
            name, ty = mt.group(1), mt.group(2)
            if sentinel_has_channel(sentinel_return_type(ty)):
                continue
            body = sentinel_body(lines, name)
            if body is None:
                continue
            if not (SENTINEL_NEG.search(body) or SENTINEL_SYSCALL.search(body)) \
                    and not SENTINEL_BRANCH.search(body):
                for callee in sorted(set(re.findall(r'\(([a-z][A-Za-z0-9_]*)[ )]', body)) - {name}):
                    helper = sentinel_body(lines, callee)
                    if helper and (SENTINEL_NEG.search(helper) or SENTINEL_SYSCALL.search(helper)):
                        body = body + "\n" + helper
                        break
            if SENTINEL_NORETURN.search(body):
                continue
            if name in SENTINEL_NO_OBSERVER:
                continue
            neg = bool(sentinel_returns(body))
            sysc = SENTINEL_SYSCALL.search(body) and not SENTINEL_INFALLIBLE.search(body)
            # A LOOKUP WHOSE BODY HAPPENS TO CONTAIN A SYSCALL IS NOT A
            # FAILURE, and until 2026-09-01 it was counted as one because
            # `sysc` beat `neg` unconditionally.
            #
            # `netPollSignalAt` answers "the signal named by event `i`, or
            # a negative when that event is not a signal at all". Every
            # answer it writes on the bad path is a hand-written `(- 0 1)`;
            # the `__syscall3` in its Linux arm is a `read` whose result is
            # COMPARED and never returned. All five of its call sites read
            # it as a presence test - `315-signal-in-poll.ax:131` asserts
            # `< 0` for "a socket event is not read as a signal" - which is
            # ERR-REC-3's absence, wanting `Option` and not `Result`.
            #
            # So the tie-breaker is: both signals present, and the syscall
            # result never reaching the answer, means LOOKUP. It is narrow
            # by construction - a body with no `(- 0 n)` in return position
            # never reaches it, which is why `netAccept` is untouched - and
            # measured over `stdlib/` it moves exactly one row.
            if sysc and neg and not sentinel_syscall_returns(body):
                sysc = False
            if neg and not SENTINEL_BRANCH.search(body) and not sysc:
                continue
            if not (neg or sysc):
                continue
            if sysc:
                fail += 1
            else:
                absent += 1
        if fail or absent:
            out["stdlib/" + m + ".ax"] = (fail, absent)
    return out


def main(argv):
    if len(argv) < 4:
        sys.exit("usage: verify-compat.py {generate|compare} <axiom> <work> [args]")
    # Resolved before anything chdirs. `surface` runs the compiler with
    # `cwd` set to the work directory, so a relative path handed in from
    # a gate would be resolved against the wrong root - and would fail
    # as a missing file rather than as a wrong answer, which is the
    # better of the two but still not this tool's job to explain.
    cmd = argv[1]
    axiom = os.path.abspath(argv[2])
    work = os.path.abspath(argv[3])
    argv = argv[:4] + [os.path.abspath(a) for a in argv[4:]]
    try:
        if cmd == "generate":
            for row in surface(argv[4], axiom, work):
                print(row)
            return 0
        if cmd == "sentinels":
            for mod, (f, a) in sorted(sentinel_census(argv[4]).items()):
                print(f"{mod} {f} {a}")
            return 0
        if cmd == "modules":
            # Printed rather than duplicated in the gate: a second copy
            # of this list is a second thing to keep in step, and the
            # failure mode of that is silent.
            for m in MODULES:
                print("stdlib/" + m + ".ax")
            return 0
        if cmd == "uncovered":
            for name in uncovered(argv[4], axiom, work):
                print(name)
            return 0
        if cmd != "compare":
            sys.exit(f"unknown command {cmd!r}")
        with open(argv[4], encoding="utf-8") as fh:
            base = [l.rstrip("\n") for l in fh if l.strip()]
        if len(base) < ROW_FLOOR:
            raise Fatal(f"the baseline is {len(base)} rows, floor is {ROW_FLOOR}")
        cur = surface(argv[5], axiom, work)
    except Fatal as e:
        # Printed with this prefix and this exit status so the gate can
        # tell "the tree does not compile" from "the API changed". They
        # are different failures and only one of them is this gate's.
        print(f"FATAL: {e}")
        return 2
    diffs = compare(base, cur)
    breaking = 0
    for kind, (letter, name), was, now in diffs:
        print(f"  {kind} {letter} {name}")
        if was and now:
            print(f"      was: {was}")
            print(f"      now: {now}")
        if kind in BREAKING:
            breaking += 1
    print(f"{len(diffs)} difference(s), {breaking} breaking, over {len(cur)} public rows")
    return 1 if breaking else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
