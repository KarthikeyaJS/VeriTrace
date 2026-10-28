# VeriTrace — start here

VeriTrace checks whether a product is genuine by scanning its QR code with an Android phone. Every product and every change of custody is recorded on a blockchain. This package runs the whole system **locally on one Windows laptop**, with the app on an Android phone connected by USB.

Plan for about **15 minutes** for the one-time setup, then **about 2 minutes** each time you start a demo.

---

## 1. What you received

| Item | What it is |
|---|---|
| `VeriTrace-client-<date>.zip` | the complete project: blockchain, server, ML service, documentation |
| `dist\VeriTrace.apk` (inside the zip) | the ready-built Android app; you do **not** need to build anything |
| `serviceAccountKey.json` | the key to the Firebase cloud project (sign-in and database). Sometimes sent separately; keep it private |

## 2. What you need (one time)

- A **Windows 10 or 11** laptop with an internet connection
- **Node.js 20 or newer (LTS)**: download from https://nodejs.org and install with the default options
- **Python 3.11 or newer** (optional, for the ML anomaly check): https://www.python.org/downloads/. Tick **"Add python.exe to PATH"** during installation
- An **Android phone** (Android 6.0 or newer) and its **USB data cable**
- Android Studio is **not** needed. Setup downloads the small `adb` tool automatically if it's missing

### Turn on USB debugging on the phone (one time)
1. **Settings → About phone** → tap **Build number** 7 times until it says "You are now a developer". (Xiaomi/Redmi: tap **MIUI/HyperOS version** instead.)
2. **Settings → (System →) Developer options** → turn on **USB debugging**. On Xiaomi/Redmi, also turn on **Install via USB**.
3. Connect the phone to the laptop. On the phone, tap **Allow** on *"Allow USB debugging?"* (tick "Always allow from this computer").

## 3. One-time setup

1. **Unzip** the package to a simple folder, e.g. `C:\VeriTrace`. Avoid OneDrive or Desktop folders that sync to the cloud.
2. If `serviceAccountKey.json` was sent separately, copy it into the **`backend`** folder (`C:\VeriTrace\backend\serviceAccountKey.json`).
3. Open **PowerShell** in the folder: in File Explorer open `C:\VeriTrace`, click the address bar, type `powershell` and press Enter.
4. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```
   This installs everything the project needs, which takes a few minutes. It ends with **"Setup complete"**. If it lists a problem instead, fix that item and run it again; it's safe to repeat.

## 4. Every time you run the demo

1. **Connect the phone** by USB and unlock it.
2. Open PowerShell in `C:\VeriTrace` (as in step 3 above) and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start-all.ps1
   ```
3. Wait about 1–2 minutes. Several windows open; **leave them open**:

   | Window | What it is |
   |---|---|
   | **T1 – Hardhat node** | the local blockchain |
   | **T3 – Backend** | the server the app talks to |
   | **T4 – ML service** | the anomaly check (only if Python is installed) |
   | **T2 – Deploy + seed** | loads the demo data; you can close it when it says *Done* |

   The script then installs the app, **opens VeriTrace on the phone**, and opens the `demo\qr` folder with the demo QR codes.
