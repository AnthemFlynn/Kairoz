//! An absolute moment in time, UTC-anchored, with nanosecond precision.
//!
//! Layer 3 of the Kairoz type hierarchy. An `Instant` has no time zone —
//! it represents the same physical moment regardless of where it's observed.
//! Project to a calendar via `toZonedDateTime(zone)` or `toUtcDateTime()`.
//!
//! Representation: `(i64 epoch_seconds, u32 nanoseconds)` matches POSIX
//! `clock_gettime(CLOCK_REALTIME)` and java.time's `Instant`. Covers
//! year-1 through ~year 292 billion with nanosecond resolution.

const std = @import("std");
const builtin = @import("builtin");
const Date = @import("Date.zig");
const Time = @import("Time.zig");
const DateTime = @import("DateTime.zig");
const Duration = @import("Duration.zig");

epoch_seconds: i64,
nanoseconds: u32,

const Instant = @This();

const ns_per_s_u32: u32 = 1_000_000_000;
const ns_per_s_u64: u64 = 1_000_000_000;
const seconds_per_day: i64 = 86_400;

/// 1970-01-01T00:00:00.000000000Z — the Unix epoch.
pub const epoch: Instant = .{ .epoch_seconds = 0, .nanoseconds = 0 };

/// Construct from a whole-second Unix timestamp.
pub fn fromEpochSeconds(s: i64) Instant {
    return .{ .epoch_seconds = s, .nanoseconds = 0 };
}

/// Construct from a Unix millisecond timestamp.
pub fn fromUnixMillis(ms: i64) Instant {
    const seconds = @divFloor(ms, 1_000);
    const remainder_ms: i64 = ms - seconds * 1_000;
    return .{
        .epoch_seconds = seconds,
        .nanoseconds = @intCast(remainder_ms * 1_000_000),
    };
}

/// Construct from a Unix microsecond timestamp.
pub fn fromUnixMicros(us: i64) Instant {
    const seconds = @divFloor(us, 1_000_000);
    const remainder_us: i64 = us - seconds * 1_000_000;
    return .{
        .epoch_seconds = seconds,
        .nanoseconds = @intCast(remainder_us * 1_000),
    };
}

/// Current system clock reading. Falls back to `epoch` on clock failure
/// — pathological case; if you need to distinguish, call `nowChecked()`.
///
/// POSIX: `clock_gettime(CLOCK_REALTIME)`.
/// Windows: KUSER_SHARED_DATA `SystemTime` (100-ns intervals from 1601).
pub fn now() Instant {
    return nowChecked() catch epoch;
}

/// Like `now()` but returns an error on clock failure instead of falling
/// back to the Unix epoch.
pub fn nowChecked() error{ClockUnavailable}!Instant {
    if (builtin.os.tag == .windows) {
        const sys_time = std.os.windows.SharedUserData.SystemTime;
        const hns: i64 = (@as(i64, sys_time.High1Time) << 32) | sys_time.LowPart;
        // hns is 100-ns intervals since 1601-01-01.
        const total_seconds = @divFloor(hns, 10_000_000) + std.time.epoch.windows;
        const remainder_100ns: u32 = @intCast(@mod(hns, 10_000_000));
        return .{ .epoch_seconds = total_seconds, .nanoseconds = remainder_100ns * 100 };
    } else {
        var ts: std.posix.timespec = undefined;
        switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
            .SUCCESS => return .{ .epoch_seconds = ts.sec, .nanoseconds = @intCast(ts.nsec) },
            else => return error.ClockUnavailable,
        }
    }
}

/// Add a duration to this instant.
pub fn addDuration(self: Instant, dur: Duration) Instant {
    const total_nanos: u64 = @as(u64, self.nanoseconds) + @as(u64, dur.nanoseconds);
    const carry: i64 = @intCast(total_nanos / ns_per_s_u64);
    const nanos: u32 = @intCast(total_nanos % ns_per_s_u64);
    return .{
        .epoch_seconds = self.epoch_seconds + dur.seconds + carry,
        .nanoseconds = nanos,
    };
}

/// Subtract a duration from this instant.
pub fn subDuration(self: Instant, dur: Duration) Instant {
    return self.addDuration(dur.negate());
}

/// Compute `self - other` as a Duration.
pub fn durationSince(self: Instant, other: Instant) Duration {
    const sec_diff = self.epoch_seconds - other.epoch_seconds;
    const ns_diff: i64 = @as(i64, self.nanoseconds) - @as(i64, other.nanoseconds);
    if (ns_diff >= 0) {
        return .{ .seconds = sec_diff, .nanoseconds = @intCast(ns_diff) };
    } else {
        // Borrow from seconds.
        return .{
            .seconds = sec_diff - 1,
            .nanoseconds = @intCast(@as(i64, ns_per_s_u32) + ns_diff),
        };
    }
}

