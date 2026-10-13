"""Runs approach 02 on images with the exported LiteRT model, exactly as the app does.

Usage: uv run --group models python approaches/02-zero-shot-clip/classify.py IMAGE [IMAGE ...] [--threshold 0.5]
Needs app/assets/models/tinyclip_* (run export_tinyclip.py first).
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from zero_shot import PromptSet, judge, preprocess

MODELS = Path(__file__).resolve().parents[2] / "app/assets/models"


def load_prompts(path: Path = MODELS / "tinyclip_prompts.json") -> PromptSet:
    spec = json.loads(path.read_text())
    return PromptSet(
        spec["prompt_version"],
        [p["text"] for p in spec["prompts"]],
        [p["bucket"] for p in spec["prompts"]],
        np.array([p["embedding"] for p in spec["prompts"]], dtype=np.float32),
        spec["logit_scale"],
        spec["reasons"],
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("images", nargs="+")
    parser.add_argument("--threshold", type=float, default=0.5)
    args = parser.parse_args()

    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=str(MODELS / "tinyclip_image_encoder.tflite"))
    interpreter.allocate_tensors()
    inp, out = interpreter.get_input_details()[0]["index"], interpreter.get_output_details()[0]["index"]
    prompts = load_prompts()
    for path in args.images:
        interpreter.set_tensor(inp, preprocess(ImageOps.exif_transpose(Image.open(path))))
        interpreter.invoke()
        v = judge(interpreter.get_tensor(out)[0], prompts, args.threshold)
        buckets = ", ".join(f"{b}={s:.2f}" for b, s in sorted(v.bucket_scores.items(), key=lambda kv: -kv[1]))
        print(f"{Path(path).name}: {'PASS' if v.passed else 'FAIL'} score={v.score:.2f} {v.reasons} [{buckets}]")


if __name__ == "__main__":
    main()
