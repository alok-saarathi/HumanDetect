# HumanDetect

Checks that a customer photo uploaded from our Android app shows a **real, live human**, not a wall, a screen, a printout, a painting or a reused photo. It is a lab for trying approaches from easiest to toughest and keeping the ones that work.

Everything here is open and license-clean (MIT, Apache-2.0, BSD, CC0/CC BY): see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Where to start

| I want to… | Read |
|---|---|
| See the plan, every approach and its status | [plan.md](plan.md) |
| Try the app on a phone | [app/README.md](app/README.md), APKs on the [Releases](../../releases) page |
| **Run the server on my Mac and test with a phone on the same Wi-Fi** | **[SERVER_SETUP.md, Part A](SERVER_SETUP.md#part-a--your-mac-as-the-server-start-here)**: `server/start_mac.sh` |
| Deploy the server on a dedicated machine | [SERVER_SETUP.md, Part B](SERVER_SETUP.md#part-b--deploying-on-a-dedicated-server); API in [server/README.md](server/README.md) |
| Understand one approach | `approaches/<NN>-…/README.md` (what, how, findings) or the **Details** button in the app |
| See the applicant-photo check wired into Pravesh | [PRAVESH_FACE_CHECK.md](PRAVESH_FACE_CHECK.md): BlazeFace on the phone and the server, float16, and the APK size |
| Build the dataset and the shared scoring | [dataset/README.md](dataset/README.md), [evaluation/README.md](evaluation/README.md) |
| Check what we may use | [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) |

## What exists today

| Tier | Approaches | Runs | Status |
|---|---|---|---|
| 1 | 01 face detection · 02 zero-shot (TinyCLIP) · 03 capture integrity · 04 recapture forensics · 05 active liveness | on the phone | prototypes in the lab app (0.1.x) |
| 2 | 06 zero-shot detection · 07 duplicate detection · 08 deep detectors · 09 open VLM judge | on our server | prototypes in server + app (0.2.x) |
| 3 | 10–14 trained on our own dataset · 15 hybrid pipeline | | not started: needs the dataset |

All results so far come from small smoke tests on public-domain images, not a real evaluation. The next step is the dataset ([dataset/README.md](dataset/README.md)) so approaches can be compared fairly.

## Repository layout

```
app/          Flutter lab app (Android): a tile per approach
server/       FastAPI service for Tier 2, with tests and a CLI
approaches/   one folder per approach: reference code, notes, findings
dataset/      plan for our own open dataset (images are git-ignored)
evaluation/   shared results format and metrics
plan.md       the master tracker
```

## Try it in 3 steps (Mac + Android phone on the same Wi-Fi)

1. **Mac:** `git clone https://github.com/alok-saarathi/HumanDetect.git && cd HumanDetect && server/start_mac.sh --warmup`. It prints the address to use.
2. **Phone:** install the lab APK from [Releases](../../releases) (0.2.0 or newer).
3. **Phone:** open the app, type the Mac's address when asked, press **Test**, then **Save**. Tier 1 tiles work without the server; Tier 2 tiles use it. If the Mac's address changes later, tap the cloud icon to change it.

Full guide, with troubleshooting: [SERVER_SETUP.md](SERVER_SETUP.md).

## Quick start (development)

```
# Python side (needs uv: https://docs.astral.sh/uv/)
uv sync --group models --group server
uv run --group models --group server python -m pytest server/tests      # 10 tests, no downloads

# App side (Flutter 3.47, JDK 17, Android SDK 36: versions in app/README.md)
cd app && flutter test                                                    # 47 tests
```
