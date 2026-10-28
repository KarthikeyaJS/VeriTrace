# VeriTrace user guide

How the app works, who uses it, and what each person can do.
To start the system first, see [RUN_GUIDE.md](RUN_GUIDE.md).

---

## 1. The idea in one minute

Every product gets a **QR code** when the manufacturer registers it. The QR holds two things: the **product ID** (e.g. `VT-2026-000001`) and a **fingerprint**, a SHA-256 hash of the product's identity details (name, brand, category, batch, serial, dates, origin, manufacturer).

The fingerprint and every **change of custody** (manufacturer → supplier → … → retailer → sold) are written to a **blockchain**. Nobody can edit them afterwards. When anyone scans the QR, VeriTrace compares:

- the QR's fingerprint with the one on the blockchain (detects **forged labels**),
- the product details in the database with the blockchain fingerprint (detects **edited records**),
- the custody history and the scan history (detects **diverted, expired or cloned** products),

and shows one of four results:

| Result | Colour + icon | Meaning | What the user should do |
|---|---|---|---|
| **GENUINE** | green ✔ shield | Registered, fingerprint matches, clean history, released to retail | Trust it |
| **FLAGGED** | amber ⚠ | Real product, but something is unusual (see reasons) | Read the reasons; ask the seller |
| **SUSPECT** | red ✖ shield | Fingerprint or record doesn't match: possible counterfeit | Don't use it; report it |
| **UNVERIFIED** | grey ? | Not a VeriTrace code, or ID never registered | Can't be checked (not proof of fake) |

Each result also lists **"Why"**, the individual checks with their own icons: ✔ passed · ⓘ note · ⚠ warning · ✖ critical.

---

## 2. Who uses it

| User | Needs an account? | What they do |
|---|---|---|
| **Consumer** (shopper) | **No** | Scans a product and sees the result and its journey |
| **Manufacturer** | Yes | Registers products, prints/shares QR labels, ships to suppliers |
| **Supplier** (distributor/wholesaler) | Yes | Confirms incoming goods, ships on to another supplier or a retailer |
| **Retailer** (shop/pharmacy) | Yes | Confirms incoming goods, marks products as sold |
| **Admin** | Yes | Creates business accounts, changes roles, deactivates accounts, views reports |

There is **no public sign-up**. Only an admin can create business accounts. Every business account automatically gets its own blockchain wallet, managed by the backend, so users never deal with crypto, keys or gas.

---

## 3. Demo accounts and passwords

All demo accounts use the password **`Demo@1234`**. They live in Firebase project `veritrace-198d5`. `npm run reset-demo` re-creates them and resets their passwords.

| Email | Password | Role | Organisation | Blockchain wallet |
|---|---|---|---|---|
| `admin@veritrace.demo` | `Demo@1234` | Admin | VeriTrace Admin | `0xf39F…2266` |
| `maker@veritrace.demo` | `Demo@1234` | Manufacturer | Aurora Electronics | `0x7099…79C8` |
| `maker2@veritrace.demo` | `Demo@1234` | Manufacturer | Nila Pharma | `0x3C44…93BC` |
| `supplier1@veritrace.demo` | `Demo@1234` | Supplier | Southern Distributors | `0x90F7…b906` |
| `supplier2@veritrace.demo` | `Demo@1234` | Supplier | Metro Wholesale | `0x15d3…6A65` |
| `retailer1@veritrace.demo` | `Demo@1234` | Retailer | CityMart Bengaluru | `0x9965…A4dc` |
| `retailer2@veritrace.demo` | `Demo@1234` | Retailer | QuickCare Pharmacy | `0x976E…0aa9` |

Accounts the admin creates in the app get the password typed or generated on the "New account" form (at least 8 characters). Share it with the person securely.

### Demo products (created by `reset-demo`, QR images in `demo\qr\`)

