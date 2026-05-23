//! Natural language date parsing.

const std = @import("std");
const Date = @import("Date.zig");
const Time = @import("Time.zig");
const DateTime = @import("DateTime.zig");
const Duration = @import("Duration.zig");
const Instant = @import("Instant.zig");
const TimeZone = @import("TimeZone.zig");
const ZonedDateTime = @import("ZonedDateTime.zig");
const DateRange = @import("DateRange.zig");
const DateError = Date.DateError;
const today_fn = Date.today;
const dateToEpochDays = Date.dateToEpochDays;
const epochDaysToDate = Date.epochDaysToDate;

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
                Date.daysInMonth(self.start.year, self.start.month),
            ),
            .year => Date.initUnchecked(self.start.year, 12, 31),
        };
    }
};

/// Result of parsing a natural-language temporal expression.
///
/// The variant returned reflects the richest type the input justified:
/// a bare weekday returns `.date`; `"next month"` returns `.period`;
/// `"tomorrow at 2pm"` returns `.datetime`; an offset-bearing ISO 8601
/// timestamp returns `.zoned`; `"in 5 min"` with no reference returns
/// `.duration`; `"jan 15 to feb 1"` returns `.range`.
///
/// Renamed from `ParsedTemporal` in v0.3.0 to reflect the broader scope.
pub const ParsedTemporal = union(enum) {
    date: Date,
    datetime: DateTime,
    zoned: ZonedDateTime,
    instant: Instant,
    period: Period,
    range: DateRange,
    duration: Duration,
    clear,
};

/// Union of every error a parse call can return.
/// Stable across reference types — extending the parser to handle new
/// inputs widens the variants the result `union` can hold, not the
/// errors the function can return.
pub const ParseFullError =
    ParseError ||
    DateError ||
    ArithmeticError ||
    Time.TimeError ||
    DateRange.DateRangeError ||
    TimeZone.TimeZoneError;

/// Parse a temporal expression with the system clock as reference.
/// Time-bearing inputs (e.g. `"9am"`, `"tomorrow at 2pm"`) error here
/// because no time-of-day reference is available; use
/// `parseWithReference(input, DateTime|ZonedDateTime)` for those.
pub fn parse(str: []const u8) ParseFullError!ParsedTemporal {
    return parseWithReference(str, today_fn());
}

/// Maximum length of an input expression accepted by the parser.
/// The longest natural-language keyword the parser currently recognises is
/// `"beginning of next month"` (23 chars); 64 bytes leaves generous headroom
/// for whitespace and ISO dates while keeping the on-stack lowercase buffer
/// small. Inputs longer than this are rejected as InvalidFormat rather than
/// silently truncated, which would risk a long input aliasing to a short
/// keyword prefix.
pub const max_input_len: usize = 64;

/// Parse a temporal expression with an explicit reference.
///
/// `reference` may be one of:
/// - `Date` — date-only inputs only; time-bearing inputs error.
/// - `DateTime` — date-only inputs return `.date`; time-bearing inputs
///   return `.datetime` (anchored to `reference.date` per the
///   today-if-future-else-tomorrow rule for bare times).
/// - `ZonedDateTime` — same as `DateTime` but time-bearing results
///   carry the reference's `TimeZone` as `.zoned`.
///
/// The return variant always reflects the richest type the input
/// justified, regardless of how rich the reference is.
pub fn parseWithReference(str: []const u8, reference: anytype) ParseFullError!ParsedTemporal {
    const T = @TypeOf(reference);
    return switch (T) {
        Date => parseWithDateRef(str, reference),
        DateTime => parseWithDateTimeRef(str, reference),
        ZonedDateTime => parseWithZonedRef(str, reference),
        else => @compileError(
            "parseWithReference: reference must be Date, DateTime, or ZonedDateTime; got " ++
                @typeName(T),
        ),
    };
}

