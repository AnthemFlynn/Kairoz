//! A naive `DateTime` paired with a `TimeZone` offset.
//!
//! `ZonedDateTime` represents a calendar moment as observed in a specific
//! time zone. Two `ZonedDateTime` values in different zones may represent
//! the same `Instant` (the same physical moment) but be structurally
//! distinct.
//!
//! Comparison semantics:
//! - `compare(a, b)` orders by underlying `Instant` (chronological order).
//!   `2024-06-15T14:00+09:00` and `2024-06-15T05:00+00:00` compare equal.
//! - `equalsExact(a, b)` returns true only if both the datetime and the
//!   zone are byte-equal. The two examples above are NOT equalsExact.

const std = @import("std");
const Date = @import("Date.zig");
const Time = @import("Time.zig");
const DateTime = @import("DateTime.zig");
const Duration = @import("Duration.zig");
const Instant = @import("Instant.zig");
const TimeZone = @import("TimeZone.zig");

datetime: DateTime,
zone: TimeZone,

const ZonedDateTime = @This();

const seconds_per_day: i64 = 86_400;

/// Compose from a datetime and a zone.
pub fn init(datetime: DateTime, zone: TimeZone) ZonedDateTime {
    return .{ .datetime = datetime, .zone = zone };
}

/// Current moment, projected into the given zone.
pub fn now(zone: TimeZone) ZonedDateTime {
    return fromInstant(Instant.now(), zone);
}

/// Project an `Instant` into the given zone.
pub fn fromInstant(instant: Instant, zone: TimeZone) ZonedDateTime {
    return .{
        .datetime = instant.toDateTimeAtOffset(zone.offset_seconds),
        .zone = zone,
    };
}

/// Convert back to the underlying `Instant`.
pub fn toInstant(self: ZonedDateTime) Instant {
    const day = Date.dateToEpochDays(self.datetime.date);
    const sec_of_day: i64 =
        @as(i64, self.datetime.time.hour) * 3600 +
        @as(i64, self.datetime.time.minute) * 60 +
        @as(i64, self.datetime.time.second);
    const local_epoch_seconds: i64 = @as(i64, day) * seconds_per_day + sec_of_day;
    return .{
        .epoch_seconds = local_epoch_seconds - @as(i64, self.zone.offset_seconds),
        .nanoseconds = self.datetime.time.nanosecond,
    };
}

/// Order two zoned datetimes chronologically (by underlying instant).
/// Two zoned values in different zones that represent the same physical
/// moment compare as `.eq`.
pub fn compare(self: ZonedDateTime, other: ZonedDateTime) std.math.Order {
    return self.toInstant().compare(other.toInstant());
}

/// True iff `self` and `other` have identical datetime AND zone.
/// Distinct from `compare(...) == .eq`, which is instant-based.
pub fn equalsExact(self: ZonedDateTime, other: ZonedDateTime) bool {
    return std.meta.eql(self, other);
}

// ============ TESTS ============

test "ZonedDateTime.init" {
    const dt = DateTime.atMidnight(Date.initUnchecked(2024, 6, 15));
    const zdt = init(dt, TimeZone.utc);
    try std.testing.expectEqual(dt, zdt.datetime);
    try std.testing.expectEqual(TimeZone.utc, zdt.zone);
}

test "ZonedDateTime.now in UTC has sane current date" {
    const z = now(TimeZone.utc);
    try std.testing.expect(z.datetime.date.year >= 2026);
    try std.testing.expect(z.datetime.date.year < 2100);
}

test "ZonedDateTime.fromInstant in UTC matches toUtcDateTime" {
    const i = Instant.fromEpochSeconds(1_718_409_600); // 2024-06-15T00:00:00Z
    const z = fromInstant(i, TimeZone.utc);
    try std.testing.expectEqual(@as(u16, 2024), z.datetime.date.year);
    try std.testing.expectEqual(@as(u8, 6), z.datetime.date.month);
    try std.testing.expectEqual(@as(u8, 15), z.datetime.date.day);
    try std.testing.expectEqual(@as(u8, 0), z.datetime.time.hour);
}

test "ZonedDateTime.fromInstant in JST (+09:00)" {
    // 2024-06-15T00:00:00Z observed in JST is 09:00 same day.
    const i = Instant.fromEpochSeconds(1_718_409_600);
    const jst = try TimeZone.fromHours(9);
    const z = fromInstant(i, jst);
    try std.testing.expectEqual(@as(u8, 15), z.datetime.date.day);
    try std.testing.expectEqual(@as(u8, 9), z.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 0), z.datetime.time.minute);
}

