// Port of GooMergeCore. Constants match GooMergeTuning.swift.
// The golden trace matches Tests/GooMergeCoreTests/Fixtures/golden-trace.txt.

const MASK = (1n << 64n) - 1n;

export const TUNING = {
  pageWidth: 390,
  pageHeight: 844,
  wellX: 195,
  wellY: 400,
  ringRadius: 112,
  wellDashRadius: 36,
  minRadius: 26,
  maxRadius: 44,
  minDrops: 4,
  maxDrops: 5,
  stiffness: 32,
  dampingRatio: 1.05,
  maxFrame: 0.1,
  substep: 1 / 240,
  stretchReach: 40,
  snapGap: 8,
  stretchShift: 16,
  attractSpeed: 12,
  arrival: 2,
  morphDuration: 0.72,
  reducedFade: 0.28,
  bobAmplitude: 3,
  bobOmega: 1.7,
  smoothK: 32,
  fieldEpsilon: 4,
  connectSDF: 0,
  gooBlur: 14,
  gooThreshold: 0.52,
  hitSlop: 10,
  cardWidth: 168,
  cardHeight: 216,
  cardRadius: 16,
  foldSize: 32,
  buttonCenterX: 195,
  buttonCenterY: 712,
  buttonWidth: 168,
  buttonHeight: 48,
  documentName: "Binder-01.pdf",
  readyValue: "Ready to combine",
  mergingValue: "Merging",
  mergedValue: "Merged into Binder-01.pdf",
  combineAction: "Combine",
};

export const SAMPLES = [
  { id: "brief", name: "brief.md", value: 0.62 },
  { id: "shot", name: "shot.png", value: 1.0 },
  { id: "notes", name: "notes.txt", value: 0.48 },
  { id: "reel", name: "reel.mov", value: 0.84 },
  { id: "deck", name: "deck.key", value: 0.7 },
];

export const DEMO_DURATION = 6.0;

export const DEMO_STILLS = [
  { name: "Idle ring", t: 0.35 },
  { name: "Stretch", t: 1.55 },
  { name: "Snap", t: 2.32 },
  { name: "Combining", t: 3.15 },
  { name: "One blob", t: 3.95 },
  { name: "Binder-01.pdf", t: 5.15 },
  { name: "Reduce Motion", t: 1.3, reduceMotion: true },
];

function length(v) {
  return Math.sqrt(v.x * v.x + v.y * v.y);
}

function add(a, b) {
  return { x: a.x + b.x, y: a.y + b.y };
}

function sub(a, b) {
  return { x: a.x - b.x, y: a.y - b.y };
}

function mul(v, s) {
  return { x: v.x * s, y: v.y * s };
}

function norm(v) {
  const l = length(v);
  return l > 0 ? mul(v, 1 / l) : { x: 0, y: 0 };
}

function dist(a, b) {
  return length(sub(a, b));
}

export function radiusFor(value) {
  const t = Math.min(1, Math.max(0, Number.isFinite(value) ? value : 0));
  return TUNING.minRadius + (TUNING.maxRadius - TUNING.minRadius) * t;
}

export function ringPoint(index, count) {
  const n = Math.max(count, 1);
  const angle = -Math.PI / 2 + index * ((2 * Math.PI) / n);
  return {
    x: TUNING.wellX + Math.cos(angle) * TUNING.ringRadius,
    y: TUNING.wellY + Math.sin(angle) * TUNING.ringRadius,
  };
}

export function smoothMin(a, b, k) {
  if (!(k > 0)) return Math.min(a, b);
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
}

export function sdfAt(point, circles) {
  if (circles.length === 0) return Number.POSITIVE_INFINITY;
  let s = dist(point, circles[0].center) - circles[0].radius;
  for (let i = 1; i < circles.length; i += 1) {
    const d = dist(point, circles[i].center) - circles[i].radius;
    s = smoothMin(s, d, TUNING.smoothK);
  }
  return s;
}

export function metaballAt(point, circles) {
  let sum = 0;
  for (const circle of circles) {
    const dx = point.x - circle.center.x;
    const dy = point.y - circle.center.y;
    sum += (circle.radius * circle.radius) / (dx * dx + dy * dy + TUNING.fieldEpsilon);
  }
  return sum;
}

