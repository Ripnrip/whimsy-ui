// Port of BoltStreakCore. Constants match BoltStreakTuning.swift.
// The golden trace matches Tests/BoltStreakCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  sceneWidth: 390,
  sceneHeight: 844,
  dayCount: 7,
  ignitionDuration: 0.64,
  maxFrame: 0.05,
  wordmark: "BOLT",
  caption: "THIS WEEK",
  ofSeven: "OF 7",
  wordmarkY: 86,
  captionY: 116,
  readoutY: 500,
  ofSevenY: 548,
  weeklyWidth: 150,
  weeklyHeight: 292,
  weeklyY: 150,
  weeklyStroke: 20,
  weeklyHead: 11,
  weeklyBevel: 2.2,
  dayWidth: 28,
  dayHeight: 74,
  dayStride: 48,
  dayOriginY: 592,
  dayStroke: 4.5,
  dayHead: 4,
  dayBevel: 0.8,
  labelGap: 18,
  hitSlop: 16,
  tiltDegrees: 22,
  tiltPerspective: 0.6,
  glowSettled: 0.62,
  glowPulse: 0.28,
  glowOmega: 18,
  glowBlur: 14,
  reflectionOpacity: 0.26,
  reflectionGap: 8,
  burnFrames: 39,
  backgroundTop: [0.09, 0.1, 0.11],
  backgroundBottom: [0.05, 0.05, 0.06],
  spill: [1, 0.62, 0.16],
  zinc: [0.42, 0.45, 0.48],
  zincHighlight: [0.75, 0.78, 0.82],
  zincShadow: [0.14, 0.15, 0.17],
  gold: [1, 0.76, 0.22],
  goldCore: [1, 0.94, 0.72],
  head: [1, 1, 1],
  labelDim: [0.55, 0.57, 0.6],
  labelLit: [1, 0.82, 0.42],
  wordmarkColor: [0.86, 0.88, 0.9],
  captionColor: [0.62, 0.58, 0.48],
  plate: [1, 1, 1],
  accessibilityLabel: "Weekly bolt streak",
  accessibilityHint: "Marks today and lights its bolt.",
  markTodayAction: "Mark today",
};

TUNING.dayRowWidth = TUNING.dayStride * (TUNING.dayCount - 1) + TUNING.dayWidth;
TUNING.dayOriginX = (TUNING.sceneWidth - TUNING.dayRowWidth) / 2;
TUNING.weeklyRect = {
  x: (TUNING.sceneWidth - TUNING.weeklyWidth) / 2,
  y: TUNING.weeklyY,
  width: TUNING.weeklyWidth,
  height: TUNING.weeklyHeight,
};

export const WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
export const WEEKDAY_LABELS = ["M", "T", "W", "T", "F", "S", "S"];
export const WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

const NORMALIZED = [
  { x: 0.72, y: 0.06 },
  { x: 0.3, y: 0.34 },
  { x: 0.78, y: 0.44 },
  { x: 0.22, y: 0.7 },
  { x: 0.58, y: 0.78 },
  { x: 0.18, y: 0.94 },
];

const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / (2 * Math.PI);

const REEL = {
  dt: 1 / 60,
  idleFrames: 30,
  gapFrames: 8,
  holdFrames: 24,
  reduceLead: 18,
  reduceMid: 24,
  reduceHold: 30,
  today: 6,
};

function clamp(x, lo, hi) {
  return Math.min(Math.max(x, lo), hi);
}

