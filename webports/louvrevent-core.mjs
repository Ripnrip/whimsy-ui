// Port of LouvreVentCore. Constants match LouvreVentTuning.swift.
// The golden trace matches Tests/LouvreVentCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  sceneWidth: 390,
  sceneHeight: 844,
  bladeCount: 7,
  minAngle: 0,
  maxAngle: 70,
  defaultLower: 60,
  defaultUpper: 85,
  frameX: 48,
  frameY: 168,
  frameWidth: 270,
  frameHeight: 404,
  bezel: 18,
  frameRadius: 26,
  openingRadius: 10,
  bladeFaceRatio: 0.92,
  stiffness: 220,
  dampingRatio: 0.92,
  settleTolerance: 0.0008,
  sweepRise: 6.5,
  sweepFall: 2.4,
  sweepOmega: 1.7,
  specularStart: 0.18,
  specularTravel: 0.62,
  specularBladePhase: 0.04,
  specularSweepAmplitude: 0.1,
  specularFloor: 0.48,
  specularGain: 0.52,
  coolRed: 0.62,
  coolGreen: 0.16,
  coolBlue: 0.02,
  coolIntensity: 0.42,
  hotRed: 1,
  hotGreen: 0.97,
  hotBlue: 0.91,
  hotIntensity: 1,
  wordmark: "LOUVRE",
  caption: "SET POINT",
  wordmarkY: 108,
  captionY: 136,
  readoutY: 652,
  railX: 344,
  accessibilityLabel: "Louvre vent thermostat",
  accessibilityHint: "Swipe up or down to change the set point by one degree.",
  maxFrame: 0.1,
  maxSubstep: 1 / 240,
};

TUNING.openingX = TUNING.frameX + TUNING.bezel;
TUNING.openingY = TUNING.frameY + TUNING.bezel;
TUNING.openingWidth = TUNING.frameWidth - TUNING.bezel * 2;
TUNING.openingHeight = TUNING.frameHeight - TUNING.bezel * 2;

const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / (2 * Math.PI);

export const DEMO_DURATION = 5.2;

export const DEMO_STILLS = [
  { name: "Closed · 60°F", t: 0.2 },
  { name: "Opening", t: 1.35 },
  { name: "Hot", t: 2.45 },
  { name: "White-hot · 85°F", t: 4.55 },
  { name: "Specular sweep", t: 2.05 },
  { name: "Reduce Motion", t: 2.05, reduceMotion: true },
];

function clamp(x, lo, hi) {
  return Math.min(Math.max(x, lo), hi);
}

