# Setting up the HumanDetect server

How to install, start, secure and operate the Tier 2 server (approaches 06–09). For what the server does and its API, see [server/README.md](server/README.md).

| You want to… | Read |
|---|---|
| **Test with a phone, server on your Mac, same Wi-Fi** | **[Part A](#part-a--your-mac-as-the-server-start-here)** (about 10 minutes plus the model download) |
| Run it on a dedicated Linux/macOS machine for others | [Part B](#part-b--deploying-on-a-dedicated-server) |

---

## Part A · Your Mac as the server (start here)

The server runs on your Mac. The phone runs the lab APK and talks to the Mac over the Wi-Fi. Photos go phone → Mac, are judged in memory, and are not stored (approach 07 keeps only fingerprints, in `server/data/`).

```
 phone (lab APK)  ──── Wi-Fi ────►  your Mac  http://<Mac's address>:8765
   Tier 1 tiles run on the phone       Tier 2 tiles: 06 07 08 09
```

### A1. What you need
- A Mac (Apple Silicon recommended: it uses the Apple GPU automatically) with about 10 GB of free disk. The first run downloads about 2.7 GB of models plus the Python packages.
- An Android phone with the lab APK (**0.2.0 or newer**) from the repo's [Releases](../../releases) page.
- The Mac and the phone on **the same Wi-Fi network** (see A6 if they can't see each other).
- [`uv`](https://docs.astral.sh/uv/) (installs Python for you). The script tells you the command if it's missing: `curl -LsSf https://astral.sh/uv/install.sh | sh`, then open a new terminal.

### A2. Start the server
In Terminal:
```
git clone https://github.com/alok-saarathi/HumanDetect.git     # first time only
cd HumanDetect
server/start_mac.sh --warmup
```
- The **first run** installs packages (a few minutes) and, with `--warmup`, downloads and loads the models (several more minutes). Later runs start in seconds; leave `--warmup` off.
- When ready, the script prints a box like this:
  ```
  In the app: home screen > Server, then enter one of:
      192.168.1.3        [en0]   (the app adds http:// and :8765)
  ```
  **That number is the address to type into the phone.** If it lists two addresses (e.g. Wi-Fi `en0` and a cable `en1`), use the one on the same network as the phone.
- Leave the Terminal window open. **Ctrl-C** stops the server.
- Options: `--port 9000` (then type the full `http://192.168.1.3:9000` in the app), and `HUMANDETECT_TOKEN=abc server/start_mac.sh` to require a token (type the same token in the app).

### A3. Connect the phone
1. Install the APK. Open **HumanDetect lab**. On first launch it asks for the Mac address.
2. Type the address from the script (just the number is fine: `192.168.1.3`), press **Test**. You should see "Connected. Approaches on the server: 06, 07, 08, 09". Press **Save**.
3. The address is remembered. The **cloud icon** in the top bar (and the Tier 2 card on the home screen) shows the live status:
   green cloud = connected, red crossed cloud = can't reach the Mac. Tap either to **change the address**; press the refresh arrow to re-check.
4. Open a Tier 2 tile (06–09), take a photo or pick one from the gallery, and read the verdict. The **first photo to each tile is slow** (up to ~10 s) while the Mac loads that model; after that it takes 0.1–4 s.

### A4. When the Mac's address changes
A Mac's address on Wi-Fi is handed out by the router and can change after a restart, a sleep, or when you join another network. When the app shows the red cloud:
1. On the Mac, run `server/start_mac.sh` again: it prints the current address. (Or run `ipconfig getifaddr en0`, or look in **System Settings → Wi-Fi → Details**.)
2. In the app, tap the cloud icon → type the new address → **Test** → **Save**.

To stop it changing: reserve the Mac's address in your router's settings (DHCP reservation), or use the Mac's name, e.g. `http://my-mac.local:8765` (the app accepts it; Android support for `.local` names varies, so try the number first).

### A5. Keep the Mac awake
If the Mac sleeps, the phone can't reach it. While testing, keep it awake: run `caffeinate -d` in a second Terminal tab (Ctrl-C when done), or set **System Settings → Battery/Energy → prevent sleeping** while on power.

### A6. If the phone can't connect
Work through these in order; each takes a minute.
1. **Is the server running?** On the Mac: `curl http://localhost:8765/v1/health` should print `{"ok":true,…}`.
2. **Same network?** The phone must be on the same Wi-Fi as the Mac, not mobile data and not a different SSID. Turn on Wi-Fi and turn off any VPN on the phone.
3. **Test from the phone's browser.** Open `http://<address>:8765/v1/health` in Chrome on the phone. If that shows `{"ok":true,…}` the app will connect too. If not:
4. **Wi-Fi blocks device-to-device traffic.** Guest networks, hotel/café Wi-Fi and some office networks ("client isolation") stop phones from reaching other devices. Use a home/office network that allows it, or put both devices on a phone hotspot (the Mac joins the hotspot; run the script again for the new address).
5. **macOS firewall.** If **System Settings → Network → Firewall** is on, macOS asks "Do you want the application "python" to accept incoming network connections?" the first time: choose **Allow**. If you missed it, add Python under Firewall → Options, or turn the firewall off while testing.
6. **Wrong address or port.** The address is the Mac's, not `localhost` and not the phone's. If you started with `--port`, include it in the address.
7. **VPN on the Mac** can hide the local network. Disconnect it while testing.
8. **Port in use.** The script says so. Our default (8765) avoids 8000, which other tools often use; change it with `--port`.

### A7. Privacy while testing
Photos sent from the phone are judged in memory and not saved. Approach 07 keeps fingerprints (not photos) of every photo it accepts in `server/data/duplicate_index.npz`; delete the file, or call the reset in the table in §7, when you finish testing. Use only photos you may use for testing, and your own network. There is no encryption on plain HTTP: don't test with real customer photos on a shared network.

---

## Part B · Deploying on a dedicated server

For running the server for other people or all the time (Linux or macOS). Part A is enough for testing on your Mac.

**In short**
```
git clone https://github.com/alok-saarathi/HumanDetect.git && cd HumanDetect
uv sync --group models --group server
export HUMANDETECT_TOKEN='<long random string>'
uv run --group models --group server python -m humandetect_server.warmup      # once: downloads ~2.7 GB of models
uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 0.0.0.0 --port 8765
curl localhost:8765/v1/health
```
Then put `http://<server address>:8765` and the token into the app's **Server** dialog.

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
    --app-dir server --host 0.0.0.0 --port 8765
```
- `--host 0.0.0.0` accepts connections from other machines (phones). Use `127.0.0.1` if a reverse proxy on the same machine is in front (§5).
- **Run one worker (the default).** Each worker loads its own copy of every model, and the duplicate index (07) is guarded by an in-process lock, so `--workers 2` would double memory and let two workers write the index at once.
- Each approach loads its model into memory on its **first request** (`warmup` only fills the download cache; it doesn't keep models loaded in the server). So the first request to each approach takes a few seconds. After a restart, warm the server by sending one photo to each approach (§7).

**Check it works**
```
curl http://localhost:8765/v1/health
# {"ok":true,"approaches":["06","07","08","09"]}
curl -X POST --data-binary @some_photo.jpg "http://localhost:8765/v1/check/08"
```

## 4. Settings

| Setting | How | Default |
|---|---|---|
| Shared secret | env `HUMANDETECT_TOKEN`. When set, every `/v1/check/*` and reset request must carry the header `X-HumanDetect-Token: <value>`; the app's Server dialog has a Token field. `/v1/health` and `/v1/approaches` stay open | none: **anyone who can reach the port can use the server** |
| Compute device | env `HUMANDETECT_DEVICE=cpu` (or `cuda`, `cuda:1`, `mps`) | CUDA if present, else Apple GPU, else CPU |
| Model cache folder | env `HF_HOME=/path` | `~/.cache/huggingface` |
| Port and address | uvicorn `--host`, `--port` | 8765 on `0.0.0.0` |
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
ExecStart=/home/humandetect/.local/bin/uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 127.0.0.1 --port 8765
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
    reverse_proxy 127.0.0.1:8765
}
```
Then use `https://humandetect.example.com` in the app. A production app build should also remove `usesCleartextTraffic` from `app/android/app/src/main/AndroidManifest.xml`.

**Firewall.** Open only the proxy's port (443), or port 8765 only to your office/VPN range if you skip the proxy. A phone on the office Wi-Fi can use `http://<server LAN address>:8765` directly.

**Before real customer photos:**
- Set `HUMANDETECT_TOKEN`; add rate limiting at the proxy.
- Photos are judged in memory and not stored, but the 07 index keeps fingerprints of every accepted photo. Decide its retention period and who may access `server/data/` (it is git-ignored). Under India's DPDP Act, treat the fingerprints as derived personal data.
- Don't enable request-body logging on the proxy.

## 6. Running only some approaches

To save memory, serve a subset by editing `APPROACHES` in `server/humandetect_server/registry.py` (delete the lines you don't want; the app shows an error on those tiles). A typical production subset is **07 + 08**: small, fast, no GPU needed. 06 and 09 are slow and are mainly for evaluation and labeling.

## 7. Operating it

| Task | Command |
|---|---|
| Is it up? | `curl localhost:8765/v1/health` |
| List approaches and their thresholds | `curl localhost:8765/v1/approaches` |
| Warm up after a restart | `for a in 06 07 08 09; do curl -s -X POST --data-binary @photo.jpg localhost:8765/v1/check/$a >/dev/null; done` (this adds `photo.jpg` to the 07 index once; reset it after) |
| Empty the duplicate index | `curl -X POST -H "X-HumanDetect-Token: $T" localhost:8765/v1/approaches/07/reset` |
| Back up the index | copy `server/data/duplicate_index.npz` while the server is idle |
| Update the code | `git pull && uv sync --group models --group server`, then restart the service |
| Run the tests | `uv run --group models --group server python -m pytest server/tests` (no model downloads needed) |
| Score an approach on a folder | `PYTHONPATH=server uv run --group models --group server python -m humandetect_server.cli eval 08 data/eval/dev` |

## 8. Connect the phone

1. Install the lab APK (0.2.0 or newer) from the repo's Releases.
2. On the home screen press **Server**, enter the address (`http://192.168.x.x:8765` or your HTTPS address) and the token, press **Test**: it should say "Connected" and list `06, 07, 08, 09`.
3. Open a Tier 2 tile and take or pick a photo. The first photo to each approach is slow while its model loads.

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| App: "Cannot reach http://…" | Server not running, wrong address, phone not on the same network, or a firewall. Try `curl http://<address>:8765/v1/health` from another machine. Use the machine's LAN address, not `localhost` |
| App: "Server said 401" | Token missing or different. Set the same value in the app |
| App: "Server said 415" | The file is not an image the server can open (very large HEIC, corrupt file). The app sends JPEG/PNG/WebP |
| First photo takes 10+ s, or the app times out | Models loading. Run `warmup` before starting, and send one photo per approach after each restart. The app waits up to 4 minutes |
| `ImportError: … requires the Torchvision library` / `num2words` | The `server` group is missing. Run `uv sync --group models --group server` |
| Killed / out of memory when starting 09 | Not enough RAM. Remove 09 (§6) or add memory |
| `CUDA out of memory` | Another process holds the GPU. Set `HUMANDETECT_DEVICE=cpu` or give the server its own GPU |
| MPS errors on Apple Silicon | Set `HUMANDETECT_DEVICE=cpu` |
| `Repository Not Found` / download errors | No access to huggingface.co from that machine. Run `warmup` where there is, then copy the cache folder (`HF_HOME`) |
| 07 says DUPLICATE for a photo you never sent | You sent it during testing. Reset the index (§7) |
| Port already in use | Another process uses 8765 (our default avoids the common 8000): change `--port`, or find it with `lsof -i :8765` |
