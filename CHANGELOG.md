# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-23

A full layered date/time hierarchy modelled on Temporal and java.time:
naive calendar (`Date`, `Time`, `DateTime`), TZ-aware (`TimeZone`,
`ZonedDateTime`), and absolute (`Instant`). The parser learned every
shape that comes with that — time-of-day, compound `<date> at <time>`,
ISO 8601 with and without offset, sub-day relative durations, and
explicit date ranges.

### Added

- **`Time`** — naive time-of-day with nanosecond precision, strict
  validation, `midnight`/`noon` constants, `totalNanoseconds()` and
  `compare()` helpers.
- **`DateTime`** — naive `Date` + `Time` pairing. `init`, `now()`
  (UTC), `atMidnight`, `atNoon`, lexicographic `compare()`,
  `addDuration` / `subDuration`.
- **`Duration`** — signed duration with `(i64 seconds, u32 nanoseconds)`
  representation; the nanoseconds field is the non-negative fractional
  part regardless of sign (java.time convention). Constructors for
  every unit from nanoseconds to weeks; `add`/`sub`/`negate`/`compare`/
  `isZero`/`isNegative`/`totalNanoseconds`.
- **`Instant`** — absolute UTC moment with nanosecond precision. `now()` /
  `nowChecked()` own the cross-platform clock read. `fromUnix{Millis,Micros}`,
  `fromEpochSeconds`, `addDuration` / `subDuration` / `durationSince`,
  `toUtc{Date,DateTime}`, `toDateTimeAtOffset` projection.
- **`TimeZone`** — fixed offset with seconds precision (supports half-hour
  zones like India +05:30 and Nepal +05:45). `utc` constant,
  `fromHours` / `fromHoursMinutes` / `fromSeconds` constructors,
  validated ±18-hour bound.
- **`ZonedDateTime`** — `DateTime` + `TimeZone` pairing.
  `fromInstant` / `toInstant` round-trip exact across UTC, JST,
  IST (half-hour), and pre-1970 negative epochs. `compare()` is
  instant-based (chronological); `equalsExact()` requires both
  fields to match. `addDuration` / `subDuration` via Instant.
- **`DateRange`** — explicit calendar date range with inclusive endpoints.
  `days()`, `contains()`, and validated `init()` rejecting end-before-start.
- **`WeekStart`** enum (`.monday` / `.sunday`) and a required
  `week_start` parameter on `startOfWeek` / `endOfWeek`.
- **Parser — bare time of day:** `9am`, `9:30 pm`, `14:30`, `00:00:00`,
  `noon`, `midnight`. With a `DateTime` or `ZonedDateTime` reference,
  the parser applies the today-if-future-else-tomorrow anchoring rule.
- **Parser — date+time compounds:** `tomorrow at 2pm`, `next friday 14:30`,
  `end of month at noon`, `tomorrow 9 am` (with internal-space time).
- **Parser — ISO 8601:** `2024-06-15T14:30:00`, with fractional seconds
  at 1..9 digit precision, `Z`/`+HH:MM`/`-HH:MM`/`±HHMM` offsets, and
  the RFC 3339 §5.6 NOTE space-separator form.
- **Parser — sub-day relative durations:** `in 5 min`, `in 30 sec`,
  `in 2 hours`, `5 minutes ago`. With `Date` reference returns
  `.duration`; with time-bearing reference anchors to `.datetime` /
  `.zoned`. Day+ deltas continue to return `.date`.
- **Parser — explicit date ranges:** `jan 15 to feb 1`, `2024-06-01 to
  2024-06-30`, `2024-06-01..2024-06-30`, `between today and friday`,
  `from monday to friday`, `next 7 days`, `last 7 days`,
  `next 2 weeks`.
- **Parser — month + day:** `jul 4`, `4 jul`, `dec 23rd`, `23rd dec`
  fall out naturally from extending the date grammar so range
  endpoints work.
- `pub const version` exported from `root.zig` so consumers can read
  the library version programmatically.
- GitHub Actions CI workflow running `zig build test` on Zig 0.16.0
  across Linux, macOS, and Windows.

### Changed

- **BREAKING:** `ParsedDate` renamed to `ParsedTemporal`. The new union
  exposes additional variants (`.datetime`, `.zoned`, `.instant`,
  `.duration`, `.range`) for the new Layer 2/3 types. Existing variants
  (`.date`, `.period`, `.clear`) are preserved with identical semantics.
