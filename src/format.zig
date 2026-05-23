//! Formatting helpers: relative-language output, Moment-style custom
//! token patterns, and ISO 8601 convenience formatters.

const std = @import("std");
const Date = @import("Date.zig");
const Time = @import("Time.zig");
const DateTime = @import("DateTime.zig");
const TimeZone = @import("TimeZone.zig");
const ZonedDateTime = @import("ZonedDateTime.zig");
const Instant = @import("Instant.zig");
const arithmetic = @import("arithmetic.zig");
const daysBetween = arithmetic.daysBetween;

/// Maximum buffer size needed for `formatRelative` output. Custom
/// formatters take caller-provided buffers and report `BufferTooSmall`.
pub const max_format_len: usize = 32;

pub const FormatError = error{BufferTooSmall};

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

// ============ CUSTOM FORMAT STRINGS ============

/// Format a `Date` using a Moment.js-style pattern. See module docs
/// for the supported tokens (`YYYY`, `MM`, `Do`, `dddd`, ...).
pub fn formatDate(date: Date, pattern: []const u8, buf: []u8) FormatError![]const u8 {
    var w = Writer.init(buf);
    try formatInto(&w, pattern, .{ .date = date, .time = null, .zone = null });
    return w.finish();
}

/// Format a `Time` using a Moment.js-style pattern.
pub fn formatTime(time: Time, pattern: []const u8, buf: []u8) FormatError![]const u8 {
    var w = Writer.init(buf);
    try formatInto(&w, pattern, .{ .date = null, .time = time, .zone = null });
    return w.finish();
}

/// Format a `DateTime` using a Moment.js-style pattern.
pub fn formatDateTime(dt: DateTime, pattern: []const u8, buf: []u8) FormatError![]const u8 {
    var w = Writer.init(buf);
    try formatInto(&w, pattern, .{ .date = dt.date, .time = dt.time, .zone = null });
    return w.finish();
}

/// Format a `ZonedDateTime` using a Moment.js-style pattern.
pub fn formatZoned(zdt: ZonedDateTime, pattern: []const u8, buf: []u8) FormatError![]const u8 {
    var w = Writer.init(buf);
    try formatInto(&w, pattern, .{ .date = zdt.datetime.date, .time = zdt.datetime.time, .zone = zdt.zone });
    return w.finish();
}

/// Format any temporal type as ISO 8601. The output shape depends on
/// the input type:
/// - `Date`           → `YYYY-MM-DD`
/// - `Time`           → `HH:mm:ss`
/// - `DateTime`       → `YYYY-MM-DDTHH:mm:ss`
/// - `ZonedDateTime`  → `YYYY-MM-DDTHH:mm:ssZ` (UTC) / `…+HH:MM`
/// - `Instant`        → `YYYY-MM-DDTHH:mm:ssZ` (UTC projection)
pub fn formatIso(value: anytype, buf: []u8) FormatError![]const u8 {
    const T = @TypeOf(value);
    return switch (T) {
        Date => formatDate(value, "YYYY-MM-DD", buf),
        Time => formatTime(value, "HH:mm:ss", buf),
        DateTime => formatDateTime(value, "YYYY-MM-DDTHH:mm:ss", buf),
        ZonedDateTime => formatZoned(value, "YYYY-MM-DDTHH:mm:ssZ", buf),
        Instant => formatZoned(ZonedDateTime.fromInstant(value, TimeZone.utc), "YYYY-MM-DDTHH:mm:ssZ", buf),
        else => @compileError("formatIso: unsupported type " ++ @typeName(T)),
    };
}

