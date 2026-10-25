const { canonicalize, computeProductHash, normalizeHash, normalizeDate, IDENTITY_FIELDS } = require("../services/hashing");

const base = {
  productId: "VT-2026-000001",
  name: "Aurora X1 Smartphone",
  brand: "Aurora",
  category: "Electronics",
  batchNumber: "B-001",
  serialNumber: "SN-123",
  manufactureDate: "2026-01-15",
  expiryDate: null,
  countryOfOrigin: "India",
  manufacturerId: "uid-maker",
};

describe("hashing", () => {
  test("same input gives the same hash regardless of key order", () => {
    const reversed = Object.fromEntries(Object.entries(base).reverse());
    expect(computeProductHash(reversed)).toBe(computeProductHash(base));
    expect(canonicalize(reversed)).toBe(canonicalize(base));
  });

  test("canonical JSON has sorted keys, no whitespace, and null for missing optionals", () => {
    const { serialNumber, expiryDate, ...withoutOptionals } = base;
    const json = canonicalize(withoutOptionals);
    expect(json).not.toMatch(/\s(?=["{}:,])/);
    const parsed = JSON.parse(json);
    expect(Object.keys(parsed)).toEqual([...IDENTITY_FIELDS]);
    expect(Object.keys(parsed)).toEqual([...Object.keys(parsed)].sort());
    expect(parsed.serialNumber).toBeNull();
    expect(parsed.expiryDate).toBeNull();
  });

  test("matches a known vector", () => {
    expect(canonicalize(base)).toBe(
      '{"batchNumber":"B-001","brand":"Aurora","category":"Electronics","countryOfOrigin":"India","expiryDate":null,' +
        '"manufactureDate":"2026-01-15","manufacturerId":"uid-maker","name":"Aurora X1 Smartphone","productId":"VT-2026-000001","serialNumber":"SN-123"}'
    );
    expect(computeProductHash(base)).toMatch(/^0x[0-9a-f]{64}$/);
  });

  test("ignores non-identity fields (mrp, description, hash, createdAt)", () => {
    const extra = { ...base, mrp: 19999, description: "x", hash: "0xabc", createdAt: "2026-01-01T00:00:00Z" };
    expect(computeProductHash(extra)).toBe(computeProductHash(base));
  });

  test("any identity field change changes the hash", () => {
    const h = computeProductHash(base);
    for (const field of IDENTITY_FIELDS) {
      const value = field.endsWith("Date") ? "2027-02-02" : "changed";
      expect(computeProductHash({ ...base, [field]: value })).not.toBe(h);
    }
  });

  test("empty strings and undefined are treated as null; strings are trimmed", () => {
    expect(computeProductHash({ ...base, serialNumber: "" })).toBe(computeProductHash({ ...base, serialNumber: undefined }));
    expect(computeProductHash({ ...base, name: `  ${base.name} ` })).toBe(computeProductHash(base));
  });

  test("dates normalize to YYYY-MM-DD from strings, Dates and Firestore Timestamps", () => {
    expect(normalizeDate("2026-01-15")).toBe("2026-01-15");
    expect(normalizeDate("2026-01-15T10:00:00.000Z")).toBe("2026-01-15");
    expect(normalizeDate(new Date("2026-01-15T00:00:00Z"))).toBe("2026-01-15");
    expect(normalizeDate({ toDate: () => new Date("2026-01-15T00:00:00Z") })).toBe("2026-01-15");
    expect(normalizeDate(null)).toBeNull();
    expect(() => normalizeDate("15/01/2026")).toThrow();
    expect(computeProductHash({ ...base, manufactureDate: new Date("2026-01-15T00:00:00Z") })).toBe(computeProductHash(base));
  });

  test("normalizeHash accepts with/without 0x and rejects malformed values", () => {
    const h = "AB".repeat(32);
    expect(normalizeHash(h)).toBe(`0x${"ab".repeat(32)}`);
    expect(normalizeHash(`0x${h}`)).toBe(`0x${"ab".repeat(32)}`);
    expect(normalizeHash("0x1234")).toBeNull();
    expect(normalizeHash("zz".repeat(32))).toBeNull();
    expect(normalizeHash(undefined)).toBeNull();
  });
});
