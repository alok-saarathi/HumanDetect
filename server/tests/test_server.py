"""Server tests that need no model downloads: fake embedder and fake approach."""

import io
import sys
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))

from humandetect_server import app as app_module  # noqa: E402
from humandetect_server import registry  # noqa: E402
from humandetect_server.contract import Result, Tunable  # noqa: E402


def jpeg(color=(120, 80, 40), size=(64, 48), noise_seed=None) -> bytes:
    pixels = np.full((size[1], size[0], 3), color, dtype=np.uint8)
    if noise_seed is not None:
        pixels = np.random.default_rng(noise_seed).integers(0, 255, pixels.shape, dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(pixels).save(buf, "JPEG")
    return buf.getvalue()


class FakeApproach:
    id, title, score_label = "07", "Fake", "fake score"
    tunables = [Tunable("limit", "A limit", 0, 10, 5, 0)]

    def load(self):
        pass

    def check(self, image, params):
        return Result(image.size == (64, 48) and params.get("limit", 5) >= 5, 0.75, [], [("size", str(image.size))])

    def reset(self):
        return 3


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setitem(registry._instances, "07", FakeApproach())
    monkeypatch.delenv("HUMANDETECT_TOKEN", raising=False)
    return TestClient(app_module.app)


def test_health_lists_approaches(client):
    body = client.get("/v1/health").json()
    assert body["ok"] and set(body["approaches"]) == {"06", "07", "08", "09"}
    assert body["pipeline"] == ["08", "07", "06", "09"]


def test_check_returns_result_json(client):
    r = client.post("/v1/check/07?limit=7", content=jpeg())
    assert r.status_code == 200
    body = r.json()
    assert body["passed"] is True and body["score"] == 0.75
    assert body["details"] == [["size", "(64, 48)"]] and body["latency_ms"] >= 0


def test_params_reach_the_approach(client):
    assert client.post("/v1/check/07?limit=2", content=jpeg()).json()["passed"] is False


def test_bad_requests(client):
    assert client.post("/v1/check/99", content=jpeg()).status_code == 404
    assert client.post("/v1/check/07", content=b"").status_code == 400
    assert client.post("/v1/check/07", content=b"not an image").status_code == 415
    assert client.post("/v1/check/07?limit=abc", content=jpeg()).status_code == 400


def test_exif_rotation_is_applied():
    img = Image.new("RGB", (40, 20), "red")
    exif = Image.Exif()
    exif[0x0112] = 6  # rotate 90 clockwise to display
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    assert app_module.decode_image(buf.getvalue()).size == (20, 40)


def test_token_is_enforced_when_set(client, monkeypatch):
    monkeypatch.setenv("HUMANDETECT_TOKEN", "secret")
    assert client.post("/v1/check/07", content=jpeg()).status_code == 401
    ok = client.post("/v1/check/07", content=jpeg(), headers={"X-HumanDetect-Token": "secret"})
    assert ok.status_code == 200
    assert client.post("/v1/approaches/07/reset").status_code == 401


def test_reset(client):
    assert client.post("/v1/approaches/07/reset").json() == {"removed": 3}


# --- approach 07 with a fake embedder ---------------------------------------------------

def make_duplicates(tmp_path):
    sys.path.insert(0, str(ROOT / "approaches" / "07-duplicate-detection"))
    from duplicates import DuplicateCheck

    def embedder(image):
        v = np.array(image.resize((8, 8)).convert("L"), dtype=np.float32).reshape(-1)[:384 // 6].repeat(6)
        v = v - v.mean()
        return (v / (np.linalg.norm(v) + 1e-9)).astype(np.float32)

    check = DuplicateCheck(index_path=tmp_path / "idx.npz", embedder=embedder)
    check.load()
    return check


def textured(seed):
    return Image.fromarray(np.random.default_rng(seed).integers(0, 255, (96, 96, 3), dtype=np.uint8))


def test_record_zero_does_not_store(tmp_path):
    check = make_duplicates(tmp_path)
    photo = textured(3)
    assert check.check(photo, {"record": 0}).passed
    assert check.check(photo, {"record": 0}).passed  # not stored, so not a duplicate yet
    assert check.check(photo, {"record": 1}).passed
    again = check.check(photo, {})
    assert not again.passed and again.reasons == ["DUPLICATE"]


class _Scripted:
    def __init__(self, approach_id, passed, reasons=None):
        self.id = approach_id
        self.title = approach_id
        self.score_label = "scripted"
        self.tunables = []
        self.passed = passed
        self.reasons = list(reasons or ([] if passed else ["NO"]))
        self.calls = []

    def load(self):
        pass

    def check(self, image, params):
        self.calls.append(dict(params))
        return Result(self.passed, 0.4, list(self.reasons), [("id", self.id)])


def test_pipeline_stops_at_the_first_hard_failure(client, monkeypatch):
    scripts = {
        "08": _Scripted("08", False, ["NO_PERSON"]),
        "07": _Scripted("07", True),
        "06": _Scripted("06", True),
        "09": _Scripted("09", True),
    }
    monkeypatch.setattr(registry, "get", lambda approach_id: scripts[approach_id])
    body = client.post("/v1/pipeline", content=jpeg()).json()
    assert body["passed"] is False
    assert body["stopped_at"] == "08"
    assert body["reasons"] == ["NO_PERSON"]
    assert scripts["08"].calls and scripts["07"].calls == []
    assert scripts["09"].calls == []
    states = {stage["id"]: stage["state"] for stage in body["stages"]}
    assert states == {"08": "failed", "07": "not_reached", "06": "not_reached", "09": "not_reached"}


def test_pipeline_keeps_06_as_a_note_and_09_decides(client, monkeypatch):
    scripts = {
        "08": _Scripted("08", True),
        "07": _Scripted("07", True),
        "06": _Scripted("06", False, ["RECAPTURE"]),
        "09": _Scripted("09", True),
    }
    monkeypatch.setattr(registry, "get", lambda approach_id: scripts[approach_id])
    body = client.post("/v1/pipeline?skip=07", content=jpeg()).json()
    assert body["passed"] is True
    assert body["advisory"] == ["RECAPTURE"]
    assert body["reasons"] == []
    assert scripts["07"].calls == []
    assert scripts["06"].calls and scripts["09"].calls
    # 07 was skipped, so nothing is recorded.
    assert all(call.get("record") != 1 for call in scripts["07"].calls)


def test_pipeline_records_a_photo_only_after_it_passes(client, monkeypatch):
    scripts = {
        "08": _Scripted("08", True),
        "07": _Scripted("07", True),
        "06": _Scripted("06", True),
        "09": _Scripted("09", False, ["NOT_REAL"]),
    }
    monkeypatch.setattr(registry, "get", lambda approach_id: scripts[approach_id])
    body = client.post("/v1/pipeline", content=jpeg()).json()
    assert body["passed"] is False and body["stopped_at"] == "09"
    # Lookup only: the failing final judge must not store the photo.
    assert scripts["07"].calls == [{"record": 0.0}]


def test_pipeline_stores_when_every_hard_stage_passes(client, monkeypatch):
    scripts = {
        "08": _Scripted("08", True),
        "07": _Scripted("07", True),
        "06": _Scripted("06", True),
        "09": _Scripted("09", True),
    }
    monkeypatch.setattr(registry, "get", lambda approach_id: scripts[approach_id])
    body = client.post("/v1/pipeline", content=jpeg()).json()
    assert body["passed"] is True
    assert [call.get("record") for call in scripts["07"].calls] == [0.0, 1.0]


def test_pipeline_rejects_an_unknown_skip(client):
    assert client.post("/v1/pipeline?skip=01", content=jpeg()).status_code == 400


def test_duplicate_flow(tmp_path):
    check = make_duplicates(tmp_path)
    first = textured(1)
    assert check.check(first, {}).passed  # new photo: added
    again = check.check(first, {})
    assert not again.passed and again.reasons == ["DUPLICATE"]
    assert check.check(textured(2), {}).passed  # a different photo passes
    assert len(check.ids) == 2  # the duplicate was not added again


def test_duplicate_index_survives_restart_and_reset(tmp_path):
    check = make_duplicates(tmp_path)
    check.check(textured(1), {})
    reloaded = make_duplicates(tmp_path)
    assert len(reloaded.ids) == 1 and reloaded.check(textured(1), {}).reasons == ["DUPLICATE"]
    assert reloaded.reset() == 1 and make_duplicates(tmp_path).ids == []


# --- approach 08 geometry ---------------------------------------------------------------

def test_inside_share():
    sys.path.insert(0, str(ROOT / "approaches" / "08-deep-detectors"))
    from detectors import inside_share

    assert inside_share((0.2, 0.2, 0.4, 0.4), (0, 0, 1, 1)) == pytest.approx(1.0)
    assert inside_share((0.0, 0.0, 0.4, 0.4), (0.2, 0.2, 1, 1)) == pytest.approx(0.25)
    assert inside_share((0.5, 0.5, 0.6, 0.6), (0, 0, 0.2, 0.2)) == 0.0
    assert inside_share((0.3, 0.3, 0.3, 0.3), (0, 0, 1, 1)) == 0.0  # empty box
