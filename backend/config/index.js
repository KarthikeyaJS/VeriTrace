// Central configuration. Everything comes from backend/.env (see .env.example).
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const env = process.env;
const num = (value, fallback) => (value === undefined || value === "" ? fallback : Number(value));

// Hardhat's well-known default mnemonic. Local development ONLY — accounts 0-19 are pre-funded on `hardhat node`.
const HARDHAT_MNEMONIC = "test test test test test test test test test test test junk";

const CHAIN = (env.CHAIN || "local").toLowerCase();

const chains = {
  local: {
    key: "local",
    name: "localhost",
    chainId: 31337,
    rpcUrl: env.RPC_URL || "http://127.0.0.1:8545",
    mnemonic: env.MNEMONIC || HARDHAT_MNEMONIC,
    contractFile: path.join(__dirname, "contract.json"),
    fundAmountEth: env.FUND_AMOUNT_ETH || "1",
    minBalanceEth: env.MIN_BALANCE_ETH || "0.1",
  },
  sepolia: {
    key: "sepolia",
    name: "sepolia",
    chainId: 11155111,
    rpcUrl: env.SEPOLIA_RPC_URL || "",
    mnemonic: env.SEPOLIA_MNEMONIC || "",
    contractFile: path.join(__dirname, "contract.sepolia.json"),
    fundAmountEth: env.FUND_AMOUNT_ETH || "0.01",
    minBalanceEth: env.MIN_BALANCE_ETH || "0.005",
  },
};

if (!chains[CHAIN]) {
  throw new Error(`Unknown CHAIN "${CHAIN}". Use "local" or "sepolia".`);
}

const usingEmulator = Boolean(env.FIRESTORE_EMULATOR_HOST);

module.exports = {
  port: num(env.PORT, 3000),
  host: env.HOST || "0.0.0.0",
  chain: chains[CHAIN],
  firebase: {
    usingEmulator,
    projectId: env.FIREBASE_PROJECT_ID || (usingEmulator ? "demo-veritrace" : ""),
    serviceAccountPath: path.resolve(__dirname, "..", env.FIREBASE_SERVICE_ACCOUNT || "serviceAccountKey.json"),
    webApiKey: env.FIREBASE_WEB_API_KEY || "",
    authEmulatorHost: env.FIREBASE_AUTH_EMULATOR_HOST || "",
  },
  // Defaults; `settings/verification` in Firestore (written by the seed) can override them at runtime.
  verification: {
    scanFlagThreshold: num(env.SCAN_FLAG_THRESHOLD, 10),
    deviceFlagThreshold: num(env.DEVICE_FLAG_THRESHOLD, 5),
    minHandoffGapSeconds: num(env.MIN_HANDOFF_GAP_SECONDS, 30),
  },
  ml: {
    url: env.ML_URL === undefined ? "http://127.0.0.1:8000" : env.ML_URL,
    timeoutMs: num(env.ML_TIMEOUT_MS, 1500),
  },
  rateLimit: {
    verifyPerMinute: num(env.VERIFY_RATE_LIMIT_PER_MIN, 60),
  },
};
