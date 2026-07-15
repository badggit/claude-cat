# Testing — Desktop Pet macOS Checklist

A manual acceptance procedure for the desktop-pet overlay window and its two
rendering paths. The original Phase-0 spike procedure remains below because
its window-level, Spaces, focus, hit-testing, and recording premises still
apply to the shipped panel. The current illustrated-cat acceptance matrix is
the final section of this article and supersedes older references to the cat
as a two-frame pixel sprite or jumping animation.

Linux can exercise platform-neutral planner, catalog, routing, and lifecycle
contracts, but a Linux build or test pass is not evidence that AppKit, Core
Graphics, Core Video, window focus, visual quality, or macOS energy behavior
works. Those items require the real-Mac checks marked `[JUDGMENT]` or
`[INSTRUMENTED]` below.

**Who consumes the result:** the overlay window's shipped level and collection
behavior are gated on the record this checklist produces. Until a verified
combo is recorded, the pet must not be released or installed for daily use.

## What the spike is

`claude-cat-app --pet-spike` starts a spike mode instead of the normal app:
a single borderless, non-activating, transparent-background panel whose
content is a 96 pt gray square centered in a 128 pt frame. The 16 pt margin
around the square is fully transparent on purpose — it exists to test
hit-testing and dragging over alpha-0 pixels. There is no usage tracker, no
menu bar item, and no timers.

Spike controls:

- **Left press + move** — drags the window (it follows the mouse).
- **Hover** — the square lightens (tracking-area test).
- **Left click without movement** — the square briefly flashes.
- **Right-click** — opens a test menu at the click point listing 12
  window-configuration combos (window level x collection behavior) plus a
  Quit item. Selecting a combo applies it live and prints its name to
  stdout, e.g. `Applied combo: .floating + [.canJoinAllSpaces,
  .fullScreenAuxiliary, .stationary]`.

The 12 combos are the levels `.floating`, `.statusBar`, `.popUpMenu`,
`.screenSaver` crossed with the collection-behavior sets:

