//! An explicit calendar date range with inclusive endpoints.
//!
//! Distinct from `Period`, which models an *implicit* range with fixed
//! granularity (day/week/month/year). A `DateRange` carries arbitrary
//! `start` and `end` dates with no granularity assumption.

const std = @import("std");
const Date = @import("Date.zig");

start: Date,
end: Date,

const DateRange = @This();

pub const DateRangeError = error{
    EndBeforeStart,
};

/// Construct a validated DateRange. `end` must be on or after `start`.
pub fn init(start: Date, end: Date) DateRangeError!DateRange {
    if (Date.dateToEpochDays(end) < Date.dateToEpochDays(start)) {
        return error.EndBeforeStart;
    }
    return .{ .start = start, .end = end };
}

/// Unchecked constructor for internal use where ordering is known-valid.
pub fn initUnchecked(start: Date, end: Date) DateRange {
    return .{ .start = start, .end = end };
}

/// Number of days covered by this range, inclusive.
/// A single-day range returns 1.
pub fn days(self: DateRange) i32 {
    return Date.dateToEpochDays(self.end) - Date.dateToEpochDays(self.start) + 1;
}

/// Does this range contain the given date? Endpoints are inclusive.
pub fn contains(self: DateRange, date: Date) bool {
    const d = Date.dateToEpochDays(date);
    return d >= Date.dateToEpochDays(self.start) and d <= Date.dateToEpochDays(self.end);
}

// ============ TESTS ============

test "DateRange.init valid range" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 1));
    try std.testing.expectEqual(@as(u8, 15), r.start.day);
    try std.testing.expectEqual(@as(u8, 1), r.end.day);
}

test "DateRange.init single-day range" {
    const d = Date.initUnchecked(2024, 6, 15);
    const r = try init(d, d);
    try std.testing.expectEqual(d, r.start);
    try std.testing.expectEqual(d, r.end);
}

test "DateRange.init rejects end-before-start" {
    try std.testing.expectError(
        error.EndBeforeStart,
        init(Date.initUnchecked(2024, 6, 15), Date.initUnchecked(2024, 6, 14)),
    );
}

test "DateRange.days single day is 1" {
    const d = Date.initUnchecked(2024, 6, 15);
    try std.testing.expectEqual(@as(i32, 1), initUnchecked(d, d).days());
}

test "DateRange.days week is 7" {
    const r = try init(Date.initUnchecked(2024, 6, 15), Date.initUnchecked(2024, 6, 21));
    try std.testing.expectEqual(@as(i32, 7), r.days());
}

test "DateRange.days across month boundary" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 14));
    // Jan 15..Jan 31 = 17 days, Feb 1..Feb 14 = 14 days → 31 total
    try std.testing.expectEqual(@as(i32, 31), r.days());
}

test "DateRange.contains start endpoint" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 1));
    try std.testing.expect(r.contains(Date.initUnchecked(2024, 1, 15)));
}

test "DateRange.contains end endpoint" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 1));
    try std.testing.expect(r.contains(Date.initUnchecked(2024, 2, 1)));
}

test "DateRange.contains interior date" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 1));
    try std.testing.expect(r.contains(Date.initUnchecked(2024, 1, 20)));
}

test "DateRange.contains outside range" {
    const r = try init(Date.initUnchecked(2024, 1, 15), Date.initUnchecked(2024, 2, 1));
    try std.testing.expect(!r.contains(Date.initUnchecked(2024, 1, 14)));
    try std.testing.expect(!r.contains(Date.initUnchecked(2024, 2, 2)));
}
