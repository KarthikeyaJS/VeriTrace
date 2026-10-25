"""Feature definition shared by training and serving (single source of truth).

The backend sends (see backend/services/verification.js -> mlFeatures):
  numHandoffs, minGapSeconds, meanGapSeconds, secondsSinceRegistration,
  scanCount, distinctDevices, scansLastHour, stage
"""
from __future__ import annotations

import math
from typing import Mapping

STAGES = {"Manufactured": 1, "AtSupplier": 2, "AtRetailer": 3, "Sold": 4}

FEATURE_NAMES = [
    "numHandoffs",
    "log_minGapSeconds",
    "log_meanGapSeconds",
    "log_secondsSinceRegistration",
    "log_scanCount",
    "log_distinctDevices",
    "log_scansLastHour",
    "stage",
]


def to_vector(f: Mapping[str, float | int | str]) -> list[float]:
    """Raw journey features -> model input (log1p for heavy-tailed counts and durations)."""
    return [
        float(f["numHandoffs"]),
        math.log1p(max(0.0, float(f["minGapSeconds"]))),
        math.log1p(max(0.0, float(f["meanGapSeconds"]))),
        math.log1p(max(0.0, float(f["secondsSinceRegistration"]))),
        math.log1p(max(0.0, float(f["scanCount"]))),
        math.log1p(max(0.0, float(f["distinctDevices"]))),
        math.log1p(max(0.0, float(f["scansLastHour"]))),
        float(STAGES.get(str(f["stage"]), 0)),
    ]
