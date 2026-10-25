# VeriTrace API

Base URL: `http://<laptop-LAN-IP>:3000` (backend listens on `0.0.0.0:3000`). JSON in, JSON out. CORS is open (prototype).
A Postman collection + environment live in [`docs/postman/`](postman/).

## Conventions

**Auth** — business endpoints need `Authorization: Bearer <Firebase ID token>`. The backend verifies the token with Firebase Admin, then loads `users/{uid}` from Firestore. Roles: `admin`, `manufacturer`, `supplier`, `retailer`. Consumers use only `POST /verify` (no auth).

**Errors** — always:
```json
{ "error": { "code": "CHAIN_REJECTED", "message": "A supplier can only send to another supplier or a retailer, not to a manufacturer.", "details": { "onChain": true, "reason": "InvalidTransition" } } }
```

| HTTP | code | When |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Body/query failed validation; `details` = `[{field, message}]` |
| 400 | `BAD_JSON` | Body is not JSON |
| 400 | `CANNOT_MODIFY_SELF` | Admin tried to change own role / deactivate self |
| 401 | `UNAUTHENTICATED` / `INVALID_TOKEN` | Missing or expired token |
| 403 | `FORBIDDEN` | Role not allowed (backend middleware) |
| 403 | `NO_PROFILE` / `ACCOUNT_DISABLED` | No Firestore profile / deactivated |
| 403/404/409/422 | `CHAIN_REJECTED` | Smart contract reverted. `details.reason` = custom error name (`NotCurrentHolder`, `NotPendingRecipient`, `InvalidTransition`, `ProductAlreadyExists`, `ProductAlreadySold`, `NoPendingTransfer`, `TransferAlreadyPending`, `NotManufacturer`, `NotRetailer`, `CallerRoleMismatch`, `CannotTransferToSelf`, `ProductNotFound`, …) |
| 404 | `NOT_FOUND`, `PRODUCT_NOT_FOUND`, `USER_NOT_FOUND`, `RECIPIENT_NOT_FOUND` | |
| 409 | `DUPLICATE_PRODUCT`, `EMAIL_EXISTS` | |
| 429 | `RATE_LIMITED` | `/verify` > `VERIFY_RATE_LIMIT_PER_MIN` (60) per IP |
| 503 | `CHAIN_UNAVAILABLE`, `CONTRACT_NOT_DEPLOYED`, `CONTRACT_NOT_FOUND`, `FIREBASE_NOT_CONFIGURED` | Infrastructure not running / not configured |

**Write latency** — write endpoints wait until the transaction is mined (instant on Hardhat, ~12 s on Sepolia) and return `{ txHash, blockNumber }`.

**Shared shapes**

`Product` (list/detail views):
```json
{
  "productId": "VT-2026-000001", "name": "Aurora X1 Smartphone", "brand": "Aurora", "category": "Electronics",
  "batchNumber": "AX1-2026-07", "serialNumber": "AX1-000781", "manufactureDate": "2026-08-25", "expiryDate": null,
  "mrp": 24999, "countryOfOrigin": "India", "description": "…", "manufacturerId": "<uid>", "manufacturerName": "Aurora Electronics",
  "hash": "0x…", "registerTxHash": "0x…", "blockNumber": 12, "createdAt": "2026-10-24T16:52:58.458Z",
  "metadataMissing": false, "onChain": true, "stage": "Sold", "stageLabel": "Sold",
  "chain": {
    "productHash": "0x…", "registeredAt": "2026-10-24T16:53:04.000Z",
    "manufacturer":     { "address": "0x…", "uid": "…", "name": "Aurora Electronics", "role": "manufacturer" },
    "currentHolder":    { "address": "0x…", "uid": "…", "name": "CityMart Bengaluru", "role": "retailer" },
    "pendingRecipient": null
  }
}
```
`stage` ∈ `Manufactured | AtSupplier | AtRetailer | Sold`.