- `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- `[.canJoinAllSpaces, .fullScreenAuxiliary]`
- `[.moveToActiveSpace, .fullScreenAuxiliary]`

## Prerequisites

- A real Mac with the Swift toolchain installed.
- Two displays connected (required for premise 2).
- A terminal kept visible during the run — the spike reports each applied
  combo on stdout, which is the record of what was active during each check.

Build and launch from the repository root:

```
swift build
.build/debug/claude-cat-app --pet-spike
```

The spike starts with the first combo applied (`.floating +
[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`) and prints it.

## Procedure

Run the five checks below. Premise 2 must be attempted per combo until a
passing combo is found; then re-verify premises 1, 3, 4, and 5 with that
winning combo applied and fill its row of the results table completely.

1. **Premise 1 — no focus steal.** Open a text editor (TextEdit is fine),
   place the cursor in a document, and start typing continuously. While
   typing, click the gray square several times and drag it around with the
   other hand. PASS if typing is never interrupted: no lost keystrokes, no
   beeps, the editor keeps keyboard focus, and its window stays frontmost in
   appearance (the square must not activate its own app).

2. **Premise 2 — two-display level/Spaces matrix.** Goal: find at least one
   combo under which the square shows over normal windows AND over a native
   fullscreen app on exactly one monitor — with "Displays have separate
   Spaces" both ON and OFF.
   1. Ensure System Settings > Desktop & Dock > Mission Control >
      "Displays have separate Spaces" is ON (log out and back in if you
      change it).
   2. For each combo (right-click the square, select the combo, confirm the
      stdout line): check the square sits above normal app windows; put an
      app (e.g. Safari) into native fullscreen on the monitor showing the
      square and verify the square remains visible over it; check the other
      monitor — the square must appear on exactly one monitor, not clone or
      leak onto the second display's Spaces.
   3. Turn "Displays have separate Spaces" OFF (log out and back in) and
      repeat step 2 for the candidate combos that passed.
   4. Record pass/fail per combo in the results table, in both the ON and
      OFF columns.

3. **Premise 3 — right-click menu z-order and dismissal.** With the current
   candidate combo applied (also try `.screenSaver` as the worst case),
   right-click the square. PASS if the test menu opens ABOVE the square
   (not hidden underneath it), highlights items normally, applies a
   selection, and dismisses correctly both on selection and on clicking
   elsewhere.

4. **Premise 4 — drag over the transparent margin.** Press on the
   transparent 16 pt margin just outside the gray square but inside the
   128 pt window frame, and drag. PASS if the window follows the mouse.
   FAIL if the press falls through to whatever window is underneath — note
   that outcome explicitly, it changes the pet window's hit-testing design.

5. **Premise 5 — screen recording visibility.** With the winning combo
   applied, start a screen recording (QuickTime Player > File > New Screen
   Recording) of the area containing the square, drag the square during the
   recording, stop, and play it back. PASS if the square is visible in the
   recording. A pet that is invisible to screen recording is an accepted
   degradation, not a blocker — record the outcome either way.

## Results table

Fill one cell per check: `pass`, `fail`, or `-` (not attempted). P2 must be
attempted for every combo until a pass is found; the winning combo's row
must be filled for all premises.

| Combo | P1 no focus steal | P2 Spaces ON | P2 Spaces OFF | P3 menu above | P4 margin drag | P5 recording |
|---|---|---|---|---|---|---|
| `.floating + [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | | | | | | |
| `.floating + [.canJoinAllSpaces, .fullScreenAuxiliary]` | | | | | | |
| `.floating + [.moveToActiveSpace, .fullScreenAuxiliary]` | | | | | | |
| `.statusBar + [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | | | | | | |
| `.statusBar + [.canJoinAllSpaces, .fullScreenAuxiliary]` | | | | | | |
| `.statusBar + [.moveToActiveSpace, .fullScreenAuxiliary]` | | | | | | |
| `.popUpMenu + [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | | | | | | |
| `.popUpMenu + [.canJoinAllSpaces, .fullScreenAuxiliary]` | | | | | | |
| `.popUpMenu + [.moveToActiveSpace, .fullScreenAuxiliary]` | | | | | | |
| `.screenSaver + [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | | | | | | |
| `.screenSaver + [.canJoinAllSpaces, .fullScreenAuxiliary]` | | | | | | |
| `.screenSaver + [.moveToActiveSpace, .fullScreenAuxiliary]` | | | | | | |

## Recording the result

After the run, record the verified window level + collection behavior combo,
with the date and the completed results table, in this article. That record is
what the shipped `PetWindowController` configuration must match. If every combo
fails any premise, do not proceed: the design returns for revision.

## Post-refactor regression — usage engine extraction

Deferred Mac items: the tracker, poll timer, shared menu and creature
selection moved from `StatusItemController` into `UsageEngine`
(the controller became a pure display layer). Linux cannot exercise any of
this AppKit behavior, so run the following on a real Mac with the normal app
(`.build/debug/claude-cat-app`, no `--pet-spike` flag):

- [ ] `[JUDGMENT]` The menu opens from the status item and shows a live countdown
      ("Next refresh in Ns") that ticks down once per second while the menu
      stays open, then resets after a refresh.
- [ ] `[JUDGMENT]` "Refresh Now" triggers an immediate refresh — the "Updated HH:mm:ss"
      row changes on the next menu open.
- [ ] `[JUDGMENT]` The "Animal" radio items switch the selected creature, the checkmark
      moves, and the menu bar icon repaints immediately (no wait for the
      next poll).
- [ ] `[JUDGMENT]` The creature choice persists across an app relaunch
      (`selectedCreatureID` in UserDefaults).
- [ ] `[JUDGMENT]` "Launch at Login" toggles its checkmark and the login-item plist state.
- [ ] `[JUDGMENT]` "Quit" exits the app and removes the status item.
- [ ] `[JUDGMENT]` While Claude is actively used, the status item animates and is tinted
      by the active model color, exactly as before the refactor.

## Display toggles — menu-bar/pet flags and layer lifecycle

Deferred Mac items: the menu has a Display section ("Show in Menu Bar" /
"Show on Screen") backed by `displayMenuBarEnabled` / `displayPetEnabled`
UserDefaults flags; the engine creates and destroys the menu-bar layer at
runtime. Run on a real Mac (`.build/debug/claude-cat-app`):

- [ ] `[JUDGMENT]` Toggle each display off and on in every order (menu bar off → on,
      pet off → on, alternate them, repeat several cycles) while watching
      the refresh cadence: exactly one transcript scan per 15 s throughout —
      the countdown keeps ticking from the same schedule, "Updated" advances
      once per interval, and no doubled/paused refreshes appear after any
      toggle sequence.
- [ ] `[JUDGMENT]` Turning "Show in Menu Bar" off removes the status item immediately;
      turning it back on restores it with the current creature and the
      latest usage state rendered at once (no wait for the next poll).
- [ ] `[JUDGMENT]` The last enabled display's menu item is checked but grayed out
      (disabled) and cannot be clicked off; enabling the other display
      re-enables it.
- [ ] `[JUDGMENT]` Both-off corrupted defaults force the menu bar back at launch: quit
      the app, run
      `defaults write <bundle-or-domain> displayMenuBarEnabled -bool NO` and
      `defaults write <bundle-or-domain> displayPetEnabled -bool NO`, then
      relaunch — the status item appears and `displayMenuBarEnabled` reads
      back as `1` (pet stays off).
- [ ] `[JUDGMENT]` Deleting both keys (fresh-user state) and relaunching leaves both
      toggles checked — missing keys default to ON.

## Pet window — overlay panel and position lifecycle

Deferred Mac items: `PetWindowController` backs "Show on Screen" with a
borderless, non-activating, transparent 128 pt panel. The window level and
collection behavior are PLACEHOLDER values (`.statusBar` +
`[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`) pending the Phase-0
spike record above. Run on a real Mac (`.build/debug/claude-cat-app`):

- [ ] `[JUDGMENT]` First launch (no `petPositionX`/`petPositionY` defaults): the pet
      appears at the bottom-right of the main screen's visible area with a
      24 pt margin, pixel-crisp (no blurry upscaling), and never steals
      keyboard focus from the active app.
- [ ] `[JUDGMENT]` The pet is visible over normal app windows AND over a native
      fullscreen app, on exactly one monitor (no clone/leak onto the second
      display) — re-verify with the real pet, with "Displays have separate
      Spaces" both ON and OFF (this repeats premise 2 with the shipped
      placeholder combo; a failure here means the placeholder must be
      replaced by the spike-verified record).
- [ ] `[JUDGMENT]` Set the position defaults (`defaults write <domain> petPositionX
      -float <x>` and `petPositionY`), relaunch: the pet reappears at that
      saved position — the position survives relaunch.
- [ ] `[JUDGMENT]` Move the pet's saved position onto a secondary monitor, unplug that
      monitor: the pet relocates onto the main screen (clamped inside its
      visible frame) without a relaunch.
- [ ] `[JUDGMENT]` Toggling "Show on Screen" off removes the pet window immediately;
      toggling it back on shows it again at the sanitized saved position
      with the current usage state rendered at once.
- [ ] `[JUDGMENT]` The pet's frame reflects usage state: sleeping frame while idle,
      jumping frame while Claude is actively used, broken frame when the
      transcripts folder is missing.

## Pixel-creature animator — energy budget

`PetAnimator` cycles frames only for bunny, bird, flower, and pig. Their jump
tempo tracks usage, sleeping animates slowly, and broken shows a still frame
with no timer. Every repeating timer carries a `>= 30%` tolerance, and
animation stops entirely (timers invalidated, not paused) when the pet is
occluded, the screen sleeps, or "Show on Screen" is toggled off. Run on a
real Mac (`.build/debug/claude-cat-app`):

- [ ] `[JUDGMENT]` While Claude is actively used the pet animates, and the jump tempo
      visibly rises as usage intensifies (faster frame cycling) and eases when
      it drops — mirroring the menu-bar icon's tempo.
- [ ] `[JUDGMENT]` When idle the pet's sleep animation is slow and calm (about one frame
      per 1.5 s), never frantic.
- [ ] `[JUDGMENT]` When the transcripts folder is missing the pet shows a still broken
      frame with no animation.
- [ ] `[INSTRUMENTED]` Leave the pet in the sleeping state for 5 minutes, then open Activity
      Monitor's Energy pane: the app shows near-zero CPU and near-zero
      "wake-ups" — the tolerance and slow interval let the OS coalesce ticks.
- [ ] `[INSTRUMENTED]` Fully cover the pet with another app's window on its Space (or send the
      pet's Space behind a native fullscreen window): the animation stops
      (no CPU) and resumes when the pet becomes visible again.
- [ ] `[INSTRUMENTED]` Lock the screen or let the display sleep: animation stops; unlocking or
      waking the display resumes it in the current usage state.
- [ ] `[INSTRUMENTED]` Toggle "Show on Screen" off: the animation timers stop with the window;
      toggling it back on resumes animation immediately.

## Pet mouse interaction and shared menu popup

Deferred Mac items: `PetInteractionView` overlays the pet with a
transparent event surface that handles drag, click, hover, and right-click.
It accepts the first click without activating the app, distinguishes a click
from a drag with a 3 pt screen-space threshold, persists the position after
every drag, and pops up the SAME engine menu above the pet. Run on a real Mac
(`.build/debug/claude-cat-app`):

- [ ] `[JUDGMENT]` Click the pet several times while typing continuously in another app
      (TextEdit): typing is never interrupted, no keystrokes are lost, the
      editor keeps keyboard focus and stays frontmost — the click never
      activates this app.
- [ ] `[JUDGMENT]` Drag the pet around while typing continuously in another app: dragging
      also never steals focus or interrupts input.
- [ ] `[JUDGMENT]` Grab the pet by a transparent-margin pixel (the corner outside the drawn
      body but inside the 128 pt frame) and drag: the window follows the mouse;
      the press does not fall through to the window underneath.
- [ ] `[JUDGMENT]` A tiny press that stays under ~3 pt is treated as a click, not a drag:
      the pet never teleports on a plain click.
- [ ] `[JUDGMENT]` Left-click a sleeping (idle) pet: it plays its short prop-appropriate
      wake/startle reaction, then returns to sleep on its own.
- [ ] `[JUDGMENT]` Hover the pointer over the pet: it shows the hover frame; move the pointer
      away: it returns to its base animation.
- [ ] `[JUDGMENT]` Drag the pet to a new spot and relaunch the app: the pet reappears at the
      dragged position (`petPositionX`/`petPositionY` persisted after the drag).
- [ ] `[JUDGMENT]` Drag the pet mostly off-screen and release: it snaps back to a sanitized
      on-screen position, and that sanitized position is what survives relaunch.
- [ ] `[JUDGMENT]` Right-click the pet: the shared menu opens ABOVE the pet (not under it),
      showing the SAME items as the status-item menu — the live "Next refresh
      in Ns" countdown ticking, the creature radio items, the Display toggles,
      Launch at Login, and Quit; selecting an item applies it, and the menu
      dismisses on selection or on clicking elsewhere, without activating the app.

## Full macOS acceptance run

`[JUDGMENT]` Deferred Mac acceptance: with the feature complete, run the
complete checklist above. The pet must pass every item below on a real Mac
before the feature is released or installed for daily use:

- [ ] `[JUDGMENT]` Phase-0 spike premises re-verified on the real pet (not the gray square):
      the shipped window level / collection behavior places the pet over normal
      windows and native fullscreen on exactly one monitor.
- [ ] `[JUDGMENT]` Above normal and fullscreen windows, on all Spaces of one monitor.
- [ ] `[JUDGMENT]` Drag and position persistence across restarts.
- [ ] `[JUDGMENT]` Right-click menu (live countdown, creature radios, toggles) opened from
      the pet, above the pet.
- [ ] `[JUDGMENT]` Left-click reaction (wake/startle).
- [ ] `[JUDGMENT]` Sleep/wake (screen sleep and lock).
- [ ] `[JUDGMENT]` Toggle cycling in every order with the transcript scan rate staying 1x.
- [ ] `[JUDGMENT]` Clicking the pet while typing in another app never interrupts input
      (and neither does dragging it).
- [ ] `[JUDGMENT]` Monitor-unplug fallback relocates the pet onto the main screen.
- [ ] `[INSTRUMENTED]` Energy check per the energy budget (near-zero CPU and wake-ups after five
      minutes of sleep state).

A Linux build is not proof that any of this AppKit behavior works.

## Update — 2026-07-13: illustrated desktop-cat acceptance

This is the normative acceptance run for the illustrated desktop cat and the
dual-renderer lifecycle. Do not mark a manual item passed from source review,
Linux output, or an automated unit test. Leave unchecked items unchecked until
they are observed on a real Mac.

### Evidence labels

- **`[AUTOMATED]`** means a deterministic build, test, or validation command.
  It can establish contracts but not visual quality or AppKit runtime
  behavior.
- **`[JUDGMENT]`** means a person must observe the running release build on a
  real Mac and record pass/fail for visual or interaction behavior.
- **`[INSTRUMENTED]`** means a person must record runtime evidence from
  Activity Monitor, Instruments, logging, or a debugger. Visual stillness is
  not enough for these checks.

### Controlled transcript input

The app has no stage or animation-rate override. Drive acceptance only through
the verified `CLAUDE_CAT_PROJECTS_DIR` seam and record the fixture preparation
procedure plus the resulting CLI snapshot; do not infer the stage or rate from
the intended token counts.

1. Create a disposable directory outside the repository with a nested
   newline-terminated `.jsonl` file. Base assistant records on the parser-tested
   shape in `Tests/ClaudeCatCoreTests/TestFixtures.swift`: `type` is
   `assistant`, timestamp is ISO 8601, message and request IDs are unique,
   `message.model` names the desired family, and `message.usage` contains the
   four token fields.

   ```sh
   fixture_root="$(mktemp -d)"
   mkdir -p "$fixture_root/project"
   ```
2. Use input tokens only when preparing stage fixtures, so effective tokens
   equal the input count. Target totals inside the six default ranges:
   `<1M`, `1M..<3M`, `3M..<8M`, `8M..<16M`, `16M..<28M`, and `>=28M`.
3. For each stage, keep one baseline event inside the current logical day but
   outside the five-minute rate window. Add a final, current event with unique
   IDs: a tiny event for the slow active case and a larger event for the fast
   case. Keep the combined total in the intended stage range. Change the last
   event's model substring among `opus`, `sonnet`, `haiku`, `fable`, and an
   unknown name to exercise accent families.
4. Before observing the app, validate the actual snapshot and save its JSON:

   ```sh
   CLAUDE_CAT_PROJECTS_DIR="$fixture_root" .build/release/claude-cat today --json
   CLAUDE_CAT_PROJECTS_DIR="$fixture_root" .build/release/claude-cat-app
   ```

   Record `stage`, `effectiveTotal`, `tokensPerMinute`, `isIdle`,
   `lastModelFamily`, the fixture timestamps, and the token counts used. Adjust
   the fixture and re-check through the CLI if the snapshot is not the intended
   active stage/cadence.
5. For broken-state acceptance, launch against a path that does not exist and
   confirm `transcriptsFolderFound` is false with `today --json` before
   observing the app.

- Use a Mac with a Retina display and, where available, a non-Retina display.
  Enable and disable Reduce Motion in System Settings > Accessibility >
  Display during the same run.
- Exercise at least two visibly different model accent families plus the
  neutral/unknown accent.

### Automated evidence

Run from the repository root:

```sh
python3 tools/art/pet_art.py check
python3 tools/art/pet_art.py selftest
swift build
swift test
git diff --check
```

- [ ] `[AUTOMATED]` Record the command output and exact test count. This validates the four
      generated pixel creatures, platform-neutral cat planner, visual catalog,
      and tests available on the current host.
- [ ] `[AUTOMATED]` On macOS, run
      `swift build -c release -Xswiftc -strict-concurrency=complete` and record
      its result. A normal Linux `swift build` does not substitute for this
      AppKit/Core Video strict-concurrency build.

No macOS result is recorded by this article; the checkboxes are the acceptance
record.

### Six-stage visual and motion matrix

Run `.build/release/claude-cat-app` and inspect every row at both a slow and a
fast active cadence. User-facing stages 1–3 correspond to internal stages
`0...2`; stages 4–6 correspond to `3...5`.

| Stage | Required prop and action | Slow `[JUDGMENT]` | Fast `[JUDGMENT]` | Fit `[JUDGMENT]` | Visual `[JUDGMENT]` |
|---|---|---|---|---|---|
| 1 (`0`) | Yarn; paw, ball, gaze, and loose thread move coherently | [ ] | [ ] | [ ] | [ ] |
| 2 (`1`) | Yarn; same character, subtly larger and rounder | [ ] | [ ] | [ ] | [ ] |
| 3 (`2`) | Yarn; clear final yarn stage without crowding the canvas | [ ] | [ ] | [ ] | [ ] |
| 4 (`3`) | Cushion; alternating paws visibly knead and compress it | [ ] | [ ] | [ ] | [ ] |
| 5 (`4`) | Cushion; same character, subtly larger and rounder | [ ] | [ ] | [ ] | [ ] |
| 6 (`5`) | Cushion; largest stage remains inside the safe canvas | [ ] | [ ] | [ ] | [ ] |

- [ ] `[JUDGMENT]` Across all rows, the cat reads as one original, softly
      asymmetric pastel character with smooth rounded outlines, not as a
      scaled pixel sprite or a copy of an existing character.
- [ ] `[JUDGMENT]` Slow motion is calm and noticeable without demanding
      attention; fast motion is clearly livelier but does not flicker,
      jump, or become frantic.
- [ ] `[JUDGMENT]` Change the usage rate while a paw or prop is mid-motion.
      The cadence changes without a phase reset, visible pop, duplicated
      beat, or discontinuous jump in the pose.
- [ ] `[JUDGMENT]` On Retina and non-Retina output, outlines and curves remain
      antialiased, the background remains transparent, and no body, tail,
      thread, yarn, or cushion edge is clipped by the 128-point window.

### State, interaction, accent, and accessibility matrix

Repeat the following in both a yarn stage and a cushion stage unless the row
says otherwise:

| State or input | Required observation | `[JUDGMENT]` pass |
|---|---|---|
| Sleeping | Calm breathing/rest pose retains the stage-appropriate prop | [ ] |
| Hover | Face and ears show restrained attention; base activity remains recognizable | [ ] |
| Click | One short prop-appropriate playful reaction returns to hover or neutral state | [ ] |
| Drag | Stable held pose follows the pointer and does not keep decorative motion running | [ ] |
| Broken | Clearly degraded, desaturated pose; no live model accent or continuous motion | [ ] |
| Accent families | Yarn and restrained cushion detail follow each tested model family; neutral fallback is readable | [ ] |
| Reduce Motion | Continuous secondary motion stops while prop, state, stage, and failure cues remain readable | [ ] |

- [ ] `[JUDGMENT]` Toggle Reduce Motion while the cat is visible. The display
      link stops promptly when motion is reduced and resumes cleanly when the
      setting is restored, without losing the current state or prop.
- [ ] `[JUDGMENT]` Hover, click, drag, and snapshot refreshes do not create a
      second click deadline or leave a stale click reaction visible.

### Creature routing and exactly-one-animator lifecycle

- [ ] `[JUDGMENT]` Switch repeatedly through Cat, Bunny, Bird, Flower, Pig,
      then back to Cat. Cat always uses smooth illustrated drawing; the other
      four remain unchanged, crisp 64x64 pixel art at all six stages.
- [ ] `[JUDGMENT]` During every switch, the previous surface disappears before
      the new one appears. There is no overlap, stale frame, blank flash, or
      failure marker for a valid creature.
- [ ] `[INSTRUMENTED]` Confirm exactly one animation
      source is active: a cat display link for animated cat states, or one
      pixel-creature timer for animated non-cat states, never both.
- [ ] `[INSTRUMENTED]` Confirm broken cat, stable cat drag, and Reduce Motion leave no cat
      display link running. Confirm broken pixel creatures leave no repeating
      sprite timer running.
- [ ] `[INSTRUMENTED]` Hide the desktop pet, fully occlude it, and let the display sleep. For
      each case, confirm the active display link or timer is stopped rather
      than merely paused or hidden; reveal/wake restores only the selected
      creature's source.

### Window, focus, drag, and menu regressions

- [ ] `[JUDGMENT]` While continuously typing in another app, click, hover, and
      drag the cat. The other app keeps keyboard focus with no lost keystrokes,
      activation flash, or beep.
- [ ] `[JUDGMENT]` Drag from both visible art and transparent window margin.
      The panel follows the pointer, clamps on-screen when released, and the
      sanitized position persists after relaunch.
- [ ] `[JUDGMENT]` Right-click the cat. The shared menu opens above it, live
      values update, animal and display choices work, and dismissal does not
      activate the pet app.
- [ ] `[JUDGMENT]` Toggle Show on Screen and Show in Menu Bar in every allowed
      order. At least one surface remains enabled, the menu-bar creature is
      unchanged, and transcript refresh cadence remains exactly one engine
      schedule rather than multiplying with display layers.
- [ ] `[JUDGMENT]` Re-run the window-level/Spaces, fullscreen, multi-display,
      monitor-unplug, and screen-recording checks from the Phase-0 procedure
      with the illustrated cat, not only the gray spike.

### Five-minute energy checks

Use Activity Monitor's Energy pane and, when available, Instruments. Record
CPU, wake-ups, and active timer/display-link evidence rather than relying only
on visual stillness.

| Condition held for five minutes | Required source state | `[INSTRUMENTED]` result |
|---|---|---|
| Sleeping illustrated cat | One calm display-linked animation; no pixel timer | [ ] |
| Broken illustrated cat | No cat display link; no pixel timer | [ ] |
| Fully occluded illustrated cat | No cat display link; no pixel timer | [ ] |
| Hidden desktop pet | No display link or pixel timer | [ ] |
| Screen asleep, then awake | No source while asleep; exactly one selected source after wake | [ ] |

- [ ] `[INSTRUMENTED]` Record the five-minute measurements and assess whether the
      sleeping cat remains within an acceptable low-background-energy budget.
      Do not infer this from the stopped broken, hidden, or occluded cases.
