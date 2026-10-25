# Build Prompt — VeriTrace (client project "BlockAuth")

You are building a complete, working prototype from an **empty folder** on **Windows** (use PowerShell-compatible commands). I (the developer) am present to answer questions and provide credentials, but you should **keep going autonomously** and only stop when genuinely blocked or when you need something only I can provide. **Speed matters**: prefer simple, working solutions over polish or abstraction. Do not over-engineer.

The app's brand name is **VeriTrace** (tagline: "Scan. Verify. Trust."). The client project is called BlockAuth; use "VeriTrace" in the UI and app name, "blockauth" is fine for the repo folder.

---

## 0. Ground rules

- **Do NOT run any git commands that commit, push, or create branches.** I handle version control. You may create a `.gitignore`.
- **Run tests and commands yourself** (Hardhat tests, backend tests, `flutter analyze`, `flutter test`) and fix failures before moving on.
- **Document as you go** (see section 10). Update `docs/PROGRESS.md` at the end of every phase.
- **No GPS, ever.** The app must not request location permission or use any location package. Verify `AndroidManifest.xml` at the end.
- **Secrets never go in the mobile app or on-chain.** Private keys/mnemonics, Firebase service account JSON → backend `.env` / backend folder only, all git-ignored. No personal data on-chain.
- **Android only.** No iOS config work.
- Environment already installed and working: Flutter, Node, Android Studio, Git. I have run Flutter on my physical Android phone from this machine before.
- If something in this prompt is contradictory or impossible, pick the most sensible option, note it in `docs/DECISIONS.md`, and continue.

### Things only I can provide — ask for them ONCE at the start, then continue working without waiting
At the very beginning, send me one message listing exactly what you need from Firebase, with step-by-step instructions for creating it in the Firebase console:
1. Firebase project created, **Email/Password** sign-in enabled, **Firestore** created (production mode, region asia-south1).
2. Android app registered with package name `com.veritrace.app` → I'll place `google-services.json` at `mobile/android/app/google-services.json` (or you run `flutterfire configure` and I complete login).
3. Service account key JSON → I'll place it at `backend/serviceAccountKey.json`.
4. Web API key (for the backend e2e script to sign in via the Firebase Auth REST API).

Then **immediately proceed with Phase 1** (contract work needs no Firebase). Pick up the Firebase items when I report them.

---

## 1. Architecture

```
Flutter app (Android, Bloc)  ──HTTP/JSON──>  Node.js + Express backend  ──ethers v6──>  Solidity contract (Hardhat local node)
                                                  │
                                                  ├── Firebase Admin (verify ID tokens, manage users)
                                                  ├── Firestore (users, product metadata, scans, audit)
                                                  └── Python ML service (optional, Phase 8)
```

- The app **never talks to the blockchain directly** (no web3dart). All chain interaction goes through the backend.
- Consumers verify **without logging in** and without a wallet.
- **Custodial wallets**: every business user (admin, manufacturer, supplier, retailer) gets an Ethereum wallet derived from a backend-held HD mnemonic (`ethers.HDNodeWallet.fromPhrase(MNEMONIC, undefined, "m/44'/60'/0'/0/<index>")`). The backend signs each user's transactions with **that user's own wallet**, so the contract's `msg.sender` role checks are real. Store `walletIndex` and `walletAddress` in the user's Firestore doc. Index 0 = deployer/admin.
  - Local: use Hardhat's default mnemonic (`test test test ... junk`); the first 20 accounts are pre-funded. When a user is created with a wallet that has a low balance, the deployer auto-funds it (e.g. 1 ETH local).
  - Sepolia (optional): separate `MNEMONIC` in `.env`; deployer funds new wallets with a small amount (e.g. 0.01 ETH) on role assignment.

### Chain approach
- **Primary: local Hardhat network** (`npx hardhat node --hostname 0.0.0.0`). This is what I demo on.
- **Optional:** `npm run deploy:sepolia` script + `CHAIN=sepolia` backend switch, configured via `.env` (`SEPOLIA_RPC_URL`). Implement in Phase 7; don't block on testing it unless I provide an RPC URL and funded key.
- `scripts/deploy.js` writes the deployed address + ABI to `backend/config/contract.json`.
- Hardhat state resets on restart, so provide `npm run reset-demo` (Phase 6) that redeploys, clears the relevant Firestore collections, and reseeds everything.

