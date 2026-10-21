#!/usr/bin/env python3
# Synthesizes the tablet shell sounds (ModeTransition.qml, ChargeAnimation.qml, unlock) as 16-bit
# mono WAVs next to this script:
#   snap.wav        keyboard dock clicks onto the tablet (magnetic double click + thump)
#   release.wav     keyboard comes off (soft unclick, falling tone)
#   connect.wav     monitor plugged in (rising two-note chime)
#   disconnect.wav  monitor unplugged (falling two-note chime)
#   warm.wav        reading mode (soft low chord)
#   whoosh.wav      the camera flies into the screen at the end
#   charge.wav      charger plugged in (ChargeAnimation.qml): two bright rising notes
#   unlock.wav      screen unlocked: a soft click with a short upward tick
#   lock.wav        screen locked: a lower, firmer clack with a short downward tick
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


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix(base, sound, at, gain=1.0):
    start = int(RATE * at)
    if len(base) < start + len(sound):
        base.extend([0.0] * (start + len(sound) - len(base)))
    for i, v in enumerate(sound):
        base[start + i] += v * gain
    return base


def tone(freq, seconds, decay, harmonics=((1, 1.0),), attack=0.004):
    out = []
    for i in range(int(RATE * seconds)):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(env * sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics))
    return out


def click(freq, seconds=0.03, noise=0.6, seed=1):
    rnd = random.Random(seed)
    out = []
    for i in range(int(RATE * seconds)):
        t = i / RATE
        env = math.exp(-t / 0.006)
        out.append(env * ((1 - noise) * math.sin(2 * math.pi * freq * t) + noise * rnd.uniform(-1, 1)))
    return out


def sweep(f0, f1, seconds, decay):
    out, phase = [], 0.0
    n = int(RATE * seconds)
    for i in range(n):
        t = i / RATE
        f = f0 + (f1 - f0) * i / n
        phase += 2 * math.pi * f / RATE
        out.append(min(1.0, t / 0.005) * math.exp(-t / decay) * math.sin(phase))
    return out


def whoosh(seconds):
    # noise through a one-pole low-pass whose cutoff sweeps up and back, rise-and-fall envelope
    rnd = random.Random(7)
    out, y = [], 0.0
    n = int(RATE * seconds)
    for i in range(n):
        p = i / n
        cutoff = 300 + 3500 * math.sin(math.pi * p) ** 2
        a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        y += a * (rnd.uniform(-1, 1) - y)
        out.append(y * math.sin(math.pi * p) ** 1.5)
    return out


def bell(freq, seconds=0.9, decay=0.35):
    return tone(freq, seconds, decay, ((1, 1.0), (2, 0.35), (3, 0.12), (4.2, 0.05)))


def save(name, samples, gain):
    peak = max(1e-9, max(abs(v) for v in samples))
    fade = int(RATE * 0.01)
    with wave.open(os.path.join(DIR, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for i, v in enumerate(samples):
            if i >= len(samples) - fade:
                v *= (len(samples) - i) / fade
            frames += struct.pack("<h", int(max(-1, min(1, v / peak * gain)) * 32767))
        w.writeframes(bytes(frames))


snap = silence(0.25)
mix(snap, tone(110, 0.12, 0.035), 0.0, 0.9)          # thump
mix(snap, click(2400, seed=1), 0.0, 0.8)
mix(snap, click(3200, seed=2), 0.045, 0.5)           # second, lighter click
save("snap.wav", snap, 0.8)

release = silence(0.3)
mix(release, tone(90, 0.1, 0.03), 0.0, 0.6)
mix(release, click(1600, noise=0.4, seed=3), 0.0, 0.5)
mix(release, sweep(900, 450, 0.18, 0.07), 0.02, 0.5)
save("release.wav", release, 0.7)

connect = silence(1.0)
mix(connect, bell(659.25), 0.0, 0.8)                 # E5
mix(connect, bell(987.77), 0.12, 0.7)                # B5
save("connect.wav", connect, 0.6)

disconnect = silence(1.0)
mix(disconnect, bell(987.77), 0.0, 0.7)
mix(disconnect, bell(659.25), 0.12, 0.8)
save("disconnect.wav", disconnect, 0.55)

warm = silence(1.4)
for f, at in ((261.63, 0.0), (392.0, 0.06), (523.25, 0.12)):   # C4 G4 C5
    mix(warm, tone(f, 1.3, 0.5, ((1, 1.0), (2, 0.2)), attack=0.06), at, 0.6)
save("warm.wav", warm, 0.5)

save("whoosh.wav", whoosh(0.7), 0.45)

charge = silence(0.9)
mix(charge, bell(1046.5, 0.8, 0.22), 0.0, 0.7)       # C6
mix(charge, bell(1568.0, 0.8, 0.25), 0.09, 0.6)      # G6
save("charge.wav", charge, 0.5)

unlock = silence(0.2)
mix(unlock, click(2200, seconds=0.02, noise=0.5, seed=5), 0.0, 0.6)
mix(unlock, sweep(1200, 1900, 0.06, 0.025), 0.012, 0.5)
mix(unlock, click(3000, seconds=0.02, noise=0.4, seed=6), 0.05, 0.35)
save("unlock.wav", unlock, 0.55)

lock = silence(0.22)
mix(lock, click(1400, seconds=0.025, noise=0.7, seed=7), 0.0, 0.7)
mix(lock, sweep(1100, 650, 0.07, 0.03), 0.01, 0.55)
mix(lock, click(900, seconds=0.03, noise=0.5, seed=8), 0.045, 0.45)
save("lock.wav", lock, 0.6)
