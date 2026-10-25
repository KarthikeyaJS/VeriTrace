// Firebase Admin initialisation + all Firestore data access.
// Collections: users, products, scans, counters, audit, settings.
// Timestamps are stored as ISO-8601 strings; dates (manufacture/expiry) as YYYY-MM-DD strings.
const fs = require("fs");
const admin = require("firebase-admin");
const config = require("../config");
const { AppError } = require("../utils/errors");

let app = null;

function init() {
  if (app) return app;
  if (config.firebase.usingEmulator) {
    app = admin.initializeApp({ projectId: config.firebase.projectId });
    return app;
  }
  const keyPath = config.firebase.serviceAccountPath;
  if (!fs.existsSync(keyPath)) {
    throw new AppError(
      503,
      "FIREBASE_NOT_CONFIGURED",
      `Firebase is not configured: ${keyPath} not found. Add the service account key or set FIRESTORE_EMULATOR_HOST to use the emulators.`
    );
  }
  const serviceAccount = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: config.firebase.projectId || serviceAccount.project_id,
  });
  return app;
}

const db = () => {
  init();
  return admin.firestore();
};
const auth = () => {
  init();
  return admin.auth();
};

const nowIso = () => new Date().toISOString();
const docData = (snap) => (snap.exists ? { id: snap.id, ...snap.data() } : null);

// ------------------------------------------------------------------ users
async function getUser(uid) {
  return docData(await db().collection("users").doc(uid).get());
}

async function listUsers({ role } = {}) {
  let q = db().collection("users");
  if (role) q = q.where("role", "==", role);
  const snap = await q.get();
  return snap.docs
    .map((d) => ({ uid: d.id, ...d.data() }))
    .sort((a, b) => (a.displayName || "").localeCompare(b.displayName || ""));
}

async function setUser(uid, data) {
  await db().collection("users").doc(uid).set(data, { merge: true });
  return getUser(uid);
}

/** Map of lower-cased wallet address -> { uid, displayName, role } for naming parties in journeys. */
async function getAddressBook() {
  const users = await listUsers();
  const book = new Map();
  for (const u of users) {
    if (u.walletAddress) book.set(u.walletAddress.toLowerCase(), { uid: u.uid, displayName: u.displayName, role: u.role });
  }
  return book;
}

// Indices 0-9 are reserved for the deployer (0) and the seeded demo accounts.
const FIRST_DYNAMIC_WALLET_INDEX = 10;

/** Next HD wallet index for a newly created account. Survives a cleared counters collection. */
async function allocateWalletIndex() {
  const ref = db().collection("counters").doc("wallets");
  const highestQuery = db().collection("users").orderBy("walletIndex", "desc").limit(1);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let next = snap.exists ? snap.data().next : null;
    if (!Number.isInteger(next)) {
      const top = await tx.get(highestQuery);
      next = top.empty ? FIRST_DYNAMIC_WALLET_INDEX : top.docs[0].data().walletIndex + 1;
    }
    next = Math.max(next, FIRST_DYNAMIC_WALLET_INDEX);
    tx.set(ref, { next: next + 1, updatedAt: nowIso() });
    return next;
  });
}

// --------------------------------------------------------------- products
async function getProduct(productId) {
  return docData(await db().collection("products").doc(productId).get());
}

async function saveProduct(productId, data) {
  await db().collection("products").doc(productId).set(data);
}

async function updateProduct(productId, data) {
  await db().collection("products").doc(productId).update(data);
}

async function listProducts({ manufacturerId } = {}) {
  let q = db().collection("products");
  if (manufacturerId) q = q.where("manufacturerId", "==", manufacturerId);
  const snap = await q.get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (b.createdAt || "").localeCompare(a.createdAt || ""));
}

async function getProductsByIds(ids) {
  if (!ids.length) return new Map();
  const refs = ids.map((id) => db().collection("products").doc(id));
  const snaps = await db().getAll(...refs);
  return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, { id: s.id, ...s.data() }]));
}

/**
 * Allocates the next product ID `VT-<YYYY>-<NNNNNN>` in a transaction on counters/products.
 * Skips numbers that already have a Firestore product document (e.g. after manual imports).
 */
