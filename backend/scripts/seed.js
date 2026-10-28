// Seeds demo accounts (Firebase Auth + Firestore + on-chain roles + funding), demo products covering
// every verification outcome plus an everyday catalogue, prior scans, a little realistic verification
// activity for the admin reports, and demo QR PNGs. Normally run via `npm run reset-demo`.
//   node scripts/seed.js   (seeds on top of the current contract without clearing anything)
const store = require("../services/firestore");
const accounts = require("../services/accounts");
const products = require("../services/products");
const custody = require("../services/custody");
const blockchain = require("../services/blockchain");
const wallets = require("../services/wallets");
const verification = require("../services/verification");
const ml = require("../services/ml");
const views = require("../services/productView");
const { buildPayload } = require("../services/qr");
const { generateDemoQrs } = require("./generate-demo-qr");
const { DEMO_PASSWORD, DEMO_ACCOUNTS, DEMO_PRODUCTS, DEMO_CATALOG, FORGED, UNKNOWN, DEMO_ACTIVITY } = require("./demoData");

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

/** History of earlier scans (spread over the last hours). Statuses follow the clone rules as the count grows. */
async function addPriorScans(productId, { count, devices }) {
  const now = Date.now();
  for (let i = 0; i < count; i++) {
    const scanNo = i + 1;
    const devicesSoFar = Math.min(scanNo, devices);
    const flags = [];
    if (scanNo > DEMO_SETTINGS.scanFlagThreshold) flags.push("EXCESSIVE_SCANS");
    if (devicesSoFar > DEMO_SETTINGS.deviceFlagThreshold) flags.push("MANY_DEVICES");
    await store.addScan({
      productId,
      at: new Date(now - (count - i) * 20 * 60 * 1000).toISOString(),
      deviceId: `seed-device-${(i % devices) + 1}`,
      status: flags.length ? "Flagged" : "Genuine",
      reasons: ["SEEDED_HISTORY", ...flags],
      flags,
      mlScored: false,
      ml: null,
    });
  }
}

/** Runs real verifications (same code path as POST /verify) so the admin Reports start populated. */
async function recordDemoActivity(created, log) {
  const deps = { chain: blockchain, store, ml, views, contractInfo: () => blockchain.getContractInfo() };
  const bySlug = new Map(created.map((p) => [p.slug, p]));
  const results = {};
  for (const { slug, device } of DEMO_ACTIVITY) {
    let payload;
    if (slug === FORGED.slug) payload = buildPayload(bySlug.get(FORGED.basedOn).productId, FORGED.fakeHash);
    else if (slug === UNKNOWN.slug) payload = UNKNOWN.productId;
    else payload = bySlug.get(slug).qrPayload;
    const r = await verification.verify({ payload, deviceId: device }, deps);
    results[r.status] = (results[r.status] || 0) + 1;
  }
  log(`  ✓ ${DEMO_ACTIVITY.length} demo verifications recorded (${Object.entries(results).map(([k, v]) => `${v} ${k}`).join(", ")})`);
}

async function seed({ log = console.log } = {}) {
  log("Seeding verification settings…");
  await store.setVerificationSettings(DEMO_SETTINGS);

  log("Seeding demo accounts…");
  const users = await seedAccounts(log);
  await resyncOtherUsers(log);

  const created = [];
  const groups = [
    ["Seeding demo scenario products (one per verification outcome)…", "scenario", DEMO_PRODUCTS],
    ["Seeding everyday catalogue products…", "catalog", DEMO_CATALOG],
  ];
  for (const [title, group, defs] of groups) {
    log(title);
    for (const def of defs) {
      const { product, qrPayload } = await products.registerProduct(users[def.maker], def.input);
      await runPath(product, def.path, users);
      if (def.tamper) await store.updateProduct(product.productId, def.tamper);
      if (def.priorScans) await addPriorScans(product.productId, def.priorScans);
      created.push({ ...def, group, productId: product.productId, qrPayload, hash: product.hash });
      log(`  ✓ ${product.productId}  ${def.input.name.padEnd(40)} → expected ${def.expected}`);
    }
  }

  log("Recording demo verification activity…");
  await recordDemoActivity(created, log);

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