| ID | Product | Where it is now | Scan result |
|---|---|---|---|
| `VT-2026-000001` | Aurora X1 Smartphone | Sold by CityMart (full journey M → S1 → S2 → R → Sold) | **Genuine** |
| `VT-2026-000002` | Aurora SoundPods Pro | On the shelf at CityMart | **Genuine** |
| `VT-2026-000003` | Aurora 65W GaN Charger | Still at Southern Distributors | **Flagged**: not yet at retail |
| `VT-2026-000004` | Aurora PowerBank 20000 | Sent by Metro Wholesale to CityMart, not yet confirmed | **Flagged**: in transit |
| `VT-2026-000005` | Nila Paracetamol 500 mg | At QuickCare; its database record was altered | **Suspect**: record tampered |
| `VT-2026-000006` | Nila Cough Syrup 100 ml | At QuickCare, past its expiry date | **Flagged**: expired |
| `VT-2026-000007` | Aurora Buds Lite | At CityMart, already scanned 14× from 8 phones | **Flagged**: possible cloned QR |
| `VT-2026-000008` | Aurora Tab 11 | At Aurora Electronics (use it for a live transfer demo) | **Flagged** until it reaches a shop |
| QR `09_FORGED…` | real ID of 000002 with a fake fingerprint | — | **Suspect**: forged label |
| QR `10_UNKNOWN…` | `VT-2026-999999` | never registered | **Unverified** |
| `VT-2026-000009` (QR `11_…`) | Nila Vitamin C 1000 mg | Sold by QuickCare Pharmacy | **Genuine** |
| `VT-2026-000010` (QR `12_…`) | Nila SunShield SPF 50 Sunscreen (Cosmetics) | At QuickCare Pharmacy | **Genuine** |
| `VT-2026-000011` (QR `13_…`) | Nila ORS Electrolyte Drink (Food & Beverage) | At CityMart Bengaluru | **Genuine** |
| `VT-2026-000012` (QR `14_…`) | Aurora DriveCam D2 Dash Camera (Automotive Parts) | M → S1 → S2 → CityMart → Sold | **Genuine** |
| `VT-2026-000013` (QR `15_…`) | Aurora Chronos Titanium Smartwatch (Luxury Goods) | At CityMart Bengaluru | **Genuine** |
| `VT-2026-000014` (QR `16_…`) | Aurora Smart Bulb 9W (4-pack) | At Aurora Electronics (a second item for live transfers) | **Flagged** until it reaches a shop |

The admin **Reports** tab starts with 12 recorded verifications (7 Genuine, 2 Flagged, 2 Suspect, 1 Unverified), plus the 14-scan history of Aurora Buds Lite.

---

## 4. Consumer: verifying a product (no login)

1. Open VeriTrace. The **Home** screen shows **Scan a product**, **Enter product ID** and, at the bottom, **Business login**.
2. Tap **Scan a product** and allow camera access the first time.
   - Point at the QR code on the label. Use the **⚡ torch** button (top right) in low light.
   - If you scan some other QR (a URL, Wi-Fi code…), an amber message says *"This is not a VeriTrace QR code"* and scanning continues.
   - No camera, or the label is damaged? Tap **Enter product ID instead**.
3. **Enter product ID**: type the ID printed under the QR (e.g. `VT-2026-000001`) and tap **Verify**. A typed ID can't check the QR fingerprint, so the result notes *"Product ID entered manually"*.
4. The **Verification result** screen shows:
   - the large **status badge** (GENUINE / FLAGGED / SUSPECT / UNVERIFIED),
   - **Why**: every check performed, passed or failed,
   - **Product details**: name, brand, category, manufacturer, batch, serial, manufacture and expiry dates (marked *expired* when past), MRP, origin, current holder,
   - **Journey**: a timeline of every custody step with the company name and role, date and time, and the blockchain transaction,
   - **Technical details** (tap to expand): contract address, product fingerprint, transaction hashes and block numbers, so anyone can recheck on the blockchain, plus the **ML anomaly check** (score, threshold, normal/unusual, or *not run* when the ML service is offline),
   - **Scan another product** / **Home**.
5. For a **Suspect** result the screen adds: *"Do not use this product. Keep the packaging and report it to the seller or brand."*

Every scan is recorded anonymously (a random ID per phone install, no personal data). That record is how cloned QR codes are detected.

---

## 5. Signing in (all business users)

1. Home → **Business login**.
2. Enter email and password → **Sign in**. You land on your own dashboard automatically.
3. Errors are shown under the form, e.g. *"Incorrect email or password"* or *"This account has been deactivated. Contact your admin."*
4. **Avatar (top-right circle)** shows your organisation, email, role and wallet address, plus **Public home** and **Sign out**.
5. Every dashboard has a **scan icon** in the top bar, so business users can verify products too.
6. Hidden **server settings**: on the login screen, tap the **tune icon** (top right) to change the backend URL, **Test** it and **Save**. Only needed if the server address changes.

The app remembers your login. Next time, Home shows **Open … dashboard** instead of Business login.

---

## 6. Manufacturer (e.g. `maker@veritrace.demo`)

### Dashboard: "My products"
A list of every product you registered, with **live status from the blockchain**:
- stage chip: **At manufacturer**, **At supplier**, **At retailer** or **Sold**, plus **Transfer pending** while a shipment awaits confirmation,
- a line saying who holds it (*Held by Southern Distributors*) or who must confirm (*Awaiting CityMart Bengaluru*).

