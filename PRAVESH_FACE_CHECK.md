# Pravesh applicant-photo check

What the Pravesh UAT app and the small HumanDetect service use for one question: is a person visible in the applicant photo?

## What runs

In Pravesh, the applicant photo — including a co-applicant, because it uses the same photo type — is checked with MediaPipe BlazeFace short-range before the loan API stores it. BlazeFace is a downloaded face detector, `blaze_face_short_range.tflite`, with float16 weights. The photo is fitted into a 128×128 input, the model runs once, and it returns face boxes with confidence scores. The photo passes when at least one face scores 0.6 or higher and the largest of those faces covers at least 4% of the image. Otherwise it stops with no face, a face the model is unsure about, or a face too small to be the subject. A second face or a turned head does not fail it. The same model and the same two cutoffs run on the phone first and then on a small HumanDetect service. A miss on the phone stops the upload. A pass is sent to that service, and the service’s yes or no is the decision. BlazeFace only answers whether a face is visible, so a gallery file, a photo of a screen, or a photo of a printed photo all pass when that face is clear enough.

The phone copy lives in `flutter-apps/pravesh/lib/features/human_detect/`. The server copy is `POST /v1/final-capture` in `server/humandetect_server/final_capture.py`. Both call the same file fetched by `app/tool/fetch_models.sh`:

`https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite`

Loan APIs stay on the UAT or production base URL. The face check is a separate call.

| | Phone | Server |
|---|---|---|
| Model | `blaze_face_short_range.tflite` bundled in the APK | the same file, loaded by LiteRT |
| Runtime | `tflite_flutter` 0.12.1 | `ai_edge_litert` |
| Pass | confidence ≥ 0.6 and largest confident face ≥ 4% of the photo | the same two numbers (`min_confidence` 0.6, `min_face_area` 0.04) |
| Reject codes | `NO_FACE`, `LOW_CONFIDENCE`, `FACE_TOO_SMALL` | the same codes |
| Role | first filter; a miss never reaches the service | the decision, and only then does the loan upload continue |

The lab approach 01 still has extra rules (one dominant face, limited yaw). This production check does not. Those rules stay in `approaches/01-face-detection/`.

## Precision

The file is MediaPipe’s **float16** v1 release. The weights are stored as 16-bit floats. The interpreter still takes the image and returns the face boxes as float32. On disk the file is 229,746 bytes (about 225 KB).

Converting the weights to int8 could cut the file toward roughly half. That is a poor trade here. 225 KB does not move an app of this size, and int8 changes the confidence scores. The phone and the server would disagree unless both copies were converted and checked together. The float16 file stays the one both sides run.

## Debug APK size

Measured on 15 Oct 2026 from the UAT debug package built for the arm64 emulator:

`flutter-apps/pravesh/build/app/outputs/flutter-apk/app-uat-debug.apk`

The file listing shows **125 MB**. The zip payload is **121,720,318 bytes** (122 MB compressed). Almost all of that is the debug build, not BlazeFace.

| Compressed | What |
|---|---|
| 34.7 MB | debug Flutter engine, `lib/arm64-v8a/libflutter.so` |
| 30.8 MB | uncompiled Dart snapshot, `kernel_blob` |
| 14.1 MB | Vulkan validation layer, `libVkLayer_khronos_validation.so` |
| ~19 MB | LiteRT native libraries, three ABIs, CPU and GPU |
| 0.22 MB | `blaze_face_short_range.tflite` |
| the rest | app bytecode, images, Firebase, and other assets |

The three debug-only pieces (engine, snapshot, Vulkan layer) are about **80 MB**. They are why a debug APK looks this large.

BlazeFace added about **19 MB**. The model is 0.22 MB of that. The other 19 MB is the LiteRT runtime, packaged three times (arm64, 32-bit ARM, and x86_64), including a GPU library this check does not call. The inference path uses the CPU interpreter with 4 threads. Before this library was added, the same debug APK would have been about **103 MB**. That older file was overwritten by the rebuild; the 19 MB is the LiteRT entries inside the current APK.

| LiteRT library | arm64-v8a | armeabi-v7a | x86_64 |
|---|---|---|---|
| `libtensorflowlite_jni.so` | 4.12 MB | 2.73 MB | 5.77 MB |
| `libtensorflowlite_gpu_jni.so` | 2.39 MB | 1.47 MB | 2.52 MB |

## Release size

A release APK has not been built. These are estimates from the debug package above.

A release build drops `kernel_blob` and the Vulkan validation layer, compiles Dart ahead of time, and runs R8. Release minify and resource shrinking are already turned on in `flutter-apps/pravesh/android/app/build.gradle.kts`.

| Package | Expected size |
|---|---|
| arm64-only release (`--target-platform android-arm64`) | about 40–55 MB |
| fat release (arm64, armeabi-v7a, and x86_64) | about 80–110 MB |

The fat package is larger because the Flutter engine, the compiled Dart code, and the LiteRT libraries are stored once per ABI. The 0.22 MB model is the same in every build.
