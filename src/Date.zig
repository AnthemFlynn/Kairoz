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
    return epochDaysToDate(@intCast(epoch_day));
}

/// Convert Date to epoch day (days since 1970-01-01).
pub fn dateToEpochDays(date: Date) i32 {
    // Algorithm from Howard Hinnant's date algorithms
    const y: i32 = @as(i32, date.year) - @as(i32, if (date.month <= 2) 1 else 0);
    const era: i32 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const m: u32 = date.month;
    const d: u32 = date.day;
    const doy: u32 = @divFloor(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + d - 1;
    const doe: u32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + @as(i32, @intCast(doe)) - 719468;
}

/// Convert epoch day (days since 1970-01-01) to Date.
pub fn epochDaysToDate(epoch_day: i32) Date {
    // Algorithm from Howard Hinnant's date algorithms
    const z = epoch_day + 719468;
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

// ============ TESTS ============

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

test "epochDaysToDate known dates" {
    // 1970-01-01 is epoch day 0
    const epoch = epochDaysToDate(0);
    try std.testing.expectEqual(@as(u16, 1970), epoch.year);
    try std.testing.expectEqual(@as(u8, 1), epoch.month);
    try std.testing.expectEqual(@as(u8, 1), epoch.day);

    // 2024-01-15 is epoch day 19737
    const jan15 = epochDaysToDate(19737);
    try std.testing.expectEqual(@as(u16, 2024), jan15.year);
    try std.testing.expectEqual(@as(u8, 1), jan15.month);
    try std.testing.expectEqual(@as(u8, 15), jan15.day);
}
