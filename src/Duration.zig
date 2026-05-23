//! A signed duration with nanosecond precision.
//!
//! Representation: `seconds` carries the sign of the duration;
//! `nanoseconds` is always the non-negative fractional part (0..999_999_999).
//!
//! Total nanoseconds = seconds * 1_000_000_000 + nanoseconds.
//!
//! Examples:
//!   +5.5 s  → .{ .seconds =  5, .nanoseconds = 500_000_000 }
//!    0.0 s  → .{ .seconds =  0, .nanoseconds = 0 }
//!   -0.5 s  → .{ .seconds = -1, .nanoseconds = 500_000_000 }   // -1 + 0.5
//!   -1.0 s  → .{ .seconds = -1, .nanoseconds = 0 }
//!   -1.5 s  → .{ .seconds = -2, .nanoseconds = 500_000_000 }   // -2 + 0.5

const std = @import("std");

seconds: i64,
nanoseconds: u32,

const Duration = @This();

const ns_per_s_i64: i64 = 1_000_000_000;
const ns_per_s_u32: u32 = 1_000_000_000;

pub const zero: Duration = .{ .seconds = 0, .nanoseconds = 0 };

/// Construct from a total nanosecond count. Normalises so `nanoseconds`
/// is always in [0, 1_000_000_000).
pub fn fromNanoseconds(n: i64) Duration {
    const seconds = @divFloor(n, ns_per_s_i64);
    const frac = n - seconds * ns_per_s_i64; // floor remainder, always in [0, 1e9)
    return .{ .seconds = seconds, .nanoseconds = @intCast(frac) };
}

/// Construct from microseconds (10⁻⁶ s).
pub fn fromMicroseconds(n: i64) Duration {
    return fromNanoseconds(n * 1_000);
}

/// Construct from milliseconds (10⁻³ s).
pub fn fromMilliseconds(n: i64) Duration {
    return fromNanoseconds(n * 1_000_000);
}

/// Construct from whole seconds.
pub fn fromSeconds(n: i64) Duration {
    return .{ .seconds = n, .nanoseconds = 0 };
}

/// Construct from whole minutes (60 s).
pub fn fromMinutes(n: i64) Duration {
    return .{ .seconds = n * 60, .nanoseconds = 0 };
}

/// Construct from whole hours (3600 s).
pub fn fromHours(n: i64) Duration {
    return .{ .seconds = n * 3_600, .nanoseconds = 0 };
}

/// Construct from whole days (86400 s — calendar days are 86400 s by
/// definition in Kairoz, ignoring DST and leap seconds).
pub fn fromDays(n: i64) Duration {
    return .{ .seconds = n * 86_400, .nanoseconds = 0 };
}

/// Construct from whole weeks (7 × 86400 s).
pub fn fromWeeks(n: i64) Duration {
    return .{ .seconds = n * 604_800, .nanoseconds = 0 };
}

/// Does this duration represent exactly zero time?
pub fn isZero(self: Duration) bool {
    return self.seconds == 0 and self.nanoseconds == 0;
}

/// Does this duration represent a strictly negative time delta?
pub fn isNegative(self: Duration) bool {
    return self.seconds < 0;
}

/// Return -self.
pub fn negate(self: Duration) Duration {
    if (self.nanoseconds == 0) {
        return .{ .seconds = -self.seconds, .nanoseconds = 0 };
    }
    // -(s + frac/1e9) = -(s+1) + (1e9 - frac)/1e9
    return .{
        .seconds = -self.seconds - 1,
        .nanoseconds = ns_per_s_u32 - self.nanoseconds,
    };
}

/// Sum two durations. Normalises the result.
pub fn add(self: Duration, other: Duration) Duration {
    // Sum of two u32 values each ≤ 999_999_999 fits comfortably in u64.
    const total_nanos: u64 = @as(u64, self.nanoseconds) + @as(u64, other.nanoseconds);
    const carry: i64 = @intCast(total_nanos / ns_per_s_u32);
    const nanos: u32 = @intCast(total_nanos % ns_per_s_u32);
    return .{ .seconds = self.seconds + other.seconds + carry, .nanoseconds = nanos };
}

/// Compute self - other.
pub fn sub(self: Duration, other: Duration) Duration {
    return self.add(other.negate());
}

/// Order two durations.
pub fn compare(self: Duration, other: Duration) std.math.Order {
    if (self.seconds != other.seconds) {
        return std.math.order(self.seconds, other.seconds);
    }
    return std.math.order(self.nanoseconds, other.nanoseconds);
}

/// Total nanoseconds across the whole duration, as a signed 128-bit count.
/// Safe across the full i64-second range.
pub fn totalNanoseconds(self: Duration) i128 {
    return @as(i128, self.seconds) * ns_per_s_i64 + @as(i128, self.nanoseconds);
}

// ============ TESTS ============

test "Duration.zero" {
    try std.testing.expect(zero.isZero());
    try std.testing.expectEqual(@as(i64, 0), zero.seconds);
    try std.testing.expectEqual(@as(u32, 0), zero.nanoseconds);
}

test "Duration.fromSeconds positive" {
    const d = fromSeconds(42);
    try std.testing.expectEqual(@as(i64, 42), d.seconds);
    try std.testing.expectEqual(@as(u32, 0), d.nanoseconds);
}

test "Duration.fromSeconds negative" {
    const d = fromSeconds(-7);
    try std.testing.expectEqual(@as(i64, -7), d.seconds);
    try std.testing.expectEqual(@as(u32, 0), d.nanoseconds);
}

