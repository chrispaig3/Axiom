#!/usr/bin/env bash
# Shared by the seed replay gates, never by the bootstrap itself:
# it reads a commit's `scripts/reseed.sh` through git, and the
# offline bootstrap path (scripts/check-offline-bootstrap.sh) runs
# no git.

# seed_emit_argv <repo> <commit> <target>
#
# Sets `seed_argv` to the arguments that emit `in.ax` for <target> the
# way <commit>'s own `scripts/reseed.sh` emitted its seed. A replay
# compares bytes with that seed, so it has to ask the same question.
#
# Two spellings exist. A commit whose reseed says `emit-llvm in.ax`
# emitted with `emit-llvm in.ax --target T`. Every earlier commit used
# the positional form, `in.ax T`, which its compiler still accepts. The
# two are different emissions on a compiler that writes a line table:
# the positional form leaves the table empty, which is why the seeds it
# wrote read `@__axiom_linetab_n = internal constant i64 0`. A commit
# with no `scripts/reseed.sh` predates the script and used the
# positional form, the only one its compiler had.
#
# Consumers: `scripts/check-seed-lineage.sh` (each row, orphan and walk
# seed against its own commit) and `scripts/check-seed-provenance.sh`
# (the committed seed against the commit that wrote it).
seed_emit_argv() {
  local repo="$1" commit="$2" target="$3"
  if git -C "$repo" show "${commit}:scripts/reseed.sh" 2>/dev/null | grep -q 'emit-llvm in\.ax'; then
    seed_argv=(emit-llvm in.ax --target "$target")
  else
    seed_argv=(in.ax "$target")
  fi
}
