#!/usr/bin/env bash
# Starts the HumanDetect server on this Mac for testing with a phone on the same Wi-Fi,
# and prints the address to type into the app (Server button on the home screen).
#
#   server/start_mac.sh                 start on port 8765
#   server/start_mac.sh --warmup        download/load the models first (first run: ~2.7 GB)
#   server/start_mac.sh --port 9000     use another port
#   HUMANDETECT_TOKEN=abc server/start_mac.sh   require a token (enter it in the app too)
#
# Stop with Ctrl-C. The address changes if the Mac joins another network or gets a new
# lease: run the script again and update it in the app.
set -euo pipefail

PORT=8765
WARMUP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:?--port needs a number}"; shift 2 ;;
    --warmup) WARMUP=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not installed. Install it with:  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  echo "then open a new terminal and run this script again." >&2
  exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use (is the server already running?)." >&2
  echo "Stop it, or choose another port with --port." >&2
  exit 1
fi

# The Mac's address on the local network: Wi-Fi is usually en0, a cable/dongle en1+.
ADDRESSES=()
for iface in en0 en1 en2 en3 en4; do
  ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  [[ -n "$ip" ]] && ADDRESSES+=("$ip $iface")
done

echo "Installing/checking Python packages (first run takes a few minutes)…"
uv sync --group models --group server --quiet

if [[ "$WARMUP" == 1 ]]; then
  echo "Loading models…"
  PYTHONPATH=server uv run --group models --group server python -m humandetect_server.warmup
fi

echo
echo "=============================================================="
if [[ ${#ADDRESSES[@]} -eq 0 ]]; then
  echo " No network address found. Connect the Mac to Wi-Fi (same network as the phone)."
  echo " The server will still start on this Mac: http://localhost:$PORT"
else
  echo " In the app: home screen > Server, then enter one of:"
  for a in "${ADDRESSES[@]}"; do
    ip="${a%% *}"; iface="${a##* }"
    if [[ "$PORT" == 8765 ]]; then
      echo "     $ip        [$iface]   (the app adds http:// and :8765)"
    else
      echo "     http://$ip:$PORT        [$iface]   (type the full address: the port is not 8765)"
    fi
  done
  echo " Press Test, then Save."
fi
[[ -n "${HUMANDETECT_TOKEN:-}" ]] && echo " Token is set: enter the same token in the app." || echo " No token set: anyone on this network can use the server."
echo " The first photo to each approach is slow while its model loads."
echo " If the phone can't connect, see SERVER_SETUP.md > Troubleshooting (macOS firewall)."
echo "=============================================================="
echo

exec uv run --group models --group server uvicorn humandetect_server.app:app \
  --app-dir server --host 0.0.0.0 --port "$PORT"
