// Pure port of NeighborBounceCore. Constants, integrator order and the parity session match the Swift.
(function (root) {
  const Layout = {
    minTicks: 5,
    maxTicks: 7,
    defaultTicks: 6,
    canvasWidth: 404,
    canvasHeight: 196,
    tickDiameter: 46,
    gap: 10,
    restY: 128,
    trackWidth: 376,
    trackHeight: 78,
    indicatorWidth: 74,
    indicatorHeight: 54,
  };

  const Tuning = {
    substep: 1 / 240,
    get maxFrame() { return 24 * this.substep; },
    staggerSteps: 12,
    get stagger() { return this.staggerSteps * this.substep; },
    kickSpeed: 1200,
    decay: 0.625,
    offsetStiffness: 100,
    offsetDamping: 0.5,
    scaleStiffness: 324,
    scaleDamping: 0.75,
    selectedScale: 1.125,
    indicatorStiffness: 196,
    indicatorDamping: 0.75,
    landBand: 4,
    landSpeed: 48,
    get hapticGap() { return 18 * this.substep; },
    stretchDivisor: 1600,
    stretchLimit: 0.125,
    stretchLateral: 0.5,
  };

  const Palette = {
    paper: [0.965, 0.945, 0.910],
    track: [0.898, 0.863, 0.784],
    ink: [0.165, 0.145, 0.125],
    tick: [0.995, 0.988, 0.976],
  };

  const demo = [
    { id: "ink", title: "Ink", red: 0.18, green: 0.20, blue: 0.28 },
    { id: "sage", title: "Sage", red: 0.35, green: 0.52, blue: 0.40 },
    { id: "clay", title: "Clay", red: 0.72, green: 0.40, blue: 0.30 },
    { id: "gold", title: "Gold", red: 0.78, green: 0.58, blue: 0.22 },
    { id: "plum", title: "Plum", red: 0.48, green: 0.28, blue: 0.48 },
    { id: "tide", title: "Tide", red: 0.22, green: 0.42, blue: 0.55 },
  ];

  function clamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
  function clampedCount(count) { return Math.min(Math.max(count, Layout.minTicks), Layout.maxTicks); }

  function hex(d) {
    if (d === 0) d = 0;
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    view.setFloat64(0, d, false);
    let s = "";
    for (let i = 0; i < 8; i++) s += view.getUint8(i).toString(16).padStart(2, "0");
    return s;
  }

  function originX(count) {
    const n = clampedCount(count);
    const row = n * Layout.tickDiameter + (n - 1) * Layout.gap;
    return (Layout.canvasWidth - row) / 2;
  }

  function restCenter(index, count) {
    const n = clampedCount(count);
    const i = Math.min(Math.max(index, 0), n - 1);
    const x = originX(n) + Layout.tickDiameter / 2 + i * (Layout.tickDiameter + Layout.gap);
    return { x, y: Layout.restY };
  }

  function indexAtX(x, count) {
    const n = clampedCount(count);
    if (!Number.isFinite(x)) return 0;
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < n; i++) {
      const d = Math.abs(x - restCenter(i, n).x);
      if (d < bestD) { bestD = d; best = i; }
    }
    return best;
  }

  function impulse(distance, sign) {
    if (!(distance > 0) || !Number.isFinite(sign) || sign === 0) return { x: 0, y: 0 };
    let speed = Tuning.kickSpeed;
    let i = 1;
    while (i < distance) { speed *= Tuning.decay; i += 1; }
    const s = sign > 0 ? 1 : -1;
    return { x: s * speed * 3 / 5, y: -speed * 4 / 5 };
  }

  function fitted(ticks) {
    if (!ticks || ticks.length === 0) return demo.map((t) => ({ ...t }));
    const capped = ticks.slice(0, Layout.maxTicks);
    if (capped.length >= Layout.minTicks) return capped;
    const out = capped.slice();
    let n = out.length;
    while (out.length < Layout.minTicks) {
      const swatch = demo[n % demo.length];
      out.push({ id: "tick-" + (n + 1), title: String(n + 1), red: swatch.red, green: swatch.green, blue: swatch.blue });
      n += 1;
    }
    return out;
  }

  function makeSpring(value, stiffness, dampingRatio) {
    return { value, velocity: 0, stiffness, dampingRatio };
  }

  function springDamping(s) { return 2 * s.dampingRatio * Math.sqrt(s.stiffness); }

  function substepSpring(s, target, h) {
    const acceleration = s.stiffness * (target - s.value) - springDamping(s) * s.velocity;
    s.velocity += acceleration * h;
    s.value += s.velocity * h;
  }

  function isSettled(s, target, tolerance = 1e-3) {
    return Math.abs(s.value - target) < tolerance && Math.abs(s.velocity) < tolerance * 10;
  }

  function snapSpring(s, target) { s.value = target; s.velocity = 0; }

  function slot(model, index) { return Math.min(Math.max(index, 0), model.count - 1); }

  function scaleTarget(model, index) {
    return index === model.selection ? Tuning.selectedScale : 1;
  }

  function isMoving(model) {
    if (model.pending.length) return true;
    if (!isSettled(model.indicator, model.indicatorTarget)) return true;
    for (let i = 0; i < model.count; i++) {
      const o = model.offsets[i];
      if (!isSettled(o.x, 0) || !isSettled(o.y, 0)) return true;
      if (!isSettled(model.scales[i], scaleTarget(model, i))) return true;
    }
    return false;
  }

  function snap(model) {
    model.pending = [];
    for (let i = 0; i < model.count; i++) {
      snapSpring(model.offsets[i].x, 0);
      snapSpring(model.offsets[i].y, 0);
      snapSpring(model.scales[i], scaleTarget(model, i));
      model.airborne[i] = false;
      model.wasHigh[i] = false;
    }
    snapSpring(model.indicator, model.indicatorTarget);
  }

  function createModel(count = Layout.defaultTicks, selection = 0, reduceMotion = false) {
    const n = clampedCount(count);
    const s = Math.min(Math.max(selection, 0), n - 1);
    const target = restCenter(s, n).x;
    const offsets = [];
    const scales = [];
    for (let i = 0; i < n; i++) {
      offsets.push({
        x: makeSpring(0, Tuning.offsetStiffness, Tuning.offsetDamping),
        y: makeSpring(0, Tuning.offsetStiffness, Tuning.offsetDamping),
      });
      scales.push(makeSpring(i === s ? Tuning.selectedScale : 1, Tuning.scaleStiffness, Tuning.scaleDamping));
    }
    return {
      count: n,
      selection: s,
      time: 0,
      reduceMotion: !!reduceMotion,
      launches: 0,
      landings: 0,
      suppressedLandings: 0,
      settles: 0,
      pending: [],
      indicator: makeSpring(target, Tuning.indicatorStiffness, Tuning.indicatorDamping),
      indicatorTarget: target,
      offsets,
      scales,
      airborne: Array(n).fill(false),
      wasHigh: Array(n).fill(false),
      wasMoving: false,
      lastLandingTime: null,
    };
  }

  function offset(model, index) {
    const o = model.offsets[slot(model, index)];
    return { x: o.x.value, y: o.y.value };
  }

  function velocity(model, index) {
    const o = model.offsets[slot(model, index)];
    return { x: o.x.velocity, y: o.y.velocity };
  }

  function pose(model, index) {
    const i = slot(model, index);
    const o = offset(model, i);
    const sc = model.scales[i].value;
    const stretch = clamp(-model.offsets[i].y.velocity / Tuning.stretchDivisor, -Tuning.stretchLimit, Tuning.stretchLimit);
    const rest = restCenter(i, model.count);
    return {
      center: { x: rest.x + o.x, y: rest.y + o.y },
      scaleX: sc * (1 - Tuning.stretchLateral * stretch),
      scaleY: sc * (1 + stretch),
      lift: Math.max(0, -o.y),
    };
  }

  function select(model, index) {
    const i = slot(model, index);
    const changed = i !== model.selection;
    model.selection = i;
    model.indicatorTarget = restCenter(i, model.count).x;
    if (model.reduceMotion) {
      snap(model);
      return [changed ? "selected:" + i : "nudged:" + i];
    }
    model.pending = [];
    for (let j = 0; j < model.count; j++) {
      if (j === i) continue;
      const distance = Math.abs(j - i);
      const sign = j > i ? 1 : -1;
      model.pending.push({
        fireAt: model.time + Tuning.stagger * distance,
        index: j,
        velocity: impulse(distance, sign),
      });
    }
    model.pending.sort((a, b) => (a.fireAt !== b.fireAt ? a.fireAt - b.fireAt : a.index - b.index));
    return [changed ? "selected:" + i : "nudged:" + i];
  }

  function setReduceMotion(model, on) {
    if (!!on === model.reduceMotion) return;
    const moving = isMoving(model);
    model.reduceMotion = !!on;
    if (on) {
      snap(model);
      if (moving) model.wasMoving = true;
    }
  }

  function landing(model, i) {
    const y = model.offsets[i].y.value;
    const vy = model.offsets[i].y.velocity;
    const high = y < -Tuning.landBand;
    const events = [];
    if (model.airborne[i] && model.wasHigh[i] && !high && vy > Tuning.landSpeed) {
      model.airborne[i] = false;
      if (model.lastLandingTime !== null && model.time - model.lastLandingTime < Tuning.hapticGap) {
        model.suppressedLandings += 1;
      } else {
        model.lastLandingTime = model.time;
        model.landings += 1;
        events.push("landed:" + i);
      }
    }
    model.wasHigh[i] = high;
    return events;
  }

  function substep(model, h) {
    const events = [];
    model.time += h;
    while (model.pending.length && model.pending[0].fireAt <= model.time + 1e-9) {
      const kick = model.pending.shift();
      model.offsets[kick.index].x.velocity += kick.velocity.x;
      model.offsets[kick.index].y.velocity += kick.velocity.y;
      model.airborne[kick.index] = true;
      model.launches += 1;
      events.push("launched:" + kick.index);
    }
    for (let i = 0; i < model.count; i++) {
      substepSpring(model.offsets[i].x, 0, h);
      substepSpring(model.offsets[i].y, 0, h);
      substepSpring(model.scales[i], scaleTarget(model, i), h);
      events.push(...landing(model, i));
    }
    substepSpring(model.indicator, model.indicatorTarget, h);
    return events;
  }

  function step(model, dt) {
    if (!Number.isFinite(dt) || dt <= 0) return [];
    const events = [];
    let remaining = Math.min(dt, Tuning.maxFrame);
    while (remaining > 1e-12) {
      const h = Math.min(remaining, Tuning.substep);
      events.push(...substep(model, h));
      remaining -= h;
    }
    const moving = isMoving(model);
    if (model.wasMoving && !moving) {
      model.settles += 1;
      events.push("settled");
    }
    model.wasMoving = moving;
    return events;
  }

  function traceLine(model) {
    const parts = [
      hex(model.time),
      String(model.selection),
      model.reduceMotion ? "1" : "0",
      hex(model.indicator.value),
      hex(model.indicator.velocity),
      String(model.pending.length),
      String(model.landings),
      String(model.suppressedLandings),
      String(model.launches),
    ];
    for (let i = 0; i < model.count; i++) {
      parts.push(hex(model.offsets[i].x.value));
      parts.push(hex(model.offsets[i].y.value));
      parts.push(hex(model.offsets[i].x.velocity));
      parts.push(hex(model.offsets[i].y.velocity));
      parts.push(hex(model.scales[i].value));
      const drawn = pose(model, i);
      parts.push(hex(drawn.scaleX));
      parts.push(hex(drawn.scaleY));
      parts.push(hex(drawn.lift));
      parts.push(hex(drawn.center.x));
      parts.push(hex(drawn.center.y));
    }
    return parts.join(" ");
  }

  function parityLines() {
    const lines = [];
    for (let n = 5; n <= 7; n++) {
      for (let i = 0; i < n; i++) {
        const p = restCenter(i, n);
        lines.push("L " + n + " " + i + " " + hex(p.x) + " " + hex(p.y));
      }
    }
    for (let distance = 1; distance <= 6; distance++) {
      const v = impulse(distance, 1);
      lines.push("K " + distance + " " + hex(v.x) + " " + hex(v.y));
    }
    const row = fitted([]);
    lines.push("F " + row.length + " " + row.map((t) => t.id).join(","));

    const model = createModel(6, 0, false);
    lines.push(traceLine(model));
    function run(steps) {
      for (let i = 0; i < steps; i++) {
        step(model, Tuning.substep);
        if ((i + 1) % 4 === 0) lines.push(traceLine(model));
      }
    }
    run(8);
    select(model, 3);
    lines.push(traceLine(model));
    run(48);
    select(model, 1);
    lines.push(traceLine(model));
    run(16);
    select(model, 5);
    lines.push(traceLine(model));
    run(12);
    select(model, 5);
    lines.push(traceLine(model));
    run(240);
    setReduceMotion(model, true);
    lines.push(traceLine(model));
    select(model, 2);
    lines.push(traceLine(model));
    run(24);
    setReduceMotion(model, false);
    lines.push(traceLine(model));
    select(model, 0);
    lines.push(traceLine(model));
    run(200);
    lines.push(traceLine(model));
    return lines;
  }

  root.NeighborBounce = {
    Layout, Tuning, Palette, demo, hex, restCenter, indexAtX, impulse, fitted,
    createModel, select, setReduceMotion, step, pose, offset, velocity, traceLine, parityLines,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
