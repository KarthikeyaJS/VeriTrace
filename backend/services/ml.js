// Client for the optional Python anomaly service (ml/). Never blocks verification:
// any error, non-200, or timeout (ML_TIMEOUT_MS, default 1.5 s) returns null.
const config = require("../config");

async function score(features) {
  if (!config.ml.url) return null;
  try {
    const res = await fetch(`${config.ml.url.replace(/\/$/, "")}/score`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(features),
      signal: AbortSignal.timeout(config.ml.timeoutMs),
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (typeof data.anomalyScore !== "number" || typeof data.isAnomaly !== "boolean") return null;
    return { anomalyScore: data.anomalyScore, isAnomaly: data.isAnomaly, modelVersion: data.modelVersion || null };
  } catch {
    return null;
  }
}

async function health() {
  if (!config.ml.url) return { configured: false, ok: false };
  try {
    const res = await fetch(`${config.ml.url.replace(/\/$/, "")}/health`, { signal: AbortSignal.timeout(config.ml.timeoutMs) });
    return { configured: true, ok: res.ok, url: config.ml.url };
  } catch {
    return { configured: true, ok: false, url: config.ml.url };
  }
}

module.exports = { score, health };
