// Compares the JS port's golden trace to the Swift fixture.
// Run from the repo root: node webports/verify-glassmorph.mjs
import { readFileSync } from "node:fs";
import { goldenTrace } from "./glassmorph-core.mjs";

const fixturePath = new URL("../Tests/GlassMorphCoreTests/Fixtures/golden-trace.txt", import.meta.url);
const expected = readFileSync(fixturePath, "utf8");
const got = goldenTrace();

if (got === expected) {
  const lines = got.trim().split("\n");
  console.log(`exact match: ${lines.length} lines`);
  process.exit(0);
}

const expLines = expected.split("\n");
const gotLines = got.split("\n");
let mismatches = 0;
let maxAbs = 0;
let worst = "";
const count = Math.max(expLines.length, gotLines.length);
for (let i = 0; i < count; i += 1) {
  const a = expLines[i] ?? "";
  const b = gotLines[i] ?? "";
  if (a === b) continue;
  mismatches += 1;
  if (mismatches <= 12) {
    console.log(`line ${i + 1}`);
    console.log(`  swift: ${a}`);
    console.log(`  js:    ${b}`);
  }
  const an = a.match(/-?\d+\.\d+/g) ?? [];
  const bn = b.match(/-?\d+\.\d+/g) ?? [];
  for (let n = 0; n < Math.max(an.length, bn.length); n += 1) {
    const delta = Math.abs(Number(an[n]) - Number(bn[n]));
    if (delta > maxAbs) {
      maxAbs = delta;
      worst = `line ${i + 1} field ${n}: ${an[n]} vs ${bn[n]}`;
    }
  }
}
console.log(`mismatched lines: ${mismatches} of ${count}`);
console.log(`max abs numeric delta: ${maxAbs} (${worst})`);
process.exit(1);
