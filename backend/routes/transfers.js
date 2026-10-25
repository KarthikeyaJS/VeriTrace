// Custody queues and transfer actions. The contract decides whether a transition is valid.
const express = require("express");
const { z } = require("zod");
const authenticate = require("../middleware/authenticate");
const authorize = require("../middleware/authorize");
const asyncHandler = require("../utils/asyncHandler");
const blockchain = require("../services/blockchain");
const products = require("../services/products");
const custody = require("../services/custody");
const { ID_PATTERN } = require("../services/qr");

const router = express.Router();
const idParam = (req) => z.string().regex(ID_PATTERN, "Invalid product ID").parse(String(req.params.id || "").trim().toUpperCase());
const initiateSchema = z.object({ toUid: z.string().trim().min(1, "Choose a recipient") });

router.use(authenticate);

router.get(
  "/incoming",
  authorize("manufacturer", "supplier", "retailer"),
  asyncHandler(async (req, res) => {
    const chainProducts = await blockchain.getIncoming(req.user.walletAddress);
    res.json({ products: await products.viewsForChainProducts(chainProducts) });
  })
);

router.get(
  "/custody",
  authorize("manufacturer", "supplier", "retailer"),
  asyncHandler(async (req, res) => {
    const chainProducts = await blockchain.getCustody(req.user.walletAddress);
    res.json({ products: await products.viewsForChainProducts(chainProducts) });
  })
);

router.post(
  "/:id/initiate",
  authorize("manufacturer", "supplier"),
  asyncHandler(async (req, res) => {
    const { toUid } = initiateSchema.parse(req.body || {});
    res.json(await custody.initiate(req.user, idParam(req), toUid));
  })
);

router.post(
  "/:id/confirm",
  authorize("supplier", "retailer"),
  asyncHandler(async (req, res) => {
    res.json(await custody.confirm(req.user, idParam(req)));
  })
);

router.post(
  "/:id/cancel",
  authorize("manufacturer", "supplier"),
  asyncHandler(async (req, res) => {
    res.json(await custody.cancel(req.user, idParam(req)));
  })
);

module.exports = router;
