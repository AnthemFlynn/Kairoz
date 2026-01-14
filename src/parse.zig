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

pub const Granularity = enum {
    day,
    week,
    month,
    year,
};

pub const Period = struct {
    start: Date,
    granularity: Granularity,

    /// Compute the last day of this period
    pub fn end(self: Period) Date {
        return switch (self.granularity) {
            .day => self.start,
            .week => addDaysInternal(self.start, 6),
            .month => Date.initUnchecked(
                self.start.year,
                self.start.month,
                DateMod.daysInMonth(self.start.year, self.start.month),
            ),
            .year => Date.initUnchecked(self.start.year, 12, 31),
        };
    }
};

pub const ParsedDate = union(enum) {
    date: Date,
    period: Period,
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

    // Boundary expressions (most specific multi-word)
    if (parseBoundaryExpression(lower, reference)) |date| {
        return .{ .date = date };
    }

    // Weekday with modifier: "next monday", "last friday"
    if (parseWeekdayModifier(lower, reference)) |date| {
        return .{ .date = date };
    }

    // Period references: "next week", "last month", "this year"
    if (parsePeriodReference(lower, reference)) |parsed| {
        return parsed;
    }

    // Natural offsets: "in 3 days", "2 weeks ago"
    if (parseNaturalOffset(lower, reference)) |parsed| {
        return parsed;
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

    // Month names as periods
    if (parseMonthName(lower, reference)) |parsed| {
        return parsed;
    }

    // Ordinal days: "1st", "23rd"
    if (try parseOrdinalDay(lower, reference)) |date| {
        return .{ .date = date };
    }

    // Forward offsets: +Nd, +Nw, +Nm
    if (parseOffset(lower)) |offset| {
        return .{ .date = try applyOffset(reference, offset) };
    } else |err| {
        // If it's InvalidOffset, return it (valid format but zero value)
        if (err == error.InvalidOffset) return err;
        // Otherwise (InvalidFormat), try other parsers
    }

    // Absolute dates: YYYY-MM-DD, MM-DD, DD, YYYY (use original trimmed, not lowercase)
    return parseAbsoluteDate(trimmed, reference);
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

/// Parse absolute date formats: YYYY-MM-DD, MM-DD, DD, YYYY
fn parseAbsoluteDate(str: []const u8, reference: Date) (ParseError || DateError)!ParsedDate {
    // Check for YYYY-MM-DD format (length 10, dashes at positions 4 and 7)
    if (str.len == 10 and str[4] == '-' and str[7] == '-') {
        const year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.InvalidFormat;
        return .{ .date = try Date.init(year, month, day) };
    }

    // Check for MM-DD format (length 5, dash at position 2)
    if (str.len == 5 and str[2] == '-') {
        const month = std.fmt.parseInt(u8, str[0..2], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, str[3..5], 10) catch return error.InvalidFormat;
        return .{ .date = try Date.init(reference.year, month, day) };
    }

    // Check for YYYY format (4 digits, all numeric) - returns period
    if (str.len == 4) {
        var all_digits = true;
        for (str) |c| {
            if (!std.ascii.isDigit(c)) {
                all_digits = false;
                break;
            }
        }
        if (all_digits) {
            const year = std.fmt.parseInt(u16, str, 10) catch return error.InvalidFormat;
            if (year == 0) return error.InvalidYear;
            return .{ .period = .{
                .start = Date.initUnchecked(year, 1, 1),
                .granularity = .year,
            } };
        }
    }

    // Check for DD format (length 1-2, all digits)
    if (str.len >= 1 and str.len <= 2) {
        // Verify all characters are digits
        for (str) |c| {
            if (!std.ascii.isDigit(c)) return error.InvalidFormat;
        }
        const day = std.fmt.parseInt(u8, str, 10) catch return error.InvalidFormat;
        return .{ .date = try Date.init(reference.year, reference.month, day) };
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

/// Find most recent past occurrence of target weekday (always in past, 1-7 days back).
fn lastWeekday(from: Date, target_dow: u8) Date {
    const current_dow = dayOfWeek(from);
    var days_back: i32 = @as(i32, current_dow) - @as(i32, target_dow);
    if (days_back <= 0) {
        days_back += 7;
    }
    return addDaysInternal(from, -days_back);
}

/// Parse "next <weekday>" or "last <weekday>"
fn parseWeekdayModifier(str: []const u8, reference: Date) ?Date {
    // Try "next <weekday>"
    if (std.mem.startsWith(u8, str, "next ")) {
        const weekday_str = str[5..];
        if (parseWeekday(weekday_str)) |target_dow| {
            // "next monday" means the Monday in "next week" (the week after this one)
            // If target is strictly ahead in current week, add 7 to skip to next week
            // If target is same day or behind, nextWeekday already returns next week
            const current_dow = dayOfWeek(reference);
            const next = nextWeekday(reference, target_dow);
            if (target_dow > current_dow) {
                // Target is ahead this week, so nextWeekday returns this week's occurrence
                // Add 7 to get next week's occurrence
                return addDaysInternal(next, 7);
            }
            return next;
        }
    }

    // Try "last <weekday>"
    if (std.mem.startsWith(u8, str, "last ")) {
        const weekday_str = str[5..];
        if (parseWeekday(weekday_str)) |target_dow| {
            return lastWeekday(reference, target_dow);
        }
    }

    return null;
}

/// Parse period references: "next week", "last month", "this year", etc.
fn parsePeriodReference(str: []const u8, reference: Date) ?ParsedDate {
    // Week references
    if (std.mem.eql(u8, str, "next week")) {
        const this_monday = arithmetic.startOfWeek(reference);
        const next_monday = addDaysInternal(this_monday, 7);
        return .{ .period = .{ .start = next_monday, .granularity = .week } };
    }
    if (std.mem.eql(u8, str, "last week")) {
        const this_monday = arithmetic.startOfWeek(reference);
        const last_monday = addDaysInternal(this_monday, -7);
        return .{ .period = .{ .start = last_monday, .granularity = .week } };
    }
    if (std.mem.eql(u8, str, "this week")) {
        const this_monday = arithmetic.startOfWeek(reference);
        return .{ .period = .{ .start = this_monday, .granularity = .week } };
    }

    // Month references
    if (std.mem.eql(u8, str, "next month")) {
        const next = arithmetic.addMonths(reference, 1) catch return null;
        return .{ .period = .{ .start = arithmetic.firstDayOfMonth(next), .granularity = .month } };
    }
    if (std.mem.eql(u8, str, "last month")) {
        const prev = arithmetic.addMonths(reference, -1) catch return null;
        return .{ .period = .{ .start = arithmetic.firstDayOfMonth(prev), .granularity = .month } };
    }
    if (std.mem.eql(u8, str, "this month")) {
        return .{ .period = .{ .start = arithmetic.firstDayOfMonth(reference), .granularity = .month } };
    }

    // Year references
    if (std.mem.eql(u8, str, "next year")) {
        const next = arithmetic.addYears(reference, 1) catch return null;
        return .{ .period = .{ .start = Date.initUnchecked(next.year, 1, 1), .granularity = .year } };
    }
    if (std.mem.eql(u8, str, "last year")) {
        const prev = arithmetic.addYears(reference, -1) catch return null;
        return .{ .period = .{ .start = Date.initUnchecked(prev.year, 1, 1), .granularity = .year } };
    }
    if (std.mem.eql(u8, str, "this year")) {
        return .{ .period = .{ .start = Date.initUnchecked(reference.year, 1, 1), .granularity = .year } };
    }

    return null;
}

/// Parse natural offset: "in 3 days", "2 weeks ago", etc.
fn parseNaturalOffset(str: []const u8, reference: Date) ?ParsedDate {
    // Try "in N <unit>" pattern
    if (std.mem.startsWith(u8, str, "in ")) {
        const rest = str[3..];
        if (parseNaturalOffsetValue(rest, 1, reference)) |date| {
            return .{ .date = date };
        }
    }

    // Try "N <unit> ago" pattern
    if (std.mem.endsWith(u8, str, " ago")) {
        const rest = str[0 .. str.len - 4];
        if (parseNaturalOffsetValue(rest, -1, reference)) |date| {
            return .{ .date = date };
        }
    }

    return null;
}

/// Parse "N <unit>" and apply with given sign multiplier
fn parseNaturalOffsetValue(str: []const u8, sign: i32, reference: Date) ?Date {
    // Find the space separating number and unit
    const space_idx = std.mem.indexOf(u8, str, " ") orelse return null;

    const num_str = str[0..space_idx];
    const unit_str = str[space_idx + 1 ..];

    const value = std.fmt.parseInt(u32, num_str, 10) catch return null;
    if (value == 0) return null;

    const signed_value: i32 = @as(i32, @intCast(value)) * sign;

    // Match unit (singular or plural)
    if (std.mem.eql(u8, unit_str, "day") or std.mem.eql(u8, unit_str, "days")) {
        return addDaysInternal(reference, signed_value);
    }
    if (std.mem.eql(u8, unit_str, "week") or std.mem.eql(u8, unit_str, "weeks")) {
        return addDaysInternal(reference, signed_value * 7);
    }
    if (std.mem.eql(u8, unit_str, "month") or std.mem.eql(u8, unit_str, "months")) {
        return arithmetic.addMonths(reference, signed_value) catch return null;
    }
    if (std.mem.eql(u8, unit_str, "year") or std.mem.eql(u8, unit_str, "years")) {
        return arithmetic.addYears(reference, signed_value) catch return null;
    }

    return null;
}

/// Parse boundary expressions: "end of month", "beginning of next week", etc.
fn parseBoundaryExpression(str: []const u8, reference: Date) ?Date {
    // Current period boundaries
    if (std.mem.eql(u8, str, "end of month")) {
        return arithmetic.lastDayOfMonth(reference);
    }
    if (std.mem.eql(u8, str, "beginning of month")) {
        return arithmetic.firstDayOfMonth(reference);
    }
    if (std.mem.eql(u8, str, "end of week")) {
        return arithmetic.endOfWeek(reference);
    }
    if (std.mem.eql(u8, str, "beginning of week")) {
        return arithmetic.startOfWeek(reference);
    }
    if (std.mem.eql(u8, str, "end of year")) {
        return Date.initUnchecked(reference.year, 12, 31);
    }
    if (std.mem.eql(u8, str, "beginning of year")) {
        return Date.initUnchecked(reference.year, 1, 1);
    }

    // Next period boundaries
    if (std.mem.eql(u8, str, "end of next month")) {
        const next = arithmetic.addMonths(reference, 1) catch return null;
        return arithmetic.lastDayOfMonth(next);
    }
    if (std.mem.eql(u8, str, "beginning of next month")) {
        const next = arithmetic.addMonths(reference, 1) catch return null;
        return arithmetic.firstDayOfMonth(next);
    }
    if (std.mem.eql(u8, str, "end of next week")) {
        const next_monday = addDaysInternal(arithmetic.startOfWeek(reference), 7);
        return arithmetic.endOfWeek(next_monday);
    }
    if (std.mem.eql(u8, str, "beginning of next week")) {
        return addDaysInternal(arithmetic.startOfWeek(reference), 7);
    }
    if (std.mem.eql(u8, str, "end of next year")) {
        const next = arithmetic.addYears(reference, 1) catch return null;
        return Date.initUnchecked(next.year, 12, 31);
    }
    if (std.mem.eql(u8, str, "beginning of next year")) {
        const next = arithmetic.addYears(reference, 1) catch return null;
        return Date.initUnchecked(next.year, 1, 1);
    }

    // Last period boundaries
    if (std.mem.eql(u8, str, "end of last month")) {
        const prev = arithmetic.addMonths(reference, -1) catch return null;
        return arithmetic.lastDayOfMonth(prev);
    }
    if (std.mem.eql(u8, str, "beginning of last month")) {
        const prev = arithmetic.addMonths(reference, -1) catch return null;
        return arithmetic.firstDayOfMonth(prev);
    }
    if (std.mem.eql(u8, str, "end of last week")) {
        const last_monday = addDaysInternal(arithmetic.startOfWeek(reference), -7);
        return arithmetic.endOfWeek(last_monday);
    }
    if (std.mem.eql(u8, str, "beginning of last week")) {
        return addDaysInternal(arithmetic.startOfWeek(reference), -7);
    }
    if (std.mem.eql(u8, str, "end of last year")) {
        const prev = arithmetic.addYears(reference, -1) catch return null;
        return Date.initUnchecked(prev.year, 12, 31);
    }
    if (std.mem.eql(u8, str, "beginning of last year")) {
        const prev = arithmetic.addYears(reference, -1) catch return null;
        return Date.initUnchecked(prev.year, 1, 1);
    }

    return null;
}

/// Parse month name and return as period.
fn parseMonthName(str: []const u8, reference: Date) ?ParsedDate {
    const months = [_]struct { full: []const u8, abbrev: []const u8, month: u8 }{
        .{ .full = "january", .abbrev = "jan", .month = 1 },
        .{ .full = "february", .abbrev = "feb", .month = 2 },
        .{ .full = "march", .abbrev = "mar", .month = 3 },
        .{ .full = "april", .abbrev = "apr", .month = 4 },
        .{ .full = "may", .abbrev = "may", .month = 5 },
        .{ .full = "june", .abbrev = "jun", .month = 6 },
        .{ .full = "july", .abbrev = "jul", .month = 7 },
        .{ .full = "august", .abbrev = "aug", .month = 8 },
        .{ .full = "september", .abbrev = "sep", .month = 9 },
        .{ .full = "october", .abbrev = "oct", .month = 10 },
        .{ .full = "november", .abbrev = "nov", .month = 11 },
        .{ .full = "december", .abbrev = "dec", .month = 12 },
    };

    for (months) |m| {
        if (std.mem.eql(u8, str, m.full) or std.mem.eql(u8, str, m.abbrev)) {
            // If target month is current or past, use next year
            const year: u16 = if (m.month <= reference.month) reference.year + 1 else reference.year;
            return .{ .period = .{
                .start = Date.initUnchecked(year, m.month, 1),
                .granularity = .month,
            } };
        }
    }

    return null;
}

/// Parse ordinal day: "1st", "2nd", "3rd", "4th", "23rd", etc.
fn parseOrdinalDay(str: []const u8, reference: Date) (ParseError || DateError)!?Date {
    // Must be at least 3 characters (e.g., "1st")
    if (str.len < 3) return null;

    const suffix = str[str.len - 2 ..];
    const valid_suffix = std.mem.eql(u8, suffix, "st") or
        std.mem.eql(u8, suffix, "nd") or
        std.mem.eql(u8, suffix, "rd") or
        std.mem.eql(u8, suffix, "th");
    if (!valid_suffix) return null;

    const num_str = str[0 .. str.len - 2];
    const day = std.fmt.parseInt(u8, num_str, 10) catch return null;

    // Validate day for current month
    return try Date.init(reference.year, reference.month, day);
}

const OffsetUnit = enum { day, week, month, year };
const Offset = struct { value: u32, unit: OffsetUnit, sign: i32 };

/// Parse offset format: +Nd, +Nw, +Nm, +Ny, -Nd, -Nw, -Nm, -Ny
fn parseOffset(str: []const u8) (ParseError)!Offset {
    if (str.len < 3) return error.InvalidFormat;

    // Must start with + or -
    const sign: i32 = switch (str[0]) {
        '+' => 1,
        '-' => -1,
        else => return error.InvalidFormat,
    };

    // Check for invalid characters after sign (like +-)
    if (str[1] == '-' or str[1] == '+') return error.InvalidFormat;

    // Extract unit from last character
    const unit_char = str[str.len - 1];
    const unit: OffsetUnit = switch (unit_char) {
        'd' => .day,
        'w' => .week,
        'm' => .month,
        'y' => .year,
        else => return error.InvalidFormat,
    };

    // Parse the number between sign and unit
    const num_str = str[1 .. str.len - 1];
    if (num_str.len == 0) return error.InvalidFormat;

    const value = std.fmt.parseInt(u32, num_str, 10) catch return error.InvalidFormat;

    // Zero offset is invalid
    if (value == 0) return error.InvalidOffset;

    return .{ .value = value, .unit = unit, .sign = sign };
}

/// Apply offset to date
fn applyOffset(date: Date, offset: Offset) ArithmeticError!Date {
    const signed_value: i32 = @as(i32, @intCast(offset.value)) * offset.sign;
    return switch (offset.unit) {
        .day => addDaysInternal(date, signed_value),
        .week => addDaysInternal(date, signed_value * 7),
        .month => arithmetic.addMonths(date, signed_value),
        .year => arithmetic.addYears(date, signed_value),
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

test "Period.end returns same day for day granularity" {
    const period = Period{
        .start = Date.initUnchecked(2024, 1, 15),
        .granularity = .day,
    };
    const end_date = period.end();
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), end_date);
}

test "Period.end returns Sunday for week granularity" {
    // Start on Monday Jan 15, 2024
    const period = Period{
        .start = Date.initUnchecked(2024, 1, 15),
        .granularity = .week,
    };
    const end_date = period.end();
    // End should be Sunday Jan 21, 2024 (+6 days)
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 21), end_date);
}

test "Period.end returns last day of month" {
    const period = Period{
        .start = Date.initUnchecked(2024, 2, 1),
        .granularity = .month,
    };
    const end_date = period.end();
    // Feb 2024 has 29 days (leap year)
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 29), end_date);
}

