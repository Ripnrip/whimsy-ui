// Port of SlatSyncCore. Keep the numbers in step with Sources/SlatSyncCore.
// goldenTrace() must match Tests/SlatSyncCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  canvasWidth: 390,
  canvasHeight: 844,
  slatCount: 11,
  coreRadius: 2,
  slatWidth: 332,
  slatHeight: 26,
  slatGap: 8,
  stackTop: 176,
  cornerRadius: 4,
  edgeThickness: 1,
  spreadFloor: 0.22,
  spreadCeil: 1,
  reachStart: 2.45,
  reachEnd: 6.2,
  reachFeather: 0.85,
  maxAttitude: 0.55,
  rollTravel: 40,
  pitchBow: 0.55,
  demoDelay: 0.35,
  demoRun: 3.5,
  title: "Halo Vault",
  subtitle: "Studio library",
  detail: "1,284 files · 3 devices",
  syncing: "Syncing…",
  synced: "All synced",
  cobalt: { red: 47 / 255, green: 92 / 255, blue: 1 },
  teal: { red: 32 / 255, green: 214 / 255, blue: 206 / 255 },
  lime: { red: 184 / 255, green: 1, blue: 74 / 255 },
  tealStop: 0.42,
  backgroundTop: { red: 7 / 255, green: 6 / 255, blue: 22 / 255 },
  backgroundBottom: { red: 12 / 255, green: 8 / 255, blue: 32 / 255 },
  muted: { red: 196 / 255, green: 194 / 255, blue: 210 / 255 },
  edgeBase: 0.22,
  edgeGain: 0.78,
};

export const DEMO_DURATION = TUNING.demoDelay + TUNING.demoRun + 0.95;

function u32(n) {
  return n >>> 0;
}

export function unit(index, salt) {
  let z = u32(Math.imul(index, 0x9e3779b1));
  z = u32(z + u32(Math.imul(salt, 0x85ebca77)));
  z = u32(z + 0xa11ce5d3);
  z = u32(z ^ (z >>> 16));
  z = u32(Math.imul(z, 0x7feb352d));
  z = u32(z ^ (z >>> 15));
  z = u32(Math.imul(z, 0x846ca68b));
  z = u32(z ^ (z >>> 16));
  return z / 4294967295;
}

export function unitProgress(progress) {
  if (!Number.isFinite(progress)) return 0;
  return Math.min(Math.max(progress, 0), 1);
}

export function percent(progress) {
  if (!Number.isFinite(progress)) return 0;
  const scaled = unitProgress(progress) * 100 + 1e-8;
  const rounded = Math.round(scaled);
  return Math.min(100, Math.max(0, rounded));
}

export function label(pct) {
  return pct >= 100 ? TUNING.synced : TUNING.syncing;
}

export function voiceOver(pct) {
  return pct >= 100 ? TUNING.synced : `Syncing, ${pct} percent`;
}

export function crossedHundred(previous, next) {
  return percent(previous) < 100 && percent(next) >= 100;
}

export function smoothstep(a, b, x) {
  let t;
  if (a === b) t = x < a ? 0 : 1;
  else t = Math.min(Math.max((x - a) / (b - a), 0), 1);
  return t * t * (3 - 2 * t);
}

export function easeInOutCubic(t) {
  const u = Math.min(Math.max(t, 0), 1);
  if (u < 0.5) return 4 * u * u * u;
  const v = 2 - 2 * u;
  return 1 - (v * v * v) / 2;
}

export function frame(index) {
  const y = TUNING.stackTop + index * (TUNING.slatHeight + TUNING.slatGap);
  const x = (TUNING.canvasWidth - TUNING.slatWidth) / 2;
  return { x, y, width: TUNING.slatWidth, height: TUNING.slatHeight };
}

export function optics(index) {
  if (index < 0 || index >= TUNING.slatCount) {
    return { index, blur: 0, offsetX: 0, tilt: 0 };
  }
  const dist = Math.abs(index - 5) / 5;
  const u = unit(index, 1);
  const v = unit(index, 2);
  const w = unit(index, 3);
  const signV = v < 0.5 ? -1 : 1;
  const signW = w < 0.5 ? -1 : 1;
  const blur = 3.2 + dist * 14 + (u - 0.5) * 1.2;
  const offsetX = signV * (4 + dist * 16) * (0.65 + 0.35 * v);
  const tilt = signW * (0.35 + dist * 4.4) * (0.7 + 0.3 * w);
  return { index, blur, offsetX, tilt };
}