`JourneyEvent`:
```json
{ "index": 2, "eventType": "Received", "label": "Received", "stageAfter": "AtSupplier", "stageLabel": "At supplier",
  "from": { "name": "Aurora Electronics", "role": "manufacturer", "address": "0x…", "uid": "…" },
  "to":   { "name": "Southern Distributors", "role": "supplier", "address": "0x…", "uid": "…" },
  "timestamp": "2026-10-24T16:53:06.000Z", "txHash": "0x…", "blockNumber": 14 }
```
`eventType` ∈ `Registered | TransferInitiated | Received | TransferCancelled | Sold`. `txHash`/`blockNumber` come from contract events.

---

## Health

### `GET /health` — public
```json
{ "status": "ok", "time": "…",
  "chain": { "connected": true, "network": "localhost", "chainId": 31337, "rpcUrl": "http://127.0.0.1:8545", "contractAddress": "0x…", "deployBlock": 1, "blockNumber": 57, "contractDeployed": true },
  "firestore": { "ok": true, "mode": "emulator", "projectId": "demo-veritrace" },
  "ml": { "configured": true, "ok": false, "url": "http://127.0.0.1:8000" } }
```
`status` is `degraded` when the chain, contract or Firestore is down (HTTP is still 200). ML being down does not degrade status.

## Auth

### `GET /me` — any business role
→ `{ "user": { "uid", "email", "displayName", "role", "active", "walletAddress", "chainRole", "createdAt", "updatedAt" } }`
`chainRole` is read live from the contract (`null` if the chain is down).

## Users

### `POST /users` — admin
```json
{ "email": "ops@metro.example", "password": "atLeast8chars", "displayName": "Metro Wholesale", "role": "supplier" }
```
Creates the Firebase Auth user, allocates a custodial HD wallet (index ≥ 10), calls `setUserRole` **signed by the acting admin's wallet**, funds the wallet if its balance is low, writes `users/{uid}`, and adds an audit entry.
→ `201 { "user": {…}, "roleTxHash": "0x…" }` · Errors: `VALIDATION_ERROR`, `EMAIL_EXISTS`, `CHAIN_*`.

### `GET /users?role=` — admin
→ `{ "users": [ { …profile, "chainRole": "supplier" } ] }` (sorted by name; `role` optional filter).

### `PATCH /users/:uid` — admin
Body: any of `{ "role": "retailer", "active": false, "displayName": "…" }`.
Role or active changes are synced on-chain (`active:false` ⇒ on-chain role `none`); Firebase Auth `disabled` follows `active`.
→ `{ "user": {…, "chainRole": "none"}, "roleTxHash": "0x…" | null }` · Errors: `CANNOT_MODIFY_SELF`, `USER_NOT_FOUND`.

### `GET /users/recipients?role=supplier|retailer|manufacturer` — any business role
Active accounts of that role, excluding the caller. Used by the transfer picker.
→ `{ "recipients": [ { "uid", "displayName", "role", "walletAddress" } ] }`

## Products

### `POST /products` — manufacturer
```json
{ "name": "Aurora X1", "brand": "Aurora", "category": "Electronics", "batchNumber": "B-1", "serialNumber": null,
  "manufactureDate": "2026-10-01", "expiryDate": null, "mrp": 24999, "countryOfOrigin": "India", "description": null,
  "productId": "OPTIONAL-CUSTOM-ID" }
```
- `category` ∈ Electronics, Pharmaceuticals, Apparel, Cosmetics, Food & Beverage, Automotive Parts, Luxury Goods, Other.
- Dates `YYYY-MM-DD`; `expiryDate` > `manufactureDate`; `manufactureDate` not in the future.
- `productId` is optional (A–Z 0–9 `-` `_`, 3–40 chars). Default: `VT-<YYYY>-<NNNNNN>` from `counters/products`.
- Hash = SHA-256 of the canonical identity fields → `registerProduct(productId, hash)` signed by the manufacturer's wallet → Firestore `products/{id}`.

