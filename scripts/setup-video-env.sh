#!/bin/sh
# Creates ./venv (a Python virtualenv in the repo, git-ignored) with the tools scripts/make-promo.sh needs.
# Packages are never installed globally. Safe to re-run.
set -e
cd "$(dirname "$0")/.."
[ -d venv ] || python3 -m venv venv
venv/bin/pip install -q -r requirements-video.txt
venv/bin/python -c 'import imageio_ffmpeg; print("ffmpeg:", imageio_ffmpeg.get_ffmpeg_exe())'
