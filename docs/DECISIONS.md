# Design decisions & deviations

Each entry: the decision, then a one-line reason.

## Architecture & chain
- **`recordHandoff()` from the client plan is split into `initiateTransfer` + `confirmReceipt` (+ `cancelTransfer`, `markSold`).** Receipt is explicitly confirmed by the recipient's own wallet, so a holder can't push custody onto someone unilaterally.
- **Hardhat 2 (2.29) + hardhat-toolbox 5, not Hardhat 3.** The prompt asks for "Hardhat (JS), hardhat-toolbox, chai tests"; Hardhat 3 replaces that stack (ESM, node:test).
- **Root folder is the Hardhat project** (`contracts/`, `scripts/deploy.js`, `test/`); backend, mobile, ml live in sub-folders. Matches the paths named in the prompt.
- **`deploy.js` writes `backend/config/contract.json` (local) or `contract.sepolia.json` (sepolia).** Keeps both deployments side by side; the backend picks by `CHAIN`.
- **The backend hot-reloads `contract.json` when it changes** (mtime check on each call). `reset-demo` can redeploy while the backend is running without a restart.
- **Admins cannot change their own on-chain role (`CannotChangeOwnRole`).** Prevents locking the system out of admin access.
- **Contract checks the caller's role as well as custody** (`CallerRoleMismatch`), and re-checks the recipient's role at `confirmReceipt`. A deactivated user (role `None`) can no longer move goods even while holding them.
- **Transition validity is decided by the contract, not pre-checked by the API.** The demo can then show a real on-chain rejection; the backend maps custom errors to readable messages (`CHAIN_REJECTED`, `details.reason`).
- **Per-wallet transaction queue + ethers `cacheTimeout: -1`.** ethers v6 caches identical RPC calls for 250 ms, which handed out stale `pending` nonces for back-to-back transactions.
- **History tx references come from one `getLogs` call** filtered by the indexed product key across all 5 history events, zipped by order with `getHandoffHistory`. That's one RPC call per journey, and the event count doubles as a consistency check.
- **Transfer queues (`/transfers/incoming`, `/transfers/custody`) are derived from contract events + live `getProduct`**, not a Firestore cache. The chain stays the single source of truth for custody.
- **HD wallet indices 0–9 are reserved** (0 = deployer/admin, 1–6 = demo accounts); dynamically created accounts start at 10. Demo wallets stay stable across resets and never collide with real accounts.

## Data & hashing
- **Dates are stored as `YYYY-MM-DD` strings, timestamps as ISO-8601 strings** in Firestore. This avoids timezone drift in the fingerprint and keeps JSON simple.
- **Canonicalization trims strings and maps `""`/`undefined` to `null`.** A whitespace-only edit isn't meaningful tampering, and form inputs vary.
- **Optional client-supplied `productId` on `POST /products`** (A–Z, 0–9, `-`, `_`; 3–40 chars). Allows importing existing serials and exercising the duplicate-ID path through the API; auto IDs skip any number already taken.
- **No Firestore composite indexes are needed.** Queries use single-field filters and sort in memory, so a fresh project works without `firestore.indexes.json` deploys (fine at prototype scale).

## Verification
- **Reasons carry a severity** (`critical` → Suspect, `warning` → Flagged, `info`/`ok` → no effect). The status is derived from the worst severity, so rule order can't cause mistakes; the app shows passed checks too.
- **Thresholds have `.env` defaults, overridden by Firestore `settings/verification`** (cached 10 s). The seed writes demo values there (`minHandoffGapSeconds: 1`), as the prompt asks ("set very low in seed").
- **"Handoff gap" = time between consecutive custody changes** (Registered, Received, Sold). Dispatch→receive is transit time, not a handoff.
- **Scan counts include the current scan**: the 11th scan trips `SCAN_FLAG_THRESHOLD=10`.
- **The pre-retail flag applies to every public verify call**, including business users scanning. The reason text ("still with the distributor") is accurate for them too, and the endpoint stays auth-free.
- **Chain unreachable → HTTP 503, not "Unverified".** A missing record is Unverified; an outage is an error.

## Firebase
- **Firebase emulator support (Auth + Firestore) alongside a real project.** Lets everything (including `e2e`) run before the real project exists; switching is three `.env` lines.
- **Accounts created by admin need passwords ≥ 8 chars** (Firebase minimum is 6). Slightly safer default.

## Tooling
- **Project `.npmrc` with `include=dev`.** VS Code's extension host exports `NODE_ENV=production`, which silently skips devDependencies (Hardhat, jest).
- **Python 3.12 instead of 3.11 for ML.** It's what's installed; the dependencies support both.