async function allocateProductId(now = new Date()) {
  const year = String(now.getFullYear());
  const counterRef = db().collection("counters").doc("products");
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    let seq = snap.exists && Number.isInteger(snap.data()[year]) ? snap.data()[year] : 0;
    let candidate;
    for (let i = 0; i < 50; i++) {
      seq += 1;
      candidate = `VT-${year}-${String(seq).padStart(6, "0")}`;
      const existing = await tx.get(db().collection("products").doc(candidate));
      if (!existing.exists) break;
    }
    tx.set(counterRef, { [year]: seq, updatedAt: nowIso() }, { merge: true });
    return candidate;
  });
}

// ------------------------------------------------------------------ scans
async function addScan(scan) {
  await db().collection("scans").add({ ...scan, at: scan.at || nowIso() });
}

/** Prior scans of a product: total, distinct devices, last-hour count, and the set of device IDs. */
async function getScanStats(productId, now = new Date()) {
  const snap = await db().collection("scans").where("productId", "==", productId).select("deviceId", "at").get();
  const devices = new Set();
  const hourAgo = new Date(now.getTime() - 3600 * 1000).toISOString();
  let lastHour = 0;
  for (const d of snap.docs) {
    const { deviceId, at } = d.data();
    if (deviceId) devices.add(deviceId);
    if (at && at >= hourAgo) lastHour += 1;
  }
  return { count: snap.size, distinctDevices: devices.size, lastHour, devices };
}

async function listScans({ statuses, limit = 50 } = {}) {
  let q = db().collection("scans");
  if (statuses && statuses.length) q = q.where("status", "in", statuses);
  const snap = await q.get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .sort((a, b) => (b.at || "").localeCompare(a.at || ""))
    .slice(0, limit);
}

async function countScansByStatus(statuses) {
  const counts = {};
  await Promise.all(
    statuses.map(async (s) => {
      const agg = await db().collection("scans").where("status", "==", s).count().get();
      counts[s] = agg.data().count;
    })
  );
  return counts;
}

// ------------------------------------------------------------------ audit
async function addAudit(entry) {
  await db().collection("audit").add({ ...entry, at: nowIso() });
}

// --------------------------------------------------------------- settings
const SETTINGS_TTL_MS = 10_000;
let settingsCache = { at: 0, value: null };

/** Verification thresholds: .env defaults overridden by Firestore settings/verification (cached 10 s). */
async function getVerificationSettings() {
  if (settingsCache.value && Date.now() - settingsCache.at < SETTINGS_TTL_MS) return settingsCache.value;
  const defaults = { ...config.verification };
  let override = {};
  try {
    const snap = await db().collection("settings").doc("verification").get();
    if (snap.exists) override = snap.data();
  } catch {
    // fall back to defaults
  }
  const value = {
    scanFlagThreshold: Number.isFinite(override.scanFlagThreshold) ? override.scanFlagThreshold : defaults.scanFlagThreshold,
    deviceFlagThreshold: Number.isFinite(override.deviceFlagThreshold) ? override.deviceFlagThreshold : defaults.deviceFlagThreshold,
    minHandoffGapSeconds: Number.isFinite(override.minHandoffGapSeconds) ? override.minHandoffGapSeconds : defaults.minHandoffGapSeconds,
  };
  settingsCache = { at: Date.now(), value };
  return value;
}

async function setVerificationSettings(values) {
  await db().collection("settings").doc("verification").set({ ...values, updatedAt: nowIso() });
  settingsCache = { at: 0, value: null };
}

// ------------------------------------------------------------- maintenance
async function clearCollection(name) {
  await db().recursiveDelete(db().collection(name));
}

async function ping() {
  await db().collection("settings").doc("verification").get();
  return true;
}

module.exports = {
  init,
  db,
  auth,
  nowIso,
  getUser,
  listUsers,
  setUser,
  getAddressBook,
  allocateWalletIndex,
  getProduct,
  saveProduct,
  updateProduct,
  listProducts,
  getProductsByIds,
  allocateProductId,
  addScan,
  getScanStats,
  listScans,
  countScansByStatus,
  addAudit,
  getVerificationSettings,
  setVerificationSettings,
  clearCollection,
  ping,
};
