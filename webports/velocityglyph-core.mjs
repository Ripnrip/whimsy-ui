// JavaScript port of VelocityGlyphCore.
// Constants, the polynomial exp, SplitMix64 and the spring substeps match the Swift sources:
//   Sources/VelocityGlyphCore/VelocityGlyphMath.swift
//   Sources/VelocityGlyphCore/VelocityGlyphModel.swift
//   Sources/VelocityGlyphCore/PriceGlyphs.swift
//   Sources/WhimsyCore/WhimsySpring.swift
//   Sources/WhimsyCore/SeededRandom.swift
// The golden session matches Tests/VelocityGlyphCoreTests/GoldenTraceTests.swift.

export const TUNING = {
  defaultLower: 40,
  defaultUpper: 600,
  defaultStep: 5,
  defaultValue: 180,
  trackWidth: 280,
  velocityTau: 0.09,
  fullSpeed: 480,
  maxOffset: 18,
  maxLean: 6,
  maxBlur: 1.8,
  springStiffness: 240,
  springDamping: 0.55,
  maxFrame: 0.1,
  substep: 1 / 240,
  domain: 1_000_000_000,
};

const LN2 = 0.6931471805599453;
const INV_LN2 = 1 / 0.6931471805599453;
const MASK64 = (1n << 64n) - 1n;

function clamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
function clamp01(x) { return clamp(x, 0, 1); }

function polyExp(x) {
  if (Number.isNaN(x)) return 0;
  const xc = clamp(x, -60, 60);
  const k = Math.floor(xc * INV_LN2 + 0.5);
  const r = xc - k * LN2;
  let p = 1 / 6_227_020_800;
  p = 1 / 479_001_600 + r * p;
  p = 1 / 39_916_800 + r * p;
  p = 1 / 3_628_800 + r * p;
  p = 1 / 362_880 + r * p;
  p = 1 / 40320 + r * p;
  p = 1 / 5040 + r * p;
  p = 1 / 720 + r * p;
  p = 1 / 120 + r * p;
  p = 1 / 24 + r * p;
  p = 1 / 6 + r * p;
  p = 0.5 + r * p;
  p = 1 + r * p;
  p = 1 + r * p;
  let n = Math.trunc(k);
  while (n > 0) { p *= 2; n -= 1; }
  while (n < 0) { p /= 2; n += 1; }
  return p;
}

function splitmix(seed) {
  let state = BigInt(seed) & MASK64;
  state = (state + 0x9E3779B97F4A7C15n) & MASK64;
  let z = state;
  z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK64;
  z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK64;
  const out = (z ^ (z >> 31n)) & MASK64;
  const unit = Number(out >> 11n) / Number(1n << 53n);
  return unit;
}

export function roleToken(role) {
  if (role.kind === "sign") return "s";
  if (role.kind === "currency") return "c";
  if (role.kind === "digit") return `d${role.place}`;
  return `g${role.group}`;
}

function seedFor(role) {
  if (role.kind === "sign") return 0x56474C5900000001n;
  if (role.kind === "currency") return 0x56474C5900000002n;
  if (role.kind === "digit") return 0x56474C5910000000n + BigInt(role.place >>> 0);
  return 0x56474C5920000000n + BigInt(role.group >>> 0);
}

export function signedUnit(role) {
  return splitmix(seedFor(role)) * 2 - 1;
}

export function signedAmplitude(role) {
  const unit = signedUnit(role);
  const direction = unit < 0 ? -1 : 1;
  return direction * (0.45 + 0.55 * Math.abs(unit));
}

export function speedScale(speed) {
  if (!Number.isFinite(speed)) return 0;
  return clamp01(Math.abs(speed) / TUNING.fullSpeed);
}

export function smoothAlpha(dt) {
  if (!Number.isFinite(dt) || dt <= 0) return 0;
  const capped = Math.min(dt, TUNING.maxFrame);
  return 1 - polyExp(-capped / TUNING.velocityTau);
}

export function smooth(previous, raw, dt) {
  const prev = Number.isFinite(previous) ? previous : 0;
  if (!Number.isFinite(raw)) return prev;
  const alpha = smoothAlpha(dt);
  return prev + (raw - prev) * alpha;
}

export function scatter(role, speed) {
  const scale = speedScale(speed);
  const amplitude = signedAmplitude(role);
  return { offset: amplitude * TUNING.maxOffset * scale, lean: amplitude * TUNING.maxLean * scale };
}

export function blurForSpeed(speed) {
  return TUNING.maxBlur * speedScale(speed);
}

