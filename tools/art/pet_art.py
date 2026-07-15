#!/usr/bin/env python3
"""Design tool for claude-cat 64x64 desktop-pet pixel art.

Each frame is a 64x64 grid of palette characters: '.' is transparent,
'@' is the model-family accent placeholder, every other character must
resolve through the shared PALETTE below (the single source of truth,
emitted into Sources/ClaudeCatPet/Art/PetPaletteData.swift).

The 16x16 menu-bar art pipeline (Sources/ClaudeCatApp/CreatureArtData.swift)
is a separate, untouched tool.

Usage:
  python3 tools/art/pet_art.py check
  python3 tools/art/pet_art.py preview <creature-id> --out <dir>
  python3 tools/art/pet_art.py emit [--creature <id>]
  python3 tools/art/pet_art.py selftest

Validation rules mirror Sources/ClaudeCatPet/PetArtValidator.swift
rule-for-rule; both validators must stay identical.
"""
import argparse
import copy
import os
import struct
import sys
import tempfile
import zlib

GRID = 64
STAGE_COUNT = 6
MIN_ANIMATION_FRAMES = 2

# Neutral gray used to preview '@' accent pixels (PetPalette.accentColor
# for the .other/nil model family).
ACCENT_PREVIEW = (142, 142, 147, 255)

# Shared palette: character -> ((r, g, b, a), human name). '.' and '@' are
# reserved and must never appear here (PetArtValidator enforces the same).
PALETTE = {
    "k": ((26, 26, 29, 255), "black outline"),
    "d": ((99, 99, 102, 255), "dark gray"),
    "e": ((142, 142, 147, 255), "mid gray"),
    "l": ((199, 199, 204, 255), "light gray"),
    "b": ((93, 64, 39, 255), "dark brown"),
    "m": ((146, 102, 57, 255), "mid brown"),
    "t": ((196, 152, 102, 255), "tan brown"),
    "c": ((243, 229, 199, 255), "cream"),
    "w": ((255, 255, 255, 255), "white"),
    "p": ((244, 166, 178, 255), "pink"),
    "n": ((216, 118, 135, 255), "rose pink"),
    "r": ((211, 64, 55, 255), "red"),
    "o": ((232, 141, 59, 255), "orange"),
    "y": ((244, 205, 80, 255), "yellow"),
    "g": ((58, 125, 68, 255), "dark green"),
    "h": ((126, 190, 101, 255), "light green"),
    "u": ((91, 141, 222, 255), "blue"),
}

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART_DIR = os.path.join(REPO_ROOT, "Sources", "ClaudeCatPet", "Art")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creatures import CREATURES  # noqa: E402


# ------------------------------------------------------------ frame helpers

def f(text):
    """Parse a frame from a multi-line string block."""
    return [r for r in text.strip("\n").split("\n")]


def alt(base, repl):
    """Frame B = frame A with some rows replaced (index -> new row)."""
    rows = list(base)
    for i, row in repl.items():
        rows[i] = row
    return rows


# -------------------------------------------------------------- validation

def frame_issues(frame, creature, location, requires_accent):
    """Mirror of PetArtValidator.frameIssues: size, palette, non-empty, accent."""
    issues = []
    if len(frame) != GRID:
        issues.append(f"{creature} {location}: expected {GRID} rows, found {len(frame)}")
    has_visible = False
    has_accent = False
    for row_index, row in enumerate(frame):
        if len(row) != GRID:
            issues.append(f"{creature} {location} row {row_index}: expected {GRID} chars, found {len(row)}")
        unknown = set()
        for ch in row:
            if ch == ".":
                continue
            has_visible = True
            if ch == "@":
                has_accent = True
            elif ch not in PALETTE:
                unknown.add(ch)
        for ch in sorted(unknown):
            issues.append(f"{creature} {location} row {row_index}: character '{ch}' not in palette")
    if not has_visible:
        issues.append(f"{creature} {location}: empty frame, no non-transparent pixels")
    if requires_accent and not has_accent:
        issues.append(f"{creature} {location}: missing '@' accent pixel")
    return issues


def palette_issues():
    """Mirror of PetArtValidator's reserved-key palette check."""
    issues = []
    for reserved in (".", "@"):
        if reserved in PALETTE:
            issues.append(f"palette: reserved character '{reserved}' must not be defined in colors")
    return issues