const Writer = struct {
    buf: []u8,
    pos: usize,

    fn init(buf: []u8) Writer {
        return .{ .buf = buf, .pos = 0 };
    }

    fn writeChar(self: *Writer, c: u8) FormatError!void {
        if (self.pos >= self.buf.len) return error.BufferTooSmall;
        self.buf[self.pos] = c;
        self.pos += 1;
    }

    fn writeAll(self: *Writer, s: []const u8) FormatError!void {
        if (self.pos + s.len > self.buf.len) return error.BufferTooSmall;
        @memcpy(self.buf[self.pos .. self.pos + s.len], s);
        self.pos += s.len;
    }

    /// Write `value` as decimal. If `min_width > 0`, left-pads with zeros.
    fn writeInt(self: *Writer, value: anytype, min_width: usize) FormatError!void {
        var tmp: [20]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch unreachable;
        if (s.len < min_width) {
            const padding = min_width - s.len;
            var i: usize = 0;
            while (i < padding) : (i += 1) try self.writeChar('0');
        }
        try self.writeAll(s);
    }

    fn finish(self: *Writer) []const u8 {
        return self.buf[0..self.pos];
    }
};

const FormatContext = struct {
    date: ?Date,
    time: ?Time,
    zone: ?TimeZone,
};

fn formatInto(w: *Writer, pattern: []const u8, ctx: FormatContext) FormatError!void {
    var i: usize = 0;
    while (i < pattern.len) {
        const c = pattern[i];

        // Bracket escape for literal text: `[T]` emits `T` regardless of
        // whether `T` would otherwise be a token.
        if (c == '[') {
            if (std.mem.indexOfScalarPos(u8, pattern, i + 1, ']')) |close| {
                try w.writeAll(pattern[i + 1 .. close]);
                i = close + 1;
                continue;
            }
            // No closing bracket — fall through and emit as literal.
        }

        if (try emitToken(w, pattern[i..], ctx)) |consumed| {
            i += consumed;
            continue;
        }

        // Pass-through literal.
        try w.writeChar(c);
        i += 1;
    }
}

