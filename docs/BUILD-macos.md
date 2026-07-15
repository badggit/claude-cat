# Building on macOS

## Prerequisites

- macOS 13 (Ventura) or newer (the package sets `.macOS(.v13)`).

## Installing Swift

On macOS the Swift toolchain ships with the Xcode Command Line Tools — the
full Xcode app is NOT required.

1. Install the Command Line Tools (a dialog opens; confirm and wait):

   ```sh
   xcode-select --install
   ```

   If it prints "already installed", you are done with this step. To check
   what is active:

   ```sh
   xcode-select -p        # expected: /Library/Developer/CommandLineTools (or an Xcode path)
   ```

2. Verify the Swift version — 5.9 or newer is required:

   ```sh
   swift --version
   ```

   The first run may take a minute while macOS finishes setting up the tools.

3. Only if the bundled Swift is older than 5.9 (very old CLT), install a
   newer toolchain via [swiftly](https://www.swift.org/install/macos/), the
   official toolchain manager:

   ```sh
   curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
   installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
   ~/.swiftly/bin/swiftly init
   swiftly install latest
   ```

   Then restart the terminal and re-check `swift --version`.

## Get the sources

Clone the repository (or copy the project folder) onto the Mac:

```sh
git clone <repo-url> claude-cat
cd claude-cat
```

## Build

```sh
swift build -c release
```

This produces two binaries under `.build/release/`:

- `claude-cat-app` — the menu-bar cat app.
- `claude-cat` — the companion CLI.

## Install to a stable location

**NEVER run the app long-term from `.build/release/`** — that directory is
wiped by rebuilds, and the Launch-at-Login toggle refuses a `.build` path.
Copy both binaries to a stable home instead:

```sh
mkdir -p ~/bin
cp .build/release/claude-cat-app ~/bin/
cp .build/release/claude-cat ~/bin/
```

## Run

```sh
~/bin/claude-cat-app
```

The cat appears in the menu bar (no Dock icon — the app uses the accessory
activation policy). It reads transcripts from `~/.claude/projects` by default.

### Overriding the transcripts folder

Set `CLAUDE_CAT_PROJECTS_DIR` to point the app (and the CLI) at a different
Claude projects directory:

```sh
CLAUDE_CAT_PROJECTS_DIR=/path/to/projects ~/bin/claude-cat-app
```

## Quitting

Click the cat in the menu bar and choose **Quit**. If the app is running
without a visible status item, stop it from a terminal:

```sh
pkill claude-cat-app
```