function mergeProgress(logical, restInside, stackedInside, restMeta, stackedMeta) {
  const inside = -sdfAt(well(), logical);
  const meta = metaballAt(well(), logical);
  const spanInside = stackedInside - restInside;
  const spanMeta = stackedMeta - restMeta;
  const a = spanInside === 0 ? 0 : (inside - restInside) / spanInside;
  const b = spanMeta === 0 ? 0 : (meta - restMeta) / spanMeta;
  return Math.min(1, Math.max(0, Math.min(a, b)));
}

export function easeInOut(t) {
  const x = Math.min(1, Math.max(0, t));
  if (x < 0.5) return 4 * x * x * x;
  const u = -2 * x + 2;
  return 1 - (u * u * u) / 2;
}

function smoothstep(edge0, edge1, x) {
  const span = edge1 - edge0;
  const t = span === 0 ? (x < edge0 ? 0 : 1) : Math.min(1, Math.max(0, (x - edge0) / span));
  return t * t * (3 - 2 * t);
}

function well() {
  return { x: TUNING.wellX, y: TUNING.wellY };
}

function SplitMix(seed) {
  this.state = BigInt(seed) & MASK;
}

SplitMix.prototype.next = function next() {
  this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
  let z = this.state;
  z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
  z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
  return (z ^ (z >> 31n)) & MASK;
};

SplitMix.prototype.uniform01 = function uniform01() {
  return Number(this.next() >> 11n) / Number(1n << 53n);
};

function makeSpring(value) {
  return { value, velocity: 0 };
}

function step1(spring, target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, 0.1);
  const damping = 2 * TUNING.dampingRatio * Math.sqrt(TUNING.stiffness);
  while (remaining > 1e-12) {
    const h = Math.min(remaining, 1 / 240);
    const acceleration = TUNING.stiffness * (target - spring.value) - damping * spring.velocity;
    spring.velocity += acceleration * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
}

function snap1(spring, value) {
  spring.value = value;
  spring.velocity = 0;
}

function resolved(drops) {
  if (drops.length > TUNING.maxDrops) return drops.slice(0, TUNING.maxDrops);
  if (drops.length < TUNING.minDrops) return SAMPLES.map((drop) => ({ ...drop }));
  return drops.map((drop) => ({ ...drop }));
}

export class GooMergeModel {
  constructor(drops = SAMPLES, seed = 1, reduceMotion = false) {
    this.drops = resolved(drops);
    this.seed = seed;
    this.reduceMotion = reduceMotion;
    this.phase = "ready";
    this.time = 0;
    this.morphElapsed = 0;
    this.dragIndex = null;
    const count = this.drops.length;
    this.radii = this.drops.map((drop) => radiusFor(drop.value));
    this.homes = Array.from({ length: count }, (_, index) => ringPoint(index, count));
    this.anchors = this.homes.map((home) => ({ ...home }));
    this.springs = this.homes.map((home) => ({ x: makeSpring(home.x), y: makeSpring(home.y) }));
    this.parent = Array.from({ length: count }, (_, index) => index);
    const rng = new SplitMix(seed);
    this.omegas = Array.from({ length: count }, () => TUNING.bobOmega * (0.75 + 0.5 * rng.uniform01()));
    this.stretchAmount = Array(count).fill(0);
    this.stretchDir = Array.from({ length: count }, () => ({ x: 0, y: 0 }));
    const homeCircles = this.homes.map((center, index) => ({ center, radius: this.radii[index] }));
    const stacked = this.radii.map((radius) => ({ center: well(), radius }));
    this.restInside = -sdfAt(well(), homeCircles);
    this.stackedInside = -sdfAt(well(), stacked);
    this.restMeta = metaballAt(well(), homeCircles);
    this.stackedMeta = metaballAt(well(), stacked);
  }

  get count() {
    return this.drops.length;
  }

  get documentName() {
    return TUNING.documentName;
  }

  get morphProgress() {
    if (this.phase === "ready" || this.phase === "combining") return 0;
    if (this.phase === "merged") return 1;
    const duration = this.reduceMotion ? TUNING.reducedFade : TUNING.morphDuration;
    const t = duration > 0 ? Math.min(1, Math.max(0, this.morphElapsed / duration)) : 1;
    return easeInOut(t);
  }

  get mergeProgress() {
    if (this.phase === "morphing" || this.phase === "merged") return 1;
    return mergeProgress(this.logicalCircles(), this.restInside, this.stackedInside, this.restMeta, this.stackedMeta);
  }

