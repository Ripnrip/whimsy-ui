// Port of GrainBloomCore. Constants match GrainBloomTuning and GrainBloomMath.
// webports/grainbloom-parity.mjs checks goldenTrace() against the Swift fixture.

const MASK = (1n << 64n) - 1n;
const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / TWO_PI;

export const TUNING = {
  stageWidth: 390,
  stageHeight: 844,
  wakeDuration: 0.9,
  resolveDuration: 1.4,
  settleDuration: 0.35,
  reduceDuration: 0.28,
  lattice: 32,
  maxBlur: 18,
  defaultSeed: 0x6b1eb10bn,
  cellSizes: [16, 8, 4, 2, 1],
  bayer4: [
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5,
  ],
  generatingValue: "Generating image",
  readyValue: "Image ready",
};

export function sin(x) {
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

export function cos(x) {
  return sin(x + HALF_PI);
}

function mod(value, modulus) {
  const raw = value % modulus;
  return raw >= 0 ? raw : raw + modulus;
}

export function bayer4(row, column) {
  const r = mod(row, 4);
  const c = mod(column, 4);
  return TUNING.bayer4[r * 4 + c];
}

export function bayer8(row, column) {
  const r = mod(row, 8);
  const c = mod(column, 8);
  const base = bayer4(r % 4, c % 4);
  let quadrant = 1;
  if (r < 4 && c < 4) quadrant = 0;
  else if (r < 4 && c >= 4) quadrant = 2;
  else if (r >= 4 && c < 4) quadrant = 3;
  return 4 * base + quadrant;
}

export function sliceIndex(progress) {
  if (progress >= 1) return TUNING.cellSizes.length - 1;
  if (progress <= 0) return 0;
  const steps = TUNING.cellSizes.length;
  let index = 0;
  for (let step = 1; step < steps; step += 1) {
    if (progress + 1e-12 >= step / steps) index = step;
  }
  return index;
}

export function cellSize(progress) {
  return TUNING.cellSizes[sliceIndex(progress)];
}

function passes(x, y, size, progress) {
  const column = Math.floor(x / size);
  const row = Math.floor(y / size);
  const threshold = bayer8(row, column);
  return progress + 1e-12 >= (threshold + 0.5) / 64;
}

export function isRevealed(x, y, progress) {
  const p = Math.min(Math.max(progress, 0), 1);
  if (p <= 0) return false;
  const steps = TUNING.cellSizes.length;
  for (let index = 0; index < steps; index += 1) {
    const sliceEnd = (index + 1) / steps;
    const size = TUNING.cellSizes[index];
    if (p + 1e-12 >= sliceEnd) {
      if (passes(x, y, size, sliceEnd)) return true;
    } else {
      return passes(x, y, size, p);
    }
  }
  return true;
}

export function coverage(progress) {
  const n = TUNING.lattice;
  let on = 0;
  for (let row = 0; row < n; row += 1) {
    for (let column = 0; column < n; column += 1) {
      const x = (column + 0.5) / n * TUNING.stageWidth;
      const y = (row + 0.5) / n * TUNING.stageHeight;
      if (isRevealed(x, y, progress)) on += 1;
    }
  }
  return on / (n * n);
}

export function rippleDelay(x, y) {
  const dx = x - TUNING.stageWidth / 2;
  const dy = y - TUNING.stageHeight / 2;
  const dist = Math.sqrt(dx * dx + dy * dy);
  const diagonal = Math.sqrt(
    TUNING.stageWidth * TUNING.stageWidth + TUNING.stageHeight * TUNING.stageHeight,
  );
  if (diagonal === 0) return 0;
  return dist / diagonal;
}

export function dotScale(wakeTime, delay, reduceMotion) {
  const t = reduceMotion ? 0 : wakeTime;
  const local = t - delay * TUNING.wakeDuration;
  if (local < 0) return 0.35;
  const pulse = 0.5 + 0.5 * sin(local * 6);
  return 0.6 + 0.4 * pulse;
}

export function blob(index, time, reduceMotion) {
  const t = reduceMotion ? 0 : time;
  const phase = index * 1.7;
  const x = TUNING.stageWidth * (
    0.5 + 0.28 * sin(t * 0.35 + phase) + 0.08 * sin(t * 0.17 + phase * 2)
  );
  const y = TUNING.stageHeight * (
    0.5 + 0.22 * cos(t * 0.27 + phase) + 0.06 * sin(t * 0.13 + phase * 0.5)
  );
  return { x, y };
}

function mul64(a, b) {
  return (a * b) & MASK;
}

export function grain(x, y, frame, seed) {
  let mixed = BigInt(seed) & MASK;
  mixed ^= mul64(BigInt(frame), 0x9E3779B97F4A7C15n);
  mixed ^= mul64(BigInt(x), 0xBF58476D1CE4E5B9n);
  mixed ^= mul64(BigInt(y), 0x94D049BB133111EBn);
  const rng = new SplitMix(mixed);
  return rng.uniform(0, 1);
}

export function shimmer(phaseIsWaking, phaseTime, reduceMotion) {
  if (!phaseIsWaking || reduceMotion) return 0;
  return Math.min(1, Math.max(0, phaseTime / TUNING.wakeDuration));
}

export function blur(progress, reduceMotion) {
  if (reduceMotion) return 0;
  const p = Math.min(Math.max(progress, 0), 1);
  return TUNING.maxBlur * (1 - p);
}

export function glint(playsSettle, phaseTime, reduceMotion) {
  if (!playsSettle || reduceMotion) return 0;
  const u = phaseTime / TUNING.settleDuration;
  if (u <= 0 || u >= 1) return 0;
  return sin(u * PI);
}

class SplitMix {
  constructor(seed) {
    this.state = BigInt(seed) & MASK;
  }

  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
    let z = this.state;
    z = (mul64(z ^ (z >> 30n), 0xBF58476D1CE4E5B9n));
    z = (mul64(z ^ (z >> 27n), 0x94D049BB133111EBn));
    return (z ^ (z >> 31n)) & MASK;
  }

  uniform(lo, hi) {
    const unit = Number(this.next() >> 11n) / Number(1n << 53n);
    return lo + (hi - lo) * unit;
  }
}

