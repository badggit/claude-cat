# Swift Coding Rules

A project-grounded cheat sheet of Swift rules distilled from this codebase. Every
rule is something the existing code already does (or deliberately avoids). Follow
them so a future change does not reintroduce a bug the design has already solved.

Scope: `ClaudeCatCore`, `ClaudeCatPet`, `ClaudeCatCLI`, `ClaudeCatApp`
(Swift 5.9, Foundation + AppKit + Core Graphics, zero external packages). There is
no tracked SwiftLint/SwiftFormat config — these conventions are the standard.

Line references (`File.swift:NN`) are pointers into the source as of the "Last
updated" date; if a line moved, search the symbol.

## TL;DR — the deadliest mistakes

1. `import AppKit` in `ClaudeCatCore` / `ClaudeCatPet` → breaks the Linux build. Keep them AppKit-free.
2. Reading `Date()` / `TimeZone.current` in logic → untestable, zone-dependent. Inject `now:` and a `Calendar`.
3. `Date()` / randomness in draw or planner code → flickery, untestable. Drive animation from an injected `elapsed`.
4. Strong `self` in a `Timer` / animator / async closure → retain cycle, `deinit` never runs. Use `[weak self]`.
5. `default:` in a `switch` over a domain enum → a new case fails silently at runtime instead of at compile time.
6. `!` force-unwrap on `statusItem.button`, `NSScreen.main`, a `CGImage`, etc. → crashes the whole app. `guard let` + fallback.
7. Collapsing "irrelevant / malformed / no-usage" into one `nil` → format drift undercounts silently. Model outcomes as an enum + diagnostics counters.
8. Hand-editing files under `Sources/ClaudeCatPet/Art/` → clobbered on regen. Change `tools/art/pet_art.py` and regenerate.
9. A green Linux `swift test` is **not** proof AppKit works. Verify the macOS runtime per the checklist.

---

## 1. Modules & platform boundaries

### Keep AppKit out of `ClaudeCatCore` and `ClaudeCatPet`
**Rule.** All cross-platform parsing/aggregation lives in `ClaudeCatCore`; all pure pet logic (state machine, geometry, palette, art model) in `ClaudeCatPet`. Neither imports AppKit/Cocoa/SwiftUI. **Why:** those two targets build and run their tests on Linux; a stray AppKit import breaks the whole loop.
```swift
.target(name: "ClaudeCatPet", dependencies: ["ClaudeCatCore"]) // no AppKit dependency
```
`Package.swift:16`, `AGENTS.md:184-189`

### Enforce the boundary with a source-scanning test, not trust
**Rule.** A test enumerates `Sources/ClaudeCatPet/*.swift` and fails on any banned import — don't rely on "a macOS build would catch it." **Why:** a passing macOS compile never proves Linux portability; the ban must be checked on Linux itself.
```swift
let bannedImports = ["import AppKit", "import Cocoa", "import SwiftUI"]
```
`Tests/ClaudeCatPetTests/DisplayTogglePolicyTests.swift:104-131`

### Wrap every AppKit source file in `#if os(macOS)`
**Rule.** Any file that imports AppKit/CoreVideo is fully bracketed by `#if os(macOS) … #endif`, so Linux sees an empty file. **Why:** an unguarded AppKit symbol breaks the cross-platform compile entirely.
```swift
#if os(macOS)
import AppKit
// entire file …
#endif
```
`Sources/ClaudeCatApp/PetInteractionView.swift:1` + `:136`

