// Client for the optional Python anomaly service (ml/). Never blocks verification:
// any error, non-200, or timeout (ML_TIMEOUT_MS, default 1.5 s) returns null.
const config = require("../config");

const baseUrl = () => config.ml.url.replace(/\/$/, "");

async function score(features) {
  if (!config.ml.url) return null;
  try {
    const res = await fetch(`${baseUrl()}/score`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(features),
      signal: AbortSignal.timeout(config.ml.timeoutMs),
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (typeof data.anomalyScore !== "number" || typeof data.isAnomaly !== "boolean") return null;
    return {
      anomalyScore: data.anomalyScore,
      isAnomaly: data.isAnomaly,
      threshold: typeof data.threshold === "number" ? data.threshold : null,
      modelVersion: data.modelVersion || null,
    };
  } catch {
    return null;
  }
}

/** Service status for /health and admin reports: online flag, model version, threshold and (synthetic) metrics. */
async function health() {
  if (!config.ml.url) return { configured: false, ok: false };
  try {
    const res = await fetch(`${baseUrl()}/health`, { signal: AbortSignal.timeout(config.ml.timeoutMs) });
    const body = res.ok ? await res.json().catch(() => ({})) : {};
    return {
      configured: true,
      ok: res.ok && body.ok !== false,
      url: config.ml.url,
      modelVersion: body.modelVersion || null,
      threshold: typeof body.threshold === "number" ? body.threshold : null,
      metrics: body.metrics || null,
    };
  } catch {
    return { configured: true, ok: false, url: config.ml.url };
  }
}

module.exports = { score, health };
