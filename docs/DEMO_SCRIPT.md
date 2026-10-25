# Demo script (5–7 minutes)

Uses the data created by `npm run reset-demo`. All accounts use the password **`Demo@1234`**.

## Before the audience arrives (5 min)

1. T1 `npx hardhat node --hostname 0.0.0.0` → T2 `npm run reset-demo` → T3 `cd backend; npm start` → (optional T5 ML service).
   **Always run `reset-demo` just before the demo**: every scan counts toward the clone-detection thresholds.
2. On the laptop, open `demo/qr/` in Explorer with large icons (or `demo/qr/README.md`) so you can show QR codes on screen.
3. Phone on the same Wi-Fi; app open on the Home screen; `http://<LAN-IP>:3000/health` loads in the phone browser.
4. Optional: open the Firestore emulator UI (http://127.0.0.1:4000) or the Firebase console in a browser tab for the tamper story.

| QR image (`demo/qr/`) | Product | Expected |
|---|---|---|
| `01_VT-2026-000001_sold-genuine.png` | Aurora X1 Smartphone — full journey, sold | **Genuine** |
| `02_VT-2026-000002_at-retailer-genuine.png` | Aurora SoundPods Pro — at CityMart | **Genuine** |
| `03_VT-2026-000003_at-supplier-flagged.png` | Aurora 65W GaN Charger — still at distributor | **Flagged** |
| `04_VT-2026-000004_pending-transfer-flagged.png` | Aurora PowerBank — in transit to CityMart | **Flagged** |
| `05_VT-2026-000005_tampered-suspect.png` | Nila Paracetamol — DB record altered | **Suspect** |
| `06_VT-2026-000006_expired-flagged.png` | Nila Cough Syrup — expired | **Flagged** |
| `07_VT-2026-000007_over-scanned-flagged.png` | Aurora Buds Lite — 14 scans / 8 devices | **Flagged** |
| `08_VT-2026-000008_manufactured-ready.png` | Aurora Tab 11 — at manufacturer (live demo item) | **Flagged** if a consumer scans |
| `09_FORGED_VT-2026-000002_forged-suspect.png` | Real ID, fake fingerprint | **Suspect** |
| `10_UNKNOWN_VT-2026-999999_unknown-unverified.png` | Never registered | **Unverified** |

---

## 0:00 — The problem (30 s)
"Counterfeit goods carry convincing labels. VeriTrace puts a fingerprint of each product and every custody handoff on a blockchain, so anyone can check a product with a phone. No account and no crypto wallet needed."

## 0:30 — Consumer: a genuine product (60 s)
1. Home → **Scan a product** → scan `01_…sold-genuine.png`.
2. Point out the large **GENUINE** badge (icon + text, never colour alone) and the reasons: *fingerprint matches*, *details match the registered fingerprint*, *history consistent*, *sold by an authorised retailer*.
3. Scroll to **Journey**: Aurora Electronics → Southern Distributors → Metro Wholesale → CityMart → Sold, each with a timestamp and transaction hash.
4. Expand **Technical details**: contract address, product hash, register tx, block numbers. "This is the evidence: anyone can recheck it on-chain."

## 1:30 — Consumer: when something is wrong (90 s)
1. Scan `09_FORGED_…` → **SUSPECT**: "Same product ID, but the fingerprint in the QR doesn't match the chain. Someone printed their own label."
2. Scan `05_…tampered-suspect.png` → **SUSPECT**: "This QR is genuine, but someone edited the database record and extended the expiry. The recomputed fingerprint no longer matches the one anchored on-chain." (Optionally show the altered `expiryDate` in Firestore.)
3. Scan `03_…at-supplier-flagged.png` → **FLAGGED**: "Registered and real, but it's still with a distributor according to the chain. A consumer shouldn't have it yet; it may have been diverted."
4. Scan `07_…over-scanned-flagged.png` → **FLAGGED**: "Scanned 14 times from 8 phones, so the QR was probably copied onto fakes." (With the ML service running, the anomaly model flags it too.)
5. Scan `10_UNKNOWN_…` → **UNVERIFIED**: "No record. We don't claim it's fake, only that it can't be verified."
6. (Also available: `06_…expired` → Flagged, expired; `04_…pending` → Flagged, in transit.)

## 3:00 — Manufacturer: register a product (60 s)
1. Home → **Business login** → `maker@veritrace.demo`.
2. Dashboard lists products with live stage chips. Tap **Register product**, fill in name/brand/category/batch/date → **Register product**.
3. "The backend hashes the identity fields with SHA-256 and the manufacturer's own wallet signs `registerProduct` on the contract." The detail screen shows the new **QR**, **Share PNG** and **Print labels** (A4 sheet).

## 4:00 — Supply chain + an on-chain rejection (90 s)
1. As the manufacturer, open **Aurora Tab 11** (`VT-2026-000008`) → **Transfer to supplier** → *Retailer* tab → CityMart → Send.
   → Red message: **"Rejected by the smart contract: A newly manufactured product can only be sent to a supplier, not to a retailer."** "The UI didn't block it; the contract did."
2. Transfer again → *Supplier* → **Southern Distributors** → Send. Status shows "awaiting confirmation".
3. Sign out (avatar → Sign out) → log in as `supplier1@veritrace.demo` → **Incoming** → **Confirm receipt**.
4. **In custody** → Transfer → *Maker* tab → Aurora Electronics → Send
   → **"Rejected by the smart contract: A supplier can only send to another supplier or a retailer, not to a manufacturer."**
5. Transfer → *Retailer* → **CityMart Bengaluru** → Send. Log in as `retailer1@veritrace.demo` → **Incoming → Confirm receipt** → **In stock → Mark as sold** (confirmation dialog).
6. Back on Home, scan `08_…` (or enter `VT-2026-000008`): now **Genuine**, with the full journey you just created.

## 5:30 — Admin (45 s)
1. Log in as `admin@veritrace.demo`. **Users**: role chips plus the live **on-chain role** for each account.
2. ⋮ on a user → change role or **Deactivate** → the on-chain role becomes *No role*, so their wallet can no longer move goods.
3. **Reports**: scans per result, recent Flagged/Suspect alerts (the scans you just made).

## 6:15 — Wrap-up (30 s)
"Fingerprints and custody live on-chain; product details stay off-chain. No personal data is on-chain. Every write is checked twice, by the API and by the smart contract. A QR can still be copied, which is why we flag repeated scans rather than claim to prevent copying. See `docs/LIMITATIONS.md`."

---

### If something goes wrong
- *"Cannot reach the VeriTrace server"*: phone Wi-Fi / firewall. Fix the URL with the tune icon on the login screen (see SETUP.md).
- *"No BlockAuth contract at the configured address"*: the Hardhat node was restarted. Run `npm run reset-demo` (takes ~15 s).
- A Genuine demo product shows **Flagged — scanned N times**: it was scanned more than 10 times while you rehearsed. Run `npm run reset-demo`.
