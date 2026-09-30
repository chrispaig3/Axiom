#!/usr/bin/env python3
"""Write the calendar vectors that tests/stdlib/661-chrono-calendar.ax reads.

    python3 tests/stdlib/tools/chrono_vectors.py > tests/stdlib/661-chrono-calendar.in

Each line is a date and what Python's `datetime` says about it:

    year month day weekday day-of-year leap days-since-1970-01-01

The weekday is ISO (1 Monday to 7 Sunday) and `leap` is 1 in a leap
year. Years 1 to 9999 come straight from `datetime.date`: a seeded
random sample, so the file is the same on every run, plus the days
either side of every leap-year rule (each century's 28 February,
29 February when there is one, and 1 March).

`datetime` stops at year 1, so years -9999 to 0 are read off the
400-year Gregorian cycle: 146,097 days, exactly 20,871 weeks. A date
in year y has the weekday, day of the year and leap flag of the same
date in year y + 400k, and lies 146,097k days before it. Nothing here
shares code with stdlib/Chrono.ax.
"""

import datetime
import random

EPOCH = datetime.date(1970, 1, 1).toordinal()
CYCLE_DAYS = 146097


def is_leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


def facts(y, m, d):
    """(weekday, day of year, leap, days) for a date in years 1-9999."""
    date = datetime.date(y, m, d)
    return (date.isoweekday(), date.timetuple().tm_yday,
            1 if is_leap(y) else 0, date.toordinal() - EPOCH)


def facts_shifted(y, m, d):
    """The same facts for any year, through the 400-year cycle."""
    k = 0
    while y + 400 * k < 1:
        k += 1
    wd, yday, leap, days = facts(y + 400 * k, m, d)
    return (wd, yday, leap, days - CYCLE_DAYS * k)


def line(y, m, d, f):
    return '%d %d %d %d %d %d %d' % ((y, m, d) + f)


def main():
    rng = random.Random('chrono-calendar-1')
    rows = []

    # Years 1 to 9999, straight from datetime.
    first = datetime.date(1, 1, 1).toordinal()
    last = datetime.date(9999, 12, 31).toordinal()
    picked = set()
    for _ in range(3000):
        picked.add(rng.randint(first, last))
    for y in range(100, 10000, 100):
        for m, d in ((2, 28), (2, 29), (3, 1), (12, 31)):
            if m == 2 and d == 29 and not is_leap(y):
                continue
            picked.add(datetime.date(y, m, d).toordinal())
    for y, m, d in ((1, 1, 1), (1969, 12, 31), (1970, 1, 1), (2000, 2, 29),
                    (2024, 2, 29), (9999, 12, 31)):
        picked.add(datetime.date(y, m, d).toordinal())
    for o in sorted(picked):
        date = datetime.date.fromordinal(o)
        rows.append(line(date.year, date.month, date.day,
                         facts(date.year, date.month, date.day)))

    # Years -9999 to 0, through the cycle.
    shifted = set()
    for _ in range(600):
        y = rng.randint(-9999, 0)
        m = rng.randint(1, 12)
        top = 29 if (m == 2 and is_leap(y)) else \
            (28 if m == 2 else (30 if m in (4, 6, 9, 11) else 31))
        shifted.add((y, m, rng.randint(1, top)))
    for y, m, d in ((-9999, 1, 1), (-4000, 2, 29), (-400, 2, 29),
                    (-100, 2, 28), (-100, 3, 1), (-4, 2, 29), (-1, 2, 28),
                    (-1, 3, 1), (-1, 12, 31), (0, 1, 1), (0, 2, 29),
                    (0, 12, 31)):
        shifted.add((y, m, d))
    shifted_rows = [line(y, m, d, facts_shifted(y, m, d))
                    for y, m, d in sorted(shifted)]

    print('# source: Python datetime (years 1-9999), and the 400-year cycle')
    print('#   for years -9999 to 0; generated, not downloaded')
    print('# generate: python3 tests/stdlib/tools/chrono_vectors.py'
          ' > tests/stdlib/661-chrono-calendar.in')
    print('# fields: year month day weekday day-of-year leap days-since-1970-01-01')
    for r in shifted_rows + rows:
        print(r)


if __name__ == '__main__':
    main()
