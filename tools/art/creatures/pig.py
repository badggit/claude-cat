"""64x64 pet art for the Pig creature (pink pig).

Six growth stages (Piglet -> Prize Hog), each with a jump pair (crouch +
bouncy airborne hop), a two-frame sleep pair (flopped on its side,
breathing), a drag frame (held up facing the viewer with dangling
trotters), and a hover frame (sitting up, ears perked, snout raised),
plus one shared broken frame (desaturated, glitch-sheared, deliberately
without the '@' accent). Style matches the approved cat: one top-left
light source, shared 'k' outline, '@' collar in every non-broken frame,
and a readable curly tail.

Frames are composed procedurally from small drawing helpers so each
pose stays consistent across the six stages.
"""
import math

GRID = 64
GROUND = 60

BODY_COLORS = ("p", "n", "c", "w")


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


def _rect(g, x0, y0, x1, y1, ch):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            _px(g, x, y, ch)


# Thick stroke along a direction, used for angled airborne legs and ears.
def _stroke(g, x0, y0, dx, dy, length, width, ch):
    for i in range(length):
        _ellipse(g, x0 + dx * i, y0 + dy * i, width, width, ch)


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


# Per-stage proportions: body rx/ry, head radius, standing leg height.
STAGE_PARAMS = [
    (9, 6, 4, 4),    # Piglet
    (11, 7, 5, 5),   # Skinny
    (13, 9, 6, 5),   # Normal
    (16, 11, 7, 5),  # Plump
    (19, 13, 8, 6),  # Fat
    (22, 16, 9, 6),  # Prize Hog
]


def _curly_tail(g, x0, y0, scale, ch="p"):
    # A small spiral of thick dots off the rump: the signature curl.
    curl = [(0, 0), (1.5, -1.5), (3, -2), (4.5, -1.5), (5, 0), (3.5, 1), (2.5, 0.5)]
    for i, (dx, dy) in enumerate(curl):
        r = 1.4 if i < 5 else 1.0
        _ellipse(g, x0 + dx * scale, y0 + dy * scale, r, r, ch)
    _px(g, x0 + 3 * scale, y0 - 0.5 * scale, "n")


def _ear_side(g, x0, y0, dx, size, perked=False):
    dy = -1.0 if perked else -0.6
    for i in range(size):
        t = 1 - i / size
        _ellipse(g, x0 + dx * i * 0.7, y0 + dy * i, 1.6 * t + 0.4, 1.4 * t + 0.4, "p")
    _px(g, x0 + dx, y0 - 1, "n")


def _head_side(g, hx, hy, hr, eye="open", perked=False):
    _ellipse(g, hx, hy, hr, hr * 0.95, "p")
    _ellipse(g, hx + hr * 0.4, hy + hr * 0.4, hr * 0.5, hr * 0.4, "n")
    _ellipse(g, hx + hr * 0.4, hy + hr * 0.4, hr * 0.45, hr * 0.35, "p")
    # snout sticking out to the left
    sx, sy = hx - hr - 1, hy + (0 if perked else 1) - (2 if perked else 0)
    _ellipse(g, sx, sy, hr * 0.42 + 1, hr * 0.36 + 1, "n")
    _px(g, sx - 1, sy, "k")
    _px(g, sx + 1, sy, "k")
    # ears on top: near ear leans forward, far ear behind
    _ear_side(g, hx - hr * 0.45, hy - hr * 0.8, -0.6, max(3, int(hr * 0.7)), perked)
    _ear_side(g, hx + hr * 0.45, hy - hr * 0.85, 0.6, max(3, int(hr * 0.7)), perked)
    if eye == "open":
        _px(g, hx - hr * 0.45, hy - hr * 0.25, "k")
        _px(g, hx - hr * 0.45, hy - hr * 0.25 - 1, "k")
    else:
        _px(g, hx - hr * 0.55, hy - hr * 0.2, "k")
        _px(g, hx - hr * 0.55 + 1, hy - hr * 0.2, "k")


def _body_side(g, cx, cy, rx, ry):
    _ellipse(g, cx, cy, rx, ry, "p")
    _ellipse(g, cx + rx * 0.45, cy + ry * 0.35, rx * 0.5, ry * 0.55, "n")
    _ellipse(g, cx + rx * 0.35, cy + ry * 0.25, rx * 0.5, ry * 0.5, "p")
    _ellipse(g, cx - rx * 0.15, cy + ry * 0.5, rx * 0.5, ry * 0.4, "c")


def _leg(g, x, top, h, ch="p"):
    _rect(g, x, top, x + 2, top + h, ch)
    _rect(g, x, top + h - 1, x + 2, top + h, "b")


def _collar_band(g, x, y0, y1):
    for xx in (x, x + 1):
        for y in range(int(y0), int(y1) + 1):
            if g[y][int(xx)] in BODY_COLORS:
                g[y][int(xx)] = "@"