fn parseWithDateRef(str: []const u8, reference: Date) ParseFullError!ParsedTemporal {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return error.InvalidFormat;
    if (trimmed.len > max_input_len) return error.InvalidFormat;

    var lower_buf: [max_input_len]u8 = undefined;
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

    // Relative keywords (with shorthands)
    if (std.mem.eql(u8, lower, "today") or std.mem.eql(u8, lower, "tdy")) {
        return .{ .date = reference };
    }
    if (std.mem.eql(u8, lower, "tomorrow") or std.mem.eql(u8, lower, "tom")) {
        return .{ .date = addDaysInternal(reference, 1) };
    }
    if (std.mem.eql(u8, lower, "yesterday") or std.mem.eql(u8, lower, "yest")) {
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

fn parseWithDateTimeRef(str: []const u8, reference: DateTime) ParseFullError!ParsedTemporal {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return error.InvalidFormat;
    if (trimmed.len > max_input_len) return error.InvalidFormat;

    var lower_buf: [max_input_len]u8 = undefined;
    const lower = toLower(trimmed, &lower_buf);

    // ISO 8601 datetime without offset, e.g. "2024-06-15T14:30:00".
    // Offset-bearing forms are handled in parseWithZonedRef.
    if (parseIsoDateTime(trimmed)) |dt| {
        return .{ .datetime = dt };
    } else |err| switch (err) {
        error.NotIsoDateTime => {},
        else => |e| return e,
    }

    // Compound: "<date> at <time>" or "<date> <time>".
    if (try parseDateTimeCompound(lower, reference.date)) |dt| {
        return .{ .datetime = dt };
    }

    // Bare time-of-day → anchor onto reference date with the
    // today-if-future-else-tomorrow rule.
    if (parseTime(lower)) |time| {
        return .{ .datetime = anchorTimeOnReference(time, reference) };
    }

    // Otherwise fall through to date-only parsing against reference.date.
    // Date-only inputs return their natural variant (`.date`, `.period`,
    // `.clear`); they are NOT silently lifted to `.datetime`.
    return parseWithDateRef(str, reference.date);
}

fn parseWithZonedRef(str: []const u8, reference: ZonedDateTime) ParseFullError!ParsedTemporal {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return error.InvalidFormat;
    if (trimmed.len > max_input_len) return error.InvalidFormat;

    var lower_buf: [max_input_len]u8 = undefined;
    const lower = toLower(trimmed, &lower_buf);

    // ISO 8601 datetime without offset → wear the reference's zone.
    if (parseIsoDateTime(trimmed)) |dt| {
        return .{ .zoned = ZonedDateTime.init(dt, reference.zone) };
    } else |err| switch (err) {
        error.NotIsoDateTime => {},
        else => |e| return e,
    }

    // Compound: "<date> at <time>" or "<date> <time>".
    if (try parseDateTimeCompound(lower, reference.datetime.date)) |dt| {
        return .{ .zoned = ZonedDateTime.init(dt, reference.zone) };
    }

    // Bare time-of-day → return a ZonedDateTime in the reference's zone.
    if (parseTime(lower)) |time| {
        const anchored = anchorTimeOnReference(time, reference.datetime);
        return .{ .zoned = ZonedDateTime.init(anchored, reference.zone) };
    }

    return parseWithDateRef(str, reference.datetime.date);
}

/// Attempt to parse `lower` as `<date-expression> at <time>` or
/// `<date-expression> <time>`. The date side reuses the existing
/// date-only parsers; the time side reuses `parseTime`.
fn parseDateTimeCompound(lower: []const u8, reference: Date) ParseFullError!?DateTime {
    // Explicit "at" separator first — unambiguous.
    if (std.mem.lastIndexOf(u8, lower, " at ")) |at_idx| {
        const date_part = lower[0..at_idx];
        const time_part = lower[at_idx + 4 ..];
        if (parseTime(time_part)) |time| {
            if (try parseDatePart(date_part, reference)) |date| {
                return DateTime.init(date, time);
            }
        }
    }

    // Implicit space separator: iterate space positions right-to-left.
    // The first split where the suffix parses as a time and the prefix
    // parses as a date wins. This handles inputs like "tomorrow 9 am"
    // where the trailing chunk ("am") isn't itself a valid time but
    // "9 am" is.
    var search_end: usize = lower.len;
    while (std.mem.lastIndexOfScalar(u8, lower[0..search_end], ' ')) |sp| {
        const time_part = lower[sp + 1 ..];
        if (parseTime(time_part)) |time| {
            const date_part = std.mem.trimEnd(u8, lower[0..sp], " ");
            if (try parseDatePart(date_part, reference)) |date| {
                return DateTime.init(date, time);
            }
        }
        search_end = sp;
    }

    return null;
}

/// Parse `str` as a date-only expression. Returns null if the input
/// parses to a non-date variant (period, range, etc.) — those can't
/// compose with a time-of-day suffix.
fn parseDatePart(str: []const u8, reference: Date) ParseFullError!?Date {
    if (str.len == 0) return null;
    const result = parseWithDateRef(str, reference) catch |err| switch (err) {
        error.InvalidFormat, error.InvalidOffset => return null,
        else => return err,
    };
    return switch (result) {
        .date => |d| d,
        else => null,
    };
}

const IsoDateTimeError = error{NotIsoDateTime} || DateError || Time.TimeError;

/// Parse ISO 8601 local datetime (no offset). Accepted shapes:
///   YYYY-MM-DDTHH:MM
///   YYYY-MM-DDTHH:MM:SS
///   YYYY-MM-DDTHH:MM:SS.<fractional seconds, 1..9 digits>
/// Also tolerates a space instead of `T` (RFC 3339 §5.6 NOTE).
fn parseIsoDateTime(str: []const u8) IsoDateTimeError!DateTime {
    if (str.len < 16) return error.NotIsoDateTime;
    if (str[4] != '-' or str[7] != '-') return error.NotIsoDateTime;
    if (str[10] != 'T' and str[10] != 't' and str[10] != ' ') return error.NotIsoDateTime;
    if (str[13] != ':') return error.NotIsoDateTime;

    // Date portion
    const year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.NotIsoDateTime;
    const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.NotIsoDateTime;
    const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.NotIsoDateTime;
    const date = try Date.init(year, month, day);

    // Time portion: parse hours and minutes (always present)
    const hour = std.fmt.parseInt(u8, str[11..13], 10) catch return error.NotIsoDateTime;
    const minute = std.fmt.parseInt(u8, str[14..16], 10) catch return error.NotIsoDateTime;

    var second: u8 = 0;
    var nanosecond: u32 = 0;
    var idx: usize = 16;

    if (idx < str.len and str[idx] == ':') {
        if (idx + 3 > str.len) return error.NotIsoDateTime;
        second = std.fmt.parseInt(u8, str[idx + 1 .. idx + 3], 10) catch return error.NotIsoDateTime;
        idx += 3;

        if (idx < str.len and str[idx] == '.') {
            idx += 1;
            const frac_start = idx;
            while (idx < str.len and std.ascii.isDigit(str[idx])) : (idx += 1) {}
            const frac_len = idx - frac_start;
            if (frac_len == 0 or frac_len > 9) return error.NotIsoDateTime;
            const frac_val = std.fmt.parseInt(u32, str[frac_start..idx], 10) catch
                return error.NotIsoDateTime;
            // Scale to nanoseconds. "5" → 5×10^8; "500" → 5×10^8; "500000000" → 5×10^8.
            var scaled: u64 = frac_val;
            const remaining: u32 = @intCast(9 - frac_len);
            var i: u32 = 0;
            while (i < remaining) : (i += 1) scaled *= 10;
            nanosecond = @intCast(scaled);
        }
    }

    // Anything left over means this isn't a bare ISO local datetime
    // (likely an offset that the Zoned parser handles).
    if (idx != str.len) return error.NotIsoDateTime;

    const time = try Time.initFull(hour, minute, second, nanosecond);
    return DateTime.init(date, time);
}

/// Anchor a bare time-of-day onto a DateTime reference.
/// If the parsed time is at or after the reference's wall-clock time,
/// it lands on the reference date; otherwise it lands on the next day.
fn anchorTimeOnReference(time: Time, reference: DateTime) DateTime {
    if (time.totalNanoseconds() >= reference.time.totalNanoseconds()) {
        return DateTime.init(reference.date, time);
    }
    return DateTime.init(addDaysInternal(reference.date, 1), time);
}

fn toLower(str: []const u8, buf: []u8) []const u8 {
    std.debug.assert(str.len <= buf.len);
    for (str, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..str.len];
}

fn addDaysInternal(date: Date, days: i32) Date {
    return epochDaysToDate(dateToEpochDays(date) + days);
}

/// Parse absolute date formats: YYYY-MM-DD, MM-DD, DD, YYYY
fn parseAbsoluteDate(str: []const u8, reference: Date) (ParseError || DateError)!ParsedTemporal {
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

/// Parse a bare time-of-day token. Returns null on no match (not an error;
/// callers fall back to other parsers).
///
/// Accepted forms (case folded by caller):
/// - Word forms: `noon` (12:00), `midnight` (00:00)
/// - 12-hour: `9am`, `9 am`, `9:30pm`, `9:30:45 am`
/// - 24-hour: `14:30`, `09:00`, `00:00`, `23:59:59`
///
/// 12-hour rules:
/// - `12am` → 00:00, `12pm` → 12:00 (standard English convention)
/// - Hours must be 1..12; minutes/seconds must be 0..59
fn parseTime(str: []const u8) ?Time {
    // Word forms
    if (std.mem.eql(u8, str, "noon")) return Time.noon;
    if (std.mem.eql(u8, str, "midnight")) return Time.midnight;

    // Detect am/pm suffix (case already lowered by caller)
    var s = str;
    var is_12h = false;
    var pm = false;
    if (std.mem.endsWith(u8, s, "am")) {
        is_12h = true;
        s = std.mem.trimEnd(u8, s[0 .. s.len - 2], " ");
    } else if (std.mem.endsWith(u8, s, "pm")) {
        is_12h = true;
        pm = true;
        s = std.mem.trimEnd(u8, s[0 .. s.len - 2], " ");
    }

    if (s.len == 0) return null;
    // A bare numeric `s` like "9" would otherwise parse as an hour with
    // no separator — that's already handled by parseAbsoluteDate as a
    // bare day-of-month. We only accept hour-only inputs when an am/pm
    // suffix was present.
    if (!is_12h and std.mem.indexOfScalar(u8, s, ':') == null) return null;

    var hour: u32 = 0;
    var minute: u32 = 0;
    var second: u32 = 0;

    var parts = std.mem.splitScalar(u8, s, ':');
    const h_str = parts.next() orelse return null;
    if (h_str.len == 0 or h_str.len > 2) return null;
    hour = std.fmt.parseInt(u32, h_str, 10) catch return null;

    if (parts.next()) |m_str| {
        if (m_str.len == 0 or m_str.len > 2) return null;
        minute = std.fmt.parseInt(u32, m_str, 10) catch return null;
    }
    if (parts.next()) |sec_str| {
        if (sec_str.len == 0 or sec_str.len > 2) return null;
        second = std.fmt.parseInt(u32, sec_str, 10) catch return null;
    }
    if (parts.next() != null) return null; // too many colons

    if (is_12h) {
        if (hour < 1 or hour > 12) return null;
        if (pm) {
            if (hour != 12) hour += 12;
        } else {
            if (hour == 12) hour = 0;
        }
    } else {
        if (hour > 23) return null;
    }
    if (minute > 59 or second > 59) return null;

    return Time.initUnchecked(
        @intCast(hour),
        @intCast(minute),
        @intCast(second),
        0,
    );
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
fn parsePeriodReference(str: []const u8, reference: Date) ?ParsedTemporal {
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
fn parseNaturalOffset(str: []const u8, reference: Date) ?ParsedTemporal {
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
fn parseMonthName(str: []const u8, reference: Date) ?ParsedTemporal {
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
/// Also supports unitless offsets: +N, -N (defaults to days)
fn parseOffset(str: []const u8) (ParseError)!Offset {
    if (str.len < 2) return error.InvalidFormat;

    // Must start with + or -
    const sign: i32 = switch (str[0]) {
        '+' => 1,
        '-' => -1,
        else => return error.InvalidFormat,
    };

    // Check for invalid characters after sign (like +-)
    if (str[1] == '-' or str[1] == '+') return error.InvalidFormat;

    // Check if last character is a unit or a digit (unitless)
    const unit_char = str[str.len - 1];
    const has_unit = switch (unit_char) {
        'd', 'w', 'm', 'y' => true,
        else => false,
    };

    const unit: OffsetUnit = if (has_unit) switch (unit_char) {
        'd' => .day,
        'w' => .week,
        'm' => .month,
        'y' => .year,
        else => unreachable,
    } else .day; // Default to days when no unit specified

    // Parse the number (either between sign and unit, or after sign)
    const num_str = if (has_unit) str[1 .. str.len - 1] else str[1..];
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
    try std.testing.expectEqual(ParsedTemporal.clear, result);
}

test "parse 'clear' returns clear" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("clear", ref);
    try std.testing.expectEqual(ParsedTemporal.clear, result);
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

test "parse 'tom' as shorthand for tomorrow" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("tom", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 16), result.date);
}

test "parse 'tdy' as shorthand for today" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("tdy", ref);
    try std.testing.expectEqual(ref, result.date);
}

test "parse 'yest' as shorthand for yesterday" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("yest", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 14), result.date);
}

test "parse '+3' defaults to days" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("+3", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 18), result.date);
}

