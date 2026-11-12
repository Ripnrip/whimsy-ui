import { createRequire } from "module";
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const core = require("./crumple-core.js");
const here = dirname(fileURLToPath(import.meta.url));
const golden = JSON.parse(readFileSync(join(here, "crumple-golden.json"), "utf8"));
const card = core.rect(...golden.card);
let failed = 0;

function close(a, b, label) {
  if (Math.abs(a - b) > 1e-5) {
    console.error(`${label}: ${a} != ${b}`);
    failed += 1;
    return false;
  }
  return true;
}

const light = core.unitLight();
close(light.x, golden.light[0], "light.x");
close(light.y, golden.light[1], "light.y");
close(light.z, golden.light[2], "light.z");

for (const sample of golden.samples) {
  const got = core.sample(card, sample.shape);
  if (got.vertices.length !== sample.vertices.length) {
    console.error(`shape ${sample.shape} vertex count`);
    failed += 1;
    continue;
  }
  got.vertices.forEach((v, i) => {
    close(v.x, sample.vertices[i][0], `s${sample.shape} v${i}.x`);
    close(v.y, sample.vertices[i][1], `s${sample.shape} v${i}.y`);
    close(v.z, sample.vertices[i][2], `s${sample.shape} v${i}.z`);
  });
  got.facets.forEach((f, i) => close(f.shade, sample.shades[i], `s${sample.shape} shade ${i}`));
  const folds = core.foldAngles(got);
  if (folds.length !== golden.edgeCount) {
    console.error(`edge count ${folds.length}`);
    failed += 1;
  }
  folds.forEach((angle, i) => close(angle, sample.folds[i], `s${sample.shape} fold ${i}`));
}

const bin = core.rect(...golden.bin);
const model = core.createModel(card, bin);
model.begin(card.center);
const axis = core.sub2(bin.center, card.center);
const creases = model.drag(core.add2(card.center, axis));
const same = creases.length === golden.gesture.creases.length
  && creases.every((id, i) => id === golden.gesture.creases[i]);
if (!same) {
  console.error("crease ids differ", creases, golden.gesture.creases);
  failed += 1;
}
if (model.end() !== golden.gesture.committed) {
  console.error("commit mismatch");
  failed += 1;
}

if (failed) {
  console.error(`${failed} parity mismatches`);
  process.exit(1);
}
console.log(`parity ok: ${golden.samples.length} shapes, ${golden.gesture.creases.length} creases, 40 triangles`);
