// JS port of RotaryDialCore. Constants match RotaryDialTuning / RotaryDialMath / RotaryDialModel.
// The golden trace is the script in Tests/RotaryDialCoreTests/GoldenTraceTests.swift.

export const canvasWidth = 390;
export const canvasHeight = 844;
export const centerX = 195;
export const centerY = 500;
export const outerRadius = 148;
export const faceRadius = 132;
export const holeOrbit = 102;
export const holeRadius = 20;
export const hubRadius = 26;
export const hitSlop = 6;
export const holeCount = 10;
export const holeStep = Math.PI / 6;
export const stopAngle = Math.PI / 5;
export const maxTravel = holeStep * 10;
export const commitSlop = holeStep * 0.42;
export const digitCount = 4;
export const springStiffness = 400;
export const springDampingRatio = 1;
export const dropDuration = 0.38;
export const shakeDuration = 0.56;
export const shakeAmplitude = 16;
export const shakeCycles = 5;
export const tintDuration = 0.32;
export const morphDuration = 0.55;
export const reduceMorphDuration = 0.28;
export const dotsY = 156;
export const dotGap = 36;
export const dotRadius = 11;
export const captionY = 214;
export const keySize = 62;
export const keyGap = 16;
export const badgeSize = 128;
export const keyOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2];
export const defaultCode = "5216";
export const restCaption = "Drag a number to the stop";
export const wrongCaption = "Wrong code";
export const keypadCaption = "Try the keypad";
export const unlockedCaption = "Unlocked";
export const wrongAnnouncement = "Incorrect, try again";
export const unlockedAnnouncement = "Unlocked";

export const palette = {
  ground: [0.09, 0.07, 0.06],
  lift: [0.20, 0.15, 0.11],
  paper: [0.96, 0.93, 0.86],
  ink: [0.14, 0.10, 0.08],
  metal: [0.28, 0.22, 0.18],
  brass: [0.72, 0.54, 0.28],
  hole: [0.08, 0.06, 0.05],
  success: [52 / 255, 199 / 255, 76 / 255],
  error: [217 / 255, 45 / 255, 32 / 255],
};

export function enteredAnnouncement(count) {
  return `${count} of ${digitCount}`;
}

export function keypadWidth() {
  return keySize * 3 + keyGap * 2 + 48;
}
export function keypadHeight() {
  return keySize * 4 + keyGap * 3 + 64;
}

export function dotCenter(slot) {
  const span = (digitCount - 1) * dotGap;
  return { x: centerX - span / 2 + slot * dotGap, y: dotsY };
}

export function keyCenter(digit) {
  const index = keyOrder.indexOf(digit);
  const at = index < 0 ? 10 : index;
  const column = at % 3;
  const row = Math.floor(at / 3);
  const pitch = keySize + keyGap;
  const gridW = keySize * 3 + keyGap * 2;
  const gridH = keySize * 4 + keyGap * 3;
  const left = centerX - gridW / 2 + keySize / 2;
  const top = centerY - gridH / 2 + keySize / 2;
  return { x: left + column * pitch, y: top + row * pitch };
}

export function plateShape(face) {
  if (face === "dial") {
    const d = outerRadius * 2;
    return { width: d, height: d, corner: outerRadius };
  }
  if (face === "keypad") return { width: keypadWidth(), height: keypadHeight(), corner: 32 };
  return { width: badgeSize, height: badgeSize, corner: badgeSize / 2 };
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}
function clamp(x, lo, hi) {
  return Math.min(Math.max(x, lo), hi);
}
function clamp01(x) {
  return clamp(x, 0, 1);
}

export function wrapPi(angle) {
  if (!Number.isFinite(angle)) return 0;
  const tau = Math.PI * 2;
  let x = angle % tau;
  if (x <= -Math.PI) x += tau;
  if (x > Math.PI) x -= tau;
  return x;
}

