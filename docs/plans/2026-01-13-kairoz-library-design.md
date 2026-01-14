# Kairoz Library Design

**Date:** 2026-01-13
**Status:** Approved
**Goal:** Extract date parsing from todo CLI into standalone Zig library

## Overview

Kairoz (from καιρός — "the opportune moment") is a natural language date parsing library for Zig. Zero dependencies, stdlib only.

## Scope

**v0.1.0 — Initial release:**
- Relative dates: today, tomorrow, yesterday
- Weekday names: monday, mon, tuesday, tue, etc.
- Forward offsets: +3d, +2w, +1m
- Special values: next week, next month, none, clear
- Absolute formats: YYYY-MM-DD, MM-DD, DD
- Date arithmetic utilities
- Relative formatting for display

**Future versions:**
- v0.2.0: Month names, negative offsets, eow/eom
- v0.3.0: "ago" patterns, "in X days", last/this weekday

## Repository Structure

```
Kairoz/
├── build.zig
├── build.zig.zon
├── src/
│   ├── root.zig        # Public API re-exports
│   ├── Date.zig        # Date type, DateError, validation, today()
│   ├── parse.zig       # ParsedDate, ParseError, parsing functions
│   ├── arithmetic.zig  # addDays, addMonths, daysBetween, daysUntil
│   └── format.zig      # formatRelative, max_format_len
├── docs/
│   └── plans/
├── README.md
├── LICENSE
└── .gitignore
```

## Module Architecture

**Dependency graph (no circular dependencies):**

```
root.zig
   ├── Date.zig        (no internal deps)
   ├── parse.zig       → Date.zig
   ├── arithmetic.zig  → Date.zig
   └── format.zig      → Date.zig, arithmetic.zig
```

Each module has single responsibility:
- **Date.zig** — The type, its errors, construction (including `today()`)
- **parse.zig** — Text → ParsedDate
- **arithmetic.zig** — Date math
- **format.zig** — Date → Text

## Public API

```zig
const kairoz = @import("kairoz");

// === Types ===
const Date = kairoz.Date;              // { year: u16, month: u8, day: u8 }
const DateError = kairoz.DateError;    // InvalidDay, InvalidMonth, InvalidYear
const ParsedDate = kairoz.ParsedDate;  // union(enum) { date: Date, clear }
const ParseError = kairoz.ParseError;  // InvalidFormat, InvalidOffset

// === Construction ===
const date = try kairoz.Date.init(2024, 1, 15);  // validated
const now = kairoz.today();                       // from system clock

// === Parsing ===
const result = try kairoz.parse("tomorrow");  // uses system time
switch (result) {
    .date => |d| // use the date,
    .clear => // handle clear request,
}

// For testing: explicit reference date
const result2 = try kairoz.parseWithReference("tomorrow", reference_date);

// === Arithmetic ===
const next_week = kairoz.addDays(date, 7);
const next_month = kairoz.addMonths(date, 1);
const diff = kairoz.daysBetween(date1, date2);  // i32, signed
const until = kairoz.daysUntil(due_date);       // convenience: daysBetween(today(), date)

// === Formatting ===
var buf: [kairoz.max_format_len]u8 = undefined;
const display = kairoz.formatRelative(date, reference, &buf);  // "tomorrow", "in 3 days", etc.
```

## Module Specifications

### Date.zig

```zig
//! Date type and construction utilities.

const std = @import("std");

pub const DateError = error{
    InvalidDay,
    InvalidMonth,
    InvalidYear,
};

pub const Date = struct {
    year: u16,
    month: u8,  // 1-12
    day: u8,    // 1-31 (validated against month)

    /// Construct a validated Date.
    pub fn init(year: u16, month: u8, day: u8) DateError!Date;

    /// Unchecked construction for internal use.
    pub fn initUnchecked(year: u16, month: u8, day: u8) Date;
};

/// Returns current date from system clock.
pub fn today() Date;

/// Check if year is a leap year.
pub fn isLeapYear(year: u16) bool;

/// Days in given month (accounts for leap years).
pub fn daysInMonth(year: u16, month: u8) u8;
```

### parse.zig

```zig
//! Natural language date parsing.

const Date = @import("Date.zig").Date;
const DateError = @import("Date.zig").DateError;

pub const ParseError = error{
    InvalidFormat,
    InvalidOffset,
};

pub const ParsedDate = union(enum) {
    date: Date,
    clear,
};

/// Parse date string using current system date as reference.
pub fn parse(str: []const u8) (ParseError || DateError)!ParsedDate;

/// Parse date string with explicit reference date (for testing).
pub fn parseWithReference(str: []const u8, reference: Date) (ParseError || DateError)!ParsedDate;
```