function clamp01(x) {
  return clamp(x, 0, 1);
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function progressBetween(x, a, b) {
  if (a === b) return x < a ? 0 : 1;
  return clamp01((x - a) / (b - a));
}

function smoothstep(a, b, x) {
  const t = progressBetween(x, a, b);
  return t * t * (3 - 2 * t);
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

function sin(x) {
  if (!Number.isFinite(x)) return 0;
  const k = Math.floor(x * INV_TWO_PI + 0.5);
  let r = x - k * TWO_PI;
  if (r > HALF_PI) r = PI - r;
  else if (r < -HALF_PI) r = -PI - r;
  const r2 = r * r;
  let p = 1 / 355687428096000;
  p = -1 / 1307674368000 + r2 * p;
  p = 1 / 6227020800 + r2 * p;
  p = -1 / 39916800 + r2 * p;
  p = 1 / 362880 + r2 * p;
  p = -1 / 5040 + r2 * p;
  p = 1 / 120 + r2 * p;
  p = -1 / 6 + r2 * p;
  p = 1 + r2 * p;
  return r * p;
}

function dist(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

export function scenePoints(rect) {
  return NORMALIZED.map((point) => ({
    x: rect.x + point.x * rect.width,
    y: rect.y + point.y * rect.height,
  }));
}

export function pathLength(rect) {
  const points = scenePoints(rect);
  let sum = 0;
  for (let index = 1; index < points.length; index += 1) sum += dist(points[index], points[index - 1]);
  return sum;
}

const UNIT = { x: 0, y: 0, width: 1, height: 1 };

export function sample(progress, rect = UNIT) {
  const points = scenePoints(rect);
  const first = points[0];
  if (!first) return { x: 0, y: 0 };
  if (points.length < 2) return first;
  const t = Number.isFinite(progress) ? clamp01(progress) : 0;
  if (t === 0) return first;
  if (t === 1) return points[points.length - 1];
  const total = pathLength(rect);
  if (total <= 0) return first;
  let remain = t * total;
  for (let index = 1; index < points.length; index += 1) {
    const start = points[index - 1];
    const end = points[index];
    const segment = dist(end, start);
    if (remain <= segment || index === points.length - 1) {
      const u = segment > 0 ? remain / segment : 0;
      const c = clamp01(u);
      return { x: lerp(start.x, end.x, c), y: lerp(start.y, end.y, c) };
    }
    remain -= segment;
  }
  return points[points.length - 1];
}

export function glowAmount(amount, elapsed, igniting, reduceMotion) {
  const p = Number.isFinite(amount) ? clamp01(amount) : 0;
  if (p <= 0) return 0;
  const base = TUNING.glowSettled * p;
  if (reduceMotion || !igniting || !Number.isFinite(elapsed)) return base;
  const wave = sin(elapsed * TUNING.glowOmega);
  return clamp(base + TUNING.glowPulse * wave * p, 0, 1);
}

export function dayRect(index) {
  const clamped = Math.min(Math.max(index, 0), TUNING.dayCount - 1);
  return {
    x: TUNING.dayOriginX + clamped * TUNING.dayStride,
    y: TUNING.dayOriginY,
    width: TUNING.dayWidth,
    height: TUNING.dayHeight,
  };
}

export function contains(rect, point, slop = 0) {
  return point.x >= rect.x - slop && point.x <= rect.x + rect.width + slop
    && point.y >= rect.y - slop && point.y <= rect.y + rect.height + slop;
}

function weeklyTarget(completed) {
  return completed.size / TUNING.dayCount;
}

export class BoltStreakModel {
  constructor({ completed = [], today = 0, reduceMotion = false } = {}) {
    this.today = today;
    this.completed = new Set(completed);
    this.reduceMotion = reduceMotion;
    this.active = null;
    this.elapsed = 0;
    this.queue = [];
    this.progress = WEEKDAYS.map((_, index) => (this.completed.has(index) ? 1 : 0));
  }

  dayProgress(day) {
    return this.progress[day];
  }

  get weeklyTarget() {
    return weeklyTarget(this.completed);
  }

  get weeklyProgress() {
    return this.progress.reduce((sum, value) => sum + value, 0) / TUNING.dayCount;
  }

  glow(day) {
    return glowAmount(this.dayProgress(day), this.elapsed, this.active === day, this.reduceMotion);
  }

  get weeklyGlow() {
    return glowAmount(this.weeklyProgress, this.elapsed, this.active !== null, this.reduceMotion);
  }

  head(day) {
    const p = this.dayProgress(day);
    if (this.reduceMotion) return this.completed.has(day) ? sample(1) : null;
    if (this.active === day) return sample(p);
    if (p <= 0) return null;
    return sample(Math.min(p, 1));
  }

  get weeklyHead() {
    if (this.reduceMotion) return this.weeklyProgress > 0 ? sample(this.weeklyProgress) : null;
    if (this.active !== null || this.weeklyProgress > 0) return sample(this.weeklyProgress);
    return null;
  }

  ignite(day) {
    if (this.completed.has(day) || this.active === day || this.queue.includes(day)) return [];
    this.completed.add(day);
    if (this.reduceMotion) {
      this.progress[day] = 1;
      return ["ignited", "tick"];
    }
    if (this.active === null) {
      this.active = day;
      this.elapsed = 0;
      this.progress[day] = 0;
    } else {
      this.queue.push(day);
    }
    return ["ignited", "tick"];
  }

  igniteToday() {
    return this.ignite(this.today);
  }

  step(dt) {
    if (!Number.isFinite(dt) || dt <= 0 || this.reduceMotion || this.active === null) return [];
    const day = this.active;
    const h = Math.min(dt, TUNING.maxFrame);
    this.elapsed += h;
    if (this.elapsed >= TUNING.ignitionDuration) {
      this.progress[day] = 1;
      this.elapsed = 0;
      this.active = null;
      this.startNext();
      return [];
    }
    this.progress[day] = smoothstep(0, TUNING.ignitionDuration, this.elapsed);
    return [];
  }

  startNext() {
    if (this.active !== null || this.queue.length === 0) return;
    const day = this.queue.shift();
    this.active = day;
    this.elapsed = 0;
    this.progress[day] = 0;
  }

  accessibilityValue() {
    const lit = WEEKDAYS.map((_, index) => index).filter((index) => this.completed.has(index));
    const litText = lit.length === 0 ? "No days lit" : `${lit.map((index) => WEEKDAY_NAMES[index]).join(", ")} lit`;
    const todayText = this.completed.has(this.today)
      ? `${WEEKDAY_NAMES[this.today]} is lit`
      : `${WEEKDAY_NAMES[this.today]} is today`;
    return `${this.completed.size} of 7 days. ${litText}. ${todayText}.`;
  }
}

function ignitionFrame(index) {
  return REEL.idleFrames + index * (TUNING.burnFrames + REEL.gapFrames);
}

function ignitionIndex(frame) {
  if (frame < REEL.idleFrames) return null;
  const stride = TUNING.burnFrames + REEL.gapFrames;
  const delta = frame - REEL.idleFrames;
  if (delta % stride !== 0) return null;
  const index = delta / stride;
  if (index < 0 || index >= WEEKDAYS.length) return null;
  return index;
}

const motionFrames = ignitionFrame(6) + TUNING.burnFrames + REEL.holdFrames;
const reduceStart = motionFrames;
const totalFrames = reduceStart + REEL.reduceLead + REEL.reduceMid + REEL.reduceHold;

export const DEMO_DURATION = totalFrames * REEL.dt;

function motionModel(steps) {
  const model = new BoltStreakModel({ today: REEL.today, reduceMotion: false });
  for (let frame = 0; frame < Math.max(0, steps); frame += 1) {
    const index = ignitionIndex(frame);
    if (index !== null) model.ignite(index);
    model.step(REEL.dt);
  }
  return model;
}

function reduceModel(local) {
  const model = new BoltStreakModel({ today: REEL.today, reduceMotion: true });
  if (local >= REEL.reduceLead) {
    model.ignite(0);
    model.ignite(1);
    model.ignite(2);
  }
  if (local >= REEL.reduceLead + REEL.reduceMid) {
    model.ignite(3);
    model.ignite(4);
    model.ignite(5);
    model.ignite(6);
  }
  const ticks = Math.min(Math.max(local, 0), 3);
  for (let index = 0; index < ticks; index += 1) model.step(REEL.dt);
  return model;
}

export function frameCount(time) {
  if (!Number.isFinite(time) || time <= 0) return 0;
  return Math.floor(time / REEL.dt + 0.5);
}

export function modelAtFrame(frame) {
  if (frame >= reduceStart) return reduceModel(frame - reduceStart);
  return motionModel(Math.max(0, frame));
}

export function demoAt(time) {
  return modelAtFrame(frameCount(time));
}

export const DEMO_STILLS = [
  { name: "Idle zinc", t: 0.2 },
  { name: "Monday head", t: (ignitionFrame(0) + 18) * REEL.dt },
  { name: "Three days", t: (ignitionFrame(3) - 4) * REEL.dt },
  { name: "Weekly filling", t: (ignitionFrame(3) + 18) * REEL.dt },
  { name: "Today ignites", t: (ignitionFrame(6) + 18) * REEL.dt },
  { name: "Full week", t: (reduceStart - 8) * REEL.dt },
  { name: "Reduce Motion", t: (reduceStart + REEL.reduceLead + 8) * REEL.dt },
  { name: "Reduce full", t: (totalFrames - 8) * REEL.dt },
];

function pointText(p) {
  return `${fmt(p.x)} ${fmt(p.y)}`;
}

function body(model) {
  const progress = WEEKDAYS.map((_, index) => fmt(model.dayProgress(index))).join(",");
  const activeHead = model.active === null ? null : model.head(model.active);
  const weeklyHead = model.weeklyHead;
  return [
    progress,
    fmt(model.weeklyProgress),
    fmt(model.weeklyTarget),
    fmt(model.active === null ? 0 : model.glow(model.active)),
    fmt(model.elapsed),
    model.active === null ? "-" : WEEKDAYS[model.active],
    String(model.queue.length),
    activeHead ? pointText(activeHead) : "- -",
    weeklyHead ? pointText(weeklyHead) : "- -",
    model.reduceMotion ? "1" : "0",
  ].join(" ");
}

function describe(kind, day) {
  if (kind === "tick") return "tick";
  return `ignited ${WEEKDAYS[day]}`;
}

function note(lines, tag, events, day) {
  if (events.length === 0) {
    lines.push(`${tag} e`);
    return;
  }
  const text = events.map((kind, index) => (kind === "ignited" ? describe(kind, day[index]) : "tick")).join(" ");
  lines.push(`${tag} e ${text}`);
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(REEL.dt)}`,
    `burn ${fmt(TUNING.ignitionDuration)} frames ${TUNING.burnFrames}`,
    `cap ${fmt(TUNING.maxFrame)}`,
    `length ${fmt(pathLength(UNIT))}`,
    `p0 ${pointText(sample(0))}`,
    `p50 ${pointText(sample(0.5))}`,
    `p100 ${pointText(sample(1))}`,
    `mid ${pointText(sample(0.5, TUNING.weeklyRect))}`,
    `sin ${fmt(sin(0))} ${fmt(sin(HALF_PI))} ${fmt(sin(PI))}`,
    `week ${fmt(TUNING.weeklyRect.x)} ${fmt(TUNING.weeklyRect.y)} ${fmt(TUNING.weeklyRect.width)} ${fmt(TUNING.weeklyRect.height)}`,
    `days ${fmt(TUNING.dayOriginX)} ${fmt(TUNING.dayOriginY)} ${fmt(TUNING.dayWidth)} ${fmt(TUNING.dayHeight)} ${fmt(TUNING.dayStride)}`,
    `glow ${fmt(TUNING.glowSettled)} ${fmt(TUNING.glowPulse)} ${fmt(TUNING.glowOmega)}`,
    `tilt ${fmt(TUNING.tiltDegrees)} ${fmt(TUNING.tiltPerspective)}`,
    `reel ${totalFrames} ${fmt(DEMO_DURATION)}`,
  ];

  const model = new BoltStreakModel({ today: 4, reduceMotion: false });
  const snap = (tag, current) => lines.push(`${tag} ${body(current)}`);
  snap("s", model);
  const first = model.ignite(4);
  note(lines, "s", first, [4, 4]);
  snap("s", model);
  for (let index = 0; index < 10; index += 1) {
    note(lines, "s", model.step(REEL.dt), []);
    snap("s", model);
  }
  note(lines, "s", model.ignite(4), [4]);
  const queued = model.ignite(5);
  note(lines, "s", queued, [5, 5]);
  snap("s", model);
  let guardCount = 0;
  while (model.active === 4 && guardCount < 80) {
    note(lines, "s", model.step(REEL.dt), []);
    guardCount += 1;
  }
  snap("s", model);

  const reduced = new BoltStreakModel({ today: 4, reduceMotion: true });
  const todayEvents = reduced.igniteToday();
  note(lines, "r", todayEvents, [4, 4]);
  snap("r", reduced);
  note(lines, "r", reduced.step(REEL.dt), []);
  note(lines, "r", reduced.step(0.2), []);
  snap("r", reduced);

  const frames = [];
  for (let frame = 0; frame <= 8; frame += 1) frames.push(frame);
  const burnStart = ignitionFrame(0);
  for (let frame = burnStart; frame <= burnStart + TUNING.burnFrames + 2; frame += 1) frames.push(frame);
  frames.push(ignitionFrame(3) - 4);
  frames.push(ignitionFrame(3) + 18);
  frames.push(ignitionFrame(6) + 18);
  frames.push(reduceStart - 8);
  frames.push(reduceStart + REEL.reduceLead + 8);
  frames.push(totalFrames - 8);
  for (const frame of frames) lines.push(`f ${frame} ${body(modelAtFrame(frame))}`);
  return `${lines.join("\n")}\n`;
}
