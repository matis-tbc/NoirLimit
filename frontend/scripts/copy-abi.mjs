import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const contractsOut = resolve(root, "../contracts/out");
const abiDir = resolve(root, "src/abi");

mkdirSync(abiDir, { recursive: true });

const sources = [
  ["PokerTable.sol/PokerTable.json", "PokerTable.json"],
  ["SpectatorMarket.sol/SpectatorMarket.json", "SpectatorMarket.json"],
];

for (const [src, dst] of sources) {
  const srcPath = resolve(contractsOut, src);
  if (!existsSync(srcPath)) {
    console.warn(`[copy-abi] missing ${srcPath} — skipping`);
    continue;
  }
  const artifact = JSON.parse(readFileSync(srcPath, "utf8"));
  const slim = { abi: artifact.abi };
  writeFileSync(resolve(abiDir, dst), JSON.stringify(slim, null, 2));
  console.log(`[copy-abi] wrote src/abi/${dst}`);
}
