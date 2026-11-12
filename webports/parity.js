// Compare the JS port's canonical trace to the Swift core's. Numbers may differ by
// at most 1e-5; labels and line counts must match exactly.
const fs = require("fs");
const RB = require("./rubber-core.js");

const swiftPath = process.argv[2];
const jsPath = process.argv[3];
if (!swiftPath) {
  console.error("usage: node parity.js swift.txt [js-out.txt]");
  process.exit(2);
}
const js = RB.canonicalTrace();
if (jsPath) fs.writeFileSync(jsPath, js);
const swift = fs.readFileSync(swiftPath, "utf8");
const a = swift.split("\n");
const b = js.split("\n");
if (a.length !== b.length) {
  console.error("line count swift", a.length, "js", b.length);
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) { console.error("first text mismatch", i + 1, "\nS", a[i], "\nJ", b[i]); break; }
  process.exit(1);
}
let numeric = 0;
let worst = 0;
for (let i = 0; i < a.length; i++) {
  if (a[i] === b[i]) continue;
  const as = a[i].split(" ");
  const bs = b[i].split(" ");
  if (as.length !== bs.length) {
    console.error("shape mismatch line", i + 1, "\nS", a[i], "\nJ", b[i]);
    process.exit(1);
  }
  for (let k = 0; k < as.length; k++) {
    if (as[k] === bs[k]) continue;
    const x = Number(as[k]);
    const y = Number(bs[k]);
    if (!Number.isFinite(x) || !Number.isFinite(y) || Math.abs(x - y) > 1e-5) {
      console.error("mismatch line", i + 1, "token", k, "\nS", a[i], "\nJ", b[i]);
      process.exit(1);
    }
    numeric += 1;
    worst = Math.max(worst, Math.abs(x - y));
  }
}
console.log("parity ok", a.length - 1, "lines,", numeric, "tokens within 1e-5, worst", worst);
