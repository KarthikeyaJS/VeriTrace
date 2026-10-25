// Product fingerprint: SHA-256 of the canonical JSON of the immutable identity fields.
// This is the ONLY place canonicalization happens — registration and verification both use it.
const crypto = require("crypto");

const IDENTITY_FIELDS = Object.freeze(
  [
    "productId",
    "name",
    "brand",
    "category",
    "batchNumber",
    "serialNumber",
    "manufactureDate",
    "expiryDate",
    "countryOfOrigin",
    "manufacturerId",
  ].sort()
);
const DATE_FIELDS = new Set(["manufactureDate", "expiryDate"]);

/** Normalizes a date-like value to YYYY-MM-DD (UTC for Date objects), or null. */
function normalizeDate(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value?.toDate === "function") value = value.toDate(); // Firestore Timestamp
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) throw new Error("Invalid date");
    return value.toISOString().slice(0, 10);
  }
  const s = String(value).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  if (!m) throw new Error(`Invalid date "${s}" (expected YYYY-MM-DD)`);
  return `${m[1]}-${m[2]}-${m[3]}`;
}

function normalizeValue(field, value) {
  if (DATE_FIELDS.has(field)) return normalizeDate(value);
  if (value === undefined || value === null) return null;
  const s = String(value).trim();
  return s === "" ? null : s;
}

/** Canonical JSON: identity fields only, keys sorted, no whitespace, missing optionals as null. */
function canonicalize(product) {
  const out = {};
  for (const field of IDENTITY_FIELDS) out[field] = normalizeValue(field, product[field]);
  return JSON.stringify(out);
}

function sha256Hex(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

/** bytes32-compatible fingerprint: "0x" + 64 lowercase hex chars. */
function computeProductHash(product) {
  return `0x${sha256Hex(canonicalize(product))}`;
}

/** Accepts a hash with or without 0x; returns "0x<64 hex>" lowercase, or null if malformed. */
function normalizeHash(hash) {
  if (typeof hash !== "string") return null;
  const h = hash.trim().toLowerCase().replace(/^0x/, "");
  return /^[0-9a-f]{64}$/.test(h) ? `0x${h}` : null;
}

module.exports = { IDENTITY_FIELDS, canonicalize, computeProductHash, normalizeHash, normalizeDate, sha256Hex };
