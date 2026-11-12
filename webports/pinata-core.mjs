// JS port of PinataCore. Constants, the polynomial sin/cos/exp, SplitMix64 and the
// substep order match Sources/PinataCore. goldenTrace() matches
// Tests/PinataCoreTests/GoldenTraceTests.swift.

const MASK = (1n << 64n) - 1n;
const PI = Math.PI;
const TWO_PI = 2 * Math.PI;
const HALF_PI = Math.PI / 2;
const INV_TWO_PI = 1 / (2 * Math.PI);
const LN2 = 0.6931471805599453;
const INV_LN2 = 1 / 0.6931471805599453;

export const TUNING = {
  canvasWidth: 320,
  canvasHeight: 480,
  anchorX: 160,
  anchorY: 48,
  restLength: 118,
  bodyRadiusX: 58,
  bodyRadiusY: 70,
  hitSlop: 1.12,
  gravity: 2200,
  torsion: 6.5,
  angularDamping: 1.35,
  radialStiffness: 70,
  radialDamping: 5.8,
  minLength: 86,
  maxLength: 176,
  maxAngle: 1.15,
  baseImpulse: 2.35,
  impulseGrowth: 0.2,
  radialKick: 120,
  candyMin: 6,
  candyMax: 10,
  candySpread: 1.05,
  candySpeedMin: 150,
  candySpeedMax: 360,
  candyLifeMin: 0.72,
  candyLifeMax: 1.05,
  candySizeMin: 5,
  candySizeMax: 9.5,
  candySpin: 8,
  candyGravity: 880,
  candyDrag: 0.45,
  candyColors: 6,
  crackBase: 18,
  crackGrowth: 4.5,
  crackXMin: 0.1,
  crackXMax: 0.55,
  crackYMin: -0.45,
  crackYMax: 0.5,
  confettiCount: 32,
  confettiSpeedMin: 90,
  confettiSpeedMax: 280,
  confettiLifeMin: 1.05,
  confettiLifeMax: 1.45,
  confettiGravity: 620,
  confettiDrag: 0.55,
  confettiSizeMin: 4,
  confettiSizeMax: 8,
  confettiSpin: 11,
  glowDecay: 5.2,
  halfSpeed: 190,
  halfLift: 80,
  halfSpin: 2.4,
  halfGravity: 1040,
  halfSpinDrag: 0.35,
  halfGap: 5,
  halfFade: 1.15,
  burstDuration: 1.35,
  fadeDuration: 0.4,
  tokenStiffness: 170,
  tokenDamping: 0.68,
  tokenDrop: 36,
  substep: 1 / 240,
  maxFrame: 0.1,
  defaultHits: 8,
  minHits: 1,
  maxHits: 24,
  defaultSeed: 0xC0FFEE51A7n,
  keepTapping: "Keep tapping",
  comeBack: "Come back tomorrow",
};

export function hitScale(n) {
  return 1 + TUNING.impulseGrowth * (Math.max(n, 1) - 1);
}

export function impulse(n) {
  return TUNING.baseImpulse * hitScale(n);
}

