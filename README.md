# Kairoz

Natural language date parsing for Zig.

> *Kairoz* (from Greek kairos) — "the opportune moment"

A zero-dependency library for parsing human-friendly date expressions like "tomorrow", "next friday", or "+2w".

## Features

- **Relative dates**: `today`, `tomorrow`, `yesterday`
- **Weekday names**: `monday`, `mon`, `tuesday`, `tue`, etc.
- **Weekday modifiers**: `next monday`, `last friday`
- **Forward/backward offsets**: `+3d`, `-2w`, `+1m`, `-1y`
- **Year offsets**: `+1y`, `+2y`, `-1y`
- **Natural offsets**: `in 3 days`, `2 weeks ago`
- **Period references**: `next week`, `this month`, `last year`
- **Boundary expressions**: `end of month`, `beginning of week`
- **Month names**: `february`, `dec`
- **Ordinal days**: `1st`, `23rd`
- **Bare years**: `2024`, `2025`
- **Clear values**: `none`, `clear`
- **Absolute formats**: `YYYY-MM-DD`, `MM-DD`, `DD`
- **Date arithmetic**: add days/months/years, week/month boundaries
- **Relative formatting**: "in 3 days", "yesterday", "Jun 20"

## Requirements

- Zig 0.16.0 or later

## Installation

Add Kairoz to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/AnthemFlynn/Kairoz
```

Then in your `build.zig`:

```zig
const kairoz = b.dependency("Kairoz", .{});
exe.root_module.addImport("kairoz", kairoz.module("Kairoz"));
```

## Usage

### Parsing Dates

```zig
const kairoz = @import("kairoz");

// Parse relative to current date
const result = try kairoz.parse("tomorrow");
switch (result) {
    .date => |d| {
        // Use the date: d.year, d.month, d.day
    },
    .period => |p| {
        // A time period with start date and granularity
        // p.start is the first day, p.end() returns the last day
    },
    .clear => {
        // User wants to clear the date field
    },
}

// Parse relative to a specific reference date
const ref = try kairoz.Date.init(2024, 1, 15);
const parsed = try kairoz.parseWithReference("+2w", ref);
// parsed.date is now 2024-01-29
```

### Periods vs Dates

Some expressions return a `Period` instead of a single `Date`. A period represents a span of time with a start date and granularity (day, week, month, or year).

```zig
const kairoz = @import("kairoz");

const ref = try kairoz.Date.init(2024, 1, 15);

// "next month" returns a period, not a specific date
const result = try kairoz.parseWithReference("next month", ref);
switch (result) {
    .period => |p| {
        // p.granularity is .month
        // p.start is 2024-02-01 (first day of February)
        // p.end() returns 2024-02-29 (last day of February)
    },
    else => {},
}

// Month names also return periods
const feb = try kairoz.parseWithReference("february", ref);
// feb.period.start is 2024-02-01, feb.period.granularity is .month

// Bare years return year periods
const year = try kairoz.parseWithReference("2025", ref);
// year.period.start is 2025-01-01, year.period.granularity is .year
```

### Supported Input Formats

| Input | Result Type | Description |
|-------|-------------|-------------|
| `today` | Date | Current date |
| `tomorrow` | Date | Next day |
| `yesterday` | Date | Previous day |
| `monday`, `mon` | Date | Next occurrence of weekday |
| `next monday` | Date | Monday of next week |
| `last friday` | Date | Most recent Friday |
| `+3d`, `-3d` | Date | 3 days forward/backward |
| `+2w`, `-2w` | Date | 2 weeks forward/backward |
| `+1m`, `-1m` | Date | 1 month forward/backward |
| `+1y`, `-1y` | Date | 1 year forward/backward |
| `in 3 days` | Date | 3 days from now |
| `2 weeks ago` | Date | 2 weeks in the past |
| `next week` | Period | The following week (Mon-Sun) |
| `this month` | Period | Current month |
| `last year` | Period | Previous year |
| `end of month` | Date | Last day of current month |
| `beginning of week` | Date | Monday of current week |
| `end of next month` | Date | Last day of next month |
| `february`, `feb` | Period | Next occurrence of February |
| `1st`, `23rd` | Date | Ordinal day in current month |
| `2024` | Period | The year 2024 |
| `none`, `clear` | Clear | Clear/unset value |
| `2024-06-15` | Date | Absolute date |
| `06-15` | Date | Month-day (current year) |
| `15` | Date | Day only (current month) |

### Date Arithmetic

```zig
const kairoz = @import("kairoz");

