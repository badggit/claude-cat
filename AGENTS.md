# Claude Cat Agent Instructions

## Project Context

- Project name: `Claude Cat`
- Goal: A zero-dependency macOS pet whose size and animation reflect Claude
  Code token usage parsed from local transcript files. It renders as a menu-bar
  creature, an optional on-screen desktop pet, or both, and the user can pick
  which animal (cat, bunny, bird, flower, or pig) both surfaces display.
- Primary repository: this repository root.
- Related repositories or services: none. The runtime reads local Claude Code
  transcripts; it makes no network requests.
- Runtime environments: Linux for core and CLI development; macOS 13+ for the
  AppKit menu-bar application and release build.
- Access policy: transcript files are read-only input. At runtime the only
  intentional application write is the optional LaunchAgent plist used by
  Launch at Login.
- Decision sources: `docs/wiki/README.md`, its relevant articles, and
  `docs/BUILD-macos.md` for the macOS build and installation procedure.

When local implementation choices are unclear, follow the relevant wiki
article and existing source patterns before proposing a new design.

## Session Initialization

At the start of each session:

1. Read `AGENTS.md`.
2. Read `docs/wiki/README.md`.
3. Read only the full wiki articles that are relevant to the current task.
4. Before coding, inspect `Package.swift` and the relevant source and test
   patterns. This is a Swift project with no external packages and no tracked
   formatter or linter configuration.

## Coding Rules

- All code, identifiers, filenames, and comments are English.
- Add explanatory comments only for intent, business rules, or non-obvious edge
  cases. Avoid comments that merely repeat function names or obvious logic. Use
  a single `//` comment immediately before a function only when the name does
  not fully capture what it does.
- Do not leave spaces on completely empty lines.
- Make code modular enough that a feature can be removed, moved, or extracted
  without unnecessary coupling.
- Keep configurable constants, limits, defaults, and thresholds in
  `ClaudeCatConfig` rather than scattering them across call sites.
- Follow existing import order, filename casing, and test conventions.
- Never hand-edit generated files. Update the generator, source data, or the
  documented generation command instead.

## Dependencies

- This project is deliberately dependency-free: Foundation and AppKit only.
- Do not introduce a network API, telemetry, external database, or third-party
  dependency without explicit approval.

## Testing And Verification

- Let test coverage scale with risk and blast radius.
- Add or update focused tests for behavioral changes, shared contracts, edge
  cases, and bug fixes.
- Run relevant tests at task completion when practical.
- If tests cannot be run, state what was skipped and why.

## Claude Cat Project Guide

### Product Behavior

- The cat represents effective tokens accumulated during a local logical day.
  The logical day runs from 05:00 to 05:00 in the injected local calendar.
- Effective tokens are a weighted sum: input ×1, output ×5, cache read ×0.1,
  and cache creation ×1.25. This is an activity metric, not a currency value.
- Six stages are derived from five configurable thresholds. The default
  thresholds live only in `Sources/ClaudeCatCore/ClaudeCatConfig.swift`.
- The cat animates faster at higher tokens-per-minute rates, sleeps after five
  idle minutes, and must visibly degrade when transcript input is unavailable
  or diagnostics indicate unreliable data.
- The same usage data drives two detachable display surfaces: the 16x16
  menu-bar creature and an optional 64x64 on-screen desktop pet in a borderless
  window. The menu's Display section toggles each; `DisplayTogglePolicy`
  guarantees at least one surface is always enabled. The on-screen pet is
  draggable (its position persists), reacts to hover, jumps on token spikes,
  sleeps when idle, and shows a desaturated broken pose when tracking fails.
- The menu's Animal section selects the creature both surfaces share (cat,
  bunny, bird, flower, pig) via a shared `selectedCreatureID`. Every creature
  is drawn for all six growth stages plus idle and broken states.
- The menu and CLI use English user-facing strings.

### Stack And Package Layout

- Swift tools version 5.9; Foundation and AppKit only; no external packages.
- Swift Package Manager defines four library and executable targets (plus the
  `ClaudeCatCoreTests` and `ClaudeCatPetTests` test targets):
  - `ClaudeCatCore`: cross-platform parsing, aggregation, configuration,
    history, and CLI formatting. It must not import AppKit.
  - `ClaudeCatPet`: pure-logic desktop-pet support — state machine, geometry,
    palette, art model/validator, and generated 64x64 art under
    `Sources/ClaudeCatPet/Art/`. It depends on `ClaudeCatCore`, imports no
    AppKit, and is fully unit-testable on Linux.
  - `ClaudeCatCLI`: the `claude-cat` executable. Keep it thin; business logic
    belongs in the core target so it stays testable.
  - `ClaudeCatApp`: the `claude-cat-app` AppKit executable. It depends on
    `ClaudeCatCore` and `ClaudeCatPet` and owns the AppKit-only rendering and
    window code (`PetWindowController`, `PetSpriteRenderer`,
    `PetSpikeController`). All macOS code is guarded by `#if os(macOS)` so
    Linux builds retain a small stub path.