### In `ClaudeCatPet`, guard Core Graphics with `#if canImport(CoreGraphics)`
**Rule.** The pet module imports only `Foundation`; CGRect/CGFloat helpers go behind `#if canImport(CoreGraphics)`. Never reference `NSColor`/AppKit there. **Why:** the geometry/validator tests run headless on Linux.
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
```
`Sources/ClaudeCatPet/PetGeometry.swift:9`

### Keep business logic in Core, keep the CLI/executable thin
**Rule.** Argument parsing, JSON/human formatting, and calibration tables live in `CLISupport` inside `ClaudeCatCore`; the `claude-cat` executable is a thin caller. **Why:** logic in an executable's `main.swift` can't be unit-tested and rots.
```swift
CLISupport.parseArguments(["today", "--json"]) == .success(.today(json: true))
```
`Sources/ClaudeCatCore/CLISupport.swift`, `AGENTS.md:190-192`

---

## 2. Concurrency & main-thread safety

### Confine the non-thread-safe worker to one serial queue; cross threads only with an immutable snapshot
**Rule.** `TodayTracker` is a `final class` that is deliberately **not** thread-safe. Run it on a private serial `DispatchQueue`; hop to `DispatchQueue.main.async` handing back only the immutable `DailyUsageSnapshot`. **Why:** sharing the mutable tracker across threads is a data race; a frozen value keeps all UI/timer state single-threaded.
```swift
trackerQueue.async { [weak self] in
    let snapshot = self?.tracker.refresh(now: Date())
    DispatchQueue.main.async { self?.apply(snapshot: snapshot) }
}
```
`Sources/ClaudeCatApp/UsageEngine.swift:42,140-148`, `TodayTracker.swift:13-17`

### Discard the result of `MainActor.assumeIsolated`
**Rule.** When a `@discardableResult` function is the last expression inside `MainActor.assumeIsolated { … }`, prefix the whole call with `_ =`. **Why:** `assumeIsolated` returns its closure's value; `@discardableResult` does **not** propagate through the closure, so the returned value is "unused" and the compiler warns (`#no-usage`).
```swift
// bad:  MainActor.assumeIsolated { router.update(...) }   // warns: unused value
// good: _ = MainActor.assumeIsolated { router.update(...) }
```
`Sources/ClaudeCatApp/PetWindowController.swift:255`, `PetPresentationRouter.swift:66`

### Off-main C callbacks: `@unchecked Sendable` guarded by a lock
**Rule.** A `CVDisplayLink` (or other C) callback fires on a private thread — route shared state through an `@unchecked Sendable` context whose every field access is `NSLock`-protected, and type the handler `@Sendable`. **Why:** `@unchecked Sendable` is what legally lets you pass the class into the C `Unmanaged` context; the lock is what prevents the race.
```swift
private final class CallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    func emit(_ t: TimeInterval) { lock.lock(); let h = handler; lock.unlock(); h?(t) }
}
```
`Sources/ClaudeCatApp/CatDisplayLinkDriver.swift:23-44`

### Advance unbounded frame counters with `&+=`
**Rule.** A monotonically-growing index used only `% count` is incremented with the overflow-safe `&+=`. **Why:** a background animation can tick for days; a plain `+=` eventually traps on `Int` overflow and crashes a long-running app.
```swift
frameIndex &+= 1
onFrame?(frames[frameIndex % frames.count])
```
`Sources/ClaudeCatApp/StatusItemController.swift:87`, `PetAnimator.swift:148`

---

## 3. Object lifecycle: timers, weak captures, deinit

### Capture `self` weakly in every escaping closure
**Rule.** `Timer.scheduledTimer`, `animator.onFrame`, `DispatchQueue.main.asyncAfter`, notification handlers — all capture `[weak self]`. **Why:** the timer/notification-center retains the closure; a strong `self` makes the controller immortal and its teardown never runs.
```swift
Timer.scheduledTimer(withTimeInterval: t, repeats: true) { [weak self] _ in self?.advanceFrame() }
```
`Sources/ClaudeCatApp/PetAnimator.swift:133`, `StatusItemController.swift:74`

### Invalidate a Timer before reassigning; skip recreation when nothing changed
**Rule.** Invalidate the old timer before storing a new one, and return early when the requested interval matches the current one. **Why:** reassigning without `invalidate()` leaks a still-firing timer; recreating every poll restarts the animation cycle (visible flicker).
```swift
if animationTimer != nil, abs(interval - currentInterval) < 0.001 { return }
animationTimer?.invalidate()
```
`Sources/ClaudeCatApp/StatusItemController.swift:67-77`, `PetAnimator.swift:126-138`

### Invalidate every timer and remove every observer in `deinit`/teardown
**Rule.** `deinit` and `hide`/`stop` paths invalidate all owned timers and remove all observers. **Why:** an orphaned repeating timer keeps firing and keeps its target alive, burning CPU on a dropped controller.
```swift
deinit { startleTimer?.invalidate(); removeObservers() }
```
`Sources/ClaudeCatApp/PetWindowController.swift:126-132`, `UsageEngine.swift:108-111`

