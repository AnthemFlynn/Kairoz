//! Kairoz - Natural language date parsing for Zig
//!
//! A zero-dependency library for parsing human-friendly date expressions.

/// Library version. Kept in sync with `build.zig.zon` manually.
pub const version = "0.2.1";

pub const Date = @import("Date.zig");
pub const DateError = Date.DateError;
pub const today = Date.today;
pub const isLeapYear = Date.isLeapYear;
pub const daysInMonth = Date.daysInMonth;

pub const Time = @import("Time.zig");
pub const TimeError = Time.TimeError;

pub const DateTime = @import("DateTime.zig");

pub const Duration = @import("Duration.zig");

pub const ParsedDate = @import("parse.zig").ParsedDate;
pub const ParseError = @import("parse.zig").ParseError;
pub const Granularity = @import("parse.zig").Granularity;
pub const Period = @import("parse.zig").Period;
pub const parse = @import("parse.zig").parse;
pub const parseWithReference = @import("parse.zig").parseWithReference;

pub const ArithmeticError = @import("arithmetic.zig").ArithmeticError;
pub const addDays = @import("arithmetic.zig").addDays;
pub const addMonths = @import("arithmetic.zig").addMonths;
pub const addYears = @import("arithmetic.zig").addYears;
pub const daysBetween = @import("arithmetic.zig").daysBetween;
pub const daysUntil = @import("arithmetic.zig").daysUntil;
pub const firstDayOfMonth = @import("arithmetic.zig").firstDayOfMonth;
pub const lastDayOfMonth = @import("arithmetic.zig").lastDayOfMonth;
pub const dayOfWeek = @import("arithmetic.zig").dayOfWeek;
pub const startOfWeek = @import("arithmetic.zig").startOfWeek;
pub const endOfWeek = @import("arithmetic.zig").endOfWeek;

pub const formatRelative = @import("format.zig").formatRelative;
pub const max_format_len = @import("format.zig").max_format_len;

test {
    _ = @import("Date.zig");
    _ = @import("Time.zig");
    _ = @import("DateTime.zig");
    _ = @import("Duration.zig");
    _ = @import("parse.zig");
    _ = @import("arithmetic.zig");
    _ = @import("format.zig");
}
