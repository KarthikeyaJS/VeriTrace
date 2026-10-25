const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const Role = { None: 0, Admin: 1, Manufacturer: 2, Supplier: 3, Retailer: 4 };
const Stage = { None: 0, Manufactured: 1, AtSupplier: 2, AtRetailer: 3, Sold: 4 };
const EventType = { Registered: 0, TransferInitiated: 1, Received: 2, TransferCancelled: 3, Sold: 4 };

const PID = "VT-2026-000001";
const HASH = ethers.sha256(ethers.toUtf8Bytes("fingerprint-1"));
const key = (id) => ethers.keccak256(ethers.toUtf8Bytes(id));

async function deployFixture() {
  const [admin, maker, supplier1, supplier2, retailer, outsider, maker2] = await ethers.getSigners();
  const contract = await (await ethers.getContractFactory("BlockAuth")).deploy();
  await contract.setUserRole(maker.address, Role.Manufacturer);
  await contract.setUserRole(maker2.address, Role.Manufacturer);
  await contract.setUserRole(supplier1.address, Role.Supplier);
  await contract.setUserRole(supplier2.address, Role.Supplier);
  await contract.setUserRole(retailer.address, Role.Retailer);
  return { contract, admin, maker, maker2, supplier1, supplier2, retailer, outsider };
}

async function registeredFixture() {
  const f = await deployFixture();
  await f.contract.connect(f.maker).registerProduct(PID, HASH);
  return f;
}

