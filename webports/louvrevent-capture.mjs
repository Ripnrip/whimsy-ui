// Renders docs/louvrevent.gif and docs/louvrevent-stills.png from the canvas port.
// The stage is 390×844. Requires puppeteer-core and a system Chrome.
//   node webports/louvrevent-capture.mjs
import { createServer } from "node:http";
import { readFileSync, copyFileSync, mkdirSync } from "node:fs";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const puppeteer = require("puppeteer-core");

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const chrome = process.env.CHROME || "/usr/local/bin/google-chrome";
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
await page.goto(`http://127.0.0.1:${port}/webports/louvrevent.html?drive=1`, { waitUntil: "networkidle0" });
await page.waitForFunction(() => window.__ready === true);

const duration = await page.evaluate(() => window.__demoDuration);
const fps = 20;
const frames = Math.round(duration * fps);
const dir = "/tmp/louvrevent-frames";
await new Promise((resolve, reject) => {
  const child = spawn("rm", ["-rf", dir]);
  child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error("rm"))));
});
await new Promise((resolve, reject) => {
  const child = spawn("mkdir", ["-p", dir]);
  child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error("mkdir"))));
});

for (let i = 0; i < frames; i += 1) {
  const t = i / fps;
  await page.evaluate((time) => window.renderAt(time), t);
  const canvas = await page.$("#stage");
  await canvas.screenshot({ path: `${dir}/frame_${String(i).padStart(4, "0")}.png` });
}

const gif = join(root, "docs/louvrevent.gif");
await new Promise((resolve, reject) => {
  const child = spawn("ffmpeg", [
    "-y", "-framerate", String(fps), "-i", `${dir}/frame_%04d.png`,
    "-vf", "fps=20,scale=390:844:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff:max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
    gif,
  ], { stdio: "inherit" });
  child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg ${code}`))));
});

const sheet = await page.evaluate(() => window.renderSheet());
await page.setViewport({
  width: Math.ceil(sheet.width) + 40,
  height: Math.ceil(sheet.height) + 40,
  deviceScaleFactor: 1,
});
const sheetCanvas = await page.$("#sheet");
const stills = join(root, "docs/louvrevent-stills.png");
await sheetCanvas.screenshot({ path: stills });

const artifacts = "/opt/cursor/artifacts";
mkdirSync(artifacts, { recursive: true });
copyFileSync(gif, join(artifacts, "louvrevent.gif"));
copyFileSync(stills, join(artifacts, "louvrevent-stills.png"));

console.log(`gif ${gif}`);
console.log(`stills ${stills} ${sheet.width}x${sheet.height}`);
await browser.close();
server.close();
