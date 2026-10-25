// Verification rules — the single source of truth for Genuine / Flagged / Suspect / Unverified.
//
//   Unverified  malformed payload, or product ID not on chain (never "counterfeit")
//   Suspect     QR hash != chain hash; Firestore metadata hash != chain hash; inconsistent history
//   Flagged     pre-retail stage; pending transfer; expired; over-scanned / many devices;
//               handoff gap below threshold; metadata missing; ML anomaly (ML can never cause Suspect)
//   Genuine     none of the above
//
// `evaluate()` is pure (unit-tested without a chain); `verify()` gathers the inputs and records the scan.
const { computeProductHash } = require("./hashing");
const { parsePayload } = require("./qr");

const STATUS = Object.freeze({ GENUINE: "Genuine", FLAGGED: "Flagged", SUSPECT: "Suspect", UNVERIFIED: "Unverified" });
const SEVERITY_ORDER = { critical: 0, warning: 1, info: 2, ok: 3 };

const reason = (code, severity, message) => ({ code, severity, message });
const lower = (a) => (a ? a.toLowerCase() : null);
const isoDate = (seconds) => new Date(seconds * 1000).toISOString();
const todayUtc = (now) => now.toISOString().slice(0, 10);

/** Replays the handoff history and returns a list of inconsistencies (empty = consistent). */
function checkHistoryConsistency(history, chainProduct) {
  const issues = [];
  if (!history || history.length === 0) return ["no custody events recorded"];
  const [first, ...rest] = history;
  if (first.eventType !== "Registered") issues.push("first event is not a registration");
  if (lower(first.from) !== lower(chainProduct.manufacturer)) issues.push("registration was not made by the manufacturer");

  let holder = lower(first.to);
  let stage = "Manufactured";
  let pending = null;
  let lastTs = first.timestamp;

  for (const h of rest) {
    if (h.timestamp < lastTs) issues.push("events are out of chronological order");
    lastTs = h.timestamp;
    const from = lower(h.from);
    const to = lower(h.to);
    switch (h.eventType) {
      case "Registered":
        issues.push("product registered more than once");
        break;
      case "TransferInitiated":
        if (from !== holder) issues.push("transfer started by a party that did not hold the product");
        if (pending) issues.push("transfer started while another was pending");
        if (stage === "AtRetailer" || stage === "Sold") issues.push(`transfer started at stage ${stage}`);
        pending = to;
        break;
      case "TransferCancelled":
        if (from !== holder || !pending || to !== pending) issues.push("cancellation does not match the pending transfer");
        pending = null;
        break;
      case "Received":
        if (!pending || to !== pending) issues.push("receipt confirmed without a matching pending transfer");
        if (from !== holder) issues.push("receipt does not follow the previous holder");
        if (h.stageAfter === "AtRetailer" && stage !== "AtSupplier") issues.push("product reached a retailer without passing through a supplier");
        if (h.stageAfter !== "AtSupplier" && h.stageAfter !== "AtRetailer") issues.push(`invalid stage after receipt (${h.stageAfter})`);
        holder = to;
        stage = h.stageAfter;
        pending = null;
        break;
      case "Sold":
        if (from !== holder) issues.push("sale recorded by a party that did not hold the product");
        if (stage !== "AtRetailer") issues.push("sold before reaching a retailer");
        stage = "Sold";
        break;
      default:
        issues.push(`unknown event type ${h.eventType}`);
    }
    if (stage === "Sold" && h.eventType !== "Sold") issues.push("activity recorded after the product was sold");
  }

  if (holder !== lower(chainProduct.currentHolder)) issues.push("current holder does not match the custody history");
  if (stage !== chainProduct.stage) issues.push("current stage does not match the custody history");
  if (pending !== lower(chainProduct.pendingRecipient)) issues.push("pending transfer does not match the custody history");
  return [...new Set(issues)];
}

/** Seconds between consecutive custody changes (Registered, Received, Sold). */
function custodyGaps(history) {
  const ts = (history || []).filter((h) => ["Registered", "Received", "Sold"].includes(h.eventType)).map((h) => h.timestamp);
  const gaps = [];
  for (let i = 1; i < ts.length; i++) gaps.push(ts[i] - ts[i - 1]);
  return gaps;
}

function statusFromReasons(reasons) {
  if (reasons.some((r) => r.severity === "critical")) return STATUS.SUSPECT;
  if (reasons.some((r) => r.severity === "warning")) return STATUS.FLAGGED;
  return STATUS.GENUINE;
}

const sortReasons = (reasons) => [...reasons].sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);

/**
 * Pure rule evaluation.
 * @param {object} input
 * @param {object} input.parsed        result of parsePayload()
 * @param {object|null} input.chainProduct  normalized on-chain product (exists flag)
 * @param {Array}  input.history       ordered handoffs [{eventType, from, to, timestamp, stageAfter}]
 * @param {number|null} input.eventCount number of contract events found (null = unknown)
 * @param {object|null} input.metadata Firestore product document
 * @param {object} input.scanStats     { count, distinctDevices } INCLUDING the current scan
 * @param {object|null} input.ml       { anomalyScore, isAnomaly } or null when unavailable
 * @param {object} input.settings      { scanFlagThreshold, deviceFlagThreshold, minHandoffGapSeconds }
 * @param {Date}   input.now
 */
