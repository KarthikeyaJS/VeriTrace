// HTTP-level tests with Firebase + chain mocked: auth, role gates, validation, public verify.
jest.mock("../services/firestore", () => {
  const users = {
    "tok-maker": { uid: "u-maker", email: "maker@x", displayName: "Aurora", role: "manufacturer", active: true, walletIndex: 1, walletAddress: "0x1111111111111111111111111111111111111111" },
    "tok-supplier": { uid: "u-sup", email: "sup@x", displayName: "Southern", role: "supplier", active: true, walletIndex: 3, walletAddress: "0x2222222222222222222222222222222222222222" },
    "tok-admin": { uid: "u-admin", email: "admin@x", displayName: "Admin", role: "admin", active: true, walletIndex: 0, walletAddress: "0x3333333333333333333333333333333333333333" },
    "tok-disabled": { uid: "u-off", email: "off@x", displayName: "Off", role: "retailer", active: false, walletIndex: 9, walletAddress: "0x4444444444444444444444444444444444444444" },
  };
  const byUid = Object.fromEntries(Object.values(users).map((u) => [u.uid, u]));
  return {
    auth: () => ({
      verifyIdToken: async (token) => {
        if (token === "tok-nobody") return { uid: "u-nobody" };
        if (!users[token]) throw new Error("bad token");
        return { uid: users[token].uid };
      },
    }),
    getUser: async (uid) => byUid[uid] || null,
    listUsers: async ({ role } = {}) => Object.values(byUid).filter((u) => !role || u.role === role),
    getProduct: async () => null,
    getScanStats: async () => ({ count: 0, distinctDevices: 0, lastHour: 0, devices: new Set() }),
    getVerificationSettings: async () => ({ scanFlagThreshold: 10, deviceFlagThreshold: 5, minHandoffGapSeconds: 30 }),
    getAddressBook: async () => new Map(),
    addScan: jest.fn(async () => {}),
    ping: async () => true,
    nowIso: () => new Date().toISOString(),
  };
});

jest.mock("../services/blockchain", () => ({
  getProduct: async () => ({ exists: false }),
  getContractInfo: () => ({ address: "0xC", chainId: 31337, network: "localhost" }),
  getRole: async () => "manufacturer",
  getStatus: async () => ({ connected: true, contractDeployed: true, chainId: 31337 }),
}));

jest.mock("../services/products", () => ({
  CATEGORIES: ["Electronics", "Pharmaceuticals", "Apparel", "Cosmetics", "Food & Beverage", "Automotive Parts", "Luxury Goods", "Other"],
  registerProduct: jest.fn(async (user, input) => ({ product: { productId: "VT-2026-000001", ...input }, qrPayload: "veritrace://verify?id=VT-2026-000001&h=00" })),
}));

const request = require("supertest");
const { createApp } = require("../server");
const products = require("../services/products");

const app = createApp();
const auth = (token) => ({ Authorization: `Bearer ${token}` });
const validProduct = {
  name: "Aurora X1",
  brand: "Aurora",
  category: "Electronics",
  batchNumber: "B-1",
  manufactureDate: "2026-01-10",
};

describe("authentication & authorization", () => {
  test("missing token -> 401", async () => {
    const res = await request(app).get("/me");
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("UNAUTHENTICATED");
  });

  test("invalid token -> 401 INVALID_TOKEN", async () => {
    const res = await request(app).get("/me").set(auth("garbage"));
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("INVALID_TOKEN");
  });

  test("valid token without profile -> 403 NO_PROFILE", async () => {
    expect((await request(app).get("/me").set(auth("tok-nobody"))).body.error.code).toBe("NO_PROFILE");
  });

  test("deactivated account -> 403 ACCOUNT_DISABLED", async () => {
    const res = await request(app).get("/me").set(auth("tok-disabled"));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe("ACCOUNT_DISABLED");
  });

  test("GET /me returns the profile without wallet internals", async () => {
    const res = await request(app).get("/me").set(auth("tok-maker"));
    expect(res.status).toBe(200);
    expect(res.body.user).toMatchObject({ uid: "u-maker", role: "manufacturer", chainRole: "manufacturer" });
    expect(res.body.user.walletIndex).toBeUndefined();
  });

  test("supplier cannot register products -> 403 FORBIDDEN", async () => {
    const res = await request(app).post("/products").set(auth("tok-supplier")).send(validProduct);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe("FORBIDDEN");
    expect(products.registerProduct).not.toHaveBeenCalled();
  });

  test("non-admin cannot list users -> 403", async () => {
    expect((await request(app).get("/users").set(auth("tok-maker"))).status).toBe(403);
  });

  test("retailer-only and supplier-only endpoints are gated", async () => {
    expect((await request(app).post("/products/VT-2026-000001/sold").set(auth("tok-maker"))).status).toBe(403);
    expect((await request(app).post("/transfers/VT-2026-000001/confirm").set(auth("tok-maker"))).status).toBe(403);
    expect((await request(app).post("/transfers/VT-2026-000001/initiate").set(auth("tok-admin")).send({ toUid: "x" })).status).toBe(403);
  });

  test("recipients list excludes the caller", async () => {
    const res = await request(app).get("/users/recipients?role=supplier").set(auth("tok-supplier"));
    expect(res.status).toBe(200);
    expect(res.body.recipients).toEqual([]);
  });
});

describe("product validation", () => {
  test("valid product is accepted by a manufacturer", async () => {
    const res = await request(app).post("/products").set(auth("tok-maker")).send(validProduct);
    expect(res.status).toBe(201);
    expect(products.registerProduct).toHaveBeenCalledWith(expect.objectContaining({ uid: "u-maker" }), expect.objectContaining({ countryOfOrigin: "India" }));
  });

  test.each([
    [{ ...validProduct, name: "" }, "name"],
    [{ ...validProduct, category: "Toys" }, "category"],
    [{ ...validProduct, manufactureDate: "10/01/2026" }, "manufactureDate"],
    [{ ...validProduct, manufactureDate: "2026-02-30" }, "manufactureDate"],
    [{ ...validProduct, expiryDate: "2026-01-01" }, "expiryDate"],
    [{ ...validProduct, mrp: -5 }, "mrp"],
    [{ ...validProduct, manufactureDate: "2999-01-01" }, "manufactureDate"],
  ])("rejects invalid input (%#: %s)", async (body, field) => {
    const res = await request(app).post("/products").set(auth("tok-maker")).send(body);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("VALIDATION_ERROR");
    expect(res.body.error.details.map((d) => d.field)).toContain(field);
  });

  test("malformed JSON -> 400 BAD_JSON", async () => {
    const res = await request(app).post("/products").set(auth("tok-maker")).set("content-type", "application/json").send("{bad");
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("BAD_JSON");
  });
});

describe("public endpoints", () => {
  test("POST /verify works without login and returns Unverified for unknown IDs", async () => {
    const res = await request(app).post("/verify").send({ productId: "VT-2026-123456", deviceId: "d1" });
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("Unverified");
    expect(res.body.technical.contractAddress).toBe("0xC");
  });

  test("POST /verify requires a payload or product ID", async () => {
    const res = await request(app).post("/verify").send({ deviceId: "d1" });
    expect(res.status).toBe(400);
  });

  test("GET /health reports chain + firestore", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  test("unknown routes -> JSON 404", async () => {
    const res = await request(app).get("/nope");
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });
});