test "ZonedDateTime.fromInstant in EST (-05:00) crosses date" {
    // 2024-06-15T00:00:00Z observed in EST is 2024-06-14 19:00.
    const i = Instant.fromEpochSeconds(1_718_409_600);
    const est = try TimeZone.fromHours(-5);
    const z = fromInstant(i, est);
    try std.testing.expectEqual(@as(u8, 14), z.datetime.date.day);
    try std.testing.expectEqual(@as(u8, 19), z.datetime.time.hour);
}

test "ZonedDateTime.fromInstant in IST (+05:30) — half-hour offset" {
    const i = Instant.fromEpochSeconds(1_718_409_600);
    const ist = try TimeZone.fromHoursMinutes(5, 30);
    const z = fromInstant(i, ist);
    try std.testing.expectEqual(@as(u8, 15), z.datetime.date.day);
    try std.testing.expectEqual(@as(u8, 5), z.datetime.time.hour);
    try std.testing.expectEqual(@as(u8, 30), z.datetime.time.minute);
}

test "ZonedDateTime round-trip preserves Instant in UTC" {
    const original = Instant{ .epoch_seconds = 1_718_409_645, .nanoseconds = 123_456_789 };
    const round = fromInstant(original, TimeZone.utc).toInstant();
    try std.testing.expectEqual(original.epoch_seconds, round.epoch_seconds);
    try std.testing.expectEqual(original.nanoseconds, round.nanoseconds);
}

test "ZonedDateTime round-trip preserves Instant in JST" {
    const original = Instant{ .epoch_seconds = 1_718_409_645, .nanoseconds = 123_456_789 };
    const jst = try TimeZone.fromHours(9);
    const round = fromInstant(original, jst).toInstant();
    try std.testing.expectEqual(original.epoch_seconds, round.epoch_seconds);
    try std.testing.expectEqual(original.nanoseconds, round.nanoseconds);
}

test "ZonedDateTime round-trip preserves Instant in IST (half-hour)" {
    const original = Instant{ .epoch_seconds = 1_718_409_645, .nanoseconds = 0 };
    const ist = try TimeZone.fromHoursMinutes(5, 30);
    const round = fromInstant(original, ist).toInstant();
    try std.testing.expectEqual(original.epoch_seconds, round.epoch_seconds);
}

test "ZonedDateTime round-trip preserves Instant pre-1970" {
    // 1965-03-15T00:00:00Z
    const original = Instant.fromEpochSeconds(-150_336_000);
    const round = fromInstant(original, TimeZone.utc).toInstant();
    try std.testing.expectEqual(original.epoch_seconds, round.epoch_seconds);
}

test "ZonedDateTime.compare same instant in different zones equals" {
    const i = Instant.fromEpochSeconds(1_718_409_600);
    const utc_view = fromInstant(i, TimeZone.utc);
    const jst_view = fromInstant(i, try TimeZone.fromHours(9));
    try std.testing.expectEqual(std.math.Order.eq, utc_view.compare(jst_view));
}

test "ZonedDateTime.compare orders by instant" {
    const earlier = fromInstant(Instant.fromEpochSeconds(100), TimeZone.utc);
    const later = fromInstant(Instant.fromEpochSeconds(200), try TimeZone.fromHours(9));
    try std.testing.expectEqual(std.math.Order.lt, earlier.compare(later));
}

test "ZonedDateTime.equalsExact distinguishes zones" {
    const i = Instant.fromEpochSeconds(1_718_409_600);
    const utc_view = fromInstant(i, TimeZone.utc);
    const jst_view = fromInstant(i, try TimeZone.fromHours(9));
    // Same instant, different zones → NOT equalsExact, but compare == .eq
    try std.testing.expect(!utc_view.equalsExact(jst_view));
    try std.testing.expectEqual(std.math.Order.eq, utc_view.compare(jst_view));
}

test "ZonedDateTime.equalsExact same datetime same zone" {
    const dt = DateTime.atNoon(Date.initUnchecked(2024, 6, 15));
    const a = init(dt, TimeZone.utc);
    const b = init(dt, TimeZone.utc);
    try std.testing.expect(a.equalsExact(b));
}
