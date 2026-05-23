//! Date arithmetic operations.

const std = @import("std");
const Date = @import("Date.zig");
const daysInMonth = Date.daysInMonth;
const today = Date.today;
const dateToEpochDays = Date.dateToEpochDays;
const epochDaysToDate = Date.epochDaysToDate;

/// Add (or subtract) days from a date.
pub fn addDays(date: Date, days: i32) Date {
    return epochDaysToDate(dateToEpochDays(date) + days);
}

pub const ArithmeticError = error{
    YearOutOfRange,
};

/// Add (or subtract) months from a date. Day is clamped if it exceeds target month.
/// Returns error if result year would be outside valid range (1-65535).
pub fn addMonths(date: Date, months: i32) ArithmeticError!Date {
    // Calculate total months, checking for overflow
    const year_months: i64 = @as(i64, date.year) * 12;
    const total_months: i64 = year_months + @as(i64, date.month - 1) + @as(i64, months);

    const new_year_i64: i64 = @divFloor(total_months, 12);
    const new_month_i64: i64 = @mod(total_months, 12) + 1;

    // Validate year is in valid range (1-65535)
    if (new_year_i64 < 1 or new_year_i64 > 65535) {
        return error.YearOutOfRange;
    }

    const year: u16 = @intCast(new_year_i64);
    const month: u8 = @intCast(new_month_i64);
    const max_day = daysInMonth(year, month);
    const day = @min(date.day, max_day);

    return Date.initUnchecked(year, month, day);
}

/// Calculate signed difference in days between two dates.
pub fn daysBetween(from: Date, to: Date) i32 {
    return dateToEpochDays(to) - dateToEpochDays(from);
}

/// Convenience: days from today until given date. Negative if date is in past.
pub fn daysUntil(date: Date) i32 {
    const now = today();
    return daysBetween(now, date);
}

/// Get the first day of the month containing this date.
pub fn firstDayOfMonth(date: Date) Date {
    return Date.initUnchecked(date.year, date.month, 1);
}

/// Get the last day of the month containing this date.
pub fn lastDayOfMonth(date: Date) Date {
    return Date.initUnchecked(date.year, date.month, daysInMonth(date.year, date.month));
}

/// Which day a week starts on for week-boundary calculations.
///
/// Locale matters: ISO 8601 and most of Europe/Asia treat Monday as the
/// first day; US/Canada/Japan calendars treat Sunday. Pass the choice
/// explicitly rather than baking a default into the library.
pub const WeekStart = enum { monday, sunday };

/// Get day of week (0=Monday, 6=Sunday).
pub fn dayOfWeek(date: Date) u8 {
    return @intCast(@mod(dateToEpochDays(date) + 3, 7));
}

/// Position of `date` within a week that begins on `week_start`.
/// Returns 0 for the first day of the week.
fn weekPosition(date: Date, week_start: WeekStart) u8 {
    const dow = dayOfWeek(date); // 0=Mon..6=Sun
    return switch (week_start) {
        .monday => dow,
        .sunday => (dow + 1) % 7,
    };
}

/// Get the first day of the week containing this date, given a `WeekStart`.
pub fn startOfWeek(date: Date, week_start: WeekStart) Date {
    const pos = weekPosition(date, week_start);
    return addDays(date, -@as(i32, pos));
}

/// Get the last day of the week containing this date, given a `WeekStart`.
pub fn endOfWeek(date: Date, week_start: WeekStart) Date {
    const pos = weekPosition(date, week_start);
    return addDays(date, @as(i32, 6 - pos));
}

/// Add (or subtract) years from a date. Day is clamped if Feb 29 in non-leap year.
/// Returns error if result year would be outside valid range (1-65535).
pub fn addYears(date: Date, years: i32) ArithmeticError!Date {
    const new_year_i64: i64 = @as(i64, date.year) + @as(i64, years);

    if (new_year_i64 < 1 or new_year_i64 > 65535) {
        return error.YearOutOfRange;
    }

    const year: u16 = @intCast(new_year_i64);
    const max_day = daysInMonth(year, date.month);
    const day = @min(date.day, max_day);

    return Date.initUnchecked(year, date.month, day);
}

// ============ TESTS ============

test "addDays adds days within same month" {
    const date = Date.initUnchecked(2024, 1, 15);
    const result = addDays(date, 5);
    try std.testing.expectEqual(@as(u8, 20), result.day);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}

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
    try std.testing.expectEqual(@as(u8, 29), result.day);
    try std.testing.expectEqual(@as(u8, 2), result.month);
}

test "addMonths adds months within same year" {
    const date = Date.initUnchecked(2024, 3, 15);
    const result = try addMonths(date, 2);
    try std.testing.expectEqual(@as(u8, 5), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}

test "addMonths crosses year boundary" {
    const date = Date.initUnchecked(2024, 11, 15);
    const result = try addMonths(date, 3);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u16, 2025), result.year);
}

