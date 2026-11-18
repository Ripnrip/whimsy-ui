// Glass pay morph. Constants, the spring and the substep order match
// Sources/GlassMorphCore. goldenTrace() matches
// Tests/GlassMorphCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  canvasWidth: 390,
  canvasHeight: 844,
  stageCenter: { x: 195, y: 400 },
  cardWidth: 308,
  cardHeight: 420,
  cardCorner: 32,
  pillWidth: 136,
  pillHeight: 56,
  pillCorner: 28,
  amberRest: { x: 98, y: 258 },
  amberRestRadius: 88,
  amberRestBlur: 18,
  redRest: { x: 322, y: 548 },
  redRestRadius: 50,
  redRestBlur: 14,
  amberLogo: { x: 184, y: 400 },
  amberLogoRadius: 8,
  redLogo: { x: 206, y: 400 },
  redLogoRadius: 7,
  logoBlur: 0,
  morphStiffness: 170,
  morphDamping: 0.75,
  settleTolerance: 0.004,
  holdDuration: 1,
  unfoldDuration: 0.45,
  fadeDuration: 0.28,
  edgeWidth: 0.5,
  substep: 1 / 240,
  maxFrame: 0.1,
  payButtonWidth: 168,
  payButtonHeight: 48,
  payButtonLocal: { x: 0, y: 150 },
  brandLocalY: -158,
  amountLocalY: -40,
  captionLocalY: 16,
  brandSize: 13,
  amountSize: 54,
  captionSize: 15,
  paySize: 17,
  defaultAmount: "$48.00",
  defaultLabel: "Solune",
  payTitle: "Pay",
  caption: "Glass wallet",
  announcement: "Payment complete",
  amber: { r: 255, g: 176, b: 64 },
  red: { r: 255, g: 59, b: 78 },
  backgroundTop: { r: 7, g: 9, b: 20 },
  backgroundBottom: { r: 22, g: 14, b: 34 },
  ink: { r: 18, g: 20, b: 31 },
};

TUNING.cardTilt = (-3 * Math.PI) / 180;

export function clamp(x, lo, hi) {
  return Math.min(Math.max(x, lo), hi);
}
export function clamp01(x) {
  return clamp(x, 0, 1);
}
export function lerp(a, b, t) {
  return a + (b - a) * t;
}
export function lerp2(a, b, t) {
  return { x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) };
}
function progress(x, a, b) {
  if (a === b) return x < a ? 0 : 1;
  return clamp01((x - a) / (b - a));
}
export function smoothstep(a, b, x) {
  const t = progress(x, a, b);
  return t * t * (3 - 2 * t);
}
export function easeInOutCubic(t) {
  const u = clamp01(t);
  if (u < 0.5) return 4 * u * u * u;
  const v = -2 * u + 2;
  return 1 - (v * v * v) / 2;
}

export function frame(p) {
  const t = Number.isFinite(p) ? p : 0;
  const u = clamp01(t);
  return {
    center: TUNING.stageCenter,
    width: Math.max(1, lerp(TUNING.cardWidth, TUNING.pillWidth, t)),
    height: Math.max(1, lerp(TUNING.cardHeight, TUNING.pillHeight, t)),
    cornerRadius: Math.max(0, lerp(TUNING.cardCorner, TUNING.pillCorner, t)),
    tilt: lerp(TUNING.cardTilt, 0, u),
  };
}

export function light(id, p) {
  const t = Number.isFinite(p) ? p : 0;
  const u = clamp01(t);
  if (id === "amber") {
    return {
      center: lerp2(TUNING.amberRest, TUNING.amberLogo, u),
      radius: Math.max(0, lerp(TUNING.amberRestRadius, TUNING.amberLogoRadius, u)),
      blur: Math.max(0, lerp(TUNING.amberRestBlur, TUNING.logoBlur, u)),
    };
  }
  return {
    center: lerp2(TUNING.redRest, TUNING.redLogo, u),
    radius: Math.max(0, lerp(TUNING.redRestRadius, TUNING.redLogoRadius, u)),
    blur: Math.max(0, lerp(TUNING.redRestBlur, TUNING.logoBlur, u)),
  };
}

export function flipAngleAt(age) {
  if (!Number.isFinite(age)) return 0;
  const u = clamp01(age / TUNING.unfoldDuration);
  return Math.PI * easeInOutCubic(u);
}

export function cardContentOpacity(phase, prog, flip, reduceMotion) {
  if (reduceMotion) return 1 - clamp01(prog);
  if (phase === "card") return 1;
  if (phase === "morphing") return 1 - smoothstep(0, 0.22, clamp01(prog));
  if (phase === "pill") return 0;
  return flip >= Math.PI / 2 ? 1 : 0;
}

export function dotOpacity(phase, prog, flip, reduceMotion) {
  if (reduceMotion) return clamp01(prog);
  if (phase === "card") return 0;
  if (phase === "morphing") return smoothstep(0.55, 0.95, clamp01(prog));
  if (phase === "pill") return 1;
  return flip >= Math.PI / 2 ? 0 : 1;
}