function hitSeed(seed, hit) {
  return (seed ^ ((BigInt(hit) * 0x9E3779B97F4A7C15n) & MASK)) & MASK;
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

export function exp(x) {
  if (Number.isNaN(x)) return 0;
  const xc = Math.min(Math.max(x, -60), 60);
  const k = Math.floor(xc * INV_LN2 + 0.5);
  const r = xc - k * LN2;
  let p = 1 / 6227020800;
  p = 1 / 479001600 + r * p;
  p = 1 / 39916800 + r * p;
  p = 1 / 3628800 + r * p;
  p = 1 / 362880 + r * p;
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

class SplitMix {
  constructor(seed) { this.state = BigInt(seed); }
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
  int(n) {
    return Number(this.next() % BigInt(n));
  }
}

function springSubstep(value, velocity, target, stiffness, dampingRatio, h) {
  const damping = 2 * dampingRatio * Math.sqrt(stiffness);
  const acceleration = stiffness * (target - value) - damping * velocity;
  velocity += acceleration * h;
  value += velocity * h;
  return [value, velocity];
}

function vec(x, y) { return { x, y }; }

export class PinataPendulum {
  constructor() {
    this.angle = 0;
    this.omega = 0;
    this.length = TUNING.restLength;
    this.radialVelocity = 0;
  }

  get bob() {
    return vec(
      TUNING.anchorX + this.length * sin(this.angle),
      TUNING.anchorY + this.length * cos(this.angle),
    );
  }

  get tangentialVelocity() {
    const s = sin(this.angle);
    const c = cos(this.angle);
    return vec(
      this.radialVelocity * s + this.omega * this.length * c,
      this.radialVelocity * c - this.omega * this.length * s,
    );
  }

  rotate(local) {
    const c = cos(this.angle);
    const s = sin(this.angle);
    return vec(local.x * c + local.y * s, -local.x * s + local.y * c);
  }

  world(local) {
    const spun = this.rotate(local);
    const bob = this.bob;
    return vec(bob.x + spun.x, bob.y + spun.y);
  }

  localPoint(world) {
    const c = cos(this.angle);
    const s = sin(this.angle);
    const bob = this.bob;
    const dx = world.x - bob.x;
    const dy = world.y - bob.y;
    return vec(dx * c - dy * s, dx * s + dy * c);
  }

  contains(world) {
    if (!Number.isFinite(world.x) || !Number.isFinite(world.y)) return false;
    const local = this.localPoint(world);
    const nx = local.x / (TUNING.bodyRadiusX * TUNING.hitSlop);
    const ny = local.y / (TUNING.bodyRadiusY * TUNING.hitSlop);
    return nx * nx + ny * ny <= 1;
  }

  snapToRest() {
    this.angle = 0;
    this.omega = 0;
    this.length = TUNING.restLength;
    this.radialVelocity = 0;
  }

  substep(h) {
    if (!(h > 0) || !Number.isFinite(h)) return;
    const s = sin(this.angle);
    const radialAcc = this.length * this.omega * this.omega
      - TUNING.radialStiffness * (this.length - TUNING.restLength)
      - TUNING.radialDamping * this.radialVelocity;
    const angularAcc = -(TUNING.gravity / this.length) * s
      - TUNING.torsion * this.angle
      - TUNING.angularDamping * this.omega
      - 2 * this.radialVelocity * this.omega / this.length;
    this.radialVelocity += radialAcc * h;
    this.omega += angularAcc * h;
    this.length += this.radialVelocity * h;
    this.angle += this.omega * h;
    if (this.length < TUNING.minLength) {
      this.length = TUNING.minLength;
      this.radialVelocity = 0;
    } else if (this.length > TUNING.maxLength) {
      this.length = TUNING.maxLength;
      this.radialVelocity = 0;
    }
    if (this.angle > TUNING.maxAngle) {
      this.angle = TUNING.maxAngle;
      this.omega = 0;
    } else if (this.angle < -TUNING.maxAngle) {
      this.angle = -TUNING.maxAngle;
      this.omega = 0;
    }
  }
}

function hiddenToken() {
  return { present: false, scale: 0, scaleVelocity: 0, offset: 0, offsetVelocity: 0 };
}

export class PinataModel {
  constructor({ hitsToBreak = TUNING.defaultHits, seed = TUNING.defaultSeed, reduceMotion = false } = {}) {
    this.hitsToBreak = Math.min(Math.max(hitsToBreak, TUNING.minHits), TUNING.maxHits);
    this.seed = BigInt(seed);
    this.reduceMotion = reduceMotion;
    this.phase = "intact";
    this.hits = 0;
    this.pendulum = new PinataPendulum();
    this.glow = 0;
    this.particles = [];
    this.cracks = [];
    this.halves = [];
    this.token = hiddenToken();
    this.burstAge = 0;
  }

  get angle() { return this.pendulum.angle; }
  get omega() { return this.pendulum.omega; }
  get length() { return this.pendulum.length; }
  get radialVelocity() { return this.pendulum.radialVelocity; }
  get bodyCenter() { return this.pendulum.bob; }
  get pillText() { return this.phase === "intact" ? TUNING.keepTapping : TUNING.comeBack; }
  get accessibilityValue() {
    return this.phase === "intact" ? `${this.hits} of ${this.hitsToBreak}` : TUNING.comeBack;
  }
  get progress() { return this.hits / Math.max(this.hitsToBreak, 1); }
  get reveal() {
    if (this.phase === "intact") return 0;
    if (!this.reduceMotion) return this.phase === "spent" ? 1 : Math.min(1, this.burstAge / TUNING.burstDuration);
    return Math.min(1, this.burstAge / TUNING.fadeDuration);
  }
  get tokenPosition() {
    return vec(TUNING.anchorX, TUNING.anchorY + TUNING.restLength + this.token.offset);
  }

  hit(point) {
    if (this.phase !== "intact") return [];
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y) || !this.pendulum.contains(point)) return [];
    const local = this.pendulum.localPoint(point);
    const side = local.x < 0 ? "left" : "right";
    return this.apply(side, local);
  }

  strike(side) {
    const x = (side === "left" ? -1 : 1) * TUNING.bodyRadiusX * 0.4;
    return this.hit(this.pendulum.world(vec(x, 0)));
  }

  hitForAccessibility() {
    return this.strike(this.hits % 2 === 0 ? "left" : "right");
  }

  step(dt) {
    if (!(dt > 0) || !Number.isFinite(dt)) return [];
    let remaining = Math.min(dt, TUNING.maxFrame);
    while (remaining > 1e-12) {
      const h = Math.min(remaining, TUNING.substep);
      this.substep(h);
      remaining -= h;
    }
    if (this.phase === "bursting") {
      const limit = this.reduceMotion ? TUNING.fadeDuration : TUNING.burstDuration;
      if (this.burstAge >= limit - 1e-9) {
        this.phase = "spent";
        return ["settled"];
      }
    }
    return [];
  }

  apply(side, impact) {
    const index = this.hits + 1;
    const scale = hitScale(index);
    if (!this.reduceMotion) {
      const sign = side === "left" ? 1 : -1;
      this.pendulum.omega += sign * impulse(index);
      this.pendulum.radialVelocity += TUNING.radialKick * scale;
    }
    this.glow = 1;
    this.hits = index;
    const rng = new SplitMix(hitSeed(this.seed, index));
    if (!this.reduceMotion) this.spawnCandy(side, impact, scale, rng);
    this.cracks.push(this.makeCrack(side, index, rng));
    const events = [`hit ${index} ${side}`];
    if (this.hits >= this.hitsToBreak) {
      this.beginBurst(scale, rng);
      events.push("burst");
    }
    return events;
  }

  beginBurst(scale, rng) {
    this.phase = "bursting";
    this.burstAge = 0;
    this.token.present = true;
    this.token.scale = 0;
    this.token.scaleVelocity = 0;
    if (this.reduceMotion) {
      this.token.offset = 0;
      this.token.offsetVelocity = 0;
      this.halves = [];
      return;
    }
    this.token.offset = TUNING.tokenDrop;
    this.token.offsetVelocity = 0;
    const bob = this.pendulum.bob;
    const carry = this.pendulum.tangentialVelocity;
    const outward = this.pendulum.rotate(vec(1, 0));
    const up = this.pendulum.rotate(vec(0, -1));
    this.halves = [
      this.makeHalf("left", -1, bob, carry, outward, up, scale),
      this.makeHalf("right", 1, bob, carry, outward, up, scale),
    ];
    this.spawnConfetti(scale, rng);
  }

  makeHalf(side, sign, bob, carry, outward, up, scale) {
    return {
      side,
      position: vec(bob.x + outward.x * sign * TUNING.halfGap, bob.y + outward.y * sign * TUNING.halfGap),
      velocity: vec(
        carry.x + outward.x * sign * TUNING.halfSpeed * scale + up.x * TUNING.halfLift * scale,
        carry.y + outward.y * sign * TUNING.halfSpeed * scale + up.y * TUNING.halfLift * scale,
      ),
      angle: this.pendulum.angle,
      angularVelocity: sign * TUNING.halfSpin * scale,
      age: 0,
    };
  }

  spawnCandy(side, impact, scale, rng) {
    const span = TUNING.candyMax - TUNING.candyMin + 1;
    const count = TUNING.candyMin + rng.int(span);
    const origin = this.pendulum.world(impact);
    const carry = this.pendulum.tangentialVelocity;
    const base = side === "left" ? PI : 0;
    for (let i = 0; i < count; i += 1) {
      const heading = base + rng.uniform(-TUNING.candySpread, TUNING.candySpread);
      const speed = rng.uniform(TUNING.candySpeedMin, TUNING.candySpeedMax) * scale;
      const life = rng.uniform(TUNING.candyLifeMin, TUNING.candyLifeMax);
      const size = rng.uniform(TUNING.candySizeMin, TUNING.candySizeMax);
      const spin = rng.uniform(-TUNING.candySpin, TUNING.candySpin);
      const color = rng.int(TUNING.candyColors);
      const shape = rng.int(3);
      const local = vec(cos(heading) * speed, sin(heading) * speed);
      const spun = this.pendulum.rotate(local);
      this.particles.push({
        kind: "candy",
        position: vec(origin.x, origin.y),
        velocity: vec(spun.x + carry.x, spun.y + carry.y),
        rotation: 0,
        spin,
        age: 0,
        life,
        size,
        colorIndex: color,
        shape,
      });
    }
  }

  spawnConfetti(scale, rng) {
    const origin = this.pendulum.bob;
    const count = TUNING.confettiCount;
    for (let i = 0; i < count; i += 1) {
      const ring = (i + 0.5) / count * TWO_PI;
      const heading = ring + rng.uniform(-0.15, 0.15);
      const speed = rng.uniform(TUNING.confettiSpeedMin, TUNING.confettiSpeedMax) * scale;
      const life = rng.uniform(TUNING.confettiLifeMin, TUNING.confettiLifeMax);
      const size = rng.uniform(TUNING.confettiSizeMin, TUNING.confettiSizeMax);
      const spin = rng.uniform(-TUNING.confettiSpin, TUNING.confettiSpin);
      const color = rng.int(TUNING.candyColors);
      const shape = rng.int(3);
      this.particles.push({
        kind: "confetti",
        position: vec(origin.x, origin.y),
        velocity: vec(cos(heading) * speed, sin(heading) * speed),
        rotation: heading,
        spin,
        age: 0,
        life,
        size,
        colorIndex: color,
        shape,
      });
    }
  }

  makeCrack(side, hit, rng) {
    const sign = side === "left" ? -1 : 1;
    const x0 = sign * rng.uniform(TUNING.crackXMin, TUNING.crackXMax) * TUNING.bodyRadiusX;
    const y0 = rng.uniform(TUNING.crackYMin, TUNING.crackYMax) * TUNING.bodyRadiusY;
    const heading = (side === "left" ? PI : 0) + rng.uniform(-0.85, 0.85);
    const jag = rng.uniform(-10, 10);
    const span = TUNING.crackBase + TUNING.crackGrowth * (hit - 1);
    const dir = vec(cos(heading), sin(heading));
    const nrm = vec(-dir.y, dir.x);
    const p0 = vec(x0, y0);
    const p1 = vec(p0.x + dir.x * span * 0.5 + nrm.x * jag, p0.y + dir.y * span * 0.5 + nrm.y * jag);
    const p2 = vec(p0.x + dir.x * span, p0.y + dir.y * span);
    return { points: [p0, p1, p2], span };
  }

  substep(h) {
    if (this.reduceMotion) {
      this.pendulum.snapToRest();
      this.particles = [];
      this.decayGlow(h);
      if (this.phase === "intact") return;
      this.burstAge += h;
      this.token.present = true;
      this.token.offset = 0;
      this.token.offsetVelocity = 0;
      this.token.scaleVelocity = 0;
      this.token.scale = Math.min(1, this.burstAge / TUNING.fadeDuration);
      return;
    }
    if (this.phase === "intact") this.pendulum.substep(h);
    this.decayGlow(h);
    this.integrateParticles(h);
    if (this.phase === "intact") return;
    this.integrateHalves(h);
    this.integrateToken(h);
    this.burstAge += h;
  }

  decayGlow(h) {
    if (!(this.glow > 0)) return;
    this.glow *= exp(-TUNING.glowDecay * h);
    if (this.glow < 1e-4) this.glow = 0;
  }

  integrateParticles(h) {
    const kept = [];
    for (const src of this.particles) {
      const p = {
        ...src,
        position: vec(src.position.x, src.position.y),
        velocity: vec(src.velocity.x, src.velocity.y),
      };
      p.age += h;
      if (p.age >= p.life) continue;
      const drag = p.kind === "candy" ? TUNING.candyDrag : TUNING.confettiDrag;
      const gravity = p.kind === "candy" ? TUNING.candyGravity : TUNING.confettiGravity;
      const d = exp(-drag * h);
      p.velocity.y += gravity * h;
      p.velocity.x *= d;
      p.velocity.y *= d;
      p.position.x += p.velocity.x * h;
      p.position.y += p.velocity.y * h;
      p.rotation += p.spin * h;
      kept.push(p);
    }
    this.particles = kept;
  }

  integrateHalves(h) {
    for (const half of this.halves) {
      half.velocity.y += TUNING.halfGravity * h;
      half.position.x += half.velocity.x * h;
      half.position.y += half.velocity.y * h;
      half.angularVelocity *= exp(-TUNING.halfSpinDrag * h);
      half.angle += half.angularVelocity * h;
      half.age += h;
    }
  }

  integrateToken(h) {
    if (!this.token.present) return;
    const scale = springSubstep(this.token.scale, this.token.scaleVelocity, 1, TUNING.tokenStiffness, TUNING.tokenDamping, h);
    const offset = springSubstep(this.token.offset, this.token.offsetVelocity, 0, TUNING.tokenStiffness, TUNING.tokenDamping, h);
    this.token.scale = scale[0];
    this.token.scaleVelocity = scale[1];
    this.token.offset = offset[0];
    this.token.offsetVelocity = offset[1];
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

function traceLine(tag, index, model) {
  let sumX = 0;
  let sumY = 0;
  for (const p of model.particles) {
    sumX += p.position.x;
    sumY += p.position.y;
  }
  const h0 = model.halves[0];
  const h1 = model.halves[1];
  const pill = model.phase === "intact" ? "keep" : "tomorrow";
  return [
    tag, String(index), model.phase, String(model.hits),
    fmt(model.angle), fmt(model.omega), fmt(model.length), fmt(model.radialVelocity), fmt(model.glow),
    String(model.particles.length), String(model.cracks.length), fmt(sumX), fmt(sumY),
    fmt(h0 ? h0.position.x : 0), fmt(h0 ? h0.position.y : 0), fmt(h0 ? h0.angle : 0),
    fmt(h1 ? h1.position.x : 0), fmt(h1 ? h1.position.y : 0), fmt(h1 ? h1.angle : 0),
    fmt(model.token.scale), fmt(model.token.offset), pill,
  ].join(" ");
}

function session(reduceMotion, tag) {
  const model = new PinataModel({ hitsToBreak: 8, seed: TUNING.defaultSeed, reduceMotion });
  const lines = [];
  let index = 0;
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
  const rest = reduceMotion ? 4 : 12;
  for (let i = 0; i < rest; i += 1) {
    note(model.step(dt));
    snap();
  }
  const between = reduceMotion ? 2 : 18;
  for (let hit = 0; hit < 8; hit += 1) {
    note(model.strike(hit % 2 === 0 ? "left" : "right"));
    snap();
    if (hit < 7) {
      for (let i = 0; i < between; i += 1) {
        note(model.step(dt));
        snap();
      }
    }
  }
  const tail = reduceMotion ? 30 : 96;
  for (let i = 0; i < tail; i += 1) {
    note(model.step(dt));
    snap();
  }
  return lines;
}

/** The same text Tests/PinataCoreTests writes into Fixtures/golden-trace.txt. */
export function goldenTrace() {
  const lines = ["v1", `dt ${fmt(1 / 60)}`];
  for (let n = 1; n <= 8; n += 1) lines.push(`imp ${n} ${fmt(impulse(n))}`);
  lines.push(`math ${[fmt(sin(0)), fmt(sin(HALF_PI)), fmt(sin(PI)), fmt(cos(0)), fmt(exp(0)), fmt(exp(1)), fmt(sin(0.3))].join(" ")}`);
  const rng = new SplitMix(TUNING.defaultSeed);
  const mixed = rng.next();
  const unit = rng.uniform(-0.5, 0.5);
  lines.push(`seed ${mixed.toString()} ${fmt(unit)}`);
  lines.push(`copy ${TUNING.keepTapping} | ${TUNING.comeBack}`);
  lines.push(...session(false, "f"));
  lines.push(...session(true, "r"));
  return `${lines.join("\n")}\n`;
}

export const DEMO_HITS = [0.45, 0.95, 1.4, 1.82, 2.2, 2.55, 2.88, 3.18];

/** Model state `t` seconds into the scripted preview. */
export function demoAt(t, { reduceMotion = false, step = 1 / 120 } = {}) {
  const model = new PinataModel({ reduceMotion });
  let next = 0;
  let elapsed = 0;
  const duration = Math.max(0, t);
  while (elapsed < duration - 1e-12) {
    const h = Math.min(step, duration - elapsed);
    const t1 = elapsed + h;
    while (next < DEMO_HITS.length && DEMO_HITS[next] <= t1 + 1e-9) {
      model.strike(next % 2 === 0 ? "left" : "right");
      next += 1;
    }
    model.step(h);
    elapsed = t1;
  }
  return model;
}

export const DEMO_STILLS = [
  { name: "Hanging", t: 0.2 },
  { name: "First swing", t: 0.7 },
  { name: "Cracking", t: 2.05 },
  { name: "Harder hits", t: 2.72 },
  { name: "The split", t: 3.34 },
  { name: "Token", t: 4.05 },
  { name: "Come back tomorrow", t: 4.85 },
  { name: "Reduce Motion", t: 3.38, reduceMotion: true },
];

export const DEMO_DURATION = 5.05;
