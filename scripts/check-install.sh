#!/usr/bin/env bash
# Gate for `scripts/install.sh`, the script `README.md` tells newcomers
# to pipe into bash. It fetches an archive and a checksum, compares
# them, unpacks, installs, and builds a program that imports the
# standard library to prove the result works.
#
# What it serves: a release built here from the compiler under test, the
# tree's `stdlib/` and the three prose files, assembled as `release.yml`
# assembles one, with its `.sha256` beside it. `python3 -m http.server`
# serves it on loopback, and `install.sh` reaches it through
# `AXIOM_BASE_URL`. That variable changes where the archive comes from,
# and nothing about what is then required of it.
#
# The four install cases:
#
#   1. A well-formed release installs, and the installed compiler builds
#      and runs a program that imports the standard library from a
#      directory of its own.
#   2. A tampered archive (one byte) is refused. This is the assertion
#      the whole download exists for.
#   3. A missing checksum file is refused, not installed unverified.
#   4. An archive with no `stdlib/` is refused: a compiler that cannot
#      find its library is not an installation.
#
# A probe on the gate itself deletes the comparison in a copy of
# `install.sh`, and case 2 must then stop being refused.
#
# Cases 5 to 9 plant files the installer did not put there, in a
# scratch HOME, never the real one. They require that:
#
#   5. every spelling of a protected directory is refused;
#   6. a directory of somebody else's is not replaced;
#   7. an upgrade replaces exactly what the ownership record lists;
#   8. an install from before the record is recognised by its shape;
#   9. a release whose compiler fails leaves the working install alone.
#
# Each of the three guards is then removed in a copy of the installer
# and must be seen to stop refusing. Without the ownership check or the
# staged probe, the file each guards is lost. Without physical_path,
# `$HOME/.` gets past the protected list, and the ownership check must
# catch it.
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
# Whether this host's target ships an archive at all.
#
# Some supported targets get no prebuilt archive from `release.yml`, and
# `install.sh` refuses them with a build-from-source message instead of
# fetching a 404. On such a host there is no install path to exercise,
# so the gate checks the refusal and what it says.
#
# The shipped list is read from `release.yml`'s matrix, so this gate
# cannot disagree with the workflow. `scripts/check-release-targets.sh`
# holds that matrix and `install.sh`'s refusal list to each other.
# --------------------------------------------------------------------
release_yml="$repo_root/.github/workflows/release.yml"
[[ -f "$release_yml" ]] || { echo "FAIL: $release_yml is missing"; exit 1; }
shipped="$(sed -n 's/^ *- name: \([a-z0-9_]*-[a-z0-9_]*\) *$/\1/p' "$release_yml" | sort -u)"
[[ -n "$shipped" ]] || {
  echo "FAIL: no build-matrix targets found in release.yml - this gate reads that"
  echo "      list to know whether the host ships, and an empty read would make"
  echo "      it silently skip every case below"; exit 1; }

if ! grep -qx "$target" <<< "$shipped"; then
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

# Copy the tracked files under <dir> into <dest>, as the working tree
# holds them. The release workflow copies from a clean checkout; a plain
# `cp -R` would also pick up strays such as a Finder `docs/.DS_Store`,
# which fails case 8's only-`.md` shape.
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
# Choose the port here instead of parsing `http.server`'s banner, whose
# wording can change. Binding a port Python just proved free costs one
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
# Wait until a fetch works, not until the server prints.
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

# `docs/` must reach the installed prefix. README points at
# `docs/reference.md` and the rest instead of restating them, so an
# archive without them leaves an installed user with dead links.
#
# The count is a floor, so adding a document never turns the gate red.
# Zero or one is the failure it catches: a `cp` that silently copied
# nothing.
doc_n=$(find "$work/prefix/docs" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ -d "$work/prefix/docs" ]] && (( doc_n >= 8 )); then
  ok "docs/ reached the prefix, $doc_n documents"
else
  bad "the installed prefix has $doc_n document(s) under docs/; the floor is 8"
  echo "     the README points at these; shipping it without them is a dead link"
fi
# `install.sh` runs this check itself. The gate repeats it from outside
# instead of trusting the installer's own report.
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
# The archive is corrupted after its checksum was published, which is
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
# With the comparison deleted, case 2 must stop being refused.
# Otherwise something other than the checksum rejected the tampered
# archive, and case 2 proves nothing about verification.
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
# The destructive half. Everything below plants files the installer
# must not delete and installs on top of them, so every directory is
# under `$work`, HOME included. A regression in the "this prefix is
# your home" refusal must cost a sentinel file, never a real one.
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
# Each spelling below names the same directory, `$HOME/.` among them.
# Each must be refused, and nothing deleted.
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
# An install made before the ownership record has no `.axiom-install`.
# Its shape (bin/ holding only `axiom`, stdlib/ only `.ax`, docs/ only
# `.md`) lets it be upgraded instead of stranded.
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
# The archive is well-formed and correctly checksummed, but its
# compiler is a script that fails. The install must refuse it and leave
# the working install in the prefix untouched: the property staging
# exists for.
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
# Three copies of install.sh, each with one guard removed by an exact
# line replacement. The seam must match install.sh once, and the copy
# must have lost it and gained the replacement once. Otherwise the
# "ablated" copy is the real installer and its probe proves nothing.
#
# The strings travel through ENVIRON, not `awk -v`. `-v` escape-processes
# its value, and seam A ends in a line-continuation `\`: gawk (the `awk`
# on Ubuntu) drops a lone trailing `\`, while BWK awk and mawk keep it,
# so under gawk the seam would match nothing.
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
#    Getting past it is asserted, not inferred from a missing refusal.
#    A run that died before the comparison also lacks "which is $HOME":
#    a copy that no longer parses (drop the replacement's trailing `\`
#    and the next line is a bare `|| die`), or a missing tool. So the run
#    must reach the download, which install.sh starts only once every
#    prefix guard has passed.
#
#    The ownership check must then stop it, since the scratch home's
#    `bin/` holds a file no install recorded. The refusal must name this
#    run's prefix, and both sentinels must survive.
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
