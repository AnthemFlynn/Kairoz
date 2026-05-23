//! A fixed offset from UTC.
//!
//! Kairoz v0.3.0 supports offset-only time zones — no IANA database,
//! no DST rules, no historical transitions. This keeps the library
//! zero-deps. IANA support is reserved for v0.4.0.
//!
//! Real-world offsets range from -12:00 (Baker Island) to +14:00
//! (Line Islands). Some zones use half-hour or quarter-hour offsets
//! (India +05:30, Nepal +05:45, Chatham +12:45), so seconds-precision
//! storage is required.

const std = @import("std");

offset_seconds: i32,

const TimeZone = @This();

pub const TimeZoneError = error{
    OffsetOutOfRange,
};

/// Maximum permissible offset magnitude (±18 hours).
/// Real zones never exceed ±14 hours, but ±18 leaves a margin for
/// historical exotic offsets without overflowing `i32`.
const max_offset_seconds: i32 = 18 * 3_600;

/// UTC. Offset = 0.
pub const utc: TimeZone = .{ .offset_seconds = 0 };

/// Construct from a whole-hour offset, e.g. `fromHours(-5)` for EST.
pub fn fromHours(hours: i8) TimeZoneError!TimeZone {
    return fromSeconds(@as(i32, hours) * 3_600);
}

/// Construct from hours + minutes offset, e.g. `fromHoursMinutes(5, 30)`
/// for India Standard Time, `fromHoursMinutes(-9, -30)` for Marquesas.
/// Both arguments must share the same sign (or one may be zero).
pub fn fromHoursMinutes(hours: i8, minutes: i8) TimeZoneError!TimeZone {
    const total: i32 = @as(i32, hours) * 3_600 + @as(i32, minutes) * 60;
    return fromSeconds(total);
}

/// Construct from a raw offset in seconds.
pub fn fromSeconds(offset_seconds: i32) TimeZoneError!TimeZone {
    if (offset_seconds < -max_offset_seconds or offset_seconds > max_offset_seconds) {
        return error.OffsetOutOfRange;
    }
    return .{ .offset_seconds = offset_seconds };
}

/// Unchecked constructor for internal use where the offset is known valid.
pub fn fromSecondsUnchecked(offset_seconds: i32) TimeZone {
    return .{ .offset_seconds = offset_seconds };
}

// ============ TESTS ============

test "TimeZone.utc has zero offset" {
    try std.testing.expectEqual(@as(i32, 0), utc.offset_seconds);
}

test "TimeZone.fromHours positive" {
    const tz = try fromHours(9);
    try std.testing.expectEqual(@as(i32, 9 * 3600), tz.offset_seconds);
}

test "TimeZone.fromHours negative" {
    const tz = try fromHours(-5);
    try std.testing.expectEqual(@as(i32, -5 * 3600), tz.offset_seconds);
}

test "TimeZone.fromHoursMinutes positive non-whole-hour" {
    // India Standard Time +05:30
    const tz = try fromHoursMinutes(5, 30);
    try std.testing.expectEqual(@as(i32, 5 * 3600 + 30 * 60), tz.offset_seconds);
}

test "TimeZone.fromHoursMinutes negative" {
    // Newfoundland -03:30
    const tz = try fromHoursMinutes(-3, -30);
    try std.testing.expectEqual(@as(i32, -3 * 3600 - 30 * 60), tz.offset_seconds);
}

test "TimeZone.fromSeconds accepts boundary" {
    _ = try fromSeconds(14 * 3600); // +14:00 Kiribati
    _ = try fromSeconds(-12 * 3600); // -12:00 Baker Island
}

test "TimeZone.fromSeconds rejects out-of-range" {
    try std.testing.expectError(error.OffsetOutOfRange, fromSeconds(19 * 3600));
    try std.testing.expectError(error.OffsetOutOfRange, fromSeconds(-19 * 3600));
}

test "TimeZone.fromHours rejects out-of-range" {
    // i8 max is 127, but our cap is ±18 hours
    try std.testing.expectError(error.OffsetOutOfRange, fromHours(19));
    try std.testing.expectError(error.OffsetOutOfRange, fromHours(-19));
}