→ `201 { "product": { …fields, "hash", "registerTxHash", "blockNumber", "createdAt" }, "qrPayload": "veritrace://verify?id=VT-2026-000009&h=1f46…" }`
Errors: `VALIDATION_ERROR`, `FORBIDDEN` (non-manufacturer), `DUPLICATE_PRODUCT` (409), `CHAIN_REJECTED/ProductAlreadyExists`.

### `GET /products/mine` — manufacturer
→ `{ "products": [Product] }` (newest first, live on-chain stage).

### `GET /products` — admin
→ `{ "products": [Product] }` (all).

### `GET /products/:id` — any business role
→ `{ "product": Product, "journey": [JourneyEvent], "qrPayload": "veritrace://…", "technical": { "contractAddress", "chainId", "network", "productHash", "registerTxHash", "registerBlock" } }`
404 `PRODUCT_NOT_FOUND` if neither chain nor Firestore knows the ID.

### `GET /products/:id/qr-payload` — any business role
→ `{ "productId", "name", "hash": "0x…", "payload": "veritrace://verify?id=…&h=…" }` (hash read from chain).

### `POST /products/:id/sold` — retailer
Contract `markSold` from the retailer's wallet (must hold it at `AtRetailer`). → `{ "txHash", "blockNumber", "productId" }`
Errors: `CHAIN_REJECTED` with `NotCurrentHolder`, `NotRetailer`, `ProductAlreadySold`, `InvalidTransition`.

## Transfers

### `GET /transfers/incoming` — manufacturer, supplier, retailer
Products whose on-chain `pendingRecipient` is the caller (derived from `TransferInitiated` events + live state). → `{ "products": [Product] }`

### `GET /transfers/custody` — manufacturer, supplier, retailer
Products the caller currently holds and that are not sold (includes ones with an outgoing pending transfer). → `{ "products": [Product] }`

### `POST /transfers/:id/initiate` — manufacturer, supplier
Body `{ "toUid": "<recipient uid>" }`. The contract enforces: caller is holder, nothing pending, and the transition is valid (Manufactured → Supplier; AtSupplier → Supplier/Retailer).
→ `{ "txHash", "blockNumber", "productId", "to": { "uid", "displayName", "role" } }`
Errors: `RECIPIENT_NOT_FOUND`, `CHAIN_REJECTED` (`InvalidTransition`, `NotCurrentHolder`, `TransferAlreadyPending`, `CannotTransferToSelf`, `CallerRoleMismatch`).

### `POST /transfers/:id/confirm` — supplier, retailer
Only the pending recipient. Moves holder + stage. → `{ "txHash", "blockNumber", "productId" }`
Errors: `NotPendingRecipient` (403), `NoPendingTransfer` (409).

### `POST /transfers/:id/cancel` — manufacturer, supplier
Only the current holder while a transfer is pending. → `{ "txHash", "blockNumber", "productId" }`

## Verification (public)

### `POST /verify` — no auth, rate-limited per IP
```json
{ "payload": "veritrace://verify?id=VT-2026-000002&h=…", "deviceId": "anon-uuid" }
{ "productId": "VT-2026-000002", "deviceId": "anon-uuid" }
```
Every call is recorded in `scans` (`productId, at, deviceId, status, reasons, flags, mlScored, ml`).
```json
{
  "status": "Genuine | Flagged | Suspect | Unverified",
  "reasons": [ { "code": "QR_HASH_MATCH", "severity": "ok", "message": "QR fingerprint matches the blockchain record." } ],
  "product": Product | { "productId": "…" } | null,
  "journey": [JourneyEvent],
  "technical": { "contractAddress", "chainId", "network", "qrHash", "productHash", "recomputedHash", "registerTxHash", "registerBlock", "latestBlock", "scanCount", "distinctDevices", "ml": { "anomalyScore", "isAnomaly", "threshold", "modelVersion", "features": { …sent to the model } } | null }
}
```
`technical.ml` is `null` when the ML service is disabled, offline or slower than `ML_TIMEOUT_MS`: the result is then based on the other checks only.

