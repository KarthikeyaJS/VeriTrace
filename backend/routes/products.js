// Product registration (manufacturer), listings, detail/journey, QR payload, mark sold (retailer).
const express = require("express");
const { z } = require("zod");
const authenticate = require("../middleware/authenticate");
const authorize = require("../middleware/authorize");
const asyncHandler = require("../utils/asyncHandler");
const products = require("../services/products");
const custody = require("../services/custody");
const { ID_PATTERN } = require("../services/qr");

const router = express.Router();

const isValidDate = (s) => {
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
};
const dateString = z
  .string()
  .trim()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Use the format YYYY-MM-DD")
  .refine(isValidDate, "Not a real calendar date");
const optionalText = (max) =>
  z
    .string()
    .trim()
    .max(max)
    .nullish()
    .transform((v) => (v ? v : null));

const registerSchema = z
  .object({
    productId: z
      .string()
      .trim()
      .toUpperCase()
      .regex(ID_PATTERN, "Product ID must be 3-40 characters: letters, digits, - or _")
      .optional(),
    name: z.string().trim().min(1, "Name is required").max(120),
    brand: z.string().trim().min(1, "Brand is required").max(80),
    category: z.enum(products.CATEGORIES, { errorMap: () => ({ message: `Category must be one of: ${products.CATEGORIES.join(", ")}` }) }),
    batchNumber: z.string().trim().min(1, "Batch number is required").max(60),
    serialNumber: optionalText(80),
    manufactureDate: dateString,
    expiryDate: dateString.nullish().transform((v) => v || null),
    mrp: z.coerce.number().nonnegative("MRP cannot be negative").max(100_000_000).nullish().transform((v) => (v === undefined ? null : v)),
    countryOfOrigin: z.string().trim().min(1).max(60).default("India"),
    description: optionalText(1000),
  })
  .refine((v) => !v.expiryDate || v.expiryDate > v.manufactureDate, {
    path: ["expiryDate"],
    message: "Expiry date must be after the manufacture date",
  })
  .refine((v) => v.manufactureDate <= new Date(Date.now() + 86400000).toISOString().slice(0, 10), {
    path: ["manufactureDate"],
    message: "Manufacture date cannot be in the future",
  });

const idParam = (req) => {
  const id = String(req.params.id || "").trim().toUpperCase();
  return z.string().regex(ID_PATTERN, "Invalid product ID").parse(id);
};

router.use(authenticate);

router.post(
  "/",
  authorize("manufacturer"),
  asyncHandler(async (req, res) => {
    const input = registerSchema.parse(req.body);
    const result = await products.registerProduct(req.user, input);
    res.status(201).json(result);
  })
);

router.get(
  "/mine",
  authorize("manufacturer"),
  asyncHandler(async (req, res) => {
    res.json({ products: await products.listForManufacturer(req.user.uid) });
  })
);

router.get(
  "/",
  authorize("admin"),
  asyncHandler(async (req, res) => {
    res.json({ products: await products.listAll() });
  })
);

router.get(
  "/:id",
  authorize(),
  asyncHandler(async (req, res) => {
    res.json(await products.getDetail(idParam(req)));
  })
);

router.get(
  "/:id/qr-payload",
  authorize(),
  asyncHandler(async (req, res) => {
    res.json(await products.getQrPayload(idParam(req)));
  })
);

router.post(
  "/:id/sold",
  authorize("retailer"),
  asyncHandler(async (req, res) => {
    res.json(await custody.sell(req.user, idParam(req)));
  })
);

module.exports = router;
module.exports.registerSchema = registerSchema;