def _standing(g, stage, crouch=False):
    rx, ry, hr, lh = STAGE_PARAMS[stage]
    if crouch:
        lh = max(2, lh - 2)
    cx = 34
    cy = GROUND - lh - ry + 1
    _leg(g, cx - rx * 0.7, cy + ry - 2, lh + 1)
    _leg(g, cx + rx * 0.55, cy + ry - 2, lh + 1)
    _body_side(g, cx, cy, rx, ry)
    _leg(g, cx - rx * 0.35, cy + ry - 2, lh + 1)
    _leg(g, cx + rx * 0.2, cy + ry - 2, lh + 1)
    _curly_tail(g, cx + rx, cy - ry * 0.35, 0.8 + stage * 0.12)
    hx = cx - rx - hr * 0.25
    hy = cy - ry * 0.35 + (2 if crouch else 0)
    _head_side(g, hx, hy, hr)
    _outline(g)
    _collar_band(g, hx + hr, hy - hr * 0.5, hy + hr)


def _airborne(g, stage):
    rx, ry, hr, _ = STAGE_PARAMS[stage]
    cx = 34
    # Lifted just enough for the flung trotters to reach the ground line rather
    # than clear it: the working pig bounces in place instead of leaping.
    cy = GROUND - ry - 3
    # legs flung: front pair reaching forward-down, rear pair kicked back
    _stroke(g, cx - rx * 0.6, cy + ry - 2, -0.45, 0.9, 5, 1.2, "p")
    _stroke(g, cx - rx * 0.25, cy + ry - 1, -0.35, 0.9, 5, 1.2, "p")
    _stroke(g, cx + rx * 0.35, cy + ry - 2, 0.55, 0.75, 5, 1.2, "p")
    _stroke(g, cx + rx * 0.65, cy + ry - 3, 0.65, 0.65, 5, 1.2, "p")
    for lx, ly, ddx, ddy in ((cx - rx * 0.6, cy + ry - 2, -0.45, 0.9),
                             (cx - rx * 0.25, cy + ry - 1, -0.35, 0.9),
                             (cx + rx * 0.35, cy + ry - 2, 0.55, 0.75),
                             (cx + rx * 0.65, cy + ry - 3, 0.65, 0.65)):
        _ellipse(g, lx + ddx * 4, ly + ddy * 4, 1.3, 1.3, "b")
    _body_side(g, cx, cy, rx, ry)
    _curly_tail(g, cx + rx, cy - ry * 0.4, 0.8 + stage * 0.12)
    hx = cx - rx - hr * 0.25
    hy = cy - ry * 0.5
    _head_side(g, hx, hy, hr, perked=True)
    _outline(g)
    _collar_band(g, hx + hr, hy - hr * 0.5, hy + hr)


def _sleeping(g, stage, breathe=0):
    rx, ry, hr, _ = STAGE_PARAMS[stage]
    brx = rx * 1.1
    bry = ry * 0.8 + breathe
    cx = 35
    cy = GROUND - bry + 1
    # trotters sticking out to the left, relaxed
    _stroke(g, cx - brx * 0.7, cy + bry * 0.15, -1, 0.25, 7, 1.3, "p")
    _stroke(g, cx - brx * 0.6, cy + bry * 0.55, -1, 0.12, 6, 1.3, "p")
    _ellipse(g, cx - brx * 0.7 - 6, cy + bry * 0.15 + 2, 1.3, 1.3, "b")
    _ellipse(g, cx - brx * 0.6 - 5, cy + bry * 0.55 + 1, 1.3, 1.3, "b")
    _ellipse(g, cx, cy, brx, bry, "p")
    _ellipse(g, cx + brx * 0.4, cy + bry * 0.4, brx * 0.5, bry * 0.5, "n")
    _ellipse(g, cx + brx * 0.32, cy + bry * 0.3, brx * 0.5, bry * 0.45, "p")
    _curly_tail(g, cx + brx, cy - bry * 0.1, 0.7 + stage * 0.1)
    # head resting on the ground against the body's left side
    hx = cx - brx - hr * 0.3
    hy = GROUND - hr + 1
    _head_side(g, hx, hy, hr, eye="closed")
    _outline(g)
    _collar_band(g, hx + hr, hy - hr * 0.4, hy + hr)


