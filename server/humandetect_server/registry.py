"""Finds the Tier 2 approaches and loads each one once, on first use.

Approach code lives in its own folder under approaches/ (like the Tier 1 references);
this module only imports it. Folder names start with digits, so they're loaded by path.
"""

from __future__ import annotations

import importlib.util
import sys
import threading
from pathlib import Path

from .contract import ServerCheck

ROOT = Path(__file__).resolve().parents[2]

# approach id -> (file under approaches/, class name)
APPROACHES: dict[str, tuple[str, str]] = {
    "06": ("06-zero-shot-detection/zero_shot_detection.py", "ZeroShotDetection"),
    "07": ("07-duplicate-detection/duplicates.py", "DuplicateCheck"),
    "08": ("08-deep-detectors/detectors.py", "DeepDetector"),
    "09": ("09-open-vlm-benchmark/vlm_judge.py", "VlmJudge"),
}

_instances: dict[str, ServerCheck] = {}
_lock = threading.Lock()


def _import(relative: str):
    path = ROOT / "approaches" / relative
    name = f"humandetect_approach_{path.parent.name.replace('-', '_')}"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def get(approach_id: str) -> ServerCheck:
    """The approach's instance, created and loaded on first call (thread-safe)."""
    if approach_id not in APPROACHES:
        raise KeyError(approach_id)
    with _lock:
        if approach_id not in _instances:
            relative, cls = APPROACHES[approach_id]
            instance = getattr(_import(relative), cls)()
            instance.load()
            _instances[approach_id] = instance
        return _instances[approach_id]


def describe(approach_id: str) -> dict:
    """Metadata without loading models (title, score meaning, tunables)."""
    relative, cls = APPROACHES[approach_id]
    c = getattr(_import(relative), cls)
    return {
        "id": approach_id,
        "title": c.title,
        "score_label": c.score_label,
        "tunables": [t.json() for t in c.tunables],
        "loaded": approach_id in _instances,
    }
