# 03 · Harden the capture flow

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**What it is:** a product control, not a detector. It's all our own code, and it can run in parallel with the rest of the ladder.

**Idea:** make faking hard before any model runs.
- Allow in-app camera capture only (`camera` in Flutter, BSD-3), with no gallery picker.
- Stamp each capture with timestamp, GPS, device ID and a server-issued nonce.
- Have the server reject uploads missing any of these.
- **Optional:** Google's Play Integrity API to detect modified apps. It's a proprietary service, so using it is a team decision under the ground rules.

**Catches:** F3 strongly. Makes F1 and F2 traceable, because time and location can be checked against the visit.

**Watch out:**
- It doesn't stop someone pointing the camera at a wall or a screen.
- Rooted or modified devices can bypass client-side rules.
- Its real impact can only be measured in the production app.

## Implementation (lab app 0.1.0)

**Status:** prototype in the app (tile 03). Needs a phone test, then a design with the production app and server team.

**Code:** `app/lib/approaches/a03_capture_integrity/capture_integrity_check.dart`. There's no Python part, because it's pure app logic.

**How it works in the app:**
1. **Session start:** opening the camera screen creates a random 128-bit nonce and starts a high-accuracy GPS fix (15 s limit). Device details are read via `device_info_plus`.
2. **Capture source:** photos only come from the in-app camera; the app has no gallery picker anywhere.
3. **Checks** (all thresholds adjustable in the app):

   | Check | Default limit | Reason code on failure |
   |---|---|---|
   | Fresh session | ≤ 120 s | `STALE_SESSION` |
   | Real device | not an emulator (`isPhysicalDevice`) | `EMULATOR` |
   | Location available | — | `NO_LOCATION` |
   | Location precise | ≤ 50 m | `LOW_LOCATION_ACCURACY` |
   | Location recent | ≤ 120 s | `NO_LOCATION` |
   | Location not mocked | Android mock flag | `MOCK_LOCATION` |

4. **Receipt:** SHA-256 of the JPEG, plus HMAC-SHA256 over `{nonce, photo hash, time, lat, lon, device}`.

**Demo limits:**
- The nonce and HMAC key are made on the phone. In production the server issues the nonce and verifies the receipt, and the key never ships in the app.
- **Play Integrity is not used:** it's a proprietary service, so it's a team decision.

**Packages:**
- `geolocator_android` + `geolocator_platform_interface` (MIT). The Android implementation is used directly, which avoids MPL-licensed Linux dependencies.
- `device_info_plus` (BSD-3).
- `crypto` (BSD-3).
