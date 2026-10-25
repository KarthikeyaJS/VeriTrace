"""Run: python -m pytest -q   (from ml/, after python train.py)"""
from fastapi.testclient import TestClient

from app import app

client = TestClient(app)

NORMAL = {
    "numHandoffs": 3,
    "minGapSeconds": 2 * 86400,
    "meanGapSeconds": 4 * 86400,
    "secondsSinceRegistration": 30 * 86400,
    "scanCount": 1,
    "distinctDevices": 1,
    "scansLastHour": 1,
    "stage": "Sold",
}

# What a freshly seeded local demo journey looks like (handoffs seconds apart, scanned a few times).
DEMO_FAST = {**NORMAL, "minGapSeconds": 1, "meanGapSeconds": 1.0, "secondsSinceRegistration": 70, "scanCount": 4, "distinctDevices": 2, "scansLastHour": 4}

CLONE = {**NORMAL, "scanCount": 60, "distinctDevices": 35, "scansLastHour": 20}
GHOST = {**NORMAL, "numHandoffs": 0, "minGapSeconds": 0, "meanGapSeconds": 0, "stage": "Manufactured", "scanCount": 25, "distinctDevices": 15, "scansLastHour": 6}


def test_health_reports_model():
    body = client.get("/health").json()
    assert body["ok"] is True
    assert body["modelVersion"].startswith("iforest-")


def test_normal_journey_is_not_anomalous():
    body = client.post("/score", json=NORMAL).json()
    assert body["isAnomaly"] is False
    assert 0 < body["anomalyScore"] < 1


def test_demo_speed_journeys_are_not_anomalous():
    for stage, hops in (("Sold", 3), ("AtRetailer", 2), ("AtSupplier", 1)):
        body = client.post("/score", json={**DEMO_FAST, "stage": stage, "numHandoffs": hops}).json()
        assert body["isAnomaly"] is False, (stage, body)


def test_demo_speed_clone_is_still_anomalous():
    assert client.post("/score", json={**DEMO_FAST, "scanCount": 40, "distinctDevices": 20, "scansLastHour": 40}).json()["isAnomaly"] is True


def test_cloned_qr_is_anomalous():
    body = client.post("/score", json=CLONE).json()
    assert body["isAnomaly"] is True
    assert body["anomalyScore"] > client.post("/score", json=NORMAL).json()["anomalyScore"]


def test_scans_before_release_are_anomalous():
    assert client.post("/score", json=GHOST).json()["isAnomaly"] is True


def test_invalid_input_is_rejected():
    assert client.post("/score", json={**NORMAL, "stage": "Teleported"}).status_code == 422
    assert client.post("/score", json={**NORMAL, "scanCount": -1}).status_code == 422
