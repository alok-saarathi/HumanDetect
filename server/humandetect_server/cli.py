"""Run Tier 2 approaches from the command line, without the phone.

From the repo root:
    uv run --group models --group server python -m humandetect_server.cli check 08 IMAGE [IMAGE ...] [--param min_area=0.05]
    uv run --group models --group server python -m humandetect_server.cli eval 06 DIR [--csv out.csv]

`eval` expects DIR/<label>/*.jpg (as in data/eval/<split>/): "live" is genuine, every
other folder is a fake. It prints per-image verdicts, accuracy, and the ROC-AUC of the
score, and can write the shared results CSV (evaluation/README.md).
(Run with PYTHONPATH=server, or from inside server/.)
"""

from __future__ import annotations

import argparse
import csv
import platform
import time
from pathlib import Path

from PIL import Image, ImageOps

from . import registry

EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def _params(pairs: list[str]) -> dict[str, float]:
    out = {}
    for pair in pairs:
        key, _, value = pair.partition("=")
        out[key] = float(value)
    return out


def _load(path: Path) -> Image.Image:
    return ImageOps.exif_transpose(Image.open(path)).convert("RGB")


def _run(approach_id: str, path: Path, params: dict[str, float]):
    approach = registry.get(approach_id)
    start = time.perf_counter()
    result = approach.check(_load(path), params)
    return result, (time.perf_counter() - start) * 1000


def auc(live: list[float], fake: list[float]) -> float:
    pairs = [1.0 if a > b else 0.5 if a == b else 0.0 for a in live for b in fake]
    return sum(pairs) / len(pairs) if pairs else float("nan")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("check")
    c.add_argument("approach", choices=sorted(registry.APPROACHES))
    c.add_argument("images", nargs="+", type=Path)
    c.add_argument("--param", action="append", default=[], help="tunable=value")
    e = sub.add_parser("eval")
    e.add_argument("approach", choices=sorted(registry.APPROACHES))
    e.add_argument("dir", type=Path)
    e.add_argument("--param", action="append", default=[])
    e.add_argument("--csv", type=Path, help="write results in the shared CSV format")
    args = parser.parse_args()
    params = _params(args.param)

    if args.command == "check":
        for path in args.images:
            r, ms = _run(args.approach, path, params)
            print(f"{path.name}: {'PASS' if r.passed else 'FAIL'} score={r.score:.3f} {r.reasons} ({ms:.0f} ms)")
            for label, value in r.details:
                print(f"    {label}: {value}")
        return

    items = sorted((p, p.parent.name) for p in args.dir.rglob("*") if p.suffix.lower() in EXTENSIONS)
    rows, live, fake, correct = [], [], [], 0
    for path, label in items:
        r, ms = _run(args.approach, path, params)
        genuine = label == "live"
        correct += r.passed == genuine
        (live if genuine else fake).append(r.score)
        print(f"{label:10s} {'PASS' if r.passed else 'FAIL'} {r.score:.3f} {','.join(r.reasons):28s} {ms:6.0f} ms  {path.name[:48]}")
        rows.append({"image": str(path.relative_to(args.dir)), "label": label, "split": "", "approach": args.approach,
                     "variant": "", "runtime": "python-server", "device": platform.machine(),
                     "passed": str(r.passed).lower(), "score": f"{r.score:.4f}", "reasons": ";".join(r.reasons),
                     "latency_ms": f"{ms:.1f}", "config": ";".join(f"{k}={v}" for k, v in params.items())})
    print(f"\ncorrect {correct}/{len(items)}   ROC-AUC of score {auc(live, fake):.3f}   (live {len(live)}, fake {len(fake)})")
    if args.csv:
        with args.csv.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        print(f"wrote {args.csv}")


if __name__ == "__main__":
    main()