### Hold UI subscribers in a weak box and prune on access
**Rule.** Store display layers/observers in a `weak var`-wrapping struct in the array; `removeAll { $0.layer == nil }` before use. **Why:** a strong array keeps destroyed windows alive; the weak box lets released layers drop out.
```swift
private struct WeakLayer { weak var layer: UsageDisplayLayer? }
```
`Sources/ClaudeCatApp/UsageEngine.swift:36-38,132-134`

---

## 4. Domain modeling with types

### Model outcomes as a closed enum, not `Optional` or `throws`
**Rule.** Parsing returns one case per distinct outcome (`.event` / `.skippedIrrelevant` / `.assistantWithoutUsage` / `.malformed`), not `UsageEvent?`. **Why:** an optional collapses "irrelevant line", "format-drift line", and "broken JSON" into a single `nil`, making the diagnostics tripwire impossible.
```swift
// bad:  func parse(line: String) -> UsageEvent?
// good: func parse(line: String) -> ParseOutcome
```
`Sources/ClaudeCatCore/TranscriptLineParser.swift:3-8`

### Switch exhaustively over domain enums — never `default:`
**Rule.** Handle every case explicitly (use `break` for the no-op arm); no catch-all. Applies to `ParseOutcome`, `PetOverlay`, `PetBehaviorState`, `CatPose`, `ModelFamily`. **Why:** `default:` turns "someone added a case" into a silent runtime fallthrough instead of a compile error at every call site.
```swift
switch overlay {
case .startled: beginStartleReaction()
case .dragging:  restingOverlay = overlay; clearStartleReaction()
case .none, .hovering: restingOverlay = overlay
} // no default
```
`Sources/ClaudeCatApp/PetWindowController.swift:242-250`, `CatIllustrationRenderer.swift:785`

### Keep everything that crosses threads a value type
**Rule.** Snapshots/events/config/art-descriptors are `struct`/`enum`; the only class is the queue-confined orchestrator. **Why:** value semantics make cross-thread hand-off race-free and make `==` diffing trivial.
`Sources/ClaudeCatCore/UsageModels.swift:93`, `TodayTracker.swift:13-17`

### Make art/animation descriptors `Equatable` value types
**Rule.** Frames, colors, and animation samples are structs conforming to `Equatable`. **Why:** the view can detect no-op updates with a one-line `==` instead of comparing pixels, and tests can diff samples directly.
```swift
public struct CatAnimationSample: Equatable { ... }
```
`Sources/ClaudeCatPet/CatAnimationPlanner.swift:16`, `PetArtModel.swift:8`

### Use `private(set)` for read-outside / mutate-inside state
**Rule.** Expose accumulator results as `public private(set) var`; keep internal bookkeeping (`seenDedupKeys`, `recentEvents`) fully `private`. **Why:** a plain `public var` lets callers corrupt running totals and break the accumulate-only invariant.
```swift
public private(set) var totals: TokenCounts = .zero
private var seenDedupKeys: Set<String> = []
```
`Sources/ClaudeCatCore/UsageAccumulator.swift:11-22`

### Map unknown inputs to an explicit fallback case, never crash
**Rule.** Derive `ModelFamily` from a lowercased substring scan over `allCases`, falling back to `.other` for nil/unrecognized. **Why:** a new/absent model id must never crash or be silently dropped from per-model totals.
```swift
let matched = ModelFamily.allCases.first { $0 != .other && lowered.contains($0.rawValue) }
self = matched ?? .other
```
`Sources/ClaudeCatCore/UsageModels.swift:56-76`

---

## 5. Errors, diagnostics, no silent failure

### Surface diagnostics counters instead of failing silently
**Rule.** Count malformed lines and usage-less assistant records into the snapshot (`parseErrorCount`, `suspiciousSkipCount`); don't `continue` past them. **Why:** a silent skip hides format drift — the product intentionally shows a "confused cat" when transcripts change shape.
```swift
case .malformed: parseErrorCount += 1
case .assistantWithoutUsage: suspiciousSkipCount += 1
```
`Sources/ClaudeCatCore/TodayTracker.swift:112-121`

### Decode into an all-optional `Codable` mirror so drift degrades, not throws
**Rule.** Every field of the transcript `Decodable` struct is optional; unknown keys are ignored. Convert missing data into `.assistantWithoutUsage`/`.malformed`, not a decode crash. **Why:** one required field would turn a single upstream schema change into a hard failure on every line.
```swift
private struct TranscriptRecord: Decodable { let type: String?; let message: Message? }
```
`Sources/ClaudeCatCore/TranscriptLineParser.swift:10-38`

