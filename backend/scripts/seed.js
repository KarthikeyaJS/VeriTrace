// Seeds demo accounts (Firebase Auth + Firestore + on-chain roles + funding), demo products covering
// every verification outcome, prior scans, and demo QR PNGs. Normally run via `npm run reset-demo`.
//   node scripts/seed.js   (seeds on top of the current contract without clearing anything)
const store = require("../services/firestore");
const accounts = require("../services/accounts");
const products = require("../services/products");
const custody = require("../services/custody");
const blockchain = require("../services/blockchain");
const wallets = require("../services/wallets");
const { generateDemoQrs } = require("./generate-demo-qr");
const { DEMO_PASSWORD, DEMO_ACCOUNTS, DEMO_PRODUCTS } = require("./demoData");

// Demo-friendly thresholds: seeded handoffs happen seconds apart, so the fast-handoff rule is set very low.
const DEMO_SETTINGS = { scanFlagThreshold: 10, deviceFlagThreshold: 5, minHandoffGapSeconds: 1 };

async function upsertAuthUser({ email, displayName }) {
  const authClient = store.auth();
  try {
    const existing = await authClient.getUserByEmail(email);
    await authClient.updateUser(existing.uid, { password: DEMO_PASSWORD, displayName, disabled: false });
    return existing.uid;
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;
    const created = await authClient.createUser({ email, password: DEMO_PASSWORD, displayName });
    return created.uid;
  }
}

async function seedAccounts(log) {
  const users = {};
  for (const acct of DEMO_ACCOUNTS) {
    const uid = await upsertAuthUser(acct);
    const profile = await accounts.provisionProfile(uid, acct, null);
    users[acct.key] = { ...profile, uid };
    log(`  ✓ ${acct.email.padEnd(28)} ${acct.role.padEnd(13)} ${profile.walletAddress}`);
  }
  return users;
}

/** Existing non-demo users keep their accounts; re-assert their roles on the (possibly fresh) contract. */
async function resyncOtherUsers(log) {
  const demoEmails = new Set(DEMO_ACCOUNTS.map((a) => a.email));
  const others = (await store.listUsers()).filter((u) => !demoEmails.has(u.email) && u.walletAddress);
  for (const u of others) {
    await accounts.syncChainRole(u, null);
    if (u.active !== false) await wallets.ensureFunded(u.walletAddress);
  }
  if (others.length) log(`  ✓ re-synced on-chain roles for ${others.length} other account(s)`);
}

async function runPath(product, path, users) {
  for (const step of path) {
    if (step.startsWith("->")) {
      const holder = await blockchain.getProduct(product.productId);
      const actor = Object.values(users).find((u) => u.walletAddress.toLowerCase() === holder.currentHolder.toLowerCase());
      await custody.initiate(actor, product.productId, users[step.slice(2)].uid);
    } else if (step === "sold") {
      const holder = await blockchain.getProduct(product.productId);
      const actor = Object.values(users).find((u) => u.walletAddress.toLowerCase() === holder.currentHolder.toLowerCase());
      await custody.sell(actor, product.productId);
    } else {
      await custody.confirm(users[step], product.productId);
    }
  }
}

async function addPriorScans(productId, { count, devices }) {
  const now = Date.now();
  for (let i = 0; i < count; i++) {
    await store.addScan({
      productId,
      at: new Date(now - (count - i) * 3 * 3600 * 1000).toISOString(),
      deviceId: `seed-device-${(i % devices) + 1}`,
      status: "Genuine",
      reasons: ["SEEDED"],
      flags: [],
    });
  }
}

async function seed({ log = console.log } = {}) {
  log("Seeding verification settings…");
  await store.setVerificationSettings(DEMO_SETTINGS);

  log("Seeding demo accounts…");
  const users = await seedAccounts(log);
  await resyncOtherUsers(log);

  log("Seeding demo products…");
  const created = [];
  for (const def of DEMO_PRODUCTS) {
    const { product, qrPayload } = await products.registerProduct(users[def.maker], def.input);
    await runPath(product, def.path, users);
    if (def.tamper) await store.updateProduct(product.productId, def.tamper);
    if (def.priorScans) await addPriorScans(product.productId, def.priorScans);
    created.push({ ...def, productId: product.productId, qrPayload, hash: product.hash });
    log(`  ✓ ${product.productId}  ${def.input.name.padEnd(38)} → expected ${def.expected}`);
  }

  const files = await generateDemoQrs(created);
  log(`Wrote ${files.length} QR images to demo/qr/`);
  return { users, products: created, files };
}

if (require.main === module) {
  seed()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(`Seed failed: ${err.message}`);
      process.exit(1);
    });
}

module.exports = { seed, DEMO_SETTINGS };