test "Duration.fromMinutes" {
    try std.testing.expectEqual(@as(i64, 300), fromMinutes(5).seconds);
    try std.testing.expectEqual(@as(i64, -180), fromMinutes(-3).seconds);
}

test "Duration.fromHours" {
    try std.testing.expectEqual(@as(i64, 7_200), fromHours(2).seconds);
}

test "Duration.fromDays" {
    try std.testing.expectEqual(@as(i64, 86_400), fromDays(1).seconds);
}

test "Duration.fromWeeks" {
    try std.testing.expectEqual(@as(i64, 604_800), fromWeeks(1).seconds);
}

test "Duration.fromMilliseconds positive" {
    const d = fromMilliseconds(2_500); // 2.5 s
    try std.testing.expectEqual(@as(i64, 2), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.fromMilliseconds negative" {
    // -2.5 s = -3 + 0.5
    const d = fromMilliseconds(-2_500);
    try std.testing.expectEqual(@as(i64, -3), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.fromMicroseconds" {
    const d = fromMicroseconds(1_500_000); // 1.5 s
    try std.testing.expectEqual(@as(i64, 1), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.fromNanoseconds positive sub-second" {
    const d = fromNanoseconds(500_000_000);
    try std.testing.expectEqual(@as(i64, 0), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.fromNanoseconds negative sub-second" {
    // -0.5 s
    const d = fromNanoseconds(-500_000_000);
    try std.testing.expectEqual(@as(i64, -1), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.fromNanoseconds spans whole seconds" {
    // -1.5 s
    const d = fromNanoseconds(-1_500_000_000);
    try std.testing.expectEqual(@as(i64, -2), d.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), d.nanoseconds);
}

test "Duration.isNegative" {
    try std.testing.expect(fromSeconds(-1).isNegative());
    try std.testing.expect(!fromSeconds(0).isNegative());
    try std.testing.expect(!fromSeconds(1).isNegative());
    // Sub-second negatives carry a -1 seconds field
    try std.testing.expect(fromMilliseconds(-500).isNegative());
}

test "Duration.negate whole seconds" {
    const d = fromSeconds(5);
    const neg = d.negate();
    try std.testing.expectEqual(@as(i64, -5), neg.seconds);
    try std.testing.expectEqual(@as(u32, 0), neg.nanoseconds);
}

test "Duration.negate zero" {
    const neg = zero.negate();
    try std.testing.expect(neg.isZero());
}

test "Duration.negate with fractional part" {
    // negate(+5.5) → -5.5 = -6 + 0.5
    const d = Duration{ .seconds = 5, .nanoseconds = 500_000_000 };
    const neg = d.negate();
    try std.testing.expectEqual(@as(i64, -6), neg.seconds);
    try std.testing.expectEqual(@as(u32, 500_000_000), neg.nanoseconds);
}

test "Duration.negate round-trip" {
    const original = fromMilliseconds(-1_750); // -1.75 s
    const round_trip = original.negate().negate();
    try std.testing.expectEqual(original.seconds, round_trip.seconds);
    try std.testing.expectEqual(original.nanoseconds, round_trip.nanoseconds);
}

test "Duration.add no nanosecond carry" {
    const a = fromSeconds(3);
    const b = fromSeconds(4);
    const sum = a.add(b);
    try std.testing.expectEqual(@as(i64, 7), sum.seconds);
    try std.testing.expectEqual(@as(u32, 0), sum.nanoseconds);
}

test "Duration.add with nanosecond carry" {
    // 0.7 + 0.7 = 1.4
    const a = fromMilliseconds(700);
    const b = fromMilliseconds(700);
    const sum = a.add(b);
    try std.testing.expectEqual(@as(i64, 1), sum.seconds);
    try std.testing.expectEqual(@as(u32, 400_000_000), sum.nanoseconds);
}

test "Duration.add negative and positive" {
    // -4.5 + 3.7 = -0.8
    const a = fromMilliseconds(-4_500);
    const b = fromMilliseconds(3_700);
    const sum = a.add(b);
    // -0.8 = -1 + 0.2
    try std.testing.expectEqual(@as(i64, -1), sum.seconds);
    try std.testing.expectEqual(@as(u32, 200_000_000), sum.nanoseconds);
}

test "Duration.sub" {
    // 10 - 3 = 7
    const sum = fromSeconds(10).sub(fromSeconds(3));
    try std.testing.expectEqual(@as(i64, 7), sum.seconds);
}

test "Duration.sub crossing zero" {
    // 3 - 5 = -2
    const sum = fromSeconds(3).sub(fromSeconds(5));
    try std.testing.expectEqual(@as(i64, -2), sum.seconds);
}

test "Duration.compare" {
    try std.testing.expectEqual(std.math.Order.lt, fromSeconds(1).compare(fromSeconds(2)));
    try std.testing.expectEqual(std.math.Order.gt, fromSeconds(5).compare(fromSeconds(2)));
    try std.testing.expectEqual(std.math.Order.eq, fromSeconds(3).compare(fromSeconds(3)));
}

test "Duration.compare differentiates by nanoseconds" {
    const a = fromMilliseconds(1_500);
    const b = fromMilliseconds(1_750);
    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
}

test "Duration.totalNanoseconds positive" {
    const d = fromMilliseconds(1_500);
    try std.testing.expectEqual(@as(i128, 1_500_000_000), d.totalNanoseconds());
}

test "Duration.totalNanoseconds negative" {
    const d = fromMilliseconds(-1_500);
    try std.testing.expectEqual(@as(i128, -1_500_000_000), d.totalNanoseconds());
}
