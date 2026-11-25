// Renders docs/liquidrepdial.gif and docs/liquidrepdial-stills.png from the canvas port.
// Requires puppeteer-core and a system Chrome. Serves the repo so the module script loads.
//   NODE_PATH=/tmp/node-tools/node_modules node webports/liquidrepdial-capture.mjs
import { createServer } from "node:http";
import { readFileSync, mkdirSync, copyFileSync } from "node:fs";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import puppeteer from "puppeteer-core";

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
await page.setViewport({ width: 460, height: 920, deviceScaleFactor: 1 });
await page.goto(`http://127.0.0.1:${port}/webports/liquidrepdial.html?drive=1`, { waitUntil: "networkidle0" });
await page.waitForFunction(() => window.__ready === true);

const duration = await page.evaluate(() => window.__demoDuration);
const fps = 16;
const frames = Math.round(duration * fps);
const dir = "/tmp/liquidrepdial-frames";
mkdirSync(dir, { recursive: true });

for (let i = 0; i < frames; i += 1) {
  const t = i / fps;
  await page.evaluate((time) => window.renderAt(time), t);
  const canvas = await page.$("#stage");
  await canvas.screenshot({ path: `${dir}/frame_${String(i).padStart(4, "0")}.png` });
}

const gif = join(root, "docs/liquidrepdial.gif");
await new Promise((resolve, reject) => {
  const child = spawn("ffmpeg", [
    "-y", "-framerate", String(fps), "-i", `${dir}/frame_%04d.png`,
    "-vf", "fps=16,scale=390:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff:max_colors=192[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
    gif,
  ], { stdio: "inherit" });
  child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg ${code}`))));
});

const sheet = await page.evaluate(() => window.renderSheet());
await page.setViewport({ width: Math.ceil(sheet.width) + 40, height: Math.ceil(sheet.height) + 40, deviceScaleFactor: 2 });
const sheetCanvas = await page.$("#sheet");
const stills = join(root, "docs/liquidrepdial-stills.png");
await sheetCanvas.screenshot({ path: stills });

const artifacts = "/opt/cursor/artifacts";
mkdirSync(artifacts, { recursive: true });
copyFileSync(gif, join(artifacts, "liquidrepdial.gif"));
copyFileSync(stills, join(artifacts, "liquidrepdial-stills.png"));

console.log(`gif ${gif}`);
console.log(`stills ${stills} ${sheet.width}x${sheet.height}`);
await browser.close();
server.close();