test "parse '-5' defaults to days" {
    const ref = Date.initUnchecked(2024, 1, 15);
    const result = try parseWithReference("-5", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 10), result.date);
}

test "parse '+0' returns InvalidOffset" {
    const ref = Date.initUnchecked(2024, 1, 15);
    try std.testing.expectError(error.InvalidOffset, parseWithReference("+0", ref));
}

test "parse rejects overlong input instead of truncating" {
    // A naive lowercase-into-fixed-buffer would truncate this to "today" + padding
    // and accept it. The length guard must reject it as InvalidFormat instead.
    const ref = Date.initUnchecked(2024, 1, 15);
    var long: [max_input_len + 1]u8 = undefined;
    @memset(&long, 'x');
    @memcpy(long[0..5], "today");
    try std.testing.expectError(error.InvalidFormat, parseWithReference(&long, ref));
}

// ============ TIME-OF-DAY PARSING (Phase E) ============

fn timeRef(date: Date, h: u8, m: u8, s: u8) DateTime {
    return DateTime.init(date, Time.initUnchecked(h, m, s, 0));
}

test "parse '9am' with DateTime ref before 9am lands on same date" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 7, 0, 0);
    const result = try parseWithReference("9am", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 15), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 9), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 0), result.datetime.time.minute);
}

