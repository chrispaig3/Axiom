# Dates and times

`Chrono` gives your program calendar dates, times of day, date-times
and durations, with ISO 8601 text in and out and arithmetic that never
wraps, and a monotonic clock to time work and sleep by. It has no time
zones, so every value means exactly what it says. This page shows how
to use it and what it assumes.

```scheme
(import IO)
(import Err)
(import Chrono)

(:: main ())
;@axiom:effect(io)
(fn (main)
  (match (datetimeParse "2024-01-31T09:30:00")
    ((Err e) (die (errorText e) 1))
    ((Ok start)
      {
        (let next (unwrapOr (dateAddMonths start.date 1) start.date))
        (let meeting (unwrapOr (durationParse "PT1H30M") durationZero))
        {
          (println (dateToString next))
          (match (datetimeAdd start meeting)
            ((Ok end) (println (datetimeToString end)))
            ((Err e) (println (errorText e))))
          (println (unwrapOr (datetimeFormat "%A %d %B %Y, %H:%M" start) ""))
        }
      }
    )))
```

```text
2024-02-29
2024-01-31T11:00:00
Wednesday 31 January 2024, 09:30
```

One month after 31 January is 29 February in 2024: the day of the
month is clamped to the month's last day.

<a id="the-four-types"></a>
## The five types

| Type | Holds | Range |
|---|---|---|
| `Date` | a day in the calendar | -9999-01-01 to 9999-12-31 |
| `Time` | a time of day, to the nanosecond | 00:00:00 to 23:59:59.999999999 |
| `NaiveDateTime` | a date and a time, with no zone or offset | any supported date, at any time of day |
| `Duration` | a signed length of time in nanoseconds | 2⁶³ − 1 ns either way, about 292 years |
| `Instant` | a reading of the monotonic clock, in nanoseconds | 0 to 2⁶³ − 1 ns from an unspecified start |

`Date`, `Time`, `Duration` and `Instant` are sealed: only `Chrono` can
make one, and it checks every value first. So a `Date` is never 30 February and a
`Time` is never 25 o'clock. A `NaiveDateTime` is an ordinary struct
with the fields `date` and `time`, and any date with any time is a
valid one.

A value prints as its type's name, such as `<Date>`. Use
`dateToString`, `timeToString`, `datetimeToString` or
`durationToString` to show one.

## Make and read values

```scheme fragment
(dateNew 2024 2 29)              ; (Ok d): year, month, day
(timeNew 14 5 9 500000000)       ; (Ok t): hour, minute, second, nanosecond
(datetimeNew d t)                ; a NaiveDateTime, never an error
(durationFromMinutes 90)         ; (Ok PT1H30M)
(dateWeekday d)                  ; 4: ISO weekday, 1 is Monday and 7 is Sunday
(dateDayOfYear d)                ; 60
(timeNanosecond t)               ; 500000000
```

The constructors answer a `Result`. `dateNew` refuses 30 February with
`chronoInvalidDate`, and `timeNew` refuses an hour of 24 or a second of
60 with `chronoInvalidTime`. The `durationFrom...` functions take
nanoseconds, microseconds, milliseconds, seconds, minutes or hours, and
refuse a count longer than a `Duration` can hold.

`dateMin`, `dateMax`, `timeMidnight` and `durationZero` are ready-made
values. `dateIsLeapYear` and `dateDaysInMonth` answer questions about
the calendar without making a date.

## Parse and print

The parsers read ISO 8601's extended format and refuse anything else,
including extra spaces, missing zero padding and fields out of range.
Printing then parsing always gives back the same value.

| Type | Reads | Prints |
|---|---|---|
| `Date` | `2024-02-29`, or a sign and six year digits: `-000044-03-15` | `2024-02-29`, with the six-digit form only outside years 0000 to 9999 |
| `Time` | `14:05`, `14:05:09`, `14:05:09.5` with one to nine fraction digits after `.` or `,` | `14:05:09`, with a fraction only when it isn't zero |
| `NaiveDateTime` | a date, `T` (or `t`, or one space) and a time | `2024-02-29T14:05:09.5` |
| `Duration` | `PT` and hours `H`, minutes `M` and seconds `S`, in that order, with a fraction only on the seconds: `PT1H30M`, `PT0.5S`, `-PT36H` | the same, largest unit hours, `PT0S` for zero |

