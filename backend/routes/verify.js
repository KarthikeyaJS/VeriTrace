// Public verification endpoint — no login, no wallet. Simple in-memory per-IP rate limit.
const express = require("express");
const { z } = require("zod");
const asyncHandler = require("../utils/asyncHandler");
const config = require("../config");
const { AppError } = require("../utils/errors");
const verification = require("../services/verification");
const blockchain = require("../services/blockchain");
const store = require("../services/firestore");
const ml = require("../services/ml");
const views = require("../services/productView");

const router = express.Router();

const schema = z
  .object({
    payload: z.string().trim().max(500).optional(),
    productId: z.string().trim().max(60).optional(),
    deviceId: z.string().trim().max(100).optional(),
  })
  .refine((v) => v.payload || v.productId, { message: "Provide a QR payload or a product ID" });

const WINDOW_MS = 60_000;
const hits = new Map();
function rateLimit(req, res, next) {
  const now = Date.now();
  const key = req.ip || "unknown";
  const entry = hits.get(key);
  if (!entry || now - entry.start > WINDOW_MS) {
    hits.set(key, { start: now, count: 1 });
  } else if (++entry.count > config.rateLimit.verifyPerMinute) {
    res.set("Retry-After", String(Math.ceil((entry.start + WINDOW_MS - now) / 1000)));
    return next(new AppError(429, "RATE_LIMITED", "Too many verification requests. Please wait a minute and try again."));
  }
  if (hits.size > 10_000) hits.clear();
  next();
}

const deps = {
  chain: blockchain,
  store,
  ml,
  views,
  contractInfo: () => blockchain.getContractInfo(),
};

router.post(
  "/",
  rateLimit,
  asyncHandler(async (req, res) => {
    const input = schema.parse(req.body || {});
    res.json(await verification.verify(input, deps));
  })
);

module.exports = router;
module.exports.deps = deps;
