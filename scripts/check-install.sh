#!/usr/bin/env bash
# `scripts/install.sh` is the one script strangers run, and nothing
# checked it.
#
# It is what `README.md` tells a newcomer to pipe into bash. It fetches
# an archive and a checksum, compares them, unpacks, installs, and
# proves the result works by building a program that imports the
# standard library. Every one of those steps was written carefully and
# none of them was ever executed by a gate - so the failure mode is the
# one this repository names most often: a check nobody has seen fail.
#
# WHAT IT SERVES. A release this script BUILDS: the compiler under
# test, the tree's `stdlib/`, and the three prose files, assembled the
# way `release.yml` assembles one, with its `.sha256` beside it, served
# over `python3 -m http.server` on the loopback. `install.sh` reaches
# it through `AXIOM_BASE_URL`, which exists for this and is documented
# in that script as not being a back door - it changes WHERE the
# archive comes from and nothing about what is then required of it.
#
# THE FOUR CASES, and three of them are the negative ones:
#
#   1. A well-formed release installs, and the installed compiler
#      builds and runs a program that imports the standard library
#      from a directory of its own.
#   2. A TAMPERED archive - one byte - is refused. This is the
#      assertion the whole download exists for.
#   3. A MISSING checksum file is refused rather than installed
#      unverified.
#   4. An archive with no `stdlib/` is refused, because a compiler
#      that cannot find its library is not an installation.
#
# And a probe on the gate itself: with `install.sh`'s comparison
# deleted in a copy, case 2 must stop being refused. A verification
# test that passes against an unverifying installer is testing nothing.
#
# THE DESTRUCTIVE HALF, cases 5-9, added 2026-09-26 after an audit
# installed into `--prefix "$HOME/."` and lost two files the string
# comparison had been written to protect. They plant files the
# installer did not put there - in a scratch HOME, never the real one -
# and require that every spelling of a protected directory is refused
# (5), that a directory of somebody else's is not replaced (6), that an
# upgrade replaces exactly what the ownership record lists (7), that an
# install from before the record is recognised by its shape (8), and
# that a release whose compiler fails leaves the working install in
# place (9). Each of the three guards is then removed in a copy of the
# installer and must be seen to stop refusing: the ownership check and
# the staged probe then cost the file they guard, and `$HOME/.` gets
# past the list - where the ownership check, the next guard down, is
# seen to catch it.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v curl >/dev/null || { echo "FAIL: curl is not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

case "$(uname -s)" in
  Darwin)  os=darwin ;;
  Linux)   os=linux ;;
  FreeBSD) os=freebsd ;;
  *) echo "FAIL: unsupported OS $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=aarch64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *) echo "FAIL: unsupported architecture $(uname -m)"; exit 1 ;;
esac
target="$os-$arch"

# --------------------------------------------------------------------
# WHETHER THIS HOST'S TARGET SHIPS AT ALL, and what to check if it does
# not.
#
# `release.yml` stopped building `linux-x86_64` on 2026-08-30 - the
# target is still supported and still runs this whole battery, only the
# prebuilt archive is gone - and `install.sh` therefore refuses that
# host with a build-from-source message instead of fetching a 404. On
# such a host the four cases below cannot run: there is no install path
# to exercise. What CAN be checked, and is, is that the refusal happens
# and says the right thing.
#
# The shipped list is read from `release.yml`'s matrix rather than
# repeated here, so this gate cannot disagree with the workflow it is
# describing. `scripts/check-release-targets.sh` holds that matrix and
# `install.sh`'s refusal list to each other.
# --------------------------------------------------------------------
release_yml="$repo_root/.github/workflows/release.yml"
[[ -f "$release_yml" ]] || { echo "FAIL: $release_yml is missing"; exit 1; }
shipped="$(sed -n 's/^ *- name: \([a-z0-9_]*-[a-z0-9_]*\) *$/\1/p' "$release_yml" | sort -u)"
[[ -n "$shipped" ]] || {
  echo "FAIL: no build-matrix targets found in release.yml - this gate reads that"
  echo "      list to know whether the host ships, and an empty read would make"
  echo "      it silently skip every case below"; exit 1; }

