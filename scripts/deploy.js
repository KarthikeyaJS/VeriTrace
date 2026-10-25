// Deploys BlockAuth and writes address + ABI for the backend.
//   npx hardhat run scripts/deploy.js --network localhost  -> backend/config/contract.json
//   npx hardhat run scripts/deploy.js --network sepolia    -> backend/config/contract.sepolia.json
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");

async function main() {
  const { ethers, network } = hre;
  if (network.name === "sepolia" && (!process.env.SEPOLIA_RPC_URL || !process.env.SEPOLIA_MNEMONIC)) {
    throw new Error("Set SEPOLIA_RPC_URL and SEPOLIA_MNEMONIC in backend/.env before deploying to Sepolia.");
  }

  const [deployer] = await ethers.getSigners();
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Network:  ${network.name} (chainId ${network.config.chainId})`);
  console.log(`Deployer: ${deployer.address} (balance ${ethers.formatEther(balance)} ETH)`);

  const factory = await ethers.getContractFactory("BlockAuth");
  const contract = await factory.deploy();
  await contract.waitForDeployment();
  const receipt = await contract.deploymentTransaction().wait();
  const address = await contract.getAddress();
  const artifact = await hre.artifacts.readArtifact("BlockAuth");

  const out = {
    network: network.name,
    chainId: Number(network.config.chainId),
    address,
    deployer: deployer.address,
    deployTxHash: receipt.hash,
    deployBlock: receipt.blockNumber,
    deployedAt: new Date().toISOString(),
    abi: artifact.abi,
  };
  const file = network.name === "sepolia" ? "contract.sepolia.json" : "contract.json";
  const target = path.join(__dirname, "..", "backend", "config", file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(out, null, 2));
  console.log(`BlockAuth deployed at ${address} (block ${receipt.blockNumber})`);
  console.log(`Wrote ${path.relative(process.cwd(), target)}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exitCode = 1;
});
