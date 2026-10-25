const { evaluate, verify, checkHistoryConsistency, custodyGaps, mlFeatures } = require("../services/verification");
const { computeProductHash } = require("../services/hashing");
const { parsePayload, buildPayload } = require("../services/qr");

const M = "0x1111111111111111111111111111111111111111";
const S1 = "0x2222222222222222222222222222222222222222";
const S2 = "0x3333333333333333333333333333333333333333";
const R = "0x4444444444444444444444444444444444444444";
const T0 = 1_770_000_000; // 2026-02-02 (seconds)
const HOUR = 3600;
const NOW = new Date((T0 + 30 * 24 * HOUR) * 1000);
const SETTINGS = { scanFlagThreshold: 10, deviceFlagThreshold: 5, minHandoffGapSeconds: 30 };

const metadata = {
  productId: "VT-2026-000001",
  name: "Aurora X1",
  brand: "Aurora",
  category: "Electronics",
  batchNumber: "B1",
  serialNumber: null,
  manufactureDate: "2026-01-01",
  expiryDate: null,
  countryOfOrigin: "India",
  manufacturerId: "uid-m",
  mrp: 100,
};
const HASH = computeProductHash(metadata);

const ev = (eventType, from, to, t, stageAfter) => ({ eventType, from, to, timestamp: T0 + t * HOUR, stageAfter });

const HISTORIES = {
  Manufactured: [ev("Registered", M, M, 0, "Manufactured")],
  AtSupplier: [ev("Registered", M, M, 0, "Manufactured"), ev("TransferInitiated", M, S1, 1, "Manufactured"), ev("Received", M, S1, 2, "AtSupplier")],
  AtRetailer: [
    ev("Registered", M, M, 0, "Manufactured"),
    ev("TransferInitiated", M, S1, 1, "Manufactured"),
    ev("Received", M, S1, 2, "AtSupplier"),
    ev("TransferInitiated", S1, R, 3, "AtSupplier"),
    ev("Received", S1, R, 4, "AtRetailer"),
  ],
  Sold: [
    ev("Registered", M, M, 0, "Manufactured"),
    ev("TransferInitiated", M, S1, 1, "Manufactured"),
    ev("Received", M, S1, 2, "AtSupplier"),
    ev("TransferInitiated", S1, S2, 3, "AtSupplier"),
    ev("Received", S1, S2, 4, "AtSupplier"),
    ev("TransferInitiated", S2, R, 5, "AtSupplier"),
    ev("Received", S2, R, 6, "AtRetailer"),
    ev("Sold", R, null, 7, "Sold"),
  ],
};
const HOLDERS = { Manufactured: M, AtSupplier: S1, AtRetailer: R, Sold: R };

function scenario(stage = "Sold", overrides = {}) {
  const history = HISTORIES[stage];
  return {
    parsed: parsePayload(buildPayload(metadata.productId, HASH)),
    chainProduct: {
      exists: true,
      productId: metadata.productId,
      productHash: HASH,
      manufacturer: M,
      registeredAt: T0,
      currentHolder: HOLDERS[stage],
      pendingRecipient: null,
      stage,
    },
    history,
    eventCount: history.length,
    metadata: { ...metadata },
    scanStats: { count: 1, distinctDevices: 1, lastHour: 1 },
    ml: null,
    settings: SETTINGS,
    now: NOW,
    ...overrides,
  };
}
const codes = (r) => r.reasons.map((x) => x.code);

describe("evaluate — Genuine", () => {
  test("sold product with matching hashes and clean history is Genuine", () => {
    const r = evaluate(scenario("Sold"));
    expect(r.status).toBe("Genuine");
    expect(codes(r)).toEqual(expect.arrayContaining(["ON_CHAIN", "QR_HASH_MATCH", "METADATA_MATCH", "HISTORY_CONSISTENT", "SOLD"]));
    expect(r.reasons.every((x) => x.severity === "ok" || x.severity === "info")).toBe(true);
  });

  test("product at retailer is Genuine", () => {
    expect(evaluate(scenario("AtRetailer")).status).toBe("Genuine");
  });

  test("manual entry (no QR hash) can still be Genuine, with an info note", () => {
    const r = evaluate(scenario("AtRetailer", { parsed: parsePayload(metadata.productId) }));
    expect(r.status).toBe("Genuine");
    expect(codes(r)).toContain("QR_NOT_CHECKED");
  });
});

