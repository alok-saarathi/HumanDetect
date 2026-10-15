"""Downloads and loads every Tier 2 model once, so the first real request is fast.

    uv run --group models --group server python -m humandetect_server.warmup [--only 08 09]

Models are cached by Hugging Face (~/.cache/huggingface, or $HF_HOME). Run it during
deployment, then start the server. Needs internet the first time only.
"""

from __future__ import annotations

import argparse
import time

from . import registry


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="+", choices=sorted(registry.APPROACHES), help="approach ids (default: all)")
    args = parser.parse_args()
    for approach_id in args.only or sorted(registry.APPROACHES):
        start = time.perf_counter()
        approach = registry.get(approach_id)
        if approach_id == "08":
            approach._get(1)  # D-FINE, the optional second model
        print(f"{approach_id} {approach.title}: ready in {time.perf_counter() - start:.1f} s", flush=True)


if __name__ == "__main__":
    main()
