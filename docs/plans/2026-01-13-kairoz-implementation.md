# Kairoz v0.1.0 Implementation Plan

**Goal:** Implement Kairoz natural language date parsing library with modular architecture.

**Architecture:** Four modules (Date.zig, arithmetic.zig, parse.zig, format.zig) with root.zig re-exporting public API. Clean dependency graph: Date is foundation, arithmetic and parse depend on Date, format depends on Date and arithmetic.

**Tech Stack:** Zig 0.16+, stdlib only, no external dependencies

**Git Strategy:**
- `main` — stable releases only
- `dev` — integration branch
- `feature/*` — feature branches from dev
- After each feature: PR → review → fix → merge to dev

---

## Execution Phases

```
Phase 1: Foundation (Sequential - 1 agent)
└── Task 1: Setup + Date.zig

Phase 2: Core Modules (Parallel - up to 4 agents)
├── Task 2: arithmetic.zig        [Agent 1]
├── Task 3: parse.zig keywords    [Agent 2]
├── Task 4: parse.zig weekdays    [Agent 3]
└── Task 5: parse.zig offsets     [Agent 4]

Phase 3: Integration (Sequential after Phase 2)
├── Task 6: parse.zig absolute dates
├── Task 7: format.zig
└── Task 8: root.zig + final integration

Phase 4: Cleanup
└── Task 9: Final review + merge to main
```

---

## Phase 1: Foundation

### Task 1: Setup + Date.zig

**Branch:** `feature/date-module`

**Files:**
- Create: `src/Date.zig`
- Modify: `src/root.zig` (replace template)
- Modify: `build.zig` (simplify for library-only)
- Delete: `src/main.zig` (not needed for v0.1.0)

#### Step 1: Create feature branch

```bash
git checkout dev
git checkout -b feature/date-module
```

#### Step 2: Simplify build.zig for library-only

Replace `build.zig` with:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module exposed to consumers
    const mod = b.addModule("kairoz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

#### Step 3: Delete main.zig, create minimal root.zig

Delete `src/main.zig`.

Create `src/root.zig`:

```zig
//! Kairoz - Natural language date parsing for Zig
//!
//! A zero-dependency library for parsing human-friendly date expressions.

pub const Date = @import("Date.zig").Date;
pub const DateError = @import("Date.zig").DateError;

test {
    _ = @import("Date.zig");
}
```

#### Step 4: Write failing test for Date.init

Create `src/Date.zig`:

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
    month: u8,
    day: u8,
};

test "Date.init validates month range" {
    // Should fail - init not implemented yet
    _ = try Date.init(2024, 1, 15);
}
```

#### Step 5: Run test to verify it fails

```bash
zig build test
```

Expected: FAIL - `init` not defined

#### Step 6: Implement Date.init

Update `src/Date.zig` - add to Date struct:

```zig
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    /// Construct a validated Date. Returns error if values are out of range.
    pub fn init(year: u16, month: u8, day: u8) DateError!Date {
        if (year == 0) return error.InvalidYear;
        if (month < 1 or month > 12) return error.InvalidMonth;
        const max_day = daysInMonth(year, month);
        if (day < 1 or day > max_day) return error.InvalidDay;
        return .{ .year = year, .month = month, .day = day };
    }

    /// Unchecked construction for internal use where values are known-valid.
    pub fn initUnchecked(year: u16, month: u8, day: u8) Date {
        return .{ .year = year, .month = month, .day = day };
    }
};
```

#### Step 7: Implement helper functions

Add to `src/Date.zig` (after Date struct):

```zig
/// Check if year is a leap year.
pub fn isLeapYear(year: u16) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    return @mod(year, 4) == 0;
}

/// Days in given month (accounts for leap years).
pub fn daysInMonth(year: u16, month: u8) u8 {
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isLeapYear(year)) return 29;
    return days[month - 1];
}

/// Returns current date from system clock.
pub fn today() Date {
    const ts = std.time.timestamp();
    const epoch_secs: u64 = @intCast(ts);
    const epoch_day = @divFloor(epoch_secs, 86400);
    return epochDayToDate(@intCast(epoch_day));
}

/// Convert epoch day (days since 1970-01-01) to Date.
fn epochDayToDate(epoch_day: i32) Date {
    // Algorithm from Howard Hinnant's date algorithms
    var z = epoch_day + 719468;
    const era: i32 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: u32 = @intCast(z - era * 146097);
    const yoe: u32 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i32 = @as(i32, @intCast(yoe)) + era * 400;
    const doy: u32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: u32 = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = if (mp < 10) @intCast(mp + 3) else @intCast(mp - 9);
    const year: u16 = @intCast(if (m <= 2) y + 1 else y);
    return Date.initUnchecked(year, m, d);
}
```

#### Step 8: Add comprehensive tests

Add tests to `src/Date.zig`:

```zig
test "Date.init validates month range" {
    _ = try Date.init(2024, 1, 15);
    _ = try Date.init(2024, 12, 31);
    try std.testing.expectError(error.InvalidMonth, Date.init(2024, 0, 15));
    try std.testing.expectError(error.InvalidMonth, Date.init(2024, 13, 15));
}

