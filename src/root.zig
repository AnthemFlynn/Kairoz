//! Kairoz - Natural language date parsing for Zig
//!
//! A zero-dependency library for parsing human-friendly date expressions.

pub const Date = @import("Date.zig").Date;
pub const DateError = @import("Date.zig").DateError;
pub const today = @import("Date.zig").today;
pub const isLeapYear = @import("Date.zig").isLeapYear;
pub const daysInMonth = @import("Date.zig").daysInMonth;

pub const ParsedDate = @import("parse.zig").ParsedDate;
pub const ParseError = @import("parse.zig").ParseError;
pub const parse = @import("parse.zig").parse;
pub const parseWithReference = @import("parse.zig").parseWithReference;

pub const addDays = @import("arithmetic.zig").addDays;
pub const addMonths = @import("arithmetic.zig").addMonths;
pub const daysBetween = @import("arithmetic.zig").daysBetween;
pub const daysUntil = @import("arithmetic.zig").daysUntil;

test {
    _ = @import("Date.zig");
    _ = @import("parse.zig");
    _ = @import("arithmetic.zig");
}
