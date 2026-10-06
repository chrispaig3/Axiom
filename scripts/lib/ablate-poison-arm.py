# Replaces the conservative `(cast Int "")` in `stampPatBinderTy`'s
# disagreement arm with `now`, making the arm last-write-wins. This is
# the ablation scripts/check-fallible-reclaim.sh rebuilds a compiler with.
#
# It is a file rather than a heredoc inside the gate so that a search
# of the repository can see it.
#
# The anchor is the whole arm and must match exactly once. An ablation
# that matched nothing would make the check it feeds unable to fail.
import sys

p = sys.argv[1]
s = open(p).read()
# The anchor follows the formatter's layout of the arm. If the formatter
# moves it, re-derive the anchor from self_host/typecheck.ax.
old = '        {\n          (setNodeBinderTy\n            arg\n            (cast Int ""))\n          0\n        }'
new = '        {\n          (setNodeBinderTy\n            arg\n            now)\n          0\n        }'
if s.count(old) != 1:
    sys.stderr.write("the poison arm is not where this expects it (%d matches)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
