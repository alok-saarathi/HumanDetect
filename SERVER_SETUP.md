# Setting up the HumanDetect server

How to install, start, secure and operate the Tier 2 server (approaches 06–09) on a Linux or macOS machine. For what the server does and its API, see [server/README.md](server/README.md).

**In short**
```
git clone https://github.com/alok-saarathi/HumanDetect.git && cd HumanDetect
uv sync --group models --group server
export HUMANDETECT_TOKEN='<long random string>'
uv run --group models --group server python -m humandetect_server.warmup      # once: downloads ~2.7 GB of models
uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 0.0.0.0 --port 8000
curl localhost:8000/v1/health
```
Then put `http://<server address>:8000` and the token into the app's **Server** dialog.

## 1. Requirements

| | Minimum | Notes |
|---|---|---|
| OS | Linux (x86-64 or arm64) or macOS | Tested on macOS 15, Apple M4 |
| Python | 3.11, 3.12 or 3.13 | `uv` installs one for you. 3.14 is not supported yet |
| Memory | 8 GB free (recommended) | We have not measured peak memory on a CPU/CUDA server (on the Apple GPU it doesn't show up in the usual counters). The model weights are 2.7 GB on disk (09 alone is 1.9 GB), so allow that plus headroom. 07 and 08 alone are about 0.2 GB of weights |
| Disk | 10 GB free | Python packages (PyTorch is most of it, several GB on Linux) + 2.7 GB of models + working space |
| GPU | optional | NVIDIA (CUDA) or Apple (MPS) is used automatically. On CPU everything works, but expect seconds per photo instead of 0.1–4 s |
| Network | internet for setup | Hugging Face and PyPI. Afterwards the server needs no internet |

**Speed (measured on an Apple M4 GPU, after loading):** 08 about 0.1 s · 07 about 0.2 s · 06 about 1.5 s · 09 about 0.5–4 s. On a CPU-only server expect it to be slower, by an amount we haven't measured; 09 and 06 are the ones to switch off if that is too slow (§6).

## 2. Install

1. **Install `uv`** (the Python package manager this repo uses):
   ```
   curl -LsSf https://astral.sh/uv/install.sh | sh        # Linux / macOS
   ```
   Open a new shell, then check `uv --version`.
2. **Get the code:**
   ```
   git clone https://github.com/alok-saarathi/HumanDetect.git
   cd HumanDetect
   ```
   You don't need Git LFS for the server. If your Git is set up for LFS, `GIT_LFS_SKIP_SMUDGE=1 git clone …` skips downloading APKs.
3. **Install the packages** (a few minutes; a few GB):
   ```
   uv sync --group models --group server
   ```
   - `models` brings PyTorch and `transformers`; `server` brings FastAPI and the rest.
   - **On Linux the default PyTorch wheel includes NVIDIA CUDA libraries** (several GB extra), even on a machine with no GPU. That is harmless, just large.
   - **Licenses:** all packages are open source. The one exception to our "no copyleft" rule is `num2words` (LGPL), which approach 09's model needs. It is accepted for server-side use only: see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
4. **Download the models once** (about 2.7 GB: OWLv2 593 MB, SmolVLM2 1.9 GB, DINOv2 84 MB, RT-DETR 77 MB, D-FINE 40 MB; cached under `~/.cache/huggingface`):
   ```
   uv run --group models --group server python -m humandetect_server.warmup
   ```
   It prints a line per approach when ready. Add `--only 07 08` to load just some. If the server can't reach the internet later, this cache is all it needs; to move it between machines, copy the folder or set `HF_HOME`.

## 3. Start the server

```
uv run --group models --group server uvicorn humandetect_server.app:app \
    --app-dir server --host 0.0.0.0 --port 8000
```
- `--host 0.0.0.0` accepts connections from other machines (phones). Use `127.0.0.1` if a reverse proxy on the same machine is in front (§5).
- **Run one worker (the default).** Each worker loads its own copy of every model, and the duplicate index (07) is guarded by an in-process lock, so `--workers 2` would double memory and let two workers write the index at once.
- Each approach loads its model into memory on its **first request** (`warmup` only fills the download cache; it doesn't keep models loaded in the server). So the first request to each approach takes a few seconds. After a restart, warm the server by sending one photo to each approach (§7).

**Check it works**
```
curl http://localhost:8000/v1/health
# {"ok":true,"approaches":["06","07","08","09"]}
curl -X POST --data-binary @some_photo.jpg "http://localhost:8000/v1/check/08"
```

## 4. Settings

| Setting | How | Default |
|---|---|---|
| Shared secret | env `HUMANDETECT_TOKEN`. When set, every `/v1/check/*` and reset request must carry the header `X-HumanDetect-Token: <value>`; the app's Server dialog has a Token field. `/v1/health` and `/v1/approaches` stay open | none: **anyone who can reach the port can use the server** |
| Compute device | env `HUMANDETECT_DEVICE=cpu` (or `cuda`, `cuda:1`, `mps`) | CUDA if present, else Apple GPU, else CPU |
| Model cache folder | env `HF_HOME=/path` | `~/.cache/huggingface` |
| Port and address | uvicorn `--host`, `--port` | 8000 on `0.0.0.0` |
| Upload limit | `MAX_BYTES` in `server/humandetect_server/app.py` | 25 MB |
| Duplicate index | file `server/data/duplicate_index.npz` | created on first use |

## 5. Running it for real

**Keep it running (Linux, systemd).** Create `/etc/systemd/system/humandetect.service` (change the user and paths):
```ini
[Unit]
Description=HumanDetect Tier 2 server
After=network-online.target
Wants=network-online.target

[Service]
User=humandetect
WorkingDirectory=/opt/HumanDetect
Environment=HUMANDETECT_TOKEN=change-me-to-a-long-random-string
Environment=HF_HOME=/opt/HumanDetect/.hf-cache
ExecStart=/home/humandetect/.local/bin/uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
```
sudo systemctl daemon-reload && sudo systemctl enable --now humandetect
journalctl -u humandetect -f          # logs
```
Prefer a root-readable file for the token (`EnvironmentFile=/etc/humandetect.env`, mode 600) over putting it in the unit.

**Use HTTPS.** The app's lab builds talk plain HTTP, so anything crossing the internet must go through a TLS-terminating reverse proxy, e.g. Caddy (automatic certificates):
```
# /etc/caddy/Caddyfile
humandetect.example.com {
    request_body {
        max_size 26MB
    }
    reverse_proxy 127.0.0.1:8000
}
```
Then use `https://humandetect.example.com` in the app. A production app build should also remove `usesCleartextTraffic` from `app/android/app/src/main/AndroidManifest.xml`.

**Firewall.** Open only the proxy's port (443), or port 8000 only to your office/VPN range if you skip the proxy. A phone on the office Wi-Fi can use `http://<server LAN address>:8000` directly.

**Before real customer photos:**
- Set `HUMANDETECT_TOKEN`; add rate limiting at the proxy.
- Photos are judged in memory and not stored, but the 07 index keeps fingerprints of every accepted photo. Decide its retention period and who may access `server/data/` (it is git-ignored). Under India's DPDP Act, treat the fingerprints as derived personal data.
- Don't enable request-body logging on the proxy.

## 6. Running only some approaches

To save memory, serve a subset by editing `APPROACHES` in `server/humandetect_server/registry.py` (delete the lines you don't want; the app shows an error on those tiles). A typical production subset is **07 + 08**: small, fast, no GPU needed. 06 and 09 are slow and are mainly for evaluation and labeling.

## 7. Operating it

| Task | Command |
|---|---|
| Is it up? | `curl localhost:8000/v1/health` |
| List approaches and their thresholds | `curl localhost:8000/v1/approaches` |
| Warm up after a restart | `for a in 06 07 08 09; do curl -s -X POST --data-binary @photo.jpg localhost:8000/v1/check/$a >/dev/null; done` (this adds `photo.jpg` to the 07 index once; reset it after) |
| Empty the duplicate index | `curl -X POST -H "X-HumanDetect-Token: $T" localhost:8000/v1/approaches/07/reset` |
| Back up the index | copy `server/data/duplicate_index.npz` while the server is idle |
| Update the code | `git pull && uv sync --group models --group server`, then restart the service |
| Run the tests | `uv run --group models --group server python -m pytest server/tests` (no model downloads needed) |
| Score an approach on a folder | `PYTHONPATH=server uv run --group models --group server python -m humandetect_server.cli eval 08 data/eval/dev` |

## 8. Connect the phone

1. Install the lab APK (0.2.0 or newer) from the repo's Releases.
2. On the home screen press **Server**, enter the address (`http://192.168.x.x:8000` or your HTTPS address) and the token, press **Test**: it should say "Connected" and list `06, 07, 08, 09`.
3. Open a Tier 2 tile and take or pick a photo. The first photo to each approach is slow while its model loads.

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| App: "Cannot reach http://…" | Server not running, wrong address, phone not on the same network, or a firewall. Try `curl http://<address>:8000/v1/health` from another machine. Use the machine's LAN address, not `localhost` |
| App: "Server said 401" | Token missing or different. Set the same value in the app |
| App: "Server said 415" | The file is not an image the server can open (very large HEIC, corrupt file). The app sends JPEG/PNG/WebP |
| First photo takes 10+ s, or the app times out | Models loading. Run `warmup` before starting, and send one photo per approach after each restart. The app waits up to 4 minutes |
| `ImportError: … requires the Torchvision library` / `num2words` | The `server` group is missing. Run `uv sync --group models --group server` |
| Killed / out of memory when starting 09 | Not enough RAM. Remove 09 (§6) or add memory |
| `CUDA out of memory` | Another process holds the GPU. Set `HUMANDETECT_DEVICE=cpu` or give the server its own GPU |
| MPS errors on Apple Silicon | Set `HUMANDETECT_DEVICE=cpu` |
| `Repository Not Found` / download errors | No access to huggingface.co from that machine. Run `warmup` where there is, then copy the cache folder (`HF_HOME`) |
| 07 says DUPLICATE for a photo you never sent | You sent it during testing. Reset the index (§7) |
| Port already in use | Another process uses 8000: change `--port`, or `lsof -i :8000` |