const date = try kairoz.Date.init(2024, 1, 15);

// Add/subtract days
const later = kairoz.addDays(date, 10);  // 2024-01-25
const earlier = kairoz.addDays(date, -5);  // 2024-01-10

// Add/subtract months (day clamped if needed)
const next_month = try kairoz.addMonths(date, 1);  // 2024-02-15
const prev_month = try kairoz.addMonths(date, -1);  // 2023-12-15

// Add/subtract years
const next_year = try kairoz.addYears(date, 1);  // 2025-01-15
const prev_year = try kairoz.addYears(date, -1);  // 2023-01-15

// Calculate difference
const diff = kairoz.daysBetween(date, later);  // 10

// Days until a date (from today)
const until = kairoz.daysUntil(later);

// Week boundaries (Monday-Sunday weeks)
const monday = kairoz.startOfWeek(date);  // 2024-01-15 (already Monday)
const sunday = kairoz.endOfWeek(date);  // 2024-01-21

// Month boundaries
const first = kairoz.firstDayOfMonth(date);  // 2024-01-01
const last = kairoz.lastDayOfMonth(date);  // 2024-01-31

// Day of week (0=Monday, 6=Sunday)
const dow = kairoz.dayOfWeek(date);  // 0 (Monday)
```

### Relative Formatting

```zig
const kairoz = @import("kairoz");

const ref = kairoz.today();
const target = kairoz.addDays(ref, 5);

var buf: [kairoz.max_format_len]u8 = undefined;
const text = kairoz.formatRelative(target, ref, &buf);
// Returns "in 5 days"
```

Output examples:
- Same day: `"today"`
- +1 day: `"tomorrow"`
- -1 day: `"yesterday"`
- +5 days: `"in 5 days"`
- -3 days: `"3 days ago"`
- Same year: `"Jun 20"`
- Different year: `"Jun 20, 2025"`

## API Reference

### Types

- `Date` — Year (u16), month (u8), day (u8)
- `ParsedDate` — Union: `.date`, `.period`, or `.clear`
- `Period` — A time span with `start: Date` and `granularity: Granularity`
- `Granularity` — Enum: `.day`, `.week`, `.month`, `.year`
- `DateError` — `InvalidYear`, `InvalidMonth`, `InvalidDay`
- `ParseError` — `InvalidFormat`, `InvalidOffset`
- `ArithmeticError` — `YearOutOfRange`

### Functions

| Function | Description |
|----------|-------------|
| `parse(str)` | Parse date string using system date |
| `parseWithReference(str, ref)` | Parse date string with explicit reference |
| `today()` | Get current system date |
| `Date.init(y, m, d)` | Create validated date |
| `addDays(date, n)` | Add/subtract days |
| `addMonths(date, n)` | Add/subtract months |
| `addYears(date, n)` | Add/subtract years |
| `daysBetween(from, to)` | Signed day difference |
| `daysUntil(date)` | Days from today to date |
| `dayOfWeek(date)` | Day of week (0=Mon, 6=Sun) |
| `startOfWeek(date)` | Monday of date's week |
| `endOfWeek(date)` | Sunday of date's week |
| `firstDayOfMonth(date)` | First day of date's month |
| `lastDayOfMonth(date)` | Last day of date's month |
| `formatRelative(date, ref, buf)` | Human-readable relative format |
| `isLeapYear(year)` | Check if year is leap year |
| `daysInMonth(year, month)` | Days in given month |

### Period Methods

| Method | Description |
|--------|-------------|
| `period.end()` | Returns the last day of the period |

## License

MIT
