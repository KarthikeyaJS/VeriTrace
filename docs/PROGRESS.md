# Progress log

## Phase 0 — Scaffold ✅
- **Built:** folder structure, `.gitignore` (node_modules, `.env*`, service-account keys, `google-services.json`, build outputs, generated contract/ML data), root `README.md`, docs, `firebase.json` + `firestore.rules` + `.firebaserc` (emulators), project `.npmrc` files.
- **Verified:** clean installs succeed.
- **Known issues:** VS Code's environment sets `NODE_ENV=production`, so npm skipped devDependencies. Fixed with `include=dev` in `.npmrc`.

## Phase 1 — Contract ✅
- **Built:** `contracts/BlockAuth.sol` (roles, stages, two-step custody, cancel, sold, history, 17 custom errors, 6 events), `test/BlockAuth.test.js`, `scripts/deploy.js` (→ `backend/config/contract.json`).
- **Verified:** `npx hardhat test` → **25 passing**. Covers role assignment by admin only; register by manufacturer only; duplicate ID; M→S1→S2→R→Sold; wrong recipient; non-holder; M→R rejected; wrong-role recipient; after-Sold actions; cancel; revoked roles; history order/contents; one event per handoff.

## Phase 2 — Backend core ✅
- **Built:** config, Firebase Admin/Firestore layer, blockchain service (hot-reloading `contract.json`, custom-error → readable message mapping, per-wallet tx queue), HD custodial wallets with auto-funding, hashing, `authenticate`/`authorize`/`errorHandler`, `/me`, `/users`.
- **Verified:** jest; live `/health` against Hardhat + Firebase emulators.
- **Known issues fixed:** ethers v6's 250 ms request cache handed out stale nonces → `cacheTimeout: -1`.

## Phase 3 — Products + verification ✅
- **Built:** product IDs via Firestore transaction (`VT-YYYY-NNNNNN`), SHA-256 fingerprint, QR payload, `/products/*`, public `/verify` with per-IP rate limit, all verification rules in `services/verification.js`, scan recording.
- **Verified:** jest unit tests for every rule with pure inputs; all demo QR codes return the expected status on the live stack.

## Phase 4 — Transfers + journey + reports ✅
- **Built:** `/transfers/{incoming,custody,:id/initiate,:id/confirm,:id/cancel}`, `/products/:id/sold`, journey with `txHash` + `blockNumber` from contract logs, `/reports/{summary,scans}`, audit entries.
- **Verified:** e2e (below).

## Phase 5 — Flutter app ✅ (physical-phone run pending — see below)
- **Built:** `mobile/` (package `com.veritrace.app`, label "VeriTrace", generated shield+check launcher icon), Material 3 light theme, go_router with role guards, Dio client with Firebase token interceptor, runtime-overridable backend URL (login → tune icon), anonymous device ID. Screens: home, scanner (torch, invalid-QR message, camera-permission state), verification result (badge, reasons, product, journey, technical details), login, manufacturer dashboard + register form + product detail (QR, Share PNG, A4 label sheet, transfer/cancel), supplier/retailer dashboards (incoming/custody/stock, confirm, transfer, mark sold with confirmation), admin (users with on-chain role, create, change role, (de)activate; all products; reports), journey screen. Loading/empty/error states everywhere; buttons disabled during requests; contract rejections shown as "Rejected by the smart contract: …".
- **Verified:**
  - `flutter analyze` → **No issues found**; `flutter test` → **23 passed** (auth bloc ×7, verify bloc ×6, QR parsing, route guard, model parsing, register-form validation, status badge).
  - `flutter build apk --debug` succeeds. The merged manifest contains only INTERNET, CAMERA, ACCESS_NETWORK_STATE + Firebase/AndroidX internals.
  - **Driven on an Android emulator (API 33)** against the live stack (Firebase Auth emulator): home → manual ID → Genuine result with journey and tx hashes; manufacturer login → dashboard → product detail with QR → **on-chain rejection M→Retailer shown in the app** → valid transfer → Share PNG (share sheet with rendered label) → Print labels (A4 preview); supplier login → Incoming → Confirm → Custody → **supplier→manufacturer rejected on-chain**; admin users list with on-chain roles; reports. Screenshots in `docs/screenshots/`.
