# Kairoz

Natural language date parsing for Zig.

> *Kairoz* (from Greek καιρός) — "the opportune moment"

A zero-dependency library for parsing human-friendly date expressions like "tomorrow", "next friday", or "+2w".

## Features

- **Relative dates**: `today`, `tomorrow`, `yesterday`
- **Weekday names**: `monday`, `mon`, `tuesday`, `tue`, etc.
- **Forward offsets**: `+3d`, `+2w`, `+1m`
- **Clear values**: `none`, `clear`
- **Absolute formats**: `YYYY-MM-DD`, `MM-DD`, `DD`
- **Date arithmetic**: add days/months, calculate differences
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
    .clear => {
        // User wants to clear the date field
    },
}

// Parse relative to a specific reference date
const ref = try kairoz.Date.init(2024, 1, 15);
const parsed = try kairoz.parseWithReference("+2w", ref);
// parsed.date is now 2024-01-29
```

### Supported Input Formats

| Input | Description |
|-------|-------------|
| `today` | Current date |
| `tomorrow` | Next day |
| `yesterday` | Previous day |
| `monday`, `mon` | Next occurrence of weekday |
| `+3d` | 3 days from now |
| `+2w` | 2 weeks from now |
| `+1m` | 1 month from now |
| `none`, `clear` | Clear/unset value |
| `2024-06-15` | Absolute date |
| `06-15` | Month-day (current year) |
| `15` | Day only (current month) |

### Date Arithmetic

```zig
const kairoz = @import("kairoz");

const date = try kairoz.Date.init(2024, 1, 15);

// Add days
const later = kairoz.addDays(date, 10);  // 2024-01-25

// Add months (day clamped if needed)
const next_month = try kairoz.addMonths(date, 1);  // 2024-02-15

// Calculate difference
const diff = kairoz.daysBetween(date, later);  // 10

// Days until a date (from today)
const until = kairoz.daysUntil(later);
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
- `ParsedDate` — Union of `.date` or `.clear`
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
| `daysBetween(from, to)` | Signed day difference |
| `daysUntil(date)` | Days from today to date |
| `formatRelative(date, ref, buf)` | Human-readable relative format |
| `isLeapYear(year)` | Check if year is leap year |
| `daysInMonth(year, month)` | Days in given month |

## License

MIT
