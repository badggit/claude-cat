# Desktop Pet

## Overview

The desktop pet is a second, detachable display surface for the same usage
data shown in the menu bar. It lives in a 128-point borderless window, grows
through six stages with daily usage, sleeps when idle, reacts to pointer
interaction, and shows a visibly broken pose when tracking fails. Users can
run the menu bar, the desktop pet, or both.

The desktop cat is an antialiased Core Graphics illustration whose camera angle
changes with its state. Working and sleeping are shown from the side at a small
laptop (screen on the left, glowing in the model-family accent color; the cat on
the right taps the keys); pointer hover, click, and the broken state keep the
front-on view (the cat turns to face us); dragging drops the laptop and lifts the
cat by the scruff. Bunny, bird, flower, and pig retain their generated 64x64
pixel art. The 16x16 menu-bar creatures use a separate renderer; the desktop-cat
redesign does not change the menu-bar cat.

## Engine and layer architecture

`UsageEngine` (in `Sources/ClaudeCatApp/UsageEngine.swift`) owns the usage
tracker and the shared menu, and treats the visible surfaces as detachable
display layers:

- **Status item layer** — `StatusItemController` renders the 16x16 menu-bar
  creature.
- **Pet window layer** — `PetWindowController` hosts either the illustrated
  cat or a pixel-art creature in one borderless desktop window.

Either layer can be enabled or disabled at runtime from the menu; the engine
keeps ticking regardless and pushes snapshots to whichever layers are
attached. `DisplayTogglePolicy` (pure logic) guarantees the user can never
turn off both layers at once.

## The ClaudeCatPet module boundary

`Sources/ClaudeCatPet` is a pure-logic target. It contains the state machine
(`PetStateEngine`), geometry, palette, visual metadata, generated pixel-art
model and validator, and the deterministic `CatAnimationPlanner`. It imports
no AppKit, so its logic is unit-testable on Linux.

`PetPresentationRouter`, its input/result values, and the
`PetPresentationSurface` protocol are platform-neutral orchestration code in
`Sources/ClaudeCatApp/PetPresentationRouter.swift`. They compile on Linux and
are covered there with injected surfaces. Only the AppKit surface adapters in
that file are inside the macOS guard.

The concrete window and rendering layer is macOS-only:
`PetWindowController`, `CatIllustrationView`, `CatIllustrationRenderer`,
`CatDisplayLinkDriver`, `PetAnimator`, `PetSpriteRenderer`, and the router's
AppKit surface adapters. These types are guarded for macOS where required.

## Dual rendering architecture

`PetVisualCatalog` is the catalog for all five selectable desktop visuals:

- `cat` has kind `illustratedCat` and six stages.
- `bunny`, `bird`, `flower`, and `pig` have kind `pixelArt` and six stages.

`PetArtCatalog` contains only the four generated pixel creatures. It
deliberately returns no art for `cat`; code that needs metadata for all
creatures must use `PetVisualCatalog`.

`PetPresentationRouter` selects one presentation surface from the visual
descriptor. When the selected kind changes, it stops and hides the previous
surface before updating, showing, and, when permitted, starting the new one.
Unknown visual IDs or missing pixel art stop and hide both surfaces and expose
a neutral failure presentation. At most one animation source is active.

### Illustrated cat

`CatAnimationPlanner.sample(stage:behavior:overlay:elapsed:accent:reduceMotion:)`
turns platform-neutral inputs into a `CatAnimationSample`. The active pose is a
single "typing" animation for all six stages: the two front paws alternate onto
the keyboard (`pawTapCyclesPerPeriod` taps per period) and `screenGlow` pulses.
Growth stages only scale `bodyScale`/`bodyRoundness`; there is no per-stage prop
split. The `pose` (active, sleeping, broken, hovering, startled, dragging)
selects paw, head, ear, tail, blink, and `screenGlow` offsets. The planner owns
pose precedence, cadence, motion amplitudes, growth, accent, and reduced-motion
behavior.

`CatIllustrationRenderer` picks a camera angle from the pose via `view(for:)`
and draws one of three scenes:

- **Side scene** (`active`, `sleeping`) — the laptop sits on the left with its
  accent screen on a tilted panel angled toward us; the cat is a side-profile
  loaf on the right, looking left and tapping the keys with both front paws.
  Sleeping flattens the loaf onto the desk, closes the eyes, and adds drifting
  "Zzz" marks.
- **Front scene** (`hovering`, `startled`, `broken`) — the original front-on
  cat behind a centered laptop. Hovering turns the cat to face us and adds
  rising "???" marks; broken shows the `.off` screen.
