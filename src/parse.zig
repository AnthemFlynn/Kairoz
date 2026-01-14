//! Natural language date parsing.

const std = @import("std");
const DateMod = @import("Date.zig");
const Date = DateMod.Date;
const DateError = DateMod.DateError;
const today_fn = DateMod.today;
const dateToEpochDays = DateMod.dateToEpochDays;
const epochDaysToDate = DateMod.epochDaysToDate;

const arithmetic = @import("arithmetic.zig");
const ArithmeticError = arithmetic.ArithmeticError;

pub const ParseError = error{
    InvalidFormat,
    InvalidOffset,
};

pub const ParsedDate = union(enum) {
    date: Date,
    clear,
};

/// Parse date string using current system date as reference.
pub fn parse(str: []const u8) (ParseError || DateError || ArithmeticError)!ParsedDate {
    return parseWithReference(str, today_fn());
}

/// Parse date string with explicit reference date (for testing).
pub fn parseWithReference(str: []const u8, reference: Date) (ParseError || DateError || ArithmeticError)!ParsedDate {
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

    // Weekday names
    if (parseWeekday(lower)) |target_dow| {
        return .{ .date = nextWeekday(reference, target_dow) };
    }

    // Forward offsets: +Nd, +Nw, +Nm
    if (parseOffset(lower)) |offset| {
        return .{ .date = try applyOffset(reference, offset) };
    } else |err| {
        // If it's InvalidOffset, return it (valid format but zero value)
        if (err == error.InvalidOffset) return err;
        // Otherwise (InvalidFormat), try other parsers
    }

    // Absolute dates: YYYY-MM-DD, MM-DD, DD (use original trimmed, not lowercase)
    if (parseAbsoluteDate(trimmed, reference)) |date| {
        return .{ .date = date };
    } else |err| {
        return err;
    }
}

fn toLower(str: []const u8, buf: []u8) []const u8 {
    const len = @min(str.len, buf.len);
    for (str[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..len];
}

fn addDaysInternal(date: Date, days: i32) Date {
    return epochDaysToDate(dateToEpochDays(date) + days);
}

/// Parse absolute date formats: YYYY-MM-DD, MM-DD, DD
fn parseAbsoluteDate(str: []const u8, reference: Date) (ParseError || DateError)!Date {
    // Check for YYYY-MM-DD format (length 10, dashes at positions 4 and 7)
    if (str.len == 10 and str[4] == '-' and str[7] == '-') {
        const year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.InvalidFormat;
        return Date.init(year, month, day);
    }

    // Check for MM-DD format (length 5, dash at position 2)
    if (str.len == 5 and str[2] == '-') {
        const month = std.fmt.parseInt(u8, str[0..2], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[3..5], 10) catch return error.InvalidFormat;
        return Date.init(reference.year, month, day);
    }

    // Check for DD format (length 1-2, all digits)
    if (str.len >= 1 and str.len <= 2) {
        // Verify all characters are digits
        for (str) |c| {
            if (!std.ascii.isDigit(c)) return error.InvalidFormat;
        }
        const day = std.fmt.parseInt(u8, str, 10) catch return error.InvalidFormat;
        return Date.init(reference.year, reference.month, day);
    }

    return error.InvalidFormat;
}

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
    // Jan 1, 1970 was Thursday (3). @mod always returns non-negative.
    return @intCast(@mod(dateToEpochDays(date) + 3, 7));
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

const OffsetUnit = enum { day, week, month };
const Offset = struct { value: u32, unit: OffsetUnit };

/// Parse forward offset format: +Nd, +Nw, +Nm
fn parseOffset(str: []const u8) (ParseError)!Offset {
    // Must start with +
    if (str.len < 3 or str[0] != '+') return error.InvalidFormat;

    // Check for invalid characters after + (like +-)
    if (str[1] == '-' or str[1] == '+') return error.InvalidFormat;

    // Extract unit from last character
    const unit_char = str[str.len - 1];
    const unit: OffsetUnit = switch (unit_char) {
        'd' => .day,
        'w' => .week,
        'm' => .month,
        else => return error.InvalidFormat,
    };

    // Parse the number between + and unit
    const num_str = str[1 .. str.len - 1];
    if (num_str.len == 0) return error.InvalidFormat;

    const value = std.fmt.parseInt(u32, num_str, 10) catch return error.InvalidFormat;

    // Zero offset is invalid
    if (value == 0) return error.InvalidOffset;

    return .{ .value = value, .unit = unit };
}

/// Apply offset to date
fn applyOffset(date: Date, offset: Offset) ArithmeticError!Date {
    return switch (offset.unit) {
        .day => addDaysInternal(date, @intCast(offset.value)),
        .week => addDaysInternal(date, @intCast(offset.value * 7)),
        .month => arithmetic.addMonths(date, @intCast(offset.value)),
    };
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

test "parse 'monday' returns next monday" {
    // Reference: Monday Jan 15, 2024 - same weekday returns next week
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("monday", ref);
    // Next Monday is Jan 22, 2024 (7 days ahead)
    try std.testing.expectEqual(@as(u8, 22), result.date.day);
    try std.testing.expectEqual(@as(u8, 1), result.date.month);
}

test "parse 'friday' returns next friday" {
    // Reference: Monday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("friday", ref);
    // Next Friday is Jan 19, 2024 (4 days ahead)
    try std.testing.expectEqual(@as(u8, 19), result.date.day);
}

test "parse weekday abbreviations" {
    const ref = Date.initUnchecked(2024, 1, 15); // Monday
    _ = try parseWithReference("mon", ref);
    _ = try parseWithReference("tue", ref);
    _ = try parseWithReference("wed", ref);
    _ = try parseWithReference("thu", ref);
    _ = try parseWithReference("fri", ref);
    _ = try parseWithReference("sat", ref);
    _ = try parseWithReference("sun", ref);
}

test "parse same weekday returns next week" {
    // Reference: Monday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("monday", ref);
    // Same day should return next week (7 days)
    try std.testing.expectEqual(@as(u8, 22), result.date.day);
}

test "dayOfWeek calculation" {
    // Jan 15, 2024 is Monday
    try std.testing.expectEqual(@as(u8, 0), dayOfWeek(Date.initUnchecked(2024, 1, 15)));
    // Jan 1, 1970 is Thursday
    try std.testing.expectEqual(@as(u8, 3), dayOfWeek(Date.initUnchecked(1970, 1, 1)));
}

test "parse '+3d' adds days" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+3d", ref);
    try std.testing.expectEqual(@as(u8, 18), result.date.day);
}

test "parse '+2w' adds weeks" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+2w", ref);
    try std.testing.expectEqual(@as(u8, 29), result.date.day);
}

