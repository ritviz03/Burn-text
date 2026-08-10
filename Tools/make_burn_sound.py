#!/usr/bin/env python3
"""Synthesise the placeholder burn sound: a whoosh with crackles over it.

Run from anywhere:

    python3 Tools/make_burn_sound.py

Writes Burn/Resources/burn-crackle.wav. This is a stand-in so the app has
something to play while you build it — replace it with a licensed recording
before shipping. Deterministic: the same SEED always produces the same file.
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
# Matches BurnCurve.duration so the clip fades out as the fire finishes.
DURATION = 2.2
SEED = 7

OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Burn",
    "Resources",
    "burn-crackle.wav",
)


def envelope(t):
    """Catches, roars, dies away — the same shape as the haptic curve."""
    x = t / DURATION
    attack = min(x / 0.18, 1.0)
    decay = max(1.0 - max((x - 0.55) / 0.45, 0.0), 0.0)
    return attack * decay**1.6


def main():
    random.seed(SEED)
    total = int(SAMPLE_RATE * DURATION)
    samples = [0.0] * total

    # Body: white noise through a one-pole low-pass whose cutoff opens as the
    # fire builds, so the whoosh brightens rather than only getting louder.
    low = 0.0
    for i in range(total):
        t = i / SAMPLE_RATE
        cutoff = 0.02 + 0.16 * min((t / DURATION) / 0.4, 1.0)
        low += cutoff * (random.uniform(-1.0, 1.0) - low)
        samples[i] = low * 3.2 * envelope(t)

    # Crackles: short bursts of brighter noise with an exponential decay,
    # weighted toward the middle of the burn where the fire is loudest.
    for _ in range(90):
        start = int(random.betavariate(2.0, 2.2) * total)
        length = int(SAMPLE_RATE * random.uniform(0.004, 0.030))
        level = random.uniform(0.10, 0.55) * envelope(start / SAMPLE_RATE)
        for j in range(min(length, total - start)):
            samples[start + j] += (
                random.uniform(-1.0, 1.0) * level * math.exp(-6.0 * j / length)
            )

    # Normalise, then soft-clip so nothing spikes.
    loudest = max((abs(s) for s in samples), default=1.0) or 1.0
    frames = bytearray()
    for s in samples:
        value = math.tanh(s / loudest * 1.4) * 0.85
        frames += struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32767))

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with wave.open(OUTPUT, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(bytes(frames))

    print(f"wrote {OUTPUT} ({len(frames) / 1024:.0f} KiB, {DURATION:.1f}s)")


if __name__ == "__main__":
    main()