- **Grabbed scene** (`dragging`) — no laptop; the body is stretched downward,
  the paws dangle, the eyes go wide, and a small wiggle above the head marks the
  scruff hold.

`screenState(for:)` maps the pose to `.on` (active/hover/click/drag, brightness
from `screenGlow`), `.dim` (sleeping), or `.off` (broken — a neutral "no signal"
screen with the live accent dropped). The grabbed scene draws no screen at all.

`CatIllustrationView` advances normalized animation phase from
`CVDisplayLink` timestamps and asks the planner for a new sample. Keeping phase
as normalized cycles preserves the visible pose when the usage rate changes
the period. `CatIllustrationRenderer` draws the sample directly into the
view's Core Graphics context with antialiased paths; it does not cache a bank
of raster frames.

### Pixel creatures

The four non-cat creatures continue through `PetAnimator`,
`PetSpriteRenderer`, and `PetSpriteCache`. Their 64x64 palette-map frames are
scaled with interpolation disabled to preserve hard pixel edges.

## Animation and interaction lifecycle

`PetWindowController` owns the single click-reaction deadline and timer for
both renderers. Hover and drag are persistent interaction overlays; click is a
short `startled` overlay that returns to the current hover or neutral state.
Neither renderer owns a second click timer.

The controller runs the selected surface only while the panel is shown,
unoccluded, and the screens are awake. Hiding the pet, full occlusion, or
screen sleep calls the router's stop path, which fully stops the active source:
the illustrated route stops its display link and the pixel route invalidates
its repeating timer. Switching creature kinds also fully stops and hides the
old surface before activating the new one. The illustrated route additionally
avoids continuous display-link work for broken, stable drag, and reduced-motion
presentations.

## Persistence (UserDefaults keys)

- `selectedCreatureID` — the creature both layers display. `PetVisualCatalog`
  and the menu-bar `CreatureCatalog` register the same five ids: cat, bunny,
  bird, flower, pig.
- `displayMenuBarEnabled` — status item layer on/off.
- `displayPetEnabled` — pet window layer on/off.
- `petPositionX` / `petPositionY` — last dragged pet window position.

## Art pipeline

The 64x64 art for bunny, bird, flower, and pig is authored as
palette-character maps in `tools/art/creatures/<id>.py` and driven by
`tools/art/pet_art.py` (Python 3 stdlib only):

```sh
python3 tools/art/pet_art.py check
python3 tools/art/pet_art.py preview bunny --out /tmp/bunny
python3 tools/art/pet_art.py emit
python3 tools/art/pet_art.py emit --creature pig
python3 tools/art/pet_art.py selftest
```

`emit` writes `Sources/ClaudeCatPet/Art/PetPaletteData.swift` plus one
`PetArt<Name>.swift` for each registered pixel creature. Generated files are
never hand-edited: every pixel-art change goes through the Python source and
`emit`. The Python validator mirrors `PetArtValidator.swift` rule-for-rule;
the shared palette table in `pet_art.py` is the single source of truth, and
`'@'` pixels are the model-family accent placeholder tinted at render time.

Cat is intentionally absent from the Python creature registry. Both
`preview cat` and `emit --creature cat` are invalid and exit nonzero; the
tool must never recreate `PetArtCat.swift`. The illustrated cat is changed in
the planner and Core Graphics renderer instead.

## Constraints and gotchas

- Every non-broken pixel-art frame must contain at least one `'@'` accent
  pixel; broken frames deliberately contain none.
- Pixel-art frame inventory per creature is 6 stages x (at least 2 jump + at
  least 2 sleep + 1 drag + 1 hover) plus shared broken frame(s).
- `PetArtCatalogTests` pins `PetVisualCatalog` to a local expected five-ID
  contract and independently pins `PetArtCatalog` to the four pixel-art IDs.
  The test does not import or compare the app target's `CreatureCatalog`;
  keeping both targets on the same five IDs remains an explicit cross-target
  contract.
- Linux tests cover planner samples, catalog contracts, and routing logic, but
  do not prove AppKit drawing, display-link lifecycle, window behavior, visual
  quality, or macOS energy use. Use the macOS checklist for those claims.

## Related

- [macOS Desktop Pet Checklist](./testing-desktop-pet-macos-checklist.md)
- [Usage Tracking Pipeline](./architecture-usage-tracking-pipeline.md)

## Update — 2026-07-13

### Per-model accent color lives in two parallel tables

The model-family accent color is encoded twice, on purpose, and the two copies
must be kept visually in sync:

- `UsageEngine.accentColors` (`Sources/ClaudeCatApp/UsageEngine.swift`) — an
  `NSColor` table for the menu-bar tint.
- `PetPalette.accentColor(for:)` (`Sources/ClaudeCatPet/PetPalette.swift`) — a
  raw-RGB `PetColor` table for the pet's `'@'` accent pixels.

They cannot share one source because `ClaudeCatPet` is AppKit-free and must not
reference `NSColor`. When a model's color changes, update **both**. (Renaming
history note: the app-side table moved from `StatusItemController` to
`UsageEngine` during the usage-engine refactor.)

### Art `emit` must run on the Linux reference platform

The CI gate requires an empty `git diff` after re-emitting art, which assumes
byte-identical output. Procedural creatures (e.g. `flower`) use libm trig
(`math.sin`/`math.cos`), whose results are not guaranteed bit-identical across
platforms/libc. Always run `python3 tools/art/pet_art.py emit` on the Linux CI
reference platform so the committed Swift art stays stable.

### Exact menu labels

The shared status menu (`MenuBuilder.swift`) exposes: usage rows, **Refresh
Now** (`r`), an **Animal** section (Cat, Bunny, Bird, Flower, Pig), a
**Display** section with **Show in Menu Bar** and **Show on Screen** (the last
enabled one stays checked but grayed out), **Launch at Login**, and **Quit**.

## Update — 2026-07-14

### The illustrated cat now works at a laptop

The cat was reworked from playing with a ball of yarn / kneading a cushion to
sitting front-on at a small laptop and typing. The active pose taps the keyboard
with alternating paws; the laptop screen glows in the model-family accent color
and pulses with the new `screenGlow` value. Sleep, hover, click, drag, and
broken remain distinct poses, differentiated by paw/head/ear offsets plus the
screen state (`.dim` when asleep, `.off` with a neutral "no signal" mark when
broken, `.on` otherwise).

`CatAnimationSample` changed shape: the yarn/cushion `CatActivity` enum and the
`activity`, `propOffsetX/Y`, `propCompression`, and `threadControlOffsetX/Y`
fields were removed; `screenGlow` (0...1) was added. Both prop shapes (yarn,
thread, cushion) and the separate curled/slumped body paths were removed from
`CatIllustrationRenderer`; a single front-on silhouette now serves every pose.

The model-family accent still flows through `PetPalette.accentColor(for:)` into
`sample.accent`, but for the cat it now paints the laptop screen instead of a
yarn ball. The "two parallel accent tables" note above still applies.

### Renderer bitmap tests read a vertically flipped buffer

`CatIllustrationRendererTests` render into a `CGBitmapContext` whose buffer is
stored top-scanline-first while Quartz draws with a bottom-left origin. Pixel
row indices read back from the buffer are therefore vertically flipped relative
to the drawing's Y. Assertions in these tests must use flip-tolerant vertical
bands (or compare heights/sizes and X positions only), never a tight absolute
readback Y. Horizontal (X) positions are not flipped.

## Update — 2026-07-14 — Per-state camera angles

The single front-on cat was split into three camera angles selected in the
renderer by `view(for:)` (a pure function of `CatPose`), so `working` reads as
distinct from `hovering` at a glance:

- `active`, `sleeping` → **side** view (laptop left, cat in profile looking left
  and typing; sleeping lies flat with "Zzz").
- `hovering`, `startled`, `broken` → **front** view (the existing geometry).
  Hovering turns to us and adds rising "???".
- `dragging` → **grabbed** view (no laptop; stretched, dangling paws, wide eyes,
  a scruff wiggle above the head).

This is a renderer-only change: `CatAnimationSample`, `CatAnimationPlanner`, and
the pet state model are untouched — the sample already carries `pose`, and the
camera angle is a presentation decision. The grabbed and hover scenes reuse the
front body/head/paw paths (grabbed under a downward stretch transform); only the
side scene and the "???" glyph are new geometry.

Because the working screen moved to the left, `testAccentAppearsOnlyInThe
GlowingScreen` now asserts a left-side accent band, and a new
`testWorkingUsesSideViewAndHoverUsesFrontView` locks the dispatch by comparing
accent centroids (working screen left of center, hover screen re-centered — X is
not affected by the bitmap flip). The side tail is the shape closest to the
right safe-bounds edge; keep its rightmost control points near x≈107 so the
stage-5 growth scale stays clear of the canvas.

## Update — 2026-07-14 — Working-scene visual language

The active side scene keeps its established composition: a profile cat on the
right works at a laptop on the left. Its silhouette separates the chest, haunch,
folded hind leg, head, ears, and curled tail so the animal reads as a sitting
cat rather than a single rounded shape at desktop-pet scale.