def _front_pig(g, stage, pose):
    # Facing the viewer: used for both the drag and hover poses.
    rx, ry, hr, lh = STAGE_PARAMS[stage]
    hfr = hr * 1.25
    brx = rx * 0.62
    bry = ry * 0.9
    cx = 31
    if pose == "drag":
        by = 34 + bry * 0.2
    else:
        by = GROUND - bry - lh + 3
    hy = by - bry - hfr * 0.55
    # ears: perked straight up when hovering, relaxed diagonal when dragged
    edy = -1.1 if pose == "hover" else -0.75
    for sx in (-1, 1):
        ex = cx + sx * hfr * 0.62
        for i in range(max(4, int(hfr * 0.75))):
            t = 1 - i / max(4, int(hfr * 0.75))
            _ellipse(g, ex + sx * i * 0.35, hy - hfr * 0.6 + edy * i,
                     1.7 * t + 0.5, 1.5 * t + 0.5, "p")
        _px(g, ex + sx, hy - hfr * 0.6 + edy, "n")
    if pose == "drag":
        # dangling trotters, splayed like the held cat's paws
        if stage <= 1:
            spots = (cx - brx * 0.75, cx + brx * 0.35)
        else:
            spots = (cx - brx * 0.85, cx - brx * 0.3, cx + brx * 0.25, cx + brx * 0.65)
        for lx in spots:
            _rect(g, lx, by + bry - 2, lx + 2, by + bry + lh + 2, "p")
            _rect(g, lx, by + bry + lh + 1, lx + 2, by + bry + lh + 2, "b")
    else:
        # sitting: front trotters planted in front of the belly
        for lx in (cx - brx * 0.75, cx + brx * 0.45):
            _rect(g, lx, by + bry - lh + 1, lx + 2, by + bry - 1, "p")
            _rect(g, lx, by + bry - 2, lx + 2, by + bry - 1, "b")
    _ellipse(g, cx, by, brx, bry, "p")
    _ellipse(g, cx + brx * 0.4, by + bry * 0.3, brx * 0.5, bry * 0.5, "n")
    _ellipse(g, cx + brx * 0.3, by + bry * 0.25, brx * 0.45, bry * 0.45, "p")
    _ellipse(g, cx, by + bry * 0.3, brx * 0.6, bry * 0.5, "c")
    # head
    _ellipse(g, cx, hy, hfr, hfr * 0.9, "p")
    _ellipse(g, cx + hfr * 0.4, hy + hfr * 0.35, hfr * 0.4, hfr * 0.35, "n")
    _ellipse(g, cx + hfr * 0.35, hy + hfr * 0.3, hfr * 0.35, hfr * 0.3, "p")
    # snout: raised toward the top of the face when hovering
    sy = hy + (hfr * 0.25 if pose == "drag" else -hfr * 0.05)
    _ellipse(g, cx, sy, hfr * 0.42, hfr * 0.3, "n")
    _px(g, cx - 1, sy, "k")
    _px(g, cx + 1, sy, "k")
    ey = hy - hfr * 0.35 if pose == "drag" else hy - hfr * 0.45
    _px(g, cx - hfr * 0.5, ey, "k")
    _px(g, cx + hfr * 0.5, ey, "k")
    _outline(g)
    # '@' collar band around the neck
    ny = by - bry
    for y in (ny, ny + 1):
        for x in range(int(cx - brx), int(cx + brx) + 1):
            if g[int(y)][x] in BODY_COLORS:
                g[int(y)][x] = "@"


def _frame(stage, pose):
    g = _grid()
    if pose == "jump0":
        _standing(g, stage, crouch=True)
    elif pose == "jump1":
        _airborne(g, stage)
    elif pose == "sleep0":
        _sleeping(g, stage, breathe=0)
    elif pose == "sleep1":
        _sleeping(g, stage, breathe=1)
    elif pose in ("drag", "hover"):
        _front_pig(g, stage, pose)
    return _rows(g)


def _broken():
    # Desaturated slumped pig, glitch-sheared, deliberately no '@'.
    g = _grid()
    rx, ry, hr, _ = STAGE_PARAMS[2]
    cx = 36
    # slumped haunches: a tall rump the pig has sagged back onto
    _ellipse(g, cx, GROUND - ry * 1.1, rx * 0.85, ry * 1.15, "l")
    _ellipse(g, cx + rx * 0.35, GROUND - ry * 0.7, rx * 0.45, ry * 0.7, "e")
    # head hanging low in front of the slumped body, ears drooping
    hx = cx - rx - hr * 0.4
    hy = GROUND - hr - 1
    _ellipse(g, hx, hy, hr, hr * 0.95, "l")
    _ellipse(g, hx - hr - 1, hy + 2, hr * 0.42 + 1, hr * 0.36 + 1, "e")
    for sx in (-0.6, 0.6):
        _stroke(g, hx + sx * hr * 0.5, hy - hr * 0.8, sx, 0.6, 4, 1.2, "l")
    _px(g, hx - hr * 0.45, hy - hr * 0.1, "d")
    # front legs folded flat on the ground under the chest
    _stroke(g, hx + hr * 0.8, GROUND - 1, 1, 0, 5, 1.2, "e")
    # limp gray tail, no curl left in it
    _stroke(g, cx + rx * 0.8, GROUND - ry * 1.4, 0.8, 0.5, 5, 1.1, "e")
    _outline(g)
    rows = _rows(g)
    # glitch shear bands through the body plus stray dropout pixels,
    # echoing the cat's broken frame
    for band, shift in ((GROUND - int(ry * 1.6), 3), (GROUND - int(ry * 0.7), -3)):
        for y in (band, band + 1):
            if 0 <= y < GRID:
                r = rows[y]
                rows[y] = ("." * shift + r[:-shift]) if shift > 0 else (r[-shift:] + "." * -shift)
    for x, y in ((14, 12), (48, 18), (20, 42), (44, 50), (30, 6)):
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

PIG = {
    "id": "pig",
    "name": "Pig",
    "stage_names": ['Piglet', 'Skinny', 'Normal', 'Plump', 'Fat', 'Prize Hog'],
    "stages": _STAGES,
    "broken": [_broken()],
}
