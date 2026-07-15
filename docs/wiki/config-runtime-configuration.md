# Runtime Configuration

## Overview

`ClaudeCatConfig` centralizes the runtime values that control transcript
discovery, logical-day boundaries, aggregation, and animation behavior.
The default configuration is created by `ClaudeCatConfig.standard`.

## Where it lives

- `Sources/ClaudeCatCore/ClaudeCatConfig.swift:3` defines the configuration.
- `Sources/ClaudeCatCore/UsageModels.swift:33` defines `TokenWeights`.
- `Sources/ClaudeCatApp/LoginItemManager.swift:38` captures the transcript
  override for the login launch agent.

## How to use it

The default settings are:

- logical-day rollover: 05:00 local time;
- polling interval: 5 seconds — the app layer re-arms the poll from each
  refresh's completion, so the effective cadence is (refresh duration + 5s)
  rather than a fixed 5-second period;
- rate window: 300 seconds; idle-after window: 30 seconds (the cat switches to
  "resting" 30 seconds after the last usage event);
- effective-token weights: input ×1, output ×5, cache read ×0.1, cache
  creation ×1.25;
- stage thresholds: 1M, 3M, 8M, 16M, and 28M effective tokens.

Set `CLAUDE_CAT_PROJECTS_DIR` to use a transcript directory other than the
default `~/.claude/projects`:

```sh
CLAUDE_CAT_PROJECTS_DIR=/path/to/projects claude-cat today
```

When Launch at Login is enabled, the app includes this non-empty environment
variable in its generated plist so the launch agent reads the same directory.

## Constraints and gotchas

- Token weights and thresholds are ordinary configuration values; the code
  does not derive monetary cost.
- The login plist is the only intentional on-disk write performed by the app.
- A missing transcript directory produces a diagnostic snapshot rather than
  an exception.

## Related

- [Usage Tracking Pipeline](./architecture-usage-tracking-pipeline.md)
- [Command-Line Interface](./feature-command-line-interface.md)
