# Claude Cat — Project Wiki

A curated knowledge base for this repository. Each article documents a durable
piece of the system — architecture, workflows, integrations, conventions —
discovered while working on the codebase. Transient task notes, in-flight bugs,
and PR-specific context do not belong here.

> Wiki content is treated as public. Never commit secrets, credentials,
> customer data, or internal hostnames into these files.

Last updated: 2026-07-15

## How to use this wiki

- Browse the **Documentation files** section below to find a topic.
- Each article is self-contained; read articles, not the whole wiki.
- File names use a category prefix (`architecture-`, `feature-`, `api-`, etc.)
  so related articles cluster together alphabetically.

## Documentation files

### Architecture

- [**Usage Tracking Pipeline**](./architecture-usage-tracking-pipeline.md) — The three-target Swift package and the transcript-to-snapshot data flow.

### Features

- [**Command-Line Interface**](./feature-command-line-interface.md) — The `today`, `calibrate`, and `watch` commands provided by `claude-cat`.
- [**Desktop Pet**](./feature-desktop-pet.md) — The 64x64 desktop-pet display layer, the ClaudeCatPet module boundary, persistence keys, and the art pipeline.

### Conventions

- [**Swift Coding Rules**](./conventions-swift-coding-rules.md) — Project-grounded Swift cheat sheet: module/platform boundaries, main-thread & timer discipline, enum-modeled outcomes, deterministic rendering, Core Graphics, and testing rules that keep the code Linux-buildable and crash-free.

### Configuration

- [**Runtime Configuration**](./config-runtime-configuration.md) — Logical-day, polling, stage, and transcript-directory settings.

### Testing

- [**Core Test Suite**](./testing-core-test-suite.md) — XCTest layout, fixture conventions, and the covered core behaviors.
