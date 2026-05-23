# Kairoz

[![CI](https://github.com/AnthemFlynn/Kairoz/actions/workflows/ci.yml/badge.svg)](https://github.com/AnthemFlynn/Kairoz/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.3.0-blue.svg)](https://github.com/AnthemFlynn/Kairoz/releases)
[![Zig](https://img.shields.io/badge/zig-0.16.0-orange.svg)](https://ziglang.org/download/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Natural-language date and time parsing for Zig. Zero dependencies, stdlib only.

> *Kairoz* (from Greek *kairos*) — "the opportune moment."

A library for parsing human-friendly temporal expressions — `tomorrow at 2pm`, `next friday`, `in 5 minutes`, `2024-06-15T14:30:00+09:00` — into strongly-typed values you can compute on.

---

## Quick example

```zig
const kairoz = @import("kairoz");

// Date reference
const today = kairoz.today();
const next_friday = try kairoz.parseWithReference("next friday", today);

// DateTime reference unlocks time-of-day inputs
const now = kairoz.DateTime.now();
const meeting = try kairoz.parseWithReference("tomorrow at 2pm", now);
switch (meeting) {
    .datetime => |dt| std.debug.print("{d}-{d}-{d} {d}:{d:0>2}\n", .{
        dt.date.year, dt.date.month, dt.date.day,
        dt.time.hour, dt.time.minute,
    }),
    else => unreachable,
}

// ISO 8601 with offset → ZonedDateTime
const launch = try kairoz.parse("2026-06-15T14:30:00+09:00");
const utc = launch.zoned.toInstant(); // 2026-06-15T05:30:00Z

// Custom formatting
var buf: [64]u8 = undefined;
const stamp = try kairoz.formatZoned(launch.zoned, "dddd, MMMM Do YYYY [at] h:mm A Z", &buf);
// "Monday, June 15th 2026 at 2:30 PM +09:00"
```

---

## Type hierarchy

Three layers, modelled after [JS Temporal](https://tc39.es/proposal-temporal/docs/) and `java.time`:

```
Layer 1 — Naive calendar (no time zone)
  Date          year, month, day
  Time          hour, minute, second, nanosecond
  DateTime      Date + Time
  Period        start: Date + Granularity (.day | .week | .month | .year)
  DateRange     start: Date + end: Date (inclusive)
  Duration      i64 seconds + u32 nanoseconds (signed; positive frac)

Layer 2 — TZ-aware
  TimeZone      offset_seconds: i32 (offset-only; IANA reserved for v0.4)
  ZonedDateTime DateTime + TimeZone

Layer 3 — Absolute
  Instant       epoch_seconds: i64 + nanoseconds: u32
```

Conversion is bidirectional and exact:

```
ZonedDateTime ⇄ Instant
              .toInstant() / .fromInstant(instant, zone)

Instant       → Date (UTC) / DateTime (UTC or any offset)
              .toUtcDate() / .toUtcDateTime() / .toDateTimeAtOffset(off)
```

---

## Requirements

- Zig **0.16.0** stable or later
- No external dependencies

---

## Installation

Add Kairoz to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/AnthemFlynn/Kairoz
```

Then in your `build.zig`:

```zig
const kairoz_dep = b.dependency("Kairoz", .{});
exe.root_module.addImport("kairoz", kairoz_dep.module("Kairoz"));
```

---

## Parsing

`parseWithReference(input, reference)` is comptime-dispatched on the reference type. The returned `ParsedTemporal` union variant matches the richest type the *input* expressed; the reference type determines whether time-bearing inputs can be anchored.

| Reference type    | Time-bearing inputs        | Day-only inputs |
|-------------------|----------------------------|-----------------|
| `Date`            | `.duration` (sub-day) or error | `.date` / `.period` / `.range` / `.clear` |
| `DateTime`        | `.datetime`                | `.date` / `.period` / `.range` / `.clear` |
| `ZonedDateTime`   | `.zoned`                   | `.date` / `.period` / `.range` / `.clear` |

ISO 8601 inputs with an offset always return `.zoned`, regardless of the reference.

### Supported input grammar

#### Single dates

| Input              | Result | Notes |
|--------------------|--------|-------|
| `today`, `tdy`     | Date   | reference date |
| `tomorrow`, `tom`  | Date   | reference + 1 day |
| `yesterday`, `yest`| Date   | reference - 1 day |
| `monday`..`sunday` | Date   | next occurrence (skipping today if same weekday) |
| `mon`..`sun`       | Date   | abbreviations |
| `next monday`      | Date   | Monday of next week |
| `last friday`      | Date   | most recent Friday |
| `1st`, `23rd`      | Date   | ordinal day in reference month |
| `jul 4`, `4 jul`   | Date   | month + day (year rolls if past) |
| `dec 23rd`         | Date   | with ordinal |
| `+3d`, `-3d`       | Date   | day offset |
| `+3`, `-3`         | Date   | unitless offset (default: days) |
| `+2w`, `-2w`       | Date   | week offset |
| `+1m`, `-1m`       | Date   | month offset |
| `+1y`, `-1y`       | Date   | year offset |
| `in 3 days`        | Date   | natural-language offset |
| `2 weeks ago`      | Date   | past offset |
| `2024-06-15`       | Date   | ISO 8601 absolute date |
| `06-15`            | Date   | MM-DD, reference year |
| `15`               | Date   | bare day, reference month |

#### Times and datetimes

Require a `DateTime` or `ZonedDateTime` reference.

| Input              | Result   | Notes |
|--------------------|----------|-------|
| `9am`, `2:30 pm`   | DateTime | today-if-future-else-tomorrow |
| `noon`, `midnight` | DateTime | word forms |
| `14:30`            | DateTime | 24-hour |
| `23:59:59`         | DateTime | with seconds |
| `tomorrow at 2pm`  | DateTime | compound |
| `tomorrow 2pm`     | DateTime | implicit separator |
| `next friday 14:30`| DateTime | weekday + time |
| `end of month at noon` | DateTime | boundary + time |
| `in 5 min`         | DateTime | sub-day delta anchored to ref |
| `in 30 sec`        | DateTime | second resolution |
| `5 minutes ago`    | DateTime | past sub-day delta |
| `2024-06-15T14:30:00` | DateTime | ISO local |
| `2024-06-15T14:30:00.500` | DateTime | with fractional seconds |
| `2024-06-15 14:30` | DateTime | RFC 3339 space separator |

#### Zoned datetimes

ISO 8601 with offset returns `.zoned` regardless of reference.

| Input | Result | Notes |
|-------|--------|-------|
| `2024-06-15T14:30:00Z` | ZonedDateTime | UTC |
| `2024-06-15T14:30:00+09:00` | ZonedDateTime | JST |
| `2024-06-15T14:30:00-05:00` | ZonedDateTime | EST |
| `2024-06-15T14:30:00+05:30` | ZonedDateTime | IST (half-hour) |
| `2024-06-15T14:30:00+0900` | ZonedDateTime | compact offset |

#### Periods, ranges, durations, clear

| Input              | Result   | Notes |
|--------------------|----------|-------|
| `next week`        | Period   | full calendar week (Mon..Sun) |
| `this month`       | Period   | calendar month |
| `last year`        | Period   | full year |
| `february`, `feb`  | Period   | next occurrence of that month |
| `2024`             | Period   | bare year as year-granularity period |
| `end of month`     | Date     | boundary expression |
| `beginning of next week` | Date | combined boundary |
| `jan 15 to feb 1`  | DateRange | explicit range |
| `2024-06-01..2024-06-30` | DateRange | ISO interval shorthand |
| `between today and friday` | DateRange | natural range |
| `from monday to friday`| DateRange | with `from` prefix |
| `next 7 days`      | DateRange | inclusive rolling window |
| `last 7 days`      | DateRange | inclusive past window |
| `in 5 min` (Date ref) | Duration | unanchored sub-day delta |
| `30 seconds ago` (Date ref) | Duration | negative sub-day delta |
| `none`, `clear`    | Clear    | unset intent |

---

## Formatting

### Relative (natural language)

```zig
const ref = kairoz.today();
const target = kairoz.addDays(ref, 5);

var buf: [kairoz.max_format_len]u8 = undefined;
const text = kairoz.formatRelative(target, ref, &buf); // "in 5 days"
```

Returns short literals for ±1 day, "in N days" / "N days ago" for ±14, then falls back to `Mon DD` or `Mon DD, YYYY`.

### Custom formats (Moment.js-style tokens)

```zig
var buf: [64]u8 = undefined;
const dt = kairoz.DateTime.init(
    try kairoz.Date.init(2024, 6, 15),
    try kairoz.Time.init(14, 30, 45),
);
const out = try kairoz.formatDateTime(dt, "dddd, MMMM Do YYYY [at] h:mm A", &buf);
// "Saturday, June 15th 2024 at 2:30 PM"
```

| Token | Output | Example |
|-------|--------|---------|
| `YYYY` | 4-digit year | `2024` |
| `YY` | 2-digit year | `24` |
| `MMMM` | Month full | `June` |
| `MMM` | Month abbrev | `Jun` |
| `MM` | 2-digit month | `06` |
| `M` | 1–2 digit month | `6` |
| `DD` | 2-digit day | `05` |
| `D` | 1–2 digit day | `5` |
| `Do` | Ordinal day | `5th`, `23rd` |
| `dddd` | Weekday full | `Monday` |
| `ddd` | Weekday abbrev | `Mon` |
| `HH` | 2-digit hour 24h | `09` |
| `H` | 1–2 digit hour 24h | `9` |
| `hh` | 2-digit hour 12h | `02` |
| `h` | 1–2 digit hour 12h | `2` |
| `mm` / `m` | Minute | `30` / `30` |
| `ss` / `s` | Second | `45` / `45` |
| `SSS` | Milliseconds | `123` |
| `SSSSSS` | Microseconds | `123456` |
| `SSSSSSSSS` | Nanoseconds | `123456789` |
| `a` / `A` | am/pm / AM/PM | `pm` / `PM` |
| `Z` | Offset with colon | `+09:00` (UTC → `Z`) |
| `ZZ` | Compact offset | `+0900` (UTC → `Z`) |
| `[literal]` | Bracket-escape | passes through verbatim |

### ISO 8601 convenience

`formatIso` dispatches on the input type:

```zig
var buf: [64]u8 = undefined;
_ = try kairoz.formatIso(date,    &buf); // "2024-06-15"
_ = try kairoz.formatIso(time,    &buf); // "14:30:45"
_ = try kairoz.formatIso(dt,      &buf); // "2024-06-15T14:30:45"
_ = try kairoz.formatIso(zoned,   &buf); // "2024-06-15T14:30:45+09:00"
_ = try kairoz.formatIso(instant, &buf); // "2024-06-15T05:30:45Z" (UTC projection)
```

---

## Arithmetic

```zig
const d = try kairoz.Date.init(2024, 1, 15);

const later   = kairoz.addDays(d, 10);              // 2024-01-25
const earlier = kairoz.addDays(d, -5);              // 2024-01-10
const next_m  = try kairoz.addMonths(d, 1);         // 2024-02-15
const next_y  = try kairoz.addYears(d, 1);          // 2025-01-15

const diff    = kairoz.daysBetween(d, later);       // 10
const until   = kairoz.daysUntil(later);            // from today

// Week boundaries — explicit WeekStart in v0.3.0
const monday  = kairoz.startOfWeek(d, .monday);     // 2024-01-15
const sunday  = kairoz.endOfWeek(d, .monday);       // 2024-01-21
const us_week = kairoz.startOfWeek(d, .sunday);     // 2024-01-14

const first   = kairoz.firstDayOfMonth(d);          // 2024-01-01
const last    = kairoz.lastDayOfMonth(d);           // 2024-01-31
const dow     = kairoz.dayOfWeek(d);                // 0 (Monday)
```

`DateTime` and `ZonedDateTime` both implement `addDuration` / `subDuration` for sub-second arithmetic. `Instant.now()` reads the system clock and falls back to the Unix epoch on failure (`nowChecked` returns an error union if you need to distinguish).

---

## API Reference

### Types

| Type | Layer | Purpose |
|------|-------|---------|
| `Date` | naive | calendar date (year, month, day) |
| `Time` | naive | time-of-day with nanosecond precision |
| `DateTime` | naive | `Date` + `Time` pairing |
| `Period` | naive | implicit time span (day/week/month/year) |
| `DateRange` | naive | explicit start/end range, inclusive |
| `Duration` | naive | signed seconds + nanoseconds delta |
| `TimeZone` | aware | fixed-offset zone (seconds precision) |
| `ZonedDateTime` | aware | `DateTime` + `TimeZone` |
| `Instant` | absolute | UTC epoch with nanosecond precision |
| `ParsedTemporal` | union | parse result over every variant above |
| `Granularity` | enum | `.day`, `.week`, `.month`, `.year` |
| `WeekStart` | enum | `.monday`, `.sunday` |

### Error sets

| Error | Source |
|-------|--------|
| `DateError` | `InvalidYear`, `InvalidMonth`, `InvalidDay` |
| `TimeError` | `InvalidHour`, `InvalidMinute`, `InvalidSecond`, `InvalidNanosecond` |
| `ArithmeticError` | `YearOutOfRange` |
| `ParseError` | `InvalidFormat`, `InvalidOffset` |
| `TimeZoneError` | `OffsetOutOfRange` |
| `DateRangeError` | `EndBeforeStart` |
| `FormatError` | `BufferTooSmall` |
| `ParseFullError` | union of every error a parse call can return |

### Constants

| Constant | Value |
|----------|-------|
| `version` | `"0.3.0"` |
| `max_format_len` | `32` (buffer hint for `formatRelative`) |
| `max_input_len` | `64` (parser input cap) |
| `Time.midnight` / `Time.noon` | precomputed `Time` values |
| `Instant.epoch` | Unix epoch (`1970-01-01T00:00:00Z`) |
| `TimeZone.utc` | offset 0 |

---

## Migration from v0.2.x

See [CHANGELOG.md](CHANGELOG.md#030---2026-05-23) for the full v0.3.0 entry. The breaking changes:

- `ParsedDate` is now `ParsedTemporal` — existing variants (`.date`, `.period`, `.clear`) preserved.
- `startOfWeek` / `endOfWeek` now require a `WeekStart` argument: `startOfWeek(d, .monday)`.
- `parseWithReference` is comptime-dispatched on reference type — `Date` callers see no change.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Anthem Flynn
