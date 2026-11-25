// Port of LiquidRepDialCore. Constants match LiquidRepTuning.swift.
// The golden trace matches Tests/LiquidRepCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  sceneWidth: 390,
  sceneHeight: 844,
  defaultGoal: 20,
  minimumGoal: 1,
  maxReps: 999,
  bounce: 0.4,
  dampingRatio: 0.6,
  stiffness: 120,
  impulse: 2.4,
  settleTolerance: 0.0015,
  sloshStiffness: 70,
  maxSlosh: 0.48,
  fullTilt: 0.4,
  meniscusOmega: 16,
  meniscusRise: 6,
  meniscusFall: 2.4,
  meniscusSpeed: 1.6,
  meniscusTrim: 0.018,
  meniscusBulge: 7,
  crossfadeDuration: 0.28,
  glowFloor: 0.22,
  glowSpan: 0.5,
  goalGlowFloor: 0.78,
  goalGlowPulse: 0.22,
  goalGlowSteady: 1,
  goalOmega: 5.2,
  wordmark: "LIQUID",
  caption: "REP DIAL",
  repsLabel: "REPS",
  wordmarkY: 148,
  captionY: 178,
  goalY: 576,
  dialDiameter: 220,
  stroke: 16,
  dialCenter: { x: 195, y: 430 },
  numberY: 418,
  repsLabelY: 468,
  hitSlop: 18,
  maxFrame: 0.1,
  maxSubstep: 1 / 240,
  backgroundTop: [0.03, 0.05, 0.1],
  backgroundBottom: [0.05, 0.09, 0.16],
  glassInner: [0.05, 0.09, 0.18],
  glassOuter: [0.11, 0.18, 0.32],
  glassEdge: [0.72, 0.82, 0.92],
  track: [1, 1, 1],
  limeDeep: [0.36, 0.72, 0.18],
  lime: [0.64, 0.93, 0.22],
  limeBright: [0.88, 1, 0.62],
  number: [0.94, 0.97, 0.99],
  label: [0.71, 0.86, 0.46],
  wordmarkColor: [0.86, 0.91, 0.96],
  captionColor: [0.55, 0.66, 0.76],
  accessibilityLabel: "Liquid rep dial",
  accessibilityHint: "Adds one rep.",
  addRepAction: "Add rep",
};

TUNING.ringRadius = (TUNING.dialDiameter - TUNING.stroke) / 2;

export const REEL = {
  dt: 1 / 60,
  goal: 20,
  motionFrames: 420,
  reduceCueFrame: 20,
  reduceSpan: 76,
};

REEL.totalFrames = REEL.motionFrames + REEL.reduceSpan;
REEL.duration = REEL.totalFrames * REEL.dt;

const CUES = [
  { frame: 30, kind: "add" },
  { frame: 72, kind: "add" },
  { frame: 108, kind: "add" },
  { frame: 150, kind: "reps", count: 10 },
  { frame: 198, kind: "tilt", roll: 0.15, pitch: 0.55 },
  { frame: 250, kind: "level" },
  { frame: 270, kind: "reps", count: 17 },
  { frame: 330, kind: "reps", count: 20 },
];

export const STILLS = [
  { name: "Idle empty", frame: 12 },
  { name: "First tap overshoot", frame: 38 },
  { name: "Mid fill", frame: 190 },
  { name: "Near goal", frame: 306 },
  { name: "Goal reached glow", frame: 366 },
  { name: "Tilt slosh", frame: 226 },
  { name: "Reduce Motion", frame: 448 },
];

const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const EIGHTH_PI = Math.PI / 8;
const INV_TWO_PI = 1 / (2 * Math.PI);

function clamp(x, lo, hi) {
  return Math.min(Math.max(x, lo), hi);
}

