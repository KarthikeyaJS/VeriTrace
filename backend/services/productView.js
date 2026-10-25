// Shapes chain + Firestore data into the JSON the app renders (product cards, journeys).

const STAGE_LABELS = {
  None: "Unknown",
  Manufactured: "At manufacturer",
  AtSupplier: "At supplier",
  AtRetailer: "At retailer",
  Sold: "Sold",
};

const EVENT_LABELS = {
  Registered: "Registered on blockchain",
  TransferInitiated: "Dispatched",
  Received: "Received",
  TransferCancelled: "Transfer cancelled",
  Sold: "Sold to customer",
};

const shortAddress = (a) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : null);

function party(address, book) {
  if (!address) return null;
  const known = book && book.get(address.toLowerCase());
  return {
    address,
    uid: known ? known.uid : null,
    name: known ? known.displayName : `Unknown wallet ${shortAddress(address)}`,
    role: known ? known.role : null,
  };
}

const PRODUCT_FIELDS = [
  "productId",
  "name",
  "brand",
  "category",
  "batchNumber",
  "serialNumber",
  "manufactureDate",
  "expiryDate",
  "mrp",
  "countryOfOrigin",
  "description",
  "manufacturerId",
  "manufacturerName",
  "hash",
  "registerTxHash",
  "blockNumber",
  "createdAt",
];

/** Product details (Firestore) merged with live on-chain state. Either side may be missing. */
function productView(metadata, chainProduct, book) {
  const view = {};
  for (const f of PRODUCT_FIELDS) view[f] = metadata && metadata[f] !== undefined ? metadata[f] : null;
  view.productId = view.productId || (chainProduct && chainProduct.productId) || null;
  view.metadataMissing = !metadata;
  if (chainProduct && chainProduct.exists) {
    view.onChain = true;
    view.stage = chainProduct.stage;
    view.stageLabel = STAGE_LABELS[chainProduct.stage] || chainProduct.stage;
    view.chain = {
      productHash: chainProduct.productHash,
      registeredAt: new Date(chainProduct.registeredAt * 1000).toISOString(),
      manufacturer: party(chainProduct.manufacturer, book),
      currentHolder: party(chainProduct.currentHolder, book),
      pendingRecipient: party(chainProduct.pendingRecipient, book),
    };
    if (!view.manufacturerName && view.chain.manufacturer) view.manufacturerName = view.chain.manufacturer.name;
  } else {
    view.onChain = false;
    view.stage = null;
    view.stageLabel = "Not on blockchain";
    view.chain = null;
  }
  return view;
}

function journeyView(handoffs, book) {
  return handoffs.map((h, i) => ({
    index: i,
    eventType: h.eventType,
    label: EVENT_LABELS[h.eventType] || h.eventType,
    stageAfter: h.stageAfter,
    stageLabel: STAGE_LABELS[h.stageAfter] || h.stageAfter,
    from: party(h.from, book),
    to: h.eventType === "Registered" || h.eventType === "Sold" ? null : party(h.to, book),
    timestamp: new Date(h.timestamp * 1000).toISOString(),
    txHash: h.txHash,
    blockNumber: h.blockNumber,
  }));
}

module.exports = { STAGE_LABELS, EVENT_LABELS, party, productView, journeyView };
