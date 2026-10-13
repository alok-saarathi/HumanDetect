# 05 · Active liveness (challenge-response)

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:** ask the customer to blink, smile or turn their head during capture, and verify it on the phone.
- **Model:** MediaPipe Face Landmarker (Apache-2.0), using its blendshapes (`eyeBlinkLeft` / `eyeBlinkRight`).
- **Head turns:** can also be tracked with 01's BlazeFace keypoints across frames.

**Catches:** F2 (a printout or a still image on a screen can't blink), plus F1 and F3.

**Watch out:**
- Adds friction to the capture.
- A replayed video can still pass.
- Needs a live camera stream rather than a single photo.
- More Flutter work than 01, because MediaPipe has no official Flutter plugin. Its model files run through `tflite_flutter`.

**Resources**
- https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker

## Implementation (lab app 0.1.0)

**Status:** prototype in the app (tile 05), with the landmark pipeline verified in Python. Needs a phone test: frame rotation, frame rate, thresholds.

| Part | Where |
|---|---|
| Face Mesh crop, landmarks, eye aspect ratio, yaw (reference) | `face_mesh.py` |
| Check against `mediapipe` FaceLandmarker | `verify_against_mediapipe.py TASK IMAGE…` |
| YUV frame → upright RGB (sensor rotation, front-camera mirror) | `app/lib/approaches/a05_active_liveness/frame_convert.dart` |
| Landmarks, EAR, yaw in the app | `face_mesh.dart` |
| Challenge state machine (unit-tested) | `liveness_session.dart`, `app/test/liveness_session_test.dart` |
| Screen: live preview, instructions, debug line | `active_liveness_screen.dart` |

**How it works in the app:**
1. **Frames:** stream 720×480 YUV frames. Each frame is processed upright: BlazeFace finds the largest face, then a square crop 1.5× the box goes into Face Mesh V2 (256×256, input 0..1). The output is 478 landmarks plus a presence score.
2. **Signals:**
   - **Eye aspect ratio**, using landmarks 33/160/158/133/153/144 and 362/385/387/263/373/380.
   - **Yaw:** the nose (landmark 1) position between the cheek edges (234/454), −1..1. The sign is flipped for the back camera so that negative always means the person's left.
3. **Get ready:** one face, ≥ 5 % of the frame, |yaw| ≤ 0.2, held for 0.7 s. The median eye openness during that hold becomes the "open" level.
4. **Challenges:** blink plus one turn (left or right), in random order, 7 s each.
   - **Blink:** eye openness below 0.6× open, then back above 0.85×.
   - **Turn:** |yaw| > 0.35 in the asked direction, for 2 frames.
5. **Failures:**
   - **`FACE_LOST`:** no face for more than 0.7 s.
   - **`MULTIPLE_FACES`:** a second face stays in view for more than 0.7 s.
   - **`FACE_SWITCHED`:** the face center jumps more than 25 % of the frame between frames.
   - **`TIMEOUT`:** a challenge isn't completed in time.

**Findings:**
- **Landmarks vs mediapipe FaceLandmarker:**
  - Mean error 0.15–0.43 % of face width on upright faces.
  - About 3–4 % on strongly turned faces, because we don't rotate the crop as MediaPipe does.
  - Eye openness and yaw signs agree.
- **Input scaling:** the mesh model expects input in 0..1. We confirmed this against mediapipe: error 0.21 % with 0..1, versus 0.27 % with −1..1.
- **Unit tests:** pass for passing, a still photo, a wrong-direction turn, face lost, face swapped and two faces.
