// Renders docs/grainbloom.gif and docs/grainbloom-stills.png from the canvas port.
// Requires puppeteer-core and a system Chrome. Serves the repo so the module script loads.
//   node webports/grainbloom-capture.mjs
import { createServer } from "node:http";
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";

const localPkg = fileURLToPath(new URL("../node_modules/puppeteer-core/package.json", import.meta.url));
const requireFrom = createRequire(existsSync(localPkg) ? localPkg : "/tmp/node-tools/package.json");
const puppeteer = requireFrom("puppeteer-core");

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const chrome = process.env.CHROME || "/usr/bin/google-chrome";
const types = { ".html": "text/html", ".mjs": "text/javascript", ".js": "text/javascript", ".png": "image/png" };

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const path = join(root, decodeURIComponent(url.pathname));
  try {
    const body = readFileSync(path);
    res.writeHead(200, { "content-type": types[extname(path)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("missing");
  }
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage", "--font-render-hinting=none"],
});
const page = await browser.newPage();
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
await page.goto(`http://127.0.0.1:${port}/webports/grainbloom.html?drive=1`, { waitUntil: "networkidle0" });
await page.waitForFunction(() => window.__ready === true);

const duration = await page.evaluate(() => window.__demoDuration);
const fps = 12;
const frames = Math.round(duration * fps);
const dir = "/tmp/grainbloom-frames";
await new Promise((resolve, reject) => {
  const child = spawn("rm", ["-rf", dir]);
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error("rm")));
});
await new Promise((resolve, reject) => {
  const child = spawn("mkdir", ["-p", dir]);
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error("mkdir")));
});

for (let i = 0; i < frames; i += 1) {
  const t = i / fps;
  await page.evaluate((time) => window.renderAt(time), t);
  const canvas = await page.$("#stage");
  await canvas.screenshot({ path: `${dir}/frame_${String(i).padStart(4, "0")}.png` });
}

const gif = join(root, "docs/grainbloom.gif");
await new Promise((resolve, reject) => {
  const child = spawn("ffmpeg", [
    "-y", "-framerate", String(fps), "-i", `${dir}/frame_%04d.png`,
    "-vf", "fps=12,scale=390:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff:max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
    gif,
  ], { stdio: "inherit" });
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`ffmpeg ${code}`)));
});

const stills = join(root, "docs/grainbloom-stills.png");
const shots = [
  [Math.round(0.15 * fps), "Idle"],
  [Math.round(0.85 * fps), "Waking"],
  [Math.round(2.1 * fps), "Resolving"],
  [Math.round(3.15 * fps), "Done"],
];
const font = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf";
const labeled = shots.map(([index, label], n) => {
  const src = `${dir}/frame_${String(index).padStart(4, "0")}.png`;
  const out = `${dir}/still_${n}.png`;
  return new Promise((resolve, reject) => {
    const child = spawn("ffmpeg", [
      "-y", "-i", src,
      "-vf", `pad=390:880:0:36:color=0x241c16,drawtext=fontfile=${font}:text='${label}':x=18:y=8:fontsize=18:fontcolor=0xf4edde`,
      "-update", "1",
      out,
    ], { stdio: "inherit" });
    child.on("exit", (code) => code === 0 ? resolve(out) : reject(new Error(`label ${code}`)));
  });
});
const stillFiles = await Promise.all(labeled);
await new Promise((resolve, reject) => {
  const child = spawn("ffmpeg", [
    "-y",
    ...stillFiles.flatMap((file) => ["-i", file]),
    "-filter_complex", "[0][1][2][3]hstack=inputs=4",
    "-update", "1",
    stills,
  ], { stdio: "inherit" });
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`sheet ${code}`)));
});

const artifacts = process.env.ARTIFACTS || "/opt/cursor/artifacts";
mkdirSync(artifacts, { recursive: true });
copyFileSync(gif, join(artifacts, "grainbloom.gif"));
copyFileSync(stills, join(artifacts, "grainbloom-stills.png"));
console.log(`gif ${gif}`);
console.log(`stills ${stills}`);
await browser.close();
server.close();