test "Date.init validates day range" {
    _ = try Date.init(2024, 1, 1);
    _ = try Date.init(2024, 1, 31);
    try std.testing.expectError(error.InvalidDay, Date.init(2024, 1, 0));
    try std.testing.expectError(error.InvalidDay, Date.init(2024, 1, 32));
    try std.testing.expectError(error.InvalidDay, Date.init(2024, 4, 31)); // April has 30 days
}

test "Date.init validates year" {
    _ = try Date.init(1, 1, 1);
    _ = try Date.init(9999, 12, 31);
    try std.testing.expectError(error.InvalidYear, Date.init(0, 1, 1));
}

test "Date.init handles leap years" {
    _ = try Date.init(2024, 2, 29); // 2024 is leap year
    try std.testing.expectError(error.InvalidDay, Date.init(2023, 2, 29)); // 2023 is not
    _ = try Date.init(2000, 2, 29); // 2000 is leap year (divisible by 400)
    try std.testing.expectError(error.InvalidDay, Date.init(1900, 2, 29)); // 1900 is not (divisible by 100)
}

test "isLeapYear" {
    try std.testing.expect(isLeapYear(2024));
    try std.testing.expect(!isLeapYear(2023));
    try std.testing.expect(isLeapYear(2000));
    try std.testing.expect(!isLeapYear(1900));
}

test "daysInMonth" {
    try std.testing.expectEqual(@as(u8, 31), daysInMonth(2024, 1));
    try std.testing.expectEqual(@as(u8, 29), daysInMonth(2024, 2)); // leap
    try std.testing.expectEqual(@as(u8, 28), daysInMonth(2023, 2)); // not leap
    try std.testing.expectEqual(@as(u8, 30), daysInMonth(2024, 4));
    try std.testing.expectEqual(@as(u8, 31), daysInMonth(2024, 12));
}

test "epochDayToDate known dates" {
    // 1970-01-01 is epoch day 0
    const epoch = epochDayToDate(0);
    try std.testing.expectEqual(@as(u16, 1970), epoch.year);
    try std.testing.expectEqual(@as(u8, 1), epoch.month);
    try std.testing.expectEqual(@as(u8, 1), epoch.day);

    // 2024-01-15 is epoch day 19737
    const jan15 = epochDayToDate(19737);
    try std.testing.expectEqual(@as(u16, 2024), jan15.year);
    try std.testing.expectEqual(@as(u8, 1), jan15.month);
    try std.testing.expectEqual(@as(u8, 15), jan15.day);
}
```

#### Step 9: Run tests

```bash
zig build test
```

Expected: All PASS

#### Step 10: Commit and create PR

```bash
git add -A
git commit -m "feat(Date): implement Date type with validation and today()

- Date.init() validates year/month/day ranges
- Date.initUnchecked() for internal known-valid construction
- isLeapYear() and daysInMonth() helpers
- today() returns current date from system clock
- Comprehensive test coverage for edge cases"
```

#### Step 11: PR and Review

```bash
git push -u origin feature/date-module
```

Create PR to dev. Run code review. Fix any issues. Merge to dev.

```bash
git checkout dev
git merge feature/date-module
git branch -d feature/date-module
```

---

## Phase 2: Core Modules (Parallel)

> **IMPORTANT:** All 4 tasks in Phase 2 can run in parallel after Task 1 completes.
> Each agent should create their own feature branch from `dev`.

### Task 2: arithmetic.zig [Agent 1]

**Branch:** `feature/arithmetic-module`

**Files:**
- Create: `src/arithmetic.zig`
- Modify: `src/root.zig` (add exports)

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/arithmetic-module
```

#### Step 2: Write failing test for addDays

Create `src/arithmetic.zig`:

```zig
//! Date arithmetic operations.

const std = @import("std");
const Date = @import("Date.zig").Date;
const daysInMonth = @import("Date.zig").daysInMonth;
const isLeapYear = @import("Date.zig").isLeapYear;

test "addDays adds days within same month" {
    const date = Date.initUnchecked(2024, 1, 15);
    const result = addDays(date, 5);
    try std.testing.expectEqual(@as(u8, 20), result.day);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}
```

#### Step 3: Run test to verify failure

```bash
zig build test
```

Expected: FAIL - `addDays` not defined

#### Step 4: Implement addDays

Add to `src/arithmetic.zig`:

