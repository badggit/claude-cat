# Core Test Suite

## Overview

The cross-platform core is tested with XCTest in a single SwiftPM test target.
The current suite contains 85 test methods and covers the parsing and
aggregation behavior without requiring AppKit.

## Where it lives

- `Tests/ClaudeCatCoreTests/` contains all XCTest suites.
- `Tests/ClaudeCatCoreTests/TestFixtures.swift:4` holds inline JSONL fixtures.
- `Package.swift:21` declares the `ClaudeCatCoreTests` target.

## How to use it

Run the complete suite from the repository root:

```sh
swift test
```

Test files are organized by core module. They cover token weights and model
families, logical-day boundaries, line-reader resets, transcript parsing,
scanner filtering, daily accumulation, tracker rollover, history aggregation,
CLI formatting, and launch-agent plist generation.

## Constraints and gotchas

- Fixtures are inline strings rather than resource bundles, keeping tests
  portable to Linux.
- The AppKit target is guarded by `#if os(macOS)` and has no unit-test target;
  its visual behavior requires manual macOS verification.
- Time-sensitive tests construct calendars with explicit time zones instead
  of relying on the machine default.

## Related

- [Usage Tracking Pipeline](./architecture-usage-tracking-pipeline.md)
