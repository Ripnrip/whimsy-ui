import { createRequire } from "module";
import { fileURLToPath } from "url";
const require = createRequire(import.meta.url);
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const C = require("./crumple-core.js");

const W = 360;
const H = 240;
const card = C.rect(40, 50, 180, 120);
const bin = C.rect(270, 78, 52, 58);

function buffer() {
  const data = Buffer.alloc(W * H * 3);
  for (let i = 0; i < W * H; i++) {
    data[i * 3] = 0x24;
    data[i * 3 + 1] = 0x21;
    data[i * 3 + 2] = 0x1c;
  }
  return data;
}

function put(data, x, y, r, g, b, a = 1) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  data[i] = Math.round(data[i] * (1 - a) + r * a);
  data[i + 1] = Math.round(data[i + 1] * (1 - a) + g * a);
  data[i + 2] = Math.round(data[i + 2] * (1 - a) + b * a);
}

function fillRect(data, x, y, w, h, color) {
  for (let yy = y; yy < y + h; yy++) {
    for (let xx = x; xx < x + w; xx++) put(data, xx, yy, color[0], color[1], color[2], color[3] ?? 1);
  }
}

function fillTri(data, a, b, c, color) {
  const minX = Math.max(0, Math.floor(Math.min(a.x, b.x, c.x)));
  const maxX = Math.min(W - 1, Math.ceil(Math.max(a.x, b.x, c.x)));
  const minY = Math.max(0, Math.floor(Math.min(a.y, b.y, c.y)));
  const maxY = Math.min(H - 1, Math.ceil(Math.max(a.y, b.y, c.y)));
  const area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
  if (Math.abs(area) < 1e-6) return;
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const w0 = ((b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)) / area;
      const w1 = ((c.x - b.x) * (y - b.y) - (c.y - b.y) * (x - b.x)) / area;
      const w2 = 1 - w0 - w1;
      if (w0 >= -0.001 && w1 >= -0.001 && w2 >= -0.001) put(data, x, y, color[0], color[1], color[2], color[3] ?? 1);
    }
  }
}

function drawBin(data, lid) {
  fillRect(data, bin.x, bin.y + 8, bin.width, bin.height - 8, [58, 60, 64]);
  const hinge = { x: bin.x, y: bin.y + 8 };
  const open = lid;
  const lidW = bin.width;
  const lidH = 8;
  const corners = [
    hinge,
    { x: hinge.x + lidW, y: hinge.y },
    { x: hinge.x + lidW, y: hinge.y - lidH * Math.cos(open) },
    { x: hinge.x, y: hinge.y - lidH * Math.cos(open) - lidW * Math.sin(open) * 0 },
  ];
  // A simple raised lid: a quad tilted back by `open` radians.
  const far = lidW * Math.sin(open);
  const up = lidH + lidW * 0.15 * Math.sin(open);
  fillTri(data, { x: bin.x, y: bin.y + 8 }, { x: bin.x + bin.width, y: bin.y + 8 }, { x: bin.x + bin.width, y: bin.y + 8 - up }, [150, 154, 160]);
  fillTri(data, { x: bin.x, y: bin.y + 8 }, { x: bin.x + bin.width, y: bin.y + 8 - up }, { x: bin.x - far * 0.2, y: bin.y + 8 - up }, [170, 174, 180]);
}

function drawCardFace(data, alpha, scale) {
  const w = card.width * scale;
  const h = card.height * scale;
  const x = card.center.x - w / 2;
  const y = card.center.y - h / 2;
  fillRect(data, x, y, w, h, [250, 246, 232, alpha]);
}

function drawMesh(data, shape, origin, alpha) {
  const sampled = C.sample(card, shape);
  const shift = { x: origin.x - card.center.x, y: origin.y - card.center.y };
  for (const facet of sampled.facets) {
    const pts = [facet.i0, facet.i1, facet.i2].map((index) => {
      const v = sampled.vertices[index];
      return { x: v.x + shift.x, y: v.y + shift.y };
    });
    const color = facet.color.map((c) => Math.round(c * 255));
    fillTri(data, pts[0], pts[1], pts[2], [color[0], color[1], color[2], alpha]);
  }
}

