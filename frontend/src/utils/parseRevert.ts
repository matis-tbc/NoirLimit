// Viem surfaces revert reasons inconsistently across error shapes. This
// helper tries each known location and falls back to a generic copy rather
// than leaving the UI saying "undefined". Centralized so CheatMoment,
// ActionBar, and botDriver all parse the same way.

export interface ParsedRevert {
  reason: string;
  // True when we found a specific message; false when we had to fall back
  // to the generic copy. Callers can choose to surface the raw error too.
  specific: boolean;
}

export function parseRevert(err: unknown): ParsedRevert {
  if (!err || typeof err !== "object") {
    return { reason: "Proof rejected on-chain", specific: false };
  }

  const e = err as Record<string, unknown>;

  const shortMessage = typeof e.shortMessage === "string" ? e.shortMessage : undefined;
  if (shortMessage) return { reason: shortMessage, specific: true };

  const details = typeof e.details === "string" ? e.details : undefined;
  if (details) return { reason: details, specific: true };

  const cause = e.cause as Record<string, unknown> | undefined;
  if (cause) {
    const causeReason = typeof cause.reason === "string" ? cause.reason : undefined;
    if (causeReason) return { reason: causeReason, specific: true };
    const causeShort = typeof cause.shortMessage === "string" ? cause.shortMessage : undefined;
    if (causeShort) return { reason: causeShort, specific: true };
    const data = cause.data as Record<string, unknown> | undefined;
    if (data) {
      const dataArgs = data.args as unknown[] | undefined;
      if (Array.isArray(dataArgs) && typeof dataArgs[0] === "string") {
        return { reason: dataArgs[0], specific: true };
      }
    }
  }

  const metaMessages = e.metaMessages as unknown[] | undefined;
  if (Array.isArray(metaMessages) && metaMessages.length > 0) {
    const first = metaMessages.find((m) => typeof m === "string") as string | undefined;
    if (first) return { reason: first, specific: true };
  }

  const message = typeof e.message === "string" ? e.message : undefined;
  if (message) {
    const firstLine = message.split("\n")[0];
    return { reason: firstLine, specific: true };
  }

  return { reason: "Proof rejected on-chain", specific: false };
}
