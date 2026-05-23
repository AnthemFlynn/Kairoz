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

**Minimum Zig version: 0.16.0 stable** (cross-platform: POSIX + Windows)

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
zig build              # Build the library module
zig build test         # Run all tests
```

This is a library-only project — there is no CLI executable or `zig build run` step.

## Architecture

The project ships a single Zig module for consumers:

- **`src/root.zig`** — Public API surface, re-exporting from the modules below.
- **`src/Date.zig`** — `Date` struct, validation, leap-year/days-in-month helpers, `today()`.
- **`src/parse.zig`** — Natural-language parsing, `ParsedDate`, `Period`, `Granularity`.
- **`src/arithmetic.zig`** — `addDays`/`addMonths`/`addYears`, week and month boundaries.
- **`src/format.zig`** — `formatRelative` for human-readable output.

The build system (`build.zig`) registers one module named `"Kairoz"` and wires up a single test step that runs every test in `src/root.zig` and its transitive imports.

## Consumer Integration

Downstream projects add Kairoz via:

**build.zig.zon:**
```zig
.dependencies = .{
    .Kairoz = .{
        .url = "git+https://github.com/AnthemFlynn/Kairoz",
        .hash = "...",
    },
},
```

**build.zig:**
```zig
const kairoz_dep = b.dependency("Kairoz", .{});
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
