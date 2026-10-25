# Setup — Windows, from zero

Everything runs on one Windows laptop. Your Android phone talks to it over Wi-Fi.

## 1. Install prerequisites

| Tool | Version used | Check |
|---|---|---|
| Node.js | 20+ (built with 22.18) | `node -v` |
| Flutter | stable (built with 3.44.4 / Dart 3.12) | `flutter --version` |
| Android Studio + SDK | with a JDK 17+ (bundled JBR is fine) | `flutter doctor` |
| Python | 3.11+ (built with 3.12) — only for the optional ML service | `python --version` |
| Java 21 | only for the optional Firebase emulators | `java -version` |

```powershell
cd D:\veritrace
npm install                 # Hardhat + contract tooling (root)
npm --prefix backend install
cd mobile; flutter pub get; cd ..
```
> If npm installs only a handful of packages, your shell has `NODE_ENV=production` (VS Code sets this). The repo ships `.npmrc` files with `include=dev` to counter it; otherwise run `$env:NODE_ENV="development"` first.

## 2. Firebase (real project)

1. https://console.firebase.google.com → **Add project** (e.g. `veritrace`).
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable.**
3. **Build → Firestore Database → Create database → Production mode → location `asia-south1` (Mumbai).**
4. **Project settings → Your apps → Add app → Android**, package name **`com.veritrace.app`** → download **`google-services.json`** → save to `mobile\android\app\google-services.json`.
5. **Project settings → Service accounts → Generate new private key** → save as `backend\serviceAccountKey.json`.
6. **Project settings → General → Web API key** → copy it.
7. Deploy the Firestore rules (the app never reads Firestore directly; rules deny everything except reading your own `users/{uid}`):
   `npm --prefix backend run deploy:rules` (uses the service account — no `firebase login` needed).
   `npx firebase-tools deploy --only firestore:rules` also works after `firebase login`; with only the service account it fails with
   *"serviceusage.services.use"* because the Admin SDK account lacks that IAM role.

All of these files are git-ignored. Never put them in the app or on-chain.

### Or: no Firebase project yet → local emulators
```powershell
npx firebase-tools emulators:start --only auth,firestore --project demo-veritrace
```
(needs Java 21; UI at http://127.0.0.1:4000). Then use the emulator lines in `.env` (below), and run the app with
`--dart-define=FIREBASE_AUTH_EMULATOR=<LAN-IP>:9099` (no `google-services.json` needed).

## 3. Backend `.env`

```powershell
copy backend\.env.example backend\.env
```
Real Firebase project:
```ini
CHAIN=local
RPC_URL=http://127.0.0.1:8545
MNEMONIC=                       # empty = Hardhat's default test mnemonic (local only)
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT=serviceAccountKey.json
FIREBASE_WEB_API_KEY=AIza...    # used by npm run e2e
ML_URL=http://127.0.0.1:8000
```
Emulators instead: add
```ini
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
FIREBASE_PROJECT_ID=demo-veritrace
```

## 4. Find your laptop's LAN IP

```powershell
ipconfig | findstr IPv4
```
Use the Wi-Fi adapter's address (e.g. `192.168.1.12`). Phone and laptop must be on the **same Wi-Fi** (not a guest network with client isolation).

## 5. Allow port 3000 through Windows Firewall (once, admin PowerShell)

```powershell
New-NetFirewallRule -DisplayName "VeriTrace backend 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Profile Private
# only if you use the Firebase emulators from the phone:
New-NetFirewallRule -DisplayName "VeriTrace auth emulator 9099" -Direction Inbound -Protocol TCP -LocalPort 9099 -Action Allow -Profile Private
```
Make sure your Wi-Fi network profile is **Private** (Settings → Network → Wi-Fi → your network → Private).

## 6. Terminal layout

Shortcut: `powershell -ExecutionPolicy Bypass -File .\start-all.ps1` opens all of these windows in order (see [RUN_GUIDE.md](RUN_GUIDE.md)). With the phone on USB you can skip steps 4–5: `adb reverse tcp:3000 tcp:3000` + `API_BASE_URL=http://127.0.0.1:3000`.


| Terminal | Command | Notes |
|---|---|---|
| T1 — chain | `npx hardhat node --hostname 0.0.0.0` | keep running; state is lost when stopped |
| T2 — deploy + seed | `npm run reset-demo` | redeploys, clears products/scans/audit/counters, seeds accounts + products, writes `demo/qr/*.png` |
| T3 — backend | `cd backend; npm start` | `http://0.0.0.0:3000`; check `http://localhost:3000/health` |
| T4 — app | `cd mobile; flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:3000` | phone connected via USB with USB debugging on |
| (T5 — ML, optional) | `cd ml; .\.venv\Scripts\python -m uvicorn app:app --host 127.0.0.1 --port 8000` | see `ml/README.md` for setup |
| (T0 — emulators, optional) | `npx firebase-tools emulators:start --only auth,firestore --project demo-veritrace` | only without a real Firebase project |

Then: `npm --prefix backend run e2e` → should print `42/42 passed`.

## 7. Optional: Sepolia testnet

1. Get a Sepolia RPC URL (Alchemy/Infura) and create a **new** mnemonic whose first account holds some Sepolia ETH.
2. In `backend\.env`: `SEPOLIA_RPC_URL=…`, `SEPOLIA_MNEMONIC=…`, and `CHAIN=sepolia`.
3. `npm run deploy:sepolia` (writes `backend\config\contract.sepolia.json`), then `npm run reset-demo` (with `CHAIN=sepolia` it redeploys to Sepolia; new wallets get 0.01 ETH from account 0). Each write waits ~12 s for a block.

## Troubleshooting

**Phone can't reach the backend** ("Cannot reach the VeriTrace server at …")
- Open `http://<LAN-IP>:3000/health` in the phone's browser. If it doesn't load: firewall rule (step 5), Wi-Fi profile not Private, phone on mobile data / a different Wi-Fi, or wrong IP (IPs change — re-run `ipconfig`).
- Fix the URL without rebuilding: Login screen → **tune icon (top right)** → enter `http://<LAN-IP>:3000` → **Test** → **Save**.
- The app allows plain HTTP (`usesCleartextTraffic="true"`) on purpose for the LAN prototype.

**Chain reset desync** ("No BlockAuth contract at the configured address", `CONTRACT_NOT_FOUND`, products missing)
- Stopping `hardhat node` wipes the chain but Firestore keeps old products. Run `npm run reset-demo` (T2). The backend reloads `contract.json` automatically — no restart needed.
- Demo QR images in `demo/qr/` belong to one deployment; `reset-demo` regenerates them.
- MetaMask-style "nonce too high" never applies here (custodial wallets, nonce read per tx).

**Camera permission**
- The first scan asks for camera access. If denied, the scanner shows instructions; enable it in *Settings → Apps → VeriTrace → Permissions → Camera*, or use **Enter product ID**.
- The app requests **no location permission** — by design.

**Business login says "not configured"** — the build has no `google-services.json` and no `FIREBASE_AUTH_EMULATOR` define. Consumer verification still works.

**`flutter build` fails with "Could not close incremental caches … different roots"** — project and pub cache are on different drives. Already handled by `kotlin.incremental=false` in `mobile/android/gradle.properties`.

**`npm run reset-demo` fails with "Cannot reach the chain"** — start T1 first. **"Cannot reach Firestore"** — check `.env` / service account / emulators.

**Login works but every request is 403 `NO_PROFILE`** — the Firebase user exists but has no `users/{uid}` doc. Run `npm run reset-demo` (demo accounts) or create the account from the admin dashboard.
