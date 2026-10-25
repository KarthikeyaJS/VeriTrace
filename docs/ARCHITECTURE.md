# Architecture

## System

```mermaid
flowchart LR
  subgraph Phone["Android phone (Flutter, Bloc)"]
    C[Consumer: scan / enter ID<br/>no login]
    B[Business dashboards<br/>admin · manufacturer · supplier · retailer]
  end

  FA[(Firebase Auth<br/>email/password)]

  subgraph Laptop["Laptop (same Wi-Fi)"]
    API["Node.js + Express backend :3000<br/>authenticate · authorize(roles)<br/>verification rules · custodial wallets"]
    HH[("Hardhat node :8545<br/>BlockAuth.sol")]
    ML["Python FastAPI :8000<br/>IsolationForest (optional)"]
  end

  FS[(Cloud Firestore<br/>users · products · scans · counters · audit · settings)]

  B -- "sign in" --> FA
  C -- "POST /verify (HTTP/JSON)" --> API
  B -- "Bearer ID token (HTTP/JSON)" --> API
  API -- "verifyIdToken, createUser" --> FA
  API -- "Admin SDK" --> FS
  API -- "ethers v6: tx signed by the user's own HD wallet" --> HH
  API -- "POST /score (1.5 s timeout)" --> ML
```

Key points
- The app **never talks to the chain**: no wallet, no keys, no web3 on the phone. Consumers need no account.
- **Custodial wallets**: the backend derives `m/44'/60'/0'/0/<walletIndex>` from its mnemonic and signs every business action with **that user's** wallet, so `msg.sender` role checks in the contract are real. Index 0 = deployer/admin; demo accounts 1–6; new accounts ≥ 10.
- **Roles are enforced twice**: backend `authorize(...roles)` middleware, and the contract (`roles[msg.sender]`, holder/recipient checks, transition rules).
- **On-chain**: product ID key `keccak256(productId)`, SHA-256 fingerprint, custody history. **Off-chain (Firestore)**: product details, user profiles, scans, audit. No personal data on-chain.
- Firestore rules deny all direct client access except reading your own `users/{uid}`; the app goes through the backend.

## Product state machine (enforced by `BlockAuth.sol`)

```mermaid
stateDiagram-v2
  [*] --> Manufactured: registerProduct()\n(manufacturer)
  Manufactured --> Manufactured: initiateTransfer(to supplier)\n/ cancelTransfer()
  Manufactured --> AtSupplier: confirmReceipt()\n(by pending supplier)
  AtSupplier --> AtSupplier: initiateTransfer(to supplier or retailer)\n/ cancelTransfer()\n/ confirmReceipt() by next supplier
  AtSupplier --> AtRetailer: confirmReceipt()\n(by pending retailer)
  AtRetailer --> Sold: markSold()\n(holding retailer)
  Sold --> [*]

  note right of Manufactured
    Rejected on-chain: M → Retailer directly,
    transfer to wrong role / self / zero address,
    second pending transfer, non-holder actions,
    anything after Sold
  end note
```

Every transition appends a `Handoff {from, to, timestamp, eventType, stageAfter}` and emits one event (`ProductRegistered`, `TransferInitiated`, `TransferReceived`, `TransferCancelled`, `ProductSold`). The backend matches the n-th event to the n-th handoff to attach `txHash` + `blockNumber`.

## Verification decision flow (`backend/services/verification.js`)

```mermaid
flowchart TD
  A[POST /verify payload or productId] --> P{Parse payload}
  P -- malformed --> U1[Unverified: MALFORMED_PAYLOAD]
  P -- ok --> G[contract.getProduct id]
  G -- "exists = false" --> U2[Unverified: NOT_ON_CHAIN<br/>never 'counterfeit']
  G -- exists --> D[Load history + events, Firestore doc,<br/>scan stats, thresholds, ML score]
  D --> C1{"QR hash ≠ chain hash?<br/>recomputed Firestore hash ≠ chain hash?<br/>history replay inconsistent?"}
  C1 -- any --> S[Suspect]
  C1 -- none --> W{"stage Manufactured/AtSupplier?<br/>transfer pending? expired?<br/>scans > 10 or devices > 5?<br/>handoff gap < threshold?<br/>metadata missing? ML anomaly?"}
  W -- any --> F[Flagged]
  W -- none --> OK[Genuine]
  S & F & OK & U1 & U2 --> R[(scans: productId, at, deviceId, status, reasons)]
```
Implementation: every rule emits a reason with a severity (`critical`, `warning`, `info`, `ok`). The status is the worst severity, so ML (always `warning`) can raise a result to Flagged but never to Suspect.

## Registration sequence

```mermaid
sequenceDiagram
  autonumber
  actor M as Manufacturer (app)
  participant FA as Firebase Auth
  participant API as Backend
  participant FS as Firestore
  participant BC as BlockAuth (Hardhat)
  M->>FA: signInWithEmailAndPassword
  FA-->>M: ID token
  M->>API: POST /products (Bearer token, details)
  API->>FA: verifyIdToken
  API->>FS: users/{uid} → role = manufacturer, walletIndex
  API->>FS: transaction counters/products → VT-2026-000042
  API->>API: hash = SHA-256(canonical identity fields)
  API->>BC: registerProduct(id, hash) signed by manufacturer wallet
  BC-->>API: receipt (txHash, block) + ProductRegistered
  API->>FS: products/{id} (details, hash, registerTxHash, blockNumber)
  API->>FS: audit
  API-->>M: 201 product + qrPayload veritrace://verify?id=…&h=…
  M->>M: render QR · Share PNG · Print label sheet
```

## Transfer sequence (two-step custody)

```mermaid
sequenceDiagram
  autonumber
  actor S as Supplier A (holder)
  actor R as Retailer (recipient)
  participant API as Backend
  participant BC as BlockAuth
  S->>API: POST /transfers/{id}/initiate {toUid: R}
  API->>BC: initiateTransfer(id, R.wallet) signed by A
  alt invalid (wrong role, not holder, pending, sold…)
    BC-->>API: revert InvalidTransition(...)
    API-->>S: 422 CHAIN_REJECTED "A supplier can only send to…"
  else valid
    BC-->>API: TransferInitiated (pendingRecipient = R)
    API-->>S: 200 txHash
  end
  R->>API: GET /transfers/incoming
  API->>BC: TransferInitiated logs (to = R) + getProduct
  API-->>R: [product]
  R->>API: POST /transfers/{id}/confirm
  API->>BC: confirmReceipt(id) signed by R
  BC-->>API: TransferReceived (holder = R, stage = AtRetailer)
  API-->>R: 200 txHash
  R->>API: POST /products/{id}/sold
  API->>BC: markSold(id) signed by R
  BC-->>API: ProductSold (stage = Sold, terminal)
```

## Code map

| Area | Path |
|---|---|
| Contract + tests + deploy | `contracts/BlockAuth.sol`, `test/BlockAuth.test.js`, `scripts/deploy.js` |
| API entry | `backend/server.js` |
| Rules (single source of truth) | `backend/services/verification.js`, fingerprint in `backend/services/hashing.js` |
| Chain access, error mapping | `backend/services/blockchain.js`, wallets in `backend/services/wallets.js` |
| Seed / reset / e2e | `backend/scripts/{seed,reset-demo,e2e}.js`, demo data `backend/scripts/demoData.js` |
| App | `mobile/lib/core/*` (API client, router, theme, models), `mobile/lib/features/<feature>/{data,bloc,view}` |
| ML | `ml/{generate_data,train,app}.py` |