export function sinPoly(radians) {
  const x = wrapPi(radians);
  const x2 = x * x;
  let term = x;
  let sum = x;
  let n = 1;
  for (let i = 0; i < 8; i += 1) {
    term *= -x2 / ((2 * n) * (2 * n + 1));
    sum += term;
    n += 1;
  }
  return sum;
}

export function pulse(digit) {
  return digit === 0 ? holeCount : digit;
}
export function display(pulseCount) {
  return pulseCount === holeCount ? 0 : pulseCount;
}
export function travel(digit) {
  return pulse(digit) * holeStep;
}
export function restAngle(digit) {
  return stopAngle - travel(digit);
}

export function holeCenter(digit, rotation) {
  const angle = restAngle(digit) + rotation;
  return {
    x: centerX + holeOrbit * Math.cos(angle),
    y: centerY + holeOrbit * Math.sin(angle),
  };
}

export function pointOnOrbit(angle, radius) {
  return { x: centerX + radius * Math.cos(angle), y: centerY + radius * Math.sin(angle) };
}

export function detentIndex(rotation) {
  if (!Number.isFinite(rotation) || rotation <= 0) return 0;
  const steps = rotation / holeStep + 1e-9;
  const index = Math.floor(steps);
  return Math.min(Math.max(index, 0), holeCount);
}

export function clampRotation(rotation, limit) {
  const cap = Math.min(Math.max(limit, 0), maxTravel);
  return clamp(rotation, 0, cap);
}

export function easeInOut(t) {
  const u = clamp01(t);
  if (u < 0.5) return 4 * u * u * u;
  const v = -2 * u + 2;
  return 1 - (v * v * v) / 2;
}

export function easeOut(t) {
  const u = 1 - clamp01(t);
  return 1 - u * u * u;
}

export function shakeOffset(t, reduceMotion) {
  if (reduceMotion) return 0;
  if (t <= 0 || t >= shakeDuration) return 0;
  const u = t / shakeDuration;
  const envelope = (1 - u) * (1 - u);
  const theta = 2 * Math.PI * shakeCycles * u;
  return shakeAmplitude * envelope * sinPoly(theta);
}

export function hitDigit(point, rotation) {
  if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
  const reach = holeRadius + hitSlop;
  const reach2 = reach * reach;
  let best = null;
  let bestDistance = reach2;
  for (let digit = 0; digit < holeCount; digit += 1) {
    const center = holeCenter(digit, rotation);
    const dx = point.x - center.x;
    const dy = point.y - center.y;
    const distance = dx * dx + dy * dy;
    if (distance <= bestDistance) {
      bestDistance = distance;
      best = digit;
    }
  }
  return best;
}

export function fingerAngle(point) {
  const dx = point.x - centerX;
  const dy = point.y - centerY;
  if (dx === 0 && dy === 0) return null;
  if (!Number.isFinite(dx) || !Number.isFinite(dy)) return null;
  return Math.atan2(dy, dx);
}

function digitsParsing(code) {
  const raw = [];
  for (const ch of String(code)) {
    if (ch >= "0" && ch <= "9") raw.push(Number(ch));
  }
  if (raw.length >= digitCount) return raw.slice(0, digitCount);
  return [...Array(digitCount - raw.length).fill(0), ...raw];
}

function springMake(value) {
  return { value, velocity: 0, stiffness: springStiffness, dampingRatio: springDampingRatio };
}

function springCoeff(spring) {
  return 2 * spring.dampingRatio * Math.sqrt(spring.stiffness);
}

function springStep(spring, target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, 0.1);
  const maxSub = 1 / 240;
  while (remaining > 1e-12) {
    const h = Math.min(remaining, maxSub);
    const acceleration = spring.stiffness * (target - spring.value) - springCoeff(spring) * spring.velocity;
    spring.velocity += acceleration * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
}

function springSettled(spring, target) {
  return Math.abs(spring.value - target) < 1e-3 && Math.abs(spring.velocity) < 1e-2;
}