---

## 2. Tech stack

| Layer | Choice |
|---|---|
| Mobile | Flutter (latest stable), Dart, **flutter_bloc** + equatable, go_router, dio, mobile_scanner, qr_flutter, share_plus, pdf + printing (label sheets), firebase_core, firebase_auth, intl, path_provider |
| Contract | Solidity ^0.8.24, Hardhat (JS), hardhat-toolbox, chai tests |
| Backend | Node 20+, Express, ethers v6, firebase-admin, dotenv, cors, zod (validation), jest + supertest |
| DB | Firestore (via backend only) |
| Hashing | SHA-256 (Node `crypto`) |
| ML (Phase 8) | Python 3.11, FastAPI, scikit-learn IsolationForest, uvicorn |

---

## 3. Roles & permissions

| Role | Can do |
|---|---|
| Admin | Create/deactivate business accounts, assign/change roles (syncs on-chain via `setUserRole`), view all products, view scan reports (counts by status, recent Flagged/Suspect scans) |
| Manufacturer | Register products, view/share/print QR, initiate transfer to a supplier |
| Supplier | Confirm receipt of incoming products, transfer to another supplier or to a retailer |
| Retailer | Confirm receipt, mark product as SOLD |
| Consumer (no login) | Scan QR or enter ID manually, see verification result + journey |

- There is **no public sign-up**. Admin creates business accounts (backend uses `admin.auth().createUser`). Role is stored in Firestore `users/{uid}.role` **and** mirrored on-chain.
- Enforce roles in **backend middleware** (`authorize(...roles)`) **and in the contract** for every write. Hiding UI buttons is not authorization.
- Deactivated users: backend rejects their requests; contract role set to `None`.

---

## 4. Product data

Fields entered by the manufacturer:
- `name` (required), `brand` (required), `category` (required, dropdown: Electronics, Pharmaceuticals, Apparel, Cosmetics, Food & Beverage, Automotive Parts, Luxury Goods, Other), `batchNumber` (required), `serialNumber` (optional), `manufactureDate` (required), `expiryDate` (optional, must be after mfg date), `mrp` (optional, INR), `countryOfOrigin` (required, default India), `description` (optional).

System fields: `productId` (auto), `manufacturerId` (uid), `manufacturerName`, `hash`, `registerTxHash`, `blockNumber`, `createdAt`.

**Product ID**: auto-generated `VT-<YYYY>-<6-digit zero-padded counter>` (e.g. `VT-2026-000042`) using a Firestore transaction on `counters/products`.

**Fingerprint**: canonical JSON of the **immutable identity fields only** — `productId, name, brand, category, batchNumber, serialNumber, manufactureDate, expiryDate, countryOfOrigin, manufacturerId` — keys sorted alphabetically, no whitespace, missing optionals as `null`, dates as `YYYY-MM-DD`. SHA-256 → hex → stored on-chain as `bytes32`. Put canonicalization in **one** function (`backend/services/hashing.js`) with unit tests (same input → same hash regardless of key order).

**QR payload**: `veritrace://verify?id=<productId>&h=<hashHex>`. The scanner must also accept a bare product ID. QR never contains secrets.

---

## 5. Smart contract — `contracts/BlockAuth.sol`

Roles: `enum Role { None, Admin, Manufacturer, Supplier, Retailer }`
Stages: `enum Stage { None, Manufactured, AtSupplier, AtRetailer, Sold }`
Event types: `enum EventType { Registered, TransferInitiated, Received, TransferCancelled, Sold }`

Product struct: `productHash (bytes32)`, `manufacturer`, `registeredAt`, `currentHolder`, `pendingRecipient`, `stage`, `exists`. Key products by `bytes32 key = keccak256(bytes(productId))`; also store the string ID for reads.

Handoff struct: `from`, `to`, `timestamp`, `eventType`, `stageAfter`. Stored per product in an array (ordered history).

