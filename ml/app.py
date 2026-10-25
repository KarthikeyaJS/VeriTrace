"""VeriTrace anomaly service. POST /score -> { anomalyScore, isAnomaly, modelVersion }.

Run: uvicorn app:app --host 127.0.0.1 --port 8000
The backend calls this with a 1.5 s timeout and continues without it if it is down or slow.
ML can only raise a verification to Flagged, never to Suspect (enforced in the backend).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

import joblib
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from features import to_vector

MODEL_DIR = Path(__file__).parent / "model"

app = FastAPI(title="VeriTrace ML", version="1.0.0")
_model = None
_meta: dict = {}


def load_model() -> None:
    global _model, _meta
    model_file = MODEL_DIR / "isolation_forest.joblib"
    meta_file = MODEL_DIR / "model_meta.json"
    if model_file.exists() and meta_file.exists():
        _model = joblib.load(model_file)
        _meta = json.loads(meta_file.read_text())


load_model()


class JourneyFeatures(BaseModel):
    numHandoffs: int = Field(ge=0, le=1000)
    minGapSeconds: float = Field(ge=0)
    meanGapSeconds: float = Field(ge=0)
    secondsSinceRegistration: float = Field(ge=0)
    scanCount: int = Field(ge=0)
    distinctDevices: int = Field(ge=0)
    scansLastHour: int = Field(ge=0)
    stage: Literal["Manufactured", "AtSupplier", "AtRetailer", "Sold"]


class Score(BaseModel):
    anomalyScore: float
    isAnomaly: bool
    threshold: float
    modelVersion: str


@app.get("/health")
def health():
    return {"ok": _model is not None, "modelVersion": _meta.get("modelVersion"), "metrics": _meta.get("metrics")}


@app.post("/score", response_model=Score)
def score(features: JourneyFeatures) -> Score:
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not trained. Run: python train.py")
    vector = np.array([to_vector(features.model_dump())])
    anomaly_score = float(-_model.score_samples(vector)[0])
    threshold = float(_meta["threshold"])
    return Score(anomalyScore=anomaly_score, isAnomaly=anomaly_score > threshold, threshold=threshold, modelVersion=_meta["modelVersion"])