  get blobOpacity() {
    if (this.phase === "ready" || this.phase === "combining") return 1;
    if (this.phase === "morphing") return 1 - this.morphProgress;
    return 0;
  }

  get cardOpacity() {
    if (this.phase === "ready" || this.phase === "combining") return 0;
    if (this.phase === "morphing") return this.morphProgress;
    return 1;
  }

  get fold() {
    if (this.reduceMotion) return this.phase === "morphing" || this.phase === "merged" ? 1 : 0;
    return smoothstep(0.4, 1, this.morphProgress);
  }

  get cardScale() {
    if (this.reduceMotion) return 1;
    return 0.86 + 0.14 * this.morphProgress;
  }

  get accessibilityValue() {
    if (this.phase === "ready") return TUNING.readyValue;
    if (this.phase === "merged") return TUNING.mergedValue;
    return TUNING.mergingValue;
  }

  center(index) {
    return { x: this.springs[index].x.value, y: this.springs[index].y.value };
  }

  find(index) {
    let cursor = index;
    while (this.parent[cursor] !== cursor) cursor = this.parent[cursor];
    return cursor;
  }

  bob(index) {
    if (this.phase !== "ready" || this.reduceMotion) return { x: 0, y: 0 };
    if (this.dragIndex != null && this.find(index) === this.find(this.dragIndex)) return { x: 0, y: 0 };
    const amp = TUNING.bobAmplitude * Math.sin(this.time * this.omegas[index]);
    return mul(norm(sub(this.homes[index], well())), amp);
  }

  renderCenter(index) {
    const shift = mul(this.stretchDir[index], this.stretchAmount[index] * TUNING.stretchShift);
    return add(add(this.center(index), shift), this.bob(index));
  }

  logicalCircles() {
    return this.drops.map((_, index) => ({ center: this.center(index), radius: this.radii[index] }));
  }

  renderCircles() {
    return this.drops.map((_, index) => ({ center: this.renderCenter(index), radius: this.radii[index] }));
  }

  sdf(point) {
    return sdfAt(point, this.renderCircles());
  }

  metaball(point) {
    return metaballAt(point, this.renderCircles());
  }

  get connectedPairCount() {
    const circles = this.renderCircles();
    let n = 0;
    for (let i = 0; i < this.count; i += 1) {
      for (let j = i + 1; j < this.count; j += 1) {
        const mid = mul(add(this.renderCenter(i), this.renderCenter(j)), 0.5);
        if (sdfAt(mid, circles) <= TUNING.connectSDF) n += 1;
      }
    }
    return n;
  }

  surfaceGap(i, j) {
    return dist(this.center(i), this.center(j)) - this.radii[i] - this.radii[j];
  }

  snapTo(index, point) {
    snap1(this.springs[index].x, point.x);
    snap1(this.springs[index].y, point.y);
  }

  clearStretch() {
    for (let i = 0; i < this.count; i += 1) {
      this.stretchAmount[i] = 0;
      this.stretchDir[i] = { x: 0, y: 0 };
    }
  }

  refreshStretch() {
    this.clearStretch();
    if (this.phase !== "ready" || this.reduceMotion) return;
    const span = TUNING.stretchReach - TUNING.snapGap;
    for (let i = 0; i < this.count; i += 1) {
      let bestGap = Number.POSITIVE_INFINITY;
      let bestJ = -1;
      for (let j = 0; j < this.count; j += 1) {
        if (this.find(j) === this.find(i)) continue;
        const gap = this.surfaceGap(i, j);
        if (gap < bestGap) {
          bestGap = gap;
          bestJ = j;
        }
      }
      if (bestJ < 0 || !(bestGap < TUNING.stretchReach)) continue;
      const amount = bestGap <= TUNING.snapGap || !(span > 0)
        ? 1
        : (TUNING.stretchReach - bestGap) / span;
      this.stretchAmount[i] = amount;
      this.stretchDir[i] = norm(sub(this.center(bestJ), this.center(i)));
    }
  }

