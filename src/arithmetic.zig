//! Date arithmetic operations.

const std = @import("std");
const DateMod = @import("Date.zig");
const Date = DateMod.Date;
const daysInMonth = DateMod.daysInMonth;
const today = DateMod.today;
const dateToEpochDays = DateMod.dateToEpochDays;
const epochDaysToDate = DateMod.epochDaysToDate;

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

/// Get day of week (0=Monday, 6=Sunday).
pub fn dayOfWeek(date: Date) u8 {
    return @intCast(@mod(dateToEpochDays(date) + 3, 7));
}

/// Get the Monday of the week containing this date.
pub fn startOfWeek(date: Date) Date {
    const dow = dayOfWeek(date);
    return addDays(date, -@as(i32, dow));
}

/// Get the Sunday of the week containing this date.
pub fn endOfWeek(date: Date) Date {
    const dow = dayOfWeek(date);
    return addDays(date, @as(i32, 6 - dow));
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

test "startOfWeek returns Monday" {
    // Wednesday Jan 17, 2024 -> Monday Jan 15, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 17)),
    );
    // Monday stays Monday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 15)),
    );
    // Sunday Jan 21 -> Monday Jan 15
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 15),
        startOfWeek(Date.initUnchecked(2024, 1, 21)),
    );
}

test "endOfWeek returns Sunday" {
    // Wednesday Jan 17, 2024 -> Sunday Jan 21, 2024
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 21),
        endOfWeek(Date.initUnchecked(2024, 1, 17)),
    );
    // Sunday stays Sunday
    try std.testing.expectEqual(
        Date.initUnchecked(2024, 1, 21),
        endOfWeek(Date.initUnchecked(2024, 1, 21)),
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
