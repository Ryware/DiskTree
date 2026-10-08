#!/usr/bin/env python3
"""Soundtrack for headroom-promo.mp4: synthesized music bed, piper narration and click sounds.

    python3 promo/audio.py --engine kokoro --lib <dir with kokoro_onnx> --model kokoro-v1.0.onnx \
        --voices voices-v1.0.bin --voice af_heart
    python3 promo/audio.py --engine piper --lib <dir with piper> --model en-us-ryan-medium.onnx

Writes promo/music.wav, promo/voice.wav, promo/sfx.wav, then mixes them under the video into
promo/headroom-promo-audio.mp4 (music ducks under the voice). Nothing here is downloaded at
render time: the music and effects are generated with numpy; the voice comes from Kokoro
(pip install kokoro-onnx; model and voices from
https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0) or, as a plainer
fallback, piper-tts with a voice such as
https://github.com/rhasspy/piper/releases/download/v0.0.2/voice-en-us-ryan-medium.tar.gz
"""
import argparse, os, subprocess, sys, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 44100
DUR = 31.8
BPM = 108
BEAT = 60 / BPM
T = np.arange(int(DUR * SR)) / SR

# scene times in the video (see promo.html: SHIFT = 2.8 after the hook)
WELCOME, SCAN, DASH, TREEMAP, SAFETY, CLEANUP, CLEAN_CLICK, TOAST, OUTRO = 3.4, 6.2, 9.7, 12.3, 14.6, 19.5, 22.3, 22.8, 26.2
CLICKS = [12.25, 14.55, 19.45, 20.3, 20.9, 21.5, 22.25]  # cursor clicks (promo.html CLICKS + SHIFT)


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


def env(t, a, d, s, r, gate):
    """ADSR for a note of length `gate` (seconds), evaluated on local time t >= 0."""
    e = np.where(t < a, t / max(a, 1e-4), 1.0)
    e = np.where((t >= a) & (t < a + d), 1 - (1 - s) * (t - a) / max(d, 1e-4), e)
    e = np.where((t >= a + d) & (t < gate), s, e)
    e = np.where(t >= gate, s * np.exp(-(t - gate) / max(r, 1e-4)), e)
    return np.clip(e, 0, 1)


def place(buf, sig, start):
    i = int(start * SR)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i:i + n] += sig[:n]


def pad(buf, notes, start, length, gain):
    """Soft detuned pad: a few sines per note with slow attack and a gentle vibrato."""
    n = int((length + 3) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        f = midi(m)
        for det, g in ((-0.4, .5), (0, 1), (0.4, .5), (12.03, .18)):
            ff = f * 2 ** (det / 1200) * 2 ** (0 if det < 12 else 0)
            vib = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t)
            out += g * np.sin(2 * np.pi * ff * vib * t)
    out *= env(t, 1.6, 0.5, 0.85, 1.8, length)
    place(buf, out * gain / (len(notes) * 2.2), start)


def pluck(buf, m, start, gain, decay=0.35):
    """Bell-like pluck for the arpeggio."""
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    f = midi(m)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3 * f * t)
    s *= np.exp(-t / decay) * (1 - np.exp(-t / 0.004))
    place(buf, s * gain, start)


def kick(buf, start, gain):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 48 + 110 * np.exp(-t / 0.035)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
    place(buf, s * gain, start)


def hat(buf, start, gain, rng, length=0.05):
    n = int(length * SR)
    s = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / (length / 4))
    s = np.diff(s, prepend=0)  # brighten
    place(buf, s * gain, start)


def riser(buf, start, length, gain, rng):
    n = int(length * SR)
    t = np.arange(n) / SR
    s = rng.standard_normal(n) * (t / length) ** 2.2
    # crude band-pass by differencing + smoothing
    s = np.convolve(np.diff(s, prepend=0), np.ones(8) / 8, mode="same")
    place(buf, s * gain, start)