export function spread(index, progress) {
  if (index < 0 || index >= TUNING.slatCount) return 0;
  if (!Number.isFinite(progress)) return 0;
  const p = Math.min(Math.max(progress, 0), 1);
  const dist = Math.abs(index - 5);
  const reach = TUNING.reachStart + (TUNING.reachEnd - TUNING.reachStart) * p;
  const gate = smoothstep(reach, reach - TUNING.reachFeather, dist);
  const base = TUNING.spreadFloor + (TUNING.spreadCeil - TUNING.spreadFloor) * p;
  const taper = 1 - 0.1 * (dist / 5) * (1 - 0.65 * p);
  return Math.min(Math.max(base * taper * gate, 0), 1);
}

function lerpColor(a, b, t) {
  const u = Math.min(Math.max(t, 0), 1);
  return {
    red: a.red + (b.red - a.red) * u,
    green: a.green + (b.green - a.green) * u,
    blue: a.blue + (b.blue - a.blue) * u,
  };
}

export function color(index) {
  if (index < 0 || index >= TUNING.slatCount) return { ...TUNING.cobalt };
  if (index === 0) return { ...TUNING.cobalt };
  if (index === TUNING.slatCount - 1) return { ...TUNING.lime };
  const t = index / (TUNING.slatCount - 1);
  if (t <= TUNING.tealStop) return lerpColor(TUNING.cobalt, TUNING.teal, t / TUNING.tealStop);
  return lerpColor(TUNING.teal, TUNING.lime, (t - TUNING.tealStop) / (1 - TUNING.tealStop));
}

export function wobble(index, roll, pitch, reduceMotion) {
  if (reduceMotion || !Number.isFinite(roll) || !Number.isFinite(pitch)) return { offsetX: 0, tilt: 0 };
  if (index < 0 || index >= TUNING.slatCount) return { offsetX: 0, tilt: 0 };
  const clampedRoll = Math.min(Math.max(roll, -TUNING.maxAttitude), TUNING.maxAttitude);
  const clampedPitch = Math.min(Math.max(pitch, -TUNING.maxAttitude), TUNING.maxAttitude);
  const lever = (index - 5) / 5;
  const depth = 0.4 + 0.6 * Math.abs(lever);
  const offsetX = clampedRoll * TUNING.rollTravel * depth;
  const tilt = -clampedPitch * (180 / Math.PI) * TUNING.pitchBow * lever;
  return { offsetX, tilt };
}

export function demoProgress(time) {
  if (!Number.isFinite(time)) return 0;
  const t = Math.max(time, 0);
  if (t <= TUNING.demoDelay) return 0;
  const u = Math.min(1, (t - TUNING.demoDelay) / TUNING.demoRun);
  return easeInOutCubic(u);
}

export function scene(progress, roll = 0, pitch = 0, reduceMotion = false) {
  const unitValue = unitProgress(progress);
  const pct = percent(progress);
  const name = label(pct);
  const reveal = reduceMotion ? 1 : unitValue;
  const opacity = reduceMotion ? unitValue : 1;
  const bands = [];
  for (let index = 0; index < TUNING.slatCount; index += 1) {
    const box = frame(index);
    const reed = optics(index);
    const extra = wobble(index, roll, pitch, reduceMotion);
    const width = spread(index, reveal);
    const ink = color(index);
    const edge = TUNING.edgeBase + TUNING.edgeGain * width * opacity;
    bands.push({
      index,
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
      blur: reed.blur,
      offsetX: reed.offsetX + extra.offsetX,
      tilt: reed.tilt + extra.tilt,
      spread: width,
      red: ink.red,
      green: ink.green,
      blue: ink.blue,
      edge,
      opacity,
    });
  }
  return { progress: unitValue, percent: pct, label: name, voiceOver: voiceOver(pct), opacity, bands };
}

export function createMonitor(progress = 0) {
  return { progress: unitProgress(progress), hapticCount: 0 };
}

export function setProgress(monitor, next) {
  if (!Number.isFinite(next)) return false;
  const fired = crossedHundred(monitor.progress, next);
  monitor.progress = unitProgress(next);
  if (fired) monitor.hapticCount += 1;
  return fired;
}