/// Try to match the longest known token at the start of `slice` and
/// emit its formatted value. Returns the number of bytes consumed,
/// or null if no token matched (or the required context is missing).
fn emitToken(w: *Writer, slice: []const u8, ctx: FormatContext) FormatError!?usize {
    // Sub-second tokens first — they're the longest.
    if (std.mem.startsWith(u8, slice, "SSSSSSSSS")) {
        if (ctx.time) |t| {
            try w.writeInt(t.nanosecond, 9);
            return 9;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "SSSSSS")) {
        if (ctx.time) |t| {
            try w.writeInt(t.nanosecond / 1_000, 6);
            return 6;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "SSS")) {
        if (ctx.time) |t| {
            try w.writeInt(t.nanosecond / 1_000_000, 3);
            return 3;
        }
        return null;
    }

    // Year
    if (std.mem.startsWith(u8, slice, "YYYY")) {
        if (ctx.date) |d| {
            try w.writeInt(d.year, 4);
            return 4;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "YY")) {
        if (ctx.date) |d| {
            try w.writeInt(d.year % 100, 2);
            return 2;
        }
        return null;
    }

    // Month
    if (std.mem.startsWith(u8, slice, "MMMM")) {
        if (ctx.date) |d| {
            try w.writeAll(monthFullName(d.month));
            return 4;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "MMM")) {
        if (ctx.date) |d| {
            try w.writeAll(monthAbbrev(d.month));
            return 3;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "MM")) {
        if (ctx.date) |d| {
            try w.writeInt(d.month, 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "M")) {
        if (ctx.date) |d| {
            try w.writeInt(d.month, 0);
            return 1;
        }
        return null;
    }

    // Day of month
    if (std.mem.startsWith(u8, slice, "Do")) {
        if (ctx.date) |d| {
            try w.writeInt(d.day, 0);
            try w.writeAll(ordinalSuffix(d.day));
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "DD")) {
        if (ctx.date) |d| {
            try w.writeInt(d.day, 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "D")) {
        if (ctx.date) |d| {
            try w.writeInt(d.day, 0);
            return 1;
        }
        return null;
    }

    // Weekday name
    if (std.mem.startsWith(u8, slice, "dddd")) {
        if (ctx.date) |d| {
            try w.writeAll(weekdayFullName(arithmetic.dayOfWeek(d)));
            return 4;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "ddd")) {
        if (ctx.date) |d| {
            try w.writeAll(weekdayAbbrev(arithmetic.dayOfWeek(d)));
            return 3;
        }
        return null;
    }

    // Hour 24-hour
    if (std.mem.startsWith(u8, slice, "HH")) {
        if (ctx.time) |t| {
            try w.writeInt(t.hour, 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "H")) {
        if (ctx.time) |t| {
            try w.writeInt(t.hour, 0);
            return 1;
        }
        return null;
    }
    // Hour 12-hour
    if (std.mem.startsWith(u8, slice, "hh")) {
        if (ctx.time) |t| {
            try w.writeInt(hour12(t.hour), 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "h")) {
        if (ctx.time) |t| {
            try w.writeInt(hour12(t.hour), 0);
            return 1;
        }
        return null;
    }

    // Minute
    if (std.mem.startsWith(u8, slice, "mm")) {
        if (ctx.time) |t| {
            try w.writeInt(t.minute, 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "m")) {
        if (ctx.time) |t| {
            try w.writeInt(t.minute, 0);
            return 1;
        }
        return null;
    }

    // Second
    if (std.mem.startsWith(u8, slice, "ss")) {
        if (ctx.time) |t| {
            try w.writeInt(t.second, 2);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "s")) {
        if (ctx.time) |t| {
            try w.writeInt(t.second, 0);
            return 1;
        }
        return null;
    }

    // am/pm
    if (std.mem.startsWith(u8, slice, "a")) {
        if (ctx.time) |t| {
            try w.writeAll(if (t.hour < 12) "am" else "pm");
            return 1;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "A")) {
        if (ctx.time) |t| {
            try w.writeAll(if (t.hour < 12) "AM" else "PM");
            return 1;
        }
        return null;
    }

    // Offset
    if (std.mem.startsWith(u8, slice, "ZZ")) {
        if (ctx.zone) |z| {
            try writeOffset(w, z, .compact);
            return 2;
        }
        return null;
    }
    if (std.mem.startsWith(u8, slice, "Z")) {
        if (ctx.zone) |z| {
            try writeOffset(w, z, .colon);
            return 1;
        }
        return null;
    }

    return null;
}

const OffsetStyle = enum { colon, compact };

fn writeOffset(w: *Writer, zone: TimeZone, style: OffsetStyle) FormatError!void {
    // Canonical ISO 8601: UTC offset 0 renders as "Z".
    if (zone.offset_seconds == 0) {
        try w.writeChar('Z');
        return;
    }
    const abs: i32 = if (zone.offset_seconds < 0) -zone.offset_seconds else zone.offset_seconds;
    const hh: u32 = @intCast(@divTrunc(abs, 3_600));
    const mm: u32 = @intCast(@divTrunc(@mod(abs, 3_600), 60));
    try w.writeChar(if (zone.offset_seconds < 0) '-' else '+');
    try w.writeInt(hh, 2);
    if (style == .colon) try w.writeChar(':');
    try w.writeInt(mm, 2);
}

fn monthFullName(month: u8) []const u8 {
    const names = [_][]const u8{
        "January", "February", "March",     "April",   "May",      "June",
        "July",    "August",   "September", "October", "November", "December",
    };
    if (month < 1 or month > 12) return "???";
    return names[month - 1];
}

fn weekdayFullName(dow: u8) []const u8 {
    // dayOfWeek returns 0=Mon..6=Sun.
    const names = [_][]const u8{
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    };
    if (dow > 6) return "???";
    return names[dow];
}

fn weekdayAbbrev(dow: u8) []const u8 {
    const names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    if (dow > 6) return "???";
    return names[dow];
}

fn ordinalSuffix(day: u8) []const u8 {
    // 11, 12, 13 always use "th".
    const last_two = day % 100;
    if (last_two >= 11 and last_two <= 13) return "th";
    return switch (day % 10) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    };
}

fn hour12(hour24: u8) u8 {
    if (hour24 == 0) return 12;
    if (hour24 > 12) return hour24 - 12;
    return hour24;
}

// ============ TESTS ============

test "formatRelative returns 'today' for same date" {
    const date = Date.initUnchecked(2024, 1, 15);
    var buf: [max_format_len]u8 = undefined;
    const result = formatRelative(date, date, &buf);
    try std.testing.expectEqualStrings("today", result);
}

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

test "formatRelative handles period start" {
    // Verifies formatting works correctly with dates that come from Period.start.
    // When a Period represents "next month" from Jan 15, its start is Feb 1.
    // Feb 1 is 17 days away (outside the 14-day window), so it shows "Feb 1".
    const ref = Date.initUnchecked(2024, 1, 15);
    const period_start = Date.initUnchecked(2024, 2, 1);
    var buf: [max_format_len]u8 = undefined;
    const result = formatRelative(period_start, ref, &buf);
    try std.testing.expectEqualStrings("Feb 1", result);
}

// ============ CUSTOM FORMAT TESTS ============

test "formatDate YYYY-MM-DD" {
    var buf: [32]u8 = undefined;
    const out = try formatDate(Date.initUnchecked(2024, 6, 15), "YYYY-MM-DD", &buf);
    try std.testing.expectEqualStrings("2024-06-15", out);
}

test "formatDate YY-M-D unpadded" {
    var buf: [32]u8 = undefined;
    const out = try formatDate(Date.initUnchecked(2024, 6, 5), "YY-M-D", &buf);
    try std.testing.expectEqualStrings("24-6-5", out);
}

test "formatDate MMM and MMMM month names" {
    var buf: [32]u8 = undefined;
    const out1 = try formatDate(Date.initUnchecked(2024, 6, 15), "MMM D", &buf);
    try std.testing.expectEqualStrings("Jun 15", out1);
    var buf2: [32]u8 = undefined;
    const out2 = try formatDate(Date.initUnchecked(2024, 6, 15), "MMMM D, YYYY", &buf2);
    try std.testing.expectEqualStrings("June 15, 2024", out2);
}

test "formatDate ordinal Do" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1st", try formatDate(Date.initUnchecked(2024, 1, 1), "Do", &buf));
    try std.testing.expectEqualStrings("2nd", try formatDate(Date.initUnchecked(2024, 1, 2), "Do", &buf));
    try std.testing.expectEqualStrings("3rd", try formatDate(Date.initUnchecked(2024, 1, 3), "Do", &buf));
    try std.testing.expectEqualStrings("4th", try formatDate(Date.initUnchecked(2024, 1, 4), "Do", &buf));
    try std.testing.expectEqualStrings("11th", try formatDate(Date.initUnchecked(2024, 1, 11), "Do", &buf));
    try std.testing.expectEqualStrings("12th", try formatDate(Date.initUnchecked(2024, 1, 12), "Do", &buf));
    try std.testing.expectEqualStrings("13th", try formatDate(Date.initUnchecked(2024, 1, 13), "Do", &buf));
    try std.testing.expectEqualStrings("21st", try formatDate(Date.initUnchecked(2024, 1, 21), "Do", &buf));
    try std.testing.expectEqualStrings("23rd", try formatDate(Date.initUnchecked(2024, 1, 23), "Do", &buf));
}

test "formatDate weekday names" {
    var buf: [32]u8 = undefined;
    // Jan 15, 2024 is Monday.
    try std.testing.expectEqualStrings("Mon", try formatDate(Date.initUnchecked(2024, 1, 15), "ddd", &buf));
    try std.testing.expectEqualStrings("Monday", try formatDate(Date.initUnchecked(2024, 1, 15), "dddd", &buf));
}

test "formatTime HH:mm:ss" {
    var buf: [32]u8 = undefined;
    const t = try Time.init(14, 30, 45);
    try std.testing.expectEqualStrings("14:30:45", try formatTime(t, "HH:mm:ss", &buf));
}

test "formatTime 12-hour with am/pm" {
    var buf: [32]u8 = undefined;
    const morning = try Time.init(9, 30, 0);
    try std.testing.expectEqualStrings("9:30 am", try formatTime(morning, "h:mm a", &buf));
    const afternoon = try Time.init(14, 30, 0);
    try std.testing.expectEqualStrings("2:30 PM", try formatTime(afternoon, "h:mm A", &buf));
    const midnight = try Time.init(0, 0, 0);
    try std.testing.expectEqualStrings("12:00 am", try formatTime(midnight, "h:mm a", &buf));
    const noon = try Time.init(12, 0, 0);
    try std.testing.expectEqualStrings("12:00 pm", try formatTime(noon, "h:mm a", &buf));
}

test "formatTime sub-second precision" {
    var buf: [32]u8 = undefined;
    const t = try Time.initFull(14, 30, 45, 123_456_789);
    try std.testing.expectEqualStrings("14:30:45.123", try formatTime(t, "HH:mm:ss.SSS", &buf));
    try std.testing.expectEqualStrings("14:30:45.123456", try formatTime(t, "HH:mm:ss.SSSSSS", &buf));
    try std.testing.expectEqualStrings("14:30:45.123456789", try formatTime(t, "HH:mm:ss.SSSSSSSSS", &buf));
}

test "formatDateTime full ISO-ish" {
    var buf: [64]u8 = undefined;
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 45));
    try std.testing.expectEqualStrings("2024-06-15T14:30:45", try formatDateTime(dt, "YYYY-MM-DDTHH:mm:ss", &buf));
}

test "formatZoned with positive offset" {
    var buf: [64]u8 = undefined;
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 0));
    const z = ZonedDateTime.init(dt, try TimeZone.fromHours(9));
    try std.testing.expectEqualStrings("2024-06-15T14:30:00+09:00", try formatZoned(z, "YYYY-MM-DDTHH:mm:ssZ", &buf));
}

