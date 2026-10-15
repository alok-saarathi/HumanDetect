# HumanDetect server (Tier 2)

A small FastAPI service (deployment option D3) that runs the approaches too big for a phone. The lab app's Tier 2 tiles send it the photo; it judges the photo **in memory and never stores it**. Approach 07 keeps only fingerprints.

| Id | Approach | Models (all open) |
|---|---|---|
| 06 | Zero-shot detection | OWLv2 base/16 (Apache-2.0). Grounding DINO tiny kept for CLI comparison |
| 07 | Duplicate detection | pHash (`imagehash`, BSD-2) + DINOv2-small (Apache-2.0) |
| 08 | Open deep detectors | RT-DETRv2 R18, D-FINE small (Apache-2.0) |
| 09 | Open VLM judge | SmolVLM2-500M (Apache-2.0); needs `num2words` (LGPL, see THIRD_PARTY_LICENSES.md) |

Models download from Hugging Face on first use (2.7 GB in total, cached), at pinned commits.

## Run it

**Testing with a phone on your Mac?** Run `server/start_mac.sh` and follow [SERVER_SETUP.md, Part A](../SERVER_SETUP.md#part-a--your-mac-as-the-server-start-here): it starts the server, prints the address to type into the app, and covers changing it, Wi-Fi problems and the firewall. **Deploying on a dedicated machine?** See Part B of the same guide. The manual commands:

From the repo root:
```
uv sync --group models --group server
uv run --group models --group server python -m humandetect_server.warmup   # optional: download models now
uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 0.0.0.0 --port 8765
```
- It uses the Apple GPU (MPS), CUDA or the CPU automatically. Force one with `HUMANDETECT_DEVICE=cpu`.
- Models load on first use of each approach, so the first request to an approach takes several seconds (06: ~5 s, 09: ~10 s on an M4).
- Optional shared secret: set `HUMANDETECT_TOKEN=...` and enter the same value in the app's Server dialog.

**Phone to computer:** on the same Wi-Fi, open the app's **Server** button on the home screen, enter `http://<computer's LAN address>:8765` (e.g. from `ipconfig getifaddr en0`), press **Test**.
- Lab builds use plain HTTP (`usesCleartextTraffic`). A real deployment needs HTTPS, authentication and a rate limit.
- Allow incoming connections if the macOS firewall asks.

## API

| Endpoint | |
|---|---|
| `GET /v1/health` | `{ok, approaches}` |
| `GET /v1/approaches` | per approach: `id`, `title`, `score_label`, `tunables[{key,label,min,max,default,decimals}]` |
| `POST /v1/check/{id}?<tunable>=<value>` | body = the image bytes. Returns `{passed, score, reasons[], details[[label,value]], marks[{box:[x,y,w,h],label}], latency_ms}` |
| `POST /v1/approaches/07/reset` | empties the duplicate index (lab use) |

Errors: 400 (empty body or bad parameter), 401 (token), 404 (unknown approach), 413 (over 25 MB), 415 (not an image).
```
curl -X POST --data-binary @photo.jpg "localhost:8765/v1/check/08?min_area=0.05"
```

## Command line (no phone needed)

```
export PYTHONPATH=server
uv run --group models --group server python -m humandetect_server.cli check 08 photo.jpg
uv run --group models --group server python -m humandetect_server.cli eval 09 data/eval/dev --csv results.csv
```
`eval` takes a folder with one sub-folder per label (`live` is genuine, everything else is fake), prints each verdict and the accuracy and ROC-AUC, and writes the shared results CSV ([evaluation/README.md](../evaluation/README.md)).

## Layout and tests

```
server/humandetect_server/   app.py (HTTP) · registry.py (loads approaches by id) · contract.py (Result, Tunable) · device.py · cli.py
server/tests/test_server.py  API, token, errors, EXIF, duplicate flow, geometry. No model downloads: uv run --group models --group server python -m pytest server/tests
server/data/                 duplicate index (git-ignored: fingerprints of customer photos)
approaches/06..09/           the approach code the server loads
```
To add an approach: write a class with `id`, `title`, `score_label`, `tunables`, `load()` and `check(image, params) -> Result`, and list it in `registry.APPROACHES`. Then add its tile and Details text in the app.