test "parse '+1m' adds months" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+1m", ref);
    try std.testing.expectEqual(@as(u8, 2), result.date.month);
    try std.testing.expectEqual(@as(u8, 15), result.date.day);
}

test "parse '+1m' clamps day" {
    const ref = Date.initUnchecked(2024, 1, 31);
    const result = try parseWithReference("+1m", ref);
    try std.testing.expectEqual(@as(u8, 29), result.date.day); // Feb 29, 2024 (leap year)
}

test "parse invalid offsets" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+0d", ref));
    try std.testing.expectError(error.InvalidFormat, parseWithReference("+d", ref));
    try std.testing.expectError(error.InvalidFormat, parseWithReference("+-3d", ref));
}

test "parse 'YYYY-MM-DD' full date" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("2025-06-20", ref);
    try std.testing.expectEqual(@as(u16, 2025), result.date.year);
    try std.testing.expectEqual(@as(u8, 6), result.date.month);
    try std.testing.expectEqual(@as(u8, 20), result.date.day);
}

test "parse 'MM-DD' uses reference year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("06-20", ref);
    try std.testing.expectEqual(@as(u16, 2024), result.date.year);
    try std.testing.expectEqual(@as(u8, 6), result.date.month);
    try std.testing.expectEqual(@as(u8, 20), result.date.day);
}

test "parse 'DD' uses reference year and month" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("20", ref);
    try std.testing.expectEqual(@as(u16, 2024), result.date.year);
    try std.testing.expectEqual(@as(u8, 6), result.date.month);
    try std.testing.expectEqual(@as(u8, 20), result.date.day);
}

test "parse invalid absolute dates" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidMonth, parseWithReference("2024-13-01", ref));
    try std.testing.expectError(error.InvalidDay, parseWithReference("2024-01-32", ref));
    try std.testing.expectError(error.InvalidFormat, parseWithReference("2024-1-15", ref)); // not zero-padded
}
