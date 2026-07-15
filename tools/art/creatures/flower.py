"""64x64 pet art for the Flower creature (potted pink flower).

Six growth stages (Sprout -> Giant), each with a jump pair (a happy
bounce: squashed crouch + airborne pot), a two-frame sleep pair (closed
bloom drooping, breathing sway), a drag frame (held aloft, stem bent by
the pot's weight), and a hover frame (bloom open and turned up), plus
one shared broken frame (desaturated, glitch-sheared, deliberately
without the '@' accent). Style matches the approved cat: one top-left
light source, shared 'k' outline, '@' pot-ribbon accent in every
non-broken frame.

Frames are composed procedurally from small drawing helpers so each
pose stays consistent across the six stages.
"""
import math

GRID = 64
GROUND = 60


def _grid():
    return [["."] * GRID for _ in range(GRID)]


def _px(g, x, y, ch):
    if 0 <= x < GRID and 0 <= y < GRID:
        g[int(y)][int(x)] = ch


def _ellipse(g, cx, cy, rx, ry, ch):
    if rx <= 0 or ry <= 0:
        return
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                _px(g, x, y, ch)


def _hspan(g, x0, x1, y, ch):
    for x in range(int(x0), int(x1) + 1):
        _px(g, x, y, ch)


# Tapered stroke used for leaves: walks from (x0, y0) along (dx, dy)
# growing then shrinking its half-width, giving a pointed leaf shape.
def _leaf(g, x0, y0, dx, dy, length, width, ch):
    for i in range(length):
        t = i / max(1, length - 1)
        half = width * math.sin(min(1.0, t * 1.25) * math.pi)
        x = x0 + dx * i
        y = y0 + dy * i
        for w in range(-int(half), int(half) + 1):
            _px(g, x, y + w, ch)