def creature_issues(c):
    """Mirror of PetArtValidator.issues for one creature dict."""
    issues = []
    cid = c["id"]
    if len(c["stages"]) != STAGE_COUNT:
        issues.append(f"{cid}: expected {STAGE_COUNT} stages, found {len(c['stages'])}")
    for stage_index, (jump, sleep, drag, hover) in enumerate(c["stages"]):
        location = f"stage {stage_index}"
        if len(jump) < MIN_ANIMATION_FRAMES:
            issues.append(f"{cid} {location}: jump needs at least {MIN_ANIMATION_FRAMES} frames, found {len(jump)}")
        if len(sleep) < MIN_ANIMATION_FRAMES:
            issues.append(f"{cid} {location}: sleep needs at least {MIN_ANIMATION_FRAMES} frames, found {len(sleep)}")
        for frame_index, frame in enumerate(jump):
            issues += frame_issues(frame, cid, f"{location} jump frame {frame_index}", True)
        for frame_index, frame in enumerate(sleep):
            issues += frame_issues(frame, cid, f"{location} sleep frame {frame_index}", True)
        issues += frame_issues(drag, cid, f"{location} drag frame", True)
        issues += frame_issues(hover, cid, f"{location} hover frame", True)
    if not c["broken"]:
        issues.append(f"{cid}: broken needs at least 1 frame, found 0")
    # Broken frames are exempt from the accent rule: a broken pet
    # deliberately shows no model-family color.
    for frame_index, frame in enumerate(c["broken"]):
        issues += frame_issues(frame, cid, f"broken frame {frame_index}", False)
    return issues


def check(creatures):
    issues = palette_issues()
    for c in creatures:
        issues += creature_issues(c)
    if issues:
        for issue in issues:
            print(issue)
        return False
    print("OK")
    return True


# -------------------------------------------------------------- PNG writer

def write_png(path, width, height, pixels):
    """Write an 8-bit RGBA PNG (filter type 0 only) using zlib + struct."""
    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw))))
        fh.write(chunk(b"IEND", b""))


def frame_pixels(frame, scale):
    """Render a frame to flat RGBA bytes with nearest-neighbor upscale."""
    size = GRID * scale
    pixels = bytearray(size * size * 4)
    for y, row in enumerate(frame):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            rgba = ACCENT_PREVIEW if ch == "@" else PALETTE[ch][0]
            for dy in range(scale):
                base = ((y * scale + dy) * size + x * scale) * 4
                for dx in range(scale):
                    pixels[base + dx * 4:base + dx * 4 + 4] = bytes(rgba)
    return pixels


def preview(c, out_dir, scale=4):
    """Write one PNG per frame plus a contact sheet (stage rows, state columns)."""
    os.makedirs(out_dir, exist_ok=True)
    cell = GRID * scale
    gutter = 2 * scale
    # Sheet layout: rows 0..5 are stages, row 6 holds the broken frames.
    stage_cells = []
    for stage_index, (jump, sleep, drag, hover) in enumerate(c["stages"]):
        cells = []
        for i, frame in enumerate(jump):
            cells.append((f"stage{stage_index}-jump{i}.png", frame))
        for i, frame in enumerate(sleep):
            cells.append((f"stage{stage_index}-sleep{i}.png", frame))
        cells.append((f"stage{stage_index}-drag.png", drag))
        cells.append((f"stage{stage_index}-hover.png", hover))
        stage_cells.append(cells)
    stage_cells.append([(f"broken{i}.png", frame) for i, frame in enumerate(c["broken"])])
    columns = max(len(cells) for cells in stage_cells)
    sheet_w = columns * cell + (columns + 1) * gutter
    sheet_h = len(stage_cells) * cell + (len(stage_cells) + 1) * gutter
    sheet = bytearray(sheet_w * sheet_h * 4)
    for row_index, cells in enumerate(stage_cells):
        for col_index, (name, frame) in enumerate(cells):
            pixels = frame_pixels(frame, scale)
            write_png(os.path.join(out_dir, name), cell, cell, pixels)
            ox = gutter + col_index * (cell + gutter)
            oy = gutter + row_index * (cell + gutter)
            for y in range(cell):
                src = y * cell * 4
                dst = ((oy + y) * sheet_w + ox) * 4
                sheet[dst:dst + cell * 4] = pixels[src:src + cell * 4]
    write_png(os.path.join(out_dir, "sheet.png"), sheet_w, sheet_h, sheet)


