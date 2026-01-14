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

**Target features (v0.1.0):**
- Relative dates: today, tomorrow, yesterday
- Weekday names: monday, mon, tuesday, tue, etc.
- Forward offsets: +3d, +2w, +1m
- Special values: next week, next month, none, clear
- Absolute formats: YYYY-MM-DD, MM-DD, DD
- Date arithmetic utilities
- Relative formatting for display

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

See `docs/plans/2026-01-13-kairoz-library-design.md` for the full API design, including:
- Public API specification
- Error types
- Internal function signatures
- Future version roadmap
