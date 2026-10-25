// npm run deploy:rules — publishes ../firestore.rules to the configured Firebase project using the
// service account (Firebase Admin SDK Security Rules API; no `firebase login` needed).
const fs = require("fs");
const path = require("path");
const config = require("../config");
const store = require("../services/firestore");

async function main() {
  if (config.firebase.usingEmulator) throw new Error("FIRESTORE_EMULATOR_HOST is set; the emulator reads firestore.rules directly.");
  store.init();
  const admin = require("firebase-admin");
  const source = fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
  const ruleset = await admin.securityRules().releaseFirestoreRulesetFromSource(source);
  console.log(`Released Firestore rules to ${config.firebase.projectId}: ${ruleset.name} (${ruleset.createTime})`);
}

main().catch((err) => {
  console.error(`deploy-rules failed: ${err.message}`);
  process.exit(1);
});