test "Period.end returns Dec 31 for year granularity" {
    const period = Period{
        .start = Date.initUnchecked(2024, 1, 1),
        .granularity = .year,
    };
    const end_date = period.end();
    try std.testing.expectEqual(Date.initUnchecked(2024, 12, 31), end_date);
}

test "parse '-3d' subtracts days" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("-3d", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 12), result.date);
}

test "parse '-2w' subtracts weeks" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("-2w", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.date);
}

test "parse '-1m' subtracts months" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("-1m", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), result.date);
}

test "parse '-1y' subtracts years" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("-1y", ref);
    try std.testing.expectEqual(Date.initUnchecked(2023, 6, 15), result.date);
}

test "parse '-0d' returns InvalidOffset" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidOffset, parseWithReference("-0d", ref));
}

test "parse '+1y' adds years" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("+1y", ref);
    try std.testing.expectEqual(Date.initUnchecked(2025, 6, 15), result.date);
}

test "parse '+2y' adds years" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("+2y", ref);
    try std.testing.expectEqual(Date.initUnchecked(2026, 6, 15), result.date);
}

test "parse 'next monday' skips to following week" {
    // Reference: Monday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("next monday", ref);
    // Should skip this week's Monday (today) and go to next Monday
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 22), result.date);
}

test "parse 'next friday' from Monday" {
    const ref = Date.initUnchecked(2024, 1, 15); // Monday
    const result = try parseWithReference("next friday", ref);
    // Next Friday after skipping this week = Jan 26
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 26), result.date);
}