export class GrainBloomModel {
  constructor({ generating = false, hasImage = false, reduceMotion = false, seed = TUNING.defaultSeed } = {}) {
    this.phase = "idle";
    this.phaseTime = 0;
    this.hasImage = false;
    this.epoch = 0;
    this.isGenerating = false;
    this.reduceMotion = reduceMotion;
    this.resolveProgress = 0;
    this.crossfade = 0;
    this.playsSettle = false;
    this.seed = BigInt(seed) & MASK;
    this.elapsed = 0;
    this.frozenCellSize = TUNING.cellSizes[0];
    this.isGenerating = generating;
    if (hasImage) {
      this.hasImage = true;
      this.epoch = 1;
      if (generating) this.enterResolving(true);
      else {
        this.phase = "done";
        this.phaseTime = 0;
        this.playsSettle = false;
        this.resolveProgress = 1;
        this.crossfade = 1;
      }
    } else if (generating) {
      this.enterWaking();
    }
  }

  setGenerating(on) {
    if (on === this.isGenerating) return;
    this.isGenerating = on;
    if (on) {
      if (!this.hasImage && this.phase === "idle") this.enterWaking();
    } else if (this.phase === "waking" && !this.hasImage) {
      this.enterIdle();
    }
  }

  setImagePresent(present) {
    if (present === this.hasImage) return;
    this.epoch += 1;
    this.hasImage = present;
    if (present) this.enterResolving(true);
    else if (this.isGenerating) this.enterWaking();
    else this.enterIdle();
  }

  setReduceMotion(on) {
    if (on && !this.reduceMotion) {
      this.frozenCellSize = cellSize(this.resolveProgress);
      this.crossfade = Math.max(this.crossfade, coverage(this.resolveProgress));
    }
    this.reduceMotion = on;
  }

  replay() {
    if (this.phase !== "done" || !this.hasImage) return false;
    this.seed = (this.seed + 1n) & MASK;
    this.epoch += 1;
    this.enterWaking();
    return true;
  }

  step(dt) {
    const delta = Math.max(0, dt);
    this.elapsed += delta;
    this.phaseTime += delta;
    if (this.reduceMotion) {
      if (!this.hasImage) return;
      const duration = TUNING.reduceDuration;
      this.crossfade = duration <= 0 ? 1 : Math.min(1, this.crossfade + delta / duration);
      this.resolveProgress = Math.max(this.resolveProgress, this.crossfade);
      if (this.crossfade >= 1 && this.phase !== "done") {
        this.phase = "done";
        this.phaseTime = 0;
        this.playsSettle = false;
      }
      return;
    }
    if (this.phase === "waking") {
      if (this.hasImage && this.phaseTime >= TUNING.wakeDuration) this.enterResolving(true);
    } else if (this.phase === "resolving") {
      this.resolveProgress = Math.min(1, this.phaseTime / TUNING.resolveDuration);
      if (this.resolveProgress >= 1) {
        this.phase = "done";
        this.phaseTime = 0;
        this.playsSettle = true;
        this.crossfade = 1;
      }
    }
  }

  get currentCellSize() {
    return this.reduceMotion ? this.frozenCellSize : cellSize(this.resolveProgress);
  }

  get revealCoverage() {
    return this.reduceMotion ? this.crossfade : coverage(this.resolveProgress);
  }

