// Port of OnAirCore. Constants and the step match Sources/OnAirCore.
// webports/onair-parity.mjs checks goldenTrace() against the Swift fixture.

export const TUNING = {
  sceneWidth: 390,
  sceneHeight: 844,
  pillWidth: 232,
  pillHeight: 88,
  pillX: (390 - 232) / 2,
  pillY: 456,
  knobDiameter: 68,
  knobInset: 10,
  pillGrabPad: 28,
  commitThreshold: 0.5,
  tapSlop: 8,
  stiffness: 260,
  dampingRatio: 0.72,
  settleTolerance: 0.001,
  reduceDuration: 0.28,
  breathPeriod: 2.6,
  breathDepth: 0.28,
  dimFloor: 0.055,
  onAirLabel: "ON AIR",
  wordmark: "Murmur",
  subtitle: "EVENING SHOW",
  wordmarkY: 108,
  subtitleY: 142,
  onAirY: 586,
  timerY: 632,
  meterY: 678,
  meterMaxHeight: 36,
  meterBarWidth: 7,
  meterGap: 6,
  meterCount: 7,
  maxSubstep: 1 / 240,
  maxFrame: 0.1,
};

TUNING.travel = TUNING.pillWidth - TUNING.knobDiameter - 2 * TUNING.knobInset;

const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / TWO_PI;

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

