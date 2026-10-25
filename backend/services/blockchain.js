// All interaction with the BlockAuth contract (ethers v6).
// Reads use a provider-backed contract; writes are signed by the acting user's custodial wallet
// and serialized per wallet so nonces never collide.
const fs = require("fs");
const { ethers } = require("ethers");
const config = require("../config");
const { AppError } = require("../utils/errors");

const ROLES = ["none", "admin", "manufacturer", "supplier", "retailer"];
const STAGES = ["None", "Manufactured", "AtSupplier", "AtRetailer", "Sold"];
const EVENT_TYPES = ["Registered", "TransferInitiated", "Received", "TransferCancelled", "Sold"];
const HISTORY_EVENTS = ["ProductRegistered", "TransferInitiated", "TransferReceived", "TransferCancelled", "ProductSold"];

const roleIndex = (role) => {
  const i = ROLES.indexOf(String(role || "none").toLowerCase());
  if (i < 0) throw new AppError(400, "INVALID_ROLE", `Unknown role "${role}".`);
  return i;
};

// --------------------------------------------------------------- provider
let provider = null;
function getProvider() {
  if (!provider) {
    if (!config.chain.rpcUrl) throw new AppError(503, "CHAIN_NOT_CONFIGURED", `No RPC URL configured for chain "${config.chain.key}".`);
    const network = ethers.Network.from(config.chain.chainId);
    provider = new ethers.JsonRpcProvider(config.chain.rpcUrl, network, {
      staticNetwork: network,
      pollingInterval: config.chain.key === "local" ? 250 : 4000,
      cacheTimeout: -1, // ethers' 250 ms request cache returns stale "pending" nonces for back-to-back txs
    });
  }
  return provider;
}

// ------------------------------------------------- contract (hot-reloaded)
let cache = { mtimeMs: -1, info: null, iface: null };

/** Reads config/contract.json, reloading automatically when a redeploy rewrites it. */
function getContractInfo() {
  const file = config.chain.contractFile;
  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    throw new AppError(503, "CONTRACT_NOT_DEPLOYED", "The BlockAuth contract has not been deployed yet. Run `npm run reset-demo` (or `npm run deploy:local`).");
  }
  if (stat.mtimeMs !== cache.mtimeMs) {
    const info = JSON.parse(fs.readFileSync(file, "utf8"));
    cache = { mtimeMs: stat.mtimeMs, info, iface: new ethers.Interface(info.abi) };
  }
  return cache.info;
}

function getInterface() {
  getContractInfo();
  return cache.iface;
}

function readContract() {
  const info = getContractInfo();
  return new ethers.Contract(info.address, info.abi, getProvider());
}

// ----------------------------------------------------------- error mapping
const STATUS_FOR = {
  NotAdmin: 403,
  NotManufacturer: 403,
  NotCurrentHolder: 403,
  NotPendingRecipient: 403,
  CallerRoleMismatch: 403,
  NotRetailer: 403,
  ProductAlreadyExists: 409,
  TransferAlreadyPending: 409,
  NoPendingTransfer: 409,
  ProductAlreadySold: 409,
  ProductNotFound: 404,
};

const roleLabel = (i) => {
  const r = ROLES[Number(i)] || "none";
  return r === "none" ? "an account without a business role" : `a ${r}`;
};

function transitionMessage(stage, recipientRole) {
  switch (STAGES[Number(stage)]) {
    case "Manufactured":
      return `A newly manufactured product can only be sent to a supplier, not to ${roleLabel(recipientRole)}.`;
    case "AtSupplier":
      return `A supplier can only send to another supplier or a retailer, not to ${roleLabel(recipientRole)}.`;
    case "AtRetailer":
      return Number(recipientRole) === 0
        ? "This product is not at the retail stage."
        : "A product at the retailer cannot be transferred further — mark it as sold instead.";
    case "Sold":
      return "This product has been sold; no further transfers are allowed.";
    default:
      return "This custody transition is not allowed.";
  }
}

const MESSAGES = {
  NotAdmin: () => "Only an admin account can change on-chain roles.",
  NotManufacturer: () => "Only a manufacturer account can register products.",
  ZeroAddress: () => "A valid recipient wallet address is required.",
  CannotChangeOwnRole: () => "You cannot change your own on-chain role.",
  EmptyProductId: () => "Product ID must not be empty.",
  InvalidHash: () => "Product fingerprint is invalid.",
  ProductAlreadyExists: ([id]) => `Product ID ${id} is already registered on the blockchain.`,
  ProductNotFound: ([id]) => `Product ${id} is not registered on the blockchain.`,
  NotCurrentHolder: () => "You are not the current holder of this product.",
  TransferAlreadyPending: () => "A transfer is already pending for this product. Cancel it before starting another.",
  NoPendingTransfer: () => "There is no pending transfer for this product.",
  NotPendingRecipient: () => "This transfer is addressed to a different account.",
  CannotTransferToSelf: () => "You cannot transfer a product to yourself.",
  CallerRoleMismatch: ([expected, actual]) =>
    `Your on-chain role (${ROLES[Number(actual)]}) cannot move this product; it requires ${ROLES[Number(expected)]}.`,
  InvalidTransition: ([stage, role]) => transitionMessage(stage, role),
  NotRetailer: () => "Only a retailer can mark a product as sold.",
  ProductAlreadySold: () => "This product has already been sold.",
};

