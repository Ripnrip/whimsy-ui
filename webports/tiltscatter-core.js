// Port of TiltScatterCore. Same constants, same polynomial sin, same SplitMix64.
// Node and the browser both see `globalThis.TiltScatter`.
(function (root) {
  const MASK = (1n << 64n) - 1n;
  const TWO_PI = Math.PI * 2;
  const INV_TWO_PI = 1 / TWO_PI;
  const HALF_PI = Math.PI / 2;

  function clamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
  function clamp01(x) { return clamp(x, 0, 1); }
  function smoothstep01(u) { const t = clamp01(u); return t * t * (3 - 2 * t); }
  function hypot(x, y) { return Math.sqrt(x * x + y * y); }

  function sin(x) {
    if (!Number.isFinite(x)) return 0;
    const k = Math.floor(x * INV_TWO_PI + 0.5);
    let r = x - k * TWO_PI;
    if (r > HALF_PI) r = Math.PI - r;
    else if (r < -HALF_PI) r = -Math.PI - r;
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

  function hex(d) {
    if (d === 0) d = 0;
    const buf = new ArrayBuffer(8);
    const view = new DataView(buf);
    view.setFloat64(0, d, false);
    let s = "";
    for (let i = 0; i < 8; i++) s += view.getUint8(i).toString(16).padStart(2, "0");
    return s;
  }

  function mul64(a, b) { return (a * b) & MASK; }
  function add64(a, b) { return (a + b) & MASK; }
  function xor64(a, b) { return a ^ b; }
  function shr64(a, n) { return a >> BigInt(n); }

  function kickSeed(base, row, index) {
    let x = add64(base, 0x9E3779B97F4A7C15n);
    x = xor64(x, mul64(BigInt(row), 0xBF58476D1CE4E5B9n));
    x = xor64(x, mul64(BigInt(index), 0x94D049BB133111EBn));
    x = xor64(x, shr64(x, 30));
    x = mul64(x, 0xBF58476D1CE4E5B9n);
    x = xor64(x, shr64(x, 27));
    return x;
  }

  function makeRng(seed) {
    let state = seed & MASK;
    return {
      next() {
        state = add64(state, 0x9E3779B97F4A7C15n);
        let z = state;
        z = mul64(xor64(z, shr64(z, 30)), 0xBF58476D1CE4E5B9n);
        z = mul64(xor64(z, shr64(z, 27)), 0x94D049BB133111EBn);
        return xor64(z, shr64(z, 31));
      },
      uniform(lo, hi) {
        const unit = Number(this.next() >> 11n) / Number(1n << 53n);
        return lo + (hi - lo) * unit;
      },
    };
  }

  const Layout = {
    cardWidth: 360, cardHeight: 600,
    rowX: 16, rowWidth: 328, rowHeight: 48, rowGap: 6, listTop: 92,
    titleInset: 46, titleRightPad: 12, fontSize: 16,
    chipHeight: 20, chipMinWidth: 10, rowCorner: 14, chipCorner: 5, checkbox: 22,
    buttonTop: 368, buttonHeight: 40, trayTop: 420, trayHeight: 164,
    boundLeft: 22, boundRight: 338, boundTop: 80, boundBottom: 578,
    collisionRadius: 7.5, fallenGap: 26,
    rowTop(i) { return this.listTop + i * (this.rowHeight + this.rowGap); },
    rowCenterY(i) { return this.rowTop(i) + this.rowHeight / 2; },
  };

  function isGap(ch) { return ch !== "" && /^[\s]+$/.test(ch); }

  function unitAdvance(ch) {
    if (ch.length !== 1) return 1;
    switch (ch) {
      case " ": case "\t": case "\n": return 0.33;
      case "i": case "l": case "I": case "j": case "!": case "|": case "'": return 0.28;
      case "f": case "t": case "r": case ".": case ",": case ":": case ";": return 0.36;
      case "m": case "w": case "M": case "W": return 0.86;
      case "J": case "c": case "s": case "z": return 0.48;
      default:
        if (ch >= "A" && ch <= "Z") return 0.70;
        return 0.56;
    }
  }

  function glyphs(title, row) {
    const maxWidth = Layout.rowWidth - Layout.titleInset - Layout.titleRightPad;
    const parts = [];
    let total = 0;
    for (const ch of title) {
      const advance = Layout.fontSize * unitAdvance(ch);
      parts.push([ch, advance, isGap(ch)]);
      total += advance;
    }
    const scale = total > maxWidth && total > 0 ? maxWidth / total : 1;
    let pen = Layout.rowX + Layout.titleInset;
    const y = Layout.rowCenterY(row);
    const out = [];
    let index = 0;
    for (const [glyph, advance, gap] of parts) {
      const width = advance * scale;
      if (!gap) {
        const chipWidth = Math.min(width, Math.max(Layout.chipMinWidth, width - 1.2));
        out.push({ row, index, glyph, homeX: pen + width * 0.5, homeY: y, width: chipWidth });
        index += 1;
      }
      pen += width;
    }
    return out;
  }

  const Tuning = {
    substep: 1 / 120,
    maxFrame: 0.1,
    dissolveDuration: 0.42,
    reducedDissolve: 0.18,
    pop: 0.07,
    linearDrag: 1.85,
    spinDrag: 1.15,
    restitution: 0.22,
    friction: 0.18,
    frictionCap: 80,
    spinFromContact: 0.012,
    wallSpin: 0.002,
    pairIterations: 4,
    maxSpeed: 2200,
    sleepSpeed: 22,
    wakeSide: 120,
    supportSlop: 0.6,
    restoreK: 220,
    restoreZ: 0.78,
    restoreAngleK: 140,
    restoreAngleZ: 0.85,
    restoreLimit: 2.4,
    seatDistance: 0.4,
    seatAngle: 0.02,
    seatSpeed: 12,
    seatSpin: 0.35,
    fadeDistance: 28,
  };

  const Gravity = { magnitude: 1500, neutralPitch: 0.70, tiltRange: 1.15 };
  function acceleration(tx, ty) {
    const downY = Gravity.magnitude * sin(Gravity.neutralPitch);
    if (!Number.isFinite(tx) || !Number.isFinite(ty)) return { x: 0, y: downY };
    const x = clamp(tx, -1, 1);
    const y = clamp(ty, -1, 1);
    const roll = x * Gravity.tiltRange;
    const pitch = Gravity.neutralPitch - y * Gravity.tiltRange;
    return { x: sin(roll) * Gravity.magnitude, y: sin(pitch) * Gravity.magnitude };
  }

  const Motion = { neutralPitch: 0.60, range: 0.55 };
  function tiltFromAttitude(pitch, roll) {
    if (!Number.isFinite(pitch) || !Number.isFinite(roll) || Motion.range <= 0) return { x: 0, y: 0 };
    return {
      x: clamp(roll / Motion.range, -1, 1),
      y: clamp(-(pitch - Motion.neutralPitch) / Motion.range, -1, 1),
    };
  }
  function tiltFromFinger(px, py, sx, sy) {
    if (!(sx > 1) || !(sy > 1) || !Number.isFinite(px) || !Number.isFinite(py)) return { x: 0, y: 0 };
    return {
      x: clamp((px / sx) * 2 - 1, -1, 1),
      y: -clamp((py / sy) * 2 - 1, -1, 1),
    };
  }

  const Catalog = [
    { id: "fern", title: "Water the fern" },
    { id: "ink", title: "Buy walnut ink" },
    { id: "letter", title: "Post the letter" },
    { id: "press", title: "Trim the press" },
    { id: "tea", title: "Steep the tea" },
  ];

  const phaseLetter = { idle: "I", dissolving: "D", tumbling: "T", restoring: "R", pinned: "P" };

  function createModel(tasks = Catalog, seed = 0x71C75CA7) {
    const seedBI = BigInt(seed);
    const rows = [];
    const chips = [];
    tasks.forEach((task, index) => {
      rows.push({ index, title: task.title, phase: "idle", clock: 0, titleOpacity: 1, landed: false });
      for (const g of glyphs(task.title, index)) {
        chips.push({
          row: g.row, index: g.index, glyph: g.glyph,
          homeX: g.homeX, homeY: g.homeY, width: g.width,
          x: g.homeX, y: g.homeY, vx: 0, vy: 0, angle: 0, spin: 0,
          scale: 1, opacity: 0, asleep: false,
        });
      }
    });
    const model = {
      tasks, seed: seedBI, rows, chips,
      tiltX: 0, tiltY: 0, time: 0, reduceMotion: false,
      completeHaptics: 0, landHaptics: 0, restoreHaptics: 0,
      announcement: null, announcementCount: 0,
    };
    model.gravity = () => acceleration(model.tiltX, model.tiltY);
    model.setTilt = (x, y) => {
      if (!Number.isFinite(x) || !Number.isFinite(y)) return;
      model.tiltX = clamp(x, -1, 1);
      model.tiltY = clamp(y, -1, 1);
    };
    model.setReduceMotion = (on) => {
      if (on === model.reduceMotion) return;
      model.reduceMotion = on;
      if (!on) return;
      for (let i = 0; i < rows.length; i++) if (rows[i].phase !== "idle") pin(model, i);
    };
    model.toggle = (index) => {
      if (index < 0 || index >= rows.length) return [];
      const phase = rows[index].phase;
      if (phase === "idle") return beginComplete(model, index);
      if (phase === "restoring") return [];
      return beginRestore(model, index, true);
    };
    model.restoreAll = () => {
      const events = [];
      let any = false;
      for (let i = 0; i < rows.length; i++) {
        if (rows[i].phase !== "idle" && rows[i].phase !== "restoring") {
          const piece = beginRestore(model, i, false);
          if (piece.length) any = true;
          events.push(...piece);
        }
      }
      if (any) {
        model.announcement = "Restoring every letter";
        model.announcementCount += 1;
        model.restoreHaptics += 1;
        events.push("haptic:restore");
      }
      return events;
    };
    model.step = (dt) => {
      if (!Number.isFinite(dt) || dt <= 0) return [];
      const events = [];
      let remaining = Math.min(dt, Tuning.maxFrame);
      while (remaining > 1e-12) {
        const h = Math.min(remaining, Tuning.substep);
        events.push(...substep(model, h));
        model.time += h;
        remaining -= h;
      }
      return events;
    };
    model.traceLine = () => {
      const parts = [hex(model.time), hex(model.tiltX), hex(model.tiltY)];
      parts.push(rows.map((r) => phaseLetter[r.phase]).join(""));
      for (const row of rows) parts.push(hex(row.titleOpacity));
      for (const c of chips) {
        parts.push(hex(c.x), hex(c.y), hex(c.angle), hex(c.vx), hex(c.vy), c.asleep ? "1" : "0");
      }
      return parts.join(" ");
    };
    model.canRestore = () => rows.some((r) => r.phase !== "idle");
    return model;
  }

  function beginComplete(model, index) {
    const row = model.rows[index];
    row.phase = "dissolving";
    row.clock = 0;
    row.landed = false;
    row.titleOpacity = 1;
    for (const c of model.chips) if (c.row === index) {
      c.x = c.homeX; c.y = c.homeY; c.vx = 0; c.vy = 0; c.angle = 0; c.spin = 0;
      c.scale = 1; c.opacity = 0; c.asleep = false;
    }
    model.completeHaptics += 1;
    model.announcement = model.reduceMotion
      ? `Completed ${row.title}`
      : `Completed ${row.title}. Letters scattered`;
    model.announcementCount += 1;
    return ["completed"];
  }

  function beginRestore(model, index, announce) {
    const row = model.rows[index];
    if (row.phase === "idle" || row.phase === "restoring") return [];
    if (model.reduceMotion || row.phase === "pinned" || row.phase === "dissolving") {
      const title = row.title;
      seat(model, index);
      model.announcement = `Restored ${title}`;
      model.announcementCount += 1;
      const events = ["seated"];
      if (announce) { model.restoreHaptics += 1; events.push("haptic:restore"); }
      return events;
    }
    row.phase = "restoring";
    row.clock = 0;
    for (const c of model.chips) if (c.row === index) {
      c.asleep = false;
      c.vx *= 0.25; c.vy *= 0.25; c.spin *= 0.25;
    }
    const events = ["restoreBegan"];
    if (announce) {
      model.announcement = `Restoring ${row.title}`;
      model.announcementCount += 1;
      model.restoreHaptics += 1;
      events.push("haptic:restore");
    }
    return events;
  }

  function pin(model, index) {
    const row = model.rows[index];
    row.phase = "pinned"; row.clock = 0; row.titleOpacity = 0; row.landed = false;
    for (const c of model.chips) if (c.row === index) {
      c.x = c.homeX; c.y = c.homeY; c.vx = 0; c.vy = 0; c.angle = 0; c.spin = 0;
      c.scale = 1; c.opacity = 1; c.asleep = false;
    }
  }

  function seat(model, index) {
    const row = model.rows[index];
    row.phase = "idle"; row.clock = 0; row.titleOpacity = 1; row.landed = false;
    for (const c of model.chips) if (c.row === index) {
      c.x = c.homeX; c.y = c.homeY; c.vx = 0; c.vy = 0; c.angle = 0; c.spin = 0;
      c.scale = 1; c.opacity = 0; c.asleep = false;
    }
  }

  function substep(model, h) {
    const events = [];
    const tumbling = [];
    model.rows.forEach((row, index) => {
      if (row.phase === "dissolving") events.push(...advanceDissolve(model, index, h));
      else if (row.phase === "tumbling") tumbling.push(index);
      else if (row.phase === "restoring") events.push(...advanceRestore(model, index, h));
    });
    if (tumbling.length && !model.reduceMotion) events.push(...integrate(model, tumbling, h));
    return events;
  }

  function advanceDissolve(model, index, h) {
    const row = model.rows[index];
    const duration = model.reduceMotion ? Tuning.reducedDissolve : Tuning.dissolveDuration;
    row.clock += h;
    const u = Math.min(1, row.clock / duration);
    const eased = smoothstep01(u);
    const pop = 1 + Tuning.pop * sin(Math.PI * u);
    row.titleOpacity = 1 - eased;
    for (const c of model.chips) if (c.row === index) {
      c.opacity = eased; c.scale = pop; c.x = c.homeX; c.y = c.homeY; c.angle = 0; c.vx = 0; c.vy = 0; c.spin = 0;
    }
    if (row.clock < duration) return [];
    if (model.reduceMotion) { pin(model, index); return []; }
    row.phase = "tumbling";
    row.titleOpacity = 0;
    applyKick(model, index);
    return ["scattered"];
  }

  function applyKick(model, index) {
    for (const c of model.chips) if (c.row === index) {
      const rng = makeRng(kickSeed(model.seed, index, c.index));
      c.x = c.homeX; c.y = c.homeY;
      c.vx = rng.uniform(-70, 70);
      c.vy = rng.uniform(-150, -40);
      c.spin = rng.uniform(-4.5, 4.5);
      c.angle = 0; c.scale = 1; c.opacity = 1; c.asleep = false;
    }
  }

  function advanceRestore(model, index, h) {
    const row = model.rows[index];
    row.clock += h;
    const k = Tuning.restoreK;
    const cDamp = 2 * Tuning.restoreZ * Math.sqrt(k);
    const ka = Tuning.restoreAngleK;
    const ca = 2 * Tuning.restoreAngleZ * Math.sqrt(ka);
    let allSeated = true;
    let mean = 0;
    let count = 0;
    for (const chip of model.chips) if (chip.row === index) {
      const ax = k * (chip.homeX - chip.x) - cDamp * chip.vx;
      const ay = k * (chip.homeY - chip.y) - cDamp * chip.vy;
      chip.vx += ax * h; chip.vy += ay * h;
      chip.x += chip.vx * h; chip.y += chip.vy * h;
      const aa = ka * (0 - chip.angle) - ca * chip.spin;
      chip.spin += aa * h;
      chip.angle += chip.spin * h;
      chip.scale = 1; chip.asleep = false;
      const dx = chip.x - chip.homeX;
      const dy = chip.y - chip.homeY;
      const dist = hypot(dx, dy);
      const u = Math.min(1, dist / Tuning.fadeDistance);
      chip.opacity = u;
      mean += u; count += 1;
      const speed = hypot(chip.vx, chip.vy);
      const close = dist < Tuning.seatDistance && Math.abs(chip.angle) < Tuning.seatAngle
        && speed < Tuning.seatSpeed && Math.abs(chip.spin) < Tuning.seatSpin;
      if (!close) allSeated = false;
    }
    row.titleOpacity = count > 0 ? (1 - mean / count) : 1;
    if (allSeated || row.clock >= Tuning.restoreLimit) {
      const title = row.title;
      seat(model, index);
      model.announcement = `Restored ${title}`;
      model.announcementCount += 1;
      return ["seated"];
    }
    return [];
  }

  function onFloor(c) {
    return c.y >= Layout.boundBottom - Layout.collisionRadius - 0.75;
  }

  function supportedIndexes(chips, indexes) {
    const supported = new Set();
    const limit = Layout.collisionRadius * 2 + Tuning.supportSlop;
    for (let pass = 0; pass < 8; pass++) {
      let changed = false;
      for (const j of indexes) {
        if (supported.has(j)) continue;
        const cj = chips[j];
        if (onFloor(cj)) { supported.add(j); changed = true; continue; }
        for (const k of supported) {
          if (hypot(cj.x - chips[k].x, cj.y - chips[k].y) <= limit) {
            supported.add(j); changed = true; break;
          }
        }
      }
      if (!changed) break;
    }
    return supported;
  }

  function integrate(model, rowIndices, h) {
    const tumbling = new Set(rowIndices);
    const indexes = [];
    model.chips.forEach((c, i) => { if (tumbling.has(c.row)) indexes.push(i); });
    const g = model.gravity();
    const damp = Math.max(0, 1 - Tuning.linearDrag * h);
    const spinDamp = Math.max(0, 1 - Tuning.spinDrag * h);
    const resting = supportedIndexes(model.chips, indexes);
    for (const i of indexes) {
      const c = model.chips[i];
      if (c.asleep) {
        if (Math.abs(g.x) < Tuning.wakeSide && resting.has(i)) { c.vx = 0; c.vy = 0; c.spin = 0; continue; }
        c.asleep = false;
      }
      c.vx += g.x * h; c.vy += g.y * h;
      c.vx *= damp; c.vy *= damp;
      const sp2 = c.vx * c.vx + c.vy * c.vy;
      if (sp2 > Tuning.maxSpeed * Tuning.maxSpeed && sp2 > 0) {
        const k = Tuning.maxSpeed / Math.sqrt(sp2);
        c.vx *= k; c.vy *= k;
      }
      c.x += c.vx * h; c.y += c.vy * h;
      c.spin *= spinDamp;
      c.angle += c.spin * h;
      c.opacity = 1; c.scale = 1;
    }
    if (indexes.length > 1) {
      for (let n = 0; n < Tuning.pairIterations; n++) {
        for (let a = 0; a < indexes.length; a++) {
          for (let b = a + 1; b < indexes.length; b++) resolvePair(model, indexes[a], indexes[b]);
        }
      }
    }
    const events = [];
    for (const i of indexes) {
      resolveWalls(model.chips[i]);
      events.push(...landIfNeeded(model, i));
    }
    const settled = supportedIndexes(model.chips, indexes);
    for (const i of indexes) sleepIfSettled(model, i, settled.has(i), g.x);
    return events;
  }

  function fallen(c) { return c.y > c.homeY + Layout.fallenGap; }

  function resolvePair(model, i, j) {
    const a = model.chips[i];
    const b = model.chips[j];
    const g = model.gravity();
    if (a.asleep && b.asleep && Math.abs(g.x) < Tuning.wakeSide) return;
    if (!fallen(a) || !fallen(b)) return;
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let dist2 = dx * dx + dy * dy;
    const minD = Layout.collisionRadius * 2;
    if (dist2 >= minD * minD && dist2 > 0) return;
    let dist = Math.sqrt(dist2);
    if (dist < 1e-9) { dx = 1; dy = 0; dist = 1e-9; }
    const nx = dx / dist;
    const ny = dy / dist;
    const half = (minD - dist) * 0.5;
    a.x -= nx * half; a.y -= ny * half;
    b.x += nx * half; b.y += ny * half;
    const rvx = b.vx - a.vx;
    const rvy = b.vy - a.vy;
    const rel = rvx * nx + rvy * ny;
    if (!(rel < 0)) return;
    const impulse = -(1 + Tuning.restitution) * rel * 0.5;
    a.vx -= impulse * nx; a.vy -= impulse * ny;
    b.vx += impulse * nx; b.vy += impulse * ny;
    const tx = -ny, ty = nx;
    const vt = rvx * tx + rvy * ty;
    const fr = clamp(vt * Tuning.friction, -Tuning.frictionCap, Tuning.frictionCap);
    a.vx += fr * tx * 0.5; a.vy += fr * ty * 0.5;
    b.vx -= fr * tx * 0.5; b.vy -= fr * ty * 0.5;
    const kick = vt * Tuning.spinFromContact;
    a.spin -= kick; b.spin += kick;
    a.asleep = false; b.asleep = false;
  }

  function resolveWalls(c) {
    const r = Layout.collisionRadius;
    const e = Tuning.restitution;
    if (c.x < Layout.boundLeft + r) {
      c.x = Layout.boundLeft + r;
      if (c.vx < 0) { c.vx = -c.vx * e; c.spin += c.vy * Tuning.wallSpin; }
    } else if (c.x > Layout.boundRight - r) {
      c.x = Layout.boundRight - r;
      if (c.vx > 0) { c.vx = -c.vx * e; c.spin -= c.vy * Tuning.wallSpin; }
    }
    if (c.y < Layout.boundTop + r) {
      c.y = Layout.boundTop + r;
      if (c.vy < 0) c.vy = -c.vy * e;
    } else if (c.y > Layout.boundBottom - r) {
      c.y = Layout.boundBottom - r;
      if (c.vy > 0) c.vy = -c.vy * e;
    }
  }

  function landIfNeeded(model, i) {
    const c = model.chips[i];
    const row = model.rows[c.row];
    if (row.landed) return [];
    const floor = Layout.boundBottom - Layout.collisionRadius - 0.75;
    if (c.y < floor) return [];
    row.landed = true;
    model.landHaptics += 1;
    return ["haptic:land"];
  }

  function sleepIfSettled(model, i, supported, gravityX) {
    const c = model.chips[i];
    if (Math.abs(gravityX) >= Tuning.wakeSide || !supported) { c.asleep = false; return; }
    if (hypot(c.vx, c.vy) < Tuning.sleepSpeed) {
      c.vx = 0; c.vy = 0; c.spin = 0; c.asleep = true;
    } else {
      c.asleep = false;
      if (onFloor(c)) c.vx *= Math.max(0, 1 - 6 * Tuning.substep);
    }
  }

  function parityLines() {
    const model = createModel(Catalog, 0x71C75CA7);
    const lines = [model.traceLine()];
    function run(steps) {
      for (let i = 0; i < steps; i++) {
        model.step(Tuning.substep);
        if ((i + 1) % 6 === 0) lines.push(model.traceLine());
      }
    }
    run(48);
    model.toggle(0); lines.push(model.traceLine());
    run(66);
    model.toggle(2); lines.push(model.traceLine());
    run(108);
    model.setTilt(0.75, -0.15); lines.push(model.traceLine());
    run(96);
    model.setTilt(-0.85, 0.55); lines.push(model.traceLine());
    run(96);
    model.setTilt(0, 0);
    model.restoreAll();
    lines.push(model.traceLine());
    run(192);
    lines.push(model.traceLine());
    return lines;
  }

  const Palette = {
    paper: [0.965, 0.941, 0.894],
    ink: [0.122, 0.133, 0.165],
    card: [1, 0.988, 0.965],
    wax: [0.725, 0.196, 0.165],
    chip: [1, 0.976, 0.941],
    tray: [0.918, 0.878, 0.808],
    rule: [0.55, 0.48, 0.38],
  };

  function flightScale(speed) {
    if (!Number.isFinite(speed) || speed <= 0) return 1;
    return 1 + 0.06 * Math.min(1, speed / 640);
  }

  function grain(count = 42, seed = 0x6A11) {
    const rng = makeRng(BigInt(seed));
    const specks = [];
    for (let i = 0; i < count; i++) specks.push([rng.uniform(0, Layout.cardWidth), rng.uniform(0, Layout.cardHeight)]);
    return specks;
  }

  root.TiltScatter = {
    Layout, Tuning, Palette, Catalog, glyphs, acceleration, tiltFromAttitude, tiltFromFinger,
    createModel, parityLines, flightScale, grain, sin, hex,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
