import type { Address } from "viem";

// Client-side-only list of table IDs the user has hidden from the Lobby.
// Keyed by host address so each wallet keeps its own list. The table still
// exists on-chain; this only affects display.

const KEY_PREFIX = "noirlimit:hidden-tables:";

function keyFor(host: Address | undefined): string | null {
  if (!host) return null;
  return KEY_PREFIX + host.toLowerCase();
}

export function loadHidden(host: Address | undefined): Set<string> {
  const key = keyFor(host);
  if (!key) return new Set();
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return new Set();
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed.map(String));
  } catch {
    return new Set();
  }
}

export function hideTable(host: Address | undefined, tableId: bigint): Set<string> {
  const key = keyFor(host);
  const next = loadHidden(host);
  next.add(tableId.toString());
  if (key) localStorage.setItem(key, JSON.stringify([...next]));
  return next;
}

export function unhideAll(host: Address | undefined): Set<string> {
  const key = keyFor(host);
  if (key) localStorage.removeItem(key);
  return new Set();
}
