// Crumple core mirrored from CrumpleCore. Constants match CrumpleRules.
// Randomness is SplitMix64 via SeededRandom.uniform (top 53 bits), not Double.random.

const RULES = {
  commitProgress: 0.8,
  creaseAngle: 0.35,
  columns: 5,
  rows: 4,
  ballRadiusFraction: 1 / 6,
  buckle: 2,
  seed: 34n,
  light: [0.45, 0.55, 0.7],
  paper: [0.96, 0.93, 0.86],
  ambient: 0.22,
  springStiffness: 380,
  springDamping: 0.4,
  calmStiffness: 520,
  calmDamping: 1,
  tossDuration: 0.5,
  reduceMotionDuration: 0.35,
  tossControl: 0.35,
  hapticInterval: 0.12,
};

function splitmix(seed) {
  let state = BigInt(seed) & 0xffffffffffffffffn;
  return function next() {
    state = (state + 0x9e3779b97f4a7c15n) & 0xffffffffffffffffn;
    let z = state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & 0xffffffffffffffffn;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & 0xffffffffffffffffn;
    return (z ^ (z >> 31n)) & 0xffffffffffffffffn;
  };
}

function uniform(next, lo, hi) {
  const unit = Number(next() >> 11n) / Number(1n << 53n);
  return lo + (hi - lo) * unit;
}

function clamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
function clamp01(x) { return clamp(x, 0, 1); }
function lerp(a, b, t) { return a + (b - a) * t; }

function v2(x, y) { return { x, y }; }
function add2(a, b) { return v2(a.x + b.x, a.y + b.y); }
function sub2(a, b) { return v2(a.x - b.x, a.y - b.y); }
function mul2(a, s) { return v2(a.x * s, a.y * s); }
function dot2(a, b) { return a.x * b.x + a.y * b.y; }
function len2(a) { return Math.hypot(a.x, a.y); }
function norm2(a) {
  const l = len2(a);
  return l > 0 ? mul2(a, 1 / l) : v2(0, 0);
}
function perp2(a) { return v2(-a.y, a.x); }

function v3(x, y, z) { return { x, y, z }; }
function sub3(a, b) { return v3(a.x - b.x, a.y - b.y, a.z - b.z); }
function mul3(a, s) { return v3(a.x * s, a.y * s, a.z * s); }
function dot3(a, b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
function cross3(a, b) {
  return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
function len3(a) { return Math.hypot(a.x, a.y, a.z); }
function norm3(a) {
  const l = len3(a);
  return l > 1e-12 ? mul3(a, 1 / l) : v3(0, 0, 0);
}

function rect(x, y, width, height) {
  return {
    x, y, width, height,
    center: v2(x + width / 2, y + height / 2),
    contains(p) {
      if (width <= 0 || height <= 0) return false;
      return p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height;
    },
  };
}

function unitLight() {
  return norm3(v3(RULES.light[0], RULES.light[1], RULES.light[2]));
}

function amplitudes() {
  const next = splitmix(RULES.seed);
  const count = (RULES.columns + 1) * (RULES.rows + 1);
  const out = [];
  for (let i = 0; i < count; i++) out.push(uniform(next, -1, 1));
  return out;
}

const AMPS = amplitudes();

function ballRadius(card) {
  return Math.min(Math.abs(card.width), Math.abs(card.height)) * RULES.ballRadiusFraction;
}

function sample(card, shape, pull = v2(0, 0)) {
  const s = Math.max(shape, 0);
  const ballR = ballRadius(card);
  const center = card.center;
  const cols = RULES.columns;
  const rows = RULES.rows;
  const stride = cols + 1;
  const vertices = [];
  for (let j = 0; j <= rows; j++) {
    for (let i = 0; i <= cols; i++) {
      const rest = v2(card.x + card.width * i / cols, card.y + card.height * j / rows);
      const offset = sub2(rest, center);
      const dist = len2(offset);
      const dir = dist > 1e-9 ? mul2(offset, 1 / dist) : v2(1, 0);
      const radius = s <= 1 ? lerp(dist, ballR, s) : ballR * s;
      const xy = add2(add2(center, mul2(dir, radius)), pull);
      const z = AMPS[j * stride + i] * Math.min(s, 1.25) * ballR * RULES.buckle;
      vertices.push(v3(xy.x, xy.y, z));
    }
  }
  const light = unitLight();
  const facets = [];
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const v00 = row * stride + col;
      const v10 = v00 + 1;
      const v01 = v00 + stride;
      const v11 = v01 + 1;
      facets.push(facet(v00, v10, v01, vertices, light));
      facets.push(facet(v10, v11, v01, vertices, light));
    }
  }
  const edges = sharedEdges(facets);
  return { vertices, facets, edges };
}

