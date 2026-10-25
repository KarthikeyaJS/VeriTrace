// Role gate: authorize('manufacturer'), authorize('supplier', 'retailer'), ...
// Must run after authenticate. The contract enforces the same rules on-chain.
const { AppError } = require("../utils/errors");

const BUSINESS_ROLES = Object.freeze(["admin", "manufacturer", "supplier", "retailer"]);

function authorize(...roles) {
  const allowed = roles.length ? roles : BUSINESS_ROLES;
  return (req, res, next) => {
    if (!req.user) return next(new AppError(401, "UNAUTHENTICATED", "Please sign in to continue."));
    if (!allowed.includes(req.user.role)) {
      return next(new AppError(403, "FORBIDDEN", `Your role (${req.user.role || "none"}) cannot do this. Required: ${allowed.join(" or ")}.`));
    }
    next();
  };
}

module.exports = authorize;
module.exports.BUSINESS_ROLES = BUSINESS_ROLES;
