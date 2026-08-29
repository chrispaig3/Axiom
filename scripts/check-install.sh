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

# Assemble a release into $serve. `--no-stdlib` omits `stdlib/` from
# the archive, for case 4.
assemble() {  # [--no-stdlib]
  local d="$work/stage/$name"
  rm -rf "$work/stage"; mkdir -p "$d/bin"
  cp "$axc" "$d/bin/axiom"
  [[ "${1:-}" == "--no-stdlib" ]] || cp -R "$repo_root/stdlib" "$d/stdlib"
  cp "$repo_root/LICENSE" "$repo_root/README.md" "$repo_root/CHANGELOG.md" "$d/"
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

echo
if (( failed > 0 )); then
  echo "check-install: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-install: $checks checks - the script a stranger pipes into bash"
echo "               installs a good release, refuses three bad ones, and its"
echo "               verification has been observed to be what does the refusing"