```zig
/// Add (or subtract) days from a date.
pub fn addDays(date: Date, days: i32) Date {
    const epoch_days = dateToEpochDays(date);
    const new_days = epoch_days + days;
    return epochDaysToDate(new_days);
}

/// Convert Date to epoch days (days since 1970-01-01).
fn dateToEpochDays(date: Date) i32 {
    const y: i32 = @as(i32, date.year) - @as(i32, if (date.month <= 2) 1 else 0);
    const era: i32 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const m: u32 = date.month;
    const d: u32 = date.day;
    const doy: u32 = @divFloor(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + d - 1;
    const doe: u32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + @as(i32, @intCast(doe)) - 719468;
}

/// Convert epoch days to Date.
fn epochDaysToDate(epoch_day: i32) Date {
    var z = epoch_day + 719468;
    const era: i32 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: u32 = @intCast(z - era * 146097);
    const yoe: u32 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i32 = @as(i32, @intCast(yoe)) + era * 400;
    const doy: u32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: u32 = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = if (mp < 10) @intCast(mp + 3) else @intCast(mp - 9);
    const year: u16 = @intCast(if (m <= 2) y + 1 else y);
    return Date.initUnchecked(year, m, d);
}
```

#### Step 5: Add more addDays tests

```zig
test "addDays crosses month boundary" {
    const date = Date.initUnchecked(2024, 1, 30);
    const result = addDays(date, 5);
    try std.testing.expectEqual(@as(u8, 4), result.day);
    try std.testing.expectEqual(@as(u8, 2), result.month);
}

test "addDays crosses year boundary" {
    const date = Date.initUnchecked(2024, 12, 30);
    const result = addDays(date, 5);
    try std.testing.expectEqual(@as(u8, 4), result.day);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2025), result.year);
}

test "addDays subtracts days" {
    const date = Date.initUnchecked(2024, 1, 15);
    const result = addDays(date, -10);
    try std.testing.expectEqual(@as(u8, 5), result.day);
    try std.testing.expectEqual(@as(u8, 1), result.month);
}

test "addDays handles leap year" {
    const date = Date.initUnchecked(2024, 2, 28);
    const result = addDays(date, 1);
    try std.testing.expectEqual(@as(u8, 29), result.day); // leap year
    try std.testing.expectEqual(@as(u8, 2), result.month);
}
```

#### Step 6: Write failing test for addMonths

```zig
test "addMonths adds months within same year" {
    const date = Date.initUnchecked(2024, 3, 15);
    const result = addMonths(date, 2);
    try std.testing.expectEqual(@as(u8, 5), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}
```

#### Step 7: Implement addMonths

```zig
/// Add (or subtract) months from a date. Day is clamped if it exceeds target month.
pub fn addMonths(date: Date, months: i32) Date {
    const total_months: i32 = @as(i32, date.year) * 12 + @as(i32, date.month - 1) + months;

    var new_year: i32 = @divFloor(total_months, 12);
    var new_month: i32 = @mod(total_months, 12) + 1;

    // Handle negative mod result
    if (new_month <= 0) {
        new_month += 12;
        new_year -= 1;
    }

    const year: u16 = @intCast(new_year);
    const month: u8 = @intCast(new_month);
    const max_day = daysInMonth(year, month);
    const day = @min(date.day, max_day);

    return Date.initUnchecked(year, month, day);
}
```

#### Step 8: Add more addMonths tests

```zig
test "addMonths crosses year boundary" {
    const date = Date.initUnchecked(2024, 11, 15);
    const result = addMonths(date, 3);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u16, 2025), result.year);
}

test "addMonths clamps day" {
    const date = Date.initUnchecked(2024, 1, 31);
    const result = addMonths(date, 1);
    try std.testing.expectEqual(@as(u8, 29), result.day); // Feb 2024 has 29 days
    try std.testing.expectEqual(@as(u8, 2), result.month);
}

test "addMonths subtracts months" {
    const date = Date.initUnchecked(2024, 3, 15);
    const result = addMonths(date, -2);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}
```

#### Step 9: Write failing test for daysBetween

```zig
test "daysBetween same date" {
    const date = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectEqual(@as(i32, 0), daysBetween(date, date));
}
```

#### Step 10: Implement daysBetween and daysUntil

```zig
/// Calculate signed difference in days between two dates.
pub fn daysBetween(from: Date, to: Date) i32 {
    return dateToEpochDays(to) - dateToEpochDays(from);
}

/// Convenience: days from today until given date. Negative if date is in past.
pub fn daysUntil(date: Date) i32 {
    const now = @import("Date.zig").today();
    return daysBetween(now, date);
}
```

#### Step 11: Add daysBetween tests

```zig
test "daysBetween positive" {
    const from = Date.initUnchecked(2024, 1, 15);
    const to = Date.initUnchecked(2024, 1, 20);
    try std.testing.expectEqual(@as(i32, 5), daysBetween(from, to));
}

test "daysBetween negative" {
    const from = Date.initUnchecked(2024, 1, 20);
    const to = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectEqual(@as(i32, -5), daysBetween(from, to));
}

test "daysBetween across years" {
    const from = Date.initUnchecked(2024, 12, 31);
    const to = Date.initUnchecked(2025, 1, 1);
    try std.testing.expectEqual(@as(i32, 1), daysBetween(from, to));
}
```

#### Step 12: Update root.zig

Add to `src/root.zig`:

```zig
pub const addDays = @import("arithmetic.zig").addDays;
pub const addMonths = @import("arithmetic.zig").addMonths;
pub const daysBetween = @import("arithmetic.zig").daysBetween;
pub const daysUntil = @import("arithmetic.zig").daysUntil;

test {
    _ = @import("Date.zig");
    _ = @import("arithmetic.zig");
}
```

