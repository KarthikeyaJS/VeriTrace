"""Synthetic journey generator: normal journeys + injected anomalies. All data is SYNTHETIC.

Normal journeys deliberately include very short handoff gaps (down to 1 s), and 25% of them run in a
"compressed-time" mode (whole journey within minutes, several scans in the last hour). Local demo/test
chains and automated warehouse handoffs look like this, and fast handoffs are already handled by the
deterministic MIN_HANDOFF_GAP rule. The model therefore focuses on scan patterns, hop counts, stage and age.

Usage: python generate_data.py  -> data/normal.csv, data/anomalies.csv
"""
from __future__ import annotations

import csv
import math
from pathlib import Path

import numpy as np

DAY = 86400.0
FIELDS = ["numHandoffs", "minGapSeconds", "meanGapSeconds", "secondsSinceRegistration",
          "scanCount", "distinctDevices", "scansLastHour", "stage", "label"]


def _log_uniform(rng: np.random.Generator, low: float, high: float, size=None):
    return np.exp(rng.uniform(math.log(low), math.log(high), size))


def _journey(rng, stage: str, hops: int, gap_low=1.0, gap_high=60 * DAY, idle_high=180 * DAY):
    custody_gaps = hops + (1 if stage == "Sold" else 0)
    gaps = _log_uniform(rng, gap_low, gap_high, custody_gaps) if custody_gaps else np.array([])
    since = float(gaps.sum()) + float(_log_uniform(rng, 5, idle_high))
    return {
        "numHandoffs": hops,
        "minGapSeconds": float(gaps.min()) if gaps.size else 0.0,
        "meanGapSeconds": float(gaps.mean()) if gaps.size else 0.0,
        "secondsSinceRegistration": since,
        "stage": stage,
    }


def _normal_scans(rng):
    scans = 1 + min(int(rng.poisson(0.8)), 9)
    devices = 1 + int(rng.binomial(scans - 1, 0.3))
    last_hour = 1 + int(rng.binomial(scans - 1, 0.3))
    return {"scanCount": scans, "distinctDevices": devices, "scansLastHour": last_hour}


def _compressed_scans(rng):
    scans = int(rng.integers(1, 9))  # repeated test/demo scans, below the deterministic threshold (10)
    devices = 1 + int(rng.binomial(scans - 1, 0.25))
    return {"scanCount": scans, "distinctDevices": min(devices, 4), "scansLastHour": scans}


def normal(rng) -> dict:
    stage = rng.choice(["Sold", "AtRetailer", "AtSupplier", "Manufactured"], p=[0.45, 0.35, 0.12, 0.08])
    hops = {"Manufactured": 0, "AtSupplier": int(rng.integers(1, 4))}.get(stage, int(rng.choice([2, 2, 3, 3, 4, 5])))
    if rng.random() < 0.25:  # compressed-time journey
        return {**_journey(rng, stage, hops, gap_high=180.0, idle_high=3600.0), **_compressed_scans(rng), "label": "normal"}
    return {**_journey(rng, stage, hops), **_normal_scans(rng), "label": "normal"}


def anomaly(rng, kind: str) -> dict:
    if kind == "clone":  # same QR printed many times, scanned everywhere
        stage = rng.choice(["Sold", "AtRetailer"])
        scans = int(rng.integers(15, 100))
        base = _journey(rng, stage, int(rng.integers(2, 5)))
        return {**base, "scanCount": scans, "distinctDevices": int(rng.integers(8, min(scans, 60) + 1)),
                "scansLastHour": int(rng.integers(3, 40)), "label": kind}
    if kind == "burst":  # scripted scanning from one or two devices
        stage = rng.choice(["Sold", "AtRetailer"])
        scans = int(rng.integers(12, 60))
        base = _journey(rng, stage, int(rng.integers(2, 5)))
        return {**base, "scanCount": scans, "distinctDevices": int(rng.integers(1, 3)),
                "scansLastHour": int(rng.integers(10, scans + 1)), "label": kind}
    if kind == "laundering":  # goods bounced between many parties
        stage = rng.choice(["Sold", "AtRetailer", "AtSupplier"])
        return {**_journey(rng, stage, int(rng.integers(10, 25))), **_normal_scans(rng), "label": kind}
    if kind == "ghost":  # public scans of a product that never left the factory
        scans = int(rng.integers(6, 40))
        return {**_journey(rng, "Manufactured", 0), "scanCount": scans,
                "distinctDevices": int(rng.integers(4, min(scans, 25) + 1)),
                "scansLastHour": int(rng.integers(1, 10)), "label": kind}
    if kind == "zombie":  # very old sold item suddenly scanned a lot
        base = _journey(rng, "Sold", int(rng.integers(2, 5)))
        base["secondsSinceRegistration"] = float(rng.uniform(4, 12) * 365 * DAY)
        scans = int(rng.integers(8, 40))
        return {**base, "scanCount": scans, "distinctDevices": int(rng.integers(4, min(scans, 20) + 1)),
                "scansLastHour": int(rng.integers(2, 15)), "label": kind}
    raise ValueError(kind)


ANOMALY_KINDS = ["clone", "burst", "laundering", "ghost", "zombie"]


def generate(n_normal=20000, n_per_anomaly=400, seed=42):
    rng = np.random.default_rng(seed)
    normals = [normal(rng) for _ in range(n_normal)]
    anomalies = [anomaly(rng, k) for k in ANOMALY_KINDS for _ in range(n_per_anomaly)]
    return normals, anomalies


def write_csv(rows, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    out = Path(__file__).parent / "data"
    normals, anomalies = generate()
    write_csv(normals, out / "normal.csv")
    write_csv(anomalies, out / "anomalies.csv")
    print(f"wrote {len(normals)} normal and {len(anomalies)} anomalous synthetic journeys to {out}")
