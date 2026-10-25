// Business-account provisioning: Firebase Auth user + Firestore profile + custodial wallet +
// on-chain role (signed by the acting admin's own wallet) + gas funding.
const store = require("./firestore");
const blockchain = require("./blockchain");
const wallets = require("./wallets");
const { AppError, badRequest, conflict, notFound } = require("../utils/errors");

const ACCOUNT_ROLES = Object.freeze(["admin", "manufacturer", "supplier", "retailer"]);

function publicProfile(u) {
  if (!u) return null;
  return {
    uid: u.uid || u.id,
    email: u.email,
    displayName: u.displayName,
    role: u.role,
    active: u.active !== false,
    walletAddress: u.walletAddress || null,
    createdAt: u.createdAt || null,
    updatedAt: u.updatedAt || null,
    ...(u.chainRole !== undefined ? { chainRole: u.chainRole } : {}),
  };
}

const adminWalletFor = (actor) => (actor && Number.isInteger(actor.walletIndex) ? wallets.walletForUser(actor) : wallets.deployer());

/** Brings the on-chain role in line with the profile (inactive => none). Returns the tx hash or null. */
async function syncChainRole(profile, actor) {
  if (profile.walletIndex === 0) return null; // deployer is Admin from the constructor and cannot change its own role
  const desired = profile.active === false ? "none" : profile.role;
  const current = await blockchain.getRole(profile.walletAddress);
  if (current === desired) return null;
  const { txHash } = await blockchain.setUserRole(adminWalletFor(actor), profile.walletAddress, desired);
  return txHash;
}

/**
 * Writes the Firestore profile for an existing Auth user, assigns the role on-chain and funds the wallet.
 * Used by POST /users and by the seed (which pins wallet indices).
 */
async function provisionProfile(uid, { email, displayName, role, walletIndex }, actor) {
  if (!ACCOUNT_ROLES.includes(role)) throw badRequest("INVALID_ROLE", `Role must be one of: ${ACCOUNT_ROLES.join(", ")}.`);
  const index = Number.isInteger(walletIndex) ? walletIndex : await store.allocateWalletIndex();
  const now = store.nowIso();
  const existing = await store.getUser(uid);
  const profile = {
    email,
    displayName,
    role,
    active: true,
    walletIndex: index,
    walletAddress: wallets.addressAt(index),
    createdAt: existing?.createdAt || now,
    updatedAt: now,
    createdBy: existing?.createdBy || actor?.uid || "system",
  };
  const roleTxHash = await syncChainRole(profile, actor);
  if (index !== 0) await wallets.ensureFunded(profile.walletAddress);
  return store.setUser(uid, { ...profile, ...(roleTxHash ? { roleTxHash } : {}) });
}

async function createAccount({ email, password, displayName, role }, actor) {
  const authClient = store.auth();
  let record;
  try {
    record = await authClient.createUser({ email, password, displayName });
  } catch (err) {
    if (err.code === "auth/email-already-exists") throw conflict("EMAIL_EXISTS", `An account with ${email} already exists.`);
    if (err.code === "auth/invalid-password") throw badRequest("WEAK_PASSWORD", "Password must be at least 6 characters.");
    if (err.code === "auth/invalid-email") throw badRequest("INVALID_EMAIL", "Email address is invalid.");
    throw err;
  }
  try {
    const profile = await provisionProfile(record.uid, { email, displayName, role }, actor);
    await store.addAudit({ action: "CREATE_USER", actorUid: actor.uid, targetUid: record.uid, role, txHash: profile.roleTxHash || null });
    return profile;
  } catch (err) {
    await authClient.deleteUser(record.uid).catch(() => {});
    throw err;
  }
}

async function updateAccount(uid, changes, actor) {
  const target = await store.getUser(uid);
  if (!target) throw notFound("USER_NOT_FOUND", "User not found.");
  const roleChanging = changes.role !== undefined && changes.role !== target.role;
  if (uid === actor.uid && (roleChanging || changes.active === false)) {
    throw badRequest("CANNOT_MODIFY_SELF", "You cannot change your own role or deactivate your own account.");
  }

  const next = {
    ...target,
    role: changes.role ?? target.role,
    active: changes.active ?? target.active !== false,
    displayName: changes.displayName ?? target.displayName,
  };
  if (!Number.isInteger(next.walletIndex)) {
    next.walletIndex = await store.allocateWalletIndex();
    next.walletAddress = wallets.addressAt(next.walletIndex);
  }

  const roleTxHash = await syncChainRole(next, actor);
  if (next.active && next.walletIndex !== 0) await wallets.ensureFunded(next.walletAddress);
  await store.auth().updateUser(uid, { disabled: !next.active, displayName: next.displayName });

  const update = {
    role: next.role,
    active: next.active,
    displayName: next.displayName,
    walletIndex: next.walletIndex,
    walletAddress: next.walletAddress,
    updatedAt: store.nowIso(),
    ...(roleTxHash ? { roleTxHash } : {}),
  };
  const saved = await store.setUser(uid, update);
  await store.addAudit({ action: "UPDATE_USER", actorUid: actor.uid, targetUid: uid, changes, txHash: roleTxHash });
  return { ...saved, roleTxHash };
}

async function withChainRoles(users) {
  return Promise.all(
    users.map(async (u) => {
      let chainRole = null;
      try {
        chainRole = u.walletAddress ? await blockchain.getRole(u.walletAddress) : null;
      } catch (err) {
        if (!(err instanceof AppError)) throw err;
      }
      return { ...u, chainRole };
    })
  );
}

module.exports = { ACCOUNT_ROLES, publicProfile, provisionProfile, createAccount, updateAccount, syncChainRole, withChainRoles };
