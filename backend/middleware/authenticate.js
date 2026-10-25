// Verifies the Firebase ID token (Authorization: Bearer <token>) and loads the user's
// Firestore profile. Deactivated or profile-less accounts are rejected.
const store = require("../services/firestore");
const { AppError } = require("../utils/errors");

module.exports = async function authenticate(req, res, next) {
  try {
    const match = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || "");
    if (!match) throw new AppError(401, "UNAUTHENTICATED", "Please sign in to continue.");

    const authClient = store.auth();
    let decoded;
    try {
      decoded = await authClient.verifyIdToken(match[1]);
    } catch {
      throw new AppError(401, "INVALID_TOKEN", "Your session has expired. Please sign in again.");
    }

    const profile = await store.getUser(decoded.uid);
    if (!profile) throw new AppError(403, "NO_PROFILE", "This account has no VeriTrace profile. Ask an admin to create it.");
    if (profile.active === false) throw new AppError(403, "ACCOUNT_DISABLED", "This account has been deactivated. Contact your admin.");

    req.user = { ...profile, uid: decoded.uid };
    next();
  } catch (err) {
    next(err);
  }
};