#### Step 13: Run all tests

```bash
zig build test
```

Expected: All PASS

#### Step 14: Commit and PR

```bash
git add -A
git commit -m "feat(arithmetic): implement date arithmetic functions

- addDays() for day-based arithmetic
- addMonths() with day clamping for shorter months
- daysBetween() for signed day difference
- daysUntil() convenience wrapper"

git push -u origin feature/arithmetic-module
```

Create PR, review, fix issues, merge to dev.

---

### Task 3: parse.zig keywords [Agent 2]

**Branch:** `feature/parse-keywords`

**Files:**
- Create: `src/parse.zig`
- Modify: `src/root.zig` (add exports)

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/parse-keywords
```

#### Step 2: Create parse.zig with types

```zig
//! Natural language date parsing.

const std = @import("std");
const Date = @import("Date.zig").Date;
const DateError = @import("Date.zig").DateError;
const today = @import("Date.zig").today;

pub const ParseError = error{
    InvalidFormat,
    InvalidOffset,
};

pub const ParsedDate = union(enum) {
    date: Date,
    clear,
};

/// Parse date string using current system date as reference.
pub fn parse(str: []const u8) (ParseError || DateError)!ParsedDate {
    return parseWithReference(str, today());
}

/// Parse date string with explicit reference date (for testing).
pub fn parseWithReference(str: []const u8, reference: Date) (ParseError || DateError)!ParsedDate {
    _ = str;
    _ = reference;
    return error.InvalidFormat; // Not implemented yet
}
```

#### Step 3: Write failing test for "today"

```zig
test "parse 'today' returns reference date" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("today", ref);
    try std.testing.expectEqual(ref, result.date);
}
```

#### Step 4: Run test to verify failure

```bash
zig build test
```

Expected: FAIL - returns InvalidFormat

#### Step 5: Implement keyword parsing

Update `parseWithReference`:

```zig
pub fn parseWithReference(str: []const u8, reference: Date) (ParseError || DateError)!ParsedDate {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return error.InvalidFormat;

    // Normalize to lowercase
    var lower_buf: [64]u8 = undefined;
    const lower = toLower(trimmed, &lower_buf);

    // Clear keywords
    if (std.mem.eql(u8, lower, "none") or std.mem.eql(u8, lower, "clear")) {
        return .clear;
    }

    // Relative keywords
    if (std.mem.eql(u8, lower, "today")) {
        return .{ .date = reference };
    }
    if (std.mem.eql(u8, lower, "tomorrow")) {
        return .{ .date = addDaysInternal(reference, 1) };
    }
    if (std.mem.eql(u8, lower, "yesterday")) {
        return .{ .date = addDaysInternal(reference, -1) };
    }

    return error.InvalidFormat;
}

fn toLower(str: []const u8, buf: []u8) []const u8 {
    const len = @min(str.len, buf.len);
    for (str[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..len];
}

fn addDaysInternal(date: Date, days: i32) Date {
    // Simple implementation for internal use
    const epoch_days = dateToEpochDays(date);
    return epochDaysToDate(epoch_days + days);
}

fn dateToEpochDays(date: Date) i32 {
    const y: i32 = @as(i32, date.year) - @as(i32, if (date.month <= 2) 1 else 0);
    const era: i32 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const m: u32 = date.month;
    const d: u32 = date.day;
    const doy: u32 = @divFloor(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + d - 1;
    const doe: u32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + @as(i32, @intCast(doe)) - 719468;
}

fn epochDaysToDate(epoch_day: i32) Date {
    var z = epoch_day + 719468;
    const era: i32 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: u32 = @intCast(z - era * 146097);
    const yoe: u32 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i32 = @as(i32, @intCast(yoe)) + era * 400;
    const doy: u32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: u32 = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = if (mp < 10) @intCast(mp + 3) else @intCast(mp - 9);
    const year: u16 = @intCast(if (m <= 2) y + 1 else y);
    return Date.initUnchecked(year, m, d);
}
```

#### Step 6: Add comprehensive keyword tests

```zig
test "parse 'tomorrow' returns next day" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("tomorrow", ref);
    try std.testing.expectEqual(@as(u8, 16), result.date.day);
}

test "parse 'yesterday' returns previous day" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("yesterday", ref);
    try std.testing.expectEqual(@as(u8, 14), result.date.day);
}

test "parse 'none' returns clear" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("none", ref);
    try std.testing.expectEqual(ParsedDate.clear, result);
}

test "parse 'clear' returns clear" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("clear", ref);
    try std.testing.expectEqual(ParsedDate.clear, result);
}

test "parse is case insensitive" {
    const ref = Date.initUnchecked(2024, 1, 15);
    _ = try parseWithReference("TODAY", ref);
    _ = try parseWithReference("Today", ref);
    _ = try parseWithReference("TOMORROW", ref);
}

