# Usage Tracking Pipeline

## Overview

Claude Cat is a Swift Package Manager package with a cross-platform core,
a command-line executable, and a macOS menu-bar executable. The core converts
locally stored Claude Code transcript lines into an in-memory daily snapshot;
neither the tracker nor the CLI persists usage state.

## Where it lives

- `Package.swift:3` declares `ClaudeCatCore`, `ClaudeCatCLI`, and `ClaudeCatApp`.
- `Sources/ClaudeCatCore/TodayTracker.swift:19` coordinates live scanning and aggregation.
- `Sources/ClaudeCatCLI/main.swift:30` wires the CLI to the core.
- `Sources/ClaudeCatApp/StatusItemController.swift:14` owns the menu-bar status item.

## How it works

1. `TodayTracker.refresh(now:)` calculates the current logical-day start with
   `LogicalDayCalculator`.
2. `ProjectsScanner.candidateFiles` finds recent `.jsonl` files below the
   configured transcript root.
3. `IncrementalLineReader` reads only complete new lines and detects
   truncation or atomic replacement by offset and file identity.
4. `TranscriptLineParser` produces `UsageEvent` values. `UsageAccumulator`
   filters them to the current logical day, deduplicates keyed events, and
   aggregates token counts by model family.
5. `TodayTracker` returns `DailyUsageSnapshot`, including effective tokens,
   stage, rate, idle state, and parser diagnostics.

The AppKit layer confines one `TodayTracker` instance to a private serial
`DispatchQueue`; immutable snapshots are then applied on the main thread.

## Constraints and gotchas

- The logical day starts at the configured rollover hour rather than at
  midnight.
- A file reset triggers a full in-memory rebuild for the day, preventing
  re-ingestion of keyless events from corrupting totals.
- `TodayTracker` is intentionally not thread-safe; callers must serialize
  `refresh(now:)` calls.

## Related

- [Runtime Configuration](./config-runtime-configuration.md)
- [Core Test Suite](./testing-core-test-suite.md)