### Default absent numeric fields to `0`; reserve `.malformed` for unparseable structure
**Rule.** Coalesce missing token counts with `?? 0`; only undecodable JSON or a bad timestamp is `.malformed`. **Why:** treating a missing `cache_read_input_tokens` as an error would drop valid usage and inflate the parse-error tripwire.
```swift
TokenCounts(input: usage.inputTokens ?? 0, output: usage.outputTokens ?? 0, ...)
```
`Sources/ClaudeCatCore/TranscriptLineParser.swift:70-82`

### Return `Result` with a typed error enum from parsing; scanners swallow I/O to `[]`
**Rule.** Argument parsing is `Result<CLICommand, CLIParseError>` with validation (`Int(raw), days > 0`); directory scanning routes I/O errors through an `errorHandler` and returns `[]` for a missing root. **Why:** throwing from argv parsing or a missing transcripts folder would crash the CLI/menu app on ordinary user conditions.
```swift
guard let days = Int(raw), days > 0 else { return .failure(.invalidValue(raw)) }
```
`Sources/ClaudeCatCore/CLISupport.swift:28-52`

### Never force-unwrap — chain, coalesce, or guard with a safe fallback
**Rule.** Use `?.`/`??`/`guard let` on `statusItem.button`, `window`, `NSScreen.main`, `CGImage`, data providers, and array indices. **Why:** these are legitimately nil (no menu bar, no screen, unrenderable frame); a `!` crashes the whole app during a routine event. Safe degradation: `.zero`, an invisible `NSImage`, or an early `return`.
```swift
NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
guard let provider = CGDataProvider(...), let cg = CGImage(...) else { return NSImage(size: size) }
```
`Sources/ClaudeCatApp/StatusItemController.swift:100-103`, `PetSpriteRenderer.swift:18`

---

## 6. Determinism & injected time

### Inject `now:` and a `Calendar`; never read `Date()` / `TimeZone.current` in logic
**Rule.** Pass the instant and a calendar (which carries the zone) into every time-dependent function. **Why:** hidden `Date()`/`TimeZone.current` makes logical-day boundaries untestable and silently zone-dependent — transcript timestamps are UTC while the "day" is local.
```swift
// bad:  func dayStart() -> Date { Calendar.current.startOfDay(for: Date()) }
// good: func dayStart(containing date: Date) -> Date // calendar injected
```
`Sources/ClaudeCatCore/LogicalDayCalculator.swift:5-13`, `TodayTracker.swift:36`

### Keep draw/plan code deterministic — feed time in as `elapsed`
**Rule.** Derive all animation from an explicit `elapsed`/phase argument and pure `sin`/`cos`; never call `Date()`, a clock, or a random source in planner or renderer code. **Why:** nondeterministic draw code is untestable and flickers; periodicity is verified with `sample(elapsed: 0) == sample(elapsed: period)`.
```swift
public static func sample(stage: Int, ..., elapsed: TimeInterval) -> CatAnimationSample
```
`Sources/ClaudeCatPet/CatAnimationPlanner.swift:126`

### Split the pure planner from the Core Graphics renderer
**Rule.** Geometry/animation math lives in the AppKit-free planner returning a value-typed sample; the renderer only reads that sample and issues CG calls. **Why:** mixing motion math into CG draw code makes it impossible to unit-test off-screen and on Linux.
`Sources/ClaudeCatPet/CatAnimationPlanner.swift:126`, `Sources/ClaudeCatApp/CatIllustrationRenderer.swift:43`

---

## 7. Parsing & data integrity

### Prefilter cheaply, then decode; hold decoders/formatters as `static let`
**Rule.** Gate JSON decoding behind `line.contains("assistant") && line.contains("usage")`, and keep `JSONDecoder`/`ISO8601DateFormatter` as shared `static let`. **Why:** `parse()` runs on every appended line; a per-call decoder and decoding irrelevant lines waste work on the poll loop.
```swift
guard line.contains("assistant"), line.contains("usage") else { return .skippedIrrelevant }
private static let decoder = JSONDecoder()
```
`Sources/ClaudeCatCore/TranscriptLineParser.swift:41-62`