function decodeRevert(err) {
  if (err && err.revert && err.revert.name) return { name: err.revert.name, args: Array.from(err.revert.args || []) };
  const data = err?.data ?? err?.info?.error?.data ?? err?.error?.data;
  const hex = typeof data === "string" ? data : typeof data?.data === "string" ? data.data : null;
  if (hex && hex.startsWith("0x") && hex.length >= 10) {
    try {
      const parsed = getInterface().parseError(hex);
      if (parsed) return { name: parsed.name, args: Array.from(parsed.args) };
    } catch {
      // not one of ours
    }
  }
  const m = /custom error '([A-Za-z]+)\(/.exec(err?.message || "");
  return m ? { name: m[1], args: [] } : null;
}

function isConnectionError(err) {
  const text = `${err?.code || ""} ${err?.message || ""} ${err?.cause?.code || ""}`;
  return /ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENOTFOUND|NETWORK_ERROR|fetch failed|socket hang up/i.test(text);
}

/** Converts any ethers/RPC error into an AppError with a human-readable message. */
function toAppError(err) {
  if (err instanceof AppError) return err;
  const revert = decodeRevert(err);
  if (revert && MESSAGES[revert.name]) {
    return new AppError(STATUS_FOR[revert.name] || 422, "CHAIN_REJECTED", MESSAGES[revert.name](revert.args), {
      onChain: true,
      reason: revert.name,
    });
  }
  if (isConnectionError(err)) {
    return new AppError(503, "CHAIN_UNAVAILABLE", `The blockchain node is not reachable at ${config.chain.rpcUrl}. Is \`npx hardhat node\` running?`);
  }
  if (err?.code === "BAD_DATA") {
    return new AppError(
      503,
      "CONTRACT_NOT_FOUND",
      "No BlockAuth contract at the configured address — the Hardhat node was probably restarted. Run `npm run reset-demo`."
    );
  }
  if (err?.code === "INSUFFICIENT_FUNDS") {
    return new AppError(503, "INSUFFICIENT_FUNDS", "The account wallet has no ETH for gas. Ask an admin to re-save the user to fund it.");
  }
  return new AppError(502, "CHAIN_ERROR", `Blockchain error: ${err?.shortMessage || err?.message || "unknown error"}`);
}

async function wrap(fn) {
  try {
    return await fn();
  } catch (err) {
    throw toAppError(err);
  }
}

// ----------------------------------------------------------- write queue
const queues = new Map();
function serialize(address, task) {
  const key = address.toLowerCase();
  const prev = queues.get(key) || Promise.resolve();
  const run = prev.then(task, task);
  queues.set(key, run.catch(() => {}));
  return run;
}

/** Sends a contract transaction from `wallet` and waits for it to be mined. */
function send(wallet, method, args) {
  return serialize(wallet.address, () =>
    wrap(async () => {
      const contract = readContract().connect(wallet);
      const tx = await contract[method](...args);
      const receipt = await tx.wait();
      return { txHash: receipt.hash, blockNumber: receipt.blockNumber };
    })
  );
}

function sendValue(wallet, to, amountEth) {
  return serialize(wallet.address, () =>
    wrap(async () => {
      const tx = await wallet.sendTransaction({ to, value: ethers.parseEther(String(amountEth)) });
      const receipt = await tx.wait();
      return { txHash: receipt.hash, blockNumber: receipt.blockNumber };
    })
  );
}

// ------------------------------------------------------------------ reads
const ZERO = ethers.ZeroAddress;

function normalizeProduct(p) {
  return {
    exists: Boolean(p.exists),
    productId: p.productId,
    productHash: p.productHash,
    manufacturer: p.manufacturer,
    registeredAt: Number(p.registeredAt),
    currentHolder: p.currentHolder,
    pendingRecipient: p.pendingRecipient === ZERO ? null : p.pendingRecipient,
    stage: STAGES[Number(p.stage)],
  };
}

function getProduct(productId) {
  return wrap(async () => normalizeProduct(await readContract().getProduct(productId)));
}

function productKey(productId) {
  return ethers.keccak256(ethers.toUtf8Bytes(productId));
}

