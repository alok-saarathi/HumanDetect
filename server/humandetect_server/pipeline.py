"""Approach 15 on the server: cheap proof first, judgment last.

Order is fixed: 08 (person present) → 07 (already submitted?) → 06 (face, not a
screen; a note, not a hard reject) → 09 (final judge). A hard failure stops the
rest. 10–14 stay out until there is a labeled dataset.

A photo is added to the duplicate index only when the pipeline accepts it.
"""

from __future__ import annotations

import time

from PIL import Image

from . import registry
from .contract import Result

# id, role. "advisory" never rejects on its own.
ORDER: tuple[tuple[str, str], ...] = (
    ("08", "hard"),
    ("07", "hard"),
    ("06", "advisory"),
    ("09", "final"),
)


def parse_skip(raw: str | None) -> set[str]:
    """Comma-separated approach ids to leave out. Unknown ids are an error."""
    if raw is None or not raw.strip():
        return set()
    known = {approach_id for approach_id, _ in ORDER}
    skip = {part.strip() for part in raw.split(",") if part.strip()}
    unknown = skip - known
    if unknown:
        raise ValueError(f"unknown stage: {', '.join(sorted(unknown))}")
    return skip


def run_pipeline(
    image: Image.Image,
    skip: set[str],
    params: dict[str, float] | None = None,
) -> dict:
    """Run the enabled server stages. Does not load a stage that is skipped or
    that sits after a hard failure."""
    params = dict(params or {})
    stages: list[dict] = []
    reasons: list[str] = []
    advisory: list[str] = []
    stopped_at: str | None = None
    blocked = False
    score = 1.0
    total_ms = 0.0
    seven_passed = False

    for approach_id, role in ORDER:
        if approach_id in skip:
            stages.append(_stage(approach_id, role, "skipped"))
            continue
        if blocked:
            stages.append(_stage(approach_id, role, "not_reached"))
            continue

        approach = registry.get(approach_id)
        call = dict(params)
        if approach_id == "07":
            call["record"] = 0.0  # store only if the pipeline accepts
        start = time.perf_counter()
        result: Result = approach.check(image, call)
        elapsed = (time.perf_counter() - start) * 1000
        total_ms += elapsed

        if role == "advisory":
            state = "passed" if result.passed else "noted"
            if not result.passed:
                advisory.extend(result.reasons)
        else:
            state = "passed" if result.passed else "failed"
            score = float(result.score)
            if result.passed and approach_id == "07":
                seven_passed = True
            if not result.passed:
                blocked = True
                stopped_at = approach_id
                reasons.extend(result.reasons)

        stages.append(
            _stage(
                approach_id,
                role,
                state,
                score=float(result.score),
                reasons=list(result.reasons),
                details=result.details,
                marks=[m.json() for m in result.marks],
                latency_ms=elapsed,
                title=approach.title,
            )
        )

    passed = stopped_at is None
    if passed and seven_passed:
        registry.get("07").check(image, {**params, "record": 1.0})

    return {
        "passed": passed,
        "score": round(score, 4),
        "reasons": reasons,
        "advisory": advisory,
        "stopped_at": stopped_at,
        "latency_ms": round(total_ms, 1),
        "stages": stages,
    }


def _stage(
    approach_id: str,
    role: str,
    state: str,
    *,
    score: float | None = None,
    reasons: list[str] | None = None,
    details: list[tuple[str, str]] | None = None,
    marks: list[dict] | None = None,
    latency_ms: float | None = None,
    title: str | None = None,
) -> dict:
    return {
        "id": approach_id,
        "title": title or approach_id,
        "role": role,
        "state": state,
        "score": None if score is None else round(score, 4),
        "reasons": reasons or [],
        "details": [[label, value] for label, value in (details or [])],
        "marks": marks or [],
        "latency_ms": None if latency_ms is None else round(latency_ms, 1),
    }