export function glowOpacity(phase, prog, flip, reduceMotion) {
  if (reduceMotion) return 1 - clamp01(prog);
  if (phase === "card") return 1;
  if (phase === "morphing") return 1 - smoothstep(0.25, 0.8, clamp01(prog));
  if (phase === "pill") return 0;
  return flip >= Math.PI / 2 ? smoothstep(0.25, 0.8, 1 - clamp01(prog)) : 0;
}

export function edgeGlow(phase, flip, reduceMotion) {
  if (reduceMotion || phase !== "unfolding") return 0;
  const d = Math.abs(flip - Math.PI / 2);
  return clamp01(1 - d / TUNING.edgeWidth);
}

export function displayFlip(flip, reduceMotion) {
  if (reduceMotion) return 0;
  if (flip <= Math.PI / 2) return flip;
  return flip - Math.PI;
}

function rotate(point, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return { x: point.x * c - point.y * s, y: point.x * s + point.y * c };
}

export function createModel(reduceMotion = false) {
  return {
    phase: "card",
    reduceMotion: !!reduceMotion,
    progress: 0,
    progressVelocity: 0,
    flipAngle: 0,
    phaseAge: 0,
    clock: 0,
    settledCount: 0,
  };
}

function springSubstep(value, velocity, target, h) {
  const damping = 2 * TUNING.morphDamping * Math.sqrt(TUNING.morphStiffness);
  const acceleration = TUNING.morphStiffness * (target - value) - damping * velocity;
  const nextVelocity = velocity + acceleration * h;
  return { value: value + nextVelocity * h, velocity: nextVelocity };
}

function isSettled(value, velocity, target) {
  const tolerance = TUNING.settleTolerance;
  return Math.abs(value - target) < tolerance && Math.abs(velocity) < tolerance * 10;
}

export function pay(model) {
  if (model.phase !== "card") return [];
  model.phase = "morphing";
  model.phaseAge = 0;
  model.progress = 0;
  model.progressVelocity = 0;
  model.flipAngle = 0;
  return ["paid"];
}

export function containsPay(model, point) {
  if (model.phase !== "card") return false;
  if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return false;
  const posed = frame(0);
  const local = rotate(
    { x: point.x - posed.center.x, y: point.y - posed.center.y },
    -posed.tilt,
  );
  const dx = Math.abs(local.x - TUNING.payButtonLocal.x);
  const dy = Math.abs(local.y - TUNING.payButtonLocal.y);
  return dx <= TUNING.payButtonWidth / 2 && dy <= TUNING.payButtonHeight / 2;
}

export function payAt(model, point) {
  if (!containsPay(model, point)) return [];
  return pay(model);
}

function arrive(model) {
  model.progress = 1;
  model.progressVelocity = 0;
  model.flipAngle = 0;
  model.phase = "pill";
  model.phaseAge = 0;
  model.settledCount += 1;
  return ["settled"];
}

function beginUnfold(model) {
  model.phase = "unfolding";
  model.phaseAge = 0;
  model.progress = 1;
  model.progressVelocity = 0;
  model.flipAngle = 0;
  return ["unfolding"];
}

function finish(model) {
  model.phase = "card";
  model.progress = 0;
  model.progressVelocity = 0;
  model.flipAngle = 0;
  model.phaseAge = 0;
  return ["returned"];
}

function integrateMorph(model, h) {
  if (model.reduceMotion) {
    model.progress = Math.min(1, model.progress + h / TUNING.fadeDuration);
    model.progressVelocity = 0;
    model.flipAngle = 0;
    if (model.progress >= 1 - 1e-12) return arrive(model);
    return [];
  }
  const next = springSubstep(model.progress, model.progressVelocity, 1, h);
  model.progress = next.value;
  model.progressVelocity = next.velocity;
  if (isSettled(model.progress, model.progressVelocity, 1)) return arrive(model);
  return [];
}

function integratePill(model, h) {
  model.phaseAge += h;
  model.progress = 1;
  model.progressVelocity = 0;
  model.flipAngle = 0;
  if (model.phaseAge >= TUNING.holdDuration - 1e-12) return beginUnfold(model);
  return [];
}

function integrateUnfold(model, h) {
  if (model.reduceMotion) {
    model.progress = Math.max(0, model.progress - h / TUNING.fadeDuration);
    model.progressVelocity = 0;
    model.flipAngle = 0;
    if (model.progress <= 1e-12) return finish(model);
    return [];
  }
  model.phaseAge += h;
  const u = Math.min(1, model.phaseAge / TUNING.unfoldDuration);
  const eased = easeInOutCubic(u);
  model.progress = 1 - eased;
  model.progressVelocity = 0;
  model.flipAngle = Math.PI * eased;
  if (model.phaseAge >= TUNING.unfoldDuration - 1e-12) return finish(model);
  return [];
}