/** Transaction references (hash + block) for each history event, in order. Null if logs are unavailable. */
async function getEventRefs(productId) {
  const info = getContractInfo();
  const iface = getInterface();
  const topics = HISTORY_EVENTS.map((name) => iface.getEvent(name).topicHash);
  try {
    const logs = await getProvider().getLogs({
      address: info.address,
      topics: [topics, productKey(productId)],
      fromBlock: info.deployBlock || 0,
      toBlock: "latest",
    });
    logs.sort((a, b) => a.blockNumber - b.blockNumber || a.index - b.index);
    return logs.map((l) => ({ txHash: l.transactionHash, blockNumber: l.blockNumber, event: iface.parseLog(l).name }));
  } catch {
    return null;
  }
}

/** Ordered handoff history, each entry enriched with txHash/blockNumber from contract events. */
function getHistory(productId) {
  return wrap(async () => {
    const [raw, refs] = await Promise.all([readContract().getHandoffHistory(productId), getEventRefs(productId)]);
    const handoffs = raw.map((h, i) => ({
      eventType: EVENT_TYPES[Number(h.eventType)],
      from: h.from,
      to: h.to === ZERO ? null : h.to,
      timestamp: Number(h.timestamp),
      stageAfter: STAGES[Number(h.stageAfter)],
      txHash: refs && refs[i] ? refs[i].txHash : null,
      blockNumber: refs && refs[i] ? refs[i].blockNumber : null,
    }));
    return { handoffs, eventCount: refs ? refs.length : null };
  });
}

function getRole(address) {
  return wrap(async () => ROLES[Number(await readContract().roles(address))]);
}

function getBalance(address) {
  return wrap(() => getProvider().getBalance(address));
}

/** Product IDs whose events name `address` in the given indexed position (for incoming/custody queues). */
async function productIdsFromEvents(eventName, topicPosition, address) {
  const info = getContractInfo();
  const iface = getInterface();
  const topics = [iface.getEvent(eventName).topicHash, null, null, null];
  topics[topicPosition] = ethers.zeroPadValue(address, 32);
  const logs = await getProvider().getLogs({ address: info.address, topics, fromBlock: info.deployBlock || 0, toBlock: "latest" });
  return logs.map((l) => iface.parseLog(l).args.productId);
}

/** Products currently awaiting confirmation by `address`. */
function getIncoming(address) {
  return wrap(async () => {
    const ids = [...new Set(await productIdsFromEvents("TransferInitiated", 3, address))];
    const products = await Promise.all(ids.map((id) => readContract().getProduct(id).then(normalizeProduct)));
    return products.filter((p) => p.pendingRecipient && p.pendingRecipient.toLowerCase() === address.toLowerCase());
  });
}

/** Products currently held by `address` (registered or received), excluding sold ones. */
function getCustody(address) {
  return wrap(async () => {
    const [registered, received] = await Promise.all([
      productIdsFromEvents("ProductRegistered", 2, address),
      productIdsFromEvents("TransferReceived", 3, address),
    ]);
    const ids = [...new Set([...registered, ...received])];
    const products = await Promise.all(ids.map((id) => readContract().getProduct(id).then(normalizeProduct)));
    return products.filter((p) => p.currentHolder.toLowerCase() === address.toLowerCase() && p.stage !== "Sold");
  });
}

async function getStatus() {
  const status = { connected: false, network: config.chain.name, chainId: config.chain.chainId, rpcUrl: config.chain.rpcUrl };
  try {
    const info = getContractInfo();
    status.contractAddress = info.address;
    status.deployBlock = info.deployBlock;
  } catch (err) {
    status.error = err.message;
  }
  try {
    status.blockNumber = await getProvider().getBlockNumber();
    status.connected = true;
    if (status.contractAddress) {
      const code = await getProvider().getCode(status.contractAddress);
      status.contractDeployed = code !== "0x";
      if (!status.contractDeployed) status.error = "No contract code at the configured address. Run `npm run reset-demo`.";
    }
  } catch (err) {
    status.error = toAppError(err).message;
  }
  return status;
}

// ----------------------------------------------------------------- writes
const setUserRole = (adminWallet, address, role) => send(adminWallet, "setUserRole", [address, roleIndex(role)]);
const registerProduct = (wallet, productId, hash) => send(wallet, "registerProduct", [productId, hash]);
const initiateTransfer = (wallet, productId, to) => send(wallet, "initiateTransfer", [productId, to]);
const confirmReceipt = (wallet, productId) => send(wallet, "confirmReceipt", [productId]);
const cancelTransfer = (wallet, productId) => send(wallet, "cancelTransfer", [productId]);
const markSold = (wallet, productId) => send(wallet, "markSold", [productId]);

module.exports = {
  ROLES,
  STAGES,
  EVENT_TYPES,
  getProvider,
  getContractInfo,
  getInterface,
  toAppError,
  decodeRevert,
  getProduct,
  getHistory,
  getRole,
  getBalance,
  getIncoming,
  getCustody,
  getStatus,
  sendValue,
  setUserRole,
  registerProduct,
  initiateTransfer,
  confirmReceipt,
  cancelTransfer,
  markSold,
};