export function fmt(x) {
  if (!Number.isFinite(x)) return "nan";
  const negative = x < 0;
  const rounded = Math.floor(Math.abs(x) * 100000000 + 0.5);
  let whole = Math.floor(rounded / 100000000);
  let frac = Math.round(rounded - whole * 100000000);
  if (frac >= 100000000) {
    frac -= 100000000;
    whole += 1;
  }
  return `${negative ? "-" : ""}${whole}.${String(frac).padStart(8, "0")}`;
}

export function goldenTrace() {
  const lines = ["v1", `slats ${TUNING.slatCount}`];
  for (let index = 0; index < TUNING.slatCount; index += 1) {
    const reed = optics(index);
    lines.push(`o ${index} ${fmt(reed.blur)} ${fmt(reed.offsetX)} ${fmt(reed.tilt)}`);
  }
  for (let index = 0; index < TUNING.slatCount; index += 1) {
    const ink = color(index);
    lines.push(`c ${index} ${fmt(ink.red)} ${fmt(ink.green)} ${fmt(ink.blue)}`);
  }
  const samples = [0, 0.25, 0.42, 0.5, 0.75, 0.994, 0.995, 1, -0.2, 1.4];
  for (const progress of samples) {
    for (let index = 0; index < TUNING.slatCount; index += 1) {
      lines.push(`s ${fmt(progress)} ${index} ${fmt(spread(index, progress))}`);
    }
    const pct = percent(progress);
    lines.push(`pct ${fmt(progress)} ${pct} ${label(pct)} ${voiceOver(pct)}`);
  }
  lines.push(`pct nan ${percent(Number.NaN)} ${voiceOver(0)}`);

  const monitor = createMonitor();
  for (const next of [0.2, 0.42, 0.994, 0.995, 1, 1, 0.4, 1]) {
    const fired = setProgress(monitor, next);
    lines.push(`h ${fmt(next)} ${fired ? 1 : 0} ${monitor.hapticCount}`);
  }

  const attitudes = [
    [0.2, 0, false],
    [0, 0.3, false],
    [2, -2, false],
    [0.2, 0.3, true],
    [Number.NaN, 0.2, false],
  ];
  for (const [roll, pitch, reduced] of attitudes) {
    for (let index = 0; index < TUNING.slatCount; index += 1) {
      const extra = wobble(index, roll, pitch, reduced);
      lines.push(`w ${index} ${fmt(roll)} ${fmt(pitch)} ${reduced ? 1 : 0} ${fmt(extra.offsetX)} ${fmt(extra.tilt)}`);
    }
  }
  for (let index = 0; index < TUNING.slatCount; index += 1) {
    const box = frame(index);
    lines.push(`l ${index} ${fmt(box.x)} ${fmt(box.y)} ${fmt(box.width)} ${fmt(box.height)}`);
  }
  const scenes = [
    [0, 0, 0, false],
    [0.42, 0.15, -0.1, false],
    [1, 0.2, 0.1, false],
    [0.5, 0.4, 0.2, true],
  ];
  for (const [progress, roll, pitch, reduced] of scenes) {
    const shot = scene(progress, roll, pitch, reduced);
    lines.push(`scene ${fmt(progress)} ${fmt(roll)} ${fmt(pitch)} ${reduced ? 1 : 0} ${shot.percent} ${shot.label}`);
    for (const band of shot.bands) {
      lines.push([
        `b ${band.index}`, fmt(band.spread), fmt(band.blur), fmt(band.offsetX),
        fmt(band.tilt), fmt(band.edge), fmt(band.opacity),
        fmt(band.red), fmt(band.green), fmt(band.blue),
      ].join(" "));
    }
  }
  for (const time of [0, 0.35, 0.5, 2.1, 3.85, 4, Number.NaN]) {
    lines.push(`demo ${fmt(time)} ${fmt(demoProgress(time))}`);
  }
  lines.push(`copy ${TUNING.title} | ${TUNING.subtitle} | ${TUNING.syncing} | ${TUNING.synced} | ${TUNING.detail}`);
  return `${lines.join("\n")}\n`;
}

export const STILLS = [0, 0.25, 0.5, 0.75, 1];
