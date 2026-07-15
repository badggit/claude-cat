# Claude Cat

A tiny macOS menu-bar cat that gets fatter as Claude Code burns tokens during
the day — and slims back down every morning. It can also step out of the menu
bar and live as a larger creature right on your desktop, and you can swap the
**cat** for a **bunny**, **bird**, **flower**, or **pig**.

- **Zero dependencies.** Pure Swift + system frameworks. No Electron, no npm,
  no telemetry, no network calls at all.
- **No persistence.** Everything lives in memory; the transcripts Claude Code
  already writes are the only data source. The single file the app ever
  creates is the optional launch-at-login plist.
- **Local only.** Token usage is parsed from `~/.claude/projects/**/*.jsonl`
  on your machine.

<img width="145" height="130" alt="claude-cat 1" src="https://github.com/user-attachments/assets/d852a417-7378-41a9-9030-e1cd5c9c3b09" />
<img width="151" height="145" alt="claude-cat 2" src="https://github.com/user-attachments/assets/93995474-dcd3-4d47-8fd3-a0aed7339f77" />
<img width="166" height="108" alt="claude-cat 3" src="https://github.com/user-attachments/assets/d7971b7d-b52a-4aaf-886f-5f9b45096b77" />

## How it works

The cat's size reflects **effective tokens** spent since 05:00 local time:
a weighted sum mirroring API price ratios (input ×1, output ×5,
cache read ×0.1, cache creation ×1.25). Six stages from Kitten to Balloon;
animation speed follows the current tokens-per-minute rate, the cat falls
asleep after 5 idle minutes, and looks confused when transcripts cannot be
parsed. Click the cat for exact numbers (totals, per-model breakdown, rate),
a manual **Refresh Now**, the **Animal** and **Display** sections below, and a
Launch-at-Login toggle.

### Where it lives, and which animal

The pet can appear in two places, toggled from the menu's **Display** section:

- **Show in Menu Bar** — the classic 16×16 creature next to the clock.
- **Show on Screen** — a larger 64×64 creature in a small borderless window
  that floats on the desktop. Drag it anywhere (its position is remembered),
  and it reacts to hover, jumps on token spikes, sleeps when idle, and shows a
  desaturated "broken" pose when tracking fails.

Run either surface or both — the app guarantees at least one always stays on.
The menu's **Animal** section picks the creature both surfaces share: **Cat**
(default), **Bunny**, **Bird**, **Flower**, or **Pig**. Every animal is drawn
for all six growth stages, the idle animation, and the broken pose.

A companion CLI ships alongside the app:

```sh
claude-cat today          # today's usage snapshot (--json available)
claude-cat calibrate      # per-day totals for the last week
claude-cat watch          # live snapshot every poll tick
```

## Requirements

- macOS 13 (Ventura) or newer.
- Swift 5.9+ toolchain.

## Dependencies

**None.** `Package.swift` declares no `.package(...)` entries, so there is no
`Package.resolved`, nothing is fetched at build time, and no third-party code
is linked into either binary. Everything the app uses ships with the platform:

| Framework | Used by |
|---|---|
| Foundation | every target |
| AppKit | the menu-bar app and desktop pet |
| CoreGraphics | illustrated-cat rendering and pet geometry |
| CoreVideo | the display link driving cat animation |
| XCTest, ImageIO, UniformTypeIdentifiers | tests only |

The pixel-art generator under `tools/art/` is a development tool, not a build
step: it is Python 3 using only the standard library (`argparse`, `copy`,
`math`, `os`, `struct`, `sys`, `tempfile`, `zlib`), and it encodes PNGs by hand
rather than depending on an imaging package. You do not need Python to build or
run the app.

The only third-party code in the repository is the `actions/checkout` step in
the CI workflow, which never reaches the binaries.

## Installing Swift

Swift ships with the Xcode Command Line Tools — the full Xcode app is not
required:

```sh
xcode-select --install
swift --version   # expect 5.9 or newer
```

If the bundled Swift is older than 5.9, install a newer toolchain via
[swiftly](https://www.swift.org/install/macos/):

```sh
curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
~/.swiftly/bin/swiftly init
swiftly install latest
```

## Build and install

```sh
git clone <repo-url> claude-cat
cd claude-cat
swift build -c release
```

Copy the binaries to a stable location — **do not run the app long-term from
`.build/release/`** (rebuilds wipe it, and the Launch-at-Login toggle refuses
that path):

```sh
mkdir -p ~/bin
cp .build/release/claude-cat-app ~/bin/
cp .build/release/claude-cat ~/bin/
```

## Run

```sh
~/bin/claude-cat-app
```

The cat appears in the menu bar (no Dock icon). Quit it from the cat's menu.
To start it automatically at login, use the "Launch at Login" toggle in the
menu.

### Overriding the transcripts folder

```sh
CLAUDE_CAT_PROJECTS_DIR=/path/to/projects ~/bin/claude-cat-app
```

The Launch-at-Login toggle captures this variable when set, so the
auto-started app watches the same folder.

## Development

The core (parsing, aggregation, stages) is platform-independent and fully
unit-tested; the test suite runs on Linux too:

```sh
swift test
```

The AppKit layer is guarded by `#if os(macOS)` and compiles to a stub
elsewhere.
