// Demo accounts and products used by seed.js, generate-demo-qr.js, e2e.js and docs/DEMO_SCRIPT.md.
const DEMO_PASSWORD = "Demo@1234";

// walletIndex is pinned so demo wallets are stable across resets (0 = contract deployer).
const DEMO_ACCOUNTS = [
  { key: "admin", email: "admin@veritrace.demo", displayName: "VeriTrace Admin", role: "admin", walletIndex: 0 },
  { key: "maker", email: "maker@veritrace.demo", displayName: "Aurora Electronics", role: "manufacturer", walletIndex: 1 },
  { key: "maker2", email: "maker2@veritrace.demo", displayName: "Nila Pharma", role: "manufacturer", walletIndex: 2 },
  { key: "supplier1", email: "supplier1@veritrace.demo", displayName: "Southern Distributors", role: "supplier", walletIndex: 3 },
  { key: "supplier2", email: "supplier2@veritrace.demo", displayName: "Metro Wholesale", role: "supplier", walletIndex: 4 },
  { key: "retailer1", email: "retailer1@veritrace.demo", displayName: "CityMart Bengaluru", role: "retailer", walletIndex: 5 },
  { key: "retailer2", email: "retailer2@veritrace.demo", displayName: "QuickCare Pharmacy", role: "retailer", walletIndex: 6 },
];

const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
const daysAhead = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

// `path` lists custody steps after registration: "->x" = initiate to x, "x" = x confirms, "sold" = retailer marks sold.
const DEMO_PRODUCTS = [
  {
    slug: "sold-genuine",
    expected: "Genuine",
    maker: "maker",
    story: "Full journey M → S1 → S2 → R → Sold",
    input: {
      name: "Aurora X1 Smartphone",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "AX1-2026-07",
      serialNumber: "AX1-000781",
      manufactureDate: daysAgo(60),
      mrp: 24999,
      description: "6.5-inch AMOLED, 8 GB RAM, 256 GB storage.",
    },
    path: ["->supplier1", "supplier1", "->supplier2", "supplier2", "->retailer1", "retailer1", "sold"],
  },
  {
    slug: "at-retailer-genuine",
    expected: "Genuine",
    maker: "maker",
    story: "On the shelf at CityMart Bengaluru",
    input: {
      name: "Aurora SoundPods Pro",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "ASP-2026-03",
      serialNumber: "ASP-004512",
      manufactureDate: daysAgo(45),
      mrp: 7999,
      description: "Active noise cancelling earbuds.",
    },
    path: ["->supplier1", "supplier1", "->retailer1", "retailer1"],
  },
  {
    slug: "at-supplier-flagged",
    expected: "Flagged",
    maker: "maker",
    story: "Still at Southern Distributors — a consumer should not have it yet",
    input: {
      name: "Aurora 65W GaN Charger",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "AGC-2026-11",
      manufactureDate: daysAgo(20),
      mrp: 2499,
    },
    path: ["->supplier1", "supplier1"],
  },
  {
    slug: "pending-transfer-flagged",
    expected: "Flagged",
    maker: "maker",
    story: "Dispatched by Metro Wholesale to CityMart, not yet confirmed",
    input: {
      name: "Aurora PowerBank 20000",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "APB-2026-02",
      manufactureDate: daysAgo(30),
      mrp: 1999,
    },
    path: ["->supplier2", "supplier2", "->retailer1"],
  },
  {
    slug: "tampered-suspect",
    expected: "Suspect",
    maker: "maker2",
    story: "Database record altered after registration (expiry extended)",
    tamper: { expiryDate: daysAhead(3 * 365), batchNumber: "NP-2026-99" },
    input: {
      name: "Nila Paracetamol 500 mg (10 tablets)",
      brand: "Nila",
      category: "Pharmaceuticals",
      batchNumber: "NP-2026-04",
      manufactureDate: daysAgo(90),
      expiryDate: daysAhead(365),
      mrp: 35,
      description: "Analgesic and antipyretic.",
    },
    path: ["->supplier1", "supplier1", "->retailer2", "retailer2"],
  },
  {
    slug: "expired-flagged",
    expected: "Flagged",
    maker: "maker2",
    story: "Expired pharmaceutical still on sale",
    input: {
      name: "Nila Cough Syrup 100 ml",
      brand: "Nila",
      category: "Pharmaceuticals",
      batchNumber: "NCS-2024-09",
      manufactureDate: daysAgo(730),
      expiryDate: daysAgo(20),
      mrp: 120,
    },
    path: ["->supplier2", "supplier2", "->retailer2", "retailer2"],
  },
  {
    slug: "over-scanned-flagged",
    expected: "Flagged",
    maker: "maker",
    story: "Scanned 14 times from 8 devices — QR probably copied",
    priorScans: { count: 14, devices: 8 },
    input: {
      name: "Aurora Buds Lite",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "ABL-2026-05",
      serialNumber: "ABL-010203",
      manufactureDate: daysAgo(40),
      mrp: 1499,
    },
    path: ["->supplier1", "supplier1", "->retailer1", "retailer1"],
  },
  {
    slug: "manufactured-ready",
    expected: "Flagged",
    maker: "maker",
    story: "Just manufactured — use it to demo a live transfer",
    input: {
      name: "Aurora Tab 11",
      brand: "Aurora",
      category: "Electronics",
      batchNumber: "AT11-2026-01",
      serialNumber: "AT11-000042",
      manufactureDate: daysAgo(2),
      mrp: 18999,
    },
    path: [],
  },
];

const FORGED = { slug: "forged-suspect", expected: "Suspect", basedOn: "at-retailer-genuine", fakeHash: "deadbeef".repeat(8) };
const UNKNOWN = { slug: "unknown-unverified", expected: "Unverified", productId: "VT-2026-999999" };

module.exports = { DEMO_PASSWORD, DEMO_ACCOUNTS, DEMO_PRODUCTS, FORGED, UNKNOWN };