/// Order two instants chronologically.
pub fn compare(self: Instant, other: Instant) std.math.Order {
    if (self.epoch_seconds != other.epoch_seconds) {
        return std.math.order(self.epoch_seconds, other.epoch_seconds);
    }
    return std.math.order(self.nanoseconds, other.nanoseconds);
}

/// Project this instant to UTC and return the calendar date.
pub fn toUtcDate(self: Instant) Date {
    const day = @divFloor(self.epoch_seconds, seconds_per_day);
    return Date.epochDaysToDate(@intCast(day));
}

/// Project this instant to UTC and return the naive DateTime.
pub fn toUtcDateTime(self: Instant) DateTime {
    return self.toDateTimeAtOffset(0);
}

/// Project this instant to a specific offset (seconds east of UTC) and
/// return the naive DateTime that observers in that zone would read.
/// Exposed primarily for `ZonedDateTime`; consumers usually call
/// `ZonedDateTime.fromInstant` instead.
pub fn toDateTimeAtOffset(self: Instant, offset_seconds: i32) DateTime {
    const local_seconds = self.epoch_seconds + @as(i64, offset_seconds);
    const day = @divFloor(local_seconds, seconds_per_day);
    const sec_of_day: i64 = local_seconds - day * seconds_per_day; // always in [0, 86400)
    const sod_u32: u32 = @intCast(sec_of_day);
    const hour: u8 = @intCast(sod_u32 / 3600);
    const minute: u8 = @intCast((sod_u32 / 60) % 60);
    const second: u8 = @intCast(sod_u32 % 60);
    return .{
        .date = Date.epochDaysToDate(@intCast(day)),
        .time = Time.initUnchecked(hour, minute, second, self.nanoseconds),
    };
}

// ============ TESTS ============

test "Instant.epoch is Unix epoch" {
    try std.testing.expectEqual(@as(i64, 0), epoch.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 0), epoch.nanoseconds);
}

test "Instant.fromEpochSeconds" {
    const i = fromEpochSeconds(1_700_000_000);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), i.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 0), i.nanoseconds);
}

test "Instant.fromUnixMillis positive" {
    const i = fromUnixMillis(1_500); // 1.5 s after epoch
    try std.testing.expectEqual(@as(i64, 1), i.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), i.nanoseconds);
}

test "Instant.fromUnixMillis negative" {
    // -1.5 s after epoch = epoch_seconds=-2, ns=500_000_000
    const i = fromUnixMillis(-1_500);
    try std.testing.expectEqual(@as(i64, -2), i.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), i.nanoseconds);
}

test "Instant.fromUnixMicros" {
    const i = fromUnixMicros(2_500_000); // 2.5 s
    try std.testing.expectEqual(@as(i64, 2), i.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), i.nanoseconds);
}

test "Instant.now returns a sane value" {
    const i = now();
    // The Kairoz repo started in 2026; the clock should be at least that.
    // Upper bound prevents a stuck clock from passing.
    try std.testing.expect(i.epoch_seconds > 1_700_000_000); // > 2023-11-14
    try std.testing.expect(i.epoch_seconds < 4_102_444_800); // < 2100-01-01
    try std.testing.expect(i.nanoseconds < 1_000_000_000);
}

test "Instant.nowChecked succeeds on a healthy system" {
    const i = try nowChecked();
    try std.testing.expect(i.epoch_seconds > 1_700_000_000);
}

test "Instant.addDuration positive" {
    const start = fromEpochSeconds(100);
    const result = start.addDuration(Duration.fromSeconds(50));
    try std.testing.expectEqual(@as(i64, 150), result.epoch_seconds);
}

test "Instant.addDuration with nanosecond carry" {
    const start = Instant{ .epoch_seconds = 100, .nanoseconds = 700_000_000 };
    const result = start.addDuration(Duration.fromMilliseconds(500));
    try std.testing.expectEqual(@as(i64, 101), result.epoch_seconds);
    try std.testing.expectEqual(@as(u32, 200_000_000), result.nanoseconds);
}

test "Instant.subDuration" {
    const start = fromEpochSeconds(100);
    const result = start.subDuration(Duration.fromSeconds(30));
    try std.testing.expectEqual(@as(i64, 70), result.epoch_seconds);
}

test "Instant.durationSince" {
    const earlier = fromEpochSeconds(100);
    const later = fromEpochSeconds(160);
    const dur = later.durationSince(earlier);
    try std.testing.expectEqual(@as(i64, 60), dur.seconds);
    try std.testing.expectEqual(@as(u32, 0), dur.nanoseconds);
}