test "parse '9am' after 9am rolls to next day" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("9am", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 9), result.datetime.time.hour);
}

test "parse '9am' at exactly 9am stays on same date" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 9, 0, 0);
    const result = try parseWithReference("9am", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 15), result.datetime.date);
}

test "parse '2:30pm' with minutes" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("2:30pm", ref);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), result.datetime.time.minute);
}

test "parse '2:30 pm' with space before am/pm" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("2:30 pm", ref);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), result.datetime.time.minute);
}

test "parse '12am' is midnight" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 11, 0, 0);
    const result = try parseWithReference("12am", ref);
    // 11am > 0am, so rolls to next day
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 0), result.datetime.time.hour);
}

test "parse '12pm' is noon" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("12pm", ref);
    try std.testing.expectEqual(@as(u8, 12), result.datetime.time.hour);
}

test "parse '14:30' 24-hour" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("14:30", ref);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), result.datetime.time.minute);
}

test "parse '00:00' 24-hour midnight" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 12, 0, 0);
    const result = try parseWithReference("00:00", ref);
    // Past noon, rolls to next day's midnight
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 0), result.datetime.time.hour);
}

test "parse '23:59:59' 24-hour with seconds" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("23:59:59", ref);
    try std.testing.expectEqual(@as(u8, 23), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 59), result.datetime.time.minute);
    try std.testing.expectEqual(@as(u8, 59), result.datetime.time.second);
}

