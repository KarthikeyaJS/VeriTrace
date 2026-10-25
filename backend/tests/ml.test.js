// The ML service must never block verification: slow, failing or absent => null.
const http = require("http");
const config = require("../config");
const ml = require("../services/ml");

const features = { numHandoffs: 3, minGapSeconds: 1, meanGapSeconds: 1, secondsSinceRegistration: 60, scanCount: 1, distinctDevices: 1, scansLastHour: 1, stage: "Sold" };

function server(handler) {
  return new Promise((resolve) => {
    const s = http.createServer(handler).listen(0, "127.0.0.1", () => resolve(s));
  });
}

describe("ML client", () => {
  const original = { ...config.ml };
  afterEach(() => Object.assign(config.ml, original));

  test("returns the score from a healthy service", async () => {
    const s = await server((req, res) => res.end(JSON.stringify({ anomalyScore: 0.7, isAnomaly: true, threshold: 0.56, modelVersion: "t" })));
    config.ml.url = `http://127.0.0.1:${s.address().port}`;
    await expect(ml.score(features)).resolves.toEqual({ anomalyScore: 0.7, isAnomaly: true, threshold: 0.56, modelVersion: "t" });
    s.close();
  });

  test("health reports model version, threshold and metrics; offline when unreachable", async () => {
    const s = await server((req, res) => res.end(JSON.stringify({ ok: true, modelVersion: "iforest-x", threshold: 0.5, metrics: { overallRecall: 0.9 } })));
    config.ml.url = `http://127.0.0.1:${s.address().port}`;
    await expect(ml.health()).resolves.toMatchObject({ configured: true, ok: true, modelVersion: "iforest-x", threshold: 0.5, metrics: { overallRecall: 0.9 } });
    s.close();
    config.ml.url = "http://127.0.0.1:1";
    await expect(ml.health()).resolves.toMatchObject({ configured: true, ok: false });
    config.ml.url = "";
    await expect(ml.health()).resolves.toEqual({ configured: false, ok: false });
  });

  test("times out after ML_TIMEOUT_MS and returns null", async () => {
    const s = await server((req, res) => setTimeout(() => res.end("{}"), 2000));
    config.ml.url = `http://127.0.0.1:${s.address().port}`;
    config.ml.timeoutMs = 200;
    const started = Date.now();
    await expect(ml.score(features)).resolves.toBeNull();
    expect(Date.now() - started).toBeLessThan(1000);
    s.closeAllConnections();
    s.close();
  });

  test("returns null on HTTP errors, bad payloads, connection refused, or when disabled", async () => {
    const s = await server((req, res) => {
      res.statusCode = req.url === "/score" ? 503 : 200;
      res.end("{}");
    });
    config.ml.url = `http://127.0.0.1:${s.address().port}`;
    await expect(ml.score(features)).resolves.toBeNull();
    s.close();

    config.ml.url = "http://127.0.0.1:1";
    await expect(ml.score(features)).resolves.toBeNull();
    config.ml.url = "";
    await expect(ml.score(features)).resolves.toBeNull();
  });
});