function halfAway(x) {
  if (!Number.isFinite(x)) return 0;
  const clamped = clamp(x, -TUNING.domain, TUNING.domain);
  if (clamped >= 0) return Math.trunc(clamped + 0.5);
  return -Math.trunc(-clamped + 0.5);
}

export function makeSpan(lowerBound, upperBound, step) {
  const spanStep = clamp(step, 1, TUNING.domain);
  const lo = clamp(lowerBound, -TUNING.domain, TUNING.domain);
  const hi = clamp(upperBound, -TUNING.domain, TUNING.domain);
  const lower = Math.min(lo, hi);
  const upper = Math.max(lo, hi);
  const last = upper <= lower ? lower : lower + Math.trunc((upper - lower) / spanStep) * spanStep;
  return {
    lower, upper, step: spanStep, last,
    snap(raw) {
      if (!Number.isFinite(raw)) return lower;
      const clamped = clamp(raw, lower, upper);
      const stepsFromLower = halfAway((clamped - lower) / spanStep);
      const snapped = lower + stepsFromLower * spanStep;
      if (snapped < lower) return lower;
      if (snapped > last) return last;
      return snapped;
    },
    fraction(value) {
      const width = upper - lower;
      if (width <= 0) return 0;
      return clamp01((this.snap(value) - lower) / width);
    },
    valueAtFraction(t) {
      if (!Number.isFinite(t)) return lower;
      return this.snap(lower + clamp01(t) * (upper - lower));
    },
    valueAtX(x, width) {
      if (!(width > 0) || !Number.isFinite(x)) return lower;
      return this.valueAtFraction(x / width);
    },
    xFor(value, width) {
      if (!(width > 0)) return 0;
      return this.fraction(value) * width;
    },
    steps(from, to) {
      const start = this.snap(from);
      const end = this.snap(to);
      if (start === end) return [];
      const out = [];
      let value = start;
      if (end > start) {
        while (value < end) { value += spanStep; out.push(value); }
      } else {
        while (value > end) { value -= spanStep; out.push(value); }
      }
      return out;
    },
  };
}

function decimalDigits(magnitude) {
  if (magnitude === 0n) return ["0"];
  const names = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
  let n = magnitude;
  const digits = [];
  while (n > 0n) {
    digits.push(names[Number(n % 10n)]);
    n /= 10n;
  }
  digits.reverse();
  return digits;
}

export function glyphsFor(value) {
  const out = [];
  if (value < 0) out.push({ role: { kind: "sign" }, character: "-" });
  out.push({ role: { kind: "currency" }, character: "$" });
  const mag = value >= 0 ? BigInt(value) : BigInt(-value);
  const digits = decimalDigits(mag);
  digits.forEach((character, index) => {
    const place = digits.length - 1 - index;
    out.push({ role: { kind: "digit", place }, character });
    if (place > 0 && place % 3 === 0) {
      out.push({ role: { kind: "separator", group: place / 3 }, character: "," });
    }
  });
  return out;
}

export function formatPrice(value) {
  return glyphsFor(value).map((glyph) => glyph.character).join("");
}

function makeSpring(value = 0) {
  return { value, velocity: 0, stiffness: TUNING.springStiffness, dampingRatio: TUNING.springDamping };
}

function springStep(spring, target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, 0.1);
  while (remaining > 1e-12) {
    const h = Math.min(remaining, TUNING.substep);
    const damping = 2 * spring.dampingRatio * Math.sqrt(spring.stiffness);
    const acceleration = spring.stiffness * (target - spring.value) - damping * spring.velocity;
    spring.velocity += acceleration * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
}

function springSettled(spring, target, tolerance = 1e-3) {
  return Math.abs(spring.value - target) < tolerance && Math.abs(spring.velocity) < tolerance * 10;
}

function springSnap(spring, target) {
  spring.value = target;
  spring.velocity = 0;
}

export function fmt(x) {
  const sign = x < 0 ? "-" : "";
  const rounded = Math.floor(Math.abs(x) * 1e8 + 0.5);
  const whole = Math.floor(rounded / 1e8);
  const frac = String(Math.trunc(rounded % 1e8)).padStart(8, "0");
  return `${sign}${whole}.${frac}`;
}

export class VelocityGlyphModel {
  constructor({ value = TUNING.defaultValue, lower = TUNING.defaultLower, upper = TUNING.defaultUpper, step = TUNING.defaultStep, reduceMotion = false } = {}) {
    this.span = makeSpan(lower, upper, step);
    this.value = this.span.snap(value);
    this.phase = "idle";
    this.time = 0;
    this.smoothedSpeed = 0;
    this.reduceMotion = reduceMotion;
    this.pointerX = this.span.xFor(this.value, TUNING.trackWidth);
    this.lastSampleX = this.pointerX;
    this.blurSpring = makeSpring(0);
    this.glyphs = [];
    this.syncGlyphs();
  }