if ! printf '%s\n' "$shipped" | grep -qx "$target"; then
  echo "== this host's target ships no archive; the refusal is what is checked =="
  echo "   shipped: $(printf '%s ' $shipped)"
  set +e
  out="$(AXIOM_PREFIX="$work/prefix" bash "$repo_root/scripts/install.sh" --version 9.9.9 2>&1)"
  rc=$?
  set -e
  if (( rc == 0 )); then
    bad "install.sh exited 0 on $target, which publishes no archive - it would have 404ed"
  elif ! grep -q "no release binary for $target" <<<"$out"; then
    bad "install.sh refused $target without naming it"
    sed 's/^/     /' <<<"$out" | head -5
  elif ! grep -q "bootstrap-from-seed.sh" <<<"$out"; then
    bad "install.sh refused $target without telling the user how to build it"
    sed 's/^/     /' <<<"$out" | head -5
  else
    ok "install.sh refuses $target and points at bootstrap-from-seed.sh (exit $rc)"
  fi
  echo
  echo "check-install: $checks check(s) on a host whose target publishes no"
  echo "               archive. THE INSTALL PATH WAS NOT EXERCISED HERE - it is"
  echo "               exercised on every leg whose target does ship, and the"
  echo "               four cases below need an archive to install."
  exit $(( failed > 0 ))
fi

# A version that is not this repository's, so nothing here can pass by
# reaching a real release: `install.sh` builds `axiom-$V-$target` from
# it, and no such file exists anywhere but in `$work`.
V="9.9.9"
name="axiom-$V-$target"

serve="$work/serve"
mkdir -p "$serve"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Copy the TRACKED files under <dir> into <dest>, as the working tree
# holds them. The release workflow copies from a clean checkout, and a
# plain `cp -R` here also copied whatever else sat in the directory: a
# Finder `docs/.DS_Store` made the staged docs/ fail case 8's
# only-`.md` shape, a red no release could produce.
copy_tracked() {  # <dir> <dest>
  ( cd "$repo_root" && git ls-files -z -- "$1" | tar --null -T - -cf - ) \
    | tar -xf - -C "$2"
}

# Assemble a release into $serve. `--no-stdlib` omits `stdlib/` from
# the archive, for case 4.
assemble() {  # [--no-stdlib]
  local d="$work/stage/$name"
  rm -rf "$work/stage"; mkdir -p "$d/bin"
  cp "$axc" "$d/bin/axiom"
  [[ "${1:-}" == "--no-stdlib" ]] || copy_tracked stdlib "$d"
  cp "$repo_root/LICENSE" "$repo_root/README.md" "$repo_root/CHANGELOG.md" "$d/"
  [[ "${1:-}" == "--no-docs" ]] || copy_tracked docs "$d"
  ( cd "$work/stage" && tar -czf "$serve/$name.tar.gz" "$name" )
  sha_of "$serve/$name.tar.gz" > "$serve/$name.tar.gz.sha256.tmp"
  printf '%s  %s\n' "$(cat "$serve/$name.tar.gz.sha256.tmp")" "$name.tar.gz" \
    > "$serve/$name.tar.gz.sha256"
  rm -f "$serve/$name.tar.gz.sha256.tmp"
}

assemble
echo "== serving a release built from this tree =="
# The port is CHOSEN here rather than read back from the server. Asking
# the kernel for 0 and parsing `http.server`'s banner works until the
# banner's wording moves, and it did: the first version of this gate
# reported "the local server never reported a port" against a server
# that was serving. Binding a port Python just proved free is one
# syscall of race and no parsing.
port="$(python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()')"
[[ "$port" =~ ^[0-9]+$ ]] || { echo "FAIL: could not choose a port"; exit 1; }
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$serve" \
  >"$work/http.log" 2>&1 &
http_pid=$!
trap 'kill "$http_pid" 2>/dev/null || true; rm -rf "$work"' EXIT
base="http://127.0.0.1:$port"
# Wait for it to answer rather than for it to print: what matters is
# that a fetch works, and that is what the loop asks.
up=0
for _ in $(seq 1 100); do
  if curl -fsS --proto '=http' -o /dev/null "$base/$name.tar.gz.sha256" 2>/dev/null; then
    up=1; break
  fi
  sleep 0.1
