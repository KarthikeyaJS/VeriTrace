// npm run e2e — end-to-end check against the RUNNING stack (Hardhat node + backend + Firebase).
// Signs in seeded users via the Firebase Auth REST API, then exercises register → transfers → sold →
// verify plus failure cases, and prints a pass/fail table. Self-contained: it creates its own products,
// so it does not change the scan counts of the seeded demo products.
const { ethers } = require("ethers");
const config = require("../config");
const store = require("../services/firestore");
const blockchain = require("../services/blockchain");
const wallets = require("../services/wallets");
const { DEMO_PASSWORD } = require("./demoData");

const BASE = (process.env.E2E_BASE_URL || `http://127.0.0.1:${config.port}`).replace(/\/$/, "");
const results = [];
let current = "setup";

function record(name, pass, detail = "") {
  results.push({ name, pass: Boolean(pass), detail: String(detail).slice(0, 90) });
}

async function check(name, fn) {
  current = name;
  try {
    const detail = await fn();
    record(name, true, detail || "");
  } catch (err) {
    record(name, false, err.message);
  }
}

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

function signInUrl() {
  if (config.firebase.authEmulatorHost) {
    return `http://${config.firebase.authEmulatorHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.firebase.webApiKey || "demo-key"}`;
  }
  if (!config.firebase.webApiKey) throw new Error("FIREBASE_WEB_API_KEY is not set in backend/.env");
  return `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.firebase.webApiKey}`;
}

async function signIn(email, password = DEMO_PASSWORD) {
  const res = await fetch(signInUrl(), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`sign-in ${email}: ${body.error?.message || res.status}`);
  return body.idToken;
}

async function api(method, path, { token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    json = null;
  }
  return { status: res.status, body: json };
}

const expectStatus = (res, status, label) => {
  assert(res.status === status, `${label}: expected HTTP ${status}, got ${res.status} ${JSON.stringify(res.body?.error || res.body).slice(0, 120)}`);
  return res;
};
const chainReason = (res) => res.body?.error?.details?.reason;
const flags = (v) => (v.reasons || []).filter((r) => r.severity === "critical" || r.severity === "warning").map((r) => r.code);

const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
const productInput = (name, extra = {}) => ({
  name,
  brand: "E2E",
  category: "Electronics",
  batchNumber: `E2E-${Date.now()}`,
  manufactureDate: daysAgo(10),
  mrp: 999,
  ...extra,
});

async function expectRevert(promise, errorName) {
  try {
    await promise;
  } catch (err) {
    const decoded = blockchain.decodeRevert(err);
    assert(decoded && decoded.name === errorName, `expected revert ${errorName}, got ${decoded ? decoded.name : err.shortMessage || err.message}`);
    return `reverted with ${errorName}`;
  }
  throw new Error(`expected revert ${errorName}, but the call succeeded`);
}