test "parse 'noon' word form" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("noon", ref);
    try std.testing.expectEqual(@as(u8, 12), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 0), result.datetime.time.minute);
}

test "parse 'midnight' word form" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 1, 0, 0);
    const result = try parseWithReference("midnight", ref);
    // Reference is 01:00, so 00:00 is past → next day
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
}

test "parse rejects '25:00' invalid 24-hour" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    // Invalid time falls through to date parsers which also reject → InvalidFormat
    try std.testing.expectError(error.InvalidFormat, parseWithReference("25:00", ref));
}

test "parse rejects '13pm' invalid 12-hour" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    try std.testing.expectError(error.InvalidFormat, parseWithReference("13pm", ref));
}

test "parse date-only input with DateTime ref returns .date not .datetime" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("tomorrow", ref);
    // Should be .date variant — date inputs are NOT lifted to .datetime
    try std.testing.expect(result == .date);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.date);
}

test "parse with ZonedDateTime ref returns .zoned for time input" {
    const tz = try TimeZone.fromHours(-5);
    const dt = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const ref = ZonedDateTime.init(dt, tz);
    const result = try parseWithReference("2:30pm", ref);
    try std.testing.expect(result == .zoned);
    try std.testing.expectEqual(@as(u8, 14), result.zoned.datetime.time.hour);
    try std.testing.expectEqual(@as(i32, -5 * 3600), result.zoned.zone.offset_seconds);
}

