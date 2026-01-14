//! Natural language date parsing.

const std = @import("std");
const Date = @import("Date.zig").Date;
const DateError = @import("Date.zig").DateError;
const today_fn = @import("Date.zig").today;

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
    return parseWithReference(str, today_fn());
}

/// Parse date string with explicit reference date (for testing).
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

test "parse 'today' returns reference date" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("today", ref);
    try std.testing.expectEqual(ref, result.date);
}

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
