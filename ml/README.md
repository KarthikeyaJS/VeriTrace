# VeriTrace ML anomaly service (optional)

FastAPI + scikit-learn **IsolationForest** that scores a product's journey at verification time.
**Trained on synthetic data only.** It can raise a verification to *Flagged*, never to *Suspect*. The backend calls it with a 1.5 s timeout and carries on without it if it's down or slow.

## Setup (Windows)
```powershell
cd ml
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python generate_data.py     # data/normal.csv, data/anomalies.csv (synthetic)
.\.venv\Scripts\python train.py             # model/isolation_forest.joblib + model/model_meta.json
.\.venv\Scripts\python -m pytest -q         # 7 tests
.\.venv\Scripts\python -m uvicorn app:app --host 127.0.0.1 --port 8000
```
A trained model is committed in `model/`, so the train step is optional. The backend reads `ML_URL` (default `http://127.0.0.1:8000`); set `ML_URL=` (empty) to disable it.

## API
- `GET /health` → `{ ok, modelVersion, metrics }`
- `POST /score`
  ```json
  { "numHandoffs": 3, "minGapSeconds": 86400, "meanGapSeconds": 172800, "secondsSinceRegistration": 2592000,
    "scanCount": 2, "distinctDevices": 1, "scansLastHour": 1, "stage": "Sold" }
  ```
  → `{ "anomalyScore": 0.52, "isAnomaly": false, "threshold": 0.56, "modelVersion": "iforest-…" }`

## Features
`numHandoffs` (custody receipts), min/mean gap between custody changes, time since registration, scan count, distinct devices, scans in the last hour, stage at scan. Durations and counts are `log1p`-scaled, and stage is ordinal. Defined once in `features.py`.

## Synthetic data
- **Normal (20 000)**: realistic journeys (2–5 hops, gaps from 1 s to 60 days, 1–3 scans), plus 25% "compressed-time" journeys (the whole chain within minutes, up to 8 scans in the hour). Local demo chains and automated handoffs look like this, and fast handoffs are already covered by the deterministic `MIN_HANDOFF_GAP_SECONDS` rule.
- **Anomalies (5 × 400, held out for evaluation)**: `clone` (15–100 scans across many devices), `burst` (scripted scans from 1–2 devices), `laundering` (10–25 hops), `ghost` (public scans of an unreleased product), `zombie` (years-old sold item suddenly scanned a lot).
- Training mixes in ~2% anomalies from a different seed (realistic for unsupervised logs; without them IsolationForest can't isolate values beyond the normal range). The threshold is the 99th percentile of normal training scores.

## Current metrics (synthetic, see `model/model_meta.json`)
Hold-out false-positive rate ≈ 1.0% · recall: clone 100%, burst 98%, ghost 99%, zombie 100%, laundering 63% · overall 92%.
These are synthetic numbers; real-world performance is unknown (see `docs/LIMITATIONS.md`).
