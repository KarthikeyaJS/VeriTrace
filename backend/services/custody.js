// Custody actions. Transition rules are enforced by the contract; the backend only resolves
// the recipient and signs with the acting user's own wallet so msg.sender checks are real.
const store = require("./firestore");
const blockchain = require("./blockchain");
const wallets = require("./wallets");
const { notFound } = require("../utils/errors");

async function audit(user, action, productId, tx, extra = {}) {
  await store.addAudit({ action, actorUid: user.uid, actorRole: user.role, productId, txHash: tx.txHash, blockNumber: tx.blockNumber, ...extra });
}

async function initiate(user, productId, toUid) {
  const recipient = await store.getUser(toUid);
  if (!recipient || recipient.active === false || !recipient.walletAddress) {
    throw notFound("RECIPIENT_NOT_FOUND", "The selected recipient does not exist or is inactive.");
  }
  const tx = await blockchain.initiateTransfer(wallets.walletForUser(user), productId, recipient.walletAddress);
  await audit(user, "TRANSFER_INITIATED", productId, tx, { toUid });
  return { ...tx, productId, to: { uid: toUid, displayName: recipient.displayName, role: recipient.role } };
}

async function confirm(user, productId) {
  const tx = await blockchain.confirmReceipt(wallets.walletForUser(user), productId);
  await audit(user, "TRANSFER_CONFIRMED", productId, tx);
  return { ...tx, productId };
}

async function cancel(user, productId) {
  const tx = await blockchain.cancelTransfer(wallets.walletForUser(user), productId);
  await audit(user, "TRANSFER_CANCELLED", productId, tx);
  return { ...tx, productId };
}

async function sell(user, productId) {
  const tx = await blockchain.markSold(wallets.walletForUser(user), productId);
  await audit(user, "PRODUCT_SOLD", productId, tx);
  return { ...tx, productId };
}

module.exports = { initiate, confirm, cancel, sell };
