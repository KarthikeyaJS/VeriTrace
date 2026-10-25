// GET /me — current user's profile, role and on-chain role.
const express = require("express");
const authenticate = require("../middleware/authenticate");
const asyncHandler = require("../utils/asyncHandler");
const accounts = require("../services/accounts");
const blockchain = require("../services/blockchain");

const router = express.Router();

router.get(
  "/me",
  authenticate,
  asyncHandler(async (req, res) => {
    let chainRole = null;
    try {
      chainRole = req.user.walletAddress ? await blockchain.getRole(req.user.walletAddress) : null;
    } catch {
      chainRole = null; // chain down: still let the user in; actions will report the error
    }
    res.json({ user: accounts.publicProfile({ ...req.user, chainRole }) });
  })
);

module.exports = router;
