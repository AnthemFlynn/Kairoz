# Contributing to Kairoz

## Development Setup

### Requirements

- Zig 0.16.0+ (nightly recommended)
- Git

### Getting Started

```bash
git clone https://github.com/AnthemFlynn/Kairoz.git
cd Kairoz
zig build test
```

## Project Structure

```
Kairoz/
├── build.zig           # Build configuration
├── build.zig.zon       # Package manifest
├── src/
│   ├── root.zig        # Public API exports
│   ├── Date.zig        # Date type and epoch conversion
│   ├── parse.zig       # Natural language parsing
│   ├── arithmetic.zig  # Date arithmetic (add days/months)
│   └── format.zig      # Relative formatting
└── docs/
    └── plans/          # Design documents
```

### Module Responsibilities

| Module | Purpose |
|--------|---------|
| `root.zig` | Public API surface — re-exports from other modules |
| `Date.zig` | Core `Date` struct, validation, epoch day conversion |
| `parse.zig` | Input parsing (keywords, offsets, absolute dates) |
| `arithmetic.zig` | `addDays`, `addMonths`, `daysBetween` |
| `format.zig` | `formatRelative` for human-readable output |

## Commands

```bash
zig build              # Build the library
zig build test         # Run all tests
zig build run          # Run CLI demo (if applicable)
```

## Testing

All code changes should include tests. Tests live alongside implementation in each module.

```bash
# Run all tests
zig build test

# Run tests for a specific file during development
zig test src/parse.zig
```

### Test Style

- One behavior per test
- Descriptive test names: `test "addMonths clamps day for short months"`
- Test edge cases: boundaries, invalid input, overflow conditions

## Code Style

### General Principles

- **Zero dependencies** — stdlib only
- **Explicit over implicit** — clear error handling, no hidden allocations
- **Test-driven** — write failing test first

### Naming

- Types: `PascalCase` (`Date`, `ParsedDate`)
- Functions: `camelCase` (`parseWithReference`, `addMonths`)
- Constants: `snake_case` (`max_format_len`)

### Error Handling

Return errors explicitly. Use error unions, not optionals, for operations that can fail:

```zig
// Good
pub fn addMonths(date: Date, months: i32) ArithmeticError!Date

// Avoid
pub fn addMonths(date: Date, months: i32) ?Date
```

### Documentation

Public functions should have doc comments:

```zig
/// Parse date string with explicit reference date.
/// Returns `ParsedDate.clear` for "none" or "clear" inputs.
pub fn parseWithReference(str: []const u8, reference: Date) !ParsedDate
```

## Making Changes

1. **Fork and clone** the repository
2. **Create a branch** for your change: `git checkout -b feature/my-change`
3. **Write a failing test** for the new behavior
4. **Implement** the minimum code to pass
5. **Run all tests**: `zig build test`
6. **Commit** with a descriptive message
7. **Open a PR** against `main`

### Commit Messages

Use conventional commits:

```
feat: add support for "next week" keyword
fix: handle negative month overflow in addMonths
docs: clarify parseWithReference error behavior
test: add edge case for leap year boundary
```

## Design Decisions

Key architectural choices documented in `docs/plans/`:

- **Epoch day conversion** — Uses Howard Hinnant's algorithms for date math
- **ParsedDate union** — Distinguishes between actual dates and "clear" intent
- **Error types** — Separate `DateError`, `ParseError`, `ArithmeticError` for precise handling
- **No allocations** — All operations use stack memory or caller-provided buffers

## Questions?

Open an issue for questions or discussion about potential changes.