Pull down to refresh. The **🖨 print icon** in the top bar prints one QR label for every product (A4 sheet).

### Register a product
1. Tap **Register product** (bottom right).
2. Fill in the form:

   | Field | Required | Notes |
   |---|---|---|
   | Product name | ✔ | |
   | Brand | ✔ | |
   | Category | ✔ | Electronics, Pharmaceuticals, Apparel, Cosmetics, Food & Beverage, Automotive Parts, Luxury Goods, Other |
   | Batch number | ✔ | |
   | Serial number | – | |
   | Manufacture date | ✔ | date picker, cannot be in the future |
   | Expiry date | – | must be after the manufacture date |
   | MRP (₹) | – | |
   | Country of origin | ✔ | defaults to India |
   | Description | – | |

3. Tap **Register product**. The button shows *"Registering on blockchain…"*. The backend gives the product an ID (`VT-<year>-<number>`), computes its fingerprint, and records it on the blockchain, signed by your company's wallet.
4. You land on the new product's page.

> Identity fields (everything except MRP and description) are part of the fingerprint. **They can't be changed later.** Changing them in the database afterwards makes every scan show *Suspect*, which is exactly how tampering is caught.

### Product page: QR, labels, shipping
- **QR code** with the product ID underneath.
- **Share PNG**: opens Android's share sheet (WhatsApp, email, Drive…) with an image of the label (QR + ID + name).
- **Print labels**: choose 1, 6, 12 or 21 labels → Android print dialog (print, or *Save as PDF*). The A4 sheet has 3 × 7 labels.
- **Transfer to supplier**: opens the recipient picker:
  1. choose a tab (**Supplier**, **Retailer** or **Maker**) and tap a company,
  2. confirm *"Send product?"*,
  3. the product shows **Transfer pending** and *"Sent to … — awaiting confirmation"*. Custody doesn't change until the supplier confirms.
- **Cancel transfer to …**: available while the shipment is pending. The product stays with you.
- **Product journey**: the full timeline. **Technical details**: blockchain references.

> A manufacturer can only ship to a **supplier**. Choosing a retailer or another manufacturer is rejected by the smart contract, and the app shows a red message: *"Rejected by the smart contract: A newly manufactured product can only be sent to a supplier, not to a retailer."*

---

## 7. Supplier (e.g. `supplier1@veritrace.demo`)

The dashboard has two tabs. The numbers show counts.

**Incoming**: products sent to you that you haven't confirmed yet.
- Each card shows the product, stage and *"From <sender>"*.
- Tap **Confirm receipt** when the goods physically arrive. The blockchain now records you as the holder (stage **At supplier**).
- Only the intended recipient can confirm. Nobody else sees it in their Incoming list.

**In custody**: products you currently hold.
- **Transfer**: pick another **supplier** (multi-hop distribution) or a **retailer**, then confirm.
- While pending, the card shows **Cancel transfer** instead.
- Sending back to a manufacturer is rejected on-chain: *"A supplier can only send to another supplier or a retailer, not to a manufacturer."*

Tap any card to open the full product page (QR, journey, technical details).

---

## 8. Retailer (e.g. `retailer1@veritrace.demo`)

**Incoming**: shipments from suppliers. Tap **Confirm receipt** when they arrive (stage **At retailer**).

**In stock**: products on your shelf.
- **Mark as sold**: confirm *"This cannot be undone"*. The stage becomes **Sold**, and the journey ends with *Sold to customer*.
- Retailers can't transfer further; the only next step is "sold".

A sold product still verifies as **Genuine** for its buyer.

---

## 9. Admin (`admin@veritrace.demo`)

Three tabs at the bottom:

### Users
- **Filter chips**: All / Admin / Manufacturer / Supplier / Retailer.
- Each card shows the name (*(you)* for yourself), email, **role**, an **Inactive** chip if deactivated, and **On-chain: <role>**:
  - green link icon: the blockchain matches the account,
  - red broken-link icon: mismatch (should not happen; re-saving the role fixes it).
- **⋮ menu** on another user:
  - **Role: Admin / Manufacturer / Supplier / Retailer**: changes the role in the database **and on the blockchain** (the confirmation shows the new on-chain role).
  - **Deactivate**: the user can't sign in or use the API, and their on-chain role becomes *No role*, so their wallet can no longer move goods. **Activate** restores it.
  - You can't change your own role or deactivate yourself.