4. **Demo!** To scan: double-click a QR image in `demo\qr` so it fills the laptop screen, then tap **Scan a product** on the phone. Suggested walkthrough: [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md).
5. **When you're done:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\stop-all.ps1
   ```
   Then close the windows.

> **Every start begins with fresh demo data.** The local blockchain doesn't keep data between runs, so `start-all.ps1` re-creates the demo accounts, products and QR codes each time. Anything you created during the previous session (new products, transfers, sales) is gone, and every demo starts from the same known state.

> **Rehearsing?** Each scan counts toward the "scanned too many times — possible copied QR" warning. Restart (`stop-all.ps1`, then `start-all.ps1`) just before presenting to the audience.

## 5. The demo data you start with

### Accounts (password for all: `Demo@1234`)

| Email | Role | Company | What to show with it |
|---|---|---|---|
| `admin@veritrace.demo` | Admin | VeriTrace Admin | create accounts, change roles, reports |
| `maker@veritrace.demo` | Manufacturer | Aurora Electronics | register a product, QR labels, ship to a supplier |
| `maker2@veritrace.demo` | Manufacturer | Nila Pharma | pharmaceutical products |
| `supplier1@veritrace.demo` | Supplier | Southern Distributors | confirm incoming goods, ship on |
| `supplier2@veritrace.demo` | Supplier | Metro Wholesale | second distributor (multi-hop) |
| `retailer1@veritrace.demo` | Retailer | CityMart Bengaluru | confirm delivery, mark as sold |
| `retailer2@veritrace.demo` | Retailer | QuickCare Pharmacy | pharmacy |

Consumers don't need an account: anyone can scan.

### Products and their QR codes (`demo\qr\`)

| QR file | Product | Situation | Scan shows |
|---|---|---|---|
| `01_…sold-genuine` | Aurora X1 Smartphone | full journey: maker → 2 distributors → shop → sold | **GENUINE** |
| `02_…at-retailer-genuine` | Aurora SoundPods Pro | on the shelf at CityMart | **GENUINE** |
| `03_…at-supplier-flagged` | Aurora 65W GaN Charger | still at the distributor; shouldn't be with a consumer | **FLAGGED** |
| `04_…pending-transfer-flagged` | Aurora PowerBank 20000 | in transit to CityMart | **FLAGGED** |
| `05_…tampered-suspect` | Nila Paracetamol 500 mg | its database record was altered after registration | **SUSPECT** |
| `06_…expired-flagged` | Nila Cough Syrup 100 ml | past its expiry date | **FLAGGED** |
| `07_…over-scanned-flagged` | Aurora Buds Lite | scanned 14× from 8 phones: possibly copied QR (ML agrees) | **FLAGGED** |
| `08_…manufactured-ready` | Aurora Tab 11 | at the factory; use it to **demo a live shipment** | **FLAGGED** until it reaches a shop |
| `09_FORGED_…` | fake label (real ID, fake fingerprint) | counterfeit label | **SUSPECT** |
| `10_UNKNOWN_…` | `VT-2026-999999` | never registered | **UNVERIFIED** |
| `11_…vitamin-sold` | Nila Vitamin C 1000 mg | sold by QuickCare Pharmacy | **GENUINE** |
| `12_…sunscreen-at-retailer` | Nila SunShield SPF 50 (cosmetics) | at QuickCare Pharmacy | **GENUINE** |
| `13_…ors-at-retailer` | Nila ORS Electrolyte Drink (food & beverage) | at CityMart | **GENUINE** |
| `14_…dashcam-sold` | Aurora DriveCam D2 (automotive) | 2 distributors, sold at CityMart | **GENUINE** |
| `15_…luxury-watch-at-retailer` | Aurora Chronos Titanium (luxury goods) | at CityMart | **GENUINE** |
| `16_…smart-bulb-ready` | Aurora Smart Bulb 4-pack | at the factory; a **second** item for live shipping | **FLAGGED** until it reaches a shop |

Product IDs are `VT-<year>-000001` … `VT-<year>-000014` in the order the products appear in this table (forged/unknown aside). You can also type an ID with **Enter product ID** instead of scanning.
The admin **Reports** tab starts with a dozen recorded verifications, plus the scan history of the over-scanned product, so it isn't empty.

How each user works with the app, step by step: **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**.

## 6. Optional: Wi-Fi instead of the USB cable

By default the phone reaches the laptop **through the USB cable**, which needs no network setup. To use Wi-Fi instead:
1. Phone and laptop on the **same Wi-Fi** network (not a guest network).
2. In Windows: **Settings → Network & Internet → Wi-Fi → (your network) → Network profile type: Private**.
3. Allow the server through the firewall. Run once in PowerShell **as Administrator**:
   ```powershell
   New-NetFirewallRule -DisplayName "VeriTrace 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Profile Private
   ```
4. Start with `.\start-all.ps1 -Wifi`. It prints the address to use (e.g. `http://192.168.1.20:3000`).
5. In the app: **Business login → tune icon (top right) → enter that address → Test → Save**.

## 7. If something goes wrong

| Problem | What to do |
|---|---|
| *"running scripts is disabled on this system"* | always start scripts as shown: `powershell -ExecutionPolicy Bypass -File .\<script>.ps1` |
| `start-all.ps1` says *"Port … already in use"* | a previous session is still running: run `.\stop-all.ps1`, then start again (or `.\start-all.ps1 -Restart`) |
| *"No phone found"* | replug the cable, unlock the phone, accept *Allow USB debugging*; on some phones choose **File transfer** mode in the USB notification. Then run `.\start-all.ps1 -Only app` |
| APK install fails on Xiaomi/Redmi | Developer options → enable **Install via USB** (needs a Mi account), then `.\start-all.ps1 -Only app` |
| App says *"Cannot reach the VeriTrace server"* | the cable was unplugged/replugged: run `.\start-all.ps1 -Only app` (restores the USB link). Check that the T3 window is still running |
| App says *"No BlockAuth contract … run reset-demo"* | the blockchain window was closed: run `.\stop-all.ps1`, then `.\start-all.ps1` |
| Sign-in fails with *"Incorrect email or password"* | check the spelling and use the password `Demo@1234`. Restarting (`start-all.ps1`) also resets the demo passwords |
| A GENUINE demo product now shows *FLAGGED: scanned N times* | it was scanned too often while rehearsing: restart to get fresh data |
| Setup: *serviceAccountKey.json is missing* | copy the key file you received into the `backend` folder, then run `setup.ps1` again |
| No ML window / ML check says *"not run"* | Python isn't installed: optional. Install Python 3.11+ and run `setup.ps1` again |
| Health check | open http://localhost:3000/health in a browser: `"status":"ok"` means the server, blockchain and database are connected |

## 8. More documentation
- [docs/USER_GUIDE.md](docs/USER_GUIDE.md): every screen and role, result meanings, rules
- [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md): a 5–7 minute presentation script
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md): what this prototype does and does not prove
- [docs/RUN_GUIDE.md](docs/RUN_GUIDE.md) and [docs/SETUP.md](docs/SETUP.md): technical details for developers