function clamp01(x) {
  return clamp(x, 0, 1);
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function progress(x, a, b) {
  if (a === b) return x < a ? 0 : 1;
  return clamp01((x - a) / (b - a));
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

function cos(x) {
  return sin(x + HALF_PI);
}

function roundTemperature(x) {
  if (!Number.isFinite(x)) return 0;
  if (x >= 0) return Math.round(x);
  return -Math.round(-x);
}

export function clampTemperature(temperature, range) {
  return Math.min(Math.max(temperature, range.lower), range.upper);
}

export function unitFor(temperature, range) {
  const t = clampTemperature(temperature, range);
  const span = range.upper - range.lower;
  if (span === 0) return 0;
  return (t - range.lower) / span;
}

export function angleForUnit(unit) {
  return lerp(TUNING.minAngle, TUNING.maxAngle, clamp01(unit));
}

export function glowForUnit(unit) {
  const u = clamp01(unit);
  return {
    red: lerp(TUNING.coolRed, TUNING.hotRed, u),
    green: lerp(TUNING.coolGreen, TUNING.hotGreen, u),
    blue: lerp(TUNING.coolBlue, TUNING.hotBlue, u),
    intensity: lerp(TUNING.coolIntensity, TUNING.hotIntensity, u),
  };
}

export function faceScale(angleDegrees) {
  if (!Number.isFinite(angleDegrees)) return 1;
  return clamp(cos((angleDegrees * PI) / 180), 0, 1);
}

export function triangle(phase) {
  if (!Number.isFinite(phase)) return 0;
  let x = phase - Math.floor(phase);
  if (x < 0) x += 1;
  if (x < 0.25) return x / 0.25;
  if (x < 0.75) return 1 - (x - 0.25) / 0.25;
  return (x - 0.75) / 0.25 - 1;
}

export function restingSpecular(blade, unit) {
  const u = clamp01(unit);
  const index = Math.min(Math.max(blade, 0), TUNING.bladeCount - 1);
  const phase = TUNING.specularBladePhase * index;
  const raw = TUNING.specularStart + TUNING.specularTravel * u + phase * (1 - u) * 0.5;
  return clamp(raw, 0, 1);
}

export function specular(blade, unit, sweep, reduceMotion) {
  const rest = restingSpecular(blade, unit);
  if (reduceMotion || !Number.isFinite(sweep) || sweep === 0) return rest;
  return clamp(rest + TUNING.specularSweepAmplitude * sweep, 0, 1);
}

export function specularIntensity(unit) {
  return TUNING.specularFloor + TUNING.specularGain * glowForUnit(unit).intensity;
}

export function sceneY(temperature, range) {
  const hot = unitFor(temperature, range);
  return TUNING.openingY + (1 - hot) * TUNING.openingHeight;
}

export function temperatureAtY(y, range) {
  if (!Number.isFinite(y)) return range.lower;
  if (range.lower === range.upper) return range.lower;
  const top = TUNING.openingY;
  const bottom = top + TUNING.openingHeight;
  const along = progress(y, top, bottom);
  const raw = range.lower + (range.upper - range.lower) * (1 - along);
  return clampTemperature(roundTemperature(raw), range);
}

function slotsFor(unit, sweep, reduceMotion) {
  const u = clamp01(Number.isFinite(unit) ? unit : 0);
  const degrees = angleForUnit(u);
  const scale = faceScale(degrees);
  const slotHeight = TUNING.openingHeight / TUNING.bladeCount;
  const face = slotHeight * TUNING.bladeFaceRatio;
  const projected = Math.min(slotHeight, face * scale);
  const width = TUNING.openingWidth;
  const x = TUNING.openingX;
  const centerX = x + width / 2;
  const out = [];
  for (let index = 0; index < TUNING.bladeCount; index += 1) {
    const slotTop = TUNING.openingY + index * slotHeight;
    out.push({
      index,
      x,
      slotTop,
      width,
      slotHeight,
      faceHeight: face,
      projectedHeight: projected,
      centerX,
      centerY: slotTop + slotHeight / 2,
      specular: specular(index, u, sweep, reduceMotion),
      angle: degrees,
      gap: (slotHeight - projected) * 0.5,
    });
  }
  return out;
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

function isSettled(spring, target, tolerance) {
  return Math.abs(spring.value - target) < tolerance && Math.abs(spring.velocity) < tolerance * 10;
}

export class LouvreVentModel {
  constructor(temperature = 68, range = { lower: TUNING.defaultLower, upper: TUNING.defaultUpper }, reduceMotion = false) {
    this.range = range;
    this.temperature = clampTemperature(temperature, range);
    this.reduceMotion = reduceMotion;
    this.isDragging = false;
    this.sweepEnvelope = 0;
    this.sweepPhase = 0;
    const unit = unitFor(this.temperature, range);
    this.spring = {
      value: unit,
      velocity: 0,
      stiffness: TUNING.stiffness,
      dampingRatio: TUNING.dampingRatio,
    };
  }

  get targetUnit() {
    return unitFor(this.temperature, this.range);
  }

  get displayedUnit() {
    return this.reduceMotion ? this.targetUnit : this.spring.value;
  }

  get displayVelocity() {
    return this.reduceMotion ? 0 : this.spring.velocity;
  }

  get targetAngle() {
    return angleForUnit(this.targetUnit);
  }

  get displayAngle() {
    return angleForUnit(this.displayedUnit);
  }

  get glow() {
    return glowForUnit(this.displayedUnit);
  }

  get sweepSignal() {
    if (this.reduceMotion || this.sweepEnvelope === 0) return 0;
    return triangle(this.sweepPhase) * this.sweepEnvelope;
  }

  get readout() {
    return String(this.temperature);
  }

  get accessibilityValue() {
    return `${this.temperature} degrees`;
  }

  specularOffset(blade) {
    return specular(blade, this.displayedUnit, this.sweepSignal, this.reduceMotion);
  }

  intensity() {
    return specularIntensity(this.displayedUnit);
  }

  get slots() {
    return slotsFor(this.displayedUnit, this.sweepSignal, this.reduceMotion);
  }

  setTemperature(raw) {
    const events = this.apply(raw);
    if (this.reduceMotion) this.snapDisplay();
    return events;
  }

  adjust(steps) {
    if (steps === 0) return [];
    return this.setTemperature(this.temperature + steps);
  }

  beginDrag(y) {
    if (!Number.isFinite(y)) return [];
    this.isDragging = true;
    return this.setTemperature(temperatureAtY(y, this.range));
  }

  updateDrag(y) {
    if (!this.isDragging || !Number.isFinite(y)) return [];
    return this.setTemperature(temperatureAtY(y, this.range));
  }

  endDrag() {
    this.isDragging = false;
  }

  setReduceMotion(on) {
    if (on === this.reduceMotion) return;
    this.reduceMotion = on;
    if (on) this.snapDisplay();
  }

  step(dt) {
    if (!Number.isFinite(dt) || !(dt > 0)) return;
    const frame = Math.min(dt, TUNING.maxFrame);
    if (this.reduceMotion) {
      this.snapDisplay();
      return;
    }
    springStep(this.spring, this.targetUnit, frame);
    const moving = this.isDragging || !isSettled(this.spring, this.targetUnit, TUNING.settleTolerance);
    this.advanceSweep(frame, moving);
  }

  apply(raw) {
    const next = clampTemperature(raw, this.range);
    const delta = next - this.temperature;
    if (delta === 0) return [];
    const step = delta > 0 ? 1 : -1;
    const events = [];
    let cursor = this.temperature;
    while (cursor !== next) {
      cursor += step;
      events.push(cursor);
    }
    this.temperature = next;
    return events;
  }

  snapDisplay() {
    this.spring.value = this.targetUnit;
    this.spring.velocity = 0;
    this.sweepEnvelope = 0;
    this.sweepPhase = 0;
  }

  advanceSweep(dt, moving) {
    const target = moving ? 1 : 0;
    const rate = moving ? TUNING.sweepRise : TUNING.sweepFall;
    const delta = target - this.sweepEnvelope;
    const limit = rate * dt;
    if (Math.abs(delta) <= limit) this.sweepEnvelope = target;
    else this.sweepEnvelope += delta > 0 ? limit : -limit;
    this.sweepPhase += TUNING.sweepOmega * dt * this.sweepEnvelope;
    if (!Number.isFinite(this.sweepPhase)) {
      this.sweepPhase = 0;
      return;
    }
    this.sweepPhase -= Math.floor(this.sweepPhase);
  }
}

function describe(events) {
  return events.map((degree) => `tick:${degree}`).join(" ");
}

function traceLine(tag, index, model) {
  const glow = model.glow;
  const specs = [];
  for (let blade = 0; blade < TUNING.bladeCount; blade += 1) specs.push(fmt(model.specularOffset(blade)));
  return [
    tag,
    String(index),
    String(model.temperature),
    model.isDragging ? "1" : "0",
    fmt(model.targetUnit),
    fmt(model.displayedUnit),
    fmt(model.targetAngle),
    fmt(model.displayAngle),
    fmt(glow.red),
    fmt(glow.green),
    fmt(glow.blue),
    fmt(glow.intensity),
    fmt(model.sweepEnvelope),
    fmt(model.sweepPhase),
    fmt(model.sweepSignal),
    fmt(model.intensity()),
    specs.join(","),
    fmt(model.slots[0].projectedHeight),
    `"${model.accessibilityValue}"`,
  ].join(" ");
}

function session(reduceMotion, tag) {
  const range = { lower: TUNING.defaultLower, upper: TUNING.defaultUpper };
  const model = new LouvreVentModel(60, range, reduceMotion);
  const lines = [];
  let index = 0;
  const dt = 1 / 60;
  function snap() {
    lines.push(traceLine(tag, index, model));
    index += 1;
  }
  function note(events) {
    if (events.length === 0) return;
    lines.push(`${tag} e ${describe(events)}`);
  }
  snap();
  note(model.setTemperature(68));
  snap();
  const coast = reduceMotion ? 4 : 20;
  for (let i = 0; i < coast; i += 1) {
    model.step(dt);
    snap();
  }
  const startY = sceneY(68, range);
  const endY = sceneY(80, range);
  note(model.beginDrag(startY));
  snap();
  for (let step = 1; step <= 8; step += 1) {
    const y = startY + (endY - startY) * (step / 8);
    note(model.updateDrag(y));
    model.step(dt);
    snap();
  }
  model.endDrag();
  snap();
  const settle = reduceMotion ? 4 : 36;
  for (let i = 0; i < settle; i += 1) {
    model.step(dt);
    snap();
  }
  return lines;
}

export function goldenTrace() {
  const range = { lower: TUNING.defaultLower, upper: TUNING.defaultUpper };
  const lines = [
    "v1",
    `range ${TUNING.defaultLower} ${TUNING.defaultUpper} blades ${TUNING.bladeCount}`,
    `angle ${fmt(TUNING.minAngle)} ${fmt(TUNING.maxAngle)}`,
    `opening ${fmt(TUNING.openingX)} ${fmt(TUNING.openingY)} ${fmt(TUNING.openingWidth)} ${fmt(TUNING.openingHeight)}`,
    `face ${fmt(TUNING.bladeFaceRatio)}`,
    `spring ${fmt(TUNING.stiffness)} ${fmt(TUNING.dampingRatio)} ${fmt(TUNING.settleTolerance)}`,
    `sweep ${fmt(TUNING.sweepRise)} ${fmt(TUNING.sweepFall)} ${fmt(TUNING.sweepOmega)} ${fmt(TUNING.specularSweepAmplitude)}`,
    `spec ${fmt(TUNING.specularStart)} ${fmt(TUNING.specularTravel)} ${fmt(TUNING.specularBladePhase)}`,
    `glow ${fmt(TUNING.coolRed)} ${fmt(TUNING.coolGreen)} ${fmt(TUNING.coolBlue)} ${fmt(TUNING.coolIntensity)} ${fmt(TUNING.hotRed)} ${fmt(TUNING.hotGreen)} ${fmt(TUNING.hotBlue)} ${fmt(TUNING.hotIntensity)}`,
    `math ${fmt(sin(0))} ${fmt(sin(HALF_PI))} ${fmt(cos(0))} ${fmt(cos(PI))} ${fmt(faceScale(70))}`,
  ];
  for (let temperature = TUNING.defaultLower; temperature <= TUNING.defaultUpper; temperature += 1) {
    const unit = unitFor(temperature, range);
    const glow = glowForUnit(unit);
    const degrees = angleForUnit(unit);
    const specs = [];
    for (let blade = 0; blade < TUNING.bladeCount; blade += 1) {
      specs.push(fmt(specular(blade, unit, 0, false)));
    }
    lines.push(
      [
        "map",
        String(temperature),
        fmt(degrees),
        fmt(glow.red),
        fmt(glow.green),
        fmt(glow.blue),
        fmt(glow.intensity),
        fmt(faceScale(degrees)),
        specs.join(","),
      ].join(" "),
    );
  }
  lines.push(...session(false, "f"));
  lines.push(...session(true, "r"));
  return `${lines.join("\n")}\n`;
}

function easeInOut(t) {
  const x = clamp01(t);
  return x < 0.5 ? 4 * x * x * x : 1 - ((-2 * x + 2) ** 3) / 2;
}

/// Scripted drag from closed (60°F) to white-hot (85°F), then a short settle
/// so the highlight can finish its sweep. Reduce Motion snaps and does not sweep.
export function demoAt(t, options = {}) {
  const reduceMotion = !!options.reduceMotion;
  const range = { lower: TUNING.defaultLower, upper: TUNING.defaultUpper };
  const model = new LouvreVentModel(60, range, reduceMotion);
  const dt = 1 / 60;
  const steps = Math.max(0, Math.round(Math.max(0, t) / dt));
  const hold = 0.4;
  const dragEnd = 3.7;
  let dragging = false;
  const coolY = sceneY(60, range);
  const hotY = sceneY(85, range);
  for (let i = 0; i < steps; i += 1) {
    const time = (i + 1) * dt;
    if (time < hold) {
      model.step(dt);
      continue;
    }
    if (time < dragEnd) {
      const along = easeInOut((time - hold) / (dragEnd - hold));
      const y = coolY + (hotY - coolY) * along;
      if (!dragging) {
        model.beginDrag(y);
        dragging = true;
      } else {
        model.updateDrag(y);
      }
      model.step(dt);
      continue;
    }
    if (dragging) {
      model.endDrag();
      dragging = false;
    }
    model.step(dt);
  }
  return model;
}