  get formattedPrice() { return formatPrice(this.value); }

  get interactionX() {
    return this.phase === "dragging" ? this.pointerX : this.span.xFor(this.value, TUNING.trackWidth);
  }

  get blurRadius() {
    if (this.reduceMotion) return 0;
    return Math.max(0, this.blurSpring.value);
  }

  get poses() {
    return this.glyphs.map((body) => ({
      id: body.role,
      token: roleToken(body.role),
      character: body.character,
      offsetY: this.reduceMotion ? 0 : body.offset.value,
      leanDegrees: this.reduceMotion ? 0 : body.lean.value,
    }));
  }

  get isVisuallySettled() {
    if (this.reduceMotion) return true;
    if (!springSettled(this.blurSpring, 0)) return false;
    return this.glyphs.every((body) => springSettled(body.offset, 0) && springSettled(body.lean, 0));
  }

  beginDrag(x) {
    if (!Number.isFinite(x)) return [];
    this.pointerX = clamp(x, 0, TUNING.trackWidth);
    this.lastSampleX = this.pointerX;
    this.smoothedSpeed = 0;
    this.phase = "dragging";
    return this.apply(this.span.valueAtX(this.pointerX, TUNING.trackWidth));
  }

  updateDrag(x) {
    if (this.phase !== "dragging" || !Number.isFinite(x)) return [];
    this.pointerX = clamp(x, 0, TUNING.trackWidth);
    return this.apply(this.span.valueAtX(this.pointerX, TUNING.trackWidth));
  }

  endDrag() {
    if (this.phase !== "dragging") return;
    this.smoothedSpeed = 0;
    if (this.reduceMotion || this.isVisuallySettled) {
      this.snapVisuals();
      this.phase = "idle";
    } else {
      this.phase = "settling";
    }
  }

  setValue(raw) { return this.apply(this.span.snap(raw)); }

  adjust(steps) {
    if (!steps) return [];
    return this.apply(this.span.snap(this.shift(this.value, steps)));
  }

  setReduceMotion(on) {
    if (on === this.reduceMotion) return;
    this.reduceMotion = on;
    if (on) {
      this.snapVisuals();
      this.smoothedSpeed = 0;
      if (this.phase === "settling") this.phase = "idle";
    }
  }

  step(dt) {
    if (!Number.isFinite(dt) || dt <= 0) return;
    const frame = Math.min(dt, TUNING.maxFrame);
    if (this.phase === "dragging") {
      const raw = (this.pointerX - this.lastSampleX) / dt;
      this.smoothedSpeed = smooth(this.smoothedSpeed, raw, frame);
      this.lastSampleX = this.pointerX;
    }
    const targets = this.glyphs.map((body) => this.target(body.role));
    const blurTarget = this.currentBlurTarget();
    if (this.reduceMotion) {
      this.snapVisuals();
    } else {
      this.glyphs.forEach((body, index) => {
        springStep(body.offset, targets[index].offset, frame);
        springStep(body.lean, targets[index].lean, frame);
      });
      springStep(this.blurSpring, blurTarget, frame);
    }
    this.time += frame;
    if (this.phase === "settling" && this.isVisuallySettled) {
      this.phase = "idle";
      this.smoothedSpeed = 0;
      this.snapVisuals();
    }
  }

  target(role) {
    if (this.phase !== "dragging" || this.reduceMotion) return { offset: 0, lean: 0 };
    return scatter(role, this.smoothedSpeed);
  }

  currentBlurTarget() {
    if (this.phase !== "dragging" || this.reduceMotion) return 0;
    return blurForSpeed(this.smoothedSpeed);
  }

  shift(value, steps) {
    const current = this.span.snap(value);
    if (steps > 0) {
      const room = Math.trunc((this.span.last - current) / this.span.step);
      return current + Math.min(steps, room) * this.span.step;
    }
    const room = Math.trunc((current - this.span.lower) / this.span.step);
    return current - Math.min(-steps, room) * this.span.step;
  }

  apply(snapped) {
    const next = this.span.snap(snapped);
    const crossed = this.span.steps(this.value, next);
    if (next === this.value) return [];
    this.value = next;
    this.syncGlyphs();
    return crossed;
  }

  syncGlyphs() {
    const kept = new Map(this.glyphs.map((body) => [roleToken(body.role), body]));
    this.glyphs = glyphsFor(this.value).map((glyph) => {
      const existing = kept.get(roleToken(glyph.role));
      if (existing) {
        existing.character = glyph.character;
        existing.role = glyph.role;
        return existing;
      }
      return { role: glyph.role, character: glyph.character, offset: makeSpring(0), lean: makeSpring(0) };
    });
  }

