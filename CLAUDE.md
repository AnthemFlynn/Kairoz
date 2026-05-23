# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Skills

Use the `/zig` skill for Zig development tasks. Additional Zig skills available:
- `/zig-doctor` — Diagnose toolchain health and configuration
- `/zig-setup` — First-time Zig toolchain setup with ZVM and ZLS
- `/zig-update` — Update Zig and ZLS to latest nightly
- `/zig-add` — Add a dependency to build.zig.zon

## Project Overview

Kairoz (from καιρός — "the opportune moment") is a natural language date parsing library for Zig. Zero dependencies, stdlib only.

**Current version: v0.3.0**

**Minimum Zig version: 0.16.0 stable** (cross-platform: POSIX + Windows)

**Type hierarchy** (Layer 1 naive → Layer 2 aware → Layer 3 absolute):
- Naive: `Date`, `Time`, `DateTime`, `Period`, `DateRange`, `Duration`
- Aware: `TimeZone` (offset-only in v0.3), `ZonedDateTime`
- Absolute: `Instant`

**Parser features:**
- Relative dates: `today`, `tomorrow`, `yesterday` (aliases: `tdy`, `tom`, `yest`)
- Weekday names: `monday`, `mon`, `next monday`, `last friday`
- Offsets: `+3d`, `-2w`, `+1m`, `-1y`, unitless `+3`/`-2`
- Natural offsets (day+): `in 3 days`, `2 weeks ago`
- Natural offsets (sub-day): `in 5 min`, `in 30 sec`, `in 2 hours`, `5 minutes ago`
- Period references: `next week`, `this month`, `last year`
- Boundary expressions: `end of month`, `beginning of next week`
- Month names + day: `jul 4`, `4 jul`, `dec 23rd`
- Ordinal days: `1st`, `23rd`
- Bare years: `2024`
- Date ranges: `jan 15 to feb 1`, `between today and friday`, `next 7 days`, `..` interval shorthand
- Times: `9am`, `9:30 pm`, `14:30`, `23:59:59`, `noon`, `midnight`
- Date+time compounds: `tomorrow at 2pm`, `next friday 14:30`, `end of month at noon`
- ISO 8601 naive: `2024-06-15T14:30:00`, fractional seconds, space separator
- ISO 8601 zoned: `Z`, `+09:00`, `-05:00`, `+05:30`, `+0900` compact
- Clear values: `none`, `clear`

**Output:**
- `formatRelative` — natural language
- `formatDate` / `formatTime` / `formatDateTime` / `formatZoned` — Moment-style tokens
- `formatIso(value, buf)` — comptime-dispatched ISO 8601 across all temporal types

**Key concept:** `ParsedTemporal` is a tagged union over every possible parse result:
- `.date` — specific calendar date (e.g., "tomorrow")
- `.datetime` — naive date + time-of-day (e.g., "tomorrow at 2pm")
- `.zoned` — TZ-aware moment (e.g., "2024-06-15T14:30:00+09:00")
- `.instant` — absolute UTC moment (rare; mainly an output type)
- `.period` — implicit time span with granularity (e.g., "next month")
- `.range` — explicit start/end date range (e.g., "jan 15 to feb 1")
- `.duration` — unanchored time delta (e.g., "in 5 min" without reference)
- `.clear` — unset intent (e.g., "none")

## Build Commands

```bash
zig build              # Build the library module
zig build test         # Run all tests
```

This is a library-only project — there is no CLI executable or `zig build run` step.

## Architecture

The project ships a single Zig module for consumers:

- **`src/root.zig`** — Public API surface, re-exporting from the modules below.
- **`src/Date.zig`** — `Date` struct, validation, leap-year/days-in-month helpers, `today()`.
- **`src/Time.zig`** — naive time-of-day with nanosecond precision.
- **`src/DateTime.zig`** — naive Date + Time pairing.
- **`src/Duration.zig`** — signed duration with nanosecond precision.
- **`src/Instant.zig`** — absolute UTC moment, owns the cross-platform clock read.
- **`src/TimeZone.zig`** — fixed-offset time zone (no IANA in v0.3.0).
- **`src/ZonedDateTime.zig`** — DateTime + TimeZone with Instant round-trip.
- **`src/DateRange.zig`** — explicit calendar range with inclusive endpoints.
- **`src/parse.zig`** — Natural-language parsing, `ParsedTemporal`, `Period`, `Granularity`.
- **`src/arithmetic.zig`** — `addDays`/`addMonths`/`addYears`, week and month boundaries.
- **`src/format.zig`** — `formatRelative` for human-readable output.

The build system (`build.zig`) registers one module named `"Kairoz"` and wires up a single test step that runs every test in `src/root.zig` and its transitive imports.

## Consumer Integration

Downstream projects add Kairoz via:

**build.zig.zon:**
```zig
.dependencies = .{
    .Kairoz = .{
        .url = "git+https://github.com/AnthemFlynn/Kairoz",
        .hash = "...",
    },
},
```

**build.zig:**
```zig
const kairoz_dep = b.dependency("Kairoz", .{});
exe.root_module.addImport("kairoz", kairoz_dep.module("Kairoz"));
```

## Design Reference

See `docs/plans/` for design documents:
- `2026-01-13-kairoz-library-design.md` — Original v0.1.0 API design
- `2026-01-13-kairoz-v0.2.0-design.md` — Period semantics and expanded parsing

Key documentation:
- Public API specification
- Error types (`DateError`, `ParseError`, `ArithmeticError`)
- `Period` struct with `start`, `granularity`, and `end()` method
- `Granularity` enum: `.day`, `.week`, `.month`, `.year`
