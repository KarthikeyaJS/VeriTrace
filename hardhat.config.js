require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config({ path: require("path").join(__dirname, "backend", ".env"), quiet: true });

const sepoliaUrl = process.env.SEPOLIA_RPC_URL || "";
const sepoliaMnemonic = process.env.SEPOLIA_MNEMONIC || "";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  networks: {
    hardhat: { chainId: 31337 },
    localhost: { url: "http://127.0.0.1:8545", chainId: 31337 },
    // Optional. scripts/deploy.js refuses to run on sepolia unless SEPOLIA_RPC_URL and a mnemonic are set.
    sepolia: {
      url: sepoliaUrl || "http://127.0.0.1:1",
      chainId: 11155111,
      accounts: sepoliaMnemonic ? { mnemonic: sepoliaMnemonic, path: "m/44'/60'/0'/0", count: 1 } : [],
    },
  },
  gasReporter: { enabled: false },
};
