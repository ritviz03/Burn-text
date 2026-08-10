#!/usr/bin/env python3
"""Draw the 1024x1024 app icon: a single flame on near-black.

Run from anywhere:

    python3 Tools/make_app_icon.py

Writes Burn/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png.

Deliberately has no alpha channel — iOS rejects app icons that carry one. Pure
stdlib, no Pillow: the flame is an implicit shape evaluated per pixel and the PNG
is encoded by hand. Deterministic, so re-running gives a byte-identical file.
"""

import math
import os
import struct
import zlib

SIZE = 1024
OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Burn",
    "Resources",
    "Assets.xcassets",
    "AppIcon.appiconset",
    "AppIcon.png",
)

# Flame geometry, in normalised 0...1 icon coordinates.
BASE_Y = 0.880
TIP_Y = 0.100
WIDTH = 0.215
# Silhouette exponents. RISE controls how quickly the base swells (low = round
# bottom), FALL how hard it tapers to the tip (high = sharp spire). One smooth
# curve rather than two joined pieces, so no corner can appear.
RISE = 0.75
FALL = 1.70
# The inner, hotter flame: narrower, and stopping short of the tip.
CORE_SCALE = 0.42
CORE_TOP = 0.62
# Sideways lean, so it reads as fire rather than a leaf.
LEAN = 0.050

BACKGROUND = (11, 9, 12)

# Flame colour from base to tip: white-hot, through ember, to a dark red edge.
STOPS = [
    (0.00, (255, 243, 208)),
    (0.28, (255, 176, 48)),
    (0.62, (241, 96, 22)),
    (1.00, (168, 32, 12)),
]


def gradient(t):
    t = min(max(t, 0.0), 1.0)
    for i in range(len(STOPS) - 1):
        t0, c0 = STOPS[i]
        t1, c1 = STOPS[i + 1]
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return tuple(c0[j] + (c1[j] - c0[j]) * k for j in range(3))
    return STOPS[-1][1]


def smoothstep(edge0, edge1, x):
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# Peak of t**RISE * (1-t)**FALL, used to normalise `shape` to a maximum of 1.
_PEAK_T = RISE / (RISE + FALL)
_PEAK = (_PEAK_T**RISE) * ((1.0 - _PEAK_T) ** FALL)


def shape(t):
    """Relative half-width, 0...1, at height `t` up the flame.

    `t**RISE * (1-t)**FALL` swells fast off the base and tapers slowly to a point,
    which is the flame profile. Smooth and single-piece, so the outline has no
    corners anywhere.
    """
    if t <= 0.0 or t >= 1.0:
        return 0.0
    return (t**RISE) * ((1.0 - t) ** FALL) / _PEAK


def main():
    height = BASE_Y - TIP_Y
    feather = 1.6 / SIZE  # antialiasing width, ~1.6px

    rows = []
    for py_i in range(SIZE):
        py = (py_i + 0.5) / SIZE

        # Everything that depends only on the row, hoisted out of the x loop.
        yn = (BASE_Y - py) / height  # 0 at the base, 1 at the tip
        if 0.0 <= yn <= 1.0:
            half = WIDTH * shape(yn)
            # A slight lean, so it reads as fire rather than a leaf. Applied to
            # the core as well, so the two stay concentric and no seam appears.
            centre = 0.5 + LEAN * (math.sin(math.pi * yn) ** 1.2) * (yn**0.4)
            colour = gradient(yn)
            core_half = (
                WIDTH * CORE_SCALE * shape(yn / CORE_TOP) if yn < CORE_TOP else -1.0
            )
            core_colour = tuple(c + (255 - c) * 0.55 for c in colour)
        else:
            half = -1.0
            centre = 0.5
            colour = core_colour = BACKGROUND
            core_half = -1.0

        row = bytearray()
        for px_i in range(SIZE):
            px = (px_i + 0.5) / SIZE
            offset = abs(px - centre)

            red, green, blue = BACKGROUND

            if half > 0.0:
                # Warm glow spilling out of the flame.
                spill = math.exp(-max(offset - half, 0.0) * 26.0)
                if spill > 0.004:
                    glow = spill * 0.34 * math.sin(math.pi * yn) ** 0.7
                    red += (255 - red) * glow * 0.55
                    green += (120 - green) * glow * 0.55
                    blue += (30 - blue) * glow * 0.55

                inside = 1.0 - smoothstep(half - feather, half + feather, offset)
                if inside > 0.0:
                    red += (colour[0] - red) * inside
                    green += (colour[1] - green) * inside
                    blue += (colour[2] - blue) * inside

                    if core_half > 0.0:
                        # A wide feather here: the core should glow into the
                        # outer flame, not sit on it as a second silhouette.
                        soft = max(core_half * 0.5, feather)
                        in_core = 1.0 - smoothstep(
                            core_half - soft, core_half + soft, offset
                        )
                        if in_core > 0.0:
                            red += (core_colour[0] - red) * in_core
                            green += (core_colour[1] - green) * in_core
                            blue += (core_colour[2] - blue) * in_core

            row += bytes(
                (
                    int(min(max(red, 0), 255)),
                    int(min(max(green, 0), 255)),
                    int(min(max(blue, 0), 255)),
                )
            )
        rows.append(bytes(row))

    write_png(OUTPUT, SIZE, SIZE, rows)
    print(f"wrote {OUTPUT} ({os.path.getsize(OUTPUT) / 1024:.0f} KiB, {SIZE}x{SIZE})")


def write_png(path, width, height, rows):
    """Minimal truecolour (RGB, no alpha) PNG encoder."""

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    # Filter type 0 (none) in front of every scanline.
    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", header))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    main()
