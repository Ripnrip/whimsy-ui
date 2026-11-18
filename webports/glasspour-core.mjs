// Port of GlassPourCore. Constants match GlassPourTuning.swift and GlassPourGeometry.swift.
// The golden trace matches Tests/GlassPourCoreTests/Fixtures/golden-trace.txt.

export const TUNING = {
  longPress: 0.32,
  stagger: 0.07,
  stiffness: 170,
  dampingRatio: 0.62,
  wobbleStiffness: 260,
  wobbleDamping: 0.16,
  wobbleKick: 2.4,
  wobbleGate: 0.86,
  minScale: 0.42,
  maxScale: 1.08,
  minDrawnScale: 0.2,
  labelFrom: 0.62,
  labelTo: 0.92,
  reducedFade: 0.24,
  neckMinimum: 0.5,
  maxRows: 6,
  maxFrame: 0.1,
  substep: 1 / 240,
  openedAnnouncement: "Menu opened",
  closedAnnouncement: "Menu closed",
};

export const LAYOUT = {
  width: 228,
  dropRadius: 30,
  topInset: 6,
  pillWidth: 196,
  pillHeight: 50,
  rowGap: 14,
  bottomMargin: 18,
  hitSlop: 4,
  gooBlur: 9,
  gooThreshold: 0.5,
  maxNeck: 40,
  breakGap: 11,
  waistThinning: 0.55,
  pageWidth: 390,
  pageHeight: 844,
  get pageOrigin() {
    return { x: (this.pageWidth - this.width) / 2, y: 300 };
  },
  get dropCenter() {
    return { x: this.width / 2, y: this.topInset + this.dropRadius };
  },
  get pitch() {
    return this.pillHeight + this.rowGap;
  },
};

export const DEFAULT_ITEMS = [
  { id: "share", title: "Share", symbol: "square.and.arrow.up", destructive: false },
  { id: "duplicate", title: "Duplicate", symbol: "plus.square.on.square", destructive: false },
  { id: "rename", title: "Rename", symbol: "pencil", destructive: false },
  { id: "delete", title: "Delete", symbol: "trash", destructive: true },
];

function clamp01(x) {
  return Math.min(1, Math.max(0, x));
}

function progress(x, a, b) {
  if (a === b) return x < a ? 0 : 1;
  return clamp01((x - a) / (b - a));
}

function smoothstep(a, b, x) {
  const t = progress(x, a, b);
  return t * t * (3 - 2 * t);
}

function makeSpring(value, stiffness, dampingRatio) {
  return { value, velocity: 0, stiffness: Math.max(stiffness, 0), dampingRatio: Math.max(dampingRatio, 0) };
}