describe("evaluate — Unverified", () => {
  test("malformed payload", () => {
    const r = evaluate({ parsed: parsePayload("not a code") });
    expect(r.status).toBe("Unverified");
    expect(codes(r)).toEqual(["MALFORMED_PAYLOAD"]);
  });

  test("product ID not on chain is Unverified, not counterfeit", () => {
    const r = evaluate({ parsed: parsePayload("VT-2026-999999"), chainProduct: { exists: false } });
    expect(r.status).toBe("Unverified");
    expect(codes(r)).toEqual(["NOT_ON_CHAIN"]);
    expect(r.reasons[0].message).toMatch(/does not prove it is counterfeit/);
  });
});

describe("evaluate — Suspect", () => {
  test("QR hash differs from chain hash (forged QR)", () => {
    const forged = parsePayload(`veritrace://verify?id=${metadata.productId}&h=${"ab".repeat(32)}`);
    const r = evaluate(scenario("Sold", { parsed: forged }));
    expect(r.status).toBe("Suspect");
    expect(r.reasons[0].code).toBe("QR_HASH_MISMATCH");
  });

  test("Firestore metadata altered after registration (tampered DB)", () => {
    const s = scenario("AtRetailer");
    s.metadata.expiryDate = "2030-01-01";
    const r = evaluate(s);
    expect(r.status).toBe("Suspect");
    expect(codes(r)).toContain("METADATA_TAMPERED");
  });

  test("changing a non-identity field (mrp) is NOT tampering", () => {
    const s = scenario("AtRetailer");
    s.metadata.mrp = 999;
    expect(evaluate(s).status).toBe("Genuine");
  });

  test("history inconsistent with current chain state", () => {
    const r = evaluate(scenario("Sold", { chainProduct: { ...scenario("Sold").chainProduct, currentHolder: S2 } }));
    expect(r.status).toBe("Suspect");
    expect(codes(r)).toContain("HISTORY_INCONSISTENT");
  });

  test("event count mismatch is inconsistent", () => {
    expect(evaluate(scenario("Sold", { eventCount: 3 })).status).toBe("Suspect");
  });

  test("Suspect outranks Flagged", () => {
    const s = scenario("Manufactured", { parsed: parsePayload(`veritrace://verify?id=${metadata.productId}&h=${"cd".repeat(32)}`) });
    const r = evaluate(s);
    expect(r.status).toBe("Suspect");
    expect(codes(r)).toEqual(expect.arrayContaining(["QR_HASH_MISMATCH", "NOT_AT_RETAIL"]));
    expect(r.reasons[0].severity).toBe("critical");
  });
});