function clamp01(x) {
  return Math.min(Math.max(x, 0), 1);
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function progress(x, a, b) {
  if (a === b) return x < a ? 0 : 1;
  return clamp01((x - a) / (b - a));
}

function smoothstep(a, b, x) {
  const t = progress(x, a, b);
  return t * t * (3 - 2 * t);
}

function easeInOutCubic(t) {
  const u = clamp01(t);
  return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
}

export function formatClock(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return "00:00";
  const cap = 99 * 60 + 59;
  const whole = Math.min(Math.floor(seconds), cap);
  const m = Math.floor(whole / 60);
  const s = whole % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export function knobCenter(p) {
  const visual = Math.min(Math.max(p, -0.05), 1.05);
  return {
    x: TUNING.pillX + TUNING.knobInset + TUNING.knobDiameter / 2 + TUNING.travel * visual,
    y: TUNING.pillY + TUNING.pillHeight / 2,
  };
}

export function progressForSceneX(x) {
  if (!Number.isFinite(x)) return 0;
  const start = TUNING.pillX + TUNING.knobInset + TUNING.knobDiameter / 2;
  return clamp01((x - start) / TUNING.travel);
}

export function sceneX(p) {
  const start = TUNING.pillX + TUNING.knobInset + TUNING.knobDiameter / 2;
  return start + TUNING.travel * clamp01(p);
}

function pillContains(y) {
  if (!Number.isFinite(y)) return false;
  return y >= TUNING.pillY - TUNING.pillGrabPad && y <= TUNING.pillY + TUNING.pillHeight + TUNING.pillGrabPad;
}

export function dimAmount(p) {
  return smoothstep(0.05, 0.95, clamp01(p));
}

export function backgroundMultiply(p) {
  return lerp(1, TUNING.dimFloor, dimAmount(p));
}

export function breath(time, reduceMotion) {
  if (reduceMotion || !Number.isFinite(time) || time <= 0) return 1;
  const wave = cos((TWO_PI * time) / TUNING.breathPeriod);
  return 1 - TUNING.breathDepth * (1 - wave) * 0.5;
}

export function glow(p, elapsed, live, reduceMotion) {
  const base = smoothstep(0.38, 1, clamp01(p));
  if (!live || reduceMotion) return base;
  return base * breath(elapsed, false);
}

export function chromeOpacity(p) {
  return smoothstep(0.58, 0.94, clamp01(p));
}

export function meterLevels(time, reduceMotion) {
  const out = [];
  for (let index = 0; index < TUNING.meterCount; index += 1) {
    if (reduceMotion || !Number.isFinite(time)) {
      out.push(0.34 + 0.08 * (index % 4));
    } else {
      const phase = time * (1.7 + 0.31 * index) + 0.55 * index;
      const wave = 0.5 + 0.5 * sin(phase);
      out.push(0.16 + 0.84 * wave);
    }
  }
  return out;
}

function Spring(value) {
  this.value = value;
  this.velocity = 0;
  this.stiffness = TUNING.stiffness;
  this.dampingRatio = TUNING.dampingRatio;
}

Spring.prototype.damping = function damping() {
  return 2 * this.dampingRatio * Math.sqrt(this.stiffness);
};

Spring.prototype.step = function step(target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, TUNING.maxFrame);
  while (remaining > 1e-12) {
    const h = Math.min(remaining, TUNING.maxSubstep);
    const acc = this.stiffness * (target - this.value) - this.damping() * this.velocity;
    this.velocity += acc * h;
    this.value += this.velocity * h;
    remaining -= h;
  }
};

Spring.prototype.snap = function snap(target) {
  this.value = target;
  this.velocity = 0;
};

Spring.prototype.isSettled = function isSettled(target, tolerance) {
  const tol = tolerance == null ? 0.001 : tolerance;
  return Math.abs(this.value - target) < tol && Math.abs(this.velocity) < tol * 10;
};

export function OnAirModel({ isOn = false, reduceMotion = false } = {}) {
  this.isOn = isOn;
  this.isDragging = false;
  this.elapsed = 0;
  this.reduceMotion = reduceMotion;
  this.spring = new Spring(isOn ? 1 : 0);
  this.progressBeforeDrag = isOn ? 1 : 0;
  this.fading = false;
  this.fadeOrigin = isOn ? 1 : 0;
  this.fadeDestination = isOn ? 1 : 0;
  this.fadeElapsed = 0;
  this.hapticArmed = false;
}

OnAirModel.prototype.throwProgress = function throwProgress() {
  return this.spring.value;
};

OnAirModel.prototype.dim = function dim() {
  return dimAmount(this.throwProgress());
};

OnAirModel.prototype.multiply = function multiply() {
  return backgroundMultiply(this.throwProgress());
};

OnAirModel.prototype.glowValue = function glowValue() {
  return glow(this.throwProgress(), this.elapsed, this.isOn, this.reduceMotion);
};

OnAirModel.prototype.chrome = function chrome() {
  return chromeOpacity(this.throwProgress());
};

OnAirModel.prototype.timerText = function timerText() {
  return formatClock(this.elapsed);
};

OnAirModel.prototype.accessibilityValue = function accessibilityValue() {
  return this.isOn ? `On air, ${this.timerText()}` : "Off";
};

OnAirModel.prototype.meter = function meter() {
  return meterLevels(this.elapsed, this.reduceMotion);
};

OnAirModel.prototype.knob = function knob() {
  return knobCenter(this.throwProgress());
};

OnAirModel.prototype.isHome = function isHome(destination) {
  return this.spring.isSettled(destination, TUNING.settleTolerance);
};

OnAirModel.prototype.beginFade = function beginFade(destination) {
  this.fadeOrigin = this.spring.value;
  this.fadeDestination = destination;
  this.fadeElapsed = 0;
  this.fading = Math.abs(this.spring.value - destination) > TUNING.settleTolerance;
  if (!this.fading) this.spring.snap(destination);
};

OnAirModel.prototype.setOn = function setOn(on) {
  this.isDragging = false;
  const events = [];
  if (on !== this.isOn) {
    this.isOn = on;
    if (on) this.elapsed = 0;
    events.push({ kind: "committed", on });
  }
  const destination = on ? 1 : 0;
  if (this.reduceMotion) {
    this.beginFade(destination);
    if (this.fading) {
      this.hapticArmed = true;
    } else if (events.length) {
      this.spring.snap(destination);
      this.hapticArmed = false;
      events.push({ kind: "haptic" });
      if (!on) this.elapsed = 0;
    }
    return events;
  }
  if (this.isHome(destination)) {
    this.spring.snap(destination);
    this.hapticArmed = false;
    if (events.length) {
      events.push({ kind: "haptic" });
      if (!on) this.elapsed = 0;
    }
    return events;
  }
  this.hapticArmed = true;
  return events;
};

OnAirModel.prototype.toggle = function toggle() {
  return this.setOn(!this.isOn);
};

OnAirModel.prototype.beginDrag = function beginDrag(x, y) {
  if (!Number.isFinite(x) || !pillContains(y)) return false;
  this.progressBeforeDrag = this.spring.value;
  this.isDragging = true;
  this.fading = false;
  this.hapticArmed = false;
  this.spring.snap(progressForSceneX(x));
  return true;
};

OnAirModel.prototype.updateDrag = function updateDrag(x) {
  if (!this.isDragging || !Number.isFinite(x)) return;
  this.spring.snap(progressForSceneX(x));
};

OnAirModel.prototype.endDrag = function endDrag(translation) {
  if (!this.isDragging) return [];
  if (!Number.isFinite(translation)) {
    this.spring.snap(this.progressBeforeDrag);
    return this.setOn(this.isOn);
  }
  if (Math.abs(translation) <= TUNING.tapSlop) {
    this.spring.snap(this.progressBeforeDrag);
    return this.setOn(!this.isOn);
  }
  return this.setOn(this.spring.value >= TUNING.commitThreshold);
};

OnAirModel.prototype.step = function step(dt) {
  if (!Number.isFinite(dt) || !(dt > 0)) return [];
  const frame = Math.min(dt, TUNING.maxFrame);
  if (this.isDragging) {
    if (this.isOn) this.elapsed += frame;
    return [];
  }
  const events = this.reduceMotion ? this.advanceFade(frame) : this.advanceSpring(frame);
  if (this.isOn) this.elapsed += frame;
  return events;
};

OnAirModel.prototype.advanceSpring = function advanceSpring(frame) {
  const destination = this.isOn ? 1 : 0;
  const events = [];
  if (!this.spring.isSettled(destination, TUNING.settleTolerance)) {
    this.spring.step(destination, frame);
  }
  if (this.hapticArmed) {
    const reached = destination >= 1 ? this.spring.value >= 1 : this.spring.value <= 0;
    const seated = this.spring.isSettled(destination, TUNING.settleTolerance);
    if (reached || seated) {
      events.push({ kind: "haptic" });
      this.hapticArmed = false;
    }
  }
  if (this.spring.isSettled(destination, TUNING.settleTolerance)) {
    this.spring.snap(destination);
    if (!this.isOn) this.elapsed = 0;
  }
  return events;
};

OnAirModel.prototype.advanceFade = function advanceFade(frame) {
  const destination = this.isOn ? 1 : 0;
  if (!this.fading) {
    if (this.spring.isSettled(destination, TUNING.settleTolerance)) {
      this.spring.snap(destination);
      if (!this.isOn) this.elapsed = 0;
    }
    return [];
  }
  this.fadeElapsed += frame;
  const t = Math.min(1, this.fadeElapsed / TUNING.reduceDuration);
  const value = this.fadeOrigin + (this.fadeDestination - this.fadeOrigin) * easeInOutCubic(t);
  this.spring.snap(value);
  const events = [];
  if (t >= 1) {
    this.fading = false;
    this.spring.snap(this.fadeDestination);
    if (this.hapticArmed) {
      events.push({ kind: "haptic" });
      this.hapticArmed = false;
    }
    if (!this.isOn) this.elapsed = 0;
  }
  return events;
};

function fmt(x) {
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

function describe(event) {
  if (event.kind === "haptic") return "haptic";
  return `committed ${event.on ? 1 : 0}`;
}

function traceLine(tag, index, model) {
  const meter = model.meter().map(fmt).join(",");
  return [
    tag, String(index), model.isOn ? "1" : "0", model.isDragging ? "1" : "0",
    fmt(model.throwProgress()), fmt(model.spring.velocity),
    fmt(model.dim()), fmt(model.glowValue()), fmt(model.multiply()),
    fmt(model.chrome()), fmt(model.elapsed), model.timerText(),
    `"${model.accessibilityValue()}"`, meter,
  ].join(" ");
}

function session(reduceMotion, tag) {
  const model = new OnAirModel({ reduceMotion });
  const lines = [];
  let index = 0;
  const dt = 1 / 60;
  const y = TUNING.pillY + TUNING.pillHeight / 2;
  const snap = () => {
    lines.push(traceLine(tag, index, model));
    index += 1;
  };
  const note = (events) => {
    if (!events.length) return;
    lines.push(`${tag} e ${events.map(describe).join(" ")}`);
  };
  snap();
  for (let i = 0; i < 4; i += 1) {
    note(model.step(dt));
    snap();
  }
  note(model.setOn(true));
  snap();
  const coast = reduceMotion ? 24 : 130;
  for (let i = 0; i < coast; i += 1) {
    note(model.step(dt));
    snap();
  }
  if (!reduceMotion) {
    const grabbed = model.beginDrag(sceneX(0.82), y);
    if (!grabbed) note([{ kind: "committed", on: false }]);
    snap();
    for (let stepIndex = 1; stepIndex <= 6; stepIndex += 1) {
      const p = 0.82 - 0.12 * stepIndex;
      model.updateDrag(sceneX(p));
      note(model.step(dt));
      snap();
    }
    note(model.endDrag(48));
    snap();
    for (let i = 0; i < 70; i += 1) {
      note(model.step(dt));
      snap();
    }
  } else {
    note(model.setOn(false));
    snap();
    for (let i = 0; i < 24; i += 1) {
      note(model.step(dt));
      snap();
    }
  }
  return lines;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(1 / 60)}`,
    `spring ${fmt(TUNING.stiffness)} ${fmt(TUNING.dampingRatio)}`,
    `threshold ${fmt(TUNING.commitThreshold)} slop ${fmt(TUNING.tapSlop)}`,
    `dim ${fmt(TUNING.dimFloor)} breath ${fmt(TUNING.breathPeriod)} ${fmt(TUNING.breathDepth)}`,
    `reduce ${fmt(TUNING.reduceDuration)}`,
    `pill ${fmt(TUNING.pillX)} ${fmt(TUNING.pillY)} ${fmt(TUNING.pillWidth)} ${fmt(TUNING.pillHeight)}`,
    `knob ${fmt(TUNING.knobDiameter)} ${fmt(TUNING.knobInset)} travel ${fmt(TUNING.travel)}`,
    `copy ${TUNING.onAirLabel} | ${formatClock(83)}`,
    `math ${fmt(sin(0))} ${fmt(sin(HALF_PI))} ${fmt(cos(0))} ${fmt(cos(PI))}`,
  ];
  lines.push(...session(false, "f"));
  lines.push(...session(true, "r"));
  return `${lines.join("\n")}\n`;
}

const DT = 1 / 60;

function scriptFrame(model, frame) {
  const y = TUNING.pillY + TUNING.pillHeight / 2;
  if (frame === 18) model.beginDrag(sceneX(0), y);
  if (frame > 18 && frame < 50) {
    const u = (frame - 18) / 32;
    model.updateDrag(sceneX(u * 0.78));
  }
  if (frame === 50) model.endDrag(140);
  if (frame === 360) model.toggle();
}

export const DEMO_DURATION = 7;

export function demoAt(t, { reduceMotion = false } = {}) {
  const model = new OnAirModel({ reduceMotion });
  const steps = Math.max(0, Math.round((Number.isFinite(t) ? t : 0) / DT));
  for (let i = 0; i < steps; i += 1) {
    scriptFrame(model, i);
    model.step(DT);
  }
  return model;
}

export const DEMO_STILLS = [
  { name: "Off air", t: 0.15 },
  { name: "Dragging", t: 0.55 },
  { name: "The throw", t: 1.1 },
  { name: "Breath low", t: 2.15 },
  { name: "On air", t: 4.2 },
  { name: "Leaving", t: 6.3 },
  { name: "Reduce Motion", t: 2.15, reduceMotion: true },
  { name: "Settled off", t: 6.9 },
];