  snapVisuals() {
    for (const body of this.glyphs) {
      springSnap(body.offset, 0);
      springSnap(body.lean, 0);
    }
    springSnap(this.blurSpring, 0);
  }
}

function traceLine(tag, index, model) {
  const glyphs = model.poses.map((pose) => `${pose.token}:${pose.character}:${fmt(pose.offsetY)}:${fmt(pose.leanDegrees)}`).join(" ");
  return `${tag} ${index} ${model.phase} ${model.value} ${fmt(model.smoothedSpeed)} ${fmt(model.blurRadius)} ${glyphs}`;
}

function session(reduceMotion, tag) {
  const model = new VelocityGlyphModel({ value: 180, reduceMotion });
  const lines = [traceLine(tag, 0, model)];
  let index = 1;
  const start = model.interactionX;
  model.beginDrag(start);
  const forward = reduceMotion ? 24 : 36;
  const dt = 1 / 60;
  for (let i = 1; i <= forward; i += 1) {
    const x = start + (250 - start) * (i / forward);
    model.updateDrag(x);
    model.step(dt);
    lines.push(traceLine(tag, index, model));
    index += 1;
  }
  if (!reduceMotion) {
    const mid = model.interactionX;
    for (let i = 1; i <= 18; i += 1) {
      const x = mid + (80 - mid) * (i / 18);
      model.updateDrag(x);
      model.step(dt);
      lines.push(traceLine(tag, index, model));
      index += 1;
    }
  }
  model.endDrag();
  lines.push(traceLine(tag, index, model));
  index += 1;
  const tail = reduceMotion ? 12 : 90;
  for (let i = 0; i < tail; i += 1) {
    model.step(dt);
    lines.push(traceLine(tag, index, model));
    index += 1;
  }
  return lines;
}

/** The same text Tests/VelocityGlyphCoreTests writes into Fixtures/golden-trace.txt. */
export function goldenTrace() {
  const lines = ["v1", `dt ${fmt(1 / 60)}`];
  for (const role of [
    { kind: "currency" },
    { kind: "sign" },
    { kind: "digit", place: 0 },
    { kind: "digit", place: 1 },
    { kind: "digit", place: 2 },
    { kind: "separator", group: 1 },
  ]) {
    lines.push(`unit ${roleToken(role)} ${fmt(signedUnit(role))}`);
  }
  for (const value of [40, 180, 600, 1000, -12]) {
    lines.push(`fmt ${value} ${formatPrice(value)}`);
  }
  lines.push(...session(false, "f"));
  lines.push(...session(true, "r"));
  return `${lines.join("\n")}\n`;
}

function easeInOut(t) {
  const x = clamp01(t);
  return x < 0.5 ? 4 * x * x * x : 1 - ((-2 * x + 2) ** 3) / 2;
}

/** Finger x along the 280 pt track, or null when the hand is up. Shared by the canvas preview. */
export function demoFinger(t, startX) {
  if (t < 0.4 || t >= 1.72) return null;
  if (t < 1.2) return startX + (246 - startX) * easeInOut((t - 0.4) / 0.8);
  if (t < 1.32) return 246;
  // A straight flick back. The hand lifts at the end of it, while the glyphs are still tossed.
  return 246 + (70 - 246) * Math.min(1, (t - 1.32) / 0.4);
}

/** Model state `t` seconds into the scripted preview. `dt` is the integration step. */
export function demoAt(t, { reduceMotion = false, step = 1 / 120 } = {}) {
  const model = new VelocityGlyphModel({ value: TUNING.defaultValue, reduceMotion });
  const startX = model.interactionX;
  let down = false;
  let elapsed = 0;
  const duration = Math.max(0, t);
  while (elapsed < duration - 1e-12) {
    const h = Math.min(step, duration - elapsed);
    const x = demoFinger(elapsed + h, startX);
    if (x == null) {
      if (down) { model.endDrag(); down = false; }
    } else if (!down) {
      model.beginDrag(x);
      down = true;
    } else {
      model.updateDrag(x);
    }
    model.step(h);
    elapsed += h;
  }
  return model;
}

export const DEMO_STILLS = [
  { name: "Rest", t: 0.2 },
  { name: "Gathering speed", t: 0.72 },
  { name: "Fast drag", t: 1.55 },
  { name: "Spring overshoot", t: 1.96 },
  { name: "Home", t: 2.85 },
  { name: "Reduce Motion", t: 1.55, reduceMotion: true },
];