function evaluate({ parsed, chainProduct, history = [], eventCount = null, metadata = null, scanStats, ml = null, settings, now = new Date() }) {
  if (!parsed || !parsed.ok) {
    return { status: STATUS.UNVERIFIED, reasons: [reason("MALFORMED_PAYLOAD", "info", parsed?.error || "This is not a VeriTrace QR code.")] };
  }
  if (!chainProduct || !chainProduct.exists) {
    return {
      status: STATUS.UNVERIFIED,
      reasons: [
        reason(
          "NOT_ON_CHAIN",
          "info",
          `No blockchain record exists for ${parsed.productId}. It cannot be verified — this alone does not prove it is counterfeit.`
        ),
      ],
    };
  }

  const reasons = [reason("ON_CHAIN", "ok", `Registered on the blockchain on ${isoDate(chainProduct.registeredAt).slice(0, 10)}.`)];

  // ---- Suspect (critical)
  if (parsed.qrHash) {
    if (parsed.qrHash.toLowerCase() !== chainProduct.productHash.toLowerCase()) {
      reasons.push(reason("QR_HASH_MISMATCH", "critical", "The QR code's fingerprint does not match the blockchain record — this QR code may be forged or altered."));
    } else {
      reasons.push(reason("QR_HASH_MATCH", "ok", "QR fingerprint matches the blockchain record."));
    }
  } else {
    reasons.push(reason("QR_NOT_CHECKED", "info", "Product ID entered manually — the QR fingerprint was not checked."));
  }

  if (metadata) {
    let recomputed = null;
    try {
      recomputed = computeProductHash(metadata);
    } catch {
      recomputed = null;
    }
    if (!recomputed || recomputed !== chainProduct.productHash.toLowerCase()) {
      reasons.push(
        reason("METADATA_TAMPERED", "critical", "The product details on record do not match the fingerprint registered on the blockchain — the record may have been tampered with.")
      );
    } else {
      reasons.push(reason("METADATA_MATCH", "ok", "Product details match the fingerprint registered on the blockchain."));
    }
  }

  const issues = checkHistoryConsistency(history, chainProduct);
  if (eventCount !== null && eventCount !== history.length) issues.push("contract events do not match the stored history");
  if (issues.length) {
    reasons.push(reason("HISTORY_INCONSISTENT", "critical", `The custody history is inconsistent: ${issues[0]}.`));
  } else {
    reasons.push(reason("HISTORY_CONSISTENT", "ok", `Custody history is consistent (${history.length} recorded events).`));
  }

  // ---- Flagged (warning)
  if (chainProduct.stage === "Manufactured" || chainProduct.stage === "AtSupplier") {
    const where = chainProduct.stage === "Manufactured" ? "manufacturer" : "distributor";
    reasons.push(reason("NOT_AT_RETAIL", "warning", `Not yet released for retail sale — the blockchain shows it is still with the ${where}.`));
  }
  if (chainProduct.pendingRecipient) {
    reasons.push(reason("TRANSFER_PENDING", "warning", "A custody transfer is in progress and has not been confirmed by the recipient."));
  }
  if (metadata && metadata.expiryDate && String(metadata.expiryDate).slice(0, 10) < todayUtc(now)) {
    reasons.push(reason("EXPIRED", "warning", `This product expired on ${String(metadata.expiryDate).slice(0, 10)}.`));
  }
  if (scanStats && scanStats.count > settings.scanFlagThreshold) {
    reasons.push(reason("EXCESSIVE_SCANS", "warning", `This code has been scanned ${scanStats.count} times — it may have been copied.`));
  }
  if (scanStats && scanStats.distinctDevices > settings.deviceFlagThreshold) {
    reasons.push(reason("MANY_DEVICES", "warning", `This code has been scanned from ${scanStats.distinctDevices} different devices — it may have been cloned.`));
  }
  const gaps = custodyGaps(history);
  if (gaps.length && Math.min(...gaps) < settings.minHandoffGapSeconds) {
    reasons.push(reason("FAST_HANDOFF", "warning", `Custody changed unusually fast (${Math.min(...gaps)} s between handoffs).`));
  }
  if (!metadata) {
    reasons.push(reason("METADATA_MISSING", "warning", "A blockchain record exists, but the product details are missing from the database."));
  }
  if (ml && ml.isAnomaly) {
    reasons.push(reason("ML_ANOMALY", "warning", `This product's journey looks unusual compared with normal supply chains (anomaly score ${Number(ml.anomalyScore).toFixed(2)}).`));
  } else if (ml) {
    reasons.push(reason("ML_NORMAL", "ok", `The anomaly model found nothing unusual in this journey (score ${Number(ml.anomalyScore).toFixed(2)}).`));
  }

  // ---- Informational context
  if (chainProduct.stage === "AtRetailer") reasons.push(reason("AT_RETAILER", "ok", "Held by an authorised retailer."));
  if (chainProduct.stage === "Sold") reasons.push(reason("SOLD", "ok", "Sold to a customer by an authorised retailer."));

  const sorted = sortReasons(reasons);
  return { status: statusFromReasons(sorted), reasons: sorted };
}

