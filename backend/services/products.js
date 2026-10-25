// Product registration and read models (shared by routes and the seed script).
const store = require("./firestore");
const blockchain = require("./blockchain");
const wallets = require("./wallets");
const { computeProductHash } = require("./hashing");
const { buildPayload } = require("./qr");
const { productView, journeyView } = require("./productView");
const { AppError, conflict, notFound } = require("../utils/errors");

const CATEGORIES = Object.freeze([
  "Electronics",
  "Pharmaceuticals",
  "Apparel",
  "Cosmetics",
  "Food & Beverage",
  "Automotive Parts",
  "Luxury Goods",
  "Other",
]);

async function nextFreeProductId() {
  for (let i = 0; i < 20; i++) {
    const candidate = await store.allocateProductId();
    const onChain = await blockchain.getProduct(candidate);
    if (!onChain.exists) return candidate;
  }
  throw new AppError(500, "ID_ALLOCATION_FAILED", "Could not allocate a free product ID. Run `npm run reset-demo` to resync.");
}

/** Registers on-chain (signed by the manufacturer's wallet), then stores the metadata in Firestore. */
async function registerProduct(user, input) {
  let productId = input.productId;
  if (productId) {
    if (await store.getProduct(productId)) throw conflict("DUPLICATE_PRODUCT", `Product ID ${productId} already exists.`);
  } else {
    productId = await nextFreeProductId();
  }

  const metadata = {
    productId,
    name: input.name,
    brand: input.brand,
    category: input.category,
    batchNumber: input.batchNumber,
    serialNumber: input.serialNumber || null,
    manufactureDate: input.manufactureDate,
    expiryDate: input.expiryDate || null,
    mrp: input.mrp ?? null,
    countryOfOrigin: input.countryOfOrigin || "India",
    description: input.description || null,
    manufacturerId: user.uid,
    manufacturerName: user.displayName,
  };
  const hash = computeProductHash(metadata);
  const { txHash, blockNumber } = await blockchain.registerProduct(wallets.walletForUser(user), productId, hash);

  const doc = { ...metadata, hash, registerTxHash: txHash, blockNumber, createdAt: store.nowIso() };
  await store.saveProduct(productId, doc);
  await store.addAudit({ action: "REGISTER_PRODUCT", actorUid: user.uid, actorRole: user.role, productId, txHash, blockNumber });
  return { product: doc, qrPayload: buildPayload(productId, hash) };
}

async function viewsFor(docs) {
  const book = await store.getAddressBook();
  const chainProducts = await Promise.all(docs.map((d) => blockchain.getProduct(d.productId)));
  return docs.map((d, i) => productView(d, chainProducts[i], book));
}

const listForManufacturer = async (uid) => viewsFor(await store.listProducts({ manufacturerId: uid }));
const listAll = async () => viewsFor(await store.listProducts());

/** Chain products (e.g. from transfer queues) merged with their Firestore metadata. */
async function viewsForChainProducts(chainProducts) {
  const [docs, book] = await Promise.all([store.getProductsByIds(chainProducts.map((p) => p.productId)), store.getAddressBook()]);
  return chainProducts.map((p) => productView(docs.get(p.productId) || null, p, book));
}

async function getDetail(productId) {
  const [chainProduct, metadata] = await Promise.all([blockchain.getProduct(productId), store.getProduct(productId)]);
  if (!chainProduct.exists && !metadata) throw notFound("PRODUCT_NOT_FOUND", `Product ${productId} was not found.`);
  const book = await store.getAddressBook();
  const history = chainProduct.exists ? await blockchain.getHistory(productId) : { handoffs: [] };
  const info = blockchain.getContractInfo();
  return {
    product: productView(metadata, chainProduct, book),
    journey: journeyView(history.handoffs, book),
    qrPayload: chainProduct.exists ? buildPayload(productId, chainProduct.productHash) : null,
    technical: {
      contractAddress: info.address,
      chainId: info.chainId,
      network: info.network,
      productHash: chainProduct.exists ? chainProduct.productHash : null,
      registerTxHash: metadata?.registerTxHash || history.handoffs[0]?.txHash || null,
      registerBlock: metadata?.blockNumber ?? history.handoffs[0]?.blockNumber ?? null,
    },
  };
}

async function getQrPayload(productId) {
  const chainProduct = await blockchain.getProduct(productId);
  if (!chainProduct.exists) throw notFound("PRODUCT_NOT_FOUND", `Product ${productId} is not registered on the blockchain.`);
  const metadata = await store.getProduct(productId);
  return {
    productId,
    name: metadata?.name || null,
    hash: chainProduct.productHash,
    payload: buildPayload(productId, chainProduct.productHash),
  };
}

module.exports = { CATEGORIES, registerProduct, listForManufacturer, listAll, viewsForChainProducts, getDetail, getQrPayload };