## Mobile app
- **Cubits for screen state, Blocs for auth and verify.** flutter_bloc either way; events add value for auth/verify (bloc-tested as required), while list/detail screens are simple load/act cycles.
- **Firebase is initialised defensively.** `google-services.json` is git-ignored, so the Google Services Gradle plugin is applied only when the file exists. Without it, consumer verification still works and business login shows "not configured". `--dart-define=FIREBASE_AUTH_EMULATOR=host:9099` enables an emulator-only build.
- **The recipient picker lists suppliers, retailers *and* manufacturers.** The smart contract (not the UI) decides validity, which is what the demo shows ("supplier tries to send to a manufacturer").
- **Login navigates explicitly after success.** `/login` is pushed on top of `/`, and go_router's refresh redirect evaluates the base location only.
- **Label sheet = A4, 3 × 7 fixed-size cells** (`pw.Wrap`); `pw.GridView` ignored the aspect ratio. Text is limited to Latin-1 because of the built-in PDF font.
- **`kotlin.incremental=false`** in `android/gradle.properties`. With the project on D: and the pub cache on C:, Kotlin incremental compilation fails ("different roots").
- **Theme seed blue-grey (`#455A64`)**; status colours green `#2E7D32`, amber `#B26A00`, red `#C62828`, grey `#616161`, each with its own icon and label. All pass 3:1 contrast on white; green and amber are not colour-blind-separable, which is why colour is never used alone.

## Demo & ops
- **`reset-demo` deploys by spawning `hardhat run scripts/deploy.js`**, so there is a single deploy path for CLI, script and Sepolia.
- **Demo products go through the same service functions as the API** (`products.registerProduct`, `custody.*`), so seeded data is indistinguishable from real usage. Tampering is a direct Firestore update after registration.
- **`npm run e2e` creates its own fixtures** (and deletes its test account), so it never consumes the seeded demo products' scan budget. `reset-demo` also purges leftover `e2e-*` accounts.
- **The backend logs one line per request** (`METHOD path status ms ip`), which helps when debugging phone connectivity in T3.

## ML
- **Synthetic "normal" includes compressed-time journeys** (25%: whole chain within minutes). Seeded demo chains look like that; without it, every Genuine demo product was flagged (observed and fixed). Fast handoffs remain a deterministic rule.
- **About 2% injected anomalies (different seed) are mixed into training.** IsolationForest trained on normal-only data could not isolate out-of-range values (laundering recall was 0.7%; now 63%). Evaluation uses a held-out anomaly set.
- **Threshold = 99th percentile of normal training scores** (≈1% false positives on hold-out). The ML reason always has `warning` severity, so it can never produce Suspect.
- **The ML check is visible even when it passes** (`ML_NORMAL`, severity `ok`) and says when it didn't run (`technical.ml = null`, "not run" in the app), so users can tell a clean ML result from a missing one. A missing score is never reported as a reason in "Why", only in Technical details, to avoid alarming consumers.
- **ML results are stored per scan** (`mlScored`, `ml`), so admin reports can count and list ML flags with single-field Firestore queries (`mlScored == true`, `flags array-contains ML_ANOMALY`), and so the data can later be exported to retrain on real journeys.
- **e2e ML checks report SKIP when the service is off**, instead of PASS or FAIL: ML is optional, but the table must not claim coverage it didn't have.

## Client hand-off
- **The client gets a prebuilt release APK** (`dist\VeriTrace.apk`, default server `http://127.0.0.1:3000`), so they need Node.js and `adb`, not Flutter or Android Studio. `start-all.ps1` installs it over USB with `adb reverse`; Wi-Fi works through the in-app server setting.
- **The APK contains arm64 + x86_64 code only** (no 32-bit ARM). arm64 covers current Android phones; x86_64 lets it run on Android emulators too (useful for testing or presenting on a laptop). This keeps the build lighter than a full universal APK.
- **Firebase keys are not packaged by default** (`package-client.ps1 -IncludeFirebaseKeys` opts in). Handing a service-account key to a third party is the developer's call.
- **Every `start-all.ps1` run starts from fresh demo data.** The local Hardhat chain is ephemeral, so the launcher always redeploys and reseeds, and each demo starts from the same known state.
- **ML requirements use environment markers:** tested pins on Python ≤3.12, current releases on 3.13+ (where the pinned wheels don't exist). `setup.ps1` retrains if the bundled model can't be loaded.