test "parse 'last monday' returns previous Monday" {
    // Reference: Wednesday Jan 17, 2024
    const ref = Date.initUnchecked(2024, 1, 17);
    const result = try parseWithReference("last monday", ref);
    // Previous Monday is Jan 15
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), result.date);
}

test "parse 'last monday' on Monday returns week before" {
    // Reference: Monday Jan 15, 2024
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("last monday", ref);
    // Previous Monday is Jan 8
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 8), result.date);
}

test "parse 'last friday' from Monday" {
    const ref = Date.initUnchecked(2024, 1, 15); // Monday
    const result = try parseWithReference("last friday", ref);
    // Last Friday is Jan 12
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 12), result.date);
}

test "parse 'next week' returns period" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("next week", ref);
    // Should return Monday of next week
    try std.testing.expectEqual(Granularity.week, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 22), result.period.start);
}

test "parse 'last week' returns period" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("last week", ref);
    try std.testing.expectEqual(Granularity.week, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 8), result.period.start);
}

test "parse 'this week' returns period" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("this week", ref);
    try std.testing.expectEqual(Granularity.week, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), result.period.start);
}

test "parse 'next month' returns period" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("next month", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 1), result.period.start);
}

test "parse 'last month' returns period" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("last month", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.period.start);
}

test "parse 'this month' returns period" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("this month", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.period.start);
}