test "parse trims whitespace" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("  today  ", ref);
    try std.testing.expectEqual(ref, result.date);
}

test "parse empty string returns error" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidFormat, parseWithReference("", ref));
    try std.testing.expectError(error.InvalidFormat, parseWithReference("   ", ref));
}
```

#### Step 7: Update root.zig

```zig
pub const ParsedDate = @import("parse.zig").ParsedDate;
pub const ParseError = @import("parse.zig").ParseError;
pub const parse = @import("parse.zig").parse;
pub const parseWithReference = @import("parse.zig").parseWithReference;

test {
    _ = @import("Date.zig");
    _ = @import("parse.zig");
}
```

#### Step 8: Run tests

```bash
zig build test
```

#### Step 9: Commit and PR

```bash
git add -A
git commit -m "feat(parse): implement keyword parsing (today, tomorrow, yesterday, none, clear)

- ParsedDate tagged union for clear semantics
- parseWithReference() for testable parsing
- Case-insensitive, whitespace-trimmed input"

git push -u origin feature/parse-keywords
```

Create PR, review, fix issues, merge to dev.

---

### Task 4: parse.zig weekdays [Agent 3]

**Branch:** `feature/parse-weekdays`

**Depends on:** Task 3 merged to dev

**Files:**
- Modify: `src/parse.zig` (add weekday parsing)

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/parse-weekdays
```

#### Step 2: Write failing test for weekday

```zig
test "parse 'monday' returns next monday" {
    // Reference: Wednesday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("monday", ref);
    // Next Monday is Jan 22, 2024
    try std.testing.expectEqual(@as(u8, 22), result.date.day);
    try std.testing.expectEqual(@as(u8, 1), result.date.month);
}
```

#### Step 3: Implement weekday parsing

Add to `parseWithReference` (before final return):

```zig
    // Weekday names
    if (parseWeekday(lower)) |target_dow| {
        return .{ .date = nextWeekday(reference, target_dow) };
    }
```

Add helper functions:

```zig
/// Parse weekday name, returns 0-6 (Mon-Sun) or null.
fn parseWeekday(name: []const u8) ?u8 {
    const weekdays = [_]struct { full: []const u8, abbrev: []const u8, dow: u8 }{
        .{ .full = "monday", .abbrev = "mon", .dow = 0 },
        .{ .full = "tuesday", .abbrev = "tue", .dow = 1 },
        .{ .full = "wednesday", .abbrev = "wed", .dow = 2 },
        .{ .full = "thursday", .abbrev = "thu", .dow = 3 },
        .{ .full = "friday", .abbrev = "fri", .dow = 4 },
        .{ .full = "saturday", .abbrev = "sat", .dow = 5 },
        .{ .full = "sunday", .abbrev = "sun", .dow = 6 },
    };
    for (weekdays) |wd| {
        if (std.mem.eql(u8, name, wd.full) or std.mem.eql(u8, name, wd.abbrev)) {
            return wd.dow;
        }
    }
    return null;
}

/// Get day of week for date (0=Mon, 6=Sun).
fn dayOfWeek(date: Date) u8 {
    const epoch_days = dateToEpochDays(date);
    // Jan 1, 1970 was Thursday (3)
    const dow = @mod(epoch_days + 3, 7);
    return @intCast(if (dow < 0) dow + 7 else dow);
}

/// Find next occurrence of target weekday (always in future, 1-7 days ahead).
fn nextWeekday(from: Date, target_dow: u8) Date {
    const current_dow = dayOfWeek(from);
    var days_ahead: i32 = @as(i32, target_dow) - @as(i32, current_dow);
    if (days_ahead <= 0) {
        days_ahead += 7;
    }
    return addDaysInternal(from, days_ahead);
}
```

#### Step 4: Add comprehensive weekday tests

```zig
test "parse 'friday' returns next friday" {
    // Reference: Wednesday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("friday", ref);
    // Next Friday is Jan 19, 2024
    try std.testing.expectEqual(@as(u8, 19), result.date.day);
}

test "parse weekday abbreviations" {
    const ref = Date.initUnchecked(2024, 1, 15); // Wednesday
    _ = try parseWithReference("mon", ref);
    _ = try parseWithReference("tue", ref);
    _ = try parseWithReference("wed", ref);
    _ = try parseWithReference("thu", ref);
    _ = try parseWithReference("fri", ref);
    _ = try parseWithReference("sat", ref);
    _ = try parseWithReference("sun", ref);
}

test "parse same weekday returns next week" {
    // Reference: Wednesday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("wednesday", ref);
    // Same day should return next week
    try std.testing.expectEqual(@as(u8, 22), result.date.day);
}

test "dayOfWeek calculation" {
    // Jan 15, 2024 is Monday
    try std.testing.expectEqual(@as(u8, 0), dayOfWeek(Date.initUnchecked(2024, 1, 15)));
    // Jan 1, 1970 is Thursday
    try std.testing.expectEqual(@as(u8, 3), dayOfWeek(Date.initUnchecked(1970, 1, 1)));
}
```