test "formatZoned UTC uses Z" {
    var buf: [64]u8 = undefined;
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 0));
    const z = ZonedDateTime.init(dt, TimeZone.utc);
    try std.testing.expectEqualStrings("2024-06-15T14:30:00Z", try formatZoned(z, "YYYY-MM-DDTHH:mm:ssZ", &buf));
}

test "formatZoned negative offset and compact ZZ form" {
    var buf: [64]u8 = undefined;
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 0));
    const z = ZonedDateTime.init(dt, try TimeZone.fromHours(-5));
    try std.testing.expectEqualStrings("2024-06-15T14:30:00-05:00", try formatZoned(z, "YYYY-MM-DDTHH:mm:ssZ", &buf));
    try std.testing.expectEqualStrings("2024-06-15T14:30:00-0500", try formatZoned(z, "YYYY-MM-DDTHH:mm:ssZZ", &buf));
}

test "formatZoned half-hour offset" {
    var buf: [64]u8 = undefined;
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 0));
    const z = ZonedDateTime.init(dt, try TimeZone.fromHoursMinutes(5, 30));
    try std.testing.expectEqualStrings("2024-06-15T14:30:00+05:30", try formatZoned(z, "YYYY-MM-DDTHH:mm:ssZ", &buf));
}

test "format bracket literal escapes tokens" {
    var buf: [32]u8 = undefined;
    const out = try formatDate(Date.initUnchecked(2024, 6, 15), "[Year:] YYYY", &buf);
    try std.testing.expectEqualStrings("Year: 2024", out);
}

test "format BufferTooSmall on insufficient buffer" {
    var buf: [3]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, formatDate(Date.initUnchecked(2024, 6, 15), "YYYY-MM-DD", &buf));
}

test "formatIso dispatches by input type" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("2024-06-15", try formatIso(Date.initUnchecked(2024, 6, 15), &buf));
    try std.testing.expectEqualStrings("14:30:45", try formatIso(try Time.init(14, 30, 45), &buf));
    const dt = DateTime.init(Date.initUnchecked(2024, 6, 15), try Time.init(14, 30, 45));
    try std.testing.expectEqualStrings("2024-06-15T14:30:45", try formatIso(dt, &buf));
    const z = ZonedDateTime.init(dt, try TimeZone.fromHours(9));
    try std.testing.expectEqualStrings("2024-06-15T14:30:45+09:00", try formatIso(z, &buf));
    const i = Instant.fromEpochSeconds(1_718_460_645); // 2024-06-15T14:10:45Z
    try std.testing.expectEqualStrings("2024-06-15T14:10:45Z", try formatIso(i, &buf));
}
