// Port of KoiPondCore. Constants and the fixed-step pond match
// Sources/KoiPondCore and Tests/KoiPondCoreTests/Fixtures/golden-trace.txt.

const MASK = (1n << 64n) - 1n;
export const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / TWO_PI;

export const TUNING = {
  sceneWidth: 390,
  sceneHeight: 844,
  pondX: 28,
  pondY: 128,
  pondWidth: 334,
  pondHeight: 600,
  outerInset: 8,
  headInset: 36,
  defaultCount: 6,
  maxKoi: 8,
  spineCount: 5,
  segmentLength: 18,
  bodyWidths: [10.5, 13, 10, 5.5, 1.6],
  fixedStep: 1 / 60,
  maxFrame: 0.1,
  longPress: 0.24,
  stagger: 0.2,
  lapSpeed: 46,
  seekSpeed: 128,
  scatterSpeed: 168,
  scatterDuration: 0.72,
  scatterFan: 0.55,
  scatterTurnRate: 8.5,
  turnRate: 3.4,
  arriveRadius: 22,
  holdRadius: 48,
  arriveSlow: 70,
  nibbleGap: 18,
  bobAmplitude: 6,
  bobOmega: 8.2,
  nibbleLeash: 8,
  nibbleThreshold: 0.35,
  returnCatch: 42,
  returnTimeout: 3.4,
  lapLookahead: 0.55,
  orbitMin: 0.36,
  orbitMax: 0.7,
  orbitJitter: 0.42,
  omegaMin: 0.32,
  omegaMax: 0.58,
  tailOmega: 8.4,
  tailAmplitude: 0.52,
  tailLag: 0.62,
  reduceScale: 0.42,
  feedDuration: 3.6,
  feedCap: 14,
  gatherLife: 1.25,
  nibbleLife: 0.72,
  gatherRadius: 148,
  nibbleRadius: 34,
  reduceGatherRadius: 36,
  reduceNibbleRadius: 14,
  maxRipples: 14,
  defaultSeed: 0x4B6F694E69622B31n,
  swimmingValue: "Koi swimming",
  nibblingValue: "Koi nibbling",
  feedAction: "Feed koi",
  title: "Koi",
  hint: "Hold to feed",
  paper: [0.91, 0.945, 0.925],
  waterDeep: [0.047, 0.227, 0.259],
  waterMid: [0.094, 0.431, 0.463],
  waterShallow: [0.306, 0.659, 0.627],
  sand: [0.769, 0.643, 0.471],
  stone: [0.42, 0.455, 0.431],
  lily: [0.18, 0.471, 0.282],
  lilyDark: [0.11, 0.333, 0.196],
  flower: [0.91, 0.471, 0.541],
  finger: [0.941, 0.769, 0.667],
  ink: [0.102, 0.141, 0.149],
  lilies: [
    [86, 246, 30],
    [308, 612, 36],
    [96, 648, 18],
  ],
  palettes: [
    { body: [0.91, 0.384, 0.165], belly: [1, 0.925, 0.839], fin: [0.769, 0.243, 0.125] },
    { body: [0.965, 0.949, 0.918], belly: [1, 0.98, 0.953], fin: [0.769, 0.188, 0.165] },
    { body: [0.91, 0.69, 0.243], belly: [1, 0.894, 0.667], fin: [0.71, 0.42, 0.11] },
    { body: [0.141, 0.157, 0.188], belly: [0.91, 0.69, 0.243], fin: [0.91, 0.384, 0.165] },
    { body: [0.957, 0.769, 0.306], belly: [1, 0.945, 0.78], fin: [0.831, 0.51, 0.141] },
    { body: [0.824, 0.212, 0.188], belly: [0.98, 0.941, 0.91], fin: [0.62, 0.11, 0.125] },
  ],
};

export function pondCenter() {
  return { x: TUNING.pondX + TUNING.pondWidth / 2, y: TUNING.pondY + TUNING.pondHeight / 2 };
}

export function headRadii() {
  const rx = TUNING.pondWidth / 2 - TUNING.outerInset - TUNING.headInset;
  const ry = TUNING.pondHeight / 2 - TUNING.outerInset - TUNING.headInset;
  return { rx, ry };
}