Severity → status: any `critical` ⇒ **Suspect**; else any `warning` ⇒ **Flagged**; else **Genuine**. `Unverified` short-circuits.

| code | severity | rule |
|---|---|---|
| `MALFORMED_PAYLOAD` | info → Unverified | not a VeriTrace QR / invalid ID |
| `NOT_ON_CHAIN` | info → Unverified | ID unknown to the contract |
| `QR_HASH_MISMATCH` | critical | QR `h` ≠ on-chain hash |
| `METADATA_TAMPERED` | critical | hash recomputed from Firestore ≠ on-chain hash |
| `HISTORY_INCONSISTENT` | critical | handoff replay ≠ product state, or events ≠ history |
| `NOT_AT_RETAIL` | warning | stage Manufactured / AtSupplier |
| `TRANSFER_PENDING` | warning | pending recipient set |
| `EXPIRED` | warning | `expiryDate` < today |
| `EXCESSIVE_SCANS` | warning | scans (incl. this one) > `scanFlagThreshold` (10) |
| `MANY_DEVICES` | warning | distinct devices > `deviceFlagThreshold` (5) |
| `FAST_HANDOFF` | warning | a custody gap < `minHandoffGapSeconds` (30; seed sets 1) |
| `METADATA_MISSING` | warning | chain record but no Firestore doc |
| `ML_ANOMALY` | warning | ML service says anomaly (never critical) |
| `ML_NORMAL` | ok | ML service scored the journey as normal |
| `ON_CHAIN`, `QR_HASH_MATCH`, `METADATA_MATCH`, `HISTORY_CONSISTENT`, `AT_RETAILER`, `SOLD` | ok | passed checks |
| `QR_NOT_CHECKED` | info | manual ID entry |

Thresholds: `.env` defaults, overridden by Firestore `settings/verification` (written by `reset-demo`).

## Reports (admin)

### `GET /reports/summary`
```json
{ "scans": { "total": 43, "byStatus": { "Genuine": 21, "Flagged": 15, "Suspect": 4, "Unverified": 3 } },
  "products": { "total": 11, "byStage": { "Manufactured": 1, "AtSupplier": 2, "AtRetailer": 5, "Sold": 3, "NotOnChain": 0 } },
  "users": { "total": 8, "active": 7, "byRole": { "admin": 1, "manufacturer": 2, "supplier": 2, "retailer": 2 } },
  "recentAlerts": [ { "id", "productId", "productName", "at", "deviceId", "status": "Suspect", "reasons": [...], "flags": ["QR_HASH_MISMATCH"] } ],
  "settings": { "scanFlagThreshold": 10, "deviceFlagThreshold": 5, "minHandoffGapSeconds": 1 },
  "ml": { "configured": true, "ok": true, "url": "http://127.0.0.1:8000", "modelVersion": "iforest-…", "threshold": 0.56,
          "metrics": { "holdoutFalsePositiveRate": 0.01, "overallRecall": 0.92, "recallByKind": {…} },
          "scansScored": 18, "flaggedByMl": 9 } }
```

### `GET /reports/scans?status=Genuine|Flagged|Suspect|Unverified|all&flag=ML_ANOMALY&limit=50`
→ `{ "scans": [ …same shape as recentAlerts, plus "ml": { anomalyScore, isAnomaly, modelVersion } | null ] }` newest first (limit ≤ 200).
`flag` (optional) returns only scans whose flags contain that reason code, e.g. `ML_ANOMALY` = scans the ML model flagged.

## ML service (internal, `ml/`)
`POST http://127.0.0.1:8000/score` with `{ numHandoffs, minGapSeconds, meanGapSeconds, secondsSinceRegistration, scanCount, distinctDevices, scansLastHour, stage }` → `{ anomalyScore, isAnomaly, threshold, modelVersion }`. `GET /health` → `{ ok, modelVersion, threshold, features, trainedOn, metrics }`. Called by the backend with a 1.5 s timeout; failures are ignored (verification continues, `technical.ml = null`, `mlScored = false`).