test "addMonths clamps day" {
    const date = Date.initUnchecked(2024, 1, 31);
    const result = try addMonths(date, 1);
    try std.testing.expectEqual(@as(u8, 29), result.day);
    try std.testing.expectEqual(@as(u8, 2), result.month);
}

test "addMonths subtracts months" {
    const date = Date.initUnchecked(2024, 3, 15);
    const result = try addMonths(date, -2);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}

test "addMonths returns error for year 0" {
    const date = Date.initUnchecked(1, 1, 15);
    try std.testing.expectError(error.YearOutOfRange, addMonths(date, -12));
}

test "addMonths returns error for negative year" {
    const date = Date.initUnchecked(1, 1, 15);
    try std.testing.expectError(error.YearOutOfRange, addMonths(date, -13));
}

test "addMonths returns error for year overflow" {
    const date = Date.initUnchecked(65535, 1, 15);
    try std.testing.expectError(error.YearOutOfRange, addMonths(date, 12));
}

test "daysBetween same date" {
    const date = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectEqual(@as(i32, 0), daysBetween(date, date));
}

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

test "firstDayOfMonth returns 1st of month" {
    const date = Date.initUnchecked(2024, 6, 15);
    const first = firstDayOfMonth(date);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 1), first);
}

test "lastDayOfMonth returns last day" {
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 2, 29),
        lastDayOfMonth(Date.initUnchecked(2024, 2, 15)),
    );
    try std.testing.expectEqual(
        Date.initUnchecked(2023, 2, 28),
        lastDayOfMonth(Date.initUnchecked(2023, 2, 15)),
    );
}

test "dayOfWeek calculation" {
    // Jan 15, 2024 is Monday
    try std.testing.expectEqual(@as(u8, 0), dayOfWeek(Date.initUnchecked(2024, 1, 15)));
    // Jan 1, 1970 is Thursday
    try std.testing.expectEqual(@as(u8, 3), dayOfWeek(Date.initUnchecked(1970, 1, 1)));
    // Sunday
    try std.testing.expectEqual(@as(u8, 6), dayOfWeek(Date.initUnchecked(2024, 1, 21)));
}

test "startOfWeek monday-start returns Monday" {
    // Wednesday Jan 17, 2024 -> Monday Jan 15, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 17), .monday),
    );
    // Monday stays Monday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 15), .monday),
    );
    // Sunday Jan 21 -> Monday Jan 15
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 21), .monday),
    );
}

test "startOfWeek sunday-start returns Sunday" {
    // Wednesday Jan 17, 2024 -> Sunday Jan 14, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 14),
        startOfWeek(Date.initUnchecked(2024, 1, 17), .sunday),
    );
    // Sunday stays Sunday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 14),
        startOfWeek(Date.initUnchecked(2024, 1, 14), .sunday),
    );
    // Monday Jan 15 -> Sunday Jan 14
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 14),
        startOfWeek(Date.initUnchecked(2024, 1, 15), .sunday),
    );
    // Saturday Jan 20 -> Sunday Jan 14
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 14),
        startOfWeek(Date.initUnchecked(2024, 1, 20), .sunday),
    );
}

test "endOfWeek monday-start returns Sunday" {
    // Wednesday Jan 17, 2024 -> Sunday Jan 21, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 21),
        endOfWeek(Date.initUnchecked(2024, 1, 17), .monday),
    );
    // Sunday stays Sunday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 21),
        endOfWeek(Date.initUnchecked(2024, 1, 21), .monday),
    );
}

test "endOfWeek sunday-start returns Saturday" {
    // Wednesday Jan 17, 2024 -> Saturday Jan 20, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 20),
        endOfWeek(Date.initUnchecked(2024, 1, 17), .sunday),
    );
    // Saturday stays Saturday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 20),
        endOfWeek(Date.initUnchecked(2024, 1, 20), .sunday),
    );
    // Sunday Jan 14 -> Saturday Jan 20
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 20),
        endOfWeek(Date.initUnchecked(2024, 1, 14), .sunday),
    );
}

test "addYears adds years" {
    const date = Date.initUnchecked(2024, 6, 15);
    const result = try addYears(date, 2);
    try std.testing.expectEqual(Date.initUnchecked(2026, 6, 15), result);
}

test "addYears handles leap year edge case" {
    // Feb 29, 2024 + 1 year -> Feb 28, 2025 (clamp)
    const date = Date.initUnchecked(2024, 2, 29);
    const result = try addYears(date, 1);
    try std.testing.expectEqual(Date.initUnchecked(2025, 2, 28), result);
}

test "addYears returns error for year overflow" {
    const date = Date.initUnchecked(65535, 1, 1);
    try std.testing.expectError(error.YearOutOfRange, addYears(date, 1));
}

test "addYears returns error for year underflow" {
    const date = Date.initUnchecked(1, 1, 1);
    try std.testing.expectError(error.YearOutOfRange, addYears(date, -1));
}
