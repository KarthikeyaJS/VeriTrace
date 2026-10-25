// Admin reports: scan counts per status, recent Flagged/Suspect scans, product/user totals.
const express = require("express");
const { z } = require("zod");
const authenticate = require("../middleware/authenticate");
const authorize = require("../middleware/authorize");
const asyncHandler = require("../utils/asyncHandler");
const store = require("../services/firestore");
const blockchain = require("../services/blockchain");

const router = express.Router();
const STATUSES = ["Genuine", "Flagged", "Suspect", "Unverified"];

router.use(authenticate, authorize("admin"));

async function withProductNames(scans) {
  const ids = [...new Set(scans.map((s) => s.productId).filter(Boolean))];
  const docs = await store.getProductsByIds(ids);
  return scans.map((s) => ({
    id: s.id,
    productId: s.productId,
    productName: s.productId && docs.get(s.productId) ? docs.get(s.productId).name : null,
    at: s.at,
    deviceId: s.deviceId,
    status: s.status,
    reasons: s.reasons || [],
    flags: s.flags || [],
  }));
}

router.get(
  "/summary",
  asyncHandler(async (req, res) => {
    const [scanCounts, recent, productDocs, users, settings] = await Promise.all([
      store.countScansByStatus(STATUSES),
      store.listScans({ statuses: ["Flagged", "Suspect"], limit: 10 }),
      store.listProducts(),
      store.listUsers(),
      store.getVerificationSettings(),
    ]);

    const byStage = { Manufactured: 0, AtSupplier: 0, AtRetailer: 0, Sold: 0, NotOnChain: 0 };
    const chainProducts = await Promise.all(productDocs.map((p) => blockchain.getProduct(p.productId)));
    for (const p of chainProducts) byStage[p.exists ? p.stage : "NotOnChain"] += 1;

    const usersByRole = {};
    for (const u of users) if (u.active !== false) usersByRole[u.role] = (usersByRole[u.role] || 0) + 1;

    res.json({
      scans: { total: STATUSES.reduce((n, s) => n + scanCounts[s], 0), byStatus: scanCounts },
      products: { total: productDocs.length, byStage },
      users: { total: users.length, active: users.filter((u) => u.active !== false).length, byRole: usersByRole },
      recentAlerts: await withProductNames(recent),
      settings,
    });
  })
);

router.get(
  "/scans",
  asyncHandler(async (req, res) => {
    const status = z.enum([...STATUSES, "all"]).default("all").parse(req.query.status || "all");
    const limit = z.coerce.number().int().min(1).max(200).default(50).parse(req.query.limit || 50);
    const scans = await store.listScans({ statuses: status === "all" ? null : [status], limit });
    res.json({ scans: await withProductNames(scans) });
  })
);

module.exports = router;
