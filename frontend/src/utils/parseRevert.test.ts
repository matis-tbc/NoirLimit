import { describe, it, expect } from "vitest";
import { parseRevert } from "./parseRevert";

describe("parseRevert", () => {
  it("prefers shortMessage when present", () => {
    const err = {
      shortMessage: "public key already registered",
      details: "details text",
      message: "message text",
    };
    expect(parseRevert(err)).toEqual({
      reason: "public key already registered",
      specific: true,
    });
  });

  it("falls back to details when shortMessage is absent", () => {
    const err = { details: "execution reverted: not your turn" };
    expect(parseRevert(err).reason).toBe(
      "execution reverted: not your turn"
    );
  });

  it("reads cause.reason when top-level fields are missing", () => {
    const err = { cause: { reason: "hole card duplicates community" } };
    expect(parseRevert(err).reason).toBe("hole card duplicates community");
  });

  it("reads cause.data.args[0] for viem's structured error", () => {
    const err = {
      cause: {
        data: { args: ["bad shuffle proof", 42] },
      },
    };
    expect(parseRevert(err).reason).toBe("bad shuffle proof");
  });

  it("reads metaMessages first string", () => {
    const err = {
      metaMessages: [undefined, "simulated revert: deadline passed", "extra"],
    };
    expect(parseRevert(err).reason).toBe("simulated revert: deadline passed");
  });

  it("falls back to the first line of message", () => {
    const err = { message: "ContractFunctionExecutionError:\nsecond line" };
    expect(parseRevert(err).reason).toBe("ContractFunctionExecutionError:");
  });

  it("returns the generic fallback and specific=false when nothing parses", () => {
    expect(parseRevert(null)).toEqual({
      reason: "Proof rejected on-chain",
      specific: false,
    });
    expect(parseRevert({})).toEqual({
      reason: "Proof rejected on-chain",
      specific: false,
    });
    expect(parseRevert(42 as unknown)).toEqual({
      reason: "Proof rejected on-chain",
      specific: false,
    });
  });
});
