"""Trains the IsolationForest on SYNTHETIC normal journeys and evaluates on injected anomalies.

Usage: python train.py   (generates data if missing) -> model/isolation_forest.joblib + model/model_meta.json
"""
from __future__ import annotations

import csv
import json
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import IsolationForest

from features import FEATURE_NAMES, to_vector
from generate_data import ANOMALY_KINDS, generate, write_csv

HERE = Path(__file__).parent
DATA = HERE / "data"
MODEL_DIR = HERE / "model"
FALSE_POSITIVE_TARGET = 0.01  # flag ~1% of normal journeys
TRAIN_ANOMALIES_PER_KIND = 65  # 5 kinds x 65 = ~2% of the training set


def load_rows(path: Path):
    with path.open() as fh:
        return list(csv.DictReader(fh))


def main():
    if not (DATA / "normal.csv").exists():
        normals, anomalies = generate()
        write_csv(normals, DATA / "normal.csv")
        write_csv(anomalies, DATA / "anomalies.csv")
    normals = load_rows(DATA / "normal.csv")
    anomalies = load_rows(DATA / "anomalies.csv")

    rng = np.random.default_rng(7)
    idx = rng.permutation(len(normals))
    split = int(len(idx) * 0.8)
    train_rows = [normals[i] for i in idx[:split]]
    holdout_rows = [normals[i] for i in idx[split:]]

    # Unsupervised setting: real logs contain a few anomalies, so ~2% injected anomalies (different seed
    # from the evaluation set) are mixed into training. Without them, IsolationForest cannot isolate values
    # outside the normal range (e.g. 15 hops looks like the 5-hop edge of normal).
    _, contamination_rows = generate(n_normal=0, n_per_anomaly=TRAIN_ANOMALIES_PER_KIND, seed=1234)
    x_normal = np.array([to_vector(r) for r in train_rows])
    x_train = np.vstack([x_normal, np.array([to_vector(r) for r in contamination_rows])])
    model = IsolationForest(n_estimators=300, max_samples=2048, contamination="auto", random_state=42)
    model.fit(x_train)

    # anomalyScore = -score_samples (higher = more anomalous); threshold = 99th percentile of NORMAL training scores
    normal_scores = -model.score_samples(x_normal)
    threshold = float(np.quantile(normal_scores, 1 - FALSE_POSITIVE_TARGET))

    def flagged(rows):
        scores = -model.score_samples(np.array([to_vector(r) for r in rows]))
        return float(np.mean(scores > threshold))

    metrics = {"holdoutFalsePositiveRate": round(flagged(holdout_rows), 4), "recallByKind": {}}
    for kind in ANOMALY_KINDS:
        metrics["recallByKind"][kind] = round(flagged([r for r in anomalies if r["label"] == kind]), 4)
    metrics["overallRecall"] = round(flagged(anomalies), 4)

    MODEL_DIR.mkdir(exist_ok=True)
    joblib.dump(model, MODEL_DIR / "isolation_forest.joblib")
    meta = {
        "modelVersion": f"iforest-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}",
        "features": FEATURE_NAMES,
        "threshold": threshold,
        "trainedOn": f"{len(train_rows)} synthetic normal + {len(contamination_rows)} injected anomalous journeys (seeded RNG)",
        "metrics": metrics,
        "note": "Synthetic data only — not validated on real supply-chain data.",
    }
    (MODEL_DIR / "model_meta.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