```scheme
(import IO)
(import Err)
(import Chrono)

(:: show (-> String String))
(fn (show text)
  (match (datetimeParse text)
    ((Ok dt) (datetimeToString dt))
    ((Err e) (errorText e))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (show "2024-02-29 14:05:09,50"))
    (println (show "2016-12-31T23:59:60"))
    (println (show "2024-02-30T10:00"))
    (println (show "2024-02-29T14:05Z"))
  })
```

```text
2024-02-29T14:05:09.5
2016-12-31T23:59:59
the day is not in the month while datetimeParse
a naive datetime has no offset: datetimeParseUtc reads one with Z or +HH:MM while datetimeParse
```

A refusal answers `chronoParseFailed` for text that isn't the format,
`chronoInvalidDate` or `chronoInvalidTime` for a field the format
allows but the calendar doesn't, and `chronoOutOfRange` for a year
outside the range. `-000000` isn't a year and `24:00` isn't a time.
A duration in days, weeks, months or years is refused, because
none of those is a fixed length.

Tested by `tests/stdlib/663-chrono-parse.ax` and
`tests/stdlib/664-chrono-roundtrip.ax`.

## Do arithmetic

```scheme fragment
(dateAddDays d 30)            ; (Ok ...), or Err past the range
(dateAddMonths d -1)          ; clamps the day, as above
(dateAddYears d 1)            ; 29 February becomes 28 February
(dateDaysUntil a b)           ; an Int, positive when b is later
(timeAdd t dur)               ; Err when the result leaves the day
(timeAddWrapping t dur)       ; 23:00 plus two hours is 01:00
(datetimeAdd dt dur)          ; and datetimeSub
(datetimeUntil a b)           ; (Ok duration), positive when b is later
(durationAdd a b)             ; and durationSub, durationMul, durationDiv
```

Every function that can leave the range answers a `Result`. A date
outside -9999-01-01 to 9999-12-31, a time pushed out of its day, and a
duration longer than 2⁶³ − 1 nanoseconds all answer `Err` with the code
`chronoOutOfRange`. Nothing wraps, except `timeAddWrapping`, whose name
says it does. `durationDiv` truncates toward zero, as `/` does, and
answers `chronoOutOfRange` when you divide by zero.

The comparisons are `dateCompare`, `timeCompare`, `datetimeCompare`
and `durationCompare`, which answer -1, 0 or 1, and `dateEq` and its
siblings.

```scheme
(import IO)
(import Err)
(import Chrono)

(:: show (-> (Result Date Error) String))
(fn (show r)
  (match r
    ((Ok d) (dateToString d))
    ((Err e) (errorText e))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let jan31 (unwrapOr (dateNew 2023 1 31) dateMin))
    (let leapDay (unwrapOr (dateNew 2024 2 29) dateMin))
    {
      (println (show (dateAddMonths jan31 1)))
      (println (show (dateAddMonths jan31 2)))
      (println (show (dateAddYears leapDay 1)))
      (println (show (dateAddDays dateMax 1)))
    }
  })
```

```text
2023-02-28
2023-03-31
2025-02-28
the date is outside -9999-01-01 to 9999-12-31 while dateAddDays
```

Clamping happens once, in the month you land in. Two months after
31 January is 31 March, not 28 March.

Tested by `tests/stdlib/662-chrono-arithmetic.ax`.

## Format with a pattern

`datetimeFormat` writes a value out by a pattern. Each `%` directive is
replaced, and every other byte is copied as it is:

| Directive | Writes | Directive | Writes |
|---|---|---|---|
| `%Y` | the year, as `dateToString` writes it | `%H` | the hour, 00 to 23 |
| `%m` | the month, 01 to 12 | `%M` | the minute, 00 to 59 |
| `%d` | the day, 01 to 31 | `%S` | the second, 00 to 59 |
| `%j` | the day of the year, 001 to 366 | `%3f` | milliseconds, three digits |
| `%u` | the ISO weekday, 1 (Monday) to 7 | `%6f` | microseconds, six digits |
| `%a`, `%A` | `Mon`, `Monday` | `%9f` | nanoseconds, nine digits |
| `%b`, `%B` | `Jan`, `January` | `%%` | a `%` |

