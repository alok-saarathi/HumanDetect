"""HTTP service for the Tier 2 approaches (deployment option D3 in plan.md).

Run (from the repo root):
    uv run --group models --group server uvicorn humandetect_server.app:app --app-dir server --host 0.0.0.0 --port 8765

Endpoints
    GET  /v1/health                      liveness of the service
    GET  /v1/approaches                  ids, titles, score meaning, tunables
    POST /v1/check/{id}?<tunable>=<v>    body = the image file bytes (JPEG, PNG, WebP, ...)
    POST /v1/pipeline?skip=06,09         body = the image. Stages 08 → 07 → 06 → 09.
    POST /v1/approaches/07/reset         empty the duplicate index (lab use)

Images are judged in memory and never written to disk. Set HUMANDETECT_TOKEN to require
the same value in an `X-HumanDetect-Token` header.
"""

from __future__ import annotations

import io
import os
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from PIL import Image, ImageOps, UnidentifiedImageError

from . import pipeline, registry

MAX_BYTES = 25 * 1024 * 1024

app = FastAPI(title="HumanDetect Tier 2", version="0.2.0")


def _authorize(request: Request) -> None:
    token = os.environ.get("HUMANDETECT_TOKEN")
    if token and request.headers.get("x-humandetect-token") != token:
        raise HTTPException(401, "missing or wrong X-HumanDetect-Token")


def decode_image(data: bytes) -> Image.Image:
    """Bytes -> upright RGB (EXIF rotation applied)."""
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except (UnidentifiedImageError, OSError) as e:
        raise HTTPException(415, f"not a decodable image: {e}") from e
    return ImageOps.exif_transpose(image).convert("RGB")


@app.get("/v1/health")
def health() -> dict:
    return {
        "ok": True,
        "approaches": list(registry.APPROACHES),
        "pipeline": [approach_id for approach_id, _ in pipeline.ORDER],
    }


@app.get("/v1/approaches")
def approaches() -> list[dict]:
    return [registry.describe(i) for i in registry.APPROACHES]


@app.post("/v1/check/{approach_id}")
async def check(approach_id: str, request: Request) -> dict:
    _authorize(request)
    if approach_id not in registry.APPROACHES:
        raise HTTPException(404, f"unknown approach {approach_id}")
    data = await request.body()
    if not data:
        raise HTTPException(400, "empty body: send the image bytes")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "image too large")
    params: dict[str, float] = {}
    for key, value in request.query_params.items():
        try:
            params[key] = float(value)
        except ValueError:
            raise HTTPException(400, f"parameter {key} must be a number") from None
    image = decode_image(data)

    def run() -> dict:
        approach = registry.get(approach_id)  # loads models on first use
        start = time.perf_counter()
        result = approach.check(image, params)
        return result.json((time.perf_counter() - start) * 1000)

    return await run_in_threadpool(run)


@app.post("/v1/pipeline")
async def run_server_pipeline(request: Request) -> dict:
    """08 → 07 → 06 → 09. `skip` is a comma-separated list of those ids."""
    _authorize(request)
    data = await request.body()
    if not data:
        raise HTTPException(400, "empty body: send the image bytes")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "image too large")
    try:
        skip = pipeline.parse_skip(request.query_params.get("skip"))
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    params: dict[str, float] = {}
    for key, value in request.query_params.items():
        if key == "skip":
            continue
        try:
            params[key] = float(value)
        except ValueError:
            raise HTTPException(400, f"parameter {key} must be a number") from None
    image = decode_image(data)

    def run() -> dict:
        return pipeline.run_pipeline(image, skip, params)

    return await run_in_threadpool(run)


@app.post("/v1/approaches/07/reset")
def reset_duplicates(request: Request) -> dict:
    _authorize(request)
    removed = registry.get("07").reset()
    return {"removed": removed}