done
(( up )) || { echo "FAIL: the local server never answered on $base"; cat "$work/http.log"; exit 1; }
ok "a $(wc -c <"$serve/$name.tar.gz" | tr -d ' ')-byte release on $base"

install_run() {  # <prefix> [installer]
  local prefix="$1" script="${2:-$repo_root/scripts/install.sh}"
  set +e
  AXIOM_BASE_URL="$base" AXIOM_PREFIX="$prefix" \
    bash "$script" --version "$V" >"$work/install.log" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# --------------------------------------------------------------------
echo
echo "== 1. a well-formed release installs and the compiler works =="
# --------------------------------------------------------------------
rc="$(install_run "$work/prefix")"
if (( rc == 0 )) && [[ -x "$work/prefix/bin/axiom" ]] && [[ -d "$work/prefix/stdlib" ]]; then
  ok "installed to \$work/prefix, bin/ and stdlib/ present"
else
  bad "install exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -10
fi

# `docs/` REACHES THE INSTALLED PREFIX, and this is asserted rather than
# assumed because the README became a front door in 0.6.0: it points at
# `docs/reference.md` and the rest instead of restating them, so an
# archive that carries the pointer and not the target leaves an
# installed user strictly worse off than before the README was cut.
#
# The count is a floor, not an equality. Documents get added; a gate
# that demanded the exact number would go red on every new one and
# teach whoever hit it to edit the number rather than think. Zero, or
# one, is the failure this catches: a `cp` that silently copied
# nothing.
doc_n=$(find "$work/prefix/docs" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ -d "$work/prefix/docs" ]] && (( doc_n >= 8 )); then
  ok "docs/ reached the prefix, $doc_n documents"
else
  bad "the installed prefix has $doc_n document(s) under docs/; the floor is 8"
  echo "     the README points at these; shipping it without them is a dead link"
fi
# install.sh proves this itself, and it is asserted again here from
# outside: the claim is that the INSTALLED compiler works, and a gate
# that trusted the installer's own report would be reading the thing
# under test.
probe="$work/probe"
mkdir -p "$probe"
cat > "$probe/p.ax" <<'AX'
(import IO (writeStr))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (writeStr 1 "installed\n")
    7
  }
)
AX
set +e
( cd "$probe" && unset AXIOM_STDLIB AXIOM_PATH
  PATH="$work/prefix/bin:$PATH" axiom run p.ax ) >"$work/probe.log" 2>&1
prc=$?
set -e
if (( prc == 7 )) && grep -q installed "$work/probe.log"; then
  ok "the installed compiler ran a program that imports the stdlib (exit $prc)"
else
  bad "the installed compiler answered $prc"
  sed 's/^/     /' "$work/probe.log" | tail -5
fi

# --------------------------------------------------------------------
echo
echo "== 2. one tampered byte is refused =="
# --------------------------------------------------------------------
# The archive is corrupted AFTER its checksum was published, which is
# what a tampered mirror looks like.
cp "$serve/$name.tar.gz" "$work/good.tar.gz"
printf 'x' >> "$serve/$name.tar.gz"
rc="$(install_run "$work/prefix2")"
if (( rc != 0 )) && grep -q "checksum mismatch" "$work/install.log"; then
  ok "refused with a checksum mismatch (exit $rc)"
else
  bad "a tampered archive exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -6
fi
[[ -e "$work/prefix2/bin/axiom" ]] && bad "it installed anyway" \
                                   || ok "and installed nothing"

# --------------------------------------------------------------------
echo
echo "== the probe on this gate: an installer that does not verify =="
# --------------------------------------------------------------------
# With the comparison deleted, case 2 must stop being refused -
# otherwise something OTHER than the checksum was rejecting the
# tampered archive and case 2 proves nothing about verification.
sed 's/^\[\[ "\$want" == "\$got" \]\].*/true/' \
  "$repo_root/scripts/install.sh" > "$work/unverifying.sh"
