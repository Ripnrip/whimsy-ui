// Compares the JavaScript port with the trace written by NeighborBounceCoreTests.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
require("./neighborbounce-core.js");

const swiftPath = process.argv[2] || "/tmp/neighborbounce-swift-trace.txt";
const swift = readFileSync(swiftPath, "utf8").trim().split("\n");
const js = globalThis.NeighborBounce.parityLines();

if (swift.length !== js.length) {
  console.error(`line count swift ${swift.length} js ${js.length}`);
  process.exit(1);
}
let mismatches = 0;
for (let i = 0; i < swift.length; i++) {
  if (swift[i] !== js[i]) {
    mismatches += 1;
    if (mismatches <= 3) {
      console.error(`mismatch at line ${i}`);
      const a = swift[i].split(" ");
      const b = js[i].split(" ");
      console.error(`  tokens ${a.length} vs ${b.length}`);
      const n = Math.max(a.length, b.length);
      for (let t = 0; t < n; t++) {
        if (a[t] !== b[t]) {
          console.error(`  token ${t}: ${a[t]} != ${b[t]}`);
          if (t > 12) break;
        }
      }
    }
  }
}
if (mismatches) {
  console.error(`${mismatches} mismatched lines out of ${swift.length}`);
  process.exit(1);
}
console.log(`parity ok: ${swift.length} lines, bit-identical`);