#### Step 5: Run tests, commit, PR

```bash
zig build test
git add -A
git commit -m "feat(parse): add weekday parsing (monday, mon, etc.)

- Full and abbreviated weekday names
- Always returns next occurrence (1-7 days ahead)"

git push -u origin feature/parse-weekdays
```

---

### Task 5: parse.zig offsets [Agent 4]

**Branch:** `feature/parse-offsets`

**Depends on:** Task 3 merged to dev

**Files:**
- Modify: `src/parse.zig` (add offset parsing)

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/parse-offsets
```

#### Step 2: Write failing test for offset

```zig
test "parse '+3d' adds 3 days" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+3d", ref);
    try std.testing.expectEqual(@as(u8, 18), result.date.day);
}
```

#### Step 3: Implement offset parsing

Add to `parseWithReference` (before weekday check):

```zig
    // Offset patterns: +3d, +2w, +1m
    if (trimmed.len > 0 and trimmed[0] == '+') {
        return .{ .date = try parseOffset(trimmed[1..], reference) };
    }
```

Add helper:

```zig
/// Parse offset like "3d", "2w", "1m".
fn parseOffset(str: []const u8, reference: Date) (ParseError || DateError)!Date {
    if (str.len < 2) return error.InvalidOffset;

    const unit = str[str.len - 1];
    const num_str = str[0 .. str.len - 1];

    const num = std.fmt.parseInt(i32, num_str, 10) catch return error.InvalidOffset;
    if (num < 0) return error.InvalidOffset;

    return switch (unit) {
        'd' => addDaysInternal(reference, num),
        'w' => addDaysInternal(reference, num * 7),
        'm' => addMonthsInternal(reference, num),
        else => error.InvalidOffset,
    };
}

fn addMonthsInternal(date: Date, months: i32) Date {
    const daysInMonthFn = @import("Date.zig").daysInMonth;
    const total_months: i32 = @as(i32, date.year) * 12 + @as(i32, date.month - 1) + months;

    var new_year: i32 = @divFloor(total_months, 12);
    var new_month: i32 = @mod(total_months, 12) + 1;

    if (new_month <= 0) {
        new_month += 12;
        new_year -= 1;
    }

    const year: u16 = @intCast(new_year);
    const month: u8 = @intCast(new_month);
    const max_day = daysInMonthFn(year, month);
    const day = @min(date.day, max_day);

    return Date.initUnchecked(year, month, day);
}
```

#### Step 4: Add comprehensive offset tests

```zig
test "parse '+2w' adds 2 weeks" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+2w", ref);
    try std.testing.expectEqual(@as(u8, 29), result.date.day);
}

test "parse '+1m' adds 1 month" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+1m", ref);
    try std.testing.expectEqual(@as(u8, 2), result.date.month);
    try std.testing.expectEqual(@as(u8, 15), result.date.day);
}

test "parse '+1m' clamps day" {
    const ref = Date.initUnchecked(2024, 1, 31);
    const result = try parseWithReference("+1m", ref);
    try std.testing.expectEqual(@as(u8, 29), result.date.day); // Feb 2024
}

test "parse invalid offset returns error" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+", ref));
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+d", ref));
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+3x", ref));
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+-3d", ref));
}
```

#### Step 5: Run tests, commit, PR

```bash
zig build test
git add -A
git commit -m "feat(parse): add offset parsing (+3d, +2w, +1m)

- Day, week, and month offsets
- Month offset clamps day to valid range"

git push -u origin feature/parse-offsets
```

---

## Phase 3: Integration

### Task 6: parse.zig absolute dates

**Branch:** `feature/parse-absolute`

**Depends on:** Tasks 3-5 merged to dev

**Files:**
- Modify: `src/parse.zig`

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/parse-absolute
```

#### Step 2: Write failing tests

```zig
test "parse 'YYYY-MM-DD' format" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("2024-06-15", ref);
    try std.testing.expectEqual(@as(u16, 2024), result.date.year);
    try std.testing.expectEqual(@as(u8, 6), result.date.month);
    try std.testing.expectEqual(@as(u8, 15), result.date.day);
}
```

#### Step 3: Implement absolute date parsing

Add to `parseWithReference` (before final error return):

```zig
    // Absolute formats: YYYY-MM-DD, MM-DD, DD
    return .{ .date = try parseAbsolute(trimmed, reference) };
```

Add helper:

```zig
/// Parse absolute date formats: YYYY-MM-DD, MM-DD, DD
fn parseAbsolute(str: []const u8, reference: Date) (ParseError || DateError)!Date {
    // Try YYYY-MM-DD
    if (str.len == 10 and str[4] == '-' and str[7] == '-') {
        const year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.InvalidFormat;
        return Date.init(year, month, day);
    }

    // Try MM-DD
    if (str.len == 5 and str[2] == '-') {
        const month = std.fmt.parseInt(u8, str[0..2], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[3..5], 10) catch return error.InvalidFormat;
        return Date.init(reference.year, month, day);
    }

    // Try DD (just day number)
    if (str.len <= 2) {
        const day = std.fmt.parseInt(u8, str, 10) catch return error.InvalidFormat;
        return Date.init(reference.year, reference.month, day);
    }

    return error.InvalidFormat;
}
```