describe("BlockAuth", function () {
  describe("roles", function () {
    it("makes the deployer Admin", async function () {
      const { contract, admin } = await loadFixture(deployFixture);
      expect(await contract.roles(admin.address)).to.equal(Role.Admin);
    });

    it("lets the admin assign roles and emits RoleChanged", async function () {
      const { contract, admin, outsider } = await loadFixture(deployFixture);
      await expect(contract.setUserRole(outsider.address, Role.Supplier))
        .to.emit(contract, "RoleChanged")
        .withArgs(outsider.address, Role.None, Role.Supplier, admin.address);
      expect(await contract.roles(outsider.address)).to.equal(Role.Supplier);
    });

    it("rejects role assignment by non-admins", async function () {
      const { contract, maker, outsider } = await loadFixture(deployFixture);
      await expect(contract.connect(maker).setUserRole(outsider.address, Role.Manufacturer))
        .to.be.revertedWithCustomError(contract, "NotAdmin")
        .withArgs(maker.address);
      await expect(contract.connect(outsider).setUserRole(outsider.address, Role.Admin))
        .to.be.revertedWithCustomError(contract, "NotAdmin");
    });

    it("lets a second admin manage roles and blocks changing your own role", async function () {
      const { contract, admin, outsider, maker } = await loadFixture(deployFixture);
      await contract.setUserRole(outsider.address, Role.Admin);
      await contract.connect(outsider).setUserRole(maker.address, Role.None);
      expect(await contract.roles(maker.address)).to.equal(Role.None);
      await expect(contract.setUserRole(admin.address, Role.None)).to.be.revertedWithCustomError(contract, "CannotChangeOwnRole");
      await expect(contract.setUserRole(ethers.ZeroAddress, Role.Supplier)).to.be.revertedWithCustomError(contract, "ZeroAddress");
    });
  });

  describe("registerProduct", function () {
    it("registers a product for a manufacturer", async function () {
      const { contract, maker } = await loadFixture(deployFixture);
      await expect(contract.connect(maker).registerProduct(PID, HASH))
        .to.emit(contract, "ProductRegistered")
        .withArgs(key(PID), PID, HASH, maker.address);

      const p = await contract.getProduct(PID);
      expect(p.exists).to.equal(true);
      expect(p.productId).to.equal(PID);
      expect(p.productHash).to.equal(HASH);
      expect(p.manufacturer).to.equal(maker.address);
      expect(p.currentHolder).to.equal(maker.address);
      expect(p.pendingRecipient).to.equal(ethers.ZeroAddress);
      expect(p.stage).to.equal(Stage.Manufactured);
      expect(p.registeredAt).to.be.greaterThan(0n);
      expect(await contract.productCount()).to.equal(1n);
    });

    it("rejects registration by non-manufacturers", async function () {
      const { contract, admin, supplier1, retailer, outsider } = await loadFixture(deployFixture);
      for (const signer of [admin, supplier1, retailer, outsider]) {
        await expect(contract.connect(signer).registerProduct(PID, HASH))
          .to.be.revertedWithCustomError(contract, "NotManufacturer")
          .withArgs(signer.address);
      }
    });

    it("rejects duplicate product IDs, even from another manufacturer", async function () {
      const { contract, maker, maker2 } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).registerProduct(PID, HASH))
        .to.be.revertedWithCustomError(contract, "ProductAlreadyExists")
        .withArgs(PID);
      await expect(contract.connect(maker2).registerProduct(PID, ethers.sha256("0x01")))
        .to.be.revertedWithCustomError(contract, "ProductAlreadyExists");
    });

    it("rejects an empty ID or zero hash", async function () {
      const { contract, maker } = await loadFixture(deployFixture);
      await expect(contract.connect(maker).registerProduct("", HASH)).to.be.revertedWithCustomError(contract, "EmptyProductId");
      await expect(contract.connect(maker).registerProduct(PID, ethers.ZeroHash)).to.be.revertedWithCustomError(contract, "InvalidHash");
    });

    it("returns exists=false for unknown products instead of reverting", async function () {
      const { contract } = await loadFixture(deployFixture);
      const p = await contract.getProduct("VT-UNKNOWN");
      expect(p.exists).to.equal(false);
      expect(p.stage).to.equal(Stage.None);
      expect(await contract.getHandoffHistory("VT-UNKNOWN")).to.have.length(0);
    });
  });

  describe("custody flow", function () {
    it("runs the full happy path M -> S1 -> S2 -> R -> Sold", async function () {
      const { contract, maker, supplier1, supplier2, retailer } = await loadFixture(registeredFixture);

      await expect(contract.connect(maker).initiateTransfer(PID, supplier1.address))
        .to.emit(contract, "TransferInitiated").withArgs(key(PID), PID, maker.address, supplier1.address);
      expect((await contract.getProduct(PID)).pendingRecipient).to.equal(supplier1.address);

      await expect(contract.connect(supplier1).confirmReceipt(PID))
        .to.emit(contract, "TransferReceived").withArgs(key(PID), PID, maker.address, supplier1.address, Stage.AtSupplier);

      await contract.connect(supplier1).initiateTransfer(PID, supplier2.address);
      await contract.connect(supplier2).confirmReceipt(PID);
      let p = await contract.getProduct(PID);
      expect(p.currentHolder).to.equal(supplier2.address);
      expect(p.stage).to.equal(Stage.AtSupplier);

      await contract.connect(supplier2).initiateTransfer(PID, retailer.address);
      await expect(contract.connect(retailer).confirmReceipt(PID))
        .to.emit(contract, "TransferReceived").withArgs(key(PID), PID, supplier2.address, retailer.address, Stage.AtRetailer);

      await expect(contract.connect(retailer).markSold(PID))
        .to.emit(contract, "ProductSold").withArgs(key(PID), PID, retailer.address);

      p = await contract.getProduct(PID);
      expect(p.stage).to.equal(Stage.Sold);
      expect(p.currentHolder).to.equal(retailer.address);
      expect(p.pendingRecipient).to.equal(ethers.ZeroAddress);
    });

    it("only lets the pending recipient confirm", async function () {
      const { contract, maker, supplier1, supplier2, retailer } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      for (const signer of [supplier2, retailer, maker]) {
        await expect(contract.connect(signer).confirmReceipt(PID))
          .to.be.revertedWithCustomError(contract, "NotPendingRecipient")
          .withArgs(signer.address, supplier1.address);
      }
    });

    it("rejects confirm when nothing is pending", async function () {
      const { contract, supplier1 } = await loadFixture(registeredFixture);
      await expect(contract.connect(supplier1).confirmReceipt(PID)).to.be.revertedWithCustomError(contract, "NoPendingTransfer");
    });

    it("rejects transfers by anyone other than the current holder", async function () {
      const { contract, maker2, supplier1, supplier2 } = await loadFixture(registeredFixture);
      await expect(contract.connect(supplier1).initiateTransfer(PID, supplier2.address))
        .to.be.revertedWithCustomError(contract, "NotCurrentHolder");
      await expect(contract.connect(maker2).initiateTransfer(PID, supplier1.address))
        .to.be.revertedWithCustomError(contract, "NotCurrentHolder");
    });

    it("rejects Manufacturer -> Retailer directly", async function () {
      const { contract, maker, retailer } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).initiateTransfer(PID, retailer.address))
        .to.be.revertedWithCustomError(contract, "InvalidTransition")
        .withArgs(Stage.Manufactured, Role.Retailer);
    });

    it("rejects transfers to the wrong role", async function () {
      const { contract, maker, maker2, supplier1, outsider, admin } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).initiateTransfer(PID, maker2.address))
        .to.be.revertedWithCustomError(contract, "InvalidTransition").withArgs(Stage.Manufactured, Role.Manufacturer);
      await expect(contract.connect(maker).initiateTransfer(PID, outsider.address))
        .to.be.revertedWithCustomError(contract, "InvalidTransition").withArgs(Stage.Manufactured, Role.None);

      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(supplier1).confirmReceipt(PID);
      // Supplier -> manufacturer / admin / unknown address are all rejected
      for (const target of [maker, admin, outsider]) {
        await expect(contract.connect(supplier1).initiateTransfer(PID, target.address))
          .to.be.revertedWithCustomError(contract, "InvalidTransition");
      }
    });

    it("rejects transfer to self, to the zero address, and a second pending transfer", async function () {
      const { contract, maker, supplier1, supplier2 } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).initiateTransfer(PID, maker.address)).to.be.revertedWithCustomError(contract, "CannotTransferToSelf");
      await expect(contract.connect(maker).initiateTransfer(PID, ethers.ZeroAddress)).to.be.revertedWithCustomError(contract, "ZeroAddress");
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await expect(contract.connect(maker).initiateTransfer(PID, supplier2.address))
        .to.be.revertedWithCustomError(contract, "TransferAlreadyPending").withArgs(supplier1.address);
    });

    it("rejects confirm when the recipient's role was revoked meanwhile", async function () {
      const { contract, maker, supplier1 } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.setUserRole(supplier1.address, Role.None);
      await expect(contract.connect(supplier1).confirmReceipt(PID)).to.be.revertedWithCustomError(contract, "InvalidTransition");
    });

    it("rejects actions by a holder whose role was revoked", async function () {
      const { contract, maker, supplier1 } = await loadFixture(registeredFixture);
      await contract.setUserRole(maker.address, Role.None);
      await expect(contract.connect(maker).initiateTransfer(PID, supplier1.address))
        .to.be.revertedWithCustomError(contract, "CallerRoleMismatch").withArgs(Role.Manufacturer, Role.None);
    });

    it("rejects every action after Sold", async function () {
      const { contract, maker, supplier1, retailer } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(supplier1).confirmReceipt(PID);
      await contract.connect(supplier1).initiateTransfer(PID, retailer.address);
      await contract.connect(retailer).confirmReceipt(PID);
      await contract.connect(retailer).markSold(PID);

      await expect(contract.connect(retailer).markSold(PID)).to.be.revertedWithCustomError(contract, "ProductAlreadySold").withArgs(PID);
      await expect(contract.connect(retailer).initiateTransfer(PID, supplier1.address))
        .to.be.revertedWithCustomError(contract, "InvalidTransition").withArgs(Stage.Sold, Role.Supplier);
      await expect(contract.connect(retailer).confirmReceipt(PID)).to.be.revertedWithCustomError(contract, "NoPendingTransfer");
      await expect(contract.connect(retailer).cancelTransfer(PID)).to.be.revertedWithCustomError(contract, "NoPendingTransfer");
    });

    it("only lets a retailer holding the product at AtRetailer mark it sold", async function () {
      const { contract, maker, supplier1, retailer } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).markSold(PID)).to.be.revertedWithCustomError(contract, "NotRetailer");
      await expect(contract.connect(retailer).markSold(PID)).to.be.revertedWithCustomError(contract, "NotCurrentHolder");
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(supplier1).confirmReceipt(PID);
      await expect(contract.connect(supplier1).markSold(PID)).to.be.revertedWithCustomError(contract, "NotRetailer");
    });

    it("rejects actions on unknown products", async function () {
      const { contract, maker, supplier1 } = await loadFixture(deployFixture);
      await expect(contract.connect(maker).initiateTransfer("NOPE", supplier1.address))
        .to.be.revertedWithCustomError(contract, "ProductNotFound").withArgs("NOPE");
      await expect(contract.connect(supplier1).confirmReceipt("NOPE")).to.be.revertedWithCustomError(contract, "ProductNotFound");
      await expect(contract.connect(maker).markSold("NOPE")).to.be.revertedWithCustomError(contract, "ProductNotFound");
    });
  });

  describe("cancelTransfer", function () {
    it("lets the holder cancel a pending transfer and re-send", async function () {
      const { contract, maker, supplier1, supplier2 } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await expect(contract.connect(maker).cancelTransfer(PID))
        .to.emit(contract, "TransferCancelled").withArgs(key(PID), PID, maker.address, supplier1.address);

      const p = await contract.getProduct(PID);
      expect(p.pendingRecipient).to.equal(ethers.ZeroAddress);
      expect(p.currentHolder).to.equal(maker.address);
      await expect(contract.connect(supplier1).confirmReceipt(PID)).to.be.revertedWithCustomError(contract, "NoPendingTransfer");

      await contract.connect(maker).initiateTransfer(PID, supplier2.address);
      await contract.connect(supplier2).confirmReceipt(PID);
      expect((await contract.getProduct(PID)).currentHolder).to.equal(supplier2.address);
    });

    it("rejects cancel by non-holders and when nothing is pending", async function () {
      const { contract, maker, supplier1 } = await loadFixture(registeredFixture);
      await expect(contract.connect(maker).cancelTransfer(PID)).to.be.revertedWithCustomError(contract, "NoPendingTransfer");
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await expect(contract.connect(supplier1).cancelTransfer(PID)).to.be.revertedWithCustomError(contract, "NotCurrentHolder");
    });
  });

  describe("history", function () {
    it("records every event in order with correct parties and stages", async function () {
      const { contract, maker, supplier1, supplier2, retailer } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(maker).cancelTransfer(PID);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(supplier1).confirmReceipt(PID);
      await contract.connect(supplier1).initiateTransfer(PID, supplier2.address);
      await contract.connect(supplier2).confirmReceipt(PID);
      await contract.connect(supplier2).initiateTransfer(PID, retailer.address);
      await contract.connect(retailer).confirmReceipt(PID);
      await contract.connect(retailer).markSold(PID);

      const h = await contract.getHandoffHistory(PID);
      const simplified = h.map((x) => [x.eventType, x.from, x.to, x.stageAfter]);
      expect(simplified).to.deep.equal([
        [BigInt(EventType.Registered), maker.address, maker.address, BigInt(Stage.Manufactured)],
        [BigInt(EventType.TransferInitiated), maker.address, supplier1.address, BigInt(Stage.Manufactured)],
        [BigInt(EventType.TransferCancelled), maker.address, supplier1.address, BigInt(Stage.Manufactured)],
        [BigInt(EventType.TransferInitiated), maker.address, supplier1.address, BigInt(Stage.Manufactured)],
        [BigInt(EventType.Received), maker.address, supplier1.address, BigInt(Stage.AtSupplier)],
        [BigInt(EventType.TransferInitiated), supplier1.address, supplier2.address, BigInt(Stage.AtSupplier)],
        [BigInt(EventType.Received), supplier1.address, supplier2.address, BigInt(Stage.AtSupplier)],
        [BigInt(EventType.TransferInitiated), supplier2.address, retailer.address, BigInt(Stage.AtSupplier)],
        [BigInt(EventType.Received), supplier2.address, retailer.address, BigInt(Stage.AtRetailer)],
        [BigInt(EventType.Sold), retailer.address, ethers.ZeroAddress, BigInt(Stage.Sold)],
      ]);
      for (let i = 1; i < h.length; i++) {
        expect(h[i].timestamp).to.be.greaterThanOrEqual(h[i - 1].timestamp);
      }
    });

    it("emits exactly one event per handoff, in the same order", async function () {
      const { contract, maker, supplier1 } = await loadFixture(registeredFixture);
      await contract.connect(maker).initiateTransfer(PID, supplier1.address);
      await contract.connect(supplier1).confirmReceipt(PID);
      const logs = await ethers.provider.getLogs({ address: await contract.getAddress(), topics: [null, key(PID)], fromBlock: 0 });
      const names = logs.map((l) => contract.interface.parseLog(l).name);
      expect(names).to.deep.equal(["ProductRegistered", "TransferInitiated", "TransferReceived"]);
      expect(await contract.getHandoffHistory(PID)).to.have.length(3);
    });
  });
});
