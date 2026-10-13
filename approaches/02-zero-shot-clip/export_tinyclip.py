"""Exports TinyCLIP's image encoder to LiteRT and the prompt embeddings to JSON for the app.

Usage: uv run --group models --group export python approaches/02-zero-shot-clip/export_tinyclip.py \
           [--model tinyclip-39m|tinyclip-8m] [--prompts PATH] [--no-int8]

Writes into app/assets/models/:
  tinyclip_image_encoder.tflite   input (1, 224, 224, 3) RGB in [0, 1] -> (1, 512) normalized embedding;
                                  weights quantized to int8 (dynamic range) unless --no-int8
  tinyclip_prompts.json           prompt texts, buckets, embeddings, logit scale, reason codes

Then checks that LiteRT and PyTorch embeddings agree (cosine >= 0.98 with int8 weights,
>= 0.99 with float32) on random inputs.
"""

import argparse
import json
from pathlib import Path

import numpy as np
import torch

from zero_shot import DEFAULT_MODEL, DEFAULT_PROMPTS, IMAGE_SIZE, MODELS, ImageEncoder, build_prompt_set, load_clip

OUT_DIR = Path(__file__).resolve().parents[2] / "app/assets/models"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=sorted(MODELS), default=DEFAULT_MODEL)
    parser.add_argument("--prompts", type=Path, default=DEFAULT_PROMPTS)
    parser.add_argument("--no-int8", action="store_true", help="keep float32 weights")
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    clip, tokenizer = load_clip(args.model)
    encoder = ImageEncoder(clip).eval()

    import litert_torch

    sample = (torch.rand(1, IMAGE_SIZE, IMAGE_SIZE, 3),)
    model_path = OUT_DIR / "tinyclip_image_encoder.tflite"
    litert_torch.convert(encoder, sample).export(str(model_path))
    if not args.no_int8:
        from ai_edge_quantizer import quantizer, recipe

        quantizer.Quantizer(str(model_path), recipe.dynamic_wi8_afp32()).quantize().export_model(
            str(model_path), overwrite=True
        )
    print(f"wrote {model_path} ({model_path.stat().st_size / 1e6:.1f} MB)")

    prompts = build_prompt_set(clip, tokenizer, args.prompts)
    prompts_path = OUT_DIR / "tinyclip_prompts.json"
    prompts_path.write_text(
        json.dumps(
            {
                "model": "{}@{}".format(*MODELS[args.model]),
                "weights": "float32" if args.no_int8 else "int8 dynamic range",
                "prompt_version": prompts.version,
                "logit_scale": prompts.logit_scale,
                "reasons": prompts.reasons,
                "prompts": [
                    {"text": t, "bucket": b, "embedding": [round(float(v), 6) for v in e]}
                    for t, b, e in zip(prompts.texts, prompts.buckets, prompts.embeddings)
                ],
            },
            indent=1,
        )
    )
    print(f"wrote {prompts_path} ({len(prompts.texts)} prompts, version {prompts.version})")

    # Parity: LiteRT vs PyTorch on random inputs.
    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    inp, out = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    print(f"LiteRT input {inp['shape'].tolist()} {inp['dtype'].__name__}, output {out['shape'].tolist()}")
    worst = 1.0
    for seed in range(5):
        x = np.random.default_rng(seed).random((1, IMAGE_SIZE, IMAGE_SIZE, 3), dtype=np.float32)
        interpreter.set_tensor(inp["index"], x)
        interpreter.invoke()
        lite = interpreter.get_tensor(out["index"])[0]
        with torch.no_grad():
            ref = encoder(torch.from_numpy(x))[0].numpy()
        worst = min(worst, float(lite @ ref / (np.linalg.norm(lite) * np.linalg.norm(ref))))
    print(f"parity: worst cosine similarity LiteRT vs PyTorch = {worst:.5f}")
    if worst < (0.99 if args.no_int8 else 0.98):
        raise SystemExit("parity check failed")


if __name__ == "__main__":
    main()
