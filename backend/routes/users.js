// Business accounts. There is no public sign-up: admins create accounts here.
const express = require("express");
const { z } = require("zod");
const authenticate = require("../middleware/authenticate");
const authorize = require("../middleware/authorize");
const asyncHandler = require("../utils/asyncHandler");
const store = require("../services/firestore");
const accounts = require("../services/accounts");

const router = express.Router();
const roleEnum = z.enum(["admin", "manufacturer", "supplier", "retailer"]);

const createSchema = z.object({
  email: z.string().trim().toLowerCase().email("Enter a valid email address"),
  password: z.string().min(8, "Password must be at least 8 characters").max(128),
  displayName: z.string().trim().min(2, "Name must be at least 2 characters").max(80),
  role: roleEnum,
});

const updateSchema = z
  .object({
    role: roleEnum.optional(),
    active: z.boolean().optional(),
    displayName: z.string().trim().min(2).max(80).optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: "Nothing to update" });

router.use(authenticate);

// Recipient picker for transfers (any business role).
router.get(
  "/recipients",
  authorize(),
  asyncHandler(async (req, res) => {
    const role = z.enum(["supplier", "retailer", "manufacturer"]).parse(req.query.role);
    const users = await store.listUsers({ role });
    const recipients = users
      .filter((u) => u.active !== false && u.uid !== req.user.uid && u.walletAddress)
      .map((u) => ({ uid: u.uid, displayName: u.displayName, role: u.role, walletAddress: u.walletAddress }));
    res.json({ recipients });
  })
);

router.get(
  "/",
  authorize("admin"),
  asyncHandler(async (req, res) => {
    const role = req.query.role ? roleEnum.parse(req.query.role) : undefined;
    const users = await accounts.withChainRoles(await store.listUsers({ role }));
    res.json({ users: users.map(accounts.publicProfile) });
  })
);

router.post(
  "/",
  authorize("admin"),
  asyncHandler(async (req, res) => {
    const input = createSchema.parse(req.body);
    const profile = await accounts.createAccount(input, req.user);
    res.status(201).json({ user: accounts.publicProfile(profile), roleTxHash: profile.roleTxHash || null });
  })
);

router.patch(
  "/:uid",
  authorize("admin"),
  asyncHandler(async (req, res) => {
    const changes = updateSchema.parse(req.body);
    const saved = await accounts.updateAccount(req.params.uid, changes, req.user);
    const [withRole] = await accounts.withChainRoles([saved]);
    res.json({ user: accounts.publicProfile(withRole), roleTxHash: saved.roleTxHash || null });
  })
);

module.exports = router;
