// What each approach is, how it is implemented and what it is built from. Shown on the
// details screen (tile "Details" button, and ⓘ on each camera screen). Keep in sync
// with the code and with approaches/<NN>/README.md.

class Component {
  const Component(this.name, this.kind, this.license, this.role);

  final String name;
  final String kind; // model, package, own code, data
  final String license;
  final String role;
}

class ApproachDetails {
  const ApproachDetails({
    required this.id,
    required this.title,
    required this.question,
    required this.steps,
    required this.components,
    required this.thresholds,
    required this.catches,
    required this.misses,
    required this.verified,
    required this.limitations,
    required this.code,
  });

  final String id;
  final String title;

  /// The question this approach answers, in one line.
  final String question;

  /// How it works, in pipeline order.
  final List<String> steps;
  final List<Component> components;

  /// Default thresholds (all adjustable in the app).
  final List<(String, String)> thresholds;
  final List<String> catches;
  final List<String> misses;

  /// How the implementation was checked so far.
  final List<String> verified;
  final List<String> limitations;

  /// Where the implementation lives in the repo.
  final List<String> code;
}

const approachDetails = <String, ApproachDetails>{
  '01': ApproachDetails(
    id: '01',
    title: 'Face detection',
    question: 'Is there one clear, frontal, big-enough face in the photo?',
    steps: [
      'Take a photo with the in-app camera (1080p, back camera by default), or pick one from the gallery. Decode it and apply its EXIF rotation in a background thread. Gallery files may be JPEG, PNG, WebP, GIF or BMP; other formats are converted to JPEG on the phone.',
      'Letterbox the photo into 128 × 128 pixels (keep the aspect ratio, pad with black) and scale pixel values to −1…1.',
      'Run BlazeFace. It scores 896 fixed candidate boxes ("anchors"); each comes with a box and 6 keypoints: both eyes, nose tip, mouth and both ears.',
      'Keep candidates scoring ≥ 0.5, merge overlapping ones (weighted non-maximum suppression, overlap ≥ 0.3) and map them back onto the photo.',
      'Apply the rules to the largest confident face: confidence ≥ 0.6, covers ≥ 4 % of the photo, ≥ 2× bigger than any other face, head turned ≤ 35° (estimated from where the nose sits between the eyes).',
      'Show PASS/FAIL with reasons, and draw every face box and keypoint on the photo.',
    ],
    components: [
      Component(
        'BlazeFace short-range',
        'model',
        'Apache-2.0',
        'Face detector from Google MediaPipe. 230 KB, 128 × 128 input. File: blaze_face_short_range.tflite (pinned, SHA-256 checked).',
      ),
      Component(
        'LiteRT (tflite_flutter)',
        'package',
        'Apache-2.0',
        'Runs the model on the phone CPU, 4 threads.',
      ),
      Component(
        'camera',
        'package',
        'BSD-3',
        'In-app camera. Gallery photos come through the Android photo picker instead.',
      ),
      Component(
        'image',
        'package',
        'MIT',
        'Decodes JPEG, PNG, WebP, GIF and BMP, and applies EXIF orientation.',
      ),
      Component(
        'Anchor decoder + weighted NMS',
        'own code',
        'this repo',
        'Turns raw model output into faces, exactly like MediaPipe does.',
      ),
      Component(
        'Face rules',
        'own code',
        'this repo',
        'Confidence, size, dominance and head-turn checks.',
      ),
    ],
    thresholds: [
      ('Min confidence', '0.6'),
      ('Min face area', '4 % of the photo'),
      ('Largest / second face', '≥ 2×'),
      ('Max head turn', '35°'),
    ],
    catches: ['F1: no human at all (walls, tables, scenery, blank frames)'],
    misses: [
      'Any face that is not live: faces on phone or laptop screens, printouts, posters, ID cards, screenshots, statues and many mannequins all pass.',
    ],
    verified: [
      'Our decoder vs Google\'s own mediapipe package: boxes within 1.6 % of image size; same face count on 19 of 22 test images (the 3 differences are borderline scores 0.4–0.6, below the 0.6 rule anyway).',
      'Dart code matches the Python reference exactly on synthetic tests (flutter test).',
    ],
    limitations: [
      'Made for faces within about 2 m of the camera; small faces fail with FACE_TOO_SMALL or NO_FACE.',
      'Head-turn angle is an estimate from 3 keypoints.',
      'Thresholds not yet calibrated on our own photos.',
    ],
    code: [
      'app/lib/approaches/a01_face_detection/',
      'approaches/01-face-detection/ (Python reference + mediapipe check)',
    ],
  ),
  '02': ApproachDetails(
    id: '02',
    title: 'Zero-shot classification',
    question: 'Does the photo look most like a live person, or like a scene, a screen, a screenshot or something not real?',
    steps: [
      'Take a photo or pick one from the gallery, and decode it as in 01. The same prompts run on either source.',
      'Resize so the shorter side is 224 pixels (big photos are first averaged down to avoid jagged edges), cut out the 224 × 224 center and scale pixel values to 0…1.',
      'The TinyCLIP image encoder turns the photo into 512 numbers (an "embedding") that describe what it shows.',
      'Compare it with 25 text prompts prepared in advance, each averaged over 4 phrasings ("a photo of …", "a blurry photo of …", "a low-light photo of …", "a close-up photo of …").',
      'The prompts form 5 buckets: genuine person, no human, recapture (screen, printout, poster, ID card), screenshot, not real (cartoon, drawing, mannequin, statue, computer-generated face).',
      'Each bucket is scored by its best-matching prompt, and a softmax turns the scores into probabilities. PASS if "genuine" ≥ 0.5; otherwise the winning bucket is the reason.',
    ],
    components: [
      Component(
        'TinyCLIP ViT-39M/16',
        'model',
        'MIT',
        'Image half of a small CLIP model by Microsoft researchers, trained on YFCC15M (Creative Commons photos). Weights stored as int8, 40 MB. The text half is used only on the laptop to prepare the prompts.',
      ),
      Component(
        'tinyclip_prompts.json',
        'data',
        'this repo',
        '25 prompt embeddings + bucket names + reason codes, generated from prompts/v0.yaml.',
      ),
      Component(
        'litert-torch, ai-edge-quantizer',
        'package (laptop only)',
        'Apache-2.0',
        'Convert the PyTorch model to LiteRT and quantize it. Converted model agrees with PyTorch at cosine similarity 0.9993.',
      ),
      Component(
        'LiteRT (tflite_flutter)',
        'package',
        'Apache-2.0',
        'Runs the encoder on the phone.',
      ),
      Component(
        'Preprocessing + bucket scoring',
        'own code',
        'this repo',
        'Resize, crop and score exactly as the Python reference does.',
      ),
    ],
    thresholds: [('Min "genuine" probability', '0.5')],
    catches: [
      'F1: scenes and objects (all 8 test scenes rejected)',
      'F5: drawings, paintings, statues, mannequins (all 8 rejected)',
      'Part of F2/F3: obvious screens and screenshots',
    ],
    misses: [
      'Good-quality photos of screens and printouts often still look "genuine" (old printed portraits passed in testing).',
      'People shown very small in the frame (a full-body mirror selfie failed).',
    ],
    verified: [
      'Compared 5 open models on 25 CC0/public-domain test images: TinyCLIP-8M AUC 0.90, TinyCLIP-39M 0.93, SigLIP 2 0.98 (too big for a phone). TinyCLIP-39M chosen.',
      'Dart preprocessing and scoring match the Python reference exactly on synthetic tests.',
    ],
    limitations: [
      'Prompts are a first draft (v0), not tuned on our photos.',
      'Speed on low-end phones still to be measured (a few hundred ms expected).',
    ],
    code: [
      'app/lib/approaches/a02_zero_shot/',
      'approaches/02-zero-shot-clip/ (prompts, export, model comparison)',
    ],
  ),
  '03': ApproachDetails(
    id: '03',
    title: 'Capture integrity',
    question: 'Was this photo taken live, in this app, just now, on a real phone, at a real location?',
    steps: [
      'Opening the camera starts a session: a random one-time code (nonce) and a start time. A GPS fix and device details are fetched in the background.',
      'The photo has to come from this camera screen. A gallery file has no session, so the gallery button is not shown and a gallery file cannot pass.',
      'Check the photo was taken soon after the session started (≤ 120 s).',
      'Check the phone is real hardware, not an emulator.',
      'Check the location: available, precise (≤ 50 m), recent (≤ 120 s) and not faked by a mock-location app.',
      'Build a receipt: SHA-256 fingerprint of the photo, then an HMAC signature over nonce + fingerprint + time + location + device. A server would store and verify this.',
    ],
    components: [
      Component(
        'camera',
        'package',
        'BSD-3',
        'In-app capture only. Gallery files are rejected.',
      ),
      Component(
        'geolocator_android',
        'package',
        'MIT',
        'GPS fix, accuracy and the Android "mocked location" flag. Android implementation used directly to avoid MPL-licensed Linux dependencies.',
      ),
      Component(
        'device_info_plus',
        'package',
        'BSD-3',
        'Physical device vs emulator, model, Android version.',
      ),
      Component(
        'crypto',
        'package',
        'BSD-3',
        'SHA-256 and HMAC for the receipt.',
      ),
      Component(
        'Session + checks',
        'own code',
        'this repo',
        'Nonce, freshness, location rules and receipt. No model.',
      ),
    ],
    thresholds: [
      ('Max session age', '120 s'),
      ('Max location error', '50 m'),
      ('Max location age', '120 s'),
    ],
    catches: [
      'Gallery files, screenshots and any photo not taken in this session',
      'Makes every photo traceable to a time, place and device',
    ],
    misses: [
      'Anything about what the photo shows: a wall or a screen photographed live passes. Pair with 01/02/05.',
      'Rooted or modified phones can fake these signals.',
    ],
    verified: [
      'Compiles and runs its checks; behaviour on real phones (GPS, mock detection) still to be tried.',
    ],
    limitations: [
      'Demo only: the nonce and signing key are made on the phone. Production needs them issued and verified by the server.',
      'Google Play Integrity (tamper detection) is not used: it is a proprietary service, so using it is a team decision.',
    ],
    code: [
      'app/lib/approaches/a03_capture_integrity/',
      'approaches/03-capture-hardening/',
    ],
  ),
  '04': ApproachDetails(
    id: '04',
    title: 'Recapture forensics',
    question: 'Does the photo carry traces of being a photo of a screen or print, or of not coming from a camera?',
    steps: [
      'Take a photo or pick one from the gallery, decode it, then convert it to brightness only (grayscale). Runs in a background thread.',
      'On a small copy (long side 512): sharpness = how much fine detail there is (variance of the Laplacian); glare = share of near-white pixels; contrast = spread between the darkest and brightest 1 %.',
      'Moiré: take a full-resolution 512 × 512 patch from the center, compute its 2-D frequency spectrum (FFT), and measure how far the 8 strongest peaks stand above the typical level at their frequency. A screen\'s pixel grid and halftone print dots make sharp peaks; normal scenes don\'t.',
      'For an in-app camera photo only: camera make/model present in EXIF, and the EXIF time within 10 min of the shutter press. On a gallery file those two are shown and do not fail the check, because a saved photo often has no camera EXIF and an old timestamp.',
      'PASS only if every signal that applies is within its limit.',
    ],
    components: [
      Component(
        'Signals + FFT',
        'own code',
        'this repo',
        'Sharpness, glare, contrast and moiré score; a radix-2 FFT written in Dart. No model.',
      ),
      Component(
        'exif',
        'package',
        'MIT',
        'Reads camera make, model and time from the JPEG.',
      ),
      Component('image', 'package', 'MIT', 'JPEG decoding.'),
    ],
    thresholds: [
      ('Min sharpness', '40'),
      ('Max glare', '5 % of pixels'),
      ('Min contrast', '60'),
      ('Max moiré score', '3.5'),
      ('Max EXIF time difference', '600 s'),
    ],
    catches: [
      'Close-up photos of screens where the pixel grid shows (simulated: moiré 4.9–6.3 vs ≤ 3.2 for normal photos)',
      'Blurry or washed-out recaptures',
      'In-app photos with no camera metadata, or an EXIF time far from the shutter press',
    ],
    misses: [
      'Screens photographed from further away (grid not visible) and good prints.',
      'EXIF can be stripped or faked: a signal, never proof.',
    ],
    verified: [
      'Dart signals match the Python reference on synthetic tests; FFT checked against a direct DFT.',
      'Defaults set from ~25 public test images and simulated screen photos.',
    ],
    limitations: [
      'Thresholds are rough; regular patterns (brick walls, tiled floors, rows of desks) can raise the moiré score.',
      'A learned screen detector belongs to approach 12 (trained on our own data).',
    ],
    code: [
      'app/lib/approaches/a04_forensics/',
      'approaches/04-metadata-forensics/forensics.py',
    ],
  ),
  '05': ApproachDetails(
    id: '05',
    title: 'Active liveness',
    question: 'Can the person in front of the camera blink and turn their head when asked?',
    steps: [
      'Stream live video (720 × 480 frames). Each frame is turned upright using the camera\'s sensor orientation, and mirrored for the front camera.',
      'BlazeFace (as in 01) finds the largest face.',
      'Cut a square 1.5× the face box, resize to 256 × 256 and run Face Mesh: 478 face landmarks plus a "face present" score.',
      'Two signals: eye openness (eyelid gap / eye width, both eyes) and head turn (where the nose sits between the cheek edges, −1 … 1).',
      'Get ready: one face, ≥ 5 % of the frame, facing the camera, still for 0.7 s. Its eye openness becomes the "open" level.',
      'Two challenges in random order: blink (eyes below 0.6× open, then back above 0.85×) and turn left or right (turn beyond 0.35 for 2 frames). 7 s each.',
      'FAIL if the face disappears > 0.7 s, a second face stays in view, the face jumps > 25 % of the frame between frames (photo swapped in), or time runs out. A final photo is kept for the record.',
    ],
    components: [
      Component(
        'BlazeFace short-range',
        'model',
        'Apache-2.0',
        'Finds the face in each frame (same as 01).',
      ),
      Component(
        'Face Mesh V2',
        'model',
        'Apache-2.0',
        'Google MediaPipe landmark model, 2.5 MB, 256 × 256 input; taken from the Face Landmarker bundle (pinned, SHA-256 checked).',
      ),
      Component(
        'camera (image stream)',
        'package',
        'BSD-3',
        'Live YUV frames.',
      ),
      Component(
        'Frame conversion',
        'own code',
        'this repo',
        'YUV → upright RGB with rotation and mirroring.',
      ),
      Component(
        'Challenge state machine',
        'own code',
        'this repo',
        'Positioning, random challenges, timeouts and anti-swap checks.',
      ),
    ],
    thresholds: [
      ('Turn threshold', '0.35'),
      ('Eyes closed below', '0.6 × open level'),
      ('Time per challenge', '7 s'),
      ('Min face area', '5 % of frame'),
    ],
    catches: [
      'F2: printed photos and still images on screens (they cannot blink or turn on request)',
      'F1 and F3 (needs a live face in front of the camera)',
    ],
    misses: [
      'A video of the person played on another screen, if it happens to blink and turn at the right time.',
      'Real-time deepfake puppeting (out of scope for Tier 1).',
    ],
    verified: [
      'Landmarks within 0.2–0.4 % of face width of Google\'s mediapipe on upright faces.',
      'State machine unit-tested: passes when followed; a still photo times out; wrong-direction turns don\'t count; face lost, face swapped and second face all fail.',
    ],
    limitations: [
      'The face crop is not rotated for strongly tilted heads (MediaPipe\'s full pipeline does); landmarks drift there.',
      'Frame rotation and speed still to be confirmed on the target phones.',
      'Adds about 5–10 s to a capture.',
    ],
    code: [
      'app/lib/approaches/a05_active_liveness/',
      'approaches/05-active-liveness/',
    ],
  ),
  '06': ApproachDetails(
    id: '06',
    title: 'Zero-shot detection',
    question: 'Is there a human face, and is it not framed by a screen or print, or a painting, statue or mannequin?',
    steps: [
      'The phone sends the photo to the HumanDetect server over the local network. The server judges it in memory and does not store it.',
      'OWLv2 takes text prompts and returns boxes with scores: "a human face"; screens and prints ("a phone screen", "a computer monitor", "a television", "a printed photograph", "a poster", "an identity card"); not-real things ("a painting", "a statue", "a mannequin", "a cartoon").',
      'NO_FACE if no face box scores ≥ 0.15; FACE_TOO_SMALL if it covers < 1 % of the photo.',
      'RECAPTURE (or NOT_REAL) if a screen / print (or painting / statue …) box scoring ≥ 0.35 is clearly larger than the face and holds ≥ 80 % of it. A "printed photograph" box covering the whole frame is ignored: it only says the image is a photo.',
    ],
    components: [
      Component(
        'OWLv2 base/16 ensemble',
        'model',
        'Apache-2.0',
        'Open-vocabulary detector by Google (google/owlv2-base-patch16-ensemble, pinned commit). Runs on the server GPU/CPU.',
      ),
      Component(
        'Grounding DINO tiny',
        'model',
        'Apache-2.0',
        'Compared on the laptop only; not offered in the app (see limitations).',
      ),
      Component(
        'FastAPI + Uvicorn',
        'package',
        'MIT / BSD-3',
        'The HTTP service all Tier 2 tiles call.',
      ),
      Component(
        'transformers, PyTorch',
        'package',
        'Apache-2.0 / BSD',
        'Model loading and inference.',
      ),
      Component(
        'Box rules',
        'own code',
        'this repo',
        'Face size and containment rules in approaches/06-zero-shot-detection/.',
      ),
    ],
    thresholds: [
      ('Min face score', '0.15'),
      ('Min face area', '1 % of the photo'),
      ('Min screen / print / not-real score', '0.35'),
      ('Share of face inside that box', '80 %'),
    ],
    catches: [
      'F1: no human (all 5 test scenes rejected)',
      'F5: paintings, statues and drawings were flagged NOT_REAL in 4 of 6 test cases',
    ],
    misses: [
      'Small faces on a phone or laptop screen: the face prompt scores under 0.15 there, so the photo is rejected as NO_FACE (right outcome, wrong reason).',
      'A real photo of a painting-like subject, or a real person next to a TV, can be mislabeled.',
    ],
    verified: [
      '26-image smoke test (CC0/public-domain photos plus simulated screens): 22 correct at the defaults, ROC-AUC 0.67. A weak signal on its own: it works as a rejector but not as a ranker.',
      'Grounding DINO tiny: every context prompt fired on every image (face scores 0.20–0.33 even on walls), so it was dropped from the app.',
    ],
    limitations: [
      'Slow compared with the detectors: the first request loads the model (about 5 s on an M4).',
      'Needs the server; photos leave the phone (to our own machine only).',
    ],
    code: [
      'server/humandetect_server/',
      'approaches/06-zero-shot-detection/zero_shot_detection.py',
    ],
  ),
  '07': ApproachDetails(
    id: '07',
    title: 'Duplicate detection',
    question: 'Has this photo, or a re-shot or edited copy of it, been submitted before?',
    steps: [
      'The phone sends the photo to the server.',
      'Two fingerprints: a 64-bit perceptual hash (pHash), and a DINOv2-small embedding (384 numbers describing what the photo shows).',
      'Compared with every earlier submission: DUPLICATE if the pHash differs in ≤ 10 bits; RESUBMITTED if the DINOv2 similarity is ≥ 0.85.',
      'A photo that passes is added to the index (fingerprints only, never the photo). A duplicate is not added again.',
      'The result names the earlier photo by its short id and how long ago it was submitted.',
    ],
    components: [
      Component(
        'imagehash (pHash)',
        'package',
        'BSD-2',
        '64-bit perceptual hash: survives re-compression, resizing and small brightness changes.',
      ),
      Component(
        'DINOv2-small',
        'model',
        'Apache-2.0',
        'facebook/dinov2-small (pinned commit): image embedding that survives re-shooting, cropping and framing.',
      ),
      Component(
        'Fingerprint index',
        'own code',
        'this repo',
        'server/data/duplicate_index.npz: fingerprints, ids and times only. Linear search, fine to a few hundred thousand photos.',
      ),
      Component('FastAPI', 'package', 'MIT', 'HTTP service.'),
    ],
    thresholds: [
      ('pHash: max differing bits', '10'),
      ('DINOv2: min similarity', '0.85'),
    ],
    catches: [
      'F4: the same photo uploaded again for another customer, including after JPEG recompression, resizing, cropping, small rotations and a chat-screenshot frame',
    ],
    misses: [
      'A mirrored copy is caught only by DINOv2 (pHash differs by about 32 bits).',
      'Two different photos of the same person: that needs face recognition, which is on hold (no cleanly licensed model).',
    ],
    verified: [
      'Calibrated on 13 public-domain photos × 7 edits: copies stay within 10 bits for JPEG q40, resizing, brightness; DINOv2 ≥ 0.82 for every edit. 78 different-photo pairs never exceeded 0.60 similarity or came closer than 20 bits.',
      'Unit-tested with a fake embedder: duplicate, re-shot copy, new photo, reset.',
    ],
    limitations: [
      'Every different photo passes and is added: the index only grows. Retention and privacy policy for fingerprints still to be agreed.',
      'Thresholds come from synthetic edits, not real resubmissions yet.',
    ],
    code: [
      'server/humandetect_server/',
      'approaches/07-duplicate-detection/duplicates.py',
    ],
  ),
  '08': ApproachDetails(
    id: '08',
    title: 'Deep detectors',
    question: 'Is there one clear person, and are they not shown on a screen or print?',
    steps: [
      'The phone sends the photo to the server.',
      'An open COCO detector (RT-DETRv2 R18 by default; D-FINE small also available) finds people, TVs/monitors, laptops, phones and books (phone frames and printed photos are often detected as "book").',
      'NO_PERSON if no person scores ≥ 0.6; PERSON_TOO_SMALL if the largest covers < 8 % of the photo; NO_DOMINANT_PERSON if a second person is within 2× the size.',
      'RECAPTURE if ≥ 70 % of the person box lies inside a screen or print box scoring ≥ 0.3.',
    ],
    components: [
      Component(
        'RT-DETRv2 R18',
        'model',
        'Apache-2.0',
        'PekingU/rtdetr_v2_r18vd (pinned commit): end-to-end detector, no NMS step.',
      ),
      Component(
        'D-FINE small',
        'model',
        'Apache-2.0',
        'ustc-community/dfine-small-coco (pinned commit): alternative detector.',
      ),
      Component(
        'Containment rules',
        'own code',
        'this repo',
        'Person size, dominance and "person inside a screen" logic.',
      ),
      Component(
        'FastAPI, transformers, PyTorch',
        'package',
        'MIT / Apache-2.0 / BSD',
        'Service and inference. Ultralytics YOLO is excluded (AGPL).',
      ),
    ],
    thresholds: [
      ('Min person confidence', '0.6'),
      ('Min person area', '8 % of the photo'),
      ('Largest / second person', '≥ 2×'),
      ('Min screen / print confidence', '0.3'),
      ('Share of person inside it', '70 %'),
    ],
    catches: [
      'F1: no person (all 5 scenes rejected)',
      'F2 partly: a person on a TV-like screen, or inside a phone frame the detector sees',
    ],
    misses: [
      'Paintings of people count as people (3 of 6 not-real photos passed): the detector is trained on photos of real scenes, but a portrait painting still looks like a person.',
      'Screens the detector doesn\'t see (laptop and phone composites mostly passed).',
    ],
    verified: [
      '26-image smoke test: RT-DETRv2 17/26 correct, ROC-AUC 0.77; D-FINE 15/26, AUC 0.87.',
      'All 7 genuine photos passed with both models; every scene was rejected.',
    ],
    limitations: [
      'Stronger person detection than Tier 1, but equally blind to prints and screens unless they are detected as objects.',
    ],
    code: [
      'server/humandetect_server/',
      'approaches/08-deep-detectors/detectors.py',
    ],
  ),
  '09': ApproachDetails(
    id: '09',
    title: 'Open VLM judge',
    question: 'If a small open vision-language model is asked what the photo shows, does it say "a real person"?',
    steps: [
      'The phone sends the photo to the server.',
      'SmolVLM2 is asked a five-option question: A real person · B person on a screen · C printed photo, poster or ID card · D painting, drawing, statue, mannequin or cartoon · E no person.',
      'Instead of generating text, the server reads the model\'s probability for each letter. The score is the probability of A.',
      'PASS if A ≥ 0.5; otherwise the reason comes from the most likely other option (RECAPTURE, NOT_REAL or NO_HUMAN).',
    ],
    components: [
      Component(
        'SmolVLM2-500M-Video-Instruct',
        'model',
        'Apache-2.0',
        'HuggingFaceTB/SmolVLM2-500M-Video-Instruct (pinned commit), run on our own machine. Photos never go to a third party.',
      ),
      Component(
        'transformers, PyTorch, torchvision',
        'package',
        'Apache-2.0 / BSD',
        'Inference.',
      ),
      Component(
        'num2words',
        'package',
        'LGPL',
        'Needed by SmolVLM\'s processor. Server-side only and never shipped in the app: accepted as an exception in THIRD_PARTY_LICENSES.md.',
      ),
      Component(
        'Question and parsing',
        'own code',
        'this repo',
        'Prompt, option table and score.',
      ),
    ],
    thresholds: [("Min probability of 'real person'", '0.5')],
    catches: [
      'F1: no person (all scenes rejected, reason NO_HUMAN)',
      'F2: screens and prints (all 8 test recaptures rejected)',
      'F5: paintings, statues, mannequins (all 6 rejected)',
    ],
    misses: [
      'It is cautious about real people too: 3 of 7 genuine photos were rejected (a person in front of a TV, a crowded selfie, a stylised portrait).',
    ],
    verified: [
      '26-image smoke test: 23/26 correct, ROC-AUC 0.92, the best of the Tier 2 approaches on this set.',
    ],
    limitations: [
      'Not a production candidate: heavy (1+ GB), about 0.5–3 s per photo on an M4, and answers vary with wording. Use it as an accuracy ceiling and as a labeler for training approaches.',
      'Smoke-test set is small and partly synthetic.',
    ],
    code: [
      'server/humandetect_server/',
      'approaches/09-open-vlm-benchmark/vlm_judge.py',
    ],
  ),
  '15': ApproachDetails(
    id: '15',
    title: 'Pipeline',
    question:
        'Did this photo pass the cheap checks first, and the slow judge last?',
    steps: [
      'Choose Capture or Upload. Capture is a photo taken in the app. Upload is a gallery file.',
      'Capture runs 05 (blink and head turn; BlazeFace here also covers face detection), then 03 (live session, real phone, GPS), then 04 (blur, glare, contrast, moiré, EXIF), then 02 (TinyCLIP).',
      'Upload skips 05 and 03 and starts at 04, then 02. There is no live face and no session to prove.',
      'The first phone failure stops the run and asks for a retake. The photo is not sent to the server.',
      'If the phone passes, the server runs 08 (one clear person), then 07 (already submitted?), then 06 (face, and not a screen or a painting), then 09 (SmolVLM2, the final judge).',
      '06 is weak on its own, so a failure there is kept as a note. It does not reject the photo unless a later hard step also fails. 09 decides when it runs.',
      'Each step has a switch. A switched-off step is skipped. Approaches 10–14 are not in this pipeline.',
    ],
    components: [
      Component(
        'Phone stages 05, 03, 04, 02',
        'own code',
        'this repo',
        'The same checks as the individual tiles, run in order.',
      ),
      Component(
        'Server stages 08, 07, 06, 09',
        'own code',
        'this repo',
        'POST /v1/pipeline. Models stay the ones already used by those tiles.',
      ),
    ],
    thresholds: [
      ('Each step', 'Uses that step\'s own defaults'),
      ('06', 'A note, not a hard reject'),
    ],
    catches: [
      'Capture: a print or a still cannot blink and turn (05), and a gallery file cannot pass 03.',
      'Both paths: blur, glare, moiré (04) and an obvious non-person (02) stop before the server.',
      'Server: no person (08), a reused photo (07), and the VLM\'s verdict (09).',
    ],
    misses: [
      '08 does not see prints and screens. 06 is too weak to reject alone. 09 is slow and cautious about some real people.',
      'An upload cannot prove the person is here now.',
    ],
    verified: [
      'Server pipeline tests with stand-in checks: a hard failure stops the rest, 06 does not reject alone, and a photo is stored for duplicate search only after the pipeline accepts it.',
      'The phone\'s stage order is unit-tested for both paths and for switches.',
    ],
    limitations: [
      '10–14 stay out until there is a labeled dataset.',
      'Switches and the diagram are for the lab. A modified app can still skip a phone check; the server stages are the ones a modified app cannot skip.',
    ],
    code: [
      'app/lib/approaches/a15_pipeline/',
      'server/humandetect_server/pipeline.py',
      'approaches/15-hybrid-pipeline/',
    ],
  ),
};
