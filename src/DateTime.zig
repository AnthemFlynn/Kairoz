//! Naive datetime — calendar date plus time-of-day, no time zone.
//!
//! For TZ-aware moments use `ZonedDateTime`. For an absolute moment use
//! `Instant`. A naive `DateTime` is meaningful only when paired with an
//! implicit or external time-zone convention chosen by the caller.

const std = @import("std");
const Date = @import("Date.zig");
const Time = @import("Time.zig");

date: Date,
time: Time,

const DateTime = @This();

/// Compose a DateTime from validated `Date` and `Time` values.
pub fn init(date: Date, time: Time) DateTime {
    return .{ .date = date, .time = time };
}

/// DateTime at 00:00:00 on the given date.
pub fn atMidnight(date: Date) DateTime {
    return .{ .date = date, .time = Time.midnight };
}

/// DateTime at 12:00:00 on the given date.
pub fn atNoon(date: Date) DateTime {
    return .{ .date = date, .time = Time.noon };
}

/// Order two datetimes. Compares by date first, then by time.
pub fn compare(self: DateTime, other: DateTime) std.math.Order {
    const self_days = Date.dateToEpochDays(self.date);
    const other_days = Date.dateToEpochDays(other.date);
    if (self_days != other_days) return std.math.order(self_days, other_days);
    return self.time.compare(other.time);
}

// ============ TESTS ============

test "DateTime.init composes date and time" {
    const d = Date.initUnchecked(2024, 6, 15);
    const t = try Time.init(14, 30, 0);
    const dt = init(d, t);
    try std.testing.expectEqual(d, dt.date);
    try std.testing.expectEqual(t, dt.time);
}

test "DateTime.atMidnight has zero time" {
    const d = Date.initUnchecked(2024, 6, 15);
    const dt = atMidnight(d);
    try std.testing.expectEqual(Time.midnight, dt.time);
    try std.testing.expectEqual(d, dt.date);
}

test "DateTime.atNoon has noon time" {
    const d = Date.initUnchecked(2024, 6, 15);
    const dt = atNoon(d);
    try std.testing.expectEqual(Time.noon, dt.time);
}

test "DateTime.compare orders by date when dates differ" {
    const earlier = atMidnight(Date.initUnchecked(2024, 1, 1));
    const later = atMidnight(Date.initUnchecked(2024, 12, 31));
    try std.testing.expectEqual(std.math.Order.lt, earlier.compare(later));
    try std.testing.expectEqual(std.math.Order.gt, later.compare(earlier));
}

test "DateTime.compare orders by time when dates match" {
    const d = Date.initUnchecked(2024, 6, 15);
    const morning = init(d, try Time.init(9, 0, 0));
    const evening = init(d, try Time.init(18, 0, 0));
    try std.testing.expectEqual(std.math.Order.lt, morning.compare(evening));
}

test "DateTime.compare equal" {
    const d = Date.initUnchecked(2024, 6, 15);
    const t = try Time.init(12, 0, 0);
    const a = init(d, t);
    const b = init(d, t);
    try std.testing.expectEqual(std.math.Order.eq, a.compare(b));
}

test "DateTime.compare crosses midnight boundary correctly" {
    // 2024-06-15 23:59 is earlier than 2024-06-16 00:01
    const late = init(Date.initUnchecked(2024, 6, 15), try Time.init(23, 59, 0));
    const early = init(Date.initUnchecked(2024, 6, 16), try Time.init(0, 1, 0));
    try std.testing.expectEqual(std.math.Order.lt, late.compare(early));
}