async function main() {
  console.log(`\nVeriTrace e2e against ${BASE}\n`);
  const t = {};
  const users = {};

  await check("health: chain + firestore up", async () => {
    const res = expectStatus(await api("GET", "/health"), 200, "health");
    assert(res.body.status === "ok", `status ${res.body.status}: ${res.body.chain?.error || res.body.firestore?.error || ""}`);
    return `contract ${res.body.chain.contractAddress}`;
  });

  await check("sign in seeded users (Firebase Auth REST)", async () => {
    for (const key of ["admin", "maker", "maker2", "supplier1", "supplier2", "retailer1", "retailer2"]) {
      t[key] = await signIn(`${key}@veritrace.demo`);
      users[key] = (await api("GET", "/me", { token: t[key] })).body.user;
    }
    return "7 accounts";
  });

  await check("GET /me returns role + matching on-chain role", async () => {
    assert(users.maker.role === "manufacturer" && users.maker.chainRole === "manufacturer", JSON.stringify(users.maker));
    assert(users.retailer1.chainRole === "retailer", "retailer chainRole");
    return `${users.maker.displayName}: ${users.maker.chainRole}`;
  });

  // ------------------------------------------------------------ registration
  let P; // main product
  await check("manufacturer registers a product", async () => {
    const res = expectStatus(await api("POST", "/products", { token: t.maker, body: productInput("E2E Phone") }), 201, "register");
    P = res.body.product;
    assert(/^VT-\d{4}-\d{6}$/.test(P.productId), `bad id ${P.productId}`);
    assert(res.body.qrPayload.startsWith(`veritrace://verify?id=${P.productId}&h=`), "qr payload");
    P.qrPayload = res.body.qrPayload;
    return `${P.productId} tx ${P.registerTxHash.slice(0, 12)}…`;
  });

  await check("QR payload endpoint matches on-chain hash", async () => {
    const res = expectStatus(await api("GET", `/products/${P.productId}/qr-payload`, { token: t.maker }), 200, "qr");
    assert(res.body.payload === P.qrPayload, "payload mismatch");
    return res.body.hash.slice(0, 18) + "…";
  });

  await check("supplier cannot register (API 403)", async () => {
    const res = expectStatus(await api("POST", "/products", { token: t.supplier1, body: productInput("Nope") }), 403, "supplier register");
    return res.body.error.code;
  });

  await check("unauthenticated register rejected (401)", async () => {
    expectStatus(await api("POST", "/products", { body: productInput("Nope") }), 401, "anon register");
  });

  await check("supplier cannot register (on-chain NotManufacturer)", async () => {
    const supplierWallet = wallets.walletAt(3);
    const contract = new ethers.Contract(blockchain.getContractInfo().address, blockchain.getContractInfo().abi, supplierWallet);
    return expectRevert(contract.registerProduct.staticCall("VT-E2E-ROGUE", ethers.id("rogue")), "NotManufacturer");
  });

  await check("duplicate product ID rejected (API 409)", async () => {
    const res = expectStatus(await api("POST", "/products", { token: t.maker, body: productInput("Dup", { productId: P.productId }) }), 409, "duplicate");
    return res.body.error.message;
  });

  await check("duplicate product ID rejected (on-chain)", async () => {
    const contract = new ethers.Contract(blockchain.getContractInfo().address, blockchain.getContractInfo().abi, wallets.walletAt(2));
    return expectRevert(contract.registerProduct.staticCall(P.productId, ethers.id("other")), "ProductAlreadyExists");
  });

  await check("validation: expiry before manufacture date (400)", async () => {
    const res = expectStatus(
      await api("POST", "/products", { token: t.maker, body: productInput("Bad dates", { expiryDate: daysAgo(30) }) }),
      400,
      "validation"
    );
    return res.body.error.message;
  });

  await check("verify at manufacturer → Flagged (not at retail)", async () => {
    const v = expectStatus(await api("POST", "/verify", { body: { payload: P.qrPayload, deviceId: "e2e-1" } }), 200, "verify").body;
    assert(v.status === "Flagged" && flags(v).includes("NOT_AT_RETAIL"), `${v.status} ${flags(v)}`);
    return flags(v).join(",");
  });

  // --------------------------------------------------------------- transfers
  await check("invalid transition M → retailer rejected on-chain", async () => {
    const res = expectStatus(
      await api("POST", `/transfers/${P.productId}/initiate`, { token: t.maker, body: { toUid: users.retailer1.uid } }),
      422,
      "M->R"
    );
    assert(chainReason(res) === "InvalidTransition", chainReason(res));
    return res.body.error.message;
  });

  await check("manufacturer → supplier1 initiated", async () => {
    const res = expectStatus(await api("POST", `/transfers/${P.productId}/initiate`, { token: t.maker, body: { toUid: users.supplier1.uid } }), 200, "init");
    return `tx ${res.body.txHash.slice(0, 12)}…`;
  });

  await check("verify while pending → Flagged (transfer pending)", async () => {
    const v = (await api("POST", "/verify", { body: { productId: P.productId, deviceId: "e2e-1" } })).body;
    assert(v.status === "Flagged" && flags(v).includes("TRANSFER_PENDING"), `${v.status} ${flags(v)}`);
    return flags(v).join(",");
  });

  await check("wrong recipient cannot confirm (on-chain NotPendingRecipient)", async () => {
    const res = expectStatus(await api("POST", `/transfers/${P.productId}/confirm`, { token: t.supplier2 }), 403, "wrong confirm");
    assert(chainReason(res) === "NotPendingRecipient", chainReason(res));
    return res.body.error.message;
  });

  await check("supplier1 sees it in incoming queue", async () => {
    const res = expectStatus(await api("GET", "/transfers/incoming", { token: t.supplier1 }), 200, "incoming");
    assert(res.body.products.some((p) => p.productId === P.productId), "not in incoming");
    return `${res.body.products.length} incoming`;
  });

  await check("supplier1 confirms receipt", async () => {
    expectStatus(await api("POST", `/transfers/${P.productId}/confirm`, { token: t.supplier1 }), 200, "confirm");
  });

  await check("supplier1 custody includes product at AtSupplier", async () => {
    const res = expectStatus(await api("GET", "/transfers/custody", { token: t.supplier1 }), 200, "custody");
    const item = res.body.products.find((p) => p.productId === P.productId);
    assert(item && item.stage === "AtSupplier", "not in custody");
    return `${res.body.products.length} in custody`;
  });

  await check("invalid transition supplier → manufacturer rejected on-chain", async () => {
    const res = expectStatus(
      await api("POST", `/transfers/${P.productId}/initiate`, { token: t.supplier1, body: { toUid: users.maker2.uid } }),
      422,
      "S->M"
    );
    assert(chainReason(res) === "InvalidTransition", chainReason(res));
    return res.body.error.message;
  });

  await check("non-holder cannot transfer (on-chain NotCurrentHolder)", async () => {
    const res = expectStatus(
      await api("POST", `/transfers/${P.productId}/initiate`, { token: t.supplier2, body: { toUid: users.retailer1.uid } }),
      403,
      "non-holder"
    );
    assert(chainReason(res) === "NotCurrentHolder", chainReason(res));
  });

  await check("cancel transfer works; cancelled transfer cannot be confirmed", async () => {
    expectStatus(await api("POST", `/transfers/${P.productId}/initiate`, { token: t.supplier1, body: { toUid: users.supplier2.uid } }), 200, "init");
    expectStatus(await api("POST", `/transfers/${P.productId}/cancel`, { token: t.supplier1 }), 200, "cancel");
    const res = expectStatus(await api("POST", `/transfers/${P.productId}/confirm`, { token: t.supplier2 }), 409, "confirm after cancel");
    assert(chainReason(res) === "NoPendingTransfer", chainReason(res));
  });

  await check("multi-hop supplier1 → supplier2 → retailer1", async () => {
    expectStatus(await api("POST", `/transfers/${P.productId}/initiate`, { token: t.supplier1, body: { toUid: users.supplier2.uid } }), 200, "s1->s2");
    expectStatus(await api("POST", `/transfers/${P.productId}/confirm`, { token: t.supplier2 }), 200, "s2 confirm");
    expectStatus(await api("POST", `/transfers/${P.productId}/initiate`, { token: t.supplier2, body: { toUid: users.retailer1.uid } }), 200, "s2->r1");
    expectStatus(await api("POST", `/transfers/${P.productId}/confirm`, { token: t.retailer1 }), 200, "r1 confirm");
  });

  await check("verify at retailer (QR) → Genuine", async () => {
    const v = (await api("POST", "/verify", { body: { payload: P.qrPayload, deviceId: "e2e-1" } })).body;
    assert(v.status === "Genuine", `${v.status} ${flags(v)}`);
    return v.reasons.map((r) => r.code).join(",");
  });

  await check("retailer marks sold", async () => {
    const res = expectStatus(await api("POST", `/products/${P.productId}/sold`, { token: t.retailer1 }), 200, "sold");
    return `tx ${res.body.txHash.slice(0, 12)}…`;
  });

  await check("actions after Sold rejected (sold twice / transfer)", async () => {
    const twice = expectStatus(await api("POST", `/products/${P.productId}/sold`, { token: t.retailer1 }), 409, "sold twice");
    assert(chainReason(twice) === "ProductAlreadySold", chainReason(twice));
    const contract = new ethers.Contract(blockchain.getContractInfo().address, blockchain.getContractInfo().abi, wallets.walletAt(5));
    return expectRevert(contract.initiateTransfer.staticCall(P.productId, users.supplier1.walletAddress), "InvalidTransition");
  });

  await check("journey: 10 ordered events with timestamps + tx hashes", async () => {
    const res = expectStatus(await api("GET", `/products/${P.productId}`, { token: t.maker }), 200, "detail");
    const j = res.body.journey;
    const types = j.map((e) => e.eventType).join(">");
    const expected = "Registered>TransferInitiated>Received>TransferInitiated>TransferCancelled>TransferInitiated>Received>TransferInitiated>Received>Sold";
    assert(types === expected, types);
    assert(j.every((e) => /^0x[0-9a-f]{64}$/.test(e.txHash) && e.blockNumber > 0 && e.timestamp), "missing tx refs");
    assert(j.every((e, i) => i === 0 || e.timestamp >= j[i - 1].timestamp), "timestamps out of order");
    assert(j[2].to.name === "Southern Distributors" && j[9].from.name === "CityMart Bengaluru", "party names");
    return `${j.length} events`;
  });

  await check("verify after sale → Genuine", async () => {
    const v = (await api("POST", "/verify", { body: { payload: P.qrPayload, deviceId: "e2e-2" } })).body;
    assert(v.status === "Genuine", `${v.status} ${flags(v)}`);
    assert(v.technical.productHash && v.technical.registerTxHash && v.journey.length === 10, "technical/journey");
  });

  // ------------------------------------------------------- verification cases
  await check("forged QR hash → Suspect", async () => {
    const forged = P.qrPayload.replace(/h=[0-9a-f]+$/, `h=${"ab".repeat(32)}`);
    const v = (await api("POST", "/verify", { body: { payload: forged, deviceId: "e2e-3" } })).body;
    assert(v.status === "Suspect" && flags(v).includes("QR_HASH_MISMATCH"), `${v.status} ${flags(v)}`);
  });

  await check("unknown product ID → Unverified", async () => {
    const v = (await api("POST", "/verify", { body: { productId: "VT-1999-424242", deviceId: "e2e-3" } })).body;
    assert(v.status === "Unverified", v.status);
  });

  await check("malformed QR → Unverified", async () => {
    const v = (await api("POST", "/verify", { body: { payload: "https://evil.example/?x=1", deviceId: "e2e-3" } })).body;
    assert(v.status === "Unverified", v.status);
  });

  await check("tampered Firestore record → Suspect", async () => {
    const res = expectStatus(await api("POST", "/products", { token: t.maker, body: productInput("E2E Tamper") }), 201, "register");
    const id = res.body.product.productId;
    await store.updateProduct(id, { batchNumber: "ALTERED-123" });
    const v = (await api("POST", "/verify", { body: { payload: res.body.qrPayload, deviceId: "e2e-4" } })).body;
    assert(v.status === "Suspect" && flags(v).includes("METADATA_TAMPERED"), `${v.status} ${flags(v)}`);
    return id;
  });

  await check("expired product at retailer → Flagged (expired)", async () => {
    const body = productInput("E2E Expired Syrup", { category: "Pharmaceuticals", manufactureDate: daysAgo(700), expiryDate: daysAgo(5) });
    const res = expectStatus(await api("POST", "/products", { token: t.maker2, body }), 201, "register");
    const id = res.body.product.productId;
    expectStatus(await api("POST", `/transfers/${id}/initiate`, { token: t.maker2, body: { toUid: users.supplier1.uid } }), 200, "init");
    expectStatus(await api("POST", `/transfers/${id}/confirm`, { token: t.supplier1 }), 200, "confirm");
    expectStatus(await api("POST", `/transfers/${id}/initiate`, { token: t.supplier1, body: { toUid: users.retailer2.uid } }), 200, "init");
    expectStatus(await api("POST", `/transfers/${id}/confirm`, { token: t.retailer2 }), 200, "confirm");
    const v = (await api("POST", "/verify", { body: { payload: res.body.qrPayload, deviceId: "e2e-5" } })).body;
    assert(v.status === "Flagged" && flags(v).includes("EXPIRED") && !flags(v).includes("NOT_AT_RETAIL"), `${v.status} ${flags(v)}`);
    return id;
  });

  await check("over-scanned QR → Flagged (possible clone)", async () => {
    let v;
    for (let i = 0; i < 9; i++) v = (await api("POST", "/verify", { body: { payload: P.qrPayload, deviceId: `e2e-clone-${i % 6}` } })).body;
    // P already had a few scans above; 9 more from 6 new devices push it over both thresholds
    assert(v.status === "Flagged" && flags(v).includes("EXCESSIVE_SCANS") && flags(v).includes("MANY_DEVICES"), `${v.status} ${flags(v)}`);
    return `${v.technical.scanCount} scans / ${v.technical.distinctDevices} devices`;
  });

  // -------------------------------------------------------------------- admin
  const email = `e2e-${Date.now()}@veritrace.demo`;
  let newUser;
  await check("admin creates a supplier; role assigned on-chain", async () => {
    const res = expectStatus(
      await api("POST", "/users", { token: t.admin, body: { email, password: "E2e@12345", displayName: "E2E Logistics", role: "supplier" } }),
      201,
      "create user"
    );
    newUser = res.body.user;
    assert(newUser.walletAddress, "no wallet");
    const chainRole = await blockchain.getRole(newUser.walletAddress);
    assert(chainRole === "supplier", `chain role ${chainRole}`);
    return `${newUser.walletAddress.slice(0, 10)}… = ${chainRole}`;
  });

  await check("new user can sign in; wallet was funded", async () => {
    const token = await signIn(email, "E2e@12345");
    const me = expectStatus(await api("GET", "/me", { token }), 200, "me").body.user;
    assert(me.role === "supplier", me.role);
    const bal = await blockchain.getBalance(newUser.walletAddress);
    assert(bal > 0n, "wallet not funded");
    return `${ethers.formatEther(bal)} ETH`;
  });

  await check("admin changes role → reflected on-chain", async () => {
    const res = expectStatus(await api("PATCH", `/users/${newUser.uid}`, { token: t.admin, body: { role: "retailer" } }), 200, "patch");
    assert(res.body.user.chainRole === "retailer", res.body.user.chainRole);
    return `chainRole ${res.body.user.chainRole}`;
  });

  await check("admin deactivates → on-chain role none, login blocked", async () => {
    const res = expectStatus(await api("PATCH", `/users/${newUser.uid}`, { token: t.admin, body: { active: false } }), 200, "deactivate");
    assert(res.body.user.chainRole === "none", res.body.user.chainRole);
    let blocked = false;
    try {
      await signIn(email, "E2e@12345");
    } catch {
      blocked = true;
    }
    assert(blocked, "deactivated user could still sign in");
  });

  await check("cleanup: delete the e2e test account", async () => {
    if (!newUser) return "nothing to clean";
    await store.auth().deleteUser(newUser.uid);
    await store.db().collection("users").doc(newUser.uid).delete();
    return newUser.uid;
  });

  await check("non-admin cannot manage users (403)", async () => {
    expectStatus(await api("GET", "/users", { token: t.maker }), 403, "list users");
    expectStatus(await api("PATCH", `/users/${users.supplier1.uid}`, { token: t.supplier1, body: { role: "admin" } }), 403, "patch");
  });

  await check("admin cannot demote themselves (400)", async () => {
    expectStatus(await api("PATCH", `/users/${users.admin.uid}`, { token: t.admin, body: { role: "retailer" } }), 400, "self");
  });

  await check("reports summary + flagged scans", async () => {
    const s = expectStatus(await api("GET", "/reports/summary", { token: t.admin }), 200, "summary").body;
    assert(s.scans.byStatus.Suspect >= 2 && s.scans.byStatus.Flagged >= 1, JSON.stringify(s.scans.byStatus));
    const list = expectStatus(await api("GET", "/reports/scans?status=Suspect", { token: t.admin }), 200, "scans").body;
    assert(list.scans.every((x) => x.status === "Suspect"), "filter");
    return JSON.stringify(s.scans.byStatus);
  });

  // ------------------------------------------------------------------ report
  const pad = (s, n) => (s.length > n ? `${s.slice(0, n - 1)}…` : s.padEnd(n));
  console.log(`${"#".padStart(3)}  ${pad("Check", 62)} Result  Detail`);
  console.log("-".repeat(140));
  results.forEach((r, i) => console.log(`${String(i + 1).padStart(3)}  ${pad(r.name, 62)} ${r.pass ? "PASS  " : "FAIL  "}  ${r.detail}`));
  const failed = results.filter((r) => !r.pass).length;
  console.log("-".repeat(140));
  console.log(`${results.length - failed}/${results.length} passed${failed ? `, ${failed} FAILED` : ""}\n`);
  return failed;
}

main()
  .then((failed) => process.exit(failed ? 1 : 0))
  .catch((err) => {
    console.error(`e2e aborted during "${current}": ${err.message}`);
    process.exit(1);
  });