export function createModel(code = defaultCode, reduceMotion = false) {
  return {
    expected: digitsParsing(code),
    reduceMotion,
    phase: "idle",
    face: "dial",
    morphFrom: "dial",
    morph: 1,
    rotation: 0,
    velocity: 0,
    digits: [],
    grabbed: null,
    time: 0,
    shakeTime: 0,
    spring: springMake(0),
    awaitingVerdict: false,
    lastFinger: 0,
    fingerUnwrapped: 0,
    grabFinger: 0,
    grabRotation: 0,
    detent: 0,
  };
}

export function entered(model) {
  return model.digits.map((digit) => digit.digit);
}

function dropOf(model, digit) {
  if (model.reduceMotion) return 1;
  return clamp01((model.time - digit.startedAt) / dropDuration);
}

export function dropProgress(model, slot) {
  if (slot < 0 || slot >= model.digits.length) return 0;
  return dropOf(model, model.digits[slot]);
}

export function glyphPoint(model, slot) {
  const progress = easeOut(dropProgress(model, slot));
  const origin = model.digits[slot].origin;
  const dot = dotCenter(slot);
  return { x: lerp(origin.x, dot.x, progress), y: lerp(origin.y, dot.y, progress) };
}

export function dotFilled(model, slot) {
  return slot >= 0 && slot < model.digits.length && dropProgress(model, slot) >= 1;
}

export function caption(model) {
  if (model.phase === "unlocked") return unlockedCaption;
  if (model.phase === "shaking") return wrongCaption;
  if (model.face === "keypad") return keypadCaption;
  if (model.digits.length === 0) return restCaption;
  return enteredAnnouncement(model.digits.length);
}

export function visualPlate(model) {
  const t = easeInOut(model.morph);
  const a = plateShape(model.morphFrom);
  const b = plateShape(model.face);
  return {
    width: lerp(a.width, b.width, t),
    height: lerp(a.height, b.height, t),
    corner: lerp(a.corner, b.corner, t),
  };
}

export function opacity(model, target) {
  const t = easeInOut(model.morph);
  if (model.face === target && model.morphFrom === target) return 1;
  if (model.face === target) return t;
  if (model.morphFrom === target) return 1 - t;
  return 0;
}

export function modelShake(model) {
  if (model.phase !== "shaking") return 0;
  return shakeOffset(model.shakeTime, model.reduceMotion);
}

export function errorTint(model) {
  if (model.phase !== "shaking") return 0;
  const duration = model.reduceMotion ? tintDuration : shakeDuration;
  if (duration <= 0) return 0;
  return Math.max(0, 1 - model.shakeTime / duration);
}

export function acceptsDialDrag(model) {
  return model.face === "dial"
    && model.digits.length < digitCount
    && !model.awaitingVerdict
    && (model.phase === "idle" || model.phase === "dragging");
}

function sameCode(model) {
  const have = entered(model);
  if (have.length !== model.expected.length) return false;
  for (let i = 0; i < have.length; i += 1) if (have[i] !== model.expected[i]) return false;
  return true;
}

function ticksBetween(oldIndex, newIndex) {
  const events = [];
  if (newIndex > oldIndex) {
    for (let pulse = oldIndex + 1; pulse <= newIndex; pulse += 1) events.push({ kind: "tick", digit: display(pulse) });
  } else if (newIndex < oldIndex) {
    for (let pulse = oldIndex; pulse > newIndex; pulse -= 1) events.push({ kind: "tick", digit: display(pulse) });
  }
  return events;
}

function setRotation(model, next) {
  if (model.grabbed == null) return [];
  const limit = travel(model.grabbed);
  model.rotation = clampRotation(next, limit);
  model.velocity = 0;
  const index = detentIndex(model.rotation);
  if (index === model.detent) return [];
  const events = ticksBetween(model.detent, index);
  model.detent = index;
  return events;
}

function appendDigit(model, digit, origin) {
  model.digits.push({ digit, startedAt: model.time, origin });
}