```scheme
(import IO)
(import Err)
(import Chrono)

(:: main ())
;@axiom:effect(io)
(fn (main)
  (match (datetimeParse "2024-03-10T02:30:05.123456789")
    ((Err e) (die (errorText e) 1))
    ((Ok dt)
      {
        (println (unwrapOr (datetimeFormat "%a %d %b %Y %H:%M:%S.%3f" dt) ""))
        (println (unwrapOr (dateFormat "day %j, weekday %u" dt.date) ""))
        (match (datetimeFormat "%Y-%m-%d %q" dt)
          ((Ok s) (println s))
          ((Err e) (println (errorText e))))
      }
    )))
```

```text
Sun 10 Mar 2024 02:30:05.123
day 070, weekday 7
unknown directive %q while datetimeFormat
```

The fractions are truncated, not rounded. The names are English and
there's no locale. The whole pattern is checked before anything is
written, so an unknown directive or a `%` at the end answers
`chronoInvalidFormat` and no partial text. `dateFormat` and
`timeFormat` take the directives that make sense for their type and
refuse the others.

Tested by `tests/stdlib/665-chrono-format.ax`.

## Work in UTC

A `NaiveDateTime` has no zone, so to record an instant you store its
UTC reading. Three functions give you one:

```scheme fragment
(datetimeNowUtc)                                  ; (Ok dt): now, in UTC
(datetimeFromUnix 1000000000 0)                   ; (Ok 2001-09-09T01:46:40)
(datetimeParseUtc "2024-12-31T23:30:00-01:00")    ; (Ok 2025-01-01T00:30:00)
```

`datetimeToUnixSeconds` goes the other way, and `timeNanosecond` of
the time gives the fraction that goes with it. `datetimeParseUtc`
reads an RFC 3339 timestamp, which must end in `Z` or an offset
`+HH:MM` or `-HH:MM`, and subtracts the offset. That can move the date
across midnight, a month or a year. `datetimeParse` refuses the same
text, because a naive reading has no offset to apply.

`datetimeNowUtc` reads the system's realtime clock. The system may
step that clock, so two readings don't reliably measure how long
something took. On a target with no realtime clock it answers
`chronoClockUnavailable`.

Tested by `tests/stdlib/666-chrono-utc.ax` and
`tests/stdlib/667-chrono-now.ax`.

## Time work and sleep

An `Instant` is a reading of the monotonic clock, which never steps
backwards, whatever happens to the time of day. Use it to measure how
long something took and to set deadlines, and `sleepFor` or
`sleepUntil` to wait:

```scheme
(import IO)
(import Err)
(import Chrono)

(:: main ())
;@axiom:effect(io)
;@axiom:effect(block)
(fn (main)
  (match instantNow
    ((Err e) (die (errorText e) 1))
    ((Ok start)
      {
        (let pause (unwrapOr (durationFromMillis 250) durationZero))
        {
          (unwrapOr (sleepFor pause) 0)
          (match (instantElapsed start)
            ((Ok took)
              (println
                (if (>= (durationCompare took pause) 0)
                  "slept at least 250 ms"
                  "woke early"))
            )
            ((Err e) (println (errorText e))))
        }
      }
    )))
```

```text
slept at least 250 ms
```

A sleep blocks the binding that calls it, so a function that sleeps
declares `effect(block)`. It never ends short: a wake that comes early,
from a signal, sleeps again for what is left. A zero or negative
duration, or an instant already past, answers at once.

| Function | Answers |
|---|---|
| `instantNow` | `(Ok i)`, the clock now |
| `instantElapsed i` | `(Ok d)`, the time since `i` |
| `instantUntil a b` | the `Duration` from `a` to `b`, negative when `b` is earlier |
| `instantAdd i d` | `(Ok i2)`, or `chronoOutOfRange` past the clock's range |
| `instantCompare a b`, `instantEq a b` | -1, 0 or 1, and whether they're equal |
| `sleepFor d` | `(Ok 0)` once at least `d` has passed |
| `sleepUntil i` | `(Ok 0)` once the clock reaches `i` |