function substep(model, h) {
  if (model.phase === "card") return [];
  model.clock += h;
  if (model.phase === "morphing") return integrateMorph(model, h);
  if (model.phase === "pill") return integratePill(model, h);
  if (model.phase === "unfolding") return integrateUnfold(model, h);
  return [];
}

export function step(model, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || model.phase === "card") return [];
  let remaining = Math.min(dt, TUNING.maxFrame);
  const events = [];
  while (remaining > 1e-12) {
    const h = Math.min(remaining, TUNING.substep);
    events.push(...substep(model, h));
    remaining -= h;
  }
  return events;
}

export function crossfade(model) {
  return model.reduceMotion ? clamp01(model.progress) : 0;
}

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

function traceLine(tag, index, model) {
  const posed = frame(model.progress);
  const amber = light("amber", model.progress);
  const red = light("red", model.progress);
  const flip = model.flipAngle;
  return [
    tag, String(index), model.phase,
    fmt(model.progress), fmt(model.progressVelocity), fmt(flip),
    fmt(posed.width), fmt(posed.height), fmt(posed.tilt),
    fmt(amber.center.x), fmt(amber.center.y), fmt(amber.radius), fmt(amber.blur),
    fmt(red.center.x), fmt(red.center.y), fmt(red.radius), fmt(red.blur),
    fmt(cardContentOpacity(model.phase, model.progress, flip, model.reduceMotion)),
    fmt(dotOpacity(model.phase, model.progress, flip, model.reduceMotion)),
    fmt(glowOpacity(model.phase, model.progress, flip, model.reduceMotion)),
    fmt(edgeGlow(model.phase, flip, model.reduceMotion)),
  ].join(" ");
}

function session(reduceMotion, tag) {
  const model = createModel(reduceMotion);
  const lines = [];
  let index = 0;
  let ignored = false;
  const snap = () => {
    lines.push(traceLine(tag, index, model));
    index += 1;
  };
  const note = (events) => {
    if (!events.length) return;
    lines.push(`${tag} e ${events.join(" ")}`);
  };
  const dt = 1 / 60;
  snap();
  for (let i = 0; i < 6; i += 1) {
    note(step(model, dt));
    snap();
  }
  note(pay(model));
  snap();
  for (let i = 0; i < 360; i += 1) {
    if (!ignored && model.phase === "pill" && model.phaseAge > 0.25) {
      note(pay(model));
      ignored = true;
    }
    const events = step(model, dt);
    note(events);
    snap();
    if (model.phase === "card" && model.clock > 0.2) break;
  }
  for (let i = 0; i < 4; i += 1) {
    note(step(model, dt));
    snap();
  }
  return lines;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(1 / 60)}`,
    `k ${fmt(TUNING.morphStiffness)} ${fmt(TUNING.morphDamping)}`,
    `hold ${fmt(TUNING.holdDuration)} ${fmt(TUNING.unfoldDuration)} ${fmt(TUNING.fadeDuration)}`,
    `tilt ${fmt(TUNING.cardTilt)}`,
    `card ${fmt(TUNING.cardWidth)} ${fmt(TUNING.cardHeight)} ${fmt(TUNING.stageCenter.x)} ${fmt(TUNING.stageCenter.y)}`,
    `pill ${fmt(TUNING.pillWidth)} ${fmt(TUNING.pillHeight)}`,
    `copy ${TUNING.defaultAmount} | ${TUNING.defaultLabel} | ${TUNING.payTitle} | ${TUNING.announcement}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

export const PAY_AT = 0.45;

/** Rebuilds the pose at time `t` of the preview. Pay lands at PAY_AT. */
export function demoAt(t, { reduceMotion = false } = {}) {
  const model = createModel(reduceMotion);
  const dt = 1 / 60;
  let elapsed = 0;
  let paid = false;
  const target = Math.max(0, t);
  while (elapsed < target - 1e-12) {
    const h = Math.min(dt, target - elapsed);
    const next = elapsed + h;
    if (!paid && elapsed < PAY_AT && next >= PAY_AT - 1e-12) {
      const toPay = PAY_AT - elapsed;
      if (toPay > 1e-12) step(model, toPay);
      pay(model);
      paid = true;
      const rest = next - PAY_AT;
      if (rest > 1e-12) step(model, rest);
    } else {
      step(model, h);
    }
    elapsed = next;
  }
  return model;
}

export function demoDuration(reduceMotion = false) {
  const dt = 1 / 60;
  let t = 0;
  let model = createModel(reduceMotion);
  let paid = false;
  let returnedAt = null;
  while (t < 8) {
    const next = t + dt;
    if (!paid && t < PAY_AT && next >= PAY_AT - 1e-12) {
      const toPay = PAY_AT - t;
      if (toPay > 1e-12) step(model, toPay);
      pay(model);
      paid = true;
      const rest = next - PAY_AT;
      if (rest > 1e-12) step(model, rest);
    } else {
      const events = step(model, dt);
      if (events.includes("returned")) returnedAt = next;
    }
    t = next;
    if (returnedAt !== null && t > returnedAt + 0.55) return t;
  }
  return t;
}