- Keep core types value-oriented and platform-independent. UI code renders
  `DailyUsageSnapshot` values rather than reimplementing aggregation logic.

### Transcript Data Pipeline

1. The default transcript root is `~/.claude/projects`; the
   `CLAUDE_CAT_PROJECTS_DIR` environment variable overrides it.
2. `ProjectsScanner` finds recent `.jsonl` files. `IncrementalLineReader`
   tracks byte offsets and file identity, consumes only complete lines, and
   detects truncation or atomic replacement.
3. `TranscriptLineParser` classifies each line as an event, irrelevant line,
   assistant record without usable usage, or malformed input.
4. `UsageAccumulator` filters events to the current logical day, deduplicates
   keyed events, aggregates raw counts by model family, and maintains the
   short rate window.
5. `TodayTracker.refresh(now:)` orchestrates the pipeline and returns
   `DailyUsageSnapshot` with totals, stage, rate, idle state, and diagnostics.

Data integrity requirements:

- Preserve the distinction between irrelevant lines, malformed lines, and
  assistant records without usable usage. Format drift must become visible in
  diagnostics rather than silently undercounting usage.
- If a read position resets, rebuild the complete logical day. Deduplication
  does not protect events that have no deduplication key.
- `TodayTracker` is deliberately not thread-safe. `StatusItemController`
  owns one tracker on a private serial `DispatchQueue`; only immutable
  snapshots may cross to the main thread.

### CLI And App Behavior

- `claude-cat today` prints the current snapshot; `today --json` emits JSON.
- `claude-cat calibrate [--days N]` prints daily totals for threshold
  calibration. It is a full historical read, not an incremental sweep.
- `claude-cat watch` prints one compact snapshot per polling interval until
  interrupted.
- The macOS app is an accessory application with no Dock icon. Its status
  menu shows totals, token breakdown, model data, rate, update time,
  diagnostics, Refresh Now, the Animal picker, the Display toggles (Show in
  Menu Bar / Show on Screen), Launch at Login, and Quit.
- `UsageEngine` owns the tracker and shared menu and pushes each snapshot to
  whichever display layers are attached: `StatusItemController` (menu bar) and
  `PetWindowController` (on-screen pet). Neither the tracker nor the poll timer
  depends on which layers are enabled.
- Menu-bar pixel-art frames are code-generated `NSImage` values. Keep them
  template images so the menu bar supports light and dark themes. The 64x64
  on-screen art is generated separately by the `tools/art` pipeline into
  `Sources/ClaudeCatPet/Art/`; regenerate it with `python3 tools/art/pet_art.py
  emit`, never hand-edit the generated Swift.
- Launch at Login writes
  `~/Library/LaunchAgents/com.claudecat.app.plist`. It must use
  `RunAtLoad = true` and `KeepAlive = false`, reject executables inside
  `/.build/`, and preserve a non-empty `CLAUDE_CAT_PROJECTS_DIR` in the plist.

### Configuration And Persistence

- `ClaudeCatConfig` is the sole home for configurable defaults: transcript
  root, rollover hour, polling, rate window, idle threshold, token weights,
  growth thresholds, and suspicious-skip threshold.
- Do not add persistent usage state. Transcripts are the source of truth and
  the tracker rebuilds state in memory after a process restart or rollover.

### Build, Test, And macOS Verification

- Linux: run `swift build` and `swift test` from the repository root for source
  changes. Core tests use XCTest and inline JSONL fixtures.
- macOS: follow `docs/BUILD-macos.md`. Build with
  `swift build -c release`, then copy both binaries from `.build/release/` to
  `~/bin/` before running or enabling Launch at Login.
- Do not treat a Linux build as proof that AppKit behavior works. Manually
  verify the status item, menu values, animation, sleep and confused states,
  Quit, Launch at Login, and a strict-concurrency macOS build when AppKit or
  concurrency code changes.
- Add or update focused XCTest coverage for core behavior, transcript-format
  changes, day boundaries, file resets, and CLI contracts.

### Documentation

- The wiki under `docs/wiki/` is durable project documentation. Read its index
  first and open only task-relevant articles:
  - `architecture-usage-tracking-pipeline.md`
  - `config-runtime-configuration.md`
  - `feature-command-line-interface.md`
  - `feature-desktop-pet.md`
  - `testing-core-test-suite.md`
  - `testing-desktop-pet-macos-checklist.md`
- Update the wiki after a significant, durable discovery or architecture
  change. Keep wiki content public-safe and in English: never commit secrets,
  credentials, or personal data.
