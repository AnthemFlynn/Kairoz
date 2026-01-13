# Kairoz Library Design

**Date:** 2026-01-13
**Status:** Draft
**Goal:** Extract date parsing from todo CLI into standalone Zig library

## Overview

Kairoz (from καιρός — "the opportune moment") is a natural language date parsing library for Zig. Zero dependencies, stdlib only.

## Scope

**v0.1.0 — Initial release:**
- Relative dates: today, tomorrow, yesterday
- Weekday names: monday, mon, tuesday, tue, etc.
- Forward offsets: +3d, +2w, +1m
- Special values: next week, next month, none, clear
- Absolute formats: YYYY-MM-DD, MM-DD, DD
- Date arithmetic utilities
- Relative formatting for display

**Future versions:**
- v0.2.0: Month names, negative offsets, eow/eom
- v0.3.0: "ago" patterns, "in X days", last/this weekday

## Repository Structure

```
Kairoz/
├── build.zig
├── build.zig.zon
├── src/
│   └── kairoz.zig      # Single-file library
├── docs/
│   └── plans/
├── README.md
├── LICENSE
└── .gitignore
```

## Package Configuration

**build.zig.zon:**
```zig
.{
    .name = .kairoz,
    .version = "0.1.0",
    .fingerprint = 0x...,  // Auto-generated
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "LICENSE",
        "README.md",
    },
}
```

**build.zig:**
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module exposed to consumers
    const mod = b.addModule("kairoz", .{
        .root_source_file = b.path("src/kairoz.zig"),
        .target = target,
    });

    // Tests
    const tests = b.addTest(.{
        .root_module = mod,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

## Public API

```zig
const kairoz = @import("kairoz");

// Core type
const Date = kairoz.Date;  // { year: u16, month: u8, day: u8 }

// Parse natural language → Date (null for "none"/"clear")
const due = try kairoz.parse("tomorrow");      // ?Date
const cleared = try kairoz.parse("none");      // null

// Get current date
const today = kairoz.today();

// Date arithmetic
const next_week = kairoz.addDays(today, 7);
const next_month = kairoz.addMonths(today, 1);
const diff = kairoz.daysBetween(date1, date2);  // i32
const until = kairoz.daysUntil(due_date);       // i32 (convenience)

// Format for display
var buf: [32]u8 = undefined;
const display = kairoz.formatRelative(due.?, today, &buf);  // "tomorrow"

// Error handling
kairoz.parse("invalid") catch |err| switch (err) {
    error.InvalidFormat => ...,
    error.InvalidDay => ...,
    error.InvalidMonth => ...,
    error.InvalidYear => ...,
    error.InvalidOffset => ...,
};
```

## Source Structure

**src/kairoz.zig:**
```zig
//! Kairoz - Natural language date parsing for Zig
//!
//! Supports: today, tomorrow, +3d, +2w, monday, YYYY-MM-DD, etc.

const std = @import("std");

// === Core Type ===
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,
};

// === Errors ===
pub const ParseError = error{
    InvalidFormat,
    InvalidDay,
    InvalidMonth,
    InvalidYear,
    InvalidOffset,
};

// === Public API ===
pub fn parse(date_str: []const u8) ParseError!?Date { ... }
pub fn today() Date { ... }
pub fn formatRelative(date: Date, reference: Date, buf: []u8) []const u8 { ... }
pub fn addDays(date: Date, days: i32) Date { ... }
pub fn addMonths(date: Date, months: i32) Date { ... }
pub fn daysBetween(from: Date, to: Date) i32 { ... }
pub fn daysUntil(date: Date) i32 { return daysBetween(today(), date); }

// === Internal Functions (private) ===
fn getCurrentDate() Date { ... }
fn dateToUnix(date: Date) i64 { ... }
fn unixToDate(timestamp: i64) Date { ... }
fn toLower(str: []const u8, buf: []u8) []const u8 { ... }
fn parseWeekday(name: []const u8) ?u8 { ... }
fn parseOffset(offset_str: []const u8, base: Date) ParseError!Date { ... }
fn parseAbsoluteDate(date_str: []const u8, base: Date) ParseError!Date { ... }
fn nextWeekday(from: Date, target_dow: u8) Date { ... }
fn dayOfWeek(date: Date) u8 { ... }
fn daysInMonth(year: u16, month: u8) u8 { ... }
fn isLeapYear(year: u16) bool { ... }
fn getMonthAbbrev(month: u8) []const u8 { ... }

// === Tests (inline) ===
test "parse handles 'today'" { ... }
// ... all existing tests
```

## Consumer Integration

After extraction, the todo app becomes a consumer:

**todo/build.zig.zon:**
```zig
.dependencies = .{
    .kairoz = .{
        .url = "git+https://github.com/<username>/kairoz",
        .hash = "...",
    },
},
```

**todo/build.zig:**
```zig
const kairoz_dep = b.dependency("kairoz", .{});
exe.root_module.addImport("kairoz", kairoz_dep.module("kairoz"));
```

**todo/src/task.zig:**
```zig
const kairoz = @import("kairoz");
pub const Date = kairoz.Date;
```

**todo/src/date.zig:** Deleted (functionality now in Kairoz)

## Publishing

**Initial setup:**
```bash
cd ~/projects/Kairoz
zig init -m
# Edit build.zig.zon, delete fingerprint, run zig build to regenerate
```

**Release process:**
1. `git tag v0.1.0`
2. `git push origin v0.1.0`
3. Users: `zig fetch --save git+https://github.com/<username>/kairoz#v0.1.0`

## Gap Analysis (Future Work)

Features to add in future versions:

| Feature | Version | Priority |
|---------|---------|----------|
| Month names (jan 15, january 15) | v0.2.0 | High |
| Negative offsets (-3d, -2w) | v0.2.0 | High |
| End-of-period (eow, eom) | v0.2.0 | Medium |
| "3 days ago" patterns | v0.3.0 | Medium |
| "in 3 days" patterns | v0.3.0 | Medium |
| last/this weekday distinction | v0.3.0 | Medium |
