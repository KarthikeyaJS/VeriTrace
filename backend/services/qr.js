// QR payload format: veritrace://verify?id=<productId>&h=<64-hex fingerprint>
// Scanners may also send a bare product ID (manual entry). QR codes never contain secrets.
const { normalizeHash } = require("./hashing");

const ID_PATTERN = /^[A-Z0-9][A-Z0-9_-]{2,39}$/;

function buildPayload(productId, hash) {
  const h = normalizeHash(hash);
  return `veritrace://verify?id=${encodeURIComponent(productId)}&h=${h.slice(2)}`;
}

/**
 * Parses a scanned QR / typed ID.
 * @returns {{ok: true, productId: string, qrHash: string|null, source: 'qr'|'manual'} | {ok: false, error: string}}
 */
function parsePayload(raw) {
  if (typeof raw !== "string" || raw.trim() === "") return { ok: false, error: "Empty QR code or product ID." };
  const text = raw.trim();

  if (/^(veritrace|https?):\/\//i.test(text)) {
    let url;
    try {
      url = new URL(text);
    } catch {
      return { ok: false, error: "This QR code is not a valid VeriTrace code." };
    }
    const isApp = url.protocol.toLowerCase() === "veritrace:" && url.hostname.toLowerCase() === "verify";
    const isWeb = /^https?:$/i.test(url.protocol) && /\/verify\/?$/i.test(url.pathname);
    if (!isApp && !isWeb) return { ok: false, error: "This QR code is not a VeriTrace code." };

    const id = (url.searchParams.get("id") || "").trim().toUpperCase();
    if (!ID_PATTERN.test(id)) return { ok: false, error: "The QR code does not contain a valid product ID." };
    const h = url.searchParams.get("h");
    if (h === null || h === "") return { ok: true, productId: id, qrHash: null, source: "qr" };
    const qrHash = normalizeHash(h);
    if (!qrHash) return { ok: false, error: "The QR code's fingerprint is malformed." };
    return { ok: true, productId: id, qrHash, source: "qr" };
  }

  const id = text.toUpperCase();
  if (ID_PATTERN.test(id)) return { ok: true, productId: id, qrHash: null, source: "manual" };
  return { ok: false, error: "This QR code is not a VeriTrace code." };
}

module.exports = { ID_PATTERN, buildPayload, parsePayload };
