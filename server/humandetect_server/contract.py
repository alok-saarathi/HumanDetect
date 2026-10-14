"""What every server-side approach (Tier 2) takes and returns.

The JSON form of `Result` matches the app's CheckResult (app/lib/core/check.dart), so the
phone shows server verdicts exactly like on-device ones.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from PIL import Image


@dataclass
class Tunable:
    """A threshold the app can adjust; sent back as a query parameter named `key`."""

    key: str
    label: str
    min: float
    max: float
    default: float
    decimals: int = 2

    def json(self) -> dict:
        return {"key": self.key, "label": self.label, "min": self.min, "max": self.max,
                "default": self.default, "decimals": self.decimals}


@dataclass
class Mark:
    """A box (and optional label) to draw on the photo, normalized 0..1: x, y, w, h."""

    box: tuple[float, float, float, float]
    label: str = ""

    def json(self) -> dict:
        return {"box": [round(v, 5) for v in self.box], "label": self.label}


@dataclass
class Result:
    passed: bool
    score: float  # 0..1, meaning given by the approach's score_label
    reasons: list[str] = field(default_factory=list)
    details: list[tuple[str, str]] = field(default_factory=list)
    marks: list[Mark] = field(default_factory=list)

    def json(self, latency_ms: float) -> dict:
        return {
            "passed": self.passed,
            "score": round(float(self.score), 4),
            "reasons": self.reasons,
            "details": [[label, value] for label, value in self.details],
            "marks": [m.json() for m in self.marks],
            "latency_ms": round(latency_ms, 1),
        }


class ServerCheck(Protocol):
    id: str
    title: str
    score_label: str
    tunables: list[Tunable]

    def load(self) -> None:
        """Load models; called once, on first use."""

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        """Judge one upright RGB image. `params` holds tunable values by key."""


def param(params: dict[str, float], tunable: Tunable) -> float:
    """The caller's value for a tunable, clamped to its range, or its default."""
    value = params.get(tunable.key, tunable.default)
    return min(max(float(value), tunable.min), tunable.max)
