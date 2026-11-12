// Headless Chrome capture of the canvas port: GIF frames plus a contact sheet.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const framesDir = "/tmp/tiltscatter-frames";
rmSync(framesDir, { recursive: true, force: true });
mkdirSync(framesDir, { recursive: true });

const server = spawn("python3", ["-m", "http.server", "8766", "--bind", "127.0.0.1"], {
  cwd: here, stdio: "ignore",
});
const chrome = spawn("google-chrome", [
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--disable-dev-shm-usage",
  "--hide-scrollbars",
  "--user-data-dir=/tmp/chrome-tiltscatter",
  "--remote-debugging-port=9334",
  "--window-size=360,600",
  "--force-device-scale-factor=2",
  "about:blank",
], { stdio: "ignore" });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function debuggerUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await fetch("http://127.0.0.1:9334/json/version").then((r) => r.json());
      if (list.webSocketDebuggerUrl) return list.webSocketDebuggerUrl;
    } catch { /* chrome still booting */ }
    await sleep(150);
  }
  throw new Error("Chrome debugger did not come up");
}

function cdp(ws) {
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (ev) => {
    const text = typeof ev.data === "string" ? ev.data : ev.data.toString();
    const msg = JSON.parse(text);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
    }
  });
  return (method, params = {}) => new Promise((resolve, reject) => {
    const n = ++id;
    pending.set(n, { resolve, reject });
    ws.send(JSON.stringify({ id: n, method, params }));
  });
}

const browser = new WebSocket(await debuggerUrl());
await new Promise((resolve, reject) => {
  browser.addEventListener("open", resolve);
  browser.addEventListener("error", reject);
});
const browserSend = cdp(browser);
const { targetId } = await browserSend("Target.createTarget", {
  url: "http://127.0.0.1:8766/tiltscatter.html?t=0",
});
const { sessionId } = await browserSend("Target.attachToTarget", { targetId, flatten: true });

function sessionSend(method, params = {}) {
  return browserSend("Target.sendMessageToTarget", {
    sessionId,
    message: JSON.stringify({ id: method, method, params }),
  });
}

// Flattened sessions arrive as Target.receivedMessageFromTarget. Use a dedicated map.
const sessionPending = new Map();
let sessionSeq = 0;
browser.addEventListener("message", (ev) => {
  const text = typeof ev.data === "string" ? ev.data : ev.data.toString();
  const msg = JSON.parse(text);
  if (msg.method === "Target.receivedMessageFromTarget" || msg.method === "Target.dispatchMessage") {
    // unused when flatten is true: responses come back with sessionId on the browser socket
  }
  if (msg.sessionId && msg.id && sessionPending.has(msg.id)) {
    const { resolve, reject } = sessionPending.get(msg.id);
    sessionPending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
});

function pageSend(method, params = {}) {
  const n = ++sessionSeq;
  return new Promise((resolve, reject) => {
    sessionPending.set(n, { resolve, reject });
    browser.send(JSON.stringify({ id: n, sessionId, method, params }));
  });
}

await pageSend("Page.enable");
await pageSend("Runtime.enable");
await pageSend("Emulation.setDeviceMetricsOverride", {
  width: 360, height: 600, deviceScaleFactor: 2, mobile: false,
});
await sleep(400);
await pageSend("Runtime.evaluate", {
  expression: "document.fonts.ready.then(() => true)",
  awaitPromise: true,
});

async function shoot(name, seconds) {
  const result = await pageSend("Runtime.evaluate", {
    expression: `window.renderTime(${seconds})`,
    returnByValue: true,
  });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  const shot = await pageSend("Page.captureScreenshot", {
    format: "png",
    clip: { x: 0, y: 0, width: 360, height: 600, scale: 1 },
    captureBeyondViewport: false,
  });
  const path = join(framesDir, name);
  writeFileSync(path, Buffer.from(shot.data, "base64"));
  return path;
}

const times = [];
for (let i = 0; i <= 72; i++) times.push(Number((i / 10).toFixed(2)));
for (let i = 0; i < times.length; i++) {
  await shoot(`frame_${String(i).padStart(3, "0")}.png`, times[i]);
  if (i % 12 === 0) console.log(`frame ${i} t=${times[i]}`);
}

const stills = [
  ["still_rest.png", 0.2],
  ["still_dissolve.png", 0.9],
  ["still_tumble.png", 1.55],
  ["still_tip_right.png", 3.3],
  ["still_tip_back.png", 4.55],
  ["still_restored.png", 6.7],
];
for (const [name, t] of stills) {
  await shoot(name, t);
  console.log("still", name, t);
}

browser.close();
chrome.kill("SIGKILL");
server.kill("SIGKILL");
console.log("frames in", framesDir);