The laptop is drawn as a small, coherent object: a perspective display with a
dark outer edge, camera, and hinge connects to a shallow keyboard deck with a
front lip, key rows, and trackpad. The model-family accent remains confined to
the screen; low-opacity terminal lines and a bloom make it read as an active
work display without competing with the cat.

## Update — 2026-07-15 — Cat-shaped profile head, hinged lid, hover drops the laptop

### The side head is short-muzzled on purpose

The first side-profile head read as a rat, not a cat: a long tapering snout, a
small eye set far back, narrow spike ears, and a wide whisker fan that extended
the snout further. The rebuilt `drawSideHead` keeps the strict profile (the
camera did not change) and fixes the proportions instead:

- The face front drops almost vertically from the brow to the chin, so the
  muzzle barely projects. **This is the load-bearing property** — a projecting
  muzzle is what makes a profile read as a rodent at any size.
- Round skull dome; head spans roughly x 43–72, y 67–89 (about 28 x 22).
- Two wide triangular ears, roughly as tall as they are wide, sitting on the
  skull's top corners. The far ear is filled with `Palette.furShadow` and drawn
  first so the pair reads with depth rather than as two spikes.
- The eye is bigger (5.0 x 5.2) and sits at ~58% of head height.
- Only two short whiskers. A long fan rebuilds the snout the skull just removed.
- Forehead tabby stripes echo the body markings and help sell "cat".

### The side laptop is one hinged object

`Metrics.sideLid` is a `LidQuad` (bottom-left, bottom-right, top-right,
top-left) hinged along the keyboard deck's back edge and leaning away from the
viewer. The screen panel is the same quad shrunk about its own center
(`inset(by: Metrics.sidePanelInset)`), which keeps the bezel's perspective
consistent with the lid instead of drifting. The deck is drawn after the lid and
covers the hinge seam. The previous lid floated above and to the left of the
deck with a separate hinge quad, which is why it read as a picture frame.

The lid stays narrow enough (right edge ≈ x 52) that the cat's forelimbs, which
are drawn later, do not cross the screen.

### Pointer interaction drops the laptop

`showsLaptop(in:)` (a pure function of `CatPose`) is now consulted before the
front scene draws the laptop:

- `hovering`, `startled` — no laptop. Hover drops it because the cat has turned
  away from its work; the click reaction drops it too, since a click almost
  always lands on an already-hovered cat and keeping it would flash the laptop
  back for the length of the startle.
- `broken` — keeps it. The dead "no signal" screen is how the failure reads.
- `dragging` — the grabbed scene never drew one anyway.

Because the hover scene has no lit screen, the `"???"` marks now carry the
model-family accent instead of `Palette.markings`, so the accent survives the
pose. They climb past the head's **top-right** corner: a stage-5 cat fills the
canvas (head top ≈ y 114, right edge ≈ x 95), so that diagonal is the only free
space left inside the safe bounds. Do not move them above the head — there is no
room there.

### Test consequences

- `testAccentAppearsOnlyInTheGlowingScreen` — the new lid sits lower on the
  canvas, so the vertical band was loosened to "clear of both edges"
  (`minY > 50`, `maxY < 205`). The X assertion is unchanged and carries the real
  claim, since X is not affected by the bitmap flip.
- `testHoverAndClickDropTheLaptopWhileBrokenKeepsIt` — new. The lit screen is the
  only place the live accent can land in the front poses, so counting accent
  pixels is how the laptop's absence is proven: startled has exactly zero.
- Hover's accent floor is 120 px at a 256 px render (measured ≈ 214). It is the
  tightest bound in the file, because three thin strokes are the pose's whole
  accent budget. If macOS CI fails one of these tests, start here.

### Pixel creatures bounce in place

The four pixel creatures jumped from a lying crouch to a fully airborne pose, so
the head rose 12–26 px out of 64. The airborne frame now lands its feet on the
same ground line as the crouch, cutting the head rise by 31–69% and reading as a
springy bounce rather than a leap. The change lives in the art source, per
creature type:

- `bunny`, `bird` — hand-authored ASCII maps: each `S<n>_JUMP1` block was
  shifted down by `crouch_bottom - airborne_bottom` rows.
- `pig` — procedural: `_airborne`'s `cy = GROUND - ry - 12` became `- 3`.
- `flower` — procedural: the `jump1` lift of 8 was removed. Only `drag` still
  lifts the pot off the ground.

Sleep, drag, hover, and broken frames were deliberately left alone.
