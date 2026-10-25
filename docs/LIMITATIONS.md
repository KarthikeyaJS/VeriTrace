# Limitations

This is a prototype built to demonstrate the approach. Read these before drawing conclusions from a demo.

1. **A local chain is not production evidence.** The demo runs on a Hardhat node on one laptop, controlled by one operator, and wiped on restart. Real tamper-evidence needs a public or consortium chain with independent validators (Sepolia support is included only for testing). Block timestamps on a local node are also controlled by that node.

2. **QR codes can be copied.** A photocopied genuine QR verifies like the original. VeriTrace **mitigates** this (scan-count, distinct-device and ML anomaly flags, plus the "not yet at retail" rule) but cannot **prevent** it. The first buyers of a cloned batch may see *Genuine* until the thresholds trip. Stronger options: per-unit serialized codes revealed at sale, scratch-off PINs, NFC tags with secure elements.

3. **A valid chain record can't prove the physical item is genuine.** The chain proves that *a code* was registered by a known manufacturer and moved through known parties. It cannot prove the item in your hand is the one that was registered. Anyone holding a genuine code can attach it to a fake.

4. **Custodial keys are a prototype shortcut.** The backend derives every business user's wallet from one mnemonic in `.env`. Whoever controls the server can sign as any user, which defeats much of the point of a blockchain. Production needs per-user key custody (HSM/KMS per tenant, MPC wallets, or user-held wallets / account abstraction) and audited key rotation.

5. **The ML model is trained on synthetic data.** `ml/` uses an IsolationForest trained on generated journeys (hold-out false-positive rate ≈1%, recall ≈92% on *synthetic* anomalies; "laundering" through many hops only ≈63%). These numbers say nothing about real supply chains. The model also treats compressed-time journeys (seconds between handoffs) as normal so local demos don't trip it. Fast handoffs are left to the deterministic `MIN_HANDOFF_GAP_SECONDS` rule. ML can only raise a result to *Flagged*, never to *Suspect*.

6. **Thresholds are demo values.** Scan > 10, devices > 5 and handoff gap < 30 s (1 s after `reset-demo`) are arbitrary. Popular products are legitimately scanned many times; real thresholds need per-category tuning.

7. **Trust in the backend.** Consumers trust the backend to report chain data honestly. A sceptical user can recheck using the contract address, product hash and tx hashes in *Technical details*. There is no independent light-client verification in the app.

8. **Off-chain data is mutable.** Product details live in Firestore. Tampering with identity fields is detected (fingerprint mismatch → Suspect), but non-identity fields (MRP, description) are not fingerprinted and can change silently.

9. **Prototype security posture.** Open CORS, plain HTTP on the LAN (`usesCleartextTraffic`), an in-memory rate limiter that resets on restart, and no audit-log integrity protection. Firebase Auth emulator mode accepts unsigned tokens and is for local use only.

10. **Scale.** Lists and reports read the chain per product and filter in memory (no composite indexes). That's fine for hundreds of products, not millions. Event queries scan from the deploy block, which public RPCs may rate-limit on long-lived chains.

11. **Android only.** No iOS configuration. Business login needs `google-services.json` (or the auth emulator define). Light theme only.
