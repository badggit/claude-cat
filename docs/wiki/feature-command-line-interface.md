# Command-Line Interface

## Overview

The `claude-cat` executable provides cross-platform access to the same core
usage logic as the menu-bar app. Argument parsing and output formatting live
in the core module so they can be unit tested.

## Where it lives

- `Sources/ClaudeCatCLI/main.swift:30` dispatches commands.
- `Sources/ClaudeCatCore/CLISupport.swift:3` defines commands, parsing, and
  formatting.
- `Sources/ClaudeCatCore/HistoryAggregator.swift:17` implements historical
  totals for calibration.

## How to use it

```sh
claude-cat today
claude-cat today --json
claude-cat calibrate
claude-cat calibrate --days 3
claude-cat watch
```

- `today` prints the current `DailyUsageSnapshot`; `--json` emits one JSON
  object.
- `calibrate` prints daily effective and raw token totals. It defaults to the
  last seven days.
- `watch` keeps one tracker alive and prints a compact snapshot after every
  configured polling interval.

Unknown commands and invalid arguments write usage text to standard error and
exit with status 2.

## Constraints and gotchas

- `watch` runs until interrupted.
- Calibration performs a full read of candidate transcript files; it is not
  the incremental path used by `today` and the menu-bar app.

## Related

- [Runtime Configuration](./config-runtime-configuration.md)
- [Usage Tracking Pipeline](./architecture-usage-tracking-pipeline.md)
