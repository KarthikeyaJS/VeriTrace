// VeriTrace backend entry point. `createApp()` is exported for supertest.
const express = require("express");
const cors = require("cors");
const config = require("./config");
const store = require("./services/firestore");
const blockchain = require("./services/blockchain");
const ml = require("./services/ml");
const { errorHandler, notFoundHandler } = require("./middleware/errorHandler");

function createApp() {
  const app = express();
  app.set("trust proxy", false);
  app.use(cors()); // prototype: open CORS
  app.use(express.json({ limit: "100kb" }));
  if (process.env.NODE_ENV !== "test") {
    app.use((req, res, next) => {
      const started = Date.now();
      res.on("finish", () => console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - started}ms ${req.ip}`));
      next();
    });
  }

  app.get("/health", async (req, res) => {
    const [chain, firestore, mlStatus] = await Promise.all([
      blockchain.getStatus(),
      store
        .ping()
        .then(() => ({ ok: true }))
        .catch((err) => ({ ok: false, error: err.message })),
      ml.health(),
    ]);
    firestore.mode = config.firebase.usingEmulator ? "emulator" : "firebase";
    firestore.projectId = config.firebase.projectId || null;
    const ok = chain.connected && chain.contractDeployed && firestore.ok;
    res.json({ status: ok ? "ok" : "degraded", time: new Date().toISOString(), chain, firestore, ml: mlStatus });
  });

  app.use("/", require("./routes/auth"));
  app.use("/users", require("./routes/users"));
  app.use("/products", require("./routes/products"));
  app.use("/transfers", require("./routes/transfers"));
  app.use("/verify", require("./routes/verify"));
  app.use("/reports", require("./routes/reports"));

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

if (require.main === module) {
  const app = createApp();
  app.listen(config.port, config.host, () => {
    console.log(`VeriTrace backend listening on http://${config.host}:${config.port}`);
    console.log(`  chain:     ${config.chain.key} (${config.chain.rpcUrl})`);
    console.log(`  firebase:  ${config.firebase.usingEmulator ? `emulator (${process.env.FIRESTORE_EMULATOR_HOST})` : "service account"}`);
    console.log(`  ml:        ${config.ml.url || "disabled"}`);
  });
}

module.exports = { createApp };