#### Step 4: Add more absolute tests

```zig
test "parse 'MM-DD' format uses reference year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("06-20", ref);
    try std.testing.expectEqual(@as(u16, 2024), result.date.year);
    try std.testing.expectEqual(@as(u8, 6), result.date.month);
    try std.testing.expectEqual(@as(u8, 20), result.date.day);
}

test "parse 'DD' format uses reference year and month" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("25", ref);
    try std.testing.expectEqual(@as(u16, 2024), result.date.year);
    try std.testing.expectEqual(@as(u8, 1), result.date.month);
    try std.testing.expectEqual(@as(u8, 25), result.date.day);
}

test "parse absolute validates date" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidDay, parseWithReference("2024-02-30", ref));
    try std.testing.expectError(error.InvalidMonth, parseWithReference("2024-13-01", ref));
}

test "parse unknown format returns error" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidFormat, parseWithReference("not-a-date", ref));
    try std.testing.expectError(error.InvalidFormat, parseWithReference("123", ref));
}
```

#### Step 5: Run tests, commit, PR

```bash
zig build test
git add -A
git commit -m "feat(parse): add absolute date formats (YYYY-MM-DD, MM-DD, DD)

- Full ISO format
- Month-day uses reference year
- Day-only uses reference year and month"

git push -u origin feature/parse-absolute
```

---

### Task 7: format.zig

**Branch:** `feature/format-module`

**Depends on:** Task 2 (arithmetic) merged to dev

**Files:**
- Create: `src/format.zig`
- Modify: `src/root.zig`

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/format-module
```

#### Step 2: Create format.zig with failing test

```zig
//! Relative date formatting for display.

const std = @import("std");
const Date = @import("Date.zig").Date;
const daysBetween = @import("arithmetic.zig").daysBetween;

/// Maximum buffer size needed for any formatted output.
pub const max_format_len: usize = 32;

test "formatRelative returns 'today' for same date" {
    const date = Date.initUnchecked(2024, 1, 15);
    var buf: [max_format_len]u8 = undefined;
    const result = formatRelative(date, date, &buf);
    try std.testing.expectEqualStrings("today", result);
}
```

#### Step 3: Implement formatRelative

```zig
/// Format a date relative to a reference date for human-readable display.
/// Returns a slice - either a string literal or into the provided buffer.
pub fn formatRelative(date: Date, reference: Date, buf: []u8) []const u8 {
    const diff = daysBetween(reference, date);

    // Exact matches - return string literals
    if (diff == 0) return "today";
    if (diff == 1) return "tomorrow";
    if (diff == -1) return "yesterday";

    // Near future (2-14 days)
    if (diff > 1 and diff <= 14) {
        return std.fmt.bufPrint(buf, "in {d} days", .{diff}) catch "soon";
    }

    // Near past (-2 to -14 days)
    if (diff < -1 and diff >= -14) {
        return std.fmt.bufPrint(buf, "{d} days ago", .{-diff}) catch "recently";
    }

    // Fall back to absolute format
    if (date.year == reference.year) {
        return std.fmt.bufPrint(buf, "{s} {d}", .{
            monthAbbrev(date.month),
            date.day,
        }) catch "date";
    } else {
        return std.fmt.bufPrint(buf, "{s} {d}, {d}", .{
            monthAbbrev(date.month),
            date.day,
            date.year,
        }) catch "date";
    }
}

fn monthAbbrev(month: u8) []const u8 {
    const abbrevs = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    if (month < 1 or month > 12) return "???";
    return abbrevs[month - 1];
}
```

#### Step 4: Add comprehensive tests

```zig
test "formatRelative returns 'tomorrow'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2024, 1, 16);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("tomorrow", formatRelative(date, ref, &buf));
}

test "formatRelative returns 'yesterday'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2024, 1, 14);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("yesterday", formatRelative(date, ref, &buf));
}

test "formatRelative returns 'in N days'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2024, 1, 20);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("in 5 days", formatRelative(date, ref, &buf));
}

test "formatRelative returns 'N days ago'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2024, 1, 10);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("5 days ago", formatRelative(date, ref, &buf));
}

test "formatRelative returns month day for same year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2024, 6, 20);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("Jun 20", formatRelative(date, ref, &buf));
}

test "formatRelative returns full date for different year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const date = Date.initUnchecked(2025, 6, 20);
    var buf: [max_format_len]u8 = undefined;
    try std.testing.expectEqualStrings("Jun 20, 2025", formatRelative(date, ref, &buf));
}
```

#### Step 5: Update root.zig

```zig
pub const formatRelative = @import("format.zig").formatRelative;
pub const max_format_len = @import("format.zig").max_format_len;

test {
    _ = @import("Date.zig");
    _ = @import("arithmetic.zig");
    _ = @import("parse.zig");
    _ = @import("format.zig");
}
```

#### Step 6: Run tests, commit, PR

```bash
zig build test
git add -A
git commit -m "feat(format): implement formatRelative for display

