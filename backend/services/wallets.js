// Custodial HD wallets: every business user signs with their own key derived from the
// backend-held mnemonic at m/44'/60'/0'/0/<walletIndex>. Index 0 is the deployer/admin.
const { ethers } = require("ethers");
const config = require("../config");
const { AppError } = require("../utils/errors");
const blockchain = require("./blockchain");

const BASE_PATH = "m/44'/60'/0'/0";
let base = null;
const cache = new Map();

function baseNode() {
  if (!base) {
    if (!config.chain.mnemonic) throw new AppError(503, "WALLET_NOT_CONFIGURED", `No mnemonic configured for chain "${config.chain.key}".`);
    base = ethers.HDNodeWallet.fromPhrase(config.chain.mnemonic, undefined, BASE_PATH);
  }
  return base;
}

function walletAt(index) {
  if (!Number.isInteger(index) || index < 0) throw new AppError(500, "INVALID_WALLET_INDEX", `Invalid wallet index ${index}.`);
  if (!cache.has(index)) cache.set(index, baseNode().deriveChild(index).connect(blockchain.getProvider()));
  return cache.get(index);
}

const addressAt = (index) => walletAt(index).address;
const deployer = () => walletAt(0);

function walletForUser(user) {
  if (!user || !Number.isInteger(user.walletIndex)) {
    throw new AppError(409, "NO_WALLET", "This account has no blockchain wallet yet. Ask an admin to re-save it.");
  }
  return walletAt(user.walletIndex);
}

/** Tops up `address` from the deployer if its balance is below the configured minimum. */
async function ensureFunded(address) {
  const balance = await blockchain.getBalance(address);
  if (balance >= ethers.parseEther(config.chain.minBalanceEth)) return { funded: false, balanceEth: ethers.formatEther(balance) };
  if (address.toLowerCase() === deployer().address.toLowerCase()) return { funded: false, balanceEth: ethers.formatEther(balance) };
  const { txHash } = await blockchain.sendValue(deployer(), address, config.chain.fundAmountEth);
  return { funded: true, txHash, amountEth: config.chain.fundAmountEth };
}

module.exports = { walletAt, addressAt, deployer, walletForUser, ensureFunded };
