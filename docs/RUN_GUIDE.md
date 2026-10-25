# How to run VeriTrace (step by step)

One-time installation and Firebase setup are in [SETUP.md](SETUP.md). On this laptop they are done:
dependencies are installed, `backend\.env` points at Firebase project `veritrace-198d5`, and the key files are in place.

The system has five parts. Each runs in its own terminal window:

| Window | What | Port | Must stay open? |
|---|---|---|---|
| **T1** Hardhat node | the local blockchain | 8545 | yes; closing it wipes the chain |
| **T2** Deploy + seed | `npm run reset-demo`: deploys the contract, creates demo accounts/products/QR images | — | no; finishes in ~30 s |
| **T3** Backend | Express API used by the app | 3000 | yes |
| **T4** ML service | optional anomaly score | 8000 | optional |
| **T5** Flutter app | builds and runs the app on your phone | — | yes while testing (hot reload) |

---

## Option A — one command (recommended)

1. Plug in the phone with **USB debugging** on, and accept the "Allow USB debugging" prompt on the phone.
2. Open PowerShell in `D:\veritrace` and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start-all.ps1
   ```
3. Five windows open, in this order: **T1** chain → **T3** backend → **T4** ML → **T2** deploy + seed → **T5** Flutter app. Explorer also opens on `demo\qr\`.
   The script waits for each part before starting the next and prints `OK` lines. The first app build takes 2–5 minutes.
4. When T5 shows `Flutter run key commands`, the app is open on the phone.

Useful switches:
| Command | Use when |
|---|---|
| `.\start-all.ps1 -Restart` | something is already running on 8545/3000/8000 (stops it first) |
| `.\start-all.ps1 -Wifi` | the phone should use Wi-Fi instead of the USB cable (see "Wi-Fi mode" below) |
| `.\start-all.ps1 -NoApp` | servers only (e.g. testing with Postman) |
| `.\start-all.ps1 -NoMl` | skip the ML service |
| `.\start-all.ps1 -NoReset` | keep current data; only valid if T1 was **not** restarted |

All window output is also saved in `logs\t1-hardhat.log` … `logs\t5-flutter.log`.

## Option B — by hand (five terminals)

Open five PowerShell windows in `D:\veritrace` and run, **in this order**:

```powershell
# T1 — blockchain (leave running)
npx hardhat node --hostname 0.0.0.0

# T2 — deploy contract + seed demo data (wait for "Done in …")
npm run reset-demo

# T3 — backend API (leave running)
cd backend; npm start

# T4 — ML service (optional, leave running)
cd ml; .\.venv\Scripts\python -m uvicorn app:app --host 127.0.0.1 --port 8000

# T5 — app on the phone over USB (leave running)
adb reverse tcp:3000 tcp:3000
cd mobile; flutter devices          # note your phone's id, e.g. WWPVAU6XJFH655PJ
flutter run -d WWPVAU6XJFH655PJ --dart-define=API_BASE_URL=http://127.0.0.1:3000
```
If `adb` is not on PATH, use `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.

Check that everything is up: open http://localhost:3000/health and look for `"status":"ok"`. Optionally run `npm --prefix backend run e2e` (expect `42/42 passed`).

## USB mode vs Wi-Fi mode

- **USB mode (default):** `adb reverse tcp:3000 tcp:3000` makes the phone's `127.0.0.1:3000` reach the laptop through the cable. No firewall or Wi-Fi setup needed. Keep the cable connected. Re-run `adb reverse …` after reconnecting the phone.
- **Wi-Fi mode:** the app calls `http://<laptop-LAN-IP>:3000` directly. Phone and laptop must be on the same Wi-Fi, and Windows must allow inbound port 3000. On this laptop the Wi-Fi is set to **Public**, while the existing "VeriTrace 3000" firewall rule only allows **Private**, so Wi-Fi mode is blocked until you run (admin PowerShell, once):
  ```powershell
  Set-NetConnectionProfile -InterfaceAlias "Wi-Fi" -NetworkCategory Private
  ```
  Then use `.\start-all.ps1 -Wifi`, or `flutter run … --dart-define=API_BASE_URL=http://192.168.1.12:3000` (check the IP with `ipconfig`).
- You can change the server URL inside the app without rebuilding: **Business login → tune icon (top right) → URL → Test → Save**.

## Using the app

1. **Consumer (no login):** Home → **Scan a product**. Point the camera at a QR from `demo\qr\` on the laptop screen. Expected results are in `demo\qr\README.md` (01–02 Genuine; 03, 04, 06, 07, 08 Flagged; 05, 09 Suspect; 10 Unverified). Or tap **Enter product ID** and type `VT-2026-000001`.
2. **Business login** (password `Demo@1234` for all):
   - `maker@veritrace.demo`: register products, QR share/print, transfer to a supplier
   - `supplier1@veritrace.demo` / `supplier2@…`: confirm incoming, transfer on
   - `retailer1@veritrace.demo` / `retailer2@…`: confirm incoming, mark as sold
   - `admin@veritrace.demo`: accounts, roles, all products, reports
3. Sign out with the round avatar (top right) → **Sign out**.
4. For a 5–7 minute demo, follow [DEMO_SCRIPT.md](DEMO_SCRIPT.md).

In the **T5** window: `r` = hot reload, `R` = hot restart, `q` = quit the app session.

## Stopping and restarting

- **Stop everything:** close the windows (or press Ctrl+C in each).
- **Restart everything:** `.\start-all.ps1 -Restart`.
- **Closing T1 wipes the blockchain.** Products in Firestore then point at a contract that no longer exists, and the app shows *"No BlockAuth contract … run reset-demo"*. Always run T2 (`npm run reset-demo`) after starting T1. `start-all.ps1` does this for you.
- **Before a demo,** run `npm run reset-demo` once more: every scan counts toward the "scanned too often" flag.

## If something goes wrong

| Symptom | Fix |
|---|---|
| App: "Cannot reach the VeriTrace server" | USB mode: run `adb reverse tcp:3000 tcp:3000` again (cable re-plugged?). Wi-Fi mode: see above. Check that T3 is running. |
| App: "No BlockAuth contract at the configured address" | T1 was restarted → run `npm run reset-demo` |
| `start-all.ps1`: "Port … already in use" | re-run with `-Restart` |
| T5: "No supported devices connected" / phone missing | replug the USB cable, accept the debugging prompt on the phone, check `adb devices` |
| T5 build error "Could not close incremental caches" | already handled (`kotlin.incremental=false`); run `flutter clean` once if it persists |
| Login: "Incorrect email or password" | run `npm run reset-demo` (re-creates demo accounts with `Demo@1234`) |
| Script won't run: "running scripts is disabled" | use `powershell -ExecutionPolicy Bypass -File .\start-all.ps1` |
| Builds fail with disk errors | free space on C: (Gradle/pub caches live there) |