export function fingerRadii() {
  const head = headRadii();
  return {
    rx: head.rx - TUNING.nibbleGap - TUNING.bobAmplitude,
    ry: head.ry - TUNING.nibbleGap - TUNING.bobAmplitude,
  };
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

function atanSeries(z) {
  const z2 = z * z;
  let n = 41;
  let acc = 1 / n;
  while (n > 1) {
    n -= 2;
    acc = 1 / n - z2 * acc;
  }
  return z * acc;
}

export function atan(x) {
  if (!Number.isFinite(x)) {
    if (x > 0) return HALF_PI;
    if (x < 0) return -HALF_PI;
    return 0;
  }
  const negative = x < 0;
  let a = negative ? -x : x;
  let complement = false;
  if (a > 1) {
    a = 1 / a;
    complement = true;
  }
  const tanSixth = 0.5773502691896257;
  const sixth = PI / 6;
  let base;
  if (a > tanSixth) {
    const t = (a - tanSixth) / (1 + a * tanSixth);
    base = sixth + atanSeries(t);
  } else {
    base = atanSeries(a);
  }
  const angle = complement ? HALF_PI - base : base;
  return negative ? -angle : angle;
}

export function atan2(y, x) {
  if (!Number.isFinite(y) || !Number.isFinite(x)) return 0;
  if (x > 0) return atan(y / x);
  if (x < 0) return y >= 0 ? atan(y / x) + PI : atan(y / x) - PI;
  if (y > 0) return HALF_PI;
  if (y < 0) return -HALF_PI;
  return 0;
}

export function wrap(angle) {
  if (!Number.isFinite(angle)) return 0;
  const k = Math.floor((angle + PI) * INV_TWO_PI);
  return angle - k * TWO_PI;
}

export function turn(heading, desired, rate, dt) {
  if (!Number.isFinite(heading) || !Number.isFinite(desired) || !Number.isFinite(rate) || !(dt > 0)) {
    return heading;
  }
  let delta = wrap(desired - heading);
  const maxStep = Math.max(rate, 0) * dt;
  if (delta > maxStep) delta = maxStep;
  if (delta < -maxStep) delta = -maxStep;
  return wrap(heading + delta);
}

function clampEllipse(p, rx, ry) {
  const c = pondCenter();
  if (!Number.isFinite(p.x) || !Number.isFinite(p.y) || !(rx > 0) || !(ry > 0)) return { x: c.x, y: c.y };
  const nx = (p.x - c.x) / rx;
  const ny = (p.y - c.y) / ry;
  const d2 = nx * nx + ny * ny;
  if (d2 <= 1) return { x: p.x, y: p.y };
  const d = Math.sqrt(d2);
  return { x: c.x + (nx / d) * rx, y: c.y + (ny / d) * ry };
}

export function clampHead(p) {
  const r = headRadii();
  return clampEllipse(p, r.rx, r.ry);
}

export function clampFinger(p) {
  const r = fingerRadii();
  return clampEllipse(p, r.rx, r.ry);
}

export function lapPoint(angle, scale) {
  const c = pondCenter();
  const r = headRadii();
  return {
    x: c.x + cos(angle) * r.rx * scale,
    y: c.y + sin(angle) * r.ry * scale,
  };
}

function constrain(spine, heading) {
  if (spine.length < 2) return;
  for (let i = 1; i < spine.length; i += 1) {
    let dx = spine[i].x - spine[i - 1].x;
    let dy = spine[i].y - spine[i - 1].y;
    let len = Math.sqrt(dx * dx + dy * dy);
    if (len < 1e-8) {
      dx = -cos(heading);
      dy = -sin(heading);
      len = 1;
    }
    const scale = TUNING.segmentLength / len;
    spine[i] = { x: spine[i - 1].x + dx * scale, y: spine[i - 1].y + dy * scale };
  }
}

function distance(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

class SplitMix {
  constructor(seed) {
    this.state = BigInt(seed) & MASK;
  }
  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
    let z = this.state;
    z = (z ^ (z >> 30n)) & MASK;
    z = (z * 0xBF58476D1CE4E5B9n) & MASK;
    z = (z ^ (z >> 27n)) & MASK;
    z = (z * 0x94D049BB133111EBn) & MASK;
    return (z ^ (z >> 31n)) & MASK;
  }
  uniform(lo, hi) {
    const unit = Number(this.next() >> 11n) / Number(1n << 53n);
    return lo + (hi - lo) * unit;
  }
}

function posedSpine(fish, time) {
  const spine = fish.spine;
  if (spine.length < 2 || !Number.isFinite(time)) return spine.map((p) => ({ x: p.x, y: p.y }));
  const out = spine.map((p) => ({ x: p.x, y: p.y }));
  const last = spine.length - 1;
  for (let i = 1; i < spine.length; i += 1) {
    const dx = spine[i].x - spine[i - 1].x;
    const dy = spine[i].y - spine[i - 1].y;
    const base = atan2(dy, dx);
    const envelope = i / last;
    const wave = sin(TUNING.tailOmega * time + fish.tailPhase - i * TUNING.tailLag) * TUNING.tailAmplitude * envelope;
    const angle = base + wave;
    out[i] = {
      x: out[i - 1].x + cos(angle) * TUNING.segmentLength,
      y: out[i - 1].y + sin(angle) * TUNING.segmentLength,
    };
  }
  return out;
}

function rippleRadius(ripple) {
  const life = Math.max(ripple.lifetime, 1e-6);
  const u = Math.min(Math.max(ripple.age / life, 0), 1);
  if (ripple.reduceMotion) {
    return ripple.kind === "gather" ? TUNING.reduceGatherRadius : TUNING.reduceNibbleRadius;
  }
  const eased = 1 - (1 - u) * (1 - u) * (1 - u);
  return ripple.maxRadius * eased;
}

function rippleOpacity(ripple) {
  const life = Math.max(ripple.lifetime, 1e-6);
  const u = Math.min(Math.max(ripple.age / life, 0), 1);
  if (ripple.reduceMotion) return (1 - u) * 0.65;
  const fadeIn = Math.min(1, ripple.age / 0.08);
  return (1 - u) * fadeIn;
}

export class KoiPondModel {
  constructor({ koiCount = TUNING.defaultCount, seed = TUNING.defaultSeed, reduceMotion = false } = {}) {
    const count = Math.min(Math.max(koiCount, 1), TUNING.maxKoi);
    const rng = new SplitMix(seed);
    this.fish = [];
    for (let index = 0; index < count; index += 1) {
      const orbit = rng.uniform(TUNING.orbitMin, TUNING.orbitMax);
      const jitter = rng.uniform(-TUNING.orbitJitter, TUNING.orbitJitter);
      const spacing = TWO_PI / count;
      const angle = wrap((index + 0.5) * spacing + jitter);
      const omegaMag = rng.uniform(TUNING.omegaMin, TUNING.omegaMax);
      const omega = omegaMag * (rng.uniform(0, 1) < 0.5 ? -1 : 1);
      const tailPhase = rng.uniform(0, TWO_PI);
      const heading = wrap(angle + (omega >= 0 ? HALF_PI : -HALF_PI));
      const head = lapPoint(angle, orbit);
      const spine = [{ x: head.x, y: head.y }];
      for (let joint = 1; joint < TUNING.spineCount; joint += 1) {
        const prev = spine[joint - 1];
        spine.push({
          x: prev.x - cos(heading) * TUNING.segmentLength,
          y: prev.y - sin(heading) * TUNING.segmentLength,
        });
      }
      this.fish.push({
        index,
        spine,
        heading,
        mode: "lap",
        lapAngle: angle,
        lapOmega: omega,
        orbitScale: orbit,
        tailPhase,
        bobSample: 0,
        modeTime: 0,
        nibbleHeading: heading,
        scatterHeading: heading,
        paletteIndex: index % TUNING.palettes.length,
      });
    }
    this.phase = "laps";
    this.ripples = [];
    this.time = 0;
    this.swimTime = 0;
    this.finger = { ...pondCenter() };
    this.armTime = 0;
    this.gatherTime = 0;
    this.reduceMotion = reduceMotion;
    this.arrivalOrder = [];
    this.nibbleCount = 0;
    this.seed = seed;
    this.scriptedRelease = null;
    this.scriptedCap = null;
    this.pecked = [];
    this.announcedReturn = false;
  }

  get koiCount() {
    return this.fish.length;
  }

  get holding() {
    return this.phase === "gathering";
  }

  get accessibilityLabel() {
    return `Pond, ${this.koiCount} koi`;
  }

  get accessibilityValue() {
    return this.phase === "gathering" ? TUNING.nibblingValue : TUNING.swimmingValue;
  }

  setReduceMotion(on) {
    const was = this.reduceMotion;
    this.reduceMotion = on;
    if (!(on && !was)) return;
    if (this.phase === "scattering") this.phase = "returning";
    for (const fish of this.fish) {
      if (fish.mode === "scattering") {
        fish.mode = "returning";
        fish.modeTime = 0;
      }
    }
  }

  beginTouch(x, y) {
    if (!Number.isFinite(x) || !Number.isFinite(y)) return [];
    this.finger = clampFinger({ x, y });
    if (this.phase === "arming" || this.phase === "gathering") return [];
    this.phase = "arming";
    this.armTime = 0;
    this.scriptedRelease = null;
    this.scriptedCap = null;
    this.spawnRipple(this.finger, "gather");
    return [];
  }

  updateTouch(x, y) {
    if (this.phase !== "arming" && this.phase !== "gathering") return;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    this.finger = clampFinger({ x, y });
  }

  endTouch() {
    if (this.phase === "arming") {
      this.phase = "laps";
      return [];
    }
    if (this.phase === "gathering") return this.releaseHold();
    return [];
  }

  feed() {
    if (this.phase === "gathering") return [];
    this.finger = clampFinger(pondCenter());
    this.spawnRipple(this.finger, "gather");
    this.commitGather(true);
    return [];
  }

  step(dt) {
    if (!Number.isFinite(dt) || !(dt > 0)) return [];
    let remaining = Math.min(dt, TUNING.maxFrame);
    const events = [];
    while (remaining > 1e-12) {
      const h = Math.min(remaining, TUNING.fixedStep);
      events.push(...this.integrate(h));
      remaining -= h;
    }
    return events;
  }

  integrate(dt) {
    this.time += dt;
    const clockScale = this.reduceMotion ? TUNING.reduceScale : 1;
    this.swimTime += dt * clockScale;
    this.ageRipples(dt);
    if (this.phase === "arming") {
      this.armTime += dt;
      if (this.armTime >= TUNING.longPress) this.commitGather(false);
    }
    const events = [];
    if (this.phase === "gathering") {
      this.gatherTime += dt;
      if (this.scriptedFeedShouldRelease()) events.push(...this.releaseHold());
    }
    if (this.phase === "laps" || this.phase === "arming") {
      for (let i = 0; i < this.fish.length; i += 1) this.lap(i, dt);
    } else if (this.phase === "gathering") {
      events.push(...this.gather(dt));
    } else if (this.phase === "scattering") {
      this.scatter(dt);
      if (this.fish.every((fish) => fish.mode !== "scattering")) this.phase = "returning";
    } else if (this.phase === "returning") {
      this.returnHome(dt);
      if (this.fish.every((fish) => fish.mode === "lap")) {
        this.phase = "laps";
        if (!this.announcedReturn) {
          this.announcedReturn = true;
          events.push({ kind: "returned" });
        }
      }
    }
    return events;
  }

  commitGather(scripted) {
    this.phase = "gathering";
    this.gatherTime = 0;
    this.arrivalOrder = [];
    this.announcedReturn = false;
    if (scripted) {
      const scale = this.reduceMotion ? TUNING.reduceScale : 1;
      this.scriptedRelease = this.time + TUNING.feedDuration / scale;
      this.scriptedCap = this.time + TUNING.feedCap;
    } else {
      this.scriptedRelease = null;
      this.scriptedCap = null;
    }
    this.pecked = this.fish.map(() => false);
    for (const fish of this.fish) {
      if (fish.mode !== "lap") {
        fish.mode = "lap";
        fish.modeTime = 0;
      }
    }
  }

  scriptedFeedShouldRelease() {
    if (this.scriptedRelease == null) return false;
    const capped = this.scriptedCap != null && this.time >= this.scriptedCap;
    if (capped) return true;
    if (this.time < this.scriptedRelease) return false;
    if (!this.reduceMotion) return true;
    return this.pecked.length === this.fish.length && this.pecked.every((done) => done);
  }

  releaseHold() {
    this.scriptedRelease = null;
    this.scriptedCap = null;
    const burst = !this.reduceMotion;
    for (let i = 0; i < this.fish.length; i += 1) {
      this.fish[i].modeTime = 0;
      if (burst) {
        this.fish[i].scatterHeading = this.scatterHeading(i);
        this.fish[i].mode = "scattering";
      } else {
        this.fish[i].mode = "returning";
      }
    }
    this.phase = burst ? "scattering" : "returning";
    this.announcedReturn = false;
    return [{ kind: "released" }];
  }

  scatterHeading(index) {
    const fish = this.fish[index];
    const head = fish.spine[0];
    const dx = head.x - this.finger.x;
    const dy = head.y - this.finger.y;
    let away = atan2(dy, dx);
    if (dx * dx + dy * dy < 1) away = wrap(fish.heading + PI);
    const fan = (index - (this.koiCount - 1) / 2) * TUNING.scatterFan;
    return wrap(away + fan);
  }

  lap(index, dt) {
    const fish = this.fish[index];
    const scale = this.reduceMotion ? TUNING.reduceScale : 1;
    fish.mode = "lap";
    fish.lapAngle = wrap(fish.lapAngle + fish.lapOmega * dt * scale);
    this.drive(index, this.lapAim(index), TUNING.lapSpeed * scale, dt);
  }

  lapAim(index) {
    const fish = this.fish[index];
    const sign = fish.lapOmega >= 0 ? 1 : -1;
    return lapPoint(fish.lapAngle + sign * TUNING.lapLookahead, fish.orbitScale);
  }

  gather(dt) {
    const already = this.fish.map((fish) => fish.mode === "nibbling");
    const events = [];
    for (let i = 0; i < this.fish.length; i += 1) {
      const delay = i * TUNING.stagger;
      if (this.gatherTime + 1e-9 < delay) {
        this.lap(i, dt);
        continue;
      }
      const fish = this.fish[i];
      if (fish.mode === "lap" || fish.mode === "returning" || fish.mode === "scattering") {
        fish.mode = "seeking";
        fish.modeTime = 0;
      }
      const predecessor = i === 0 || already[i - 1];
      const event = this.seek(i, predecessor, dt);
      if (event) events.push(event);
    }
    return events;
  }

  seek(index, predecessor, dt) {
    const fish = this.fish[index];
    if (fish.mode === "nibbling") {
      if (this.nibbleJump(index) <= TUNING.nibbleLeash) return this.nibble(index, dt);
      fish.mode = "seeking";
      fish.modeTime = 0;
    }
    const head = fish.spine[0];
    const dist = distance(head, this.finger);
    if (predecessor && dist <= TUNING.arriveRadius) return this.arrive(index, dt);
    if (!predecessor && dist <= TUNING.holdRadius) {
      fish.mode = "waiting";
      const desired = atan2(this.finger.y - head.y, this.finger.x - head.x);
      fish.heading = turn(fish.heading, desired, TUNING.turnRate, dt);
      fish.modeTime += dt;
      return null;
    }
    fish.mode = "seeking";
    const scale = this.reduceMotion ? TUNING.reduceScale : 1;
    let speed = TUNING.seekSpeed * scale;
    if (dist < TUNING.arriveSlow) speed *= Math.max(0.22, dist / TUNING.arriveSlow);
    this.drive(index, this.finger, speed, dt);
    fish.modeTime += dt;
    return null;
  }

  arrive(index, dt) {
    const fish = this.fish[index];
    const head = fish.spine[0];
    const dx = this.finger.x - head.x;
    const dy = this.finger.y - head.y;
    fish.nibbleHeading = atan2(dy, dx);
    fish.heading = fish.nibbleHeading;
    fish.mode = "nibbling";
    fish.modeTime = 0;
    fish.bobSample = sin(fish.tailPhase);
    if (!this.arrivalOrder.includes(index)) this.arrivalOrder.push(index);
    return this.nibble(index, dt);
  }

  nibbleJump(index) {
    const fish = this.fish[index];
    const scale = this.reduceMotion ? TUNING.reduceScale : 1;
    const phase = TUNING.bobOmega * fish.modeTime * scale + fish.tailPhase;
    const sample = sin(phase);
    const peck = Math.max(0, sample) * TUNING.bobAmplitude;
    const ux = cos(fish.nibbleHeading);
    const uy = sin(fish.nibbleHeading);
    const gap = TUNING.nibbleGap - peck;
    const slot = clampHead({ x: this.finger.x - ux * gap, y: this.finger.y - uy * gap });
    return distance(fish.spine[0], slot);
  }

  nibble(index, dt) {
    const fish = this.fish[index];
    const scale = this.reduceMotion ? TUNING.reduceScale : 1;
    const phase = TUNING.bobOmega * fish.modeTime * scale + fish.tailPhase;
    const sample = sin(phase);
    const peck = Math.max(0, sample) * TUNING.bobAmplitude;
    const ux = cos(fish.nibbleHeading);
    const uy = sin(fish.nibbleHeading);
    const gap = TUNING.nibbleGap - peck;
    fish.heading = fish.nibbleHeading;
    fish.spine[0] = clampHead({
      x: this.finger.x - ux * gap,
      y: this.finger.y - uy * gap,
    });
    constrain(fish.spine, fish.heading);
    let event = null;
    if (fish.bobSample < TUNING.nibbleThreshold && sample >= TUNING.nibbleThreshold) {
      this.nibbleCount += 1;
      if (this.pecked.length === this.fish.length) this.pecked[index] = true;
      this.spawnRipple(fish.spine[0], "nibble");
      event = { kind: "nibble", index };
    }
    fish.bobSample = sample;
    fish.modeTime += dt;
    return event;
  }

  scatter(dt) {
    for (let i = 0; i < this.fish.length; i += 1) {
      const fish = this.fish[i];
      if (fish.mode === "scattering") {
        fish.modeTime += dt;
        if (fish.modeTime >= TUNING.scatterDuration) {
          fish.mode = "returning";
          fish.modeTime = 0;
        } else {
          const head = fish.spine[0];
          this.drive(
            i,
            {
              x: head.x + cos(fish.scatterHeading) * 240,
              y: head.y + sin(fish.scatterHeading) * 240,
            },
            TUNING.scatterSpeed,
            dt,
            TUNING.scatterTurnRate,
          );
        }
      } else if (fish.mode === "returning") {
        this.returnOne(i, dt);
      } else if (fish.mode === "lap") {
        this.lap(i, dt);
      }
    }
  }

  returnHome(dt) {
    for (let i = 0; i < this.fish.length; i += 1) {
      if (this.fish[i].mode === "lap") this.lap(i, dt);
      else this.returnOne(i, dt);
    }
  }

  returnOne(index, dt) {
    const fish = this.fish[index];
    const scale = this.reduceMotion ? TUNING.reduceScale : 1;
    fish.mode = "returning";
    fish.lapAngle = wrap(fish.lapAngle + fish.lapOmega * dt * scale);
    const aim = this.lapAim(index);
    this.drive(index, aim, TUNING.lapSpeed * scale, dt);
    fish.modeTime += dt;
    if (distance(fish.spine[0], aim) <= TUNING.returnCatch || fish.modeTime >= TUNING.returnTimeout) {
      fish.mode = "lap";
      fish.modeTime = 0;
    }
  }

  drive(index, aim, speed, dt, turnRate = TUNING.turnRate) {
    const fish = this.fish[index];
    const head = fish.spine[0];
    const desired = atan2(aim.y - head.y, aim.x - head.x);
    const heading = turn(fish.heading, desired, turnRate, dt);
    fish.heading = heading;
    const step = speed * dt;
    fish.spine[0] = clampHead({
      x: head.x + cos(heading) * step,
      y: head.y + sin(heading) * step,
    });
    constrain(fish.spine, heading);
  }

  ageRipples(dt) {
    for (const ripple of this.ripples) ripple.age += dt;
    this.ripples = this.ripples.filter((ripple) => ripple.age < ripple.lifetime);
  }

  spawnRipple(origin, kind) {
    this.ripples.push({
      origin: { x: origin.x, y: origin.y },
      age: 0,
      lifetime: kind === "gather" ? TUNING.gatherLife : TUNING.nibbleLife,
      maxRadius: kind === "gather" ? TUNING.gatherRadius : TUNING.nibbleRadius,
      kind,
      reduceMotion: this.reduceMotion,
    });
    if (this.ripples.length > TUNING.maxRipples) {
      this.ripples.splice(0, this.ripples.length - TUNING.maxRipples);
    }
  }

  posed(index) {
    return posedSpine(this.fish[index], this.swimTime);
  }
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

function describe(event) {
  if (event.kind === "nibble") return `nibble ${event.index}`;
  if (event.kind === "released") return "released";
  return "returned";
}

function traceLine(tag, index, model) {
  const arrivals = model.arrivalOrder.length ? model.arrivalOrder.join(",") : "-";
  const parts = [
    tag,
    String(index),
    model.phase,
    fmt(model.time),
    fmt(model.swimTime),
    model.holding ? "1" : "0",
    fmt(model.finger.x),
    fmt(model.finger.y),
    String(model.nibbleCount),
    String(model.ripples.length),
    arrivals,
  ];
  for (const fish of model.fish) {
    const posed = posedSpine(fish, model.swimTime);
    const tail = posed[posed.length - 1];
    const head = fish.spine[0];
    parts.push(fmt(head.x), fmt(head.y), fmt(fish.heading), fish.mode, fmt(tail.x), fmt(tail.y));
  }
  if (model.ripples.length) {
    const ripple = model.ripples[0];
    parts.push(ripple.kind, fmt(rippleRadius(ripple)), fmt(rippleOpacity(ripple)));
  } else {
    parts.push("none");
  }
  return parts.join(" ");
}

function session(reduceMotion, tag) {
  const model = new KoiPondModel({ seed: TUNING.defaultSeed, reduceMotion });
  const lines = [];
  let index = 0;
  const snap = () => {
    lines.push(traceLine(tag, index, model));
    index += 1;
  };
  const note = (events) => {
    if (!events.length) return;
    lines.push(`${tag} e ${events.map(describe).join(" ")}`);
  };
  const finger = pondCenter();
  const dt = TUNING.fixedStep;
  snap();
  for (let i = 0; i < 12; i += 1) {
    note(model.step(dt));
    snap();
  }
  note(model.beginTouch(finger.x, finger.y));
  snap();
  for (let i = 0; i < 8; i += 1) {
    note(model.step(dt));
    snap();
  }
  model.updateTouch(finger.x + 24, finger.y - 16);
  snap();
  const gatherFrames = reduceMotion ? 80 : 150;
  for (let i = 0; i < gatherFrames; i += 1) {
    note(model.step(dt));
    snap();
  }
  note(model.endTouch());
  snap();
  const after = reduceMotion ? 40 : 80;
  for (let i = 0; i < after; i += 1) {
    note(model.step(dt));
    snap();
  }
  return lines;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(TUNING.fixedStep)}`,
    `press ${fmt(TUNING.longPress)} stagger ${fmt(TUNING.stagger)}`,
    `segment ${fmt(TUNING.segmentLength)} spine ${TUNING.spineCount}`,
    `tail ${fmt(TUNING.tailOmega)} ${fmt(TUNING.tailAmplitude)} ${fmt(TUNING.tailLag)}`,
    `seek ${fmt(TUNING.seekSpeed)} scatter ${fmt(TUNING.scatterSpeed)} reduce ${fmt(TUNING.reduceScale)}`,
    `gap ${fmt(TUNING.nibbleGap)} bob ${fmt(TUNING.bobOmega)} ${fmt(TUNING.nibbleThreshold)}`,
    `center ${fmt(pondCenter().x)} ${fmt(pondCenter().y)}`,
    `math ${fmt(sin(0))} ${fmt(sin(HALF_PI))} ${fmt(atan(1))} ${fmt(atan2(-1, -1))}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

export const DEMO_DURATION = 7.2;
export const DEMO_STILLS = [
  { name: "Laps", t: 0.9 },
  { name: "Long press", t: 1.55 },
  { name: "Gathering", t: 2.55 },
  { name: "Nibbling", t: 4.15 },
  { name: "Scatter", t: 5.6 },
  { name: "Drifting home", t: 6.55 },
  { name: "Reduce Motion", t: 4.15, reduceMotion: true },
  { name: "Gentle fades", t: 5.35, reduceMotion: true },
];

export function demoAt(t, { reduceMotion = false } = {}) {
  const model = new KoiPondModel({ reduceMotion });
  const pressAt = 1.35;
  const releaseAt = 4.9;
  const finger = { x: 214, y: 468 };
  const dt = TUNING.fixedStep;
  let time = 0;
  let touching = false;
  const end = Math.max(0, t);
  while (time < end - 1e-12) {
    const next = Math.min(time + dt, end);
    if (!touching && time < pressAt && next >= pressAt) {
      if (pressAt - time > 1e-12) model.step(pressAt - time);
      model.beginTouch(finger.x, finger.y);
      touching = true;
      if (next - pressAt > 1e-12) model.step(next - pressAt);
    } else if (touching && time < releaseAt && next >= releaseAt) {
      if (releaseAt - time > 1e-12) model.step(releaseAt - time);
      model.endTouch();
      touching = false;
      if (next - releaseAt > 1e-12) model.step(next - releaseAt);
    } else {
      model.step(next - time);
    }
    time = next;
  }
  return model;
}

export { rippleRadius, rippleOpacity, posedSpine };