- **BREAKING:** `parse()` and `parseWithReference()` return
  `ParsedTemporal`. Existing switches on `.date`, `.period`, `.clear`
  continue to work; exhaustive switches must add new prongs.
- **BREAKING:** `parseWithReference` is now comptime-dispatched on
  `@TypeOf(reference)`. Accepts `Date`, `DateTime`, or `ZonedDateTime`
  — `Date` callers see no change. Other reference types unlock the
  time-of-day and zoned variants.
- **BREAKING:** `startOfWeek` / `endOfWeek` now require a `WeekStart`
  argument. Replace `startOfWeek(d)` with `startOfWeek(d, .monday)`
  for identical behaviour, or pass `.sunday` for US-style weeks.
- `Date.today()` delegates to `Instant.now().toUtcDate()`. The
  cross-platform clock-read logic is consolidated in `Instant.zig`.
- `Date.zig` refactored to the Zig stdlib "file is the type" convention.
  All new type modules follow the same pattern. External consumers
  using `kairoz.Date` are unaffected.

### Fixed

- Parser silently truncated inputs longer than 64 bytes during
  lowercasing, which could cause an overlong input ending in junk to
  alias to a short keyword prefix. Inputs over 64 bytes now return
  `error.InvalidFormat` up front.

### Migration from v0.2.x

The only required change is the union type name:

```zig
// Before (v0.2.x)
const result = try kairoz.parse("tomorrow");
switch (result) {
    .date => |d| ...,
    .period => |p| ...,
    .clear => ...,
}

// After (v0.3.0) — variant arms unchanged, type renamed
const result = try kairoz.parse("tomorrow");
switch (result) {
    .date => |d| ...,
    .period => |p| ...,
    .clear => ...,
    // If your switch is exhaustive, also handle:
    .datetime, .zoned, .instant, .duration, .range => unreachable,
}
```

If you explicitly named the type, rename it:

```zig
// Before
const ParsedDate = kairoz.ParsedDate;

// After
const ParsedTemporal = kairoz.ParsedTemporal;
```

For `startOfWeek` / `endOfWeek`, add the explicit `WeekStart` argument:

```zig
// Before (v0.2.x)
const monday = kairoz.startOfWeek(date);
const sunday = kairoz.endOfWeek(date);

// After (v0.3.0)
const monday = kairoz.startOfWeek(date, .monday);
const sunday = kairoz.endOfWeek(date, .monday);
```

No other changes are required for consumers who were already on v0.2.x.

[0.3.0]: https://github.com/AnthemFlynn/Kairoz/compare/v0.2.1...v0.3.0

## [0.2.1] - 2026-01-15

### Fixed

- Compatibility with Zig 0.16.0 stable. `std.time.timestamp()` was
  removed; `Date.today()` now reads the clock via `clock_gettime`
  on POSIX and `KUSER_SHARED_DATA` on Windows.

## [0.2.0] - 2026-01-13

### Added

- `Period` struct with `start: Date`, `granularity: Granularity`, and
  `end()` method.
- `Granularity` enum (`.day`, `.week`, `.month`, `.year`).
- Period-returning parsers: `next week`, `last month`, `this year`,
  month names (`february`, `dec`), bare years (`2024`).
- Boundary expressions: `end of month`, `beginning of next week`, etc.
- Natural offset inputs: `in 3 days`, `2 weeks ago`.
- Ordinal day inputs: `1st`, `23rd`.
- Weekday modifiers: `next monday`, `last friday`.
- Year arithmetic: `addYears`, `+1y`/`-1y` offsets, year boundary helpers.
- Relative date aliases: `tdy`, `tom`, `yest`.
- Unitless offsets: `+3` (defaults to days).

## [0.1.0] - 2026-01-13

### Added

- Initial release.
- `Date` struct with validated `init` and unchecked `initUnchecked`.
- `parse` / `parseWithReference` accepting `today`, `tomorrow`,
  `yesterday`, weekday names, `+Nd`/`+Nw`/`+Nm` offsets,
  `YYYY-MM-DD`/`MM-DD`/`DD` absolute formats, and `none`/`clear`.
- `addDays`, `addMonths`, `daysBetween`, `daysUntil` arithmetic.
- Week and month boundary helpers.
- `formatRelative` for human-readable output.

[Unreleased]: https://github.com/AnthemFlynn/Kairoz/compare/v0.3.0...HEAD
[0.2.1]: https://github.com/AnthemFlynn/Kairoz/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/AnthemFlynn/Kairoz/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/AnthemFlynn/Kairoz/releases/tag/v0.1.0