function facet(i0, i1, i2, vertices, light) {
  const normal = cross3(sub3(vertices[i1], vertices[i0]), sub3(vertices[i2], vertices[i0]));
  const n = norm3(normal);
  const shade = Math.max(0, dot3(n, light));
  const t = RULES.ambient + (1 - RULES.ambient) * clamp01(shade);
  const color = RULES.paper.map((c) => c * t);
  return { i0, i1, i2, normal: n, shade, color };
}

function sharedEdges(facets) {
  const owners = new Map();
  facets.forEach((f, index) => {
    [[f.i0, f.i1], [f.i1, f.i2], [f.i2, f.i0]].forEach(([p, q]) => {
      const a = Math.min(p, q);
      const b = Math.max(p, q);
      const key = `${a},${b}`;
      const list = owners.get(key) || [];
      list.push(index);
      owners.set(key, list);
    });
  });
  const shared = [...owners.entries()]
    .filter(([, list]) => list.length === 2)
    .map(([key, list]) => {
      const [a, b] = key.split(",").map(Number);
      return { a, b, left: list[0], right: list[1] };
    })
    .sort((p, q) => (p.a === q.a ? p.b - q.b : p.a - q.a));
  return shared.map((edge, index) => ({ ...edge, index }));
}

function foldAngles(sampled) {
  return sampled.edges.map((edge) => {
    const a = norm3(sampled.facets[edge.left].normal);
    const b = norm3(sampled.facets[edge.right].normal);
    return Math.acos(clamp(dot3(a, b), -1, 1));
  });
}

function createModel(card, bin, reduceMotion = false) {
  const state = {
    card, bin, reduceMotion,
    phase: "idle",
    pull: v2(0, 0),
    shape: 0,
    toss: 0,
    zoneLatched: false,
    log: [],
    creases: new Set(),
    previousAngles: [],
    previousProgress: 0,
  };
  function progress() {
    const axis = sub2(bin.center, card.center);
    const gap2 = dot2(axis, axis);
    if (gap2 <= 1e-12) return 0;
    return clamp01(dot2(state.pull, axis) / gap2);
  }
  function center() { return add2(card.center, state.pull); }
  function currentSample() {
    return sample(card, state.shape, state.phase === "tossing" || state.phase === "gone" ? v2(0, 0) : state.pull);
  }
  function crossed() {
    const angles = foldAngles(currentSample());
    const fresh = [];
    angles.forEach((angle, index) => {
      const prior = index < state.previousAngles.length ? state.previousAngles[index] : 0;
      if (prior < RULES.creaseAngle && angle >= RULES.creaseAngle && !state.creases.has(index)) {
        state.creases.add(index);
        fresh.push(index);
      }
    });
    return fresh;
  }
  return {
    state,
    progress,
    begin(point) {
      if (state.phase !== "idle" && state.phase !== "springing") return false;
      const c = center();
      const inside = point.x >= c.x - card.width / 2 && point.x <= c.x + card.width / 2
        && point.y >= c.y - card.height / 2 && point.y <= c.y + card.height / 2;
      if (!inside) return false;
      state.phase = "dragging";
      state.creases = new Set();
      state.pull = sub2(point, card.center);
      state.shape = progress();
      state.zoneLatched = bin.contains(center());
      state.previousProgress = progress();
      state.previousAngles = foldAngles(currentSample());
      return true;
    },
    drag(point) {
      if (state.phase !== "dragging") return [];
      state.pull = sub2(point, card.center);
      state.shape = progress();
      state.zoneLatched = bin.contains(center());
      let fresh = [];
      if (progress() > state.previousProgress + 1e-9) fresh = crossed();
      state.previousProgress = progress();
      state.previousAngles = foldAngles(currentSample());
      fresh.forEach((id) => state.log.push(id));
      return fresh;
    },
    end() {
      if (state.phase !== "dragging") return false;
      if (progress() >= RULES.commitProgress || state.zoneLatched) {
        state.phase = "tossing";
        return true;
      }
      state.phase = "springing";
      return false;
    },
  };
}

const api = {
  RULES, rect, sample, foldAngles, unitLight, createModel, ballRadius, v2, add2, sub2, mul2,
};
if (typeof module !== "undefined" && module.exports) module.exports = api;
if (typeof globalThis !== "undefined") globalThis.Crumple = api;
