// Compares the JS port's golden trace to the Swift fixture.
// Run from the repo root: node webports/verify-velocityglyph.mjs
import { readFileSync } from "node:fs";
import { TUNING, VelocityGlyphModel, goldenTrace, makeSpan } from "./velocityglyph-core.mjs";

const fixturePath = new URL("../Tests/VelocityGlyphCoreTests/Fixtures/golden-trace.txt", import.meta.url);
const expected = readFileSync(fixturePath, "utf8");
const got = goldenTrace();

if (got === expected) {
  const lines = got.trim().split("\n");
  console.log(`exact match: ${lines.length} lines`);
}

const wide = makeSpan(-TUNING.domain, TUNING.domain, 1);
const wideModel = new VelocityGlyphModel({ value: 123, lower: -TUNING.domain, upper: TUNING.domain, step: 1 });
const domainOk = wide.snap(123) === 123
  && wide.snap(-456) === -456
  && wide.valueAtFraction(0) === -TUNING.domain
  && wide.valueAtFraction(1) === TUNING.domain
  && wideModel.value === 123;
if (!domainOk) {
  console.log("full-domain snap diverged", {
    snap123: wide.snap(123),
    top: wide.valueAtFraction(1),
    model: wideModel.value,
  });
  process.exit(1);
}
console.log("full-domain step indices preserved");
if (got === expected) process.exit(0);

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
  if (mismatches <= 8) {
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
console.log(`mismatched lines: ${mismatches}`);
console.log(`max abs numeric delta: ${maxAbs} (${worst})`);
process.exit(mismatches === 0 ? 0 : 1);