  resolveSnaps() {
    if (this.dragIndex == null || this.reduceMotion || this.phase !== "ready") return [];
    const events = [];
    let passes = 0;
    while (passes < this.count) {
      passes += 1;
      const lead = this.find(this.dragIndex);
      let didSnap = false;
      for (let i = 0; i < this.count && !didSnap; i += 1) {
        if (this.find(i) !== lead) continue;
        for (let j = 0; j < this.count; j += 1) {
          if (this.find(j) === lead) continue;
          if (this.surfaceGap(i, j) <= TUNING.snapGap) {
            const delta = sub(this.center(j), this.center(i));
            for (let k = 0; k < this.count; k += 1) {
              if (this.find(k) === lead) this.snapTo(k, add(this.center(k), delta));
            }
            this.parent[lead] = this.find(j);
            events.push({ kind: "snapped", a: Math.min(i, j), b: Math.max(i, j) });
            events.push({ kind: "haptic" });
            didSnap = true;
            break;
          }
        }
      }
      if (!didSnap) break;
    }
    return events;
  }

  attract(h) {
    if (this.dragIndex == null || this.reduceMotion || !(h > 0)) return;
    const lead = this.find(this.dragIndex);
    for (let j = 0; j < this.count; j += 1) {
      if (this.find(j) === lead) continue;
      let bestGap = Number.POSITIVE_INFINITY;
      let bestI = this.dragIndex;
      for (let i = 0; i < this.count; i += 1) {
        if (this.find(i) !== lead) continue;
        const gap = this.surfaceGap(i, j);
        if (gap < bestGap) {
          bestGap = gap;
          bestI = i;
        }
      }
      if (!(bestGap < TUNING.stretchReach) || !(bestGap > TUNING.snapGap)) continue;
      const span = TUNING.stretchReach - TUNING.snapGap;
      const amount = span > 0 ? (TUNING.stretchReach - bestGap) / span : 1;
      const dir = norm(sub(this.center(bestI), this.center(j)));
      this.snapTo(j, add(this.center(j), mul(dir, TUNING.attractSpeed * amount * h)));
    }
  }

  springTowardWell(index, h) {
    const before = this.center(index);
    const beforeD = dist(before, well());
    step1(this.springs[index].x, TUNING.wellX, h);
    step1(this.springs[index].y, TUNING.wellY, h);
    const after = this.center(index);
    const afterD = dist(after, well());
    if (afterD > beforeD && afterD > 0) {
      const pulled = add(well(), mul(sub(after, well()), beforeD / afterD));
      this.springs[index].x.value = pulled.x;
      this.springs[index].y.value = pulled.y;
      this.springs[index].x.velocity = 0;
      this.springs[index].y.velocity = 0;
    }
  }

  integrate(h) {
    this.time += h;
    if (this.phase === "ready") {
      this.attract(h);
      const events = this.resolveSnaps();
      const held = this.dragIndex == null ? null : this.find(this.dragIndex);
      for (let i = 0; i < this.count; i += 1) {
        if (held != null && this.find(i) === held) continue;
        step1(this.springs[i].x, this.anchors[i].x, h);
        step1(this.springs[i].y, this.anchors[i].y, h);
      }
      this.refreshStretch();
      return events;
    }
    if (this.phase === "combining") {
      for (let i = 0; i < this.count; i += 1) this.springTowardWell(i, h);
      const arrived = this.springs.every((_, index) => dist(this.center(index), well()) <= TUNING.arrival);
      if (arrived) {
        this.phase = "morphing";
        this.morphElapsed = 0;
        this.clearStretch();
        return [{ kind: "morphing" }, { kind: "haptic" }];
      }
      return [];
    }
    if (this.phase === "morphing") {
      this.morphElapsed += h;
      const duration = this.reduceMotion ? TUNING.reducedFade : TUNING.morphDuration;
      if (this.morphElapsed + 1e-9 >= duration) {
        this.morphElapsed = duration;
        this.phase = "merged";
        return [{ kind: "merged", name: TUNING.documentName }, { kind: "haptic" }];
      }
      return [];
    }
    return [];
  }

  step(dt) {
    if (!(dt > 0) || !Number.isFinite(dt)) return [];
    let remaining = Math.min(dt, TUNING.maxFrame);
    const events = [];
    while (remaining > 1e-12) {
      const h = Math.min(remaining, TUNING.substep);
      events.push(...this.integrate(h));
      remaining -= h;
    }
    return events;
  }

  clampPoint(point, radius) {
    return {
      x: Math.min(Math.max(point.x, radius), TUNING.pageWidth - radius),
      y: Math.min(Math.max(point.y, radius), TUNING.pageHeight - radius),
    };
  }