### Never consume a trailing partial line
**Rule.** Split only up to the last `\n`; leave a newline-less tail unread and don't advance the byte offset past it. **Why:** consuming a half-written JSONL line permanently loses its remainder once the writer finishes appending.
```swift
guard let last = data.lastIndex(of: UInt8(ascii: "\n")) else { return ([], didReset) }
position.byteOffset += UInt64(consumed.count)
```
`Sources/ClaudeCatCore/IncrementalLineReader.swift:52-66`

### On truncation/replacement, rebuild the whole day — dedup is not enough
**Rule.** Detect a position reset (`currentSize < offset` OR inode mismatch); when any file reset, discard state and re-scan from `.start`. **Why:** keyless events (no `messageId`/`requestId`) can't be deduplicated, so a re-read after atomic replacement double-counts them.
```swift
if scanAndIngest(...) { accumulator.resetForNewDay(); positions.removeAll(); _ = scanAndIngest(...) }
```
`Sources/ClaudeCatCore/TodayTracker.swift:48-59`

### Persist a read position only after a successful read
**Rule.** Copy `positions[url]` into a local `var`, pass it `inout`, write it back only on success; on failure `continue` and leave the stored value intact. **Why:** overwriting the offset before a read that then throws (file vanished mid-read) skips or re-reads bytes next tick.
```swift
var position = positions[url] ?? .start
guard let (lines, reset) = try? reader.readNewLines(at: url, from: &position) else { continue }
positions[url] = position
```
`Sources/ClaudeCatCore/TodayTracker.swift:103-109`

### Do weighting math in `Double`, keep raw counts in `Int`
**Rule.** Convert to `Double` only inside `effectiveTokens(weights:)`; keep `TokenCounts` integer, combine with a custom `+` seeded from `.zero`. **Why:** multiplying `Int` counts by a fractional weight (`cacheRead 0.1`) truncates to 0; ad-hoc field summation invites transcription bugs.
```swift
Double(cacheRead) * weights.cacheRead
totals = totals + event.counts
```
`Sources/ClaudeCatCore/UsageModels.swift:9-34`

---

## 8. Core Graphics & rendering

### Balance every `saveGState()` with a `restoreGState()`
**Rule.** Bracket the whole draw with `saveGState()` + `defer { restoreGState() }`, and wrap every nested transform in its own explicit save/restore. **Why:** a leaked graphics-state transform corrupts every subsequent layer's coordinate system.
```swift
context.saveGState(); defer { context.restoreGState() }
```
`Sources/ClaudeCatApp/CatIllustrationRenderer.swift:63,114`

### Guard the destination rect before drawing; return, don't crash
**Rule.** Validate that the destination origin/size are finite and strictly positive at the top of `draw`, and early-return on failure. **Why:** a `NaN`/zero/negative rect produces garbage transforms or an out-of-range scale — tests feed `0`, `NaN`, `-1` and assert the bitmap is untouched.
```swift
guard destination.width.isFinite, destination.width > 0, ... else { return }
```
`Sources/ClaudeCatApp/CatIllustrationRenderer.swift:48`

### Clamp stages and normalized scalars at the point of use
**Rule.** Index sprite arrays only through a clamped stage; clamp normalized values (`0...1` glow/alpha/scale). **Why:** a persisted or computed out-of-range stage crashes on array access, and an unclamped scalar over-saturates.
```swift
let clamped = min(max(stage, 0), stages.count - 1)
```
`Sources/ClaudeCatPet/PetArtModel.swift:48`, `CatAnimationPlanner.swift:134`

### Template `NSImage` for the menu bar; drop template only after tinting
**Rule.** Menu-bar silhouettes use `image.isTemplate = true` (adapts to light/dark); after tinting with an explicit accent (`.sourceAtop`), set `isTemplate = false`. **Why:** a non-template menu-bar image is wrong in one appearance; a tinted image left as a template gets re-monochromed by AppKit.
```swift
image.isTemplate = true          // adaptive silhouette
result.isTemplate = false        // after applying an explicit color
```
`Sources/ClaudeCatApp/Creature.swift:77`, `StatusItemController.swift:116`

### Disable interpolation and scale pixel art by integer multiples
**Rule.** Build pixel-art `CGImage`s with `shouldInterpolate: false` and present at an integer multiple of the backing grid (64px shown at 128pt = 2×). The buffer is exactly `petGrid*petGrid*4` RGBA bytes, top-left row-major, `alpha .last`. **Why:** interpolated/non-integer scaling blurs crisp pixels.
```swift
CGImage(width: petGrid, height: petGrid, ..., shouldInterpolate: false, ...)
```
`Sources/ClaudeCatApp/PetSpriteRenderer.swift:13`