test "Instant.durationSince with nanosecond borrow" {
    const earlier = Instant{ .epoch_seconds = 100, .nanoseconds = 700_000_000 };
    const later = Instant{ .epoch_seconds = 102, .nanoseconds = 200_000_000 };
    const dur = later.durationSince(earlier);
    // 102.2 - 100.7 = 1.5
    try std.testing.expectEqual(@as(i64, 1), dur.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), dur.nanoseconds);
}

test "Instant.durationSince negative direction" {
    const a = fromEpochSeconds(100);
    const b = fromEpochSeconds(160);
    const dur = a.durationSince(b);
    try std.testing.expectEqual(@as(i64, -60), dur.seconds);
    try std.testing.expectEqual(@as(u32, 0), dur.nanoseconds);
}

test "Instant.compare" {
    try std.testing.expectEqual(std.math.Order.lt, fromEpochSeconds(1).compare(fromEpochSeconds(2)));
    try std.testing.expectEqual(std.math.Order.gt, fromEpochSeconds(5).compare(fromEpochSeconds(3)));
    try std.testing.expectEqual(std.math.Order.eq, fromEpochSeconds(7).compare(fromEpochSeconds(7)));
}

test "Instant.compare differentiates by nanoseconds" {
    const a = Instant{ .epoch_seconds = 100, .nanoseconds = 0 };
    const b = Instant{ .epoch_seconds = 100, .nanoseconds = 1 };
    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
}

test "Instant.toUtcDate at Unix epoch" {
    const d = epoch.toUtcDate();
    try std.testing.expectEqual(@as(u16, 1970), d.year);
    try std.testing.expectEqual(@as(u8, 1), d.month);
    try std.testing.expectEqual(@as(u8, 1), d.day);
}

test "Instant.toUtcDate known timestamp" {
    // 2024-01-15T00:00:00Z = 1705276800
    const d = fromEpochSeconds(1_705_276_800).toUtcDate();
    try std.testing.expectEqual(@as(u16, 2024), d.year);
    try std.testing.expectEqual(@as(u8, 1), d.month);
    try std.testing.expectEqual(@as(u8, 15), d.day);
}

test "Instant.toUtcDateTime preserves nanoseconds" {
    const i = Instant{ .epoch_seconds = 1_705_276_845, .nanoseconds = 123_456_789 };
    const dt = i.toUtcDateTime();
    try std.testing.expectEqual(@as(u16, 2024), dt.date.year);
    try std.testing.expectEqual(@as(u8, 1), dt.date.month);
    try std.testing.expectEqual(@as(u8, 15), dt.date.day);
    try std.testing.expectEqual(@as(u8, 0), dt.time.hour);
    try std.testing.expectEqual(@as(u8, 0), dt.time.minute);
    try std.testing.expectEqual(@as(u8, 45), dt.time.second);
    try std.testing.expectEqual(@as(u32, 123_456_789), dt.time.nanosecond);
}

test "Instant.toDateTimeAtOffset positive offset" {
    // 2024-06-15T00:00:00Z observed in +09:00 (JST) is 09:00 same day.
    const i = fromEpochSeconds(1_718_409_600);
    const dt = i.toDateTimeAtOffset(9 * 3600);
    try std.testing.expectEqual(@as(u16, 2024), dt.date.year);
    try std.testing.expectEqual(@as(u8, 6), dt.date.month);
    try std.testing.expectEqual(@as(u8, 15), dt.date.day);
    try std.testing.expectEqual(@as(u8, 9), dt.time.hour);
    try std.testing.expectEqual(@as(u8, 0), dt.time.minute);
}

test "Instant.toDateTimeAtOffset negative offset crosses date" {
    // 2024-06-15T00:00:00Z observed in -05:00 (EST) is 2024-06-14 19:00.
    const i = fromEpochSeconds(1_718_409_600);
    const dt = i.toDateTimeAtOffset(-5 * 3600);
    try std.testing.expectEqual(@as(u16, 2024), dt.date.year);
    try std.testing.expectEqual(@as(u8, 6), dt.date.month);
    try std.testing.expectEqual(@as(u8, 14), dt.date.day);
    try std.testing.expectEqual(@as(u8, 19), dt.time.hour);
}

test "Instant.toDateTimeAtOffset half-hour offset (India)" {
    // 2024-06-15T00:00:00Z observed in +05:30 (IST) is 05:30 same day.
    const i = fromEpochSeconds(1_718_409_600);
    const dt = i.toDateTimeAtOffset(5 * 3600 + 30 * 60);
    try std.testing.expectEqual(@as(u8, 5), dt.time.hour);
    try std.testing.expectEqual(@as(u8, 30), dt.time.minute);
}