- **Fixed during UI testing:** login didn't navigate (pushed route + go_router redirect); lists didn't refresh after returning from detail; label sheet cell aspect ratio.
- **Pending (needs the developer's phone):** camera QR scanning on a physical device. Command:
  `cd mobile; flutter run --dart-define=API_BASE_URL=http://192.168.1.12:3000` (+ `--dart-define=FIREBASE_AUTH_EMULATOR=192.168.1.12:9099` while using the emulators).

## Phase 6 — Seed / reset / e2e ✅
- **Built:** `scripts/demoData.js`, `seed.js`, `reset-demo.js` (redeploy, clear products/scans/audit/counters, purge stale e2e accounts, upsert 7 demo accounts with pinned wallets, on-chain roles, funding, 8 products covering every case, 14 prior scans, demo-friendly thresholds), `generate-demo-qr.js` (10 PNGs + README + index.json, including forged and unknown), `e2e.js`.
- **Verified from a fresh Hardhat node:** `npm run reset-demo` (≈13 s) → all 10 demo QR codes give their expected result → `npm run e2e` → **42/42 passed** (both with the ML service on and off).

## Phase 7 — Hardening & docs ✅
- **Built:** readable contract-error messages, per-request log line, `/health` diagnostics (chain/contract/Firestore/ML), desync message (`CONTRACT_NOT_FOUND` → "run reset-demo"), no-GPS defence (`tools:node="remove"` for location permissions), Windows firewall + LAN IP instructions, Sepolia network + `deploy:sepolia` + `CHAIN=sepolia`, all docs, Postman collection (32 requests) + environment, Mermaid diagrams.
- **Verified:** no-GPS grep of `AndroidManifest.xml` (source + merged), `pubspec.yaml`, `lib/` → nothing. Sepolia path implemented but **not exercised** (no RPC URL / funded key provided).

## Phase 8 — ML ✅
- **Built:** `ml/` FastAPI service, synthetic data generator (normal + 5 anomaly kinds), IsolationForest training with hold-out evaluation, saved model + metadata, pytest suite, README. Backend client with 1.5 s timeout; ML can only produce a `warning` (Flagged).
- **Verified:** pytest **7 passed**; hold-out false-positive rate ≈1.0%, recall ≈92% (laundering 63%); seeded Genuine products stay Genuine with ML on; the over-scanned product gets `ML_ANOMALY`; with ML stopped, verify still answers in ~130 ms; jest covers timeout/HTTP error/connection refused.

---

## Acceptance checklist

| # | Item | Result |
|---|---|---|
| 1 | Authorized manufacturer registers a product; duplicate IDs rejected (contract + API) | ✅ Hardhat tests + e2e #4, #9 (API 409), #10 (on-chain `ProductAlreadyExists`) |
| 2 | Hash and QR generated; QR shareable as PNG and printable as label sheet | ✅ e2e #4–5; Share PNG + A4 sheet verified on emulator |
| 3 | QR scans on the developer's physical phone | ⏳ **Needs your phone** (camera). Manual-ID path verified on emulator |
| 4 | Valid → Genuine; unknown → Unverified; forged → Suspect; tampered DB → Suspect; pre-retail / expired / over-scanned → Flagged | ✅ jest rule tests + demo QR check + e2e #12, #15, #24, #28–34 |
| 5 | Suppliers and retailer transfer/confirm; retailer marks sold | ✅ e2e #14–25; supplier confirm on emulator |
| 6 | Journey shows ordered events with timestamps and tx hashes | ✅ e2e #27 (10 events, ordered, tx refs); emulator screenshot |
| 7 | Invalid transitions / unauthorized writes rejected on-chain and in the API, clear in the app | ✅ Hardhat tests; e2e #6–8, #13, #16, #20–22, #26; both rejections shown in the app |
| 8 | Login + role dashboards; admin creates users, changes roles (on-chain) | ✅ e2e #35–41; emulator (manufacturer, supplier, admin) |
| 9 | Consumers verify without login | ✅ e2e (unauthenticated `/verify`); emulator |
| 10 | `reset-demo` and `e2e` pass from a fresh Hardhat node | ✅ node restarted → reset-demo → 46/46 (with ML) |
| 11 | Hardhat, jest, `flutter analyze`, Flutter tests pass | ✅ 25 / 83 / 0 issues / 26 |
| 12 | No location permission or GPS code | ✅ source + merged manifest, pubspec, lib |
| 13 | All docs in section 10 exist and are accurate | ✅ PROGRESS, DECISIONS, SETUP, API, ARCHITECTURE, DEMO_SCRIPT, LIMITATIONS, Postman, README |
| 14 | ML works and degrades gracefully when stopped | ✅ pytest 7; e2e with ML on/off; verify with ML stopped |

## Real Firebase project (`veritrace-198d5`) ✅ — 2026-10-24
- `backend/serviceAccountKey.json` and `mobile/android/app/google-services.json` in place (git-ignored); `backend/.env` switched from the emulators to the project; `.firebaserc` default = `veritrace-198d5` (alias `demo` = emulators).
- **Verified:** `/health` → Firestore `mode: firebase`; `npm run reset-demo` created the 7 demo accounts in Firebase Auth and seeded Firestore (≈29 s); `npm run e2e` → **42/42 passed** (REST sign-in with the project API key, token verification, account create/disable/delete); all 10 demo QR codes return their expected result; debug APK builds with the Google Services plugin applied.
- Firestore rules released with `npm --prefix backend run deploy:rules` (Admin SDK). `firebase deploy` with the service account is blocked by a missing `serviceusage` IAM role — not needed.

## ML integration completed ✅ (2026-10-25)
- **Built:**
  - `ML_NORMAL` passed-check reason when the model scores a journey as normal.
  - Scans store `mlScored` and `ml { anomalyScore, isAnomaly, modelVersion }`.
  - `technical.ml` now includes the threshold and the features sent; it is `null` when ML was unavailable.
  - `/health` and `/reports/summary` expose the model version, threshold, synthetic metrics, scans scored and scans flagged by ML; `/reports/scans?flag=ML_ANOMALY` lists the scans ML flagged.
  - App: an **Anomaly detection (ML)** card in Admin → Reports (with a drill-down list), ML scores on report rows, and an "ML anomaly check" line in Technical details (normal / UNUSUAL / not run).
  - e2e has 4 new ML checks (SKIP, not FAIL, when the service is off).
  - `start-all.ps1 -Only <parts>` restarts individual windows.
- **Verified:** jest **83**, Flutter **26** + `flutter analyze` clean, ML pytest **7**. `npm run e2e` → **46/46** with ML on, **43/46 + 3 skipped** with ML stopped. All 10 demo QR codes are unchanged; only the cloned-QR product (`000007`) gets `ML_ANOMALY`.

## Open items
- **Physical phone test** (checklist #3): `cd mobile; flutter run --dart-define=API_BASE_URL=http://192.168.1.12:3000`.
- **Sepolia**: untested without an RPC URL and funded key.