---

## 9. AppKit surface specifics

### Build the desktop pet as a non-activating panel that answers the first click
**Rule.** Use `NSPanel` with `[.borderless, .nonactivatingPanel]`, `becomesKeyOnlyIfNeeded = true`, show via `orderFrontRegardless()`, and override `acceptsFirstMouse` → `true` on the event view. **Why:** the pet must never activate the app or steal key focus, yet still react to the first click while another app is frontmost.
```swift
NSPanel(..., styleMask: [.borderless, .nonactivatingPanel], ...)
override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
```
`Sources/ClaudeCatApp/PetWindowController.swift:98-103,146`, `PetInteractionView.swift:40-42`

### Probe `UserDefaults` with `object(forKey:)` when absent must mean `true`
**Rule.** For a boolean whose "not set" state is ON, read `(defaults.object(forKey:) as? Bool) ?? true`, not `defaults.bool(forKey:)`. **Why:** `bool(forKey:)` returns `false` for a missing key, silently turning a default-on feature off for existing users on first launch.
```swift
// bad:  defaults.bool(forKey: displayPetEnabledKey)
// good: (defaults.object(forKey: displayPetEnabledKey) as? Bool) ?? true
```
`Sources/ClaudeCatApp/UsageEngine.swift:265-270`

### An `NSMenuItem` belongs to one menu — detach before re-adding
**Rule.** When moving items from a throwaway builder `NSMenu` into the persistent menu, call `removeItem(item)` on the source before `addItem` on the destination. **Why:** an item can only be in one menu at a time; adding one still owned by the builder produces wrong/duplicated menus.
```swift
for item in built.items { built.removeItem(item); menu.addItem(item) }
```
`Sources/ClaudeCatApp/UsageEngine.swift:186-191`

### Add menu-tracking timers to the run loop in `.common` mode
**Rule.** A timer that must keep firing while a menu is open uses `Timer(...)` + `RunLoop.current.add(timer, forMode: .common)`, not `scheduledTimer`. **Why:** a default-mode timer is starved during menu tracking, so a live countdown row freezes the moment the menu opens.
```swift
let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateCountdownItem() }
RunLoop.current.add(t, forMode: .common)
```
`Sources/ClaudeCatApp/UsageEngine.swift:197-203`

---

## 10. Generated art

### Never hand-edit generated art — regenerate it
**Rule.** Treat `Sources/ClaudeCatPet/Art/*` and `PetPaletteData.swift` as build output of `tools/art/pet_art.py`; change the tool and run `python3 tools/art/pet_art.py emit`, don't tweak the Swift/pixels by hand. **Why:** hand edits are clobbered on the next regen and drift from the Python source of truth.
```swift
// GENERATED by tools/art/pet_art.py — do not edit.
```
`Sources/ClaudeCatPet/Art/PetArtBird.swift:1`

### Validate art models instead of trusting them
**Rule.** `PetArtValidator.issues(in:palette:)` checks grid size, stage/frame counts, unknown glyphs, and the required `@` accent; `.` and `@` stay reserved (out of the palette). A valid model returns `[]`. **Why:** bad art otherwise renders as transparent or crashes deep in the rasterizer with no message.
```swift
for reserved in [".", "@"] where palette.colors[reserved] != nil {
    issues.append("reserved character '\(reserved)' must not be defined")
}
```
`Sources/ClaudeCatPet/PetArtValidator.swift:12`

---

## 11. Testing discipline

### Inject clock, calendar, file manager, and frame driver — never touch the real ones
**Rule.** Drive time/environment/animation through injected fixed instants, an explicit-timezone `Calendar`, an injected `FileManager`, and a manual `frameDriver`/`monotonicClock`/`reduceMotionProvider`; advance frames by calling `driver.pulse(timestamp:)`. **Why:** real clocks, display links, timezones, and `~/.claude` make tests flaky, slow, and time-of-day dependent.
```swift
calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!   // non-UTC exposes zone bugs
let first = tracker.refresh(now: fixedInstant)
```
`Tests/ClaudeCatCoreTests/TodayTrackerTests.swift:24-25,62-66`

