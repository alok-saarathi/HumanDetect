"""Approach 09: ask a self-hosted open vision-language model what the photo shows.

Model: SmolVLM2-500M-Video-Instruct (HuggingFaceTB, Apache-2.0), run on our own machine,
so photos never leave it. A multiple-choice question with a one-letter answer keeps the
output parseable; the score is the model's probability of the "live person" option.

Accuracy ceiling and labeler for the training approaches, not a production check.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from humandetect_server.contract import Result, Tunable, param  # noqa: E402

MODEL_ID = "HuggingFaceTB/SmolVLM2-500M-Video-Instruct"
MODEL_REVISION = "7b375e1b73b11138ff12fe22c8f2822d8fe03467"

OPTIONS = {
    "A": ("a real person, photographed directly", None),
    "B": ("a person shown on a screen (phone, TV, monitor, laptop)", "RECAPTURE"),
    "C": ("a printed photo, poster or ID card of a person", "RECAPTURE"),
    "D": ("a painting, drawing, statue, mannequin or cartoon", "NOT_REAL"),
    "E": ("no person at all (a place, object or document)", "NO_HUMAN"),
}
QUESTION = ("What does this photo show? Answer with one letter.\n"
            + "\n".join(f"{k}. {v[0]}" for k, v in OPTIONS.items()))

MIN_LIVE = Tunable("min_live", "Min probability of 'real person'", 0.2, 0.95, 0.5, 2)


class VlmJudge:
    id = "09"
    title = "Open VLM judge"
    score_label = "probability of 'real person'"
    tunables = [MIN_LIVE]

    def load(self) -> None:
        import torch
        from transformers import AutoModelForImageTextToText, AutoProcessor

        from humandetect_server.device import torch_device

        self.torch = torch
        self.device = torch_device()
        self.processor = AutoProcessor.from_pretrained(MODEL_ID, revision=MODEL_REVISION)
        self.model = AutoModelForImageTextToText.from_pretrained(
            MODEL_ID, revision=MODEL_REVISION, use_safetensors=True, torch_dtype=torch.bfloat16
        ).eval().to(self.device)
        tok = self.processor.tokenizer
        self.letter_ids = {k: tok.encode(k, add_special_tokens=False)[0] for k in OPTIONS}

    def probabilities(self, image: Image.Image) -> dict[str, float]:
        messages = [{"role": "user", "content": [{"type": "image"}, {"type": "text", "text": QUESTION}]}]
        prompt = self.processor.apply_chat_template(messages, add_generation_prompt=True)
        inputs = self.processor(text=prompt, images=[image], return_tensors="pt").to(self.device)
        with self.torch.no_grad():
            logits = self.model(**inputs).logits[0, -1].float()
        picked = self.torch.stack([logits[i] for i in self.letter_ids.values()]).softmax(0).tolist()
        return dict(zip(OPTIONS, picked))

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        probs = self.probabilities(image)
        live = probs["A"]
        best = max(probs, key=probs.get)
        passed = live >= param(params, MIN_LIVE)
        reasons = [] if passed else [OPTIONS[best][1] or OPTIONS[max((k for k in probs if k != "A"), key=probs.get)][1]]
        ranked = sorted(probs.items(), key=lambda kv: -kv[1])
        details = [(f"{k}. {OPTIONS[k][0]}", f"{p * 100:.0f} %") for k, p in ranked]
        details.append(("Model", "SmolVLM2-500M (local)"))
        return Result(passed, live, reasons, details)
