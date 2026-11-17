#!/usr/bin/env python3
"""Builds the website video, GIF and the dropdown picture from one screen recording by cutting clips.

    venv/bin/python scripts/make-promo-clips.py ~/Desktop/altformac2.mov

Why clips: typing `H O I` fast shows each badge screen for a tenth of a second, so the video holds on
those frames ("hold"), and zooms into the part of the screen that matters ("left" or "right" crop of the
full-screen recording, which is too wide to read on a web page).

Writes site/promo.mp4, promo.webm, promo-poster.jpg, promo.gif and promo-dropdown.png.
ffmpeg comes from the repo's virtualenv (scripts/setup-video-env.sh), never a global install.

The numbers below are seconds in altformac2.mov (screen 2940 x 1912, Excel in dark mode, demo-sales data):
  4.55 Home-tab badges   3.82 Format dropdown with item badges   4.30 columns auto-fitted
  6.57 tab badges        8.80 View-tab badges                    10.10 Insert-tab badges   10.40 PivotTable dialog
Check a recording with a contact sheet before changing them; the menu bar (clock, other apps) is cropped off.
"""
import os
import subprocess
import sys
import tempfile

import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SITE = os.path.join(ROOT, "site")

# Crop windows in recording pixels: W:H:X:Y. Y=60 drops the macOS menu bar (it shows the clock and other apps).
LEFT = "1700:950:0:60"      # tab strip, left half of the ribbon, the data columns
RIGHT = "1700:950:1240:60"  # right half of the ribbon and the open Format dropdown
OUT_W = 1600

# ("play", start, end, crop) | ("hold", time, seconds, crop) | ("card", png, seconds), a title card faded in and out
# (scripts/make-cards.swift draws them). `mark` ends the H O I part; the GIF is intro + that part + outro.
INTRO = ("card", "packaging/promo-intro.png", 2.2)
OUTRO = ("card", "packaging/promo-outro.png", 2.8)
CLIPS = [
    INTRO,
    ("play", 2.40, 3.60, LEFT),      # narrow columns A:G selected
    ("hold", 4.55, 1.6, RIGHT),      # H typed: a badge on every control of the Home tab (clean frame, 2nd take)
    ("hold", 3.82, 2.6, RIGHT),      # O typed: the real Format dropdown, a badge on each item
    ("play", 3.82, 4.30, LEFT),      # I typed: the dropdown closes, columns snap to fit
    ("hold", 4.30, 1.3, LEFT),       # "AutoFit column width"
    ("mark", "hoi_done"),
    ("play", 6.30, 6.55, LEFT),
    ("hold", 6.567, 1.5, LEFT),      # tap Option: a badge on every tab
    ("hold", 8.80, 1.5, LEFT),       # W typed: badges on the View tab
    ("play", 8.80, 9.30, LEFT),
    ("hold", 10.10, 1.4, LEFT),      # N typed: badges on the Insert tab
    ("play", 10.10, 10.60, LEFT),
    ("hold", 10.40, 1.3, LEFT),      # V typed: Create PivotTable
    OUTRO,
]


def length(clip):
    kind = clip[0]
    return clip[2] - clip[1] if kind == "play" else clip[2]


def run(*args):
    r = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], capture_output=True, text=True)
    if r.returncode != 0 or "Error" in r.stderr or "bug" in r.stderr:
        sys.exit(f"ffmpeg failed ({r.returncode}): {' '.join(args)}\n{r.stderr.strip()}")


def scale(crop, width):
    return f"crop={crop},scale={width}:-2:flags=lanczos,format=yuv420p"


def build_clip(src, clip, tmp, i, width):
    path = os.path.join(tmp, f"c{i:02d}.mp4")
    kind = clip[0]
    enc = ["-an", "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-pix_fmt", "yuv420p"]
    if kind == "card":
        _, png, seconds = clip
        fade = 0.35
        run("-loop", "1", "-framerate", "30", "-i", os.path.join(ROOT, png), "-t", str(seconds),
            "-vf", f"scale={width}:-2:flags=lanczos,fade=t=in:st=0:d={fade},fade=t=out:st={seconds - fade}:d={fade},format=yuv420p",
            *enc, path)
    elif kind == "play":
        _, start, end, crop = clip
        run("-ss", str(start), "-to", str(end), "-i", src, "-vf", scale(crop, width) + ",fps=30", *enc, path)
    else:
        _, t, hold, crop = clip
        png = os.path.join(tmp, f"c{i:02d}.png")
        run("-ss", str(t), "-i", src, "-frames:v", "1", "-vf", scale(crop, width), png)
        run("-loop", "1", "-framerate", "30", "-i", png, "-t", str(hold), *enc, path)
    return path


def concat(paths, out, extra=()):
    listing = out + ".txt"
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in paths)
    run("-f", "concat", "-safe", "0", "-i", listing, *extra, out)
    os.remove(listing)


def main():
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        sys.exit("usage: make-promo-clips.py recording.mov")
    src = sys.argv[1]
    with tempfile.TemporaryDirectory() as tmp:
        paths, gif_len, marked = [], 0.0, False
        total = sum(length(c) for c in CLIPS if c[0] != "mark")
        for i, clip in enumerate(CLIPS):
            if clip[0] == "mark":
                marked = True
                continue
            p = build_clip(src, clip, tmp, i, OUT_W)
            paths.append(p)
            if not marked:
                gif_len += length(clip)

        master = os.path.join(tmp, "master.mp4")
        concat(paths, master, ["-c", "copy"])

        print("==> mp4")
        run("-i", master, "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-movflags", "+faststart",
            os.path.join(SITE, "promo.mp4"))
        print("==> webm")
        run("-i", os.path.join(SITE, "promo.mp4"), "-an", "-c:v", "libvpx-vp9", "-crf", "36", "-b:v", "0",
            "-row-mt", "1", os.path.join(SITE, "promo.webm"))
        print("==> poster (the dropdown frame)")
        dropdown = next(i for i, c in enumerate(CLIPS) if c[0] == "hold" and c[1] == 3.82)
        run("-ss", "0", "-i", os.path.join(tmp, f"c{dropdown:02d}.mp4"), "-frames:v", "1", "-q:v", "3",
            os.path.join(SITE, "promo-poster.jpg"))

        print("==> gif")
        # Intro + the H O I part are the start of the finished video; the outro is its end.
        mp4 = os.path.join(SITE, "promo.mp4")
        run("-t", f"{gif_len:.3f}", "-i", mp4, "-ss", f"{total - OUTRO[2]:.3f}", "-t", f"{OUTRO[2]:.3f}", "-i", mp4,
            "-filter_complex",
            "[0:v][1:v]concat=n=2:v=1:a=0,fps=12,scale=900:-2:flags=lanczos,split[a][b];"
            "[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
            "-loop", "0", os.path.join(SITE, "promo.gif"))

    print("==> dropdown picture")
    run("-ss", "3.82", "-i", src, "-frames:v", "1", "-vf", "crop=1040:1180:1900:92",
        os.path.join(SITE, "promo-dropdown.png"))
    for name in ("promo.mp4", "promo.webm", "promo-poster.jpg", "promo.gif", "promo-dropdown.png"):
        print(f"{name}: {os.path.getsize(os.path.join(SITE, name)) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