function beginMorph(model, target) {
  if (model.face === target) {
    model.morph = 1;
    model.morphFrom = target;
    model.phase = target === "badge" ? "unlocked" : "keypad";
    return target === "badge" ? [{ kind: "unlocked" }] : [];
  }
  model.morphFrom = model.face;
  model.face = target;
  model.morph = 0;
  model.phase = "morphing";
  return [];
}

function beginShake(model) {
  model.phase = "shaking";
  model.shakeTime = 0;
  return [{ kind: "wrong" }];
}

function finishMorph(model) {
  model.morph = 1;
  model.morphFrom = model.face;
  if (model.face === "badge") {
    model.phase = "unlocked";
    return [{ kind: "unlocked" }];
  }
  model.digits = [];
  model.phase = "keypad";
  return [{ kind: "morphedKeypad" }];
}

function finishShake(model) {
  model.digits = [];
  if (model.face === "dial") return beginMorph(model, "keypad");
  model.phase = "keypad";
  return [];
}

function readyForVerdict(model) {
  if (!model.awaitingVerdict || model.digits.length !== digitCount) return false;
  if (model.phase !== "idle" && model.phase !== "keypad") return false;
  return model.digits.every((digit) => dropOf(model, digit) >= 1);
}

function startVerdict(model) {
  model.awaitingVerdict = false;
  if (sameCode(model)) return beginMorph(model, "badge");
  return beginShake(model);
}

export function beginDragDigit(model, digit) {
  if (!acceptsDialDrag(model) || model.phase === "dragging" || digit < 0 || digit > 9) return [];
  model.phase = "dragging";
  model.grabbed = digit;
  model.grabRotation = model.rotation;
  model.grabFinger = 0;
  model.fingerUnwrapped = 0;
  model.lastFinger = 0;
  model.detent = detentIndex(model.rotation);
  return [];
}

export function dragByClockwise(model, delta) {
  if (model.phase !== "dragging" || model.grabbed == null || !Number.isFinite(delta)) return [];
  model.fingerUnwrapped += delta;
  const limit = travel(model.grabbed);
  const target = clampRotation(model.grabRotation + (model.fingerUnwrapped - model.grabFinger), limit);
  return setRotation(model, target);
}

export function beginDragAt(model, point) {
  if (!acceptsDialDrag(model) || model.phase === "dragging") return [];
  const digit = hitDigit(point, model.rotation);
  const angle = fingerAngle(point);
  if (digit == null || angle == null) return [];
  model.phase = "dragging";
  model.grabbed = digit;
  model.grabRotation = model.rotation;
  model.grabFinger = angle;
  model.fingerUnwrapped = angle;
  model.lastFinger = angle;
  model.detent = detentIndex(model.rotation);
  return [];
}

export function updateDragAt(model, point) {
  if (model.phase !== "dragging" || model.grabbed == null) return [];
  const angle = fingerAngle(point);
  if (angle == null) return [];
  const delta = wrapPi(angle - model.lastFinger);
  model.lastFinger = angle;
  model.fingerUnwrapped += delta;
  const limit = travel(model.grabbed);
  const target = clampRotation(model.grabRotation + (model.fingerUnwrapped - model.grabFinger), limit);
  return setRotation(model, target);
}

export function release(model) {
  if (model.phase !== "dragging" || model.grabbed == null) return [];
  const grabbed = model.grabbed;
  const limit = travel(grabbed);
  const accept = model.rotation + 1e-9 >= limit - commitSlop && model.rotation > 0;
  const events = [];
  if (accept) {
    appendDigit(model, grabbed, holeCenter(grabbed, model.rotation));
    events.push({ kind: "committed", digit: grabbed });
  } else {
    events.push({ kind: "rejected" });
  }
  if (model.rotation > 0.01) events.push({ kind: "springBack" });
  model.grabbed = null;
  if (model.reduceMotion) {
    model.spring = springMake(0);
    model.rotation = 0;
    model.velocity = 0;
    model.phase = "idle";
    if (model.digits.length === digitCount) events.push(...startVerdict(model));
  } else {
    model.spring = springMake(model.rotation);
    model.velocity = 0;
    model.phase = "springing";
    if (model.digits.length === digitCount) model.awaitingVerdict = true;
  }
  return events;
}

