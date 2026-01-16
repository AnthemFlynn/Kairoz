# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Skills

Use the `/zig` skill for Zig development tasks. Additional Zig skills available:
- `/zig-doctor` — Diagnose toolchain health and configuration
- `/zig-setup` — First-time Zig toolchain setup with ZVM and ZLS
- `/zig-update` — Update Zig and ZLS to latest nightly
- `/zig-add` — Add a dependency to build.zig.zon

## Project Overview

Kairoz (from καιρός — "the opportune moment") is a natural language date parsing library for Zig. Zero dependencies, stdlib only.

**Current version: v0.2.1**

**Minimum Zig version: 0.16.0** (uses `std.posix.gettimeofday`)

**Features:**
- Relative dates: `today`, `tomorrow`, `yesterday` (aliases: `tdy`, `tom`, `yest`)
- Weekday names: `monday`, `mon`, `next monday`, `last friday`
- Forward/backward offsets: `+3d`, `-2w`, `+1m`, `-1y` (or unitless: `+3`, `-2`)
- Natural offsets: `in 3 days`, `2 weeks ago`
- Period references: `next week`, `this month`, `last year` (return `Period`)
- Boundary expressions: `end of month`, `beginning of week`
- Month names: `february`, `dec` (return `Period`)
- Ordinal days: `1st`, `23rd`
- Clear values: `none`, `clear`
- Absolute formats: `YYYY-MM-DD`, `MM-DD`, `DD`, `2024` (bare year)
- Date arithmetic: add days/months/years, week/month boundaries
- Relative formatting for display

**Key concept:** `ParsedDate` has three variants:
- `.date` — specific date (e.g., "tomorrow")
- `.period` — time span with granularity (e.g., "next month")
- `.clear` — unset intent (e.g., "none")

## Build Commands

```bash
zig build              # Build the project
zig build run          # Run the CLI executable
zig build test         # Run all tests (library + executable)
```

## Architecture

The project exposes a Zig module for consumers and an optional CLI executable:

- **`src/root.zig`** — Library module exposed as "Kairoz" to package consumers. Contains the public API for date parsing and manipulation.
- **`src/main.zig`** — CLI executable that imports and uses the Kairoz module. For demonstrating/testing the library.

The build system (`build.zig`) sets up:
1. A public module "Kairoz" from `src/root.zig` for library consumers
2. An executable that imports this module for CLI usage
3. Separate test runners for both the module and executable

## Consumer Integration

Downstream projects add Kairoz via:

**build.zig.zon:**
```zig
.dependencies = .{
    .kairoz = .{
        .url = "git+https://github.com/<username>/kairoz",
        .hash = "...",
    },
},
```

**build.zig:**
```zig
const kairoz_dep = b.dependency("kairoz", .{});
exe.root_module.addImport("kairoz", kairoz_dep.module("Kairoz"));
```

## Design Reference

See `docs/plans/` for design documents:
- `2026-01-13-kairoz-library-design.md` — Original v0.1.0 API design
- `2026-01-13-kairoz-v0.2.0-design.md` — Period semantics and expanded parsing

Key documentation:
- Public API specification
- Error types (`DateError`, `ParseError`, `ArithmeticError`)
- `Period` struct with `start`, `granularity`, and `end()` method
- `Granularity` enum: `.day`, `.week`, `.month`, `.year`