# Quadratic bezier stem, 2px wide green with a light left-edge highlight.
def _stem(g, p0, p1, p2, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    for x, y in pts:
        _px(g, x, y, "h")
        _px(g, x + 1, y, "g")
    return pts


def _pot(g, cx, top, w, h):
    rim_h = 2
    half = w // 2
    _hspan(g, cx - half - 1, cx + half + 1, top, "o")
    _hspan(g, cx - half - 1, cx + half + 1, top + 1, "o")
    body_h = h - rim_h
    for i in range(body_h):
        y = top + rim_h + i
        shrink = (i * (w // 5 + 1)) // max(1, body_h)
        _hspan(g, cx - half + shrink, cx + half - shrink, y, "o")
    # top-left light, bottom-right shade
    for i in range(body_h):
        y = top + rim_h + i
        shrink = (i * (w // 5 + 1)) // max(1, body_h)
        _px(g, cx - half + shrink + 1, y, "t")
        _px(g, cx + half - shrink - 1, y, "m")
        _px(g, cx + half - shrink - 2, y, "m")
    _px(g, cx - half, top, "t")
    # '@' ribbon accent tied around the pot body
    ry = top + rim_h + body_h // 2
    for dy in (0, 1):
        i = ry + dy - top - rim_h
        shrink = (i * (w // 5 + 1)) // max(1, body_h)
        _hspan(g, cx - half + shrink, cx + half - shrink, ry + dy, "@")


def _bloom_full(g, cx, cy, r):
    pr = max(2.0, r * 0.55)
    for i in range(6):
        ang = -math.pi / 2 + i * math.pi / 3
        px_ = cx + math.cos(ang) * r * 0.62
        py_ = cy + math.sin(ang) * r * 0.58
        _ellipse(g, px_, py_, pr, pr * 0.9, "p")
    _ellipse(g, cx, cy, max(1.5, r * 0.42), max(1.5, r * 0.40), "y")


def _bloom_up(g, cx, cy, r):
    # Petals fanned across the top half: the bloom looks turned up.
    pr = max(2.0, r * 0.55)
    for i in range(5):
        ang = -math.pi * (0.08 + 0.84 * i / 4)
        px_ = cx + math.cos(ang) * r * 0.68
        py_ = cy + math.sin(ang) * r * 0.66
        _ellipse(g, px_, py_, pr, pr, "p")
    _ellipse(g, cx, cy, max(2.0, r * 0.5), max(1.5, r * 0.4), "y")


def _bloom_closed(g, cx, cy, r, tilt=0):
    # Folded petals hanging off the drooping stem tip: a teardrop that
    # leans with the droop, sepals at its base against the stem.
    rr = max(2.0, r * 0.62)
    _ellipse(g, cx + tilt * 2, cy + rr * 0.6, rr * 0.75, rr, "p")
    _ellipse(g, cx + tilt * 3, cy + rr * 1.2, rr * 0.45, rr * 0.55, "p")
    _ellipse(g, cx + tilt, cy + rr * 0.05, rr * 0.45, rr * 0.35, "g")


def _bloom_bud(g, cx, cy, r):
    rr = max(2.0, r * 0.6)
    _ellipse(g, cx, cy, rr * 0.75, rr, "p")
    _ellipse(g, cx, cy + rr * 0.6, rr * 0.7, rr * 0.5, "g")


def _sprout_tip(g, cx, cy):
    _leaf(g, cx - 1, cy, -1, -0.45, 6, 1.6, "h")
    _leaf(g, cx + 2, cy, 1, -0.45, 6, 1.6, "h")
    _px(g, cx, cy - 1, "g")
    _px(g, cx + 1, cy - 1, "g")


# Convert every painted pixel that borders transparency into the shared
# 'k' outline, mirroring the hand-drawn cat's edge treatment.
def _outline(g):
    edges = []
    for y in range(GRID):
        for x in range(GRID):
            if g[y][x] == ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or nx >= GRID or ny < 0 or ny >= GRID or g[ny][nx] == ".":
                    edges.append((x, y))
                    break
    for x, y in edges:
        g[y][x] = "k"


def _rows(g):
    return ["".join(r) for r in g]


# Per-stage proportions: pot width/height, stem length, bloom radius,
# and how many leaf pairs sprout from the stem.
STAGE_PARAMS = [
    (12, 7, 5, 0, 1),   # Sprout
    (14, 8, 9, 3, 1),   # Seedling
    (16, 9, 13, 5, 2),  # Bud
    (18, 10, 15, 7, 2),  # Bloom
    (20, 11, 17, 9, 3),  # Flower
    (24, 13, 20, 12, 3),  # Giant
]


def _plant(g, cx, pot_top, stem_len, bloom_r, leaves, stage,
           bend=0, droop=0, bloom_mode="stage", leaf_dy=-0.35):
    top_x = cx + bend
    top_y = pot_top - stem_len - droop
    ctrl = (cx + bend * 0.2, pot_top - stem_len * 0.55)
    pts = _stem(g, (cx, pot_top + 1), ctrl, (top_x, top_y))
    for i in range(leaves):
        t = 0.30 + 0.22 * i
        lx, ly = pts[int(t * (len(pts) - 1))]
        size = 5 + stage
        _leaf(g, lx - 1, ly, -1, leaf_dy, size, 1.7, "h")
        _leaf(g, lx + 2, ly + 1, 1, leaf_dy, size, 1.7, "g")
    if bloom_mode == "stage":
        if stage == 0:
            bloom_mode = "sprout"
        elif stage == 1:
            bloom_mode = "bud"
        elif stage == 2:
            bloom_mode = "bud"
        else:
            bloom_mode = "full"
    by = top_y - max(2, bloom_r * 0.5)
    if bloom_mode == "sprout":
        _sprout_tip(g, top_x, top_y)
    elif bloom_mode == "bud":
        _bloom_bud(g, top_x, top_y - 2, max(4, bloom_r))
    elif bloom_mode == "full":
        _bloom_full(g, top_x, by, bloom_r)
    elif bloom_mode == "up":
        _bloom_up(g, top_x, by, max(4, bloom_r))
    elif bloom_mode == "closed":
        _bloom_closed(g, top_x, top_y, max(4, bloom_r), tilt=1 if bend > 0 else -1)


def _frame(stage, pose):
    pot_w, pot_h, stem_len, bloom_r, leaves = STAGE_PARAMS[stage]
    g = _grid()
    cx = 31
    # The working bounce keeps the pot on the ground and reads in the stretched
    # stem and flung leaves instead of a hop. Only a dragged plant leaves it.
    lift = 10 if pose == "drag" else 0
    pot_top = GROUND - pot_h - lift

    if pose == "jump0":
        # Happy bounce wind-up: the whole plant squashes down.
        _plant(g, cx, pot_top, max(3, stem_len - 3), bloom_r, leaves, stage,
               bend=0, leaf_dy=-0.15)
    elif pose == "jump1":
        # Airborne: stem stretched, leaves flung upward.
        _plant(g, cx, pot_top, stem_len + 2, bloom_r, leaves, stage,
               bend=0, leaf_dy=-0.6)
    elif pose in ("sleep0", "sleep1"):
        sway = 0 if pose == "sleep0" else 1
        mode = "sprout" if stage == 0 else "closed"
        _plant(g, cx, pot_top, max(4, stem_len - 2), bloom_r, leaves, stage,
               bend=3 + stage // 2 + sway, droop=-(1 + sway),
               bloom_mode=mode, leaf_dy=0.2)
    elif pose == "drag":
        # Held by the cursor: the pot's weight bends the stem sideways.
        _plant(g, cx, pot_top, stem_len, bloom_r, leaves, stage,
               bend=-(7 + stage), droop=-2, leaf_dy=0.35)
    elif pose == "hover":
        mode = "up" if stage >= 2 else ("bud" if stage == 1 else "sprout")
        _plant(g, cx, pot_top, stem_len + 1, max(4, bloom_r), leaves, stage,
               bend=0, bloom_mode=mode, leaf_dy=-0.5)
    _pot(g, cx, pot_top, pot_w, pot_h)
    _outline(g)
    if pose == "hover" and stage >= 1:
        # sparkle of delight around the raised bloom
        top_y = pot_top - stem_len - 1 - max(2, bloom_r)
        _px(g, cx - bloom_r - 5, top_y, "y")
        _px(g, cx + bloom_r + 6, top_y + 2, "y")
        _px(g, cx + 2, max(1, top_y - bloom_r - 3), "y")
    return _rows(g)


def _broken():
    # Desaturated wilted plant, glitch-sheared, deliberately no '@'.
    g = _grid()
    cx = 31
    pot_w, pot_h = 20, 11
    pot_top = GROUND - pot_h
    pts = _stem(g, (cx, pot_top + 1), (cx, pot_top - 20), (cx + 9, pot_top - 13))
    for x, y in pts:
        _px(g, x, y, "l")
        _px(g, x + 1, y, "e")
    _leaf(g, cx - 1, pot_top - 8, -1, 0.55, 7, 1.7, "e")
    _leaf(g, cx + 1, pot_top - 12, -1, 0.35, 6, 1.5, "l")
    # wilted gray bloom hanging off the stem tip, petal tips sagging
    tipx, tipy = pts[-1]
    _ellipse(g, tipx + 2, tipy + 4, 4.5, 6, "l")
    _ellipse(g, tipx + 3, tipy + 7, 2.5, 3.5, "e")
    _ellipse(g, tipx + 1, tipy + 1, 2.5, 2, "e")
    half = pot_w // 2
    for i in range(pot_h):
        y = pot_top + i
        shrink = 0 if i < 2 else (i * 3) // pot_h
        _hspan(g, cx - half + shrink, cx + half - shrink, y, "l")
        _px(g, cx + half - shrink, y, "e")
        _px(g, cx + half - shrink - 1, y, "e")
    _outline(g)
    rows = _rows(g)
    # glitch shear bands through stem and bloom (the pot stays intact)
    # plus stray dropout pixels, echoing the cat's broken frame
    for band, shift in ((pot_top - 16, 3), (pot_top - 7, -3)):
        for y in (band, band + 1):
            if 0 <= y < GRID:
                r = rows[y]
                rows[y] = ("." * shift + r[:-shift]) if shift > 0 else (r[-shift:] + "." * -shift)
    for x, y in ((12, 14), (50, 20), (18, 44), (46, 52), (26, 8)):
        r = rows[y]
        rows[y] = r[:x] + "d" + r[x + 1:]
    return rows


_STAGES = [
    ([_frame(s, "jump0"), _frame(s, "jump1")],
     [_frame(s, "sleep0"), _frame(s, "sleep1")],
     _frame(s, "drag"),
     _frame(s, "hover"))
    for s in range(6)
]

FLOWER = {
    "id": "flower",
    "name": "Flower",
    "stage_names": ['Sprout', 'Seedling', 'Bud', 'Bloom', 'Flower', 'Giant'],
    "stages": _STAGES,
    "broken": [_broken()],
}