  beginDragIndex(index) {
    if (this.phase !== "ready" || index < 0 || index >= this.count) return false;
    this.dragIndex = index;
    this.refreshStretch();
    return true;
  }

  updateDrag(point) {
    if (this.dragIndex == null || this.phase !== "ready") return [];
    const lead = this.find(this.dragIndex);
    const desired = this.clampPoint(point, this.radii[this.dragIndex]);
    const delta = sub(desired, this.center(this.dragIndex));
    for (let i = 0; i < this.count; i += 1) {
      if (this.find(i) === lead) this.snapTo(i, add(this.center(i), delta));
    }
    const events = this.resolveSnaps();
    this.refreshStretch();
    return events;
  }

  endDrag() {
    if (this.dragIndex == null) return [];
    const index = this.dragIndex;
    this.dragIndex = null;
    const lead = this.find(index);
    const members = [];
    for (let i = 0; i < this.count; i += 1) if (this.find(i) === lead) members.push(i);
    if (members.length > 1) {
      for (const i of members) this.anchors[i] = this.center(i);
    } else if (this.reduceMotion) {
      this.snapTo(index, this.homes[index]);
      this.anchors[index] = { ...this.homes[index] };
    } else {
      this.anchors[index] = { ...this.homes[index] };
    }
    this.refreshStretch();
    return [];
  }

  combine() {
    if (this.phase !== "ready") return [];
    this.dragIndex = null;
    this.clearStretch();
    if (this.reduceMotion) {
      for (let i = 0; i < this.count; i += 1) this.snapTo(i, well());
      this.phase = "morphing";
      this.morphElapsed = 0;
      return [{ kind: "combining" }, { kind: "morphing" }, { kind: "haptic" }];
    }
    this.phase = "combining";
    return [{ kind: "combining" }];
  }

  reset() {
    const next = new GooMergeModel(this.drops, this.seed, this.reduceMotion);
    Object.assign(this, next);
    this.drops = next.drops;
    this.homes = next.homes;
    this.anchors = next.anchors;
    this.springs = next.springs;
    this.parent = next.parent;
    this.omegas = next.omegas;
    this.radii = next.radii;
    this.stretchAmount = next.stretchAmount;
    this.stretchDir = next.stretchDir;
  }
}

function fmt(x) {
  if (!Number.isFinite(x)) return "nan";
  const negative = x < 0;
  const rounded = Math.floor(Math.abs(x) * 100000000 + 0.5);
  const whole = Math.floor(rounded / 100000000);
  let frac = Math.round(rounded - whole * 100000000);
  let wholeOut = whole;
  if (frac >= 100000000) {
    frac -= 100000000;
    wholeOut += 1;
  }
  return `${negative ? "-" : ""}${wholeOut}.${String(frac).padStart(8, "0")}`;
}

function describe(event) {
  if (event.kind === "combining") return "combining";
  if (event.kind === "snapped") return `snapped ${event.a} ${event.b}`;
  if (event.kind === "haptic") return "haptic";
  if (event.kind === "morphing") return "morphing";
  if (event.kind === "merged") return `merged ${event.name}`;
  return event.kind;
}

function traceLine(tag, index, model) {
  const parts = [
    tag,
    String(index),
    model.phase,
    fmt(model.time),
    fmt(model.mergeProgress),
    fmt(model.morphProgress),
    fmt(model.sdf(well())),
    fmt(model.metaball(well())),
    String(model.connectedPairCount),
  ];
  for (let i = 0; i < model.count; i += 1) {
    const center = model.center(i);
    const render = model.renderCenter(i);
    const stretch = model.reduceMotion ? 0 : model.stretchAmount[i];
    parts.push(fmt(center.x), fmt(center.y), fmt(render.x), fmt(render.y), fmt(stretch));
  }
  return parts.join(" ");
}