**Supported formats:**
- Keywords: `today`, `tomorrow`, `yesterday`, `none`, `clear`
- Weekdays: `monday`, `mon`, `tuesday`, `tue`, etc. (next occurrence)
- Offsets: `+3d`, `+2w`, `+1m`
- Absolute: `YYYY-MM-DD`, `MM-DD`, `DD`

### arithmetic.zig

```zig
//! Date arithmetic operations.

const Date = @import("Date.zig").Date;

/// Add (or subtract) days from a date.
pub fn addDays(date: Date, days: i32) Date;

/// Add (or subtract) months. Day clamped if exceeds target month.
pub fn addMonths(date: Date, months: i32) Date;

/// Signed difference in days between two dates.
pub fn daysBetween(from: Date, to: Date) i32;

/// Days from today until given date. Negative if in past.
pub fn daysUntil(date: Date) i32;
```

### format.zig

```zig
//! Relative date formatting for display.

const Date = @import("Date.zig").Date;

/// Maximum buffer size needed for any formatted output.
pub const max_format_len: usize = 32;

/// Format a date relative to reference for human-readable display.
pub fn formatRelative(date: Date, reference: Date, buf: []u8) []const u8;
```

**Output examples:**
- Same day: `"today"`
- +1 day: `"tomorrow"`
- -1 day: `"yesterday"`
- +2 to +14 days: `"in 5 days"`
- -2 to -14 days: `"5 days ago"`
- Same year: `"Jan 15"`
- Different year: `"Jan 15, 2025"`

### root.zig

```zig
//! Kairoz - Natural language date parsing for Zig

pub const Date = @import("Date.zig").Date;
pub const DateError = @import("Date.zig").DateError;
pub const today = @import("Date.zig").today;
pub const isLeapYear = @import("Date.zig").isLeapYear;
pub const daysInMonth = @import("Date.zig").daysInMonth;

pub const ParsedDate = @import("parse.zig").ParsedDate;
pub const ParseError = @import("parse.zig").ParseError;
pub const parse = @import("parse.zig").parse;
pub const parseWithReference = @import("parse.zig").parseWithReference;

pub const addDays = @import("arithmetic.zig").addDays;
pub const addMonths = @import("arithmetic.zig").addMonths;
pub const daysBetween = @import("arithmetic.zig").daysBetween;
pub const daysUntil = @import("arithmetic.zig").daysUntil;

pub const formatRelative = @import("format.zig").formatRelative;
pub const max_format_len = @import("format.zig").max_format_len;
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module structure | Modular from start | Single responsibility, easier testing |
| Date validation | Constructor with validation | `Date.init()` validates, fields public for advanced use |
| Error sets | Separate `DateError` and `ParseError` | Errors match their domains |
| Time source | Both convenience and explicit | `parse()` for ease, `parseWithReference()` for testing |
| File naming | PascalCase for types | Follows stdlib convention |
| Clear semantics | Tagged union `ParsedDate` | More explicit than `?Date` |
| Buffer handling | Caller-provided | Idiomatic Zig, no hidden allocations |
| `today()` location | Date.zig | Clean dependency graph |

## Consumer Integration

**build.zig.zon:**
```zig
.dependencies = .{
    .kairoz = .{
        .url = "git+https://github.com/<username>/kairoz",
        .hash = "...",
    },
},
```

**build.zig:**
```zig
const kairoz_dep = b.dependency("kairoz", .{});
exe.root_module.addImport("kairoz", kairoz_dep.module("kairoz"));
```

## Testing Strategy

Each module contains inline tests using `std.testing`. Key patterns:

- **Date.zig**: Validation edge cases, leap years
- **parse.zig**: Use `parseWithReference` for deterministic tests
- **arithmetic.zig**: Month boundary clamping, year transitions
- **format.zig**: All output variants with explicit reference dates

Run tests: `zig build test`

## Gap Analysis (Future Work)

| Feature | Version | Priority |
|---------|---------|----------|
| Month names (jan 15, january 15) | v0.2.0 | High |
| Negative offsets (-3d, -2w) | v0.2.0 | High |
| End-of-period (eow, eom) | v0.2.0 | Medium |
| "3 days ago" patterns | v0.3.0 | Medium |
| "in 3 days" patterns | v0.3.0 | Medium |
| last/this weekday distinction | v0.3.0 | Medium |