/** Feature vector for the ML anomaly service. */
function mlFeatures({ history, scanStats, chainProduct, now }) {
  const gaps = custodyGaps(history);
  const nowSec = Math.floor(now.getTime() / 1000);
  return {
    numHandoffs: history.filter((h) => h.eventType === "Received").length,
    minGapSeconds: gaps.length ? Math.min(...gaps) : 0,
    meanGapSeconds: gaps.length ? gaps.reduce((a, b) => a + b, 0) / gaps.length : 0,
    secondsSinceRegistration: Math.max(0, nowSec - chainProduct.registeredAt),
    scanCount: scanStats.count,
    distinctDevices: scanStats.distinctDevices,
    scansLastHour: scanStats.lastHour,
    stage: chainProduct.stage,
  };
}

/**
 * Full verification: gathers chain + Firestore + ML inputs, evaluates, records the scan.
 * `deps` is injectable for tests.
 */
async function verify({ payload, productId, deviceId }, deps) {
  const { chain, store, ml, views, contractInfo } = deps;
  const now = deps.now ? deps.now() : new Date();
  const parsed = parsePayload(payload ?? productId);
  const info = contractInfo();
  const technical = {
    contractAddress: info.address,
    chainId: info.chainId,
    network: info.network,
    qrHash: parsed.ok ? parsed.qrHash : null,
  };
  const record = (status, reasons, pid, mlResult = null) =>
    store.addScan({
      productId: pid || null,
      at: now.toISOString(),
      deviceId: deviceId || null,
      status,
      reasons: reasons.map((r) => r.code).filter((c, i, a) => a.indexOf(c) === i),
      flags: reasons.filter((r) => r.severity === "critical" || r.severity === "warning").map((r) => r.code),
      mlScored: Boolean(mlResult),
      ml: mlResult ? { anomalyScore: mlResult.anomalyScore, isAnomaly: mlResult.isAnomaly, modelVersion: mlResult.modelVersion } : null,
    });

  if (!parsed.ok) {
    const result = evaluate({ parsed });
    await record(result.status, result.reasons, null);
    return { ...result, product: null, journey: [], technical };
  }

  const chainProduct = await chain.getProduct(parsed.productId);
  if (!chainProduct.exists) {
    const result = evaluate({ parsed, chainProduct });
    await record(result.status, result.reasons, parsed.productId);
    return { ...result, product: { productId: parsed.productId }, journey: [], technical };
  }

  const [{ handoffs, eventCount }, metadata, prior, settings, addressBook] = await Promise.all([
    chain.getHistory(parsed.productId),
    store.getProduct(parsed.productId),
    store.getScanStats(parsed.productId, now),
    store.getVerificationSettings(),
    store.getAddressBook(),
  ]);
  const isNewDevice = deviceId ? !prior.devices.has(deviceId) : false;
  const scanStats = {
    count: prior.count + 1,
    distinctDevices: prior.distinctDevices + (isNewDevice ? 1 : 0),
    lastHour: prior.lastHour + 1,
  };

  const features = mlFeatures({ history: handoffs, scanStats, chainProduct, now });
  const mlResult = await ml.score(features);
  const result = evaluate({ parsed, chainProduct, history: handoffs, eventCount, metadata, scanStats, ml: mlResult, settings, now });
  await record(result.status, result.reasons, parsed.productId, mlResult);

  let recomputedHash = null;
  try {
    recomputedHash = metadata ? computeProductHash(metadata) : null;
  } catch {
    recomputedHash = null;
  }
  const registered = handoffs.find((h) => h.eventType === "Registered");
  return {
    ...result,
    product: views.productView(metadata, chainProduct, addressBook),
    journey: views.journeyView(handoffs, addressBook),
    technical: {
      ...technical,
      productHash: chainProduct.productHash,
      recomputedHash,
      registerTxHash: registered?.txHash || metadata?.registerTxHash || null,
      registerBlock: registered?.blockNumber ?? metadata?.blockNumber ?? null,
      latestBlock: handoffs.length ? handoffs[handoffs.length - 1].blockNumber : null,
      scanCount: scanStats.count,
      distinctDevices: scanStats.distinctDevices,
      // null = ML service disabled, offline or too slow (verification continued without it)
      ml: mlResult ? { ...mlResult, features } : null,
    },
  };
}

module.exports = { STATUS, evaluate, verify, checkHistoryConsistency, custodyGaps, mlFeatures, statusFromReasons };