describe("evaluate — Flagged", () => {
  test.each(["Manufactured", "AtSupplier"])("consumer scan at stage %s (not yet at retail)", (stage) => {
    const r = evaluate(scenario(stage));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("NOT_AT_RETAIL");
  });

  test("pending transfer", () => {
    const history = [...HISTORIES.AtSupplier, ev("TransferInitiated", S1, R, 3, "AtSupplier")];
    const s = scenario("AtSupplier", { history, eventCount: history.length });
    s.chainProduct.pendingRecipient = R;
    const r = evaluate(s);
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("TRANSFER_PENDING");
    expect(codes(r)).not.toContain("HISTORY_INCONSISTENT");
  });

  test("expired product", () => {
    const s = scenario("AtRetailer");
    s.metadata.expiryDate = "2026-01-02";
    s.chainProduct.productHash = computeProductHash(s.metadata);
    s.parsed = parsePayload(buildPayload(metadata.productId, s.chainProduct.productHash));
    const r = evaluate(s);
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("EXPIRED");
  });

  test("not expired when expiry is in the future", () => {
    const s = scenario("AtRetailer");
    s.metadata.expiryDate = "2099-01-01";
    s.chainProduct.productHash = computeProductHash(s.metadata);
    s.parsed = parsePayload(buildPayload(metadata.productId, s.chainProduct.productHash));
    expect(evaluate(s).status).toBe("Genuine");
  });

  test("scan count above threshold (possible copied QR)", () => {
    expect(codes(evaluate(scenario("Sold", { scanStats: { count: 10, distinctDevices: 1 } })))).not.toContain("EXCESSIVE_SCANS");
    const r = evaluate(scenario("Sold", { scanStats: { count: 11, distinctDevices: 1 } }));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("EXCESSIVE_SCANS");
  });

  test("distinct devices above threshold (possible clone)", () => {
    expect(evaluate(scenario("Sold", { scanStats: { count: 5, distinctDevices: 5 } })).status).toBe("Genuine");
    const r = evaluate(scenario("Sold", { scanStats: { count: 6, distinctDevices: 6 } }));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("MANY_DEVICES");
  });

  test("handoff gap below threshold", () => {
    const fast = HISTORIES.AtRetailer.map((h, i) => ({ ...h, timestamp: T0 + i * 5 }));
    const r = evaluate(scenario("AtRetailer", { history: fast }));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("FAST_HANDOFF");
    expect(evaluate(scenario("AtRetailer", { history: fast, settings: { ...SETTINGS, minHandoffGapSeconds: 1 } })).status).toBe("Genuine");
  });

  test("metadata missing while chain record exists", () => {
    const r = evaluate(scenario("AtRetailer", { metadata: null }));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("METADATA_MISSING");
  });

  test("ML anomaly raises to Flagged only", () => {
    const r = evaluate(scenario("Sold", { ml: { anomalyScore: 0.9, isAnomaly: true } }));
    expect(r.status).toBe("Flagged");
    expect(codes(r)).toContain("ML_ANOMALY");
    expect(r.reasons.find((x) => x.code === "ML_ANOMALY").severity).toBe("warning");
  });

  test("ML not anomalous / unavailable leaves Genuine", () => {
    const scored = evaluate(scenario("Sold", { ml: { anomalyScore: 0.1, isAnomaly: false } }));
    expect(scored.status).toBe("Genuine");
    expect(scored.reasons.find((r) => r.code === "ML_NORMAL").severity).toBe("ok");
    const offline = evaluate(scenario("Sold", { ml: null }));
    expect(offline.status).toBe("Genuine");
    expect(codes(offline)).not.toContain("ML_NORMAL");
  });
});

describe("history helpers", () => {
  test("valid histories are consistent", () => {
    for (const stage of Object.keys(HISTORIES)) {
      expect(checkHistoryConsistency(HISTORIES[stage], scenario(stage).chainProduct)).toEqual([]);
    }
  });

  test("detects a receipt without a matching transfer", () => {
    const bad = [ev("Registered", M, M, 0, "Manufactured"), ev("Received", M, S1, 1, "AtSupplier")];
    const issues = checkHistoryConsistency(bad, { manufacturer: M, currentHolder: S1, stage: "AtSupplier", pendingRecipient: null });
    expect(issues.join(" ")).toMatch(/without a matching pending transfer/);
  });

  test("detects manufacturer -> retailer skipping suppliers, and out-of-order timestamps", () => {
    const bad = [ev("Registered", M, M, 5, "Manufactured"), ev("TransferInitiated", M, R, 1, "Manufactured"), ev("Received", M, R, 2, "AtRetailer")];
    const issues = checkHistoryConsistency(bad, { manufacturer: M, currentHolder: R, stage: "AtRetailer", pendingRecipient: null });
    expect(issues).toEqual(expect.arrayContaining(["events are out of chronological order", "product reached a retailer without passing through a supplier"]));
  });

  test("detects activity after sale", () => {
    const bad = [...HISTORIES.Sold, ev("TransferInitiated", R, S1, 8, "Sold")];
    const issues = checkHistoryConsistency(bad, { manufacturer: M, currentHolder: R, stage: "Sold", pendingRecipient: S1 });
    expect(issues).toContain("activity recorded after the product was sold");
  });

  test("custody gaps only count custody changes", () => {
    expect(custodyGaps(HISTORIES.AtSupplier)).toEqual([2 * HOUR]);
    expect(custodyGaps(HISTORIES.Manufactured)).toEqual([]);
  });

  test("ML features", () => {
    const f = mlFeatures({ history: HISTORIES.Sold, scanStats: { count: 3, distinctDevices: 2, lastHour: 1 }, chainProduct: scenario("Sold").chainProduct, now: NOW });
    expect(f).toMatchObject({ numHandoffs: 3, minGapSeconds: HOUR, scanCount: 3, distinctDevices: 2, scansLastHour: 1, stage: "Sold" });
  });
});