- Returns 'today', 'tomorrow', 'yesterday' for exact matches
- 'in N days' / 'N days ago' for near dates
- 'Mon DD' or 'Mon DD, YYYY' for distant dates"

git push -u origin feature/format-module
```

---

### Task 8: root.zig + Final Integration

**Branch:** `feature/final-integration`

**Depends on:** All previous tasks merged to dev

**Files:**
- Modify: `src/root.zig` (complete exports)
- Modify: `build.zig` (final cleanup)

#### Step 1: Create feature branch

```bash
git checkout dev
git pull origin dev
git checkout -b feature/final-integration
```

#### Step 2: Complete root.zig

```zig
//! Kairoz - Natural language date parsing for Zig
//!
//! A zero-dependency library for parsing human-friendly date expressions
//! like "tomorrow", "next monday", "+3d", or "2024-06-15".
//!
//! ## Quick Start
//!
//! ```zig
//! const kairoz = @import("kairoz");
//!
//! const result = try kairoz.parse("tomorrow");
//! switch (result) {
//!     .date => |d| std.debug.print("{}-{}-{}\n", .{d.year, d.month, d.day}),
//!     .clear => std.debug.print("cleared\n", .{}),
//! }
//! ```

// Types
pub const Date = @import("Date.zig").Date;
pub const DateError = @import("Date.zig").DateError;
pub const ParsedDate = @import("parse.zig").ParsedDate;
pub const ParseError = @import("parse.zig").ParseError;

// Date construction
pub const today = @import("Date.zig").today;
pub const isLeapYear = @import("Date.zig").isLeapYear;
pub const daysInMonth = @import("Date.zig").daysInMonth;

// Parsing
pub const parse = @import("parse.zig").parse;
pub const parseWithReference = @import("parse.zig").parseWithReference;

// Arithmetic
pub const addDays = @import("arithmetic.zig").addDays;
pub const addMonths = @import("arithmetic.zig").addMonths;
pub const daysBetween = @import("arithmetic.zig").daysBetween;
pub const daysUntil = @import("arithmetic.zig").daysUntil;

// Formatting
pub const formatRelative = @import("format.zig").formatRelative;
pub const max_format_len = @import("format.zig").max_format_len;

// Re-run all module tests
test {
    _ = @import("Date.zig");
    _ = @import("arithmetic.zig");
    _ = @import("parse.zig");
    _ = @import("format.zig");
}
```

#### Step 3: Add integration tests

Add to bottom of `src/root.zig`:

```zig
test "integration: parse and format round trip" {
    const ref = Date.initUnchecked(2024, 1, 15);
    var buf: [max_format_len]u8 = undefined;

    // Parse "tomorrow", format should return "tomorrow"
    const tomorrow = try parseWithReference("tomorrow", ref);
    try std.testing.expectEqualStrings("tomorrow", formatRelative(tomorrow.date, ref, &buf));

    // Parse "+7d", format should return "in 7 days"
    const week = try parseWithReference("+7d", ref);
    try std.testing.expectEqualStrings("in 7 days", formatRelative(week.date, ref, &buf));
}

test "integration: arithmetic consistency" {
    const date = Date.initUnchecked(2024, 1, 15);

    // addDays and daysBetween are inverses
    const future = addDays(date, 30);
    try std.testing.expectEqual(@as(i32, 30), daysBetween(date, future));

    const past = addDays(date, -30);
    try std.testing.expectEqual(@as(i32, -30), daysBetween(date, past));
}
```

#### Step 4: Run all tests

```bash
zig build test
```

#### Step 5: Commit and PR

```bash
git add -A
git commit -m "feat: complete public API with integration tests

- Full re-exports in root.zig
- Module documentation
- Integration tests for round-trip behavior"

git push -u origin feature/final-integration
```

---

## Phase 4: Cleanup

### Task 9: Final Review + Merge to Main

**Branch:** dev → main

#### Step 1: Ensure dev is clean

```bash
git checkout dev
git pull origin dev
zig build test
```

#### Step 2: Code review checklist

- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Public API matches design document
- [ ] All modules have doc comments
- [ ] No dead code

#### Step 3: Merge to main

```bash
git checkout main
git merge dev
git tag v0.1.0
git push origin main --tags
```

---

## Parallel Execution Map

```
Time →

Agent 1: ████ Task 1 ████ Task 2 ████████████████ Task 7 ████
Agent 2:                  ████ Task 3 ████████████████████████
Agent 3:                  ████ Task 4 ████████████████████████
Agent 4:                  ████ Task 5 ████ Task 6 ████████████

                          ↑ Sync point: Task 1 complete
                                              ↑ Sync: Tasks 2-5 complete
                                                            ↑ Sync: Task 8
```

**Sync Points:**
1. After Task 1: All agents can start Phase 2
2. After Tasks 2-5: Task 6 and 7 can proceed
3. After Task 7: Task 8 can proceed
4. After Task 8: Final review