test "parse with Date ref rejects time-bearing input" {
    const ref = Date.initUnchecked(2024, 6, 15);
    try std.testing.expectError(error.InvalidFormat, parseWithReference("9am", ref));
}

// ============ DATE+TIME COMPOUNDS (Phase F) ============

test "parse 'tomorrow at 2pm'" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("tomorrow at 2pm", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
}

test "parse 'tomorrow 2pm' without 'at'" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("tomorrow 2pm", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
}

test "parse 'tomorrow 9 am' with internal space in time" {
    const ref = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const result = try parseWithReference("tomorrow 9 am", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 9), result.datetime.time.hour);
}

test "parse 'next friday 14:30'" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 15), 10, 0, 0); // Monday
    const result = try parseWithReference("next friday 14:30", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 26), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), result.datetime.time.minute);
}

test "parse 'next friday at 14:30'" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 15), 10, 0, 0);
    const result = try parseWithReference("next friday at 14:30", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 26), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
}

test "parse 'end of month at noon'" {
    const ref = timeRef(Date.initUnchecked(2024, 2, 15), 10, 0, 0);
    const result = try parseWithReference("end of month at noon", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 2, 29), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 12), result.datetime.time.hour);
}

test "parse 'monday at 9am'" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 15), 10, 0, 0); // Monday
    const result = try parseWithReference("monday at 9am", ref);
    // 'monday' on Monday returns next Monday
    try std.testing.expectEqual(Date.initUnchecked(2024, 1, 22), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 9), result.datetime.time.hour);
}

test "parse ISO 8601 datetime YYYY-MM-DDTHH:MM" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const result = try parseWithReference("2024-06-15T14:30", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 15), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), result.datetime.time.minute);
    try std.testing.expectEqual(@as(u8, 0), result.datetime.time.second);
}

test "parse ISO 8601 datetime YYYY-MM-DDTHH:MM:SS" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const result = try parseWithReference("2024-06-15T14:30:45", ref);
    try std.testing.expectEqual(@as(u8, 45), result.datetime.time.second);
}

test "parse ISO 8601 datetime with fractional seconds (ms)" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const result = try parseWithReference("2024-06-15T14:30:45.500", ref);
    try std.testing.expectEqual(@as(u32, 500_000_000), result.datetime.time.nanosecond);
}

test "parse ISO 8601 datetime with nanosecond fractional" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const result = try parseWithReference("2024-06-15T14:30:45.123456789", ref);
    try std.testing.expectEqual(@as(u32, 123_456_789), result.datetime.time.nanosecond);
}

test "parse ISO 8601 datetime with space separator" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const result = try parseWithReference("2024-06-15 14:30", ref);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 15), result.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.datetime.time.hour);
}

test "parse ISO 8601 datetime with ZonedDateTime ref returns .zoned" {
    const tz = try TimeZone.fromHours(-5);
    const dt = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    const ref = ZonedDateTime.init(dt, tz);
    const result = try parseWithReference("2024-06-15T14:30", ref);
    try std.testing.expect(result == .zoned);
    try std.testing.expectEqual(@as(i32, -5 * 3600), result.zoned.zone.offset_seconds);
    try std.testing.expectEqual(@as(u8, 14), result.zoned.datetime.time.hour);
}

test "parse compound with ZonedDateTime ref returns .zoned" {
    const tz = try TimeZone.fromHours(9);
    const dt = timeRef(Date.initUnchecked(2024, 6, 15), 10, 0, 0);
    const ref = ZonedDateTime.init(dt, tz);
    const result = try parseWithReference("tomorrow at 2pm", ref);
    try std.testing.expect(result == .zoned);
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.zoned.datetime.date);
    try std.testing.expectEqual(@as(u8, 14), result.zoned.datetime.time.hour);
    try std.testing.expectEqual(@as(i32, 9 * 3600), result.zoned.zone.offset_seconds);
}

test "parse ISO datetime rejects invalid date in shape" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    try std.testing.expectError(error.InvalidMonth, parseWithReference("2024-13-01T00:00", ref));
}

test "parse ISO datetime rejects malformed time" {
    const ref = timeRef(Date.initUnchecked(2024, 1, 1), 0, 0, 0);
    // Hour 25 invalid
    try std.testing.expectError(error.InvalidHour, parseWithReference("2024-06-15T25:00", ref));
}