if cmp -s "$repo_root/scripts/install.sh" "$work/unverifying.sh"; then
  bad "the ablation changed nothing - the line it targets has moved"
else
  rc="$(install_run "$work/prefix3" "$work/unverifying.sh")"
  if grep -q "checksum mismatch" "$work/install.log"; then
    bad "the unverifying copy still reported a checksum mismatch"
  else
    ok "with the comparison deleted the tampered archive is not refused for it"
  fi
fi
cp "$work/good.tar.gz" "$serve/$name.tar.gz"

# --------------------------------------------------------------------
echo
echo "== 3. a missing checksum is refused, not installed unverified =="
# --------------------------------------------------------------------
mv "$serve/$name.tar.gz.sha256" "$work/sums.away"
rc="$(install_run "$work/prefix4")"
if (( rc != 0 )) && grep -q "unverified" "$work/install.log"; then
  ok "refused: the archive published no checksum (exit $rc)"
else
  bad "a release with no checksum exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -6
fi
mv "$work/sums.away" "$serve/$name.tar.gz.sha256"

# --------------------------------------------------------------------
echo
echo "== 4. an archive with no stdlib/ is refused =="
# --------------------------------------------------------------------
assemble --no-stdlib
rc="$(install_run "$work/prefix5")"
if (( rc != 0 )) && grep -q "stdlib" "$work/install.log"; then
  ok "refused: a compiler with no standard library is not an installation (exit $rc)"
else
  bad "an archive with no stdlib/ exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -6
fi

