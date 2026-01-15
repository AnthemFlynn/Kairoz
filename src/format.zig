//! Relative date formatting for display.

const std = @import("std");
const Date = @import("Date.zig").Date;
const daysBetween = @import("arithmetic.zig").daysBetween;

/// Maximum buffer size needed for any formatted output.
pub const max_format_len: usize = 32;

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