test "parse 'next year' returns period" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("next year", ref);
    try std.testing.expectEqual(Granularity.year, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2025, 1, 1), result.period.start);
}

test "parse 'last year' returns period" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("last year", ref);
    try std.testing.expectEqual(Granularity.year, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2023, 1, 1), result.period.start);
}

test "parse 'this year' returns period" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("this year", ref);
    try std.testing.expectEqual(Granularity.year, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.period.start);
}

test "parse 'in 3 days'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("in 3 days", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 18), result.date);
}

test "parse 'in 2 weeks'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("in 2 weeks", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 29), result.date);
}

test "parse 'in 1 month'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("in 1 month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 15), result.date);
}

test "parse 'in 1 year'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("in 1 year", ref);
    try std.testing.expectEqual(Date.initUnchecked(2025, 1, 15), result.date);
}

test "parse '3 days ago'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("3 days ago", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 12), result.date);
}

test "parse '2 weeks ago'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("2 weeks ago", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.date);
}

test "parse '1 month ago'" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("1 month ago", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), result.date);
}

test "parse '1 year ago'" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("1 year ago", ref);
    try std.testing.expectEqual(Date.initUnchecked(2023, 6, 15), result.date);
}

test "parse 'end of month'" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("end of month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 29), result.date);
}

test "parse 'beginning of month'" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("beginning of month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 1), result.date);
}