# --------------------------------------------------------------------
# THE DESTRUCTIVE HALF. Everything below plants files the installer
# must not delete and asks it to install on top of them - so every
# directory involved is under `$work`, INCLUDING the home directory:
# `HOME` is pointed at a scratch directory for each run, because the
# refusal under test is "this prefix is your home", and a regression
# in it must cost a sentinel file, never a real one.
# --------------------------------------------------------------------
home_run() {  # <home> <prefix> [installer] - like install_run, with HOME set
  local home="$1" prefix="$2" script="${3:-$repo_root/scripts/install.sh}"
  set +e
  HOME="$home" AXIOM_BASE_URL="$base" AXIOM_PREFIX="$prefix" \
    bash "$script" --version "$V" >"$work/install.log" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

plant_home() {  # <dir>: a home directory with two files nobody installed
  rm -rf "$1"
  mkdir -p "$1/bin" "$1/docs"
  echo "not the installer's" > "$1/bin/keep-me"
  echo "not the installer's" > "$1/docs/keep-me.md"
}

sentinels_ok() {  # <dir>
  [[ -f "$1/bin/keep-me" && -f "$1/docs/keep-me.md" ]]
}

# Case 4 left a release with no stdlib/ on the server; every case below
# needs one the installer would accept, so that a refusal can only be
# the one under test.
assemble

# --------------------------------------------------------------------
echo
echo "== 5. every spelling of the home directory is the home directory =="
# --------------------------------------------------------------------
# The audit's reproduction was `--prefix "$HOME/."`: refused as "$HOME",
# accepted with the dot, and both sentinels gone. Each spelling below
# names the same directory; each must be refused, and nothing deleted.
fake_home="$work/home"
plant_home "$fake_home"
ln -s "$fake_home" "$work/homelink"
for spelling in "$fake_home" "$fake_home/" "$fake_home/." "$fake_home/./" \
                "$fake_home//" "$fake_home/bin/.." "$fake_home/nowhere/.." \
                "$work/homelink" "$work/homelink/." "$work/./home"; do
  rc="$(home_run "$fake_home" "$spelling")"
  shown="${spelling#"$work"/}"
  if (( rc != 0 )) && grep -qF "which is $fake_home" "$work/install.log" && sentinels_ok "$fake_home"; then
    ok "\$work/$shown is refused as the home directory, and both sentinels survive"
  else
    bad "\$work/$shown: exit $rc, sentinels $(sentinels_ok "$fake_home" && echo intact || echo DELETED)"
    sed 's/^/     /' "$work/install.log" | tail -4
    plant_home "$fake_home"
  fi
done

# --------------------------------------------------------------------
echo
echo "== 6. a directory of somebody else's is not replaced =="
# --------------------------------------------------------------------
# A prefix no list protects can still hold things: here, a `bin/` with
# a tool of the user's own. With no record of an earlier install and
# not the shape of one, the installer must refuse before it deletes.
tools="$work/tools"
mkdir -p "$tools/bin"
echo "#!/bin/sh" > "$tools/bin/mytool"
rc="$(home_run "$fake_home" "$tools")"
if (( rc != 0 )) && grep -q "nothing records" "$work/install.log" && [[ -f "$tools/bin/mytool" ]]; then
  ok "a prefix whose bin/ holds a stranger's file is refused, and the file survives"
else
  bad "a prefix with an unrelated bin/ exited $rc; mytool $([[ -f "$tools/bin/mytool" ]] && echo survived || echo DELETED)"
  sed 's/^/     /' "$work/install.log" | tail -4
fi
# The same prefix with bin/ empty but a README.md of its own: prose
# files count as an earlier install's only beside its `bin/axiom`.
rm -rf "$tools"; mkdir -p "$tools"; echo "my project" > "$tools/README.md"
rc="$(home_run "$fake_home" "$tools")"
if (( rc != 0 )) && grep -q "already has README.md" "$work/install.log" \
   && [[ "$(cat "$tools/README.md")" == "my project" ]]; then
  ok "a prefix with a README.md of its own is refused, and the README survives"
else
  bad "a prefix with its own README.md exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -4
fi

# --------------------------------------------------------------------
echo
echo "== 7. the ownership record: an upgrade replaces, a stranger stops it =="
# --------------------------------------------------------------------
# Case 1 installed into `$work/prefix`, so it has a record. Installing
# again is the upgrade path and must succeed; a file dropped into its
# `bin/` afterwards is not in the record and must stop the next one.
if [[ -f "$work/prefix/.axiom-install" ]] && grep -qx 'file bin/axiom' "$work/prefix/.axiom-install"; then
  ok "case 1's install wrote .axiom-install, listing bin/axiom"
else
  bad "case 1's install left no .axiom-install naming bin/axiom"
fi
rc="$(home_run "$fake_home" "$work/prefix")"
if (( rc == 0 )) && "$work/prefix/bin/axiom" --version >/dev/null 2>&1; then
  ok "reinstalling over a recorded install succeeds (the upgrade path)"
else
  bad "reinstalling over a recorded install exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -4
fi
echo "mine" > "$work/prefix/bin/extra"
rc="$(home_run "$fake_home" "$work/prefix")"
if (( rc != 0 )) && grep -q "bin/extra" "$work/install.log" && [[ -f "$work/prefix/bin/extra" ]]; then
  ok "a file the record does not list is named, and the install refused around it"
else
  bad "an unrecorded bin/extra did not stop the install (exit $rc)"
  sed 's/^/     /' "$work/install.log" | tail -4
fi
rm -f "$work/prefix/bin/extra"

# --------------------------------------------------------------------
echo
echo "== 8. an install from before the record is recognised by its shape =="
# --------------------------------------------------------------------
# Every install made before 2026-09-26 has no `.axiom-install`. Its
# shape - bin/ holding only `axiom`, stdlib/ only `.ax`, docs/ only
# `.md` - is what lets it be upgraded rather than stranded.
cp -R "$work/prefix" "$work/legacy"
rm -f "$work/legacy/.axiom-install"
rc="$(home_run "$fake_home" "$work/legacy")"
if (( rc == 0 )) && [[ -f "$work/legacy/.axiom-install" ]]; then
  ok "an unrecorded install of the old shape is upgraded, and gains a record"
else
  bad "an unrecorded install of the old shape exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -4
fi

# --------------------------------------------------------------------
echo
echo "== 9. a release whose compiler does not work leaves the old one =="
# --------------------------------------------------------------------
# The archive is well-formed and correctly checksummed; its compiler
# is a script that fails. The install must refuse it AND the working
# install already in the prefix must be untouched - the property that
# staging exists for. Before it, the old tree was deleted first.
assemble
printf '#!/bin/sh\nexit 3\n' > "$work/broken-axiom"
chmod +x "$work/broken-axiom"
( d="$work/stage/$name"; cp "$work/broken-axiom" "$d/bin/axiom"
  cd "$work/stage" && tar -czf "$serve/$name.tar.gz" "$name" )
printf '%s  %s\n' "$(sha_of "$serve/$name.tar.gz")" "$name.tar.gz" > "$serve/$name.tar.gz.sha256"
cp -R "$work/prefix" "$work/kept"
rc="$(home_run "$fake_home" "$work/kept")"
if (( rc != 0 )) && grep -q "Nothing was installed" "$work/install.log" \
   && cmp -s "$work/kept/bin/axiom" "$work/prefix/bin/axiom" \
   && "$work/kept/bin/axiom" --version >/dev/null 2>&1 \
   && [[ -z "$(ls -A "$work/kept" | grep '^\.axiom-\(stage\|old\)\.' || true)" ]]; then
  ok "refused, and the installed compiler is the one that was there, still running"
else
  bad "a broken release over a working install exited $rc"
  sed 's/^/     /' "$work/install.log" | tail -4
fi
broken_tar="$work/broken.tar.gz"; cp "$serve/$name.tar.gz" "$broken_tar"
assemble

# --------------------------------------------------------------------
echo
echo "== the probes on the destructive half: each guard, removed, must cost =="
# --------------------------------------------------------------------
# Three copies of install.sh, each with one guard taken out by an exact
# line replacement whose match count is asserted first - `sed` that
# matches nothing produces a copy identical to the original and an
# ablation that proves nothing.
#
# THE COPY IS CHECKED AS WELL AS THE ORIGINAL, because a seam that
# matches install.sh once can still be missed by the tool doing the
# replacing - and was. This used `awk -v old="$2"`, and `-v` runs its
# value through awk's string-escape processing. Seam A ends in the
# line-continuation backslash, and what a lone trailing `\` becomes is
# the awk's choice: BWK awk (macOS) and mawk keep it, gawk DROPS it. So
# under gawk `$0 == old` matched nothing, the "ablated" copy was
# install.sh byte for byte, and probe A ran the real installer and
# watched it refuse `$HOME/.` - reported as "still refused", a message
# that points at physical_path and not at the copy. Reproduced
# 2026-09-27 in `run-gates-linux.sh`'s Ubuntu 24.04 aarch64 image, where
# `awk` is gawk 5.2.1; it is why probe A failed on all three
# linux-aarch64 CI runs it had, identically, and passed on darwin.
# (linux-x86_64 never reaches it: that target ships no archive, so this
# gate stops at the refusal check above.)
#
# The two strings now travel through ENVIRON, which no awk
# escape-processes, and the copy must have lost the seam and gained the
# replacement exactly once. A replacement that silently did not happen
# is named for what it is.
ablated() {  # <out> <exact line> <replacement>
  local n had
  n="$(grep -cxF -- "$2" "$repo_root/scripts/install.sh" || true)"
  if [[ "$n" != 1 ]]; then
    bad "the ablation seam \`$2\` matches $n lines of install.sh, not 1"
    return 1
  fi
  had="$(grep -cxF -- "$3" "$repo_root/scripts/install.sh" || true)"
  ABL_OLD="$2" ABL_NEW="$3" \
    awk '$0 == ENVIRON["ABL_OLD"] { print ENVIRON["ABL_NEW"]; next } { print }' \
    "$repo_root/scripts/install.sh" > "$1"
  n="$(grep -cxF -- "$2" "$1" || true)"
  if [[ "$n" != 0 || "$(grep -cxF -- "$3" "$1" || true)" != $((had + 1)) ]]; then
    bad "the ablation seam \`$2\` was not replaced in the copy ($n left) - the probe would run the real installer"
    return 1
  fi
}

# A. The spelling compared instead of the directory: `$HOME/.` must get
#    past the protected list.
#
#    GETTING PAST IT IS ASSERTED, not read off a missing refusal. A log
#    without "which is $HOME" is also what a run that died BEFORE the
#    comparison writes - a copy that no longer parses (drop the seam's
#    trailing `\` from the replacement and the next line is a bare
#    `|| die`), a tool it looks for first - and that run proves nothing
#    about physical_path. So it must be seen to reach the download,
#    which install.sh starts only once every prefix guard has passed.
#
#    What stops it after that is the ownership check: the scratch
#    home's `bin/` holds a file no install recorded. This comment used
#    to say the sentinels were then deleted; that was true before the
#    record existed and nothing checked it after. It is asserted now,
#    against a refusal that names THIS run's prefix, because a second
#    line of defence nobody has seen hold is a comment and not a guard.
if ablated "$work/spelling.sh" \
     'PREFIX="$(physical_path "$given_prefix")" \' 'PREFIX="${given_prefix%/}" \'; then
  plant_home "$fake_home"
  rc="$(home_run "$fake_home" "$fake_home/." "$work/spelling.sh")"
  if grep -qF "which is $fake_home" "$work/install.log"; then
    bad "with the spelling compared, \$HOME/. was still refused as the home directory"
    sed 's/^/     /' "$work/install.log" | tail -4
  elif ! grep -qF "==> downloading $name" "$work/install.log"; then
    bad "with the spelling compared, the installer stopped before the download (exit $rc) - it never reached the comparison, so this proves nothing"
    sed 's/^/     /' "$work/install.log" | tail -4
  else
    ok "with the spelling compared, \$HOME/. gets past the list to the download - case 5 is what physical_path buys"
    if (( rc != 0 )) && sentinels_ok "$fake_home" \
       && grep -qF "refusing to install into '$fake_home/.': it already has bin" "$work/install.log"; then
      ok "and the ownership check refuses it there (exit $rc), both sentinels intact - the second line of defence"
    else
      bad "past the list, \$HOME/. was not stopped by the ownership check: exit $rc, sentinels $(sentinels_ok "$fake_home" && echo intact || echo DELETED)"
      sed 's/^/     /' "$work/install.log" | tail -4
    fi
  fi
  plant_home "$fake_home"
fi

# B. No ownership check: the stranger's bin/ must be replaced.
if ablated "$work/owner.sh" '  elif ! legacy_owns "$m"; then' '  elif false; then'; then
  rm -rf "$tools"; mkdir -p "$tools/bin"; echo "#!/bin/sh" > "$tools/bin/mytool"
  rc="$(home_run "$fake_home" "$tools" "$work/owner.sh")"
  if [[ -f "$tools/bin/mytool" ]]; then
    bad "with the ownership check removed, the stranger's bin/mytool still survived"
  else
    ok "with the ownership check removed, bin/mytool is deleted (exit $rc) - case 6 is what it buys"
  fi
fi

# C. No verification before the switch: the broken compiler must land.
if ablated "$work/unstaged.sh" \
     'verify_compiler "$stage" || die "Nothing was installed; $given_prefix is as it was."' 'true'; then
  cp "$broken_tar" "$serve/$name.tar.gz"
  printf '%s  %s\n' "$(sha_of "$serve/$name.tar.gz")" "$name.tar.gz" > "$serve/$name.tar.gz.sha256"
  rm -rf "$work/kept"; cp -R "$work/prefix" "$work/kept"
  rc="$(home_run "$fake_home" "$work/kept" "$work/unstaged.sh")"
  if cmp -s "$work/kept/bin/axiom" "$work/prefix/bin/axiom"; then
    bad "with the staged probe removed, the old compiler still survived a broken release"
  else
    ok "with the staged probe removed, the broken compiler replaces the working one (exit $rc) - case 9 is what staging buys"
  fi
  assemble
fi

echo
if (( failed > 0 )); then
  echo "check-install: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-install: $checks checks - the script a stranger pipes into bash"
echo "               installs a good release, refuses three bad ones and every"
echo "               spelling of a protected directory, replaces only what an"
echo "               earlier install recorded, leaves a working install alone"
echo "               when the new compiler fails, and each of those guards has"
echo "               been observed to be what does the refusing"
