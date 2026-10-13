#!/usr/bin/env bash
# Downloads the pinned MediaPipe models (Apache-2.0) into app/assets/models/.
# TinyCLIP (approach 02) is exported separately: see approaches/02-zero-shot-clip/README.md.
set -euo pipefail

DEST="$(cd "$(dirname "$0")/.." && pwd)/assets/models"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {  # url, output path, sha256
  curl -fsSL -o "$2" "$1"
  echo "$3  $2" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $1" >&2; exit 1; }
}

# 01 · BlazeFace short-range face detector (MediaPipe, Apache-2.0)
fetch https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite \
  "$DEST/blaze_face_short_range.tflite" b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f

# 05 · Face Mesh V2 landmarks, taken from the Face Landmarker bundle (MediaPipe, Apache-2.0)
fetch https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task \
  "$TMP/face_landmarker.task" 64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff
unzip -o -q -j "$TMP/face_landmarker.task" face_landmarks_detector.tflite -d "$DEST"
chmod 644 "$DEST"/*.tflite
echo "c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5  $DEST/face_landmarks_detector.tflite" | shasum -a 256 -c - >/dev/null

echo "Models ready in $DEST:"
ls -l "$DEST"
