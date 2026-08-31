#!/usr/bin/env python3
"""An independent terminal model, and the expectation it is compared to.

WHAT MAKES THIS A CHECK RATHER THAN A RECORD. Neither side of the
comparison is a checked-in value, so there is nothing an `AXIOM_BLESS`
can launder. One side REPLAYS the editor's actual bytes onto a grid;
the other COMPUTES what the grid should hold straight from the key
script, in plain Python, with no knowledge of what the editor emitted.
They can only agree if the editor is right.

THE DEFERRED WRAP IS MODELLED, because it is the thing being tested.
A terminal that has just printed into the last column does NOT move to
the next row: it leaves the cursor there with the wrap PENDING, and
only the next printable character makes it happen. Every line editor
that gets multi-row redraw wrong gets it wrong here - the cursor ends
one row high, and the next repaint erases rows the content still
occupies. `lineedit.ax` handles it by forcing the wrap with `\\n\\r`
whenever the content's column count is a multiple of the width; this
model implements the terminal's half of that contract, so if the force
is removed the two sides disagree.

The escape vocabulary is exactly the five sequences `lineedit.ax` can
emit (CUU, CUD, CUF, EL 0, and the SGR the prompt is painted with),
plus CR, LF and BS. Anything else is an error rather than a silent
skip: a model that ignored what it did not understand would report
success for a redraw it never actually replayed.
"""
import sys, json, re


class Screen:
    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols
        self.g = [[" "] * cols for _ in range(rows)]
        self.r = 0
        self.c = 0
        self.pending = False       # deferred wrap
        self.unknown = []

    def _scroll(self):
        self.g.pop(0)
        self.g.append([" "] * self.cols)
        self.r = self.rows - 1

    def put(self, ch):
        if self.pending:
            self.c = 0
            self.r += 1
            self.pending = False
            if self.r >= self.rows:
                self._scroll()
        self.g[self.r][self.c] = ch
        if self.c == self.cols - 1:
            self.pending = True
        else:
            self.c += 1

    def cr(self):
        self.c = 0
        self.pending = False

    def lf(self):
        self.pending = False
        self.r += 1
        if self.r >= self.rows:
            self._scroll()

    def bs(self):
        self.pending = False
        if self.c > 0:
            self.c -= 1

    def up(self, n):
        self.pending = False
        self.r = max(0, self.r - n)

    def down(self, n):
        self.pending = False
        self.r = min(self.rows - 1, self.r + n)

    def fwd(self, n):
        self.pending = False
        self.c = min(self.cols - 1, self.c + n)

    def el0(self):
        self.pending = False
        for i in range(self.c, self.cols):
            self.g[self.r][i] = " "

    def text(self):
        return [("".join(row)).rstrip() for row in self.g]


CSI = re.compile(rb"\x1b\[([0-9;]*)([A-Za-z])")


def replay(data, rows, cols):
    s = Screen(rows, cols)
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b == 0x1B:
            m = CSI.match(data, i)
            if not m:
                s.unknown.append(("bare-ESC", i))
                i += 1
                continue
            params, final = m.group(1), m.group(2).decode()
            arg = int(params) if params.isdigit() else (0 if final == "K" else 1)
            if final == "m":
                pass                                  # SGR: colour, no motion
            elif final == "A":
                s.up(arg)
            elif final == "B":
                s.down(arg)
            elif final == "C":
                s.fwd(arg)
            elif final == "D":
                s.c = max(0, s.c - arg)
            elif final == "K":
                if arg != 0:
                    s.unknown.append(("EL-%d" % arg, i))
                s.el0()
            elif final == "J":
                for rr in range(rows):
                    s.g[rr] = [" "] * cols
            elif final == "H":
                s.r, s.c, s.pending = 0, 0, False
            else:
                s.unknown.append(("CSI-" + final, i))
            i = m.end()
            continue
        if b == 0x0D:
            s.cr()
        elif b == 0x0A:
            s.lf()
        elif b == 0x08:
            s.bs()
        elif b == 0x07:
            pass
        elif b < 0x20 or b == 0x7F:
            s.unknown.append(("ctl-%d" % b, i))
        else:
            # UTF-8: one code point is one column in this editor's model,
            # which is the same rule `ledCharCols` states.
            ln = 1
            if b >= 0xF0:
                ln = 4
            elif b >= 0xE0:
                ln = 3
            elif b >= 0xC0:
                ln = 2
            s.put(data[i:i + ln].decode("utf-8", "replace"))
            i += ln
            continue
        i += 1
    return s


def expect(prompt, typed, rows, cols):
    """The grid the screen MUST hold, computed from the script alone."""
    line = prompt + typed
    grid = []
    for r in range((len(line) // cols) + 1):
        grid.append(line[r * cols:(r + 1) * cols].rstrip())
    while len(grid) < rows:
        grid.append("")
    cell = len(line)
    return grid[:rows], (cell // cols, cell % cols)


def main():
    spec = json.load(open(sys.argv[1]))
    data = open(sys.argv[2], "rb").read()
    if len(sys.argv) > 3:
        # Replay only up to a mark the driver recorded: the screen is
        # inspected mid-line, before the keys that end the session.
        data = data[:int(sys.argv[3])]
    rows, cols = spec["rows"], spec["cols"]
    s = replay(data, rows, cols)
    want_grid, want_cur = expect(spec["prompt"], spec["typed"], rows, cols)
    got_grid = s.text()

    print("MODEL_UNKNOWN=%d" % len(s.unknown))
    if s.unknown:
        print("MODEL_UNKNOWN_WHAT=%s" % s.unknown[:6])
    print("MODEL_CURSOR=%d,%d" % (s.r, s.c))
    print("WANT_CURSOR=%d,%d" % want_cur)
    print("MODEL_CURSOR_OK=%d" % (1 if (s.r, s.c) == want_cur else 0))
    same = got_grid[:len(want_grid)] == want_grid
    print("MODEL_GRID_OK=%d" % (1 if same else 0))
    print("MODEL_ROWS_USED=%d" % (1 + max([i for i, r in enumerate(got_grid) if r] or [0])))
    if not same:
        for i, (a, b) in enumerate(zip(got_grid, want_grid)):
            if a != b:
                print("ROW%d_GOT=%r" % (i, a))
                print("ROW%d_WANT=%r" % (i, b))
    return 0


if __name__ == "__main__":
    sys.exit(main())
