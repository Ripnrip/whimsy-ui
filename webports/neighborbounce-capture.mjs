// Headless Chrome capture of the Neighbor Bounce canvas port: GIF frames, stills, contact sheet.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const framesDir = "/tmp/neighborbounce-frames";
rmSync(framesDir, { recursive: true, force: true });
mkdirSync(framesDir, { recursive: true });

const server = spawn("python3", ["-m", "http.server", "8767", "--bind", "127.0.0.1"], {
  cwd: here, stdio: "ignore",
});
const chrome = spawn("google-chrome", [
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--disable-dev-shm-usage",
  "--hide-scrollbars",
  "--user-data-dir=/tmp/chrome-neighborbounce",
  "--remote-debugging-port=9335",
  "--window-size=420,480",
  "--force-device-scale-factor=2",
  "about:blank",
], { stdio: "ignore" });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function debuggerUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await fetch("http://127.0.0.1:9335/json/version").then((r) => r.json());
      if (list.webSocketDebuggerUrl) return list.webSocketDebuggerUrl;
    } catch { /* chrome still booting */ }
    await sleep(150);
  }
  throw new Error("Chrome debugger did not come up");
}

const browser = new WebSocket(await debuggerUrl());
await new Promise((resolve, reject) => {
  browser.addEventListener("open", resolve);
  browser.addEventListener("error", reject);
});

let nextId = 0;
const pending = new Map();
browser.addEventListener("message", (ev) => {
  const text = typeof ev.data === "string" ? ev.data : ev.data.toString();
  const msg = JSON.parse(text);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
});

function browserSend(method, params = {}, sessionId) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    browser.send(JSON.stringify(payload));
  });
}

const { targetId } = await browserSend("Target.createTarget", {
  url: "http://127.0.0.1:8767/neighborbounce.html?t=0",
});
const { sessionId } = await browserSend("Target.attachToTarget", { targetId, flatten: true });
const pageSend = (method, params = {}) => browserSend(method, params, sessionId);

await pageSend("Page.enable");
await pageSend("Runtime.enable");
await pageSend("Emulation.setDeviceMetricsOverride", {
  width: 420, height: 480, deviceScaleFactor: 2, mobile: false,
});
await sleep(300);

async function shoot(name, seconds) {
  const result = await pageSend("Runtime.evaluate", {
    expression: `window.renderTime(${seconds})`,
    returnByValue: true,
  });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  const shot = await pageSend("Page.captureScreenshot", {
    format: "png",
    clip: { x: 0, y: 0, width: 420, height: 480, scale: 1 },
    captureBeyondViewport: false,
  });
  const path = join(framesDir, name);
  writeFileSync(path, Buffer.from(shot.data, "base64"));
  return path;
}

const times = [];
for (let i = 0; i <= 54; i++) times.push(Number((i / 12).toFixed(4)));
for (let i = 0; i < times.length; i++) {
  await shoot(`frame_${String(i).padStart(3, "0")}.png`, times[i]);
  if (i % 12 === 0) console.log(`frame ${i} t=${times[i]}`);
}

const stills = [
  ["still_rest.png", 0.12],
  ["still_rise.png", 0.48],
  ["still_peak.png", 0.68],
  ["still_rapid.png", 2.18],
  ["still_return.png", 3.05],
  ["still_settled.png", 4.35],
];
for (const [name, t] of stills) {
  await shoot(name, t);
  console.log("still", name, t);
}

browser.close();
chrome.kill("SIGKILL");
server.kill("SIGKILL");
console.log("frames in", framesDir);