export function enterDigit(model, digit) {
  if (digit < 0 || digit > 9) return [];
  if (model.digits.length >= digitCount || model.awaitingVerdict) return [];
  if (model.phase !== "idle" && model.phase !== "keypad") return [];
  const origin = model.face === "keypad" ? keyCenter(digit) : holeCenter(digit, 0);
  appendDigit(model, digit, origin);
  const events = [{ kind: "committed", digit }];
  if (model.digits.length === digitCount) {
    if (model.reduceMotion) events.push(...startVerdict(model));
    else model.awaitingVerdict = true;
  }
  return events;
}

export function deleteDigit(model) {
  if ((model.phase !== "idle" && model.phase !== "keypad") || model.awaitingVerdict || model.digits.length === 0) return [];
  model.digits.pop();
  return [{ kind: "deleted" }];
}

export function step(model, dt) {
  if (!Number.isFinite(dt) || dt <= 0) return [];
  const h = Math.min(dt, 0.1);
  model.time += h;
  const events = [];
  if (model.phase === "springing") {
    springStep(model.spring, 0, h);
    model.rotation = model.spring.value;
    model.velocity = model.spring.velocity;
    if (model.spring.value <= 0 || springSettled(model.spring, 0)) {
      model.spring = springMake(0);
      model.rotation = 0;
      model.velocity = 0;
      model.phase = "idle";
    }
  } else if (model.phase === "shaking") {
    model.shakeTime += h;
    const duration = model.reduceMotion ? tintDuration : shakeDuration;
    if (model.shakeTime >= duration) {
      model.shakeTime = duration;
      events.push(...finishShake(model));
    }
  } else if (model.phase === "morphing") {
    const duration = model.reduceMotion ? reduceMorphDuration : morphDuration;
    model.morph += h / duration;
    if (model.morph >= 1) {
      model.morph = 1;
      events.push(...finishMorph(model));
    }
  }
  if (readyForVerdict(model)) events.push(...startVerdict(model));
  return events;
}

export function reset(model) {
  const code = model.expected.join("");
  const reduceMotion = model.reduceMotion;
  const fresh = createModel(code, reduceMotion);
  Object.assign(model, fresh);
}

