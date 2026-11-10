import { createRequire } from "module";
import { fileURLToPath } from "url";
import { writeFileSync, readFileSync } from "fs";
import path from "path";

const require = createRequire(import.meta.url);
const C = require("./ripple-core.js");

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const goldenPath = path.join(root, "webports", "ripple-golden.json");

const rules = C.RULES;
const displacements = [];
for (let t = 0; t <= 0.9 + 1e-9; t += 0.1) {
  for (let d = 0; d <= 200; d += 10) {
    displacements.push({ d, t: round(t), v: C.displacement(d, round(t), rules) });
  }
}
displacements.push({ d: 40, t: 0, v: C.displacement(40, 0, rules) });
displacements.push({ d: 40, t: -0.2, v: C.displacement(40, -0.2, rules) });

const samples = [];
const points = [
  [80, 60, 20, 30, 0.37, 14],
  [20, 30, 20, 30, 0.4, 14],
  [200, 90, 40, 50, 0.15, 14],
  [10, 10, 140, 80, 0.9, 14],
  [90, 20, 10, 20, 0, 14],
];
for (const [x, y, tapX, tapY, time, amplitude] of points) {
  const s = C.samplePosition({ x, y }, { x: tapX, y: tapY }, time, amplitude, rules);
  samples.push({ x, y, tapX, tapY, time, amplitude, sx: s.x, sy: s.y });
}

const masks = ["$4,820.16", "1 284,50 €", "-£42", "USD 12", "", "hello"].map((input) => ({
  input,
  output: C.mask(input),
}));

const bounds = { minX: 0, minY: 0, maxX: 300, maxY: 188 };
const reach = rules.speed * rules.duration;
const pass = {
  reach,
  fromCenter: C.passRadius({ x: 150, y: 94 }, bounds, reach),
  fromCorner: C.passRadius({ x: 0, y: 0 }, bounds, reach),
};

const golden = {
  rules,
  displacements,
  samples,
  masks,
  pass,
  full: C.trace(false),
  reduced: C.trace(true),
};

const text = JSON.stringify(golden);
writeFileSync(goldenPath, text);
const roundTrip = JSON.parse(readFileSync(goldenPath, "utf8"));
if (roundTrip.full.length !== golden.full.length) {
  console.error("golden round trip lost steps");
  process.exit(1);
}
console.log(`wrote ${goldenPath}`);
console.log(`displacements ${displacements.length}, full steps ${golden.full.length}, reduced steps ${golden.reduced.length}`);

function round(x) {
  return Math.round(x * 1e9) / 1e9;
}
