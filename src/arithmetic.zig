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

/// Add (or subtract) months from a date. Day is clamped if it exceeds target month.
pub fn addMonths(date: Date, months: i32) Date {
    const total_months: i32 = @as(i32, date.year) * 12 + @as(i32, date.month - 1) + months;

    const new_year: i32 = @divFloor(total_months, 12);
    const new_month: i32 = @mod(total_months, 12) + 1;

    const year: u16 = @intCast(new_year);
    const month: u8 = @intCast(new_month);
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
    const result = addMonths(date, 2);
    try std.testing.expectEqual(@as(u8, 5), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
}

test "addMonths crosses year boundary" {
    const date = Date.initUnchecked(2024, 11, 15);
    const result = addMonths(date, 3);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u16, 2025), result.year);
}

test "addMonths clamps day" {
    const date = Date.initUnchecked(2024, 1, 31);
    const result = addMonths(date, 1);
    try std.testing.expectEqual(@as(u8, 29), result.day);
    try std.testing.expectEqual(@as(u8, 2), result.month);
}

test "addMonths subtracts months" {
    const date = Date.initUnchecked(2024, 3, 15);
    const result = addMonths(date, -2);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
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