function springStep(spring, target, dt) {
  if (!(dt > 0) || !Number.isFinite(dt) || !Number.isFinite(target)) return;
  let remaining = Math.min(dt, TUNING.maxFrame);
  const damping = 2 * spring.dampingRatio * Math.sqrt(spring.stiffness);
  while (remaining > 1e-12) {
    const h = Math.min(remaining, TUNING.substep);
    const acceleration = spring.stiffness * (target - spring.value) - damping * spring.velocity;
    spring.velocity += acceleration * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
}

function springSnap(spring, target) {
  spring.value = target;
  spring.velocity = 0;
}

function springSettled(spring, target) {
  return Math.abs(spring.value - target) < 1e-3 && Math.abs(spring.velocity) < 1e-2;
}

export function restCenter(index) {
  const first = LAYOUT.dropCenter.y + LAYOUT.dropRadius + LAYOUT.rowGap + LAYOUT.pillHeight / 2;
  return { x: LAYOUT.width / 2, y: first + index * LAYOUT.pitch };
}

export function layoutHeight(count) {
  if (!(count > 0)) return LAYOUT.dropCenter.y + LAYOUT.dropRadius + LAYOUT.bottomMargin;
  return restCenter(count - 1).y + LAYOUT.pillHeight / 2 + LAYOUT.bottomMargin;
}

export function dropBlob(scale) {
  const radius = LAYOUT.dropRadius * scale;
  return { center: { ...LAYOUT.dropCenter }, halfWidth: radius, radius };
}

export function pillBlob(center, scale) {
  return {
    center: { x: center.x, y: center.y },
    halfWidth: (LAYOUT.pillWidth / 2) * scale,
    radius: (LAYOUT.pillHeight / 2) * scale,
  };
}

export function neckWidth(gap) {
  return LAYOUT.maxNeck * (1 - smoothstep(0, LAYOUT.breakGap, gap));
}

export function pinchFor(gap) {
  return 1 - neckWidth(gap) / LAYOUT.maxNeck;
}

export function neckBetween(upper, lower) {
  const gap = lower.top - upper.bottom;
  const width = neckWidth(gap);
  if (width < TUNING.neckMinimum) return null;
  const t = smoothstep(0, LAYOUT.breakGap, gap);
  const top = Math.min(upper.center.y, lower.center.y);
  const bottom = Math.max(upper.center.y, lower.center.y);
  return {
    x: upper.center.x,
    top,
    bottom,
    width,
    waist: width * (1 - LAYOUT.waistThinning * t),
    polygon() {
      const mid = (this.top + this.bottom) / 2;
      return [
        { x: this.x - this.width / 2, y: this.top },
        { x: this.x - this.waist / 2, y: mid },
        { x: this.x - this.width / 2, y: this.bottom },
        { x: this.x + this.width / 2, y: this.bottom },
        { x: this.x + this.waist / 2, y: mid },
        { x: this.x + this.width / 2, y: this.top },
      ];
    },
  };
}

function blobTop(blob) {
  return blob.center.y - blob.radius;
}
function blobBottom(blob) {
  return blob.center.y + blob.radius;
}

export function necksFor(drop, rows) {
  const blobs = [drop, ...rows].map((blob, offset) => ({ blob, offset }));
  blobs.sort((a, b) => (a.blob.center.y - b.blob.center.y) || (a.offset - b.offset));
  const ordered = blobs.map((entry) => entry.blob);
  const necks = [];
  for (let i = 0; i < ordered.length - 1; i += 1) {
    const upper = { ...ordered[i], top: blobTop(ordered[i]), bottom: blobBottom(ordered[i]) };
    const lower = { ...ordered[i + 1], top: blobTop(ordered[i + 1]), bottom: blobBottom(ordered[i + 1]) };
    const neck = neckBetween(upper, lower);
    if (neck) necks.push(neck);
  }
  return necks;
}

function resolveItems(items) {
  const source = !items || items.length === 0 ? DEFAULT_ITEMS : items;
  return source.slice(0, TUNING.maxRows).map((item) => ({
    id: item.id ?? item.title,
    title: item.title,
    symbol: item.symbol,
    destructive: !!item.destructive,
  }));
}

export class GlassPourModel {
  constructor(options = {}) {
    this.items = resolveItems(options.items);
    this.phase = "closed";
    this.time = 0;
    this.phaseTime = 0;
    this.fade = 0;
    this.reduceMotion = !!options.reduceMotion;
    this.travels = this.items.map(() => makeSpring(0, TUNING.stiffness, TUNING.dampingRatio));
    this.wobbles = this.items.map(() => makeSpring(0, TUNING.wobbleStiffness, TUNING.wobbleDamping));
    this.wobbleKicked = this.items.map(() => false);
  }

  get count() {
    return this.items.length;
  }

  get isExpanded() {
    return this.phase === "opening" || this.phase === "open" || this.phase === "closing";
  }

  get dropScale() {
    if (this.phase !== "arming" || this.reduceMotion) return 1;
    const held = TUNING.longPress > 0 ? this.phaseTime / TUNING.longPress : 1;
    return 1 + 0.07 * Math.min(1, Math.max(0, held));
  }

  get usesGoo() {
    if (this.reduceMotion) return false;
    return this.phase === "opening" || this.phase === "closing";
  }

  rowCenter(index) {
    const rest = restCenter(index);
    const seated = this.reduceMotion && (this.phase === "opening" || this.phase === "open" || this.phase === "closing" || this.fade > 0);
    if (seated) return { x: rest.x, y: rest.y };
    const travel = this.travels[index].value;
    return {
      x: rest.x,
      y: LAYOUT.dropCenter.y + (rest.y - LAYOUT.dropCenter.y) * travel,
    };
  }

  pinchAbove(index, center, scale, visible) {
    if (!visible) return 0;
    if (this.reduceMotion) return 1;
    const top = center.y - (LAYOUT.pillHeight / 2) * scale;
    let aboveBottom = LAYOUT.dropCenter.y + LAYOUT.dropRadius * this.dropScale;
    for (let other = 0; other < this.count; other += 1) {
      if (other === index) continue;
      const candidate = this.rowCenter(other);
      if (!(candidate.y < center.y)) continue;
      const otherVisible = this.travels[other].value > 0.015 || Math.abs(this.travels[other].velocity) > 0.02;
      if (!otherVisible) continue;
      const otherScale = TUNING.minScale + (1 - TUNING.minScale) * this.travels[other].value;
      const clamped = Math.min(TUNING.maxScale, Math.max(TUNING.minDrawnScale, otherScale));
      aboveBottom = Math.max(aboveBottom, candidate.y + (LAYOUT.pillHeight / 2) * clamped);
    }
    return pinchFor(top - aboveBottom);
  }

  row(index) {
    const travel = this.travels[index].value;
    const center = this.rowCenter(index);
    let scale = 1;
    if (!this.reduceMotion) {
      const raw = TUNING.minScale + (1 - TUNING.minScale) * travel;
      scale = Math.min(TUNING.maxScale, Math.max(TUNING.minDrawnScale, raw));
    }
    const opacity = this.reduceMotion ? this.fade : smoothstep(TUNING.labelFrom, TUNING.labelTo, travel);
    const visible = this.reduceMotion ? this.fade > 0.02 : (travel > 0.015 || Math.abs(this.travels[index].velocity) > 0.02);
    const interactive = opacity > 0.5 && (this.phase === "opening" || this.phase === "open");
    return {
      index,
      travel,
      center,
      scale,
      opacity,
      wobble: this.reduceMotion ? 0 : this.wobbles[index].value,
      pinch: this.pinchAbove(index, center, scale, visible),
      destructive: this.items[index].destructive,
      isVisible: visible,
      isInteractive: interactive,
    };
  }

  get rows() {
    return this.items.map((_, index) => this.row(index));
  }

  get necks() {
    if (this.reduceMotion) return [];
    const visible = this.rows.filter((row) => row.isVisible).map((row) => pillBlob(row.center, row.scale));
    if (visible.length === 0) return [];
    return necksFor(dropBlob(this.dropScale), visible);
  }

  beginOpening() {
    const alreadyOut = this.travels.some((spring) => spring.value > 0.2);
    this.phase = "opening";
    this.phaseTime = alreadyOut ? TUNING.stagger * Math.max(this.count - 1, 0) : 0;
    if (this.reduceMotion) {
      for (let index = 0; index < this.count; index += 1) {
        springSnap(this.travels[index], 1);
        springSnap(this.wobbles[index], 0);
        this.wobbleKicked[index] = false;
      }
    } else {
      for (let index = 0; index < this.count; index += 1) this.wobbleKicked[index] = false;
    }
  }

  beginClosing() {
    this.phase = "closing";
    this.phaseTime = 0;
  }

  pressDrop() {
    if (this.phase === "closed") {
      this.phase = "arming";
      this.phaseTime = 0;
      return [];
    }
    if (this.phase === "arming" || this.phase === "closing") return [];
    this.beginClosing();
    return ["closing"];
  }

  releaseDrop() {
    if (this.phase !== "arming") return [];
    this.phase = "closed";
    this.phaseTime = 0;
    return ["pulsed"];
  }

  activateDrop() {
    if (this.phase === "closed" || this.phase === "arming" || this.phase === "closing") {
      this.beginOpening();
      return ["opening"];
    }
    this.beginClosing();
    return ["closing"];
  }

  pressOutside() {
    if (this.phase !== "opening" && this.phase !== "open") return [];
    this.beginClosing();
    return ["closing"];
  }

  selectRow(index) {
    if (index < 0 || index >= this.count) return [];
    if (this.phase !== "opening" && this.phase !== "open") return [];
    this.beginClosing();
    return [`selected ${index}`, "closing", "haptic"];
  }

  travelTargets() {
    if (this.reduceMotion) return this.travels.map((spring) => spring.value);
    if (this.phase === "closed" || this.phase === "arming") return this.items.map(() => 0);
    if (this.phase === "opening" || this.phase === "open") {
      return this.items.map((_, index) => (this.phase === "open" || this.phaseTime >= index * TUNING.stagger ? 1 : 0));
    }
    const last = Math.max(this.count - 1, 0);
    return this.items.map((_, index) => {
      const delay = (last - index) * TUNING.stagger;
      const home = this.travels[index].value < 0.02 && Math.abs(this.travels[index].velocity) < 0.05;
      return this.phaseTime >= delay || home ? 0 : 1;
    });
  }

  kickWobbles() {
    if (this.phase !== "opening" && this.phase !== "open") return;
    for (let index = 0; index < this.count; index += 1) {
      if (!this.items[index].destructive || this.wobbleKicked[index]) continue;
      if (this.travels[index].value >= TUNING.wobbleGate) {
        this.wobbles[index].velocity += TUNING.wobbleKick;
        this.wobbleKicked[index] = true;
      }
    }
  }

  finishClosed() {
    this.phase = "closed";
    this.phaseTime = 0;
    this.fade = 0;
    for (let index = 0; index < this.count; index += 1) {
      springSnap(this.travels[index], 0);
      springSnap(this.wobbles[index], 0);
      this.wobbleKicked[index] = false;
    }
  }

  settleMotion() {
    if (this.phase === "opening") {
      const released = this.items.every((_, index) => this.phaseTime >= index * TUNING.stagger);
      const seated = this.travels.every((spring) => springSettled(spring, 1));
      if (released && seated) {
        this.phase = "open";
        this.phaseTime = 0;
        return ["opened", "haptic"];
      }
    } else if (this.phase === "closing") {
      const last = Math.max(this.count - 1, 0);
      const released = this.items.every((_, index) => {
        const delay = (last - index) * TUNING.stagger;
        const home = this.travels[index].value < 0.02 && Math.abs(this.travels[index].velocity) < 0.05;
        return this.phaseTime >= delay || home;
      });
      const seated = this.travels.every((spring) => springSettled(spring, 0));
      if (released && seated) {
        this.finishClosed();
        return ["closed"];
      }
    }
    return [];
  }

  settleFade(h) {
    const rate = TUNING.reducedFade > 0 ? h / TUNING.reducedFade : 1;
    if (this.phase === "opening") {
      this.fade = Math.min(1, this.fade + rate);
      if (this.fade >= 1) {
        this.fade = 1;
        this.phase = "open";
        this.phaseTime = 0;
        return ["opened", "haptic"];
      }
    } else if (this.phase === "closing") {
      this.fade = Math.max(0, this.fade - rate);
      if (this.fade <= 0) {
        this.fade = 0;
        this.finishClosed();
        return ["closed"];
      }
    }
    return [];
  }

  step(dt) {
    if (!(dt > 0) || !Number.isFinite(dt)) return [];
    const h = Math.min(dt, TUNING.maxFrame);
    this.time += h;
    this.phaseTime += h;
    const events = [];
    if (this.phase === "arming" && this.phaseTime >= TUNING.longPress) {
      this.beginOpening();
      events.push("opening");
    }
    const targets = this.travelTargets();
    for (let index = 0; index < this.count; index += 1) springStep(this.travels[index], targets[index], h);
    if (!this.reduceMotion) {
      this.kickWobbles();
      for (let index = 0; index < this.count; index += 1) springStep(this.wobbles[index], 0, h);
      events.push(...this.settleMotion());
    } else {
      events.push(...this.settleFade(h));
    }
    return events;
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

function describeLine(tag, index, model) {
  const fields = [
    tag, String(index), model.phase,
    fmt(model.time), fmt(model.phaseTime), fmt(model.fade), fmt(model.dropScale),
  ];
  for (const row of model.rows) {
    fields.push(fmt(row.travel), fmt(row.center.y), fmt(row.scale), fmt(row.opacity), fmt(row.wobble), fmt(row.pinch));
  }
  const necks = model.necks.slice().sort((a, b) => (a.top - b.top) || (a.x - b.x));
  for (let slot = 0; slot < 4; slot += 1) {
    if (slot < necks.length) {
      fields.push(fmt(necks[slot].width), fmt(necks[slot].waist));
    } else {
      fields.push(fmt(0), fmt(0));
    }
  }
  return fields.join(" ");
}

function session(reduceMotion, tag) {
  const model = new GlassPourModel({ reduceMotion });
  const lines = [];
  let index = 0;
  const snap = () => {
    lines.push(describeLine(tag, index, model));
    index += 1;
  };
  const note = (events) => {
    if (!events.length) return;
    lines.push(`${tag} e ${events.join(" ")}`);
  };
  const frames = (count) => {
    for (let i = 0; i < count; i += 1) {
      note(model.step(1 / 60));
      snap();
    }
  };
  snap();
  frames(3);
  note(model.pressDrop());
  snap();
  frames(100);
  note(model.pressOutside());
  snap();
  frames(90);
  note(model.pressDrop());
  snap();
  frames(8);
  note(model.releaseDrop());
  snap();
  frames(3);
  note(model.activateDrop());
  snap();
  frames(90);
  note(model.selectRow(3));
  snap();
  frames(90);
  return lines;
}

export function goldenTrace() {
  const lines = [
    "v1",
    `dt ${fmt(1 / 60)}`,
    `longPress ${fmt(TUNING.longPress)}`,
    `stagger ${fmt(TUNING.stagger)}`,
    `spring ${fmt(TUNING.stiffness)} ${fmt(TUNING.dampingRatio)}`,
    `wobble ${fmt(TUNING.wobbleStiffness)} ${fmt(TUNING.wobbleDamping)} ${fmt(TUNING.wobbleKick)} ${fmt(TUNING.wobbleGate)}`,
    `neck ${fmt(LAYOUT.maxNeck)} ${fmt(LAYOUT.breakGap)} ${fmt(LAYOUT.waistThinning)} ${fmt(TUNING.neckMinimum)}`,
    `goo ${fmt(LAYOUT.gooBlur)} ${fmt(LAYOUT.gooThreshold)}`,
    `layout ${fmt(LAYOUT.width)} ${fmt(LAYOUT.dropRadius)} ${fmt(LAYOUT.pillWidth)} ${fmt(LAYOUT.pillHeight)} ${fmt(LAYOUT.rowGap)}`,
    `page ${fmt(LAYOUT.pageWidth)} ${fmt(LAYOUT.pageHeight)} ${fmt(LAYOUT.pageOrigin.x)} ${fmt(LAYOUT.pageOrigin.y)}`,
    `items ${DEFAULT_ITEMS.map((item) => item.title).join(" | ")}`,
    `copy ${TUNING.openedAnnouncement} | ${TUNING.closedAnnouncement}`,
    ...session(false, "f"),
    ...session(true, "r"),
  ];
  return `${lines.join("\n")}\n`;
}

// Preview clock. Times are multiples of 1/60 so the script lands on a frame.
export const DEMO_PRESS = 21 / 60;
export const DEMO_DISMISS = 132 / 60;
export const DEMO_PRESS_AGAIN = 213 / 60;
export const DEMO_DURATION = 336 / 60;

export function demoAt(t, { reduceMotion = false } = {}) {
  const model = new GlassPourModel({ reduceMotion });
  const dt = 1 / 60;
  const marks = [
    { t: DEMO_PRESS, run: () => model.pressDrop() },
    { t: DEMO_DISMISS, run: () => model.pressOutside() },
    { t: DEMO_PRESS_AGAIN, run: () => model.pressDrop() },
  ];
  let next = 0;
  let elapsed = 0;
  const duration = Math.max(0, t);
  while (elapsed < duration - 1e-12) {
    const h = Math.min(dt, duration - elapsed);
    const t1 = elapsed + h;
    while (next < marks.length && marks[next].t <= t1 + 1e-9) {
      marks[next].run();
      next += 1;
    }
    model.step(h);
    elapsed = t1;
  }
  return model;
}

export const DEMO_STILLS = [
  { name: "The drop", t: 0.1 },
  { name: "Arming", t: 0.5 },
  { name: "Necks", t: 0.9 },
  { name: "Pouring", t: 1.2 },
  { name: "Delete wobbles", t: 1.55 },
  { name: "Crisp glass", t: 2.05 },
  { name: "Sucked back", t: 2.7 },
  { name: "Reduce Motion", t: 1.3, reduceMotion: true },
];