test "parse 'end of week'" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("end of week", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 21), result.date); // Sunday
}

test "parse 'beginning of week'" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("beginning of week", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 15), result.date); // Monday
}

test "parse 'end of year'" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("end of year", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 12, 31), result.date);
}

test "parse 'beginning of year'" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("beginning of year", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.date);
}

test "parse 'end of next month'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("end of next month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 29), result.date);
}

test "parse 'beginning of next month'" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("beginning of next month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 1), result.date);
}

test "parse 'end of last month'" {
    const ref = Date.initUnchecked(2024, 2, 15);
    const result = try parseWithReference("end of last month", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 31), result.date);
}

test "parse 'end of next week'" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("end of next week", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 28), result.date); // Sunday of next week
}

test "parse 'beginning of next week'" {
    const ref = Date.initUnchecked(2024, 1, 17); // Wednesday
    const result = try parseWithReference("beginning of next week", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 22), result.date); // Monday of next week
}

test "parse 'february' in January returns this year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("february", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 1), result.period.start);
}

test "parse 'february' in March returns next year" {
    const ref = Date.initUnchecked(2024, 3, 15);
    const result = try parseWithReference("february", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2025, 2, 1), result.period.start);
}

test "parse 'january' in January returns next year" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("january", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2025, 1, 1), result.period.start);
}