function bezier(t) {
  const start = card.center;
  const end = bin.center;
  const seg = C.sub2(end, start);
  const len = Math.hypot(seg.x, seg.y);
  const n = len > 1e-9 ? { x: -seg.y / len, y: seg.x / len } : { x: 0, y: -1 };
  const control = {
    x: start.x + seg.x * 0.5 + n.x * len * C.RULES.tossControl,
    y: start.y + seg.y * 0.5 + n.y * len * C.RULES.tossControl,
  };
  const u = Math.min(1, Math.max(0, t));
  const a = { x: start.x + (control.x - start.x) * u, y: start.y + (control.y - start.y) * u };
  const b = { x: control.x + (end.x - control.x) * u, y: control.y + (end.y - control.y) * u };
  return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u };
}

function scene({ shape = 0, origin = card.center, face = 1, scale = 1, lid = 0, mesh = true }) {
  const data = buffer();
  drawBin(data, lid);
  if (face > 0.01) drawCardFace(data, face, scale);
  if (mesh && shape > 0.01) drawMesh(data, shape, origin, Math.min(1, shape + 0.15));
  return data;
}

const stills = [
  scene({ shape: 0, face: 1, mesh: false }),
  scene({ shape: 0.4, face: 0.6, mesh: true }),
  scene({ shape: 0.8, face: 0.2, mesh: true }),
  scene({ shape: 1, origin: bezier(0.45), face: 0, mesh: true, lid: 0.4 }),
  scene({ shape: 1, origin: bin.center, face: 0, mesh: true, lid: 0.9 }),
  scene({ shape: 0, face: 0.55, scale: 0.9, mesh: false }),
];

const frames = [];
for (let i = 0; i <= 16; i++) {
  const p = i / 16;
  frames.push(scene({ shape: p * 0.9, face: 1 - p * 0.9, mesh: true }));
}
for (let i = 1; i <= 14; i++) {
  const t = i / 14;
  const overshoot = t < 0.35 ? 1 + 0.08 * Math.sin(t / 0.35 * Math.PI) : 1;
  frames.push(scene({ shape: overshoot, origin: bezier(t), face: 0, mesh: true, lid: 0.2 + t * 0.6 }));
}
for (let i = 0; i < 6; i++) {
  frames.push(scene({ shape: 1, origin: bin.center, face: 0, mesh: true, lid: 0.9 - i * 0.08 }));
}

const dir = fs.mkdtempSync(path.join(require("os").tmpdir(), "crumple-"));
function writeRaw(file, data) { fs.writeFileSync(file, data); }

stills.forEach((data, i) => writeRaw(path.join(dir, `still${i}.rgb`), data));
frames.forEach((data, i) => writeRaw(path.join(dir, `f${String(i).padStart(3, "0")}.rgb`), data));

const sheet = Buffer.alloc(W * stills.length * H * 3);
stills.forEach((data, index) => {
  for (let y = 0; y < H; y++) {
    data.copy(sheet, (y * stills.length * W + index * W) * 3, y * W * 3, (y + 1) * W * 3);
  }
});
writeRaw(path.join(dir, "sheet.rgb"), sheet);

const movie = Buffer.concat(frames);
writeRaw(path.join(dir, "movie.rgb"), movie);

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const docsGif = path.join(repo, "docs", "crumple.gif");
const artifacts = process.env.CRUMPLE_ARTIFACTS || "/opt/cursor/artifacts";
fs.mkdirSync(artifacts, { recursive: true });
fs.mkdirSync(path.dirname(docsGif), { recursive: true });

function ffmpeg(args) {
  const result = spawnSync("ffmpeg", ["-y", ...args], { encoding: "utf8" });
  if (result.status !== 0) {
    console.error(result.stderr);
    process.exit(result.status || 1);
  }
}

ffmpeg(["-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${W}x${H}`, "-r", "16",
  "-i", path.join(dir, "movie.rgb"),
  "-vf", "split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse", docsGif]);
ffmpeg(["-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${W * stills.length}x${H}`,
  "-i", path.join(dir, "sheet.rgb"), path.join(artifacts, "crumple-stills.png")]);
fs.copyFileSync(docsGif, path.join(artifacts, "crumple.gif"));
console.log("wrote", docsGif);
console.log("wrote", path.join(artifacts, "crumple.gif"));
console.log("wrote", path.join(artifacts, "crumple-stills.png"));