  get blur() {
    return blur(this.resolveProgress, this.reduceMotion);
  }

  get shimmer() {
    return shimmer(this.phase === "waking", this.phaseTime, this.reduceMotion);
  }

  get glint() {
    return glint(this.playsSettle && this.phase === "done", this.phaseTime, this.reduceMotion);
  }

  get accessibilityValue() {
    return this.phase === "done" ? TUNING.readyValue : TUNING.generatingValue;
  }

  blob(index) {
    return blob(index, this.elapsed, this.reduceMotion);
  }

  enterIdle() {
    this.phase = "idle";
    this.phaseTime = 0;
    this.playsSettle = false;
    this.resolveProgress = 0;
    this.crossfade = 0;
  }

  enterWaking() {
    this.phase = "waking";
    this.phaseTime = 0;
    this.playsSettle = false;
    if (!this.reduceMotion) {
      this.resolveProgress = 0;
      this.crossfade = 0;
    }
  }

  enterResolving(resetProgress) {
    this.phase = "resolving";
    this.phaseTime = 0;
    this.playsSettle = false;
    if (resetProgress && !this.reduceMotion) {
      this.resolveProgress = 0;
      this.crossfade = 0;
    }
    if (this.reduceMotion) this.frozenCellSize = TUNING.cellSizes[0];
  }
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

const DT = 0.1;

function line(tag, index, model) {
  const spot = model.blob(0);
  return [
    tag,
    String(index),
    model.phase,
    model.hasImage ? "1" : "0",
    String(model.epoch),
    fmt(model.phaseTime),
    fmt(model.resolveProgress),
    fmt(model.revealCoverage),
    fmt(model.currentCellSize),
    fmt(model.blur),
    fmt(model.shimmer),
    fmt(model.glint),
    fmt(spot.x),
    fmt(spot.y),
    `"${model.accessibilityValue}"`,
  ].join(" ");
}

function session(reduceMotion, tag) {
  const lines = [];
  let index = 0;
  const snap = (model) => {
    lines.push(line(tag, index, model));
    index += 1;
  };
  const run = (model, steps) => {
    for (let i = 0; i < steps; i += 1) {
      model.step(DT);
      snap(model);
    }
  };
  const model = new GrainBloomModel({ reduceMotion });
  snap(model);
  model.setGenerating(true);
  lines.push(`${tag} e generating 1`);
  snap(model);
  run(model, 3);
  model.setImagePresent(true);
  lines.push(`${tag} e image 1`);
  snap(model);
  run(model, 16);
  model.replay();
  lines.push(`${tag} e replay`);
  snap(model);
  run(model, 12);

  const cancel = new GrainBloomModel({ generating: true, reduceMotion });
  cancel.setGenerating(false);
  lines.push(`${tag} e cancel ${cancel.phase}`);
  snap(cancel);

  const swap = new GrainBloomModel({ generating: false, hasImage: true, reduceMotion });
  swap.setImagePresent(false);
  swap.setImagePresent(true);
  lines.push(`${tag} e swap ${swap.epoch} ${swap.phase}`);
  snap(swap);
  return lines;
}

export function goldenTrace() {
  const bayerRow = Array.from({ length: 8 }, (_, column) => bayer8(0, column)).join(",");
  const lines = [
    "v1",
    `dt ${fmt(DT)}`,
    `wake ${fmt(TUNING.wakeDuration)} resolve ${fmt(TUNING.resolveDuration)} settle ${fmt(TUNING.settleDuration)} reduce ${fmt(TUNING.reduceDuration)}`,
    `stage ${fmt(TUNING.stageWidth)} ${fmt(TUNING.stageHeight)} lattice ${TUNING.lattice}`,
    `bayer4 ${TUNING.bayer4.slice(0, 4).join(",")}`,
    `bayer8 ${bayerRow}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

export const DEMO_DURATION = 5.2;
export const DEMO_STILLS = [
  { t: 0.15, label: "Idle" },
  { t: 0.85, label: "Waking" },
  { t: 2.1, label: "Resolving" },
  { t: 3.15, label: "Done" },
];

export function demoAt(t) {
  const model = new GrainBloomModel();
  const marks = [
    [0.35, () => model.setGenerating(true)],
    [1.3, () => model.setImagePresent(true)],
    [3.5, () => model.replay()],
  ];
  const step = 1 / 60;
  let time = 0;
  let cursor = 0;
  while (time + 1e-9 < t) {
    const next = Math.min(t, time + step);
    while (cursor < marks.length && marks[cursor][0] <= next + 1e-9) {
      const gap = marks[cursor][0] - time;
      if (gap > 0) model.step(gap);
      marks[cursor][1]();
      time = marks[cursor][0];
      cursor += 1;
    }
    if (next > time) model.step(next - time);
    time = next;
  }
  return model;
}