test "parse 'dec' abbreviation works" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("dec", ref);
    try std.testing.expectEqual(Granularity.month, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 12, 1), result.period.start);
}

test "parse '1st' returns 1st of current month" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("1st", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 1), result.date);
}

test "parse '23rd' returns 23rd of current month" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("23rd", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 23), result.date);
}

test "parse '2nd' returns 2nd of current month" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("2nd", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 2), result.date);
}

test "parse '31st' in short month returns error" {
    const ref = Date.initUnchecked(2024, 6, 15); // June has 30 days
    try std.testing.expectError(error.InvalidDay, parseWithReference("31st", ref));
}

test "parse '11th' works" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("11th", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 11), result.date);
}

test "parse '2024' as year period" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("2024", ref);
    try std.testing.expectEqual(Granularity.year, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 1), result.period.start);
}

test "parse '2025' as year period" {
    const ref = Date.initUnchecked(2024, 6, 15);
    const result = try parseWithReference("2025", ref);
    try std.testing.expectEqual(Granularity.year, result.period.granularity);
    try std.testing.expectEqual(Date.initUnchecked(2025, 1, 1), result.period.start);
}

test "parse '0000' as year returns InvalidYear" {
    const ref = Date.initUnchecked(2024, 6, 15);
    try std.testing.expectError(error.InvalidYear, parseWithReference("0000", ref));
}
