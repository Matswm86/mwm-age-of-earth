#!/bin/bash
# Encode the Blender frames of the intro planet stage (tools/intro/render_earth.py) to Ogg Theora
# for Godot's VideoStreamTheora. Usage: encode_video.sh <frames dir> <out.ogv> [quality 0-10] [fps]
# Quality 8 keeps star points and cloud edges; check the size against GitHub's 100 MB file limit.
set -euo pipefail
FRAMES="$1"; OUT="$2"; Q="${3:-8}"; FPS="${4:-30}"
ffmpeg -hide_banner -y -framerate "$FPS" -i "$FRAMES/%04d.png" -c:v libtheora -q:v "$Q" -pix_fmt yuv420p -an "$OUT"
ls -la "$OUT"