def chime(buf, start, gain):
    for i, m in enumerate((88, 92, 95)):  # E6 G#6 B6 arpeggio
        pluck(buf, m, start + i * 0.07, gain, decay=0.6)


def click(buf, start, gain, rng):
    n = int(0.012 * SR)
    s = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / 0.002)
    place(buf, s * gain, start)


def lowpass(x, cutoff):
    """One-pole lowpass, run twice."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = a * acc + (1 - a) * x[i]
            y[i] = acc
        x = y.copy()
    return y


def stereo(mono, width=0.012):
    """Haas widening: right channel delayed by `width` seconds, slightly quieter."""
    d = int(width * SR)
    r = np.concatenate([np.zeros(d), mono[:-d]]) * 0.9
    return np.stack([mono, 0.4 * mono + 0.6 * r], axis=1)


def write_wav(path, data):
    data = np.clip(data, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(data.shape[1] if data.ndim == 2 else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype(np.int16).tobytes())


def music():
    rng = np.random.default_rng(7)
    padb = np.zeros(len(T))
    arp = np.zeros(len(T))
    drums = np.zeros(len(T))
    fx = np.zeros(len(T))

    # Chords: A minor, F, C, G (uplifting, resolves to C at the outro). Two bars each.
    chords = [((57, 60, 64), 0), ((53, 57, 60), 1), ((48, 52, 55, 60), 2), ((55, 59, 62), 3)]
    bar = 4 * BEAT
    t = 0.0
    i = 0
    while t < OUTRO:
        notes, _ = chords[i % 4]
        gain = 0.55 if t < WELCOME else 0.75
        pad(padb, notes, t, 2 * bar, gain)
        # arpeggio from the Welcome page onward, 16ths over the chord tones, up an octave
        if t + 2 * bar > WELCOME:
            steps = [n + 12 for n in notes] + [notes[-1] + 19]
            k = 0
            s = t
            while s < t + 2 * bar:
                if s >= WELCOME:
                    g = 0.08 if s < SCAN else 0.13
                    if k % 4 in (0, 2) or s >= SCAN:
                        pluck(arp, steps[k % len(steps)], s, g * (1 if k % 2 == 0 else 0.7))
                s += BEAT / 2
                k += 1
        t += 2 * bar
        i += 1
    # the outro: one long C major with the fifth on top
    pad(padb, (48, 55, 60, 64, 67), OUTRO, DUR - OUTRO, 0.9)

    # Drums from the scan to the outro: kick on 1 and 3, hats on 8ths, snare-ish hat on 2 and 4
    b = SCAN
    n = 0
    while b < OUTRO - 0.05:
        if n % 2 == 0:
            kick(drums, b, 0.5)
        hat(drums, b, 0.045, rng)
        hat(drums, b + BEAT / 2, 0.03, rng, 0.03)
        if n % 2 == 1:
            hat(drums, b, 0.07, rng, 0.11)
        b += BEAT
        n += 1
    # fills: a riser into the Clean click and a crash-like wash at the outro
    riser(fx, CLEAN_CLICK - 1.3, 1.3, 0.16, rng)
    hat(fx, OUTRO, 0.22, rng, 0.9)
    chime(fx, TOAST + 0.15, 0.16)

    mix = lowpass(padb, 2200) * 1.0 + lowpass(arp, 5000) * 1.0 + drums * 0.9 + fx
    # overall fade out at the very end
    mix *= np.clip((DUR - T) / 2.0, 0, 1)
    mix *= np.clip(T / 0.3, 0, 1)
    # soft limiter
    mix = np.tanh(mix * 1.4) / 1.4
    peak = np.max(np.abs(mix))
    return stereo(mix / peak * 0.8)


def sfx():
    rng = np.random.default_rng(3)
    out = np.zeros(len(T))
    for c in CLICKS:
        click(out, c, 0.5, rng)
    return np.stack([out, out], axis=1)


def speaker(a):
    """Returns say(text) -> (samples, rate) for the chosen engine."""
    sys.path.insert(0, a.lib or "")
    if a.engine == "kokoro":
        from kokoro_onnx import Kokoro  # noqa: E402
        k = Kokoro(a.model, a.voices)
        return lambda text: k.create(text, voice=a.voice, speed=a.speed, lang="en-us")
    from piper import PiperVoice, SynthesisConfig  # noqa: E402
    voice = PiperVoice.load(a.model)
    cfg = SynthesisConfig(length_scale=1 / a.speed)
    tmp = os.path.join(HERE, "_line.wav")

    def say(text):
        with wave.open(tmp, "wb") as w:
            voice.synthesize_wav(text, w, syn_config=cfg)
        with wave.open(tmp) as w:
            sr = w.getframerate()
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
        os.remove(tmp)
        return pcm, sr
    return say


def narration(a):
    say = speaker(a)
    out = np.zeros(len(T))
    cues = []
    with open(os.path.join(HERE, "narration.txt")) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            start, text = line.rstrip("\n").split("\t", 1)
            cues.append((float(start), text))
    prev_end = 0.0
    for start, text in cues:
        pcm, sr = say(text)
        pcm = np.asarray(pcm, dtype=float)
        # resample to SR with linear interpolation
        if sr != SR:
            x = np.arange(len(pcm)) / sr
            pcm = np.interp(np.arange(0, x[-1], 1 / SR), x, pcm)
        length = len(pcm) / SR
        flag = "  <-- overlaps the previous line" if start < prev_end else ""
        print(f"{start:5.1f}s +{length:4.1f}s = {start + length:5.1f}s  {text[:52]}{flag}")
        place(out, pcm, start)
        prev_end = start + length
    return np.stack([out, out], axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=["kokoro", "piper"], default="kokoro")
    ap.add_argument("--lib", help="directory containing the installed kokoro_onnx or piper package")
    ap.add_argument("--model", help="model file (.onnx)")
    ap.add_argument("--voices", help="kokoro voices file (voices-v1.0.bin)")
    ap.add_argument("--voice", default="af_heart", help="kokoro voice name")
    ap.add_argument("--speed", type=float, default=1.05)
    ap.add_argument("--mute-voice", action="store_true")
    ap.add_argument("--video", default=os.path.join(HERE, "headroom-promo.mp4"))
    ap.add_argument("--out", default=os.path.join(HERE, "headroom-promo-audio.mp4"))
    a = ap.parse_args()

    write_wav(os.path.join(HERE, "music.wav"), music())
    write_wav(os.path.join(HERE, "sfx.wav"), sfx())
    have_voice = bool(a.model) and not a.mute_voice
    if have_voice:
        write_wav(os.path.join(HERE, "voice.wav"), narration(a))

    # Mix: voice on top, music ducked by the voice (sidechain), clicks quiet.
    inputs = ["-i", a.video, "-i", os.path.join(HERE, "music.wav"), "-i", os.path.join(HERE, "sfx.wav")]
    if have_voice:
        inputs += ["-i", os.path.join(HERE, "voice.wav")]
        graph = ("[3:a]highpass=f=90,lowpass=f=9000,acompressor=threshold=-18dB:ratio=3:attack=5:release=120,"
                 "volume=1.6,aresample=44100,asplit=2[v][vk];"
                 "[1:a]volume=-9dB[m];[m][vk]sidechaincompress=threshold=0.02:ratio=6:attack=40:release=500:makeup=1[md];"
                 "[2:a]volume=-12dB[s];[md][s][v]amix=inputs=3:normalize=0,alimiter=limit=0.95[a]")
    else:
        graph = "[1:a]volume=-6dB[m];[2:a]volume=-12dB[s];[m][s]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", graph,
           "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", a.out]
    subprocess.run(cmd, check=True)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