Linux and FreeBSD read `clock_gettime`'s monotonic clock, and
darwin-aarch64 reads the processor's counter, the one
`mach_absolute_time` reads. A target without a monotonic clock
answers `chronoClockUnavailable`. `Sys` has the same clock in
nanoseconds, `sysNowMonotonicNanos`, and the sleep call `sysSleepNanos`.
The clock read takes no arguments and releases its own scratch storage.

Tested by `tests/stdlib/851-instant-sleep.ax` and
`scripts/check-task.sh`.

## What Chrono assumes

### No leap seconds

Every day has exactly 86,400 seconds. A second of 60 parses as 59, as
Jiff and Temporal read it, so `23:59:60` is `23:59:59` and
`23:59:60.5` is `23:59:59.5`. `timeNew` refuses a second of 60.

### No time zones or daylight saving

A `NaiveDateTime` is a wall-clock reading with no zone. Adding 24 hours
to one adds 24 hours of wall time, even across a day when some zone's
clocks changed. `2024-03-10T01:30` plus `PT24H` is `2024-03-11T01:30`,
whatever New York did that night. Use UTC for instants and convert to
local time at the edge of your program.

### The proleptic Gregorian calendar

Every date uses today's Gregorian rules, including dates before the
calendar was adopted in 1582. Years are astronomical: year 0 is 1 BC
and a leap year, and year -1 is 2 BC. A leap year is a multiple of 4,
and of 400 if it is a multiple of 100, so 2000 and 0 are leap years
and 1900 and -100 are not.

### The range

Dates run from -9999-01-01 to 9999-12-31. A `Duration` holds up to
2⁶³ − 1 nanoseconds either way, so negating one always fits and the
most negative `Int` is never a duration. Two date-times more than
about 292 years apart have no `Duration` between them, and
`datetimeUntil` answers `chronoOutOfRange` for them.

### Overflow

Arithmetic that would leave the range answers `Err` with the code
`chronoOutOfRange`. It never wraps. The one exception is
`timeAddWrapping`, which wraps around midnight and says so in its
name.

### Month-end clamping

`dateAddMonths` and `dateAddYears` keep the day of the month when the
new month has it, and otherwise use the new month's last day. So
31 January plus one month is 28 or 29 February, and 29 February plus
one year is 28 February.

Tested by `tests/stdlib/660-chrono-days.ax`, which walks every day of
the range, and `tests/stdlib/661-chrono-calendar.ax`, which checks
weekdays and leap years against Python's `datetime`.

## Performance

These times are from darwin-aarch64 at `--opt 1`: whole-process time
over many iterations, best of five, with an empty program's startup
subtracted.

| Operation | Time per call |
|---|---|
| `dateAddDays` | 5 ns |
| `dateToString` | 26 ns |
| `datetimeToString`, with a nine-digit fraction | 42 ns |
| `datetimeParse`, with a nine-digit fraction | 60 ns |

## Error codes

| Code | Name | Means |
|---|---|---|
| 1201 | `chronoInvalidDate` | a month or day the calendar doesn't have |
| 1202 | `chronoInvalidTime` | an hour, minute, second or nanosecond out of range |
| 1203 | `chronoOutOfRange` | a result outside the range, including every overflow |
| 1204 | `chronoParseFailed` | text that isn't the format |
| 1205 | `chronoInvalidFormat` | a pattern with an unknown directive or a `%` at its end |
| 1206 | `chronoClockUnavailable` | no realtime clock, or no monotonic clock for an instant or a sleep, or reading it failed |

## Limits

- No time zones, no daylight saving and no zone database.
- ISO 8601 extended format only: no week dates, ordinal dates or basic
  format such as `20240229`.
- `datetimeNowUtc` answers `chronoClockUnavailable` on bare metal, and
  after 2262-04-11, where the clock's nanoseconds no longer fit an `Int`.
- `instantNow` and the sleeps answer `chronoClockUnavailable` on bare
  metal and darwin-x86_64, which have no monotonic clock a program can
  read without the C library. On FreeBSD a sleep spins on the clock
  instead of blocking in the kernel; on Windows it waits in `Sleep`, a
  millisecond at a time.

## See also

- [stdlib-api.md](stdlib-api.md) lists every public name in `Chrono`
  with its type and effects.
- [reference.md](reference.md#make-a-handle-other-modules-cant-forge)
  explains the sealed types `Date`, `Time` and `Duration` are made of.
