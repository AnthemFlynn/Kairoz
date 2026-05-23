//! Naive time-of-day with nanosecond precision (no time zone).
//!
//! Follows the Zig stdlib "file is the type" convention:
//! `const Time = @import("Time.zig");` returns the type directly.

const std = @import("std");

hour: u8,
minute: u8,
second: u8,
nanosecond: u32,

const Time = @This();

pub const TimeError = error{
    InvalidHour,
    InvalidMinute,
    InvalidSecond,
    InvalidNanosecond,
};

/// 00:00:00.000000000 — start of day.
pub const midnight: Time = .{ .hour = 0, .minute = 0, .second = 0, .nanosecond = 0 };

/// 12:00:00.000000000 — solar noon.
pub const noon: Time = .{ .hour = 12, .minute = 0, .second = 0, .nanosecond = 0 };

/// Construct a validated Time with second precision (nanosecond = 0).
/// Returns error if any field is out of range.
pub fn init(hour: u8, minute: u8, second: u8) TimeError!Time {
    return initFull(hour, minute, second, 0);
}

/// Construct a validated Time with full nanosecond precision.
pub fn initFull(hour: u8, minute: u8, second: u8, nanosecond: u32) TimeError!Time {
    if (hour > 23) return error.InvalidHour;
    if (minute > 59) return error.InvalidMinute;
    if (second > 59) return error.InvalidSecond;
    if (nanosecond > 999_999_999) return error.InvalidNanosecond;
    return .{ .hour = hour, .minute = minute, .second = second, .nanosecond = nanosecond };
}

/// Unchecked construction for internal use where values are known-valid.
/// Skips validation — callers are responsible for staying in range.
pub fn initUnchecked(hour: u8, minute: u8, second: u8, nanosecond: u32) Time {
    return .{ .hour = hour, .minute = minute, .second = second, .nanosecond = nanosecond };
}

/// Total nanoseconds since midnight.
/// Range: 0 .. 86_400_000_000_000 - 1 (exclusive).
pub fn totalNanoseconds(self: Time) u64 {
    const ns_per_s: u64 = 1_000_000_000;
    const seconds_of_day: u64 =
        @as(u64, self.hour) * 3600 +
        @as(u64, self.minute) * 60 +
        @as(u64, self.second);
    return seconds_of_day * ns_per_s + self.nanosecond;
}

/// Order two times. Earlier time is `.lt`.
pub fn compare(self: Time, other: Time) std.math.Order {
    return std.math.order(self.totalNanoseconds(), other.totalNanoseconds());
}

// ============ TESTS ============

test "Time.init constructs valid time" {
    const t = try init(14, 30, 45);
    try std.testing.expectEqual(@as(u8, 14), t.hour);
    try std.testing.expectEqual(@as(u8, 30), t.minute);
    try std.testing.expectEqual(@as(u8, 45), t.second);
    try std.testing.expectEqual(@as(u32, 0), t.nanosecond);
}

test "Time.init rejects out-of-range hour" {
    try std.testing.expectError(error.InvalidHour, init(24, 0, 0));
    try std.testing.expectError(error.InvalidHour, init(99, 0, 0));
}

test "Time.init rejects out-of-range minute" {
    try std.testing.expectError(error.InvalidMinute, init(0, 60, 0));
    try std.testing.expectError(error.InvalidMinute, init(0, 99, 0));
}

test "Time.init rejects out-of-range second" {
    // Leap seconds (60) are NOT accepted — Kairoz follows POSIX time.
    try std.testing.expectError(error.InvalidSecond, init(0, 0, 60));
    try std.testing.expectError(error.InvalidSecond, init(0, 0, 99));
}

test "Time.initFull validates nanoseconds" {
    _ = try initFull(0, 0, 0, 999_999_999);
    try std.testing.expectError(error.InvalidNanosecond, initFull(0, 0, 0, 1_000_000_000));
}

test "Time.init accepts boundary values" {
    _ = try init(0, 0, 0);    // midnight
    _ = try init(23, 59, 59); // last second of day
}

test "Time.midnight constant" {
    try std.testing.expectEqual(@as(u8, 0), midnight.hour);
    try std.testing.expectEqual(@as(u8, 0), midnight.minute);
    try std.testing.expectEqual(@as(u8, 0), midnight.second);
    try std.testing.expectEqual(@as(u32, 0), midnight.nanosecond);
}

test "Time.noon constant" {
    try std.testing.expectEqual(@as(u8, 12), noon.hour);
    try std.testing.expectEqual(@as(u8, 0), noon.minute);
}

test "Time.totalNanoseconds for midnight is zero" {
    try std.testing.expectEqual(@as(u64, 0), midnight.totalNanoseconds());
}

test "Time.totalNanoseconds for noon is half a day" {
    const half_day_ns: u64 = 12 * 3600 * 1_000_000_000;
    try std.testing.expectEqual(half_day_ns, noon.totalNanoseconds());
}

test "Time.totalNanoseconds with nanoseconds" {
    const t = try initFull(1, 2, 3, 456_789_012);
    const expected: u64 = (1 * 3600 + 2 * 60 + 3) * 1_000_000_000 + 456_789_012;
    try std.testing.expectEqual(expected, t.totalNanoseconds());
}

test "Time.totalNanoseconds maximum" {
    const t = try initFull(23, 59, 59, 999_999_999);
    // One nanosecond before the next day
    const expected: u64 = 86_400 * 1_000_000_000 - 1;
    try std.testing.expectEqual(expected, t.totalNanoseconds());
}

test "Time.compare orders earlier as less" {
    const a = try init(9, 0, 0);
    const b = try init(17, 0, 0);
    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
    try std.testing.expectEqual(std.math.Order.gt, b.compare(a));
    try std.testing.expectEqual(std.math.Order.eq, a.compare(a));
}

test "Time.compare differentiates by nanoseconds" {
    const a = try initFull(12, 0, 0, 0);
    const b = try initFull(12, 0, 0, 1);
    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
}
