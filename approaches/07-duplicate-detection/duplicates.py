"""Approach 07: has this photo (or a re-shot / edited copy of it) been submitted before?

Two fingerprints per photo, compared against every earlier submission:
  * pHash (64-bit perceptual hash, `imagehash`, BSD-2): near-identical copies survive
    re-compression, resizing and small brightness changes. Distance = differing bits.
  * DINOv2-small embedding (facebook/dinov2-small, Apache-2.0): catches the same scene
    re-shot, cropped, rotated or framed by a screenshot. Similarity = cosine.

Only the fingerprints are stored (server/data/duplicate_index.npz), never the photos.
A photo that passes is added to the index; a duplicate is not added again.
Same-face (identity) matching is on hold: see README.
"""

from __future__ import annotations

import json
import sys
import threading
import time
import uuid
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from humandetect_server.contract import Result, Tunable, param  # noqa: E402

MODEL_ID = "facebook/dinov2-small"
MODEL_REVISION = "ed25f3a31f01632728cabb09d1542f84ab7b0056"
INDEX_PATH = ROOT / "server" / "data" / "duplicate_index.npz"

MAX_HASH_DISTANCE = Tunable("max_hash_distance", "pHash: max differing bits for a copy", 0, 20, 10, 0)
MIN_SIMILARITY = Tunable("min_similarity", "DINOv2: min similarity for a re-shot copy", 0.70, 0.99, 0.85, 2)


class DuplicateCheck:
    id = "07"
    title = "Duplicate detection"
    score_label = "1 − similarity to the closest earlier photo"
    tunables = [MAX_HASH_DISTANCE, MIN_SIMILARITY]

    def __init__(self, index_path: Path = INDEX_PATH, embedder=None):
        self.index_path = index_path
        self._embedder = embedder  # injectable for tests
        self._lock = threading.Lock()
        self.ids: list[str] = []
        self.times: list[float] = []
        self.hashes = np.zeros((0, 64), dtype=bool)
        self.embeddings = np.zeros((0, 384), dtype=np.float32)

    # --- models and index ----------------------------------------------------------

    def load(self) -> None:
        if self._embedder is None:
            self._embedder = DinoEmbedder()
        if self.index_path.exists():
            data = np.load(self.index_path, allow_pickle=False)
            meta = json.loads(str(data["meta"]))
            self.ids, self.times = meta["ids"], meta["times"]
            self.hashes, self.embeddings = data["hashes"], data["embeddings"]

    def _save(self) -> None:
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.index_path.with_suffix(".tmp.npz")
        np.savez(tmp, hashes=self.hashes, embeddings=self.embeddings,
                 meta=json.dumps({"ids": self.ids, "times": self.times}))
        tmp.replace(self.index_path)

    def reset(self) -> int:
        with self._lock:
            removed = len(self.ids)
            self.ids, self.times = [], []
            self.hashes = self.hashes[:0]
            self.embeddings = self.embeddings[:0]
            self._save()
            return removed

    # --- the check -------------------------------------------------------------------

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        import imagehash

        bits = imagehash.phash(image).hash.reshape(-1)
        embedding = self._embedder(image)
        max_dist, min_sim = param(params, MAX_HASH_DISTANCE), param(params, MIN_SIMILARITY)

        with self._lock:
            n = len(self.ids)
            details = [("Earlier photos in the index", str(n))]
            reasons: list[str] = []
            similarity = 0.0
            if n:
                distances = (self.hashes != bits).sum(axis=1)
                sims = self.embeddings @ embedding
                h, e = int(distances.argmin()), int(sims.argmax())
                similarity = float(sims[e])
                details += [
                    ("Closest by pHash", f"{int(distances[h])} bits differ  (copy if ≤ {max_dist:.0f})"),
                    ("Closest by DINOv2", f"similarity {similarity:.3f}  (re-shot if ≥ {min_sim:.2f})"),
                ]
                if distances[h] <= max_dist:
                    reasons.append("DUPLICATE")
                    details.append(("Matches", _describe(self.ids[h], self.times[h])))
                elif similarity >= min_sim:
                    reasons.append("RESUBMITTED")
                    details.append(("Matches", _describe(self.ids[e], self.times[e])))
            if not reasons:
                self.ids.append(uuid.uuid4().hex[:8])
                self.times.append(time.time())
                self.hashes = np.vstack([self.hashes, bits[None]])
                self.embeddings = np.vstack([self.embeddings, embedding[None]])
                self._save()
                details.append(("Added to index as", self.ids[-1]))
        details.append(("Models", "pHash 64-bit + DINOv2-small"))
        return Result(passed=not reasons, score=1.0 - max(similarity, 0.0), reasons=reasons, details=details)


def _describe(match_id: str, when: float) -> str:
    minutes = (time.time() - when) / 60
    age = f"{minutes:.0f} min ago" if minutes < 120 else f"{minutes / 60:.1f} h ago"
    return f"photo {match_id}, submitted {age}"


class DinoEmbedder:
    """Image -> L2-normalized DINOv2-small CLS embedding (384 numbers)."""

    def __init__(self):
        import torch
        from transformers import AutoImageProcessor, AutoModel

        from humandetect_server.device import torch_device

        self.torch = torch
        self.device = torch_device()
        self.processor = AutoImageProcessor.from_pretrained(MODEL_ID, revision=MODEL_REVISION)
        self.model = AutoModel.from_pretrained(MODEL_ID, revision=MODEL_REVISION, use_safetensors=True)
        self.model.eval().to(self.device)

    def __call__(self, image: Image.Image) -> np.ndarray:
        with self.torch.no_grad():
            inputs = self.processor(images=image, return_tensors="pt").to(self.device)
            cls = self.model(**inputs).last_hidden_state[0, 0]
            v = (cls / cls.norm()).float().cpu().numpy()
        return v.astype(np.float32)
