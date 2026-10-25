// npm run reset-demo
//   1. Redeploys BlockAuth (Hardhat localhost by default, or sepolia when CHAIN=sepolia)
//   2. Clears Firestore products, scans, audit, counters
//   3. Upserts demo accounts, assigns roles on-chain, funds wallets, seeds products + scans + QR images
const path = require("path");
const { execSync } = require("child_process");
const config = require("../config");
const store = require("../services/firestore");
const blockchain = require("../services/blockchain");
const { seed } = require("./seed");

const ROOT = path.join(__dirname, "..", "..");
const CLEARED = ["products", "scans", "audit", "counters"];
const E2E_EMAIL = /^e2e-\d+@veritrace\.demo$/;

async function main() {
  const started = Date.now();
  console.log(`\n=== VeriTrace reset-demo (chain: ${config.chain.key}, firebase: ${config.firebase.usingEmulator ? "emulator" : "project"}) ===\n`);

  const status = await blockchain.getStatus();
  if (!status.connected) {
    throw new Error(`Cannot reach the chain at ${config.chain.rpcUrl}. Start it first: npx hardhat node --hostname 0.0.0.0`);
  }
  await store.ping().catch((err) => {
    throw new Error(`Cannot reach Firestore: ${err.message}`);
  });

  console.log("1/3 Deploying contract…");
  const network = config.chain.key === "sepolia" ? "sepolia" : "localhost";
  execSync(`npx hardhat run scripts/deploy.js --network ${network}`, { cwd: ROOT, stdio: "inherit", env: { ...process.env, NODE_ENV: "development" } });

  console.log(`\n2/3 Clearing Firestore: ${CLEARED.join(", ")}…`);
  for (const name of CLEARED) await store.clearCollection(name);
  // Leftover accounts from interrupted `npm run e2e` runs
  for (const u of (await store.listUsers()).filter((x) => E2E_EMAIL.test(x.email || ""))) {
    await store.auth().deleteUser(u.uid).catch(() => {});
    await store.db().collection("users").doc(u.uid).delete();
    console.log(`  removed e2e account ${u.email}`);
  }

  console.log("\n3/3 Seeding…");
  const result = await seed();

  const info = blockchain.getContractInfo();
  console.log(`\nDone in ${((Date.now() - started) / 1000).toFixed(1)} s. Contract ${info.address} on ${info.network}.`);
  console.log("Demo password for all accounts: Demo@1234");
  console.log("\nProducts:");
  for (const p of result.products) console.log(`  ${p.productId}  ${p.expected.padEnd(10)} ${p.input.name}`);
  console.log("\nQR images: demo/qr/  (see demo/qr/README.md)\n");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(`\nreset-demo failed: ${err.message}\n`);
    process.exit(1);
  });