function describe(event) {
  switch (event.kind) {
    case "tick": return `tick ${event.digit}`;
    case "committed": return `committed ${event.digit}`;
    case "rejected": return "rejected";
    case "springBack": return "springBack";
    case "wrong": return "wrong";
    case "deleted": return "deleted";
    case "morphedKeypad": return "morphedKeypad";
    case "unlocked": return "unlocked";
    default: return event.kind;
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

function stateLine(tag, index, model) {
  const plate = visualPlate(model);
  const have = entered(model);
  const text = have.length === 0 ? "-" : have.join("");
  const drops = [0, 1, 2, 3].map((slot) => fmt(dropProgress(model, slot))).join(",");
  return [
    tag, String(index), model.phase, model.face, model.morphFrom, text,
    fmt(model.rotation), fmt(model.velocity), fmt(model.morph),
    fmt(modelShake(model)), fmt(errorTint(model)),
    fmt(plate.width), fmt(plate.height), fmt(plate.corner),
    drops, caption(model),
  ].join(" ");
}

function session(reduceMotion, tag) {
  const model = createModel("5216", reduceMotion);
  const lines = [];
  let index = 0;
  const dt = 1 / 60;
  const snap = () => {
    lines.push(stateLine(tag, index, model));
    index += 1;
  };
  const note = (events) => {
    if (!events.length) return;
    lines.push(`${tag} e ${events.map(describe).join(" ")}`);
  };
  const frames = (count) => {
    for (let i = 0; i < count; i += 1) {
      note(step(model, dt));
      snap();
    }
  };
  snap();
  if (reduceMotion) {
    note(beginDragDigit(model, 5));
    snap();
    const slice = travel(5) / 5;
    for (let i = 0; i < 5; i += 1) {
      note(dragByClockwise(model, slice));
      snap();
    }
    note(release(model));
    snap();
    for (const digit of [2, 1, 0]) {
      note(enterDigit(model, digit));
      snap();
    }
    frames(40);
    for (const digit of [5, 2, 1, 6]) {
      note(enterDigit(model, digit));
      snap();
    }
    frames(24);
    return lines;
  }
  note(beginDragDigit(model, 5));
  snap();
  const slice = travel(5) / 5;
  for (let i = 0; i < 8; i += 1) {
    note(dragByClockwise(model, slice));
    snap();
  }
  note(dragByClockwise(model, -holeStep * 0.2));
  snap();
  note(release(model));
  snap();
  frames(36);
  for (const digit of [2, 1, 0]) {
    note(enterDigit(model, digit));
    snap();
  }
  frames(100);
  for (const digit of [5, 2, 1, 6]) {
    note(enterDigit(model, digit));
    snap();
  }
  frames(70);
  return lines;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(1 / 60)}`,
    `step ${fmt(holeStep)}`,
    `stop ${fmt(stopAngle)}`,
    `travel5 ${fmt(travel(5))}`,
    `travel0 ${fmt(travel(0))}`,
    `sin ${fmt(sinPoly(0))} ${fmt(sinPoly(0.3))} ${fmt(sinPoly(Math.PI))}`,
    `shake ${fmt(shakeOffset(0.12, false))} ${fmt(shakeOffset(0.12, true))}`,
    `copy ${restCaption} | ${wrongAnnouncement} | ${unlockedAnnouncement}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

/// Scripted phone demo. A wrong dial becomes the keypad, then 5216 unlocks.
export function demoAt(time) {
  const model = createModel("5216", false);
  const moves = [
    { digit: 5, t0: 0.35, t1: 1.15 },
    { digit: 2, t0: 1.95, t1: 2.5 },
    { digit: 1, t0: 3.2, t1: 3.6 },
    { digit: 0, t0: 4.3, t1: 5.45 },
  ];
  const taps = [
    { digit: 5, t: 7.45 },
    { digit: 2, t: 7.85 },
    { digit: 1, t: 8.25 },
    { digit: 6, t: 8.65 },
  ];
  const dt = 1 / 60;
  const limit = Math.max(0, time);
  let cursor = 0;
  let active = null;
  let sent = 0;
  const ease = (u) => easeInOut(u);
  while (cursor < limit - 1e-12) {
    const next = Math.min(cursor + dt, limit);
    for (const move of moves) {
      if (!active && cursor < move.t0 && next >= move.t0) {
        beginDragDigit(model, move.digit);
        active = { ...move, travel: travel(move.digit), spun: 0 };
      }
    }
    if (active) {
      const u = clamp01((next - active.t0) / (active.t1 - active.t0));
      const want = ease(u) * active.travel;
      dragByClockwise(model, want - active.spun);
      active.spun = want;
      if (next >= active.t1) {
        release(model);
        active = null;
      }
    }
    while (sent < taps.length && next >= taps[sent].t) {
      enterDigit(model, taps[sent].digit);
      sent += 1;
    }
    step(model, next - cursor);
    cursor = next;
  }
  return model;
}

export const demoDuration = 10.1;

export const stillTimes = [
  { t: 0.2, label: "At rest" },
  { t: 0.78, label: "Dialing 5" },
  { t: 1.28, label: "Digit drops" },
  { t: 6.3, label: "Wrong code" },
  { t: 7.35, label: "Keypad" },
  { t: 9.85, label: "Unlocked" },
];