function session(reduceMotion, tag) {
  const dt = 1 / 60;
  let model = new GooMergeModel(SAMPLES, 11, reduceMotion);
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
  const frames = (count) => {
    for (let n = 0; n < count; n += 1) {
      note(model.step(dt));
      snap();
    }
  };
  snap();
  frames(6);
  if (!reduceMotion) {
    model.beginDragIndex(0);
    lines.push(`${tag} e drag 0`);
    snap();
    const home0 = model.homes[0];
    const home1 = model.homes[1];
    const reach = model.radii[0] + model.radii[1];
    const dir = norm(sub(home0, home1));
    for (const gap of [72, 40, 24, 16, 4]) {
      note(model.updateDrag(add(home1, mul(dir, reach + gap))));
      snap();
      frames(4);
    }
    note(model.endDrag());
    snap();
    frames(8);
    model = new GooMergeModel(SAMPLES, 11, reduceMotion);
    lines.push(`${tag} e reset`);
    snap();
  }
  note(model.combine());
  snap();
  frames(reduceMotion ? 30 : 170);
  return lines;
}

export function goldenTrace() {
  const probe = new GooMergeModel(SAMPLES, 11, false);
  const lines = [
    "v1",
    `dt ${fmt(1 / 60)}`,
    `well ${fmt(TUNING.wellX)} ${fmt(TUNING.wellY)}`,
    `ring ${fmt(TUNING.ringRadius)} ${fmt(TUNING.wellDashRadius)}`,
    `radius ${fmt(TUNING.minRadius)} ${fmt(TUNING.maxRadius)}`,
    `spring ${fmt(TUNING.stiffness)} ${fmt(TUNING.dampingRatio)}`,
    `stretch ${fmt(TUNING.stretchReach)} ${fmt(TUNING.snapGap)} ${fmt(TUNING.stretchShift)} ${fmt(TUNING.attractSpeed)}`,
    `field ${fmt(TUNING.smoothK)} ${fmt(TUNING.fieldEpsilon)} ${fmt(TUNING.connectSDF)}`,
    `clock ${fmt(TUNING.arrival)} ${fmt(TUNING.morphDuration)} ${fmt(TUNING.reducedFade)} ${fmt(TUNING.bobAmplitude)} ${fmt(TUNING.bobOmega)}`,
    `goo ${fmt(TUNING.gooBlur)} ${fmt(TUNING.gooThreshold)}`,
    `card ${fmt(TUNING.cardWidth)} ${fmt(TUNING.cardHeight)} ${fmt(TUNING.cardRadius)} ${fmt(TUNING.foldSize)}`,
    `doc ${TUNING.documentName}`,
    `copy ${TUNING.readyValue} | ${TUNING.mergingValue} | ${TUNING.mergedValue} | ${TUNING.combineAction}`,
    `drops ${SAMPLES.map((drop) => `${drop.name} ${fmt(drop.value)}`).join(" | ")}`,
    `omega ${probe.omegas.map(fmt).join(" ")}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

function gapAt(time) {
  const keys = [
    [0.7, 78],
    [1.15, 28],
    [1.85, 18],
    [2.3, 3],
  ];
  if (time <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i += 1) {
    const [t0, g0] = keys[i - 1];
    const [t1, g1] = keys[i];
    if (time <= t1) {
      const u = (time - t0) / (t1 - t0);
      return g0 + (g1 - g0) * u;
    }
  }
  return keys[keys.length - 1][1];
}

function pointForGap(gap) {
  const home0 = ringPoint(0, 5);
  const home1 = ringPoint(1, 5);
  const reach = radiusFor(SAMPLES[0].value) + radiusFor(SAMPLES[1].value);
  return add(home1, mul(norm(sub(home0, home1)), reach + gap));
}

function scriptInput(model, time, reduce) {
  if (reduce) {
    if (time >= 0.55 && model.phase === "ready") model.combine();
    return;
  }
  if (time >= 0.7 && time < 2.35 && model.phase === "ready") {
    if (model.dragIndex == null) model.beginDragIndex(0);
    model.updateDrag(pointForGap(gapAt(time)));
  } else if (time >= 2.35 && model.dragIndex != null) {
    model.endDrag();
  }
  if (time >= 2.7 && model.phase === "ready") model.combine();
}

export function demoAt(t, options = {}) {
  const reduce = !!options.reduceMotion;
  const model = new GooMergeModel(SAMPLES, 11, reduce);
  const step = 1 / 60;
  let time = 0;
  const target = Math.max(0, t);
  while (time < target - 1e-9) {
    const h = Math.min(step, target - time);
    scriptInput(model, time, reduce);
    model.step(h);
    time += h;
  }
  scriptInput(model, target, reduce);
  return model;
}
