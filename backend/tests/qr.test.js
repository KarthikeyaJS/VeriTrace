const { buildPayload, parsePayload } = require("../services/qr");

const HASH = `0x${"1f".repeat(32)}`;

describe("QR payload", () => {
  test("build/parse round trip", () => {
    const payload = buildPayload("VT-2026-000042", HASH);
    expect(payload).toBe(`veritrace://verify?id=VT-2026-000042&h=${"1f".repeat(32)}`);
    expect(parsePayload(payload)).toEqual({ ok: true, productId: "VT-2026-000042", qrHash: HASH, source: "qr" });
  });

  test("accepts a bare product ID (manual entry), case-insensitive", () => {
    expect(parsePayload("  vt-2026-000042 ")).toEqual({ ok: true, productId: "VT-2026-000042", qrHash: null, source: "manual" });
  });

  test("accepts an https /verify link and a 0x-prefixed hash", () => {
    const r = parsePayload(`https://veritrace.example/verify?id=VT-2026-000001&h=0x${"1f".repeat(32)}`);
    expect(r).toMatchObject({ ok: true, productId: "VT-2026-000001", qrHash: HASH });
  });

  test("QR without hash is accepted (no fingerprint check)", () => {
    expect(parsePayload("veritrace://verify?id=VT-2026-000001")).toMatchObject({ ok: true, qrHash: null, source: "qr" });
  });

  test.each([
    ["", "empty"],
    ["hello world", "random text"],
    ["https://example.com/?q=1", "unrelated URL"],
    ["veritrace://other?id=VT-2026-000001", "wrong host"],
    ["veritrace://verify?h=abc", "missing id"],
    [`veritrace://verify?id=VT-2026-000001&h=1234`, "truncated hash"],
    ["veritrace://verify?id=<script>&h=" + "1f".repeat(32), "invalid id"],
  ])("rejects %p (%s)", (input) => {
    expect(parsePayload(input).ok).toBe(false);
  });
});