describe("verify() orchestration", () => {
  const makeDeps = (overrides = {}) => {
    const s = scenario("AtRetailer");
    const scans = [];
    return {
      scans,
      deps: {
        chain: {
          getProduct: jest.fn(async (id) => (id === metadata.productId ? s.chainProduct : { exists: false })),
          getHistory: jest.fn(async () => ({ handoffs: s.history.map((h) => ({ ...h, txHash: "0xtx", blockNumber: 1 })), eventCount: s.history.length })),
        },
        store: {
          getProduct: jest.fn(async () => s.metadata),
          getScanStats: jest.fn(async () => ({ count: 0, distinctDevices: 0, lastHour: 0, devices: new Set() })),
          getVerificationSettings: jest.fn(async () => SETTINGS),
          getAddressBook: jest.fn(async () => new Map([[M.toLowerCase(), { uid: "uid-m", displayName: "Aurora", role: "manufacturer" }]])),
          addScan: jest.fn(async (scan) => scans.push(scan)),
        },
        ml: { score: jest.fn(async () => null) },
        views: require("../services/productView"),
        contractInfo: () => ({ address: "0xC", chainId: 31337, network: "localhost" }),
        now: () => NOW,
        ...overrides,
      },
    };
  };

  test("records every scan and returns product, journey and technical details", async () => {
    const { deps, scans } = makeDeps();
    const r = await verify({ payload: buildPayload(metadata.productId, HASH), deviceId: "dev-1" }, deps);
    expect(r.status).toBe("Genuine");
    expect(r.product.name).toBe("Aurora X1");
    expect(r.journey).toHaveLength(5);
    expect(r.journey[0].from.name).toBe("Aurora");
    expect(r.technical).toMatchObject({ contractAddress: "0xC", chainId: 31337, productHash: HASH, scanCount: 1 });
    expect(scans).toHaveLength(1);
    expect(scans[0]).toMatchObject({ productId: metadata.productId, deviceId: "dev-1", status: "Genuine" });
  });

  test("records Unverified scans for unknown IDs and malformed payloads", async () => {
    const { deps, scans } = makeDeps();
    expect((await verify({ productId: "VT-2026-424242" }, deps)).status).toBe("Unverified");
    expect((await verify({ payload: "garbage!" }, deps)).status).toBe("Unverified");
    expect(scans.map((s) => s.status)).toEqual(["Unverified", "Unverified"]);
    expect(deps.chain.getHistory).not.toHaveBeenCalled();
  });

  test("ML failure does not break verification", async () => {
    const { deps, scans } = makeDeps({ ml: { score: jest.fn(async () => null) } });
    const r = await verify({ productId: metadata.productId }, deps);
    expect(r.status).toBe("Genuine");
    expect(r.technical.ml).toBeNull();
    expect(scans[0]).toMatchObject({ mlScored: false, ml: null });
  });

  test("ML score is sent the journey features, returned in technical details and stored with the scan", async () => {
    const score = jest.fn(async () => ({ anomalyScore: 0.7, isAnomaly: true, threshold: 0.56, modelVersion: "iforest-test" }));
    const { deps, scans } = makeDeps({ ml: { score } });
    const r = await verify({ productId: metadata.productId, deviceId: "d1" }, deps);
    expect(score).toHaveBeenCalledWith(expect.objectContaining({ numHandoffs: 2, scanCount: 1, distinctDevices: 1, stage: "AtRetailer" }));
    expect(r.status).toBe("Flagged");
    expect(r.technical.ml).toMatchObject({ anomalyScore: 0.7, isAnomaly: true, threshold: 0.56, features: expect.objectContaining({ scanCount: 1 }) });
    expect(scans[0]).toMatchObject({ mlScored: true, ml: { anomalyScore: 0.7, isAnomaly: true, modelVersion: "iforest-test" } });
    expect(scans[0].flags).toContain("ML_ANOMALY");
  });
});
