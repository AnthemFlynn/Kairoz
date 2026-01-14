//! Kairoz - Natural language date parsing for Zig
//!
//! A zero-dependency library for parsing human-friendly date expressions.

pub const Date = @import("Date.zig").Date;
pub const DateError = @import("Date.zig").DateError;
pub const today = @import("Date.zig").today;
pub const isLeapYear = @import("Date.zig").isLeapYear;
pub const daysInMonth = @import("Date.zig").daysInMonth;

test {
    _ = @import("Date.zig");
}