Functions:
- `setUserRole(address user, Role role)` — Admin only. Constructor makes deployer Admin.
- `registerProduct(string productId, bytes32 hash)` — Manufacturer only; reject duplicates; sets holder = manufacturer, stage = Manufactured; appends `Registered` handoff.
- `getProduct(string productId)` → full struct (+ exists flag; don't revert on unknown, return exists=false).
- `initiateTransfer(string productId, address to)` — caller must be `currentHolder`, no pending transfer, and the transition must be valid:
  - Manufactured → Supplier (to must have role Supplier)
  - AtSupplier → Supplier (another supplier; supports multi-hop distribution) or → Retailer
  - Anything else reverts (e.g. Manufacturer → Retailer directly, transfers after Sold, transfer to self).
- `confirmReceipt(string productId)` — only `pendingRecipient`; moves holder and stage (AtSupplier / AtRetailer); appends `Received`.
- `cancelTransfer(string productId)` — only current holder while pending.
- `markSold(string productId)` — only current holder with Retailer role at stage AtRetailer; stage = Sold; terminal.
- `getHandoffHistory(string productId)` → array of handoffs.
- Events for every state change: `ProductRegistered`, `RoleChanged`, `TransferInitiated`, `TransferReceived`, `TransferCancelled`, `ProductSold`.
- Custom errors instead of revert strings.

(Mapping to the client plan: `recordHandoff()` is implemented as initiateTransfer + confirmReceipt + markSold, so receipts are explicitly confirmed. Note this in DECISIONS.md.)

**Hardhat tests (must all pass)**: role assignment by admin only; register by manufacturer only; duplicate ID rejected; full happy path M→S→S→R→Sold; wrong recipient cannot confirm; non-holder cannot transfer; M→R direct rejected; transfer to wrong role rejected; actions after Sold rejected; cancel works; history order and contents correct; events emitted.

---

## 6. Backend — `backend/`

Structure (preserve these names):
```
backend/
  server.js
  config/ (contract.json, index.js reading .env)
  routes/ auth.js, users.js, products.js, transfers.js, verify.js, reports.js
  middleware/ authenticate.js (Firebase ID token), authorize.js (roles), errorHandler.js
  services/ blockchain.js, wallets.js, hashing.js, verification.js, firestore.js, ml.js
  scripts/ seed.js, reset-demo.js, e2e.js
  tests/ (jest)
  .env.example
```

- Listen on `0.0.0.0:3000`. CORS open (prototype). Consistent JSON errors `{ error: { code, message } }`. Map contract custom errors to human-readable messages.
- Transaction references: for history, use contract events (`queryFilter`) to attach `txHash` and `blockNumber` to each handoff.
- Endpoints (document all in `docs/API.md` and the Postman collection):
  - `GET /health` (chain connected, contract address, Firestore OK)
  - `GET /me` — current user profile + role
  - Admin: `POST /users`, `GET /users?role=`, `PATCH /users/:uid` (role, active, name)
  - `GET /users/recipients?role=supplier|retailer` — for transfer pickers (any business role)
  - Manufacturer: `POST /products`, `GET /products/mine`
  - `GET /products/:id` (auth, business roles), `GET /products/:id/qr-payload`
  - Holder queues: `GET /transfers/incoming`, `GET /transfers/custody`
  - `POST /transfers/:id/initiate { toUid }`, `POST /transfers/:id/confirm`, `POST /transfers/:id/cancel`, `POST /products/:id/sold`
  - Public: `POST /verify { payload | productId, deviceId }` — no auth, simple in-memory rate limit per IP
  - Admin: `GET /reports/summary`, `GET /reports/scans?status=`
- Firestore collections: `users`, `products`, `scans` (`productId, at, deviceId, status, reasons`), `counters`, `audit` (who did what, txHash). Write `firestore.rules` that deny all direct client access except a user reading their own `users/{uid}` doc. The app goes through the backend for everything else.

### Verification rules — `services/verification.js` (single source of truth)
Return `{ status, reasons[], product, journey, technical }`. Evaluate in this order:
- **Unverified**: malformed payload; product ID not on chain.
- **Suspect** (critical): QR hash ≠ on-chain hash (forged/copied-and-altered QR); hash recomputed from Firestore metadata ≠ on-chain hash (tampered DB record); history internally inconsistent.
- **Flagged** (warning): consumer scan while stage is Manufactured or AtSupplier (not yet at retail); transfer pending; product expired; total scans > `SCAN_FLAG_THRESHOLD` (default 10) or distinct devices > `DEVICE_FLAG_THRESHOLD` (default 5) — possible cloned QR; any handoff gap < `MIN_HANDOFF_GAP_SECONDS` (default 30, configurable, set very low in seed so the demo doesn't trip it); Firestore metadata missing while chain record exists; ML anomaly (Phase 8).
- **Genuine**: none of the above.
- A missing record is Unverified, never "counterfeit". Record every scan in `scans`.
- `technical` section: contract address, chain ID, product hash, register tx hash, block numbers.
- Unit-test every rule with pure inputs (no chain needed).

---

## 7. Mobile app — `mobile/`

- Package: `com.veritrace.app`, app label "VeriTrace", simple generated launcher icon (shield + check, neutral colors) via flutter_launcher_icons.
- Clean neutral Material 3 theme, light mode only. Status colors: Genuine green, Flagged amber, Suspect red, Unverified grey. Each status also has an icon and text (not color alone).
- Backend URL via `--dart-define=API_BASE_URL=http://<laptop-LAN-IP>:3000`, with a hidden settings field on the login screen to override it at runtime (persisted). Enable `android:usesCleartextTraffic="true"`. Camera permission only. **No location permission.**
- Feature-first Bloc structure: `lib/core/` (api client with auth interceptor, theme, router, errors), `lib/features/<feature>/{data,bloc,view}`. Features: auth, home, scan, verify, products, transfers, admin, reports.
- Anonymous `deviceId` (UUID stored locally) sent with scans.

Screens:
1. **Home (public)**: big "Scan a product" button, "Enter product ID" option, "Business login" link.
2. **Scanner**: mobile_scanner with torch toggle, handles both payload formats, invalid QR message.
3. **Verification result**: large status badge + reasons list, product details, journey timeline (stage, party name and role, timestamp), and a collapsed **"Technical details"** expander (tx hashes, block numbers, contract address, product hash).
4. **Login**: email/password (Firebase Auth) → role-based routing.
5. **Manufacturer dashboard**: register product form (validation, date pickers, category dropdown); my products list with stage chips; product detail with QR, **Share PNG** (share_plus), **Print label sheet** (PDF grid of QR labels with product ID and name, via printing), and "Transfer to supplier" (recipient picker).
6. **Supplier dashboard**: tabs Incoming (Confirm receipt) / In custody (transfer to supplier or retailer).
7. **Retailer dashboard**: Incoming (Confirm receipt) / In stock (Mark as sold, with confirmation dialog).
8. **Admin dashboard**: users list (filter by role), create user, change role, activate/deactivate; all products; reports (counts per status, recent Flagged/Suspect scans).
9. **Product journey** screen reachable from any product detail.

All screens need loading, empty, and error states; disable buttons during in-flight requests; show contract rejection messages clearly. Business users can also use the scanner.

Run `flutter analyze` (zero errors) and write bloc tests for the auth and verify blocs.

---

## 8. Seed data & demo — `npm run reset-demo`

Redeploys the contract, clears Firestore `products`, `scans`, `audit`, and `counters`, upserts demo accounts (creates them in Firebase Auth if missing), assigns roles on-chain, funds wallets, then creates:

Accounts (password `Demo@1234` for all, documented in README):
- `admin@veritrace.demo`
- `maker@veritrace.demo` (Manufacturer: "Aurora Electronics")
- `maker2@veritrace.demo` (Manufacturer: "Nila Pharma")
- `supplier1@veritrace.demo` ("Southern Distributors"), `supplier2@veritrace.demo` ("Metro Wholesale")
- `retailer1@veritrace.demo` ("CityMart Bengaluru"), `retailer2@veritrace.demo` ("QuickCare Pharmacy")

Products covering every case:
- One fully **Sold** (M → S1 → S2 → R → Sold) → Genuine
- One **AtRetailer** → Genuine
- One **AtSupplier** → Flagged when a consumer scans (not yet at retail)
- One with a **pending transfer**
- One whose Firestore metadata is **tampered** after registration → Suspect
- One **expired** pharma product → Flagged
- One with **many prior scans** → Flagged (cloned QR)

Also generate `demo/qr/` PNGs: a QR for each seeded product, a **forged QR** (valid ID, wrong hash → Suspect), and an **unknown ID** QR (→ Unverified). Write `docs/DEMO_SCRIPT.md`: a 5–7 minute walkthrough using these, including showing an on-chain rejection (e.g. supplier tries to send to a manufacturer).

`npm run e2e`: against the running stack, signs in seeded users via the Firebase Auth REST API, runs register → transfers → sold → verify, plus failure cases (unauthorized register, duplicate, invalid transition, forged hash, unknown ID), and prints a pass/fail table.

---

## 9. Phases (execute in order, don't stop between phases unless blocked)

0. **Scaffold**: folder structure, `.gitignore` (node_modules, .env, serviceAccountKey.json, build outputs, google-services.json), docs skeleton, root README stub. Send the Firebase checklist message.
1. **Contract**: write, test (all passing), deploy script.
2. **Backend core**: config, blockchain + wallets services, hashing (with tests), Firebase admin, auth middleware, users routes. *(Needs Firebase; if not ready, build and unit-test everything that doesn't need it, then wire it up.)*
3. **Products + verification**: registration, QR payload, verify endpoint, verification rules + tests.
4. **Transfers + journey**: transfer endpoints, history with tx refs, reports.
5. **Flutter app**: all screens wired to the backend. Then **ask me to run it on my phone** (give me the exact command with my LAN IP from `ipconfig`) and tell me what to test; fix what I report.
6. **Seed / reset / e2e**: scripts + demo QR images; run e2e until green.
7. **Hardening & docs**: error messages, empty states, no-GPS check (grep the manifest and pubspec), Windows firewall note for port 3000, optional Sepolia deploy script, finalize all docs, Postman collection, architecture diagram.
8. **ML (optional, last)**: `ml/` FastAPI service with an IsolationForest trained on **synthetic** journeys (generated by a script; normal journeys + injected anomalies). Features: number of handoffs, min/mean handoff gap, total time since registration, scan count, distinct devices, scans per hour, stage at scan. `POST /score` → `{ anomalyScore, isAnomaly }`. Backend calls it with a 1.5 s timeout; if it is down or slow, verification continues without it. **ML can only raise a result to Flagged, never to Suspect.** Include the training script, saved model, README section, and a test.

---

## 10. Documentation to maintain (`docs/`)

- `PROGRESS.md` — per phase: what was built, how it was verified, known issues. Update at the end of every phase.
- `DECISIONS.md` — every design choice and deviation from the client plan, with a one-line reason.
- `SETUP.md` — exact Windows setup from zero: install deps, Firebase setup, `.env` values, terminal layout (T1 `npx hardhat node --hostname 0.0.0.0`, T2 deploy + `npm run reset-demo`, T3 backend, T4 `flutter run --dart-define=...`), finding the LAN IP, firewall rule, troubleshooting (phone can't reach backend, chain reset desync, camera permission).
- `API.md` — every endpoint with auth, request, response, errors.
- `ARCHITECTURE.md` — Mermaid diagrams: system architecture, product state machine, verification decision flow, registration and transfer sequence diagrams.
- `DEMO_SCRIPT.md` — see section 8.
- `LIMITATIONS.md` — local chain is not production evidence; QR codes can be copied (mitigated by scan-count flags, not prevented); custodial keys are a prototype shortcut; a valid chain record can't prove the physical item is genuine; ML is trained on synthetic data.
- `postman/VeriTrace.postman_collection.json` with an environment file.
- Root `README.md` — overview, features, screenshots placeholder, quick start (5 commands), demo accounts, links to docs.

---

## 11. Acceptance checklist (verify every item before declaring done; report results in PROGRESS.md)

- [ ] Authorized manufacturer registers a product; duplicate IDs are rejected (contract + API)
- [ ] Hash and QR are generated; QR can be shared as PNG and printed as a label sheet
- [ ] QR scans on my physical phone
- [ ] Valid product → Genuine; unknown → Unverified; forged hash → Suspect; tampered DB → Suspect; pre-retail scan / expired / over-scanned → Flagged
- [ ] Supplier(s) and retailer can transfer/confirm; retailer can mark sold
- [ ] Journey shows ordered events with timestamps and tx hashes
- [ ] Invalid transitions and unauthorized writes are rejected on-chain and in the API, with clear messages in the app
- [ ] Login and role-based dashboards work; admin can create users and change roles (reflected on-chain)
- [ ] Consumers verify without login
- [ ] `npm run reset-demo` and `npm run e2e` both pass from a fresh Hardhat node
- [ ] Hardhat tests, backend jest tests, `flutter analyze`, and Flutter tests pass
- [ ] No location permission or GPS code anywhere
- [ ] All docs in section 10 exist and are accurate
- [ ] ML service works and degrades gracefully when stopped

Start with Phase 0 now.
