#!/usr/bin/env python3
# Key click sounds of tablet-keyboard (Main.qml, option "sound"), iPad-like:
#   key.wav      letters, digits, symbols: a short bright tick
#   delete.wav   backspace: a slightly lower, softer tick
#   modifier.wav space, return, shift, globe, 123: a duller, rounder tock
# Standard library only. Run it again after changing a sound.
import math
import os
import sys
import random
import struct
import wave

RATE = 44100
# output directory: the first argument, else next to this script
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))


def tick(freq, seconds, decay, noise, seed):
    rnd = random.Random(seed)
    out = []
    for i in range(int(RATE * seconds)):
        t = i / RATE
        env = min(1.0, t / 0.0008) * math.exp(-t / decay)
        tone = math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(2 * math.pi * freq * 2.7 * t)
        out.append(env * ((1 - noise) * tone + noise * (rnd.random() * 2 - 1)))
    return out


def save(name, samples, gain):
    peak = max(abs(s) for s in samples) or 1.0
    with wave.open(os.path.join(DIR, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * gain * s / peak)) for s in samples))


save("key.wav", tick(3400, 0.035, 0.006, 0.55, 1), 0.5)
save("delete.wav", tick(2600, 0.04, 0.007, 0.5, 2), 0.45)
save("modifier.wav", tick(1500, 0.05, 0.009, 0.35, 3), 0.5)