### Use inline string/JSONL fixtures, never resource bundles
**Rule.** Express transcript lines as inline Swift constants or builder helpers; when a file is genuinely needed, write it into a per-test temp dir and delete it in teardown. **Why:** resource bundles don't travel to Linux (no test bundle here) and add I/O flakiness.
```swift
enum TestFixtures { static let assistantFullUsage = """{ ... "usage": { ... } }""" }
```
`Tests/ClaudeCatCoreTests/TestFixtures.swift:1-7`

### `@testable import` for Core/App internals; plain `import` for the Pet contract
**Rule.** Use `@testable import` when reaching internal types; use plain `import ClaudeCatPet` since its API is exercised as a public contract. **Why:** reaching into internals needlessly couples tests to private shape; the pet module is deliberately tested through its public surface.
`Tests/ClaudeCatPetTests/PetStateEngineTests.swift:3-4`

### Gate AppKit tests behind `#if os(macOS)`
**Rule.** Any test touching AppKit/CoreGraphics/CoreVideo is fully wrapped in `#if os(macOS)`, and a smoke test keeps the target linking on Linux. **Why:** unguarded AppKit test code fails to build on Linux and breaks `swift test` for the whole suite.
`Tests/ClaudeCatAppTests/CatIllustrationRendererTests.swift:1`

### Assert invariants across the whole state space, not one example
**Rule.** For safety invariants (e.g. `DisplayTogglePolicy` always keeps one surface enabled), loop over all reachable states and assert the property; cross-check paired predicates (`canDisable` vs the actual toggle) for mutual agreement. **Why:** a single happy-path test misses the one transition that violates the invariant.
```swift
for flags in allStates { for display in bothDisplays { XCTAssertTrue(next.menuBar || next.pet) } }
```
`Tests/ClaudeCatPetTests/DisplayTogglePolicyTests.swift:45-88`

### Cover malformed lines, day boundaries, file resets, and keyless dedup explicitly
**Rule.** Add focused tests for broken JSON that passes the prefilter, assistant records without usage, day rollover, mid-day truncate-and-rewrite, and events with nil `messageId`/`requestId`; assert the diagnostic counters, not just totals. **Why:** format drift must show in diagnostics, a rebuild must count replaced content exactly once, and keyless events must not double-count after a re-read.
```swift
XCTAssertEqual(first.parseErrorCount, 2)   // not just checking totals
```
`Tests/ClaudeCatCoreTests/TodayTrackerTests.swift:163-200,254-292`

### Test rendering by drawing into an off-screen bitmap and asserting statistics
**Rule.** Verify visuals with no real screen: draw into a `CGContext(data: nil, ...)` bitmap and assert on aggregate stats — transparent corners, an antialiased edge (`0 < alpha < 255`), tolerance-matched accent-pixel counts/centroids, and `differingPixelCount` between poses — not exact golden images. **Why:** golden images are brittle across antialiasing/platforms; statistical assertions catch real regressions while tolerating sub-pixel noise.
```swift
XCTAssertTrue(corners.allSatisfy { $0.alpha == 0 })                       // transparent margins
XCTAssertTrue(bitmap.pixels.contains { $0.alpha > 0 && $0.alpha < 255 })  // AA edge
```
`Tests/ClaudeCatAppTests/CatIllustrationRendererTests.swift:198,233`

### A green Linux build is not proof AppKit/art/runtime works
**Rule.** Treat Linux `swift test` as covering only planner/catalog/routing/lifecycle contracts; verify the status item, menu, animation, sleep/broken states, Quit, Launch at Login, and visual art quality manually per `testing-desktop-pet-macos-checklist.md`. **Why:** AppKit, Core Graphics/Video, window focus, energy behavior, and visual quality cannot be proven on Linux.
`AGENTS.md:262-270`, `docs/wiki/testing-desktop-pet-macos-checklist.md`

### Inject fakes/recorders to test routing and idempotency
**Rule.** Inject fake surfaces plus an event recorder into routers/controllers to assert ordered side effects, that only the active surface is targeted, and that identical updates are idempotent. **Why:** without doubles you can't assert "stop+hide the inactive surface before showing the new one" ordering, or that repeated updates don't replay stale frames.
`Tests/ClaudeCatAppTests/PetPresentationRouterTests.swift:110-119,267-311`