# ------------------------------------------------------------------- emit

def swift_frame_lines(rows, indent):
    """Format a frame as a PetFrame literal, rows grouped 4 per line."""
    lines = [indent + "PetFrame(rows: ["]
    for i in range(0, GRID, 4):
        group = ", ".join(f'"{r}"' for r in rows[i:i + 4])
        tail = "," if i + 4 < GRID else ""
        lines.append(indent + "    " + group + tail)
    lines.append(indent + "])")
    return lines


def swift_frame_list_lines(frames, indent):
    lines = []
    for i, frame in enumerate(frames):
        block = swift_frame_lines(frame, indent)
        if i < len(frames) - 1:
            block[-1] += ","
        lines += block
    return lines


HEADER = "// GENERATED by tools/art/pet_art.py — do not edit."


def emit_palette_file():
    out = [HEADER]
    out.append("// Shared standard palette for all 64x64 pet creature art. '.' (transparent)")
    out.append("// and '@' (accent placeholder) are reserved and deliberately absent.")
    out.append("")
    out.append("extension PetPalette {")
    out.append("    public static let standard = PetPalette(colors: [")
    for i, (ch, ((r, g, b, a), name)) in enumerate(PALETTE.items()):
        tail = "," if i < len(PALETTE) - 1 else ""
        out.append(f'        "{ch}": PetColor(r: {r}, g: {g}, b: {b}, a: {a}){tail} // {name}')
    out.append("    ])")
    out.append("}")
    out.append("")
    path = os.path.join(ART_DIR, "PetPaletteData.swift")
    os.makedirs(ART_DIR, exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    return path


def emit_creature_file(c):
    out = [HEADER]
    out.append(f"// 64x64 palette-map pet art for the {c['name']} creature.")
    out.append("")
    out.append("extension PetCreatureArt {")
    out.append(f"    static let {c['id']} = PetCreatureArt(")
    out.append(f"        id: \"{c['id']}\",")
    out.append(f"        displayName: \"{c['name']}\",")
    out.append("        stages: [")
    for stage_index, (jump, sleep, drag, hover) in enumerate(c["stages"]):
        out.append(f"            // Stage {stage_index}: {c['stage_names'][stage_index]}")
        out.append("            PetStageSprites(")
        out.append("                jump: [")
        out += swift_frame_list_lines(jump, "                    ")
        out.append("                ],")
        out.append("                sleep: [")
        out += swift_frame_list_lines(sleep, "                    ")
        out.append("                ],")
        drag_lines = swift_frame_lines(drag, "                ")
        drag_lines[0] = "                drag: " + drag_lines[0].strip()
        drag_lines[-1] += ","
        out += drag_lines
        hover_lines = swift_frame_lines(hover, "                ")
        hover_lines[0] = "                hover: " + hover_lines[0].strip()
        out += hover_lines
        tail = "," if stage_index < len(c["stages"]) - 1 else ""
        out.append(f"            ){tail}")
    out.append("        ],")
    out.append("        broken: [")
    out += swift_frame_list_lines(c["broken"], "            ")
    out.append("        ]")
    out.append("    )")
    out.append("}")
    out.append("")
    name = c["name"].replace(" ", "")
    path = os.path.join(ART_DIR, f"PetArt{name}.swift")
    os.makedirs(ART_DIR, exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    return path


# Determinism note: the CI gate requires an empty `git diff` after re-emit,
# which assumes byte-identical output. Procedural creatures (e.g. flower) use
# libm trig (math.sin/cos), whose results are not guaranteed bit-identical
# across platforms/libc. Always re-emit on the reference platform (Linux CI)
# so the committed Swift art stays stable.
def emit(creature_id=None):
    if not check(CREATURES):
        print("emit refused: check failed", file=sys.stderr)
        return False
    # The palette file is regenerated on EVERY run; --creature filters
    # only the per-creature files.
    print(f"wrote {emit_palette_file()}")
    targets = CREATURES
    if creature_id is not None:
        targets = [c for c in CREATURES if c["id"] == creature_id]
        if not targets:
            print(f"emit: unknown creature '{creature_id}'", file=sys.stderr)
            return False
    for c in targets:
        print(f"wrote {emit_creature_file(c)}")
    return True


# ---------------------------------------------------------- sample creature

def _sample_frame(width, height, lift=0, accent=True, fill="o"):
    """Draw a centered outlined blob sitting near the bottom of the grid."""
    rows = [["."] * GRID for _ in range(GRID)]
    x0 = (GRID - width) // 2
    y1 = GRID - 4 - lift
    y0 = y1 - height + 1
    for y in range(y0, y1 + 1):
        for x in range(x0, x0 + width):
            edge = y in (y0, y1) or x in (x0, x0 + width - 1)
            rows[y][x] = "k" if edge else fill
    if accent:
        rows[y0 + 2][x0 + 2] = "@"
    return ["".join(r) for r in rows]


def build_sample():
    """Built-in tiny sample creature used by selftest and preview."""
    stages = []
    stage_names = []
    for s in range(STAGE_COUNT):
        size = 14 + s * 6
        jump = [_sample_frame(size, size), _sample_frame(size, size, lift=3)]
        sleep = [_sample_frame(size, size), _sample_frame(size, size - 2)]
        drag = _sample_frame(size, size, lift=1)
        hover = _sample_frame(size, size, fill="y")
        stages.append((jump, sleep, drag, hover))
        stage_names.append(f"Size{s}")
    broken = [_sample_frame(20, 12, accent=False, fill="e")]
    return {
        "id": "sample",
        "name": "Sample",
        "stage_names": stage_names,
        "stages": stages,
        "broken": broken,
    }


# ---------------------------------------------------------------- selftest

def selftest():
    ok = True
    sample = build_sample()
    issues = palette_issues() + creature_issues(sample)
    if issues:
        ok = False
        print("selftest FAIL: valid sample reported issues:")
        for issue in issues:
            print("  " + issue)
    else:
        print("selftest: valid sample passes")
    # Corrupt one frame: an unknown character and a short row, both of
    # which must be reported with frame coordinates (stage/state/frame/row).
    corrupt = copy.deepcopy(sample)
    jump = corrupt["stages"][0][0]
    frame = list(jump[1])
    frame[10] = frame[10][:5] + "Z" + frame[10][6:]
    frame[20] = frame[20][:GRID - 1]
    jump[1] = frame
    corrupt_issues = creature_issues(corrupt)
    expected = [
        "sample stage 0 jump frame 1 row 10: character 'Z' not in palette",
        f"sample stage 0 jump frame 1 row 20: expected {GRID} chars, found {GRID - 1}",
    ]
    for message in expected:
        if message in corrupt_issues:
            print(f"selftest: corrupted sample rejected: {message}")
        else:
            ok = False
            print(f"selftest FAIL: missing expected issue: {message}")
            for issue in corrupt_issues:
                print("  got: " + issue)
    # PNG writer: every emitted file must start with the PNG signature.
    out_dir = tempfile.mkdtemp(prefix="pet-art-selftest-")
    preview(sample, out_dir)
    names = sorted(os.listdir(out_dir))
    if "sheet.png" not in names:
        ok = False
        print("selftest FAIL: sheet.png not written")
    for name in names:
        with open(os.path.join(out_dir, name), "rb") as fh:
            if fh.read(8) != b"\x89PNG\r\n\x1a\n":
                ok = False
                print(f"selftest FAIL: {name} lacks PNG signature")
    if ok:
        print(f"selftest: {len(names)} PNGs written to {out_dir} with valid signatures")
        print("selftest OK")
    return ok


# --------------------------------------------------------------------- CLI

def main(argv):
    parser = argparse.ArgumentParser(description="claude-cat 64x64 pet art tool")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    p_preview = sub.add_parser("preview")
    p_preview.add_argument("creature")
    p_preview.add_argument("--out", required=True)
    p_emit = sub.add_parser("emit")
    p_emit.add_argument("--creature")
    sub.add_parser("selftest")
    args = parser.parse_args(argv)

    if args.command == "check":
        return 0 if check(CREATURES) else 1
    if args.command == "preview":
        creature = next((c for c in CREATURES if c["id"] == args.creature), None)
        if creature is None and args.creature == "sample":
            creature = build_sample()
        if creature is None:
            print(f"preview: unknown creature '{args.creature}'", file=sys.stderr)
            return 1
        preview(creature, args.out)
        print(f"wrote previews to {args.out}")
        return 0
    if args.command == "emit":
        return 0 if emit(args.creature) else 1
    if args.command == "selftest":
        return 0 if selftest() else 1
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