- **New account** (bottom right): business/display name, email, role, initial password (auto-generated; **copy** or **regenerate**, minimum 8 characters) → **Create account**. This creates the login, a blockchain wallet (funded with test ETH for fees) and the on-chain role in one step.

### Products
Every product in the system, with manufacturer, stage and current holder. Tap one for its page.

### Reports
- **Anomaly detection (ML)**: whether the ML service is online, the model version and threshold, how many verifications it scored, and how many it flagged as unusual (tap to see those scans), plus its accuracy measured on synthetic test data.
- **Scans by result**: Genuine / Flagged / Suspect / Unverified counts. Tap a tile for the list of those scans (product, time, reasons).
- **Recent alerts**: the latest Flagged and Suspect scans and why they were flagged.
- **Products by stage** and **Active accounts by role**.

---

## 10. The rules the system enforces

### Custody path (enforced by the smart contract, not just the app)
```
Manufacturer ──► Supplier ──► (more Suppliers) ──► Retailer ──► SOLD
```
- A transfer has two steps: the **sender initiates**, the **recipient confirms**. Until then the sender still holds it and can **cancel**.
- Only the current holder can send. Only the named recipient can confirm. Only one pending transfer per product.
- Not allowed: manufacturer → retailer directly, anything → manufacturer/admin, sending to yourself, any action after **Sold**, and actions by deactivated accounts.
- Rejections are shown in the app as **"Rejected by the smart contract: …"**.

Roles are checked twice: by the backend before anything happens, and again by the blockchain contract, which checks the signing wallet's role.

### What makes a scan Flagged or Suspect

| Reason shown | Result | Rule |
|---|---|---|
| QR fingerprint doesn't match the blockchain | Suspect | forged or altered label |
| Product details don't match the registered fingerprint | Suspect | database record tampered |
| Custody history is inconsistent | Suspect | journey doesn't add up |
| Not yet released for retail sale | Flagged | stage is *At manufacturer* or *At supplier*: a consumer shouldn't have it |
| A custody transfer is in progress | Flagged | shipment not yet confirmed |
| Product expired on … | Flagged | expiry date passed |
| Scanned N times — may have been copied | Flagged | more than **10** scans in total |
| Scanned from N different devices | Flagged | more than **5** different phones |
| Custody changed unusually fast | Flagged | handoffs closer than the minimum gap (30 s normally; 1 s for the seeded demo) |
| Product details are missing | Flagged | on the blockchain but not in the database |
| Journey looks unusual (anomaly score) | Flagged | ML model (optional service); can never cause Suspect |
| Anomaly model found nothing unusual | (passed check ✔) | shown when the ML service scored the journey as normal |
| No blockchain record | Unverified | ID never registered: "cannot be verified", **not** "fake" |
| Not a VeriTrace QR code | Unverified | unreadable or foreign code |

> **Every scan counts.** Scanning a demo product more than 10 times while rehearsing turns it Flagged. Run `npm run reset-demo` before a real demo.

---

## 11. Typical end-to-end story (what to try)

1. **Consumer** scans `01_…sold-genuine.png` → Genuine; scroll through the journey.
2. **Consumer** scans `09_FORGED…` → Suspect; `05_…tampered…` → Suspect; `03_…` → Flagged; `10_UNKNOWN…` → Unverified.
3. **maker@** registers a new product → shares the QR → **Transfer to supplier** → tries **Retailer** first (rejected on-chain), then **Southern Distributors**.
4. **supplier1@** → Incoming → **Confirm receipt** → In custody → **Transfer** → *Retailer* → **CityMart Bengaluru**.
5. **retailer1@** → Incoming → **Confirm receipt** → In stock → **Mark as sold**.
6. **Consumer** scans the new product → Genuine, with the journey you just created.
7. **admin@** → Users (on-chain roles), deactivate a test account → Reports (your scans appear).

The timed presenter version is [DEMO_SCRIPT.md](DEMO_SCRIPT.md).

---

## 12. Good to know

- **No location is ever collected.** The app asks for camera permission only.
- **No personal data on the blockchain.** Only product IDs, fingerprints and wallet addresses.
- **Wallets are managed by the server** (prototype shortcut). Users never see keys or pay fees.
- **Local blockchain:** if the Hardhat node (T1) is restarted, all on-chain data is gone. Run `npm run reset-demo` to rebuild the demo (see [RUN_GUIDE.md](RUN_GUIDE.md)).
- **Limits of the approach** (copied QR codes, custodial keys, synthetic ML data…): [LIMITATIONS.md](LIMITATIONS.md).
