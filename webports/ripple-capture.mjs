// Build the preview GIF and the stills contact sheet from ripple-core.js.
// Python only paints the two card faces. Every sample coordinate comes from the core.
import { createRequire } from "module";
import { fileURLToPath } from "url";
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import path from "path";

const require = createRequire(import.meta.url);
const C = require("./ripple-core.js");

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dir = mkdtempSync(path.join(tmpdir(), "ripple-"));
const painted = spawnSync("python3", [path.join(root, "webports", "render_card.py"), dir], { encoding: "utf8" });
if (painted.status !== 0) {
  console.error(painted.stderr || painted.stdout);
  process.exit(painted.status || 1);
}
const meta = JSON.parse(readFileSync(path.join(dir, "meta.json"), "utf8"));
const W = meta.width;
const H = meta.height;
const tap = meta.tap;
const shown = readFileSync(path.join(dir, "shown.rgb"));
const hidden = readFileSync(path.join(dir, "hidden.rgb"));

function blend(amount) {
  const out = Buffer.alloc(W * H * 3);
  const a = Math.min(1, Math.max(0, amount));
  for (let i = 0; i < out.length; i++) {
    out[i] = Math.round(shown[i] * (1 - a) + hidden[i] * a);
  }
  return out;
}

function sample(src, x, y) {
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x > W - 1) x = W - 1;
  if (y > H - 1) y = H - 1;
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const x1 = Math.min(x0 + 1, W - 1);
  const y1 = Math.min(y0 + 1, H - 1);
  const wx = x - x0;
  const wy = y - y0;
  const i00 = (y0 * W + x0) * 3;
  const i10 = (y0 * W + x1) * 3;
  const i01 = (y1 * W + x0) * 3;
  const i11 = (y1 * W + x1) * 3;
  const rgb = [0, 0, 0];
  for (let c = 0; c < 3; c++) {
    const top = src[i00 + c] * (1 - wx) + src[i10 + c] * wx;
    const bot = src[i01 + c] * (1 - wx) + src[i11 + c] * wx;
    rgb[c] = Math.round(top * (1 - wy) + bot * wy);
  }
  return rgb;
}

function distort(src, time, amplitude) {
  if (!(amplitude !== 0) || !(time > 0)) return Buffer.from(src);
  const out = Buffer.alloc(src.length);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const p = C.samplePosition({ x, y }, tap, time, amplitude);
      const rgb = sample(src, p.x, p.y);
      const i = (y * W + x) * 3;
      out[i] = rgb[0];
      out[i + 1] = rgb[1];
      out[i + 2] = rgb[2];
    }
  }
  return out;
}

function frameFrom(model) {
  const src = blend(C.maskAmount(model));
  return distort(src, C.shaderTime(model), C.shaderAmplitude(model));
}

const model = C.createModel({});
const frames = [];
function hold(n) {
  const frame = frameFrom(model);
  for (let i = 0; i < n; i++) frames.push(frame);
}
function trip() {
  frames.push(frameFrom(model));
  let guard = 0;
  while ((model.phase === "hiding" || model.phase === "revealing") && guard++ < 40) {
    C.advance(model, 1 / 12);
    frames.push(frameFrom(model));
  }
}

hold(5);
C.toggle(model, tap, 72);
trip();
hold(6);
C.toggle(model, tap, 72);
trip();
hold(5);

function still(spec) {
  const m = C.createModel({ reduceMotion: !!spec.reduce });
  if (spec.hidden && !spec.elapsed && !spec.reveal) {
    C.toggle(m, tap, 72);
    C.advance(m, C.RULES.duration);
    return frameFrom(m);
  }
  if (spec.reveal) {
    C.toggle(m, tap, 72);
    C.advance(m, C.RULES.duration);
    C.toggle(m, tap, 72);
  } else if (spec.elapsed || spec.reduce) {
    C.toggle(m, tap, 72);
  }
  if (spec.elapsed) C.advance(m, spec.elapsed);
  return frameFrom(m);
}

const stills = [
  { image: still({}), caption: "Shown" },
  { image: still({ elapsed: 0.18 }), caption: "Ripple, digits" },
  { image: still({ elapsed: 0.52 }), caption: "Halfway, dots" },
  { image: still({ hidden: true }), caption: "Hidden" },
  { image: still({ reveal: true, elapsed: 0.55 }), caption: "Ripple returns" },
  { image: still({ reduce: true, elapsed: 0.14 }), caption: "Reduce Motion" },
];

writeFileSync(path.join(dir, "movie.rgb"), Buffer.concat(frames));
stills.forEach((stillFrame, index) => writeFileSync(path.join(dir, `still${index}.rgb`), stillFrame.image));

const artifacts = process.env.RIPPLE_ARTIFACTS || "/opt/cursor/artifacts";
mkdirSync(artifacts, { recursive: true });
const docsGif = path.join(root, "docs", "ripple.gif");
const artifactGif = path.join(artifacts, "ripple_to_hide_preview.gif");
const artifactSheet = path.join(artifacts, "ripple_to_hide_stills.png");

function ffmpeg(args) {
  const result = spawnSync("ffmpeg", ["-y", ...args], { encoding: "utf8" });
  if (result.status !== 0) {
    console.error(result.stderr);
    process.exit(result.status || 1);
  }
}

ffmpeg([
  "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${W}x${H}`, "-r", "12",
  "-i", path.join(dir, "movie.rgb"),
  "-vf", "split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
  docsGif,
]);

const sheetPy = `
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
meta = json.loads(Path(sys.argv[1]).read_text())
W, H = meta["width"], meta["height"]
captions = json.loads(Path(sys.argv[2]).read_text())
label_h = 36
sheet = Image.new("RGB", (W * len(captions), H + label_h), (240, 232, 214))
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf", 16)
for i, caption in enumerate(captions):
    raw = Path(sys.argv[1]).parent.joinpath(f"still{i}.rgb").read_bytes()
    panel = Image.frombytes("RGB", (W, H), raw)
    sheet.paste(panel, (i * W, 0))
    tw = draw.textlength(caption, font=font)
    draw.text((i * W + (W - tw) / 2, H + 8), caption, font=font, fill=(36, 48, 42))
sheet.save(sys.argv[3])
`;
writeFileSync(path.join(dir, "sheet.py"), sheetPy);
writeFileSync(path.join(dir, "captions.json"), JSON.stringify(stills.map((s) => s.caption)));
const sheet = spawnSync("python3", [path.join(dir, "sheet.py"), path.join(dir, "meta.json"), path.join(dir, "captions.json"), artifactSheet], { encoding: "utf8" });
if (sheet.status !== 0) {
  console.error(sheet.stderr || sheet.stdout);
  process.exit(sheet.status || 1);
}
spawnSync("cp", [docsGif, artifactGif]);
console.log("wrote", docsGif);
console.log("wrote", artifactGif);
console.log("wrote", artifactSheet);
console.log("frames", frames.length, "tap", JSON.stringify(tap));
