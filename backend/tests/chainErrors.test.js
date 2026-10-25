const { toAppError } = require("../services/blockchain");

const revert = (name, args = []) => Object.assign(new Error("execution reverted"), { code: "CALL_EXCEPTION", revert: { name, args } });

describe("contract error mapping", () => {
  test("InvalidTransition from AtSupplier to a manufacturer", () => {
    const e = toAppError(revert("InvalidTransition", [2n, 2n]));
    expect(e.status).toBe(422);
    expect(e.code).toBe("CHAIN_REJECTED");
    expect(e.details).toEqual({ onChain: true, reason: "InvalidTransition" });
    expect(e.message).toBe("A supplier can only send to another supplier or a retailer, not to a manufacturer.");
  });

  test("InvalidTransition manufacturer -> retailer", () => {
    expect(toAppError(revert("InvalidTransition", [1n, 4n])).message).toMatch(/only be sent to a supplier, not to a retailer/);
  });

  test("role and state errors map to 403 / 409", () => {
    expect(toAppError(revert("NotManufacturer", ["0x1"])).status).toBe(403);
    expect(toAppError(revert("ProductAlreadyExists", ["VT-1"])).message).toBe("Product ID VT-1 is already registered on the blockchain.");
    expect(toAppError(revert("ProductAlreadyExists", ["VT-1"])).status).toBe(409);
    expect(toAppError(revert("ProductAlreadySold", ["VT-1"])).status).toBe(409);
  });

  test("custom error name in the message is decoded as a fallback", () => {
    const e = toAppError(new Error("VM Exception while processing transaction: reverted with custom error 'NotRetailer(\"0x1\")'"));
    expect(e.details.reason).toBe("NotRetailer");
  });

  test("connection problems become CHAIN_UNAVAILABLE", () => {
    const e = toAppError(Object.assign(new Error("connect ECONNREFUSED 127.0.0.1:8545"), { code: "ECONNREFUSED" }));
    expect(e.status).toBe(503);
    expect(e.code).toBe("CHAIN_UNAVAILABLE");
  });

  test("BAD_DATA (no contract at address) suggests reset-demo", () => {
    const e = toAppError(Object.assign(new Error("could not decode result data"), { code: "BAD_DATA" }));
    expect(e.code).toBe("CONTRACT_NOT_FOUND");
    expect(e.message).toMatch(/reset-demo/);
  });
});