function clamp01(x) {
  return clamp(x, 0, 1);
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

function atanSeries(x) {
  const x2 = x * x;
  let p = 1 / 17;
  p = -1 / 15 + x2 * p;
  p = 1 / 13 + x2 * p;
  p = -1 / 11 + x2 * p;
  p = 1 / 9 + x2 * p;
  p = -1 / 7 + x2 * p;
  p = 1 / 5 + x2 * p;
  p = -1 / 3 + x2 * p;
  p = 1 + x2 * p;
  return x * p;
}

export function atan(z) {
  if (!Number.isFinite(z)) {
    if (z > 0) return HALF_PI;
    if (z < 0) return -HALF_PI;
    return 0;
  }
  const negative = z < 0;
  let x = Math.abs(z);
  let complement = false;
  if (x > 1) {
    x = 1 / x;
    complement = true;
  }
  let add = 0;
  const tanEighth = Math.sqrt(2) - 1;
  if (x > tanEighth) {
    x = (x - tanEighth) / (1 + x * tanEighth);
    add = EIGHTH_PI;
  }
  let result = atanSeries(x) + add;
  if (complement) result = HALF_PI - result;
  return negative ? -result : result;
}

export function atan2(y, x) {
  if (!Number.isFinite(y) || !Number.isFinite(x)) return 0;
  if (x > 0) return atan(y / x);
  if (x < 0) {
    const base = atan(y / x);
    return y >= 0 ? base + PI : base - PI;
  }
  if (y > 0) return HALF_PI;
  if (y < 0) return -HALF_PI;
  return 0;
}

export function shortest(start, end) {
  return atan2(sin(end - start), cos(end - start));
}

export function pool(fill) {
  const unit = Number.isFinite(fill) ? clamp01(fill) : 0;
  return sin(unit * PI);
}

export function sloshTarget(fill, tilt) {
  const unit = Number.isFinite(fill) ? clamp01(fill) : 0;
  const weight = pool(unit);
  if (weight === 0) return 0;
  const roll = Number.isFinite(tilt.roll) ? tilt.roll : 0;
  const pitch = Number.isFinite(tilt.pitch) ? tilt.pitch : 0;
  const gx = sin(roll);
  const gy = sin(pitch);
  const mag = Math.sqrt(gx * gx + gy * gy);
  if (mag < 1e-9) return 0;
  const strength = Math.min(mag / TUNING.fullTilt, 1);
  const low = atan2(gx, -gy);
  const restCenter = unit * TWO_PI * 0.5;
  const delta = shortest(restCenter, low);
  return clamp(delta * strength * weight, -TUNING.maxSlosh, TUNING.maxSlosh);
}

export function glowFor(fill, atGoal, elapsed, reduceMotion) {
  const f = Number.isFinite(fill) ? clamp(fill, 0, 1) : 0;
  if (atGoal) {
    if (reduceMotion || !Number.isFinite(elapsed)) return TUNING.goalGlowSteady;
    const wave = 0.5 + 0.5 * sin(elapsed * TUNING.goalOmega);
    return clamp(TUNING.goalGlowFloor + TUNING.goalGlowPulse * wave, 0, 1);
  }
  return clamp(TUNING.glowFloor + TUNING.glowSpan * f, 0, 1);
}

export function rimFor(fill, sloshAngle, meniscus, glowValue) {
  const clamped = Number.isFinite(fill) ? clamp(fill, 0, 1) : 0;
  const wobble = Number.isFinite(meniscus) ? meniscus : 0;
  const trim = clamp(clamped + wobble * TUNING.meniscusTrim, 0, 1);
  const slosh = Number.isFinite(sloshAngle) ? sloshAngle : 0;
  const rotation = -HALF_PI + slosh;
  const angle = slosh + trim * TWO_PI;
  const bulge = wobble * TUNING.meniscusBulge;
  const radius = TUNING.ringRadius + bulge;
  const center = TUNING.dialCenter;
  const leading = {
    x: center.x + sin(angle) * radius,
    y: center.y - cos(angle) * radius,
  };
  return {
    trim,
    rotation,
    slosh,
    meniscus: wobble,
    glow: Number.isFinite(glowValue) ? glowValue : 0,
    bulge,
    leading,
    center,
    radius: TUNING.ringRadius,
  };
}

function springMake(value, stiffness) {
  return {
    value,
    velocity: 0,
    stiffness: Math.max(stiffness, 0),
    dampingRatio: Math.max(TUNING.dampingRatio, 0),
  };
}

function springStep(spring, target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, TUNING.maxFrame);
  const damping = 2 * spring.dampingRatio * Math.sqrt(Math.max(spring.stiffness, 0));
  while (remaining > 1e-12) {
    const h = Math.min(remaining, TUNING.maxSubstep);
    const acceleration = spring.stiffness * (target - spring.value) - damping * spring.velocity;
    spring.velocity += acceleration * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
}

function springSnap(spring, target) {
  spring.value = target;
  spring.velocity = 0;
}

export class LiquidRepModel {
  constructor(reps = 0, goal = TUNING.defaultGoal, tilt = { roll: 0, pitch: 0 }, reduceMotion = false) {
    const clampedGoal = Math.max(TUNING.minimumGoal, goal);
    const clampedReps = Math.min(Math.max(reps, 0), TUNING.maxReps);
    this.reps = clampedReps;
    this.goal = clampedGoal;
    this.reduceMotion = reduceMotion;
    this.tilt = {
      roll: Number.isFinite(tilt.roll) ? tilt.roll : 0,
      pitch: Number.isFinite(tilt.pitch) ? tilt.pitch : 0,
    };
    const fill = clamp(clampedReps / clampedGoal, 0, 1);
    this.spring = springMake(fill, TUNING.stiffness);
    this.slosh = springMake(0, TUNING.sloshStiffness);
    this.fadeFrom = fill;
    this.fadeTo = fill;
    this.fadeElapsed = TUNING.crossfadeDuration;
    this.fadeShown = fill;
    this.meniscusEnvelope = 0;
    this.meniscusPhase = 0;
    this.elapsed = 0;
  }

  get targetFill() {
    if (!(this.goal > 0)) return 0;
    return clamp(this.reps / this.goal, 0, 1);
  }

  get displayedFill() {
    return this.reduceMotion ? this.fadeShown : this.spring.value;
  }

  get fillVelocity() {
    return this.reduceMotion ? 0 : this.spring.velocity;
  }

  get sloshAngle() {
    return this.reduceMotion ? 0 : this.slosh.value;
  }

  get meniscus() {
    if (this.reduceMotion) return 0;
    return this.meniscusEnvelope * sin(this.meniscusPhase);
  }

  get atGoal() {
    return this.reps >= this.goal;
  }

  get glow() {
    return glowFor(this.displayedFill, this.atGoal, this.elapsed, this.reduceMotion);
  }

  get rim() {
    return rimFor(this.displayedFill, this.sloshAngle, this.meniscus, this.glow);
  }

  get readout() {
    return String(this.reps);
  }

  addRep() {
    return this.setReps(this.reps + 1);
  }

  setReps(raw) {
    const next = Math.min(Math.max(raw, 0), TUNING.maxReps);
    if (next === this.reps) return [];
    const previous = this.reps;
    this.reps = next;
    if (next > previous) {
      const events = [];
      const steps = next - previous;
      for (let i = 0; i < steps; i += 1) events.push("tick");
      if (previous < this.goal && next >= this.goal) events.push("goal");
      this.retarget(true);
      return events;
    }
    this.retarget(false);
    return [];
  }

  setGoal(raw) {
    const next = Math.max(TUNING.minimumGoal, raw);
    if (next === this.goal) return;
    this.goal = next;
    this.retarget(false);
  }

  setTilt(tilt) {
    this.tilt = {
      roll: Number.isFinite(tilt.roll) ? tilt.roll : 0,
      pitch: Number.isFinite(tilt.pitch) ? tilt.pitch : 0,
    };
  }

  setReduceMotion(on) {
    if (on === this.reduceMotion) return;
    this.reduceMotion = on;
    if (on) {
      const shown = this.spring.value;
      this.fadeFrom = shown;
      this.fadeTo = this.targetFill;
      this.fadeElapsed = 0;
      this.fadeShown = shown;
      springSnap(this.spring, shown);
      springSnap(this.slosh, 0);
      this.meniscusEnvelope = 0;
      this.meniscusPhase = 0;
      this.elapsed = 0;
    } else {
      springSnap(this.spring, this.fadeShown);
    }
  }

  step(dt) {
    if (!Number.isFinite(dt) || !(dt > 0)) return;
    const frame = Math.min(dt, TUNING.maxFrame);
    if (this.reduceMotion) {
      this.advanceFade(frame);
      return;
    }
    this.elapsed += frame;
    springStep(this.spring, this.targetFill, frame);
    const goal = sloshTarget(this.targetFill, this.tilt);
    springStep(this.slosh, goal, frame);
    this.advanceMeniscus(frame);
  }

  retarget(kick) {
    if (this.reduceMotion) {
      this.fadeFrom = this.displayedFill;
      this.fadeTo = this.targetFill;
      this.fadeElapsed = 0;
      springSnap(this.spring, this.displayedFill);
      springSnap(this.slosh, 0);
      this.meniscusEnvelope = 0;
      this.meniscusPhase = 0;
      return;
    }
    if (kick) this.spring.velocity += TUNING.impulse;
  }

  advanceFade(dt) {
    const duration = TUNING.crossfadeDuration;
    this.fadeElapsed = Math.min(duration, this.fadeElapsed + dt);
    const t = duration > 0 ? this.fadeElapsed / duration : 1;
    this.fadeShown = this.fadeFrom + (this.fadeTo - this.fadeFrom) * t;
    springSnap(this.spring, this.fadeShown);
    springSnap(this.slosh, 0);
    this.meniscusEnvelope = 0;
  }

  advanceMeniscus(dt) {
    const speed = Math.abs(this.spring.velocity);
    const target = Number.isFinite(speed) ? clamp01(speed / TUNING.meniscusSpeed) : 0;
    const rate = target > this.meniscusEnvelope ? TUNING.meniscusRise : TUNING.meniscusFall;
    const delta = target - this.meniscusEnvelope;
    const limit = rate * dt;
    if (Math.abs(delta) <= limit) {
      this.meniscusEnvelope = target;
    } else {
      this.meniscusEnvelope += delta > 0 ? limit : -limit;
    }
    const drive = 0.35 + 0.65 * this.meniscusEnvelope;
    this.meniscusPhase += TUNING.meniscusOmega * dt * drive;
  }
}

function applyCue(model, cue) {
  if (cue.kind === "add") model.addRep();
  else if (cue.kind === "reps") model.setReps(cue.count);
  else if (cue.kind === "tilt") model.setTilt({ roll: cue.roll, pitch: cue.pitch });
  else if (cue.kind === "level") model.setTilt({ roll: 0, pitch: 0 });
}

function motionModel(steps) {
  const model = new LiquidRepModel(0, REEL.goal, { roll: 0, pitch: 0 }, false);
  const limit = Math.max(0, steps);
  for (let frame = 0; frame < limit; frame += 1) {
    for (const cue of CUES) {
      if (cue.frame === frame) applyCue(model, cue);
    }
    model.step(REEL.dt);
  }
  return model;
}

function reduceModel(local) {
  const model = new LiquidRepModel(0, REEL.goal, { roll: 0, pitch: 0 }, true);
  const limit = Math.max(0, local);
  for (let frame = 0; frame < limit; frame += 1) {
    if (frame === REEL.reduceCueFrame) model.setReps(12);
    model.step(REEL.dt);
  }
  return model;
}

export function frameCount(time) {
  if (!Number.isFinite(time) || !(time > 0)) return 0;
  return Math.floor(time / REEL.dt + 0.5);
}

export function modelAtFrame(frame) {
  if (frame >= REEL.motionFrames) return reduceModel(frame - REEL.motionFrames);
  return motionModel(Math.max(0, frame));
}

export function demoAt(time) {
  return modelAtFrame(frameCount(time));
}

export const DEMO_DURATION = REEL.duration;
export const DEMO_STILLS = STILLS;

function body(model) {
  const rim = model.rim;
  return [
    String(model.reps),
    String(model.goal),
    fmt(model.targetFill),
    fmt(model.displayedFill),
    fmt(model.fillVelocity),
    fmt(model.sloshAngle),
    fmt(model.meniscus),
    fmt(model.meniscusEnvelope),
    fmt(model.glow),
    fmt(model.elapsed),
    fmt(rim.trim),
    fmt(rim.rotation),
    fmt(rim.leading.x),
    fmt(rim.leading.y),
    model.reduceMotion ? "1" : "0",
    model.atGoal ? "1" : "0",
  ].join(" ");
}

function note(tag, events) {
  if (events.length === 0) return `${tag} e`;
  return `${tag} e ${events.join(" ")}`;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(REEL.dt)}`,
    `bounce ${fmt(TUNING.bounce)} zeta ${fmt(TUNING.dampingRatio)}`,
    `spring ${fmt(TUNING.stiffness)} ${fmt(TUNING.impulse)} ${fmt(TUNING.sloshStiffness)}`,
    `slosh ${fmt(TUNING.maxSlosh)} ${fmt(TUNING.fullTilt)}`,
    `meniscus ${fmt(TUNING.meniscusOmega)} ${fmt(TUNING.meniscusTrim)} ${fmt(TUNING.meniscusBulge)}`,
    `fade ${fmt(TUNING.crossfadeDuration)}`,
    `dial ${fmt(TUNING.dialCenter.x)} ${fmt(TUNING.dialCenter.y)} ${fmt(TUNING.dialDiameter)} ${fmt(TUNING.ringRadius)}`,
    `sin ${fmt(sin(0))} ${fmt(sin(HALF_PI))} ${fmt(sin(PI))}`,
    `atan ${fmt(atan(0))} ${fmt(atan(1))} ${fmt(atan2(1, 0))}`,
    `reel ${REEL.totalFrames} ${fmt(REEL.duration)}`,
  ];
  const model = new LiquidRepModel(0, 20, { roll: 0, pitch: 0 }, false);
  lines.push(`s ${body(model)}`);
  lines.push(note("s", model.addRep()));
  lines.push(`s ${body(model)}`);
  for (let i = 0; i < 12; i += 1) {
    model.step(REEL.dt);
    lines.push(`s ${body(model)}`);
  }
  model.setTilt({ roll: 0.15, pitch: 0.55 });
  for (let i = 0; i < 8; i += 1) {
    model.step(REEL.dt);
    lines.push(`s ${body(model)}`);
  }
  lines.push(note("s", model.setReps(20)));
  lines.push(`s ${body(model)}`);

  const reduced = new LiquidRepModel(0, 20, { roll: 0, pitch: 0 }, true);
  lines.push(note("r", reduced.setReps(12)));
  lines.push(`r ${body(reduced)}`);
  for (let i = 0; i < 6; i += 1) {
    reduced.step(REEL.dt);
    lines.push(`r ${body(reduced)}`);
  }
  reduced.setReduceMotion(true);
  lines.push(`r ${body(reduced)}`);

  const frames = STILLS.map((still) => still.frame).concat([0, 30, 31, 80, 420, REEL.totalFrames - 1]);
  const seen = [];
  for (const frame of frames) {
    if (seen.includes(frame)) continue;
    seen.push(frame);
    lines.push(`f ${frame} ${body(modelAtFrame(frame))}`);
  }
  return `${lines.join("\n")}\n`;
}
