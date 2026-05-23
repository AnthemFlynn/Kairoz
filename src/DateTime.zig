//! Naive datetime — calendar date plus time-of-day, no time zone.
//!
//! For TZ-aware moments use `ZonedDateTime`. For an absolute moment use
//! `Instant`. A naive `DateTime` is meaningful only when paired with an
//! implicit or external time-zone convention chosen by the caller.

const std = @import("std");
const Date = @import("Date.zig");
const Time = @import("Time.zig");
const Duration = @import("Duration.zig");

date: Date,
time: Time,

const DateTime = @This();

const seconds_per_day: i64 = 86_400;
const ns_per_s_u32: u32 = 1_000_000_000;
const ns_per_s_u64: u64 = 1_000_000_000;

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

/// Add a `Duration` to this naive datetime. The result rolls over day,
/// month, and year boundaries naturally. Since `DateTime` is naive (no
/// time zone), the arithmetic treats one day as exactly 86_400 seconds —
/// DST and leap seconds are not modelled.
pub fn addDuration(self: DateTime, dur: Duration) DateTime {
    const day = Date.dateToEpochDays(self.date);
    const sod: i64 =
        @as(i64, self.time.hour) * 3600 +
        @as(i64, self.time.minute) * 60 +
        @as(i64, self.time.second);

    const total_nanos: u64 = @as(u64, self.time.nanosecond) + @as(u64, dur.nanoseconds);
    const ns_carry: i64 = @intCast(total_nanos / ns_per_s_u64);
    const final_nanos: u32 = @intCast(total_nanos % ns_per_s_u64);

    const final_seconds: i64 = @as(i64, day) * seconds_per_day + sod + dur.seconds + ns_carry;
    const final_day = @divFloor(final_seconds, seconds_per_day);
    const final_sod_total: i64 = final_seconds - final_day * seconds_per_day;
    const final_sod: u32 = @intCast(final_sod_total);

    return .{
        .date = Date.epochDaysToDate(@intCast(final_day)),
        .time = Time.initUnchecked(
            @intCast(final_sod / 3600),
            @intCast((final_sod / 60) % 60),
            @intCast(final_sod % 60),
            final_nanos,
        ),
    };
}

/// Subtract a `Duration`. Equivalent to `addDuration(dur.negate())`.
pub fn subDuration(self: DateTime, dur: Duration) DateTime {
    return self.addDuration(dur.negate());
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

test "DateTime.addDuration adds seconds within same day" {
    const dt = init(Date.initUnchecked(2024, 6, 15), try Time.init(10, 0, 0));
    const result = dt.addDuration(Duration.fromMinutes(5));
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 15), result.date);
    try std.testing.expectEqual(@as(u8, 10), result.time.hour);
    try std.testing.expectEqual(@as(u8, 5), result.time.minute);
}

test "DateTime.addDuration crosses midnight forward" {
    const dt = init(Date.initUnchecked(2024, 6, 15), try Time.init(23, 30, 0));
    const result = dt.addDuration(Duration.fromMinutes(45));
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 16), result.date);
    try std.testing.expectEqual(@as(u8, 0), result.time.hour);
    try std.testing.expectEqual(@as(u8, 15), result.time.minute);
}

test "DateTime.addDuration crosses midnight backward" {
    const dt = init(Date.initUnchecked(2024, 6, 15), try Time.init(0, 15, 0));
    const result = dt.addDuration(Duration.fromMinutes(-30));
    try std.testing.expectEqual(Date.initUnchecked(2024, 6, 14), result.date);
    try std.testing.expectEqual(@as(u8, 23), result.time.hour);
    try std.testing.expectEqual(@as(u8, 45), result.time.minute);
}

test "DateTime.addDuration with nanoseconds carry" {
    const dt = init(Date.initUnchecked(2024, 6, 15), try Time.initFull(10, 0, 0, 700_000_000));
    const result = dt.addDuration(Duration.fromMilliseconds(500));
    try std.testing.expectEqual(@as(u8, 1), result.time.second);
    try std.testing.expectEqual(@as(u32, 200_000_000), result.time.nanosecond);
}

test "DateTime.subDuration is inverse of addDuration" {
    const dt = init(Date.initUnchecked(2024, 6, 15), try Time.init(10, 30, 0));
    const dur = Duration.fromMinutes(75);
    const round = dt.addDuration(dur).subDuration(dur);
    try std.testing.expectEqual(dt.date, round.date);
    try std.testing.expectEqual(dt.time, round.time);
}
