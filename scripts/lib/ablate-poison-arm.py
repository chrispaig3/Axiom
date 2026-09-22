# The one-word ablation of `stampPatBinderTy`'s disagreement arm, for
# scripts/check-fallible-reclaim.sh.
#
# It lives in its own file rather than in a heredoc inside the gate
# because the gate's patch is Python inside shell inside a golden-
# bearing repository, and this repository has already been bitten by a
# sweep that could not see a heredoc corpus. A file is greppable.
#
# Anchored on the whole arm and required to match exactly once: an
# ablation that silently matched nothing would make the check it feeds
# a check that cannot fail.
import sys

p = sys.argv[1]
s = open(p).read()
# 2026-09-21: the formatter's normal-form move split the aligned
# `arg (cast Int "")` pair across two lines and folded the stray `)`
# up. The arm is unchanged, so the anchor follows the spelling.
old = '        {\n          (setNodeBinderTy\n            arg\n            (cast Int ""))\n          0\n        }'
new = '        {\n          (setNodeBinderTy\n            arg\n            now)\n          0\n        }'
if s.count(old) != 1:
    sys.stderr.write("the poison arm is not where this expects it (%d matches)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
