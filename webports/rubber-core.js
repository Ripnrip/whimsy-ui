// Port of RubberBandCore. Constants and the step loop match the Swift model.
// Visible offset = offset * 0.55 / (1 + abs(offset) / 300).
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.RubberBand = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const L = {
    count: 5,
    width: 390,
    height: 700,
    cardWidth: 108,
    cardHeight: 158,
    cornerRadius: 16,
    arcRadius: 292,
    halfSpan: 0.42,
    bottomMargin: 52,
    hoverLift: 20,
    commitRise: 56,
    flickSpeed: 900,
    flickMin: 22,
    grabSlop: 16,
    stickiness: 14,
    dismissRise: 48,
    dismissFlick: 800,
    presentedScale: 1.62,
    hitPadX: 16,
    hitPadY: 36,
  };
  L.stage = { x: L.width / 2, y: 246 };
  L.angle = function (index) {
    const i = Math.min(Math.max(index, 0), L.count - 1);
    return -Math.PI / 2 + ((i - 2) / 2) * L.halfSpan;
  };
  L.origin = function () {
    const a = L.angle(0);
    return { x: L.width / 2, y: (L.height - L.bottomMargin) - L.cardHeight / 2 - Math.sin(a) * L.arcRadius };
  };
  L.restCenter = function (index) {
    const a = L.angle(index);
    const o = L.origin();
    return { x: o.x + Math.cos(a) * L.arcRadius, y: o.y + Math.sin(a) * L.arcRadius };
  };
  L.restRotation = function (index) { return L.angle(index) + Math.PI / 2; };
  L.restTop = function (index) { return L.restCenter(index).y - L.cardHeight / 2; };
  L.handContains = function (p) {
    if (!isFinite(p.x) || !isFinite(p.y)) return false;
    let minX = Infinity, maxX = -Infinity, minY = Infinity;
    for (let i = 0; i < L.count; i++) {
      const c = L.restCenter(i);
      minX = Math.min(minX, c.x);
      maxX = Math.max(maxX, c.x);
      minY = Math.min(minY, L.restTop(i));
    }
    minX -= L.cardWidth / 2 + L.hitPadX;
    maxX += L.cardWidth / 2 + L.hitPadX;
    minY -= L.hoverLift + L.hitPadY;
    return p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= L.height;
  };
  L.nearestIndex = function (point, current) {
    if (!L.handContains(point)) return null;
    let best = 0;
    let bestD = Math.abs(L.restCenter(0).x - point.x);
    for (let i = 1; i < L.count; i++) {
      const d = Math.abs(L.restCenter(i).x - point.x);
      if (d < bestD - 1e-9) { best = i; bestD = d; }
    }
    if (current != null) {
      const c = Math.min(Math.max(current, 0), L.count - 1);
      const dCur = Math.abs(L.restCenter(c).x - point.x);
      if (dCur - bestD <= L.stickiness) return c;
    }
    return best;
  };
  L.presentedContains = function (point) {
    const hw = L.cardWidth / 2 * L.presentedScale + 8;
    const hh = L.cardHeight / 2 * L.presentedScale + 8;
    return Math.abs(point.x - L.stage.x) <= hw && Math.abs(point.y - L.stage.y) <= hh;
  };

  const R = {
    scale: 0.55,
    length: 300,
    resist: function (offset) {
      if (!isFinite(offset)) return 0;
      return offset * 0.55 / (1 + Math.abs(offset) / 300);
    },
    slope: function (offset) {
      if (!isFinite(offset)) return 0;
      const d = 1 + Math.abs(offset) / 300;
      return 0.55 / (d * d);
    },
    decide: function (pullUp, upwardVelocity) {
      const up = isFinite(pullUp) ? pullUp : 0;
      if (R.resist(up) >= L.commitRise) return "commitDrag";
      if (isFinite(upwardVelocity) && upwardVelocity >= L.flickSpeed && up >= L.flickMin) return "commitFlick";
      return "springBack";
    },
    decideDismiss: function (pullDown, downwardVelocity) {
      const down = isFinite(pullDown) ? pullDown : 0;
      if (R.resist(down) >= L.dismissRise) return "commitDrag";
      if (isFinite(downwardVelocity) && downwardVelocity >= L.dismissFlick && down >= L.flickMin) return "commitFlick";
      return "springBack";
    },
  };
  R.asymptote = R.scale * R.length;

  function Velocity() { this.samples = []; }
  Velocity.window = 0.1;
  Velocity.stale = 0.06;
  Velocity.prototype.reset = function () { this.samples = []; };
  Velocity.prototype.add = function (point, t) {
    if (!isFinite(point.x) || !isFinite(point.y) || !isFinite(t)) return;
    const last = this.samples[this.samples.length - 1];
    if (last && t < last.t) return;
    this.samples.push({ t: t, x: point.x, y: point.y });
    this.samples = this.samples.filter(function (s) { return t - s.t <= Velocity.window * 3; });
  };
  Velocity.prototype.velocity = function (now) {
    const last = this.samples[this.samples.length - 1];
    if (!last || !isFinite(now) || now - last.t > Velocity.stale) return { x: 0, y: 0 };
    const recent = this.samples.filter(function (s) { return last.t - s.t <= Velocity.window; });
    const first = recent[0];
    if (!first || last.t - first.t <= 0.001) return { x: 0, y: 0 };
    const dt = last.t - first.t;
    return { x: (last.x - first.x) / dt, y: (first.y - last.y) / dt };
  };

  function Spring(value, velocity, stiffness, dampingRatio) {
    this.value = value || 0;
    this.velocity = velocity || 0;
    this.stiffness = Math.max(stiffness, 0);
    this.dampingRatio = Math.max(dampingRatio, 0);
  }
  Spring.maxSubstep = 1 / 240;
  Spring.maxFrame = 0.1;
  Spring.prototype.damping = function () { return 2 * this.dampingRatio * Math.sqrt(this.stiffness); };
  Spring.prototype.step = function (target, dt) {
    if (!(dt > 0) || !isFinite(dt) || !isFinite(target)) return;
    let remaining = Math.min(dt, Spring.maxFrame);
    while (remaining > 1e-12) {
      const h = Math.min(remaining, Spring.maxSubstep);
      const acc = this.stiffness * (target - this.value) - this.damping() * this.velocity;
      this.velocity += acc * h;
      this.value += this.velocity * h;
      remaining -= h;
    }
  };
  Spring.prototype.snap = function (target) { this.value = target; this.velocity = 0; };
  Spring.prototype.isSettled = function (target, tol) {
    const tolerance = tol == null ? 1e-3 : tol;
    return Math.abs(this.value - target) < tolerance && Math.abs(this.velocity) < tolerance * 10;
  };

  function clamp01(x) { return Math.min(Math.max(x, 0), 1); }
  function smoothstep(a, b, x) {
    let t;
    if (a === b) t = x < a ? 0 : 1;
    else t = clamp01((x - a) / (b - a));
    return t * t * (3 - 2 * t);
  }
  function len(a, b) {
    const dx = a.x - b.x, dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  const rgb = function (r, g, b) { return { r: r, g: g, b: b }; };
  const E = function (cx, cy, rx, ry, color, alpha) {
    return { kind: "ellipse", cx: cx, cy: cy, rx: rx, ry: ry, rotation: 0, color: color, alpha: alpha };
  };
  const Rect = function (cx, cy, width, height, corner, color, alpha) {
    return { kind: "rect", cx: cx, cy: cy, width: width, height: height, rotation: corner, color: color, alpha: alpha };
  };
  const Cap = function (cx, cy, width, height, rotation, color, alpha) {
    return { kind: "capsule", cx: cx, cy: cy, width: width, height: height, rotation: rotation, color: color, alpha: alpha };
  };

  const cards = [
    { index: 0, title: "Lumen", kicker: "FIELD NOTES", detail: "A band of colour that only shows after the lamps along the ridge go out.", paper: rgb(0.09, 0.10, 0.18), ink: rgb(0.93, 0.95, 0.98), marks: [
      E(0.74, 0.16, 0.075, 0.075, rgb(0.96, 0.93, 0.84), 1),
      E(0.77, 0.15, 0.060, 0.060, rgb(0.09, 0.10, 0.18), 1),
      Cap(0.46, 0.30, 0.92, 0.09, -0.22, rgb(0.28, 0.82, 0.74), 0.90),
      Cap(0.50, 0.40, 0.78, 0.075, 0.10, rgb(0.93, 0.42, 0.62), 0.88),
      Cap(0.48, 0.50, 0.64, 0.055, -0.06, rgb(0.98, 0.80, 0.42), 0.85),
    ]},
    { index: 1, title: "Terrace", kicker: "AFTERNOON", detail: "Stone steps that hold the last of the heat, and a sun that has not quite left.", paper: rgb(0.95, 0.86, 0.73), ink: rgb(0.29, 0.17, 0.11), marks: [
      E(0.74, 0.18, 0.09, 0.09, rgb(0.93, 0.52, 0.20), 1),
      Rect(0.40, 0.32, 0.42, 0.075, 0.035, rgb(0.55, 0.34, 0.24), 1),
      Rect(0.46, 0.42, 0.58, 0.075, 0.035, rgb(0.78, 0.50, 0.32), 1),
      Rect(0.52, 0.52, 0.74, 0.075, 0.035, rgb(0.86, 0.62, 0.40), 1),
    ]},
    { index: 2, title: "Citrus", kicker: "MARKET", detail: "Three fruits, one leaf, and a paper bag that will not quite close.", paper: rgb(0.98, 0.96, 0.90), ink: rgb(0.55, 0.24, 0.09), marks: [
      E(0.38, 0.40, 0.16, 0.16, rgb(0.93, 0.48, 0.12), 1),
      E(0.64, 0.42, 0.14, 0.14, rgb(0.55, 0.70, 0.24), 1),
      E(0.52, 0.24, 0.11, 0.11, rgb(0.92, 0.40, 0.42), 1),
      Cap(0.70, 0.16, 0.16, 0.055, -0.7, rgb(0.28, 0.52, 0.26), 1),
      Cap(0.66, 0.20, 0.04, 0.02, 0.4, rgb(0.36, 0.28, 0.14), 1),
    ]},
    { index: 3, title: "Night Train", kicker: "PLATFORM 4", detail: "Windows ticking past in the dark, each one a room with the lamp still on.", paper: rgb(0.07, 0.08, 0.13), ink: rgb(0.96, 0.91, 0.80), marks: [
      Rect(0.28, 0.34, 0.16, 0.22, 0.04, rgb(0.98, 0.78, 0.42), 0.95),
      Rect(0.50, 0.34, 0.16, 0.22, 0.04, rgb(0.98, 0.62, 0.38), 0.95),
      Rect(0.72, 0.34, 0.16, 0.22, 0.04, rgb(0.86, 0.78, 0.55), 0.92),
      Rect(0.28, 0.34, 0.10, 0.16, 0.02, rgb(0.16, 0.18, 0.26), 0.28),
      Cap(0.50, 0.52, 0.84, 0.018, 0.04, rgb(0.75, 0.72, 0.62), 0.85),
      E(0.18, 0.18, 0.035, 0.035, rgb(0.98, 0.86, 0.55), 1),
    ]},
    { index: 4, title: "Botanic", kicker: "GLASSHOUSE", detail: "Leaves made of ellipses, the way a stencil remembers a plant it once held.", paper: rgb(0.89, 0.93, 0.86), ink: rgb(0.13, 0.32, 0.22), marks: [
      Rect(0.50, 0.48, 0.028, 0.30, 0.02, rgb(0.24, 0.42, 0.28), 1),
      Cap(0.36, 0.34, 0.28, 0.09, -0.9, rgb(0.36, 0.62, 0.38), 1),
      Cap(0.66, 0.30, 0.30, 0.10, 0.7, rgb(0.22, 0.50, 0.36), 1),
      Cap(0.34, 0.48, 0.26, 0.08, -0.45, rgb(0.48, 0.70, 0.40), 1),
      E(0.62, 0.50, 0.045, 0.045, rgb(0.85, 0.42, 0.38), 1),
    ]},
  ];

  function Model(reduceMotion) {
    this.phase = "resting";
    this.focusIndex = null;
    this.activeIndex = null;
    this.pullUp = 0;
    this.pullRight = 0;
    this.isArmed = false;
    this.lastRelease = "springBack";
    this.reduceMotion = !!reduceMotion;
    this.time = 0;
    this.phaseTime = 0;
    this.liftEvents = 0;
    this.grabs = 0;
    this.commits = 0;
    this.presentations = 0;
    this.restores = 0;
    this.lifts = [];
    for (let i = 0; i < L.count; i++) this.lifts.push(new Spring(0, 0, 520, 0.72));
    this.flightX = new Spring();
    this.flightY = new Spring();
    this.flightRot = new Spring();
    this.flightFlip = new Spring();
    this.flightScale = new Spring();
    this.flightTarget = { x: 0, y: 0 };
    this.flightTargetRot = 0;
    this.flightTargetFlip = 0;
    this.flightTargetScale = 1;
    this.announceArrival = false;
    this.anchor = { x: 0, y: 0 };
    this.lastPoint = { x: 0, y: 0 };
    this.dragFinger = { x: 0, y: 0 };
    this.dragBaseLift = 0;
    this.dismissFinger = { x: 0, y: 0 };
    this.tracker = new Velocity();
    this.reportedGrab = false;
  }
  Model.maxStep = 0.25;
  Model.flightCap = 2.4;
  Model.presentStiffness = 190;
  Model.presentDamping = 0.76;
  Model.returnStiffness = 260;
  Model.returnDamping = 0.86;
  Model.flipStiffness = 120;
  Model.flipDamping = 1;

  Model.prototype.flying = function () {
    return this.phase === "presenting" || this.phase === "presented" || this.phase === "dismissing" || this.phase === "returning";
  };
  Model.prototype.openness = function () {
    if (this.phase === "presenting" || this.phase === "returning" || this.phase === "dismissing") return clamp01(this.flightFlip.value);
    if (this.phase === "presented") return 1;
    return 0;
  };
  Model.prototype.liftTarget = function (index) {
    if (this.phase === "browsing" && this.focusIndex === index) return L.hoverLift;
    return 0;
  };
  Model.prototype.pose = function (index) {
    const i = Math.min(Math.max(index, 0), L.count - 1);
    const rest = L.restCenter(i);
    const restRot = L.restRotation(i);
    const dim = this.activeIndex === i ? 1 : (1 - 0.4 * this.openness());
    if (this.activeIndex === i && this.phase === "dragging") {
      const extra = Math.max(0, R.resist(this.pullUp));
      const up = Math.max(0, this.dragBaseLift + R.resist(this.pullUp));
      const side = R.resist(this.pullRight);
      const straighten = smoothstep(0, L.commitRise, extra);
      return { index: i, center: { x: rest.x + side, y: rest.y - up }, rotation: restRot * (1 - straighten), lift: up, scale: 1.04 + 0.06 * straighten, flip: 0, opacity: 1, z: 20 };
    }
    if (this.activeIndex === i && this.phase === "dismissing") {
      const dx = R.resist(this.pullRight);
      const dy = R.resist(this.pullUp);
      const center = { x: L.stage.x + dx, y: L.stage.y - dy };
      return { index: i, center: center, rotation: 0, lift: rest.y - center.y, scale: L.presentedScale, flip: 1, opacity: 1, z: 20 };
    }
    if (this.activeIndex === i && this.flying()) {
      const center = { x: this.flightX.value, y: this.flightY.value };
      return { index: i, center: center, rotation: this.flightRot.value, lift: rest.y - center.y, scale: Math.max(0.4, this.flightScale.value), flip: clamp01(this.flightFlip.value), opacity: 1, z: 20 };
    }
    const lift = Math.max(0, this.lifts[i].value);
    const raised = clamp01(lift / L.hoverLift);
    return { index: i, center: { x: rest.x, y: rest.y - lift }, rotation: restRot, lift: lift, scale: 1 + 0.04 * raised, flip: 0, opacity: dim, z: i };
  };
  Model.prototype.retarget = function (point) {
    const next = L.nearestIndex(point, this.focusIndex);
    if (next === this.focusIndex) {
      if (this.reduceMotion) this.snapLifts();
      return [];
    }
    this.focusIndex = next;
    if (this.reduceMotion) this.snapLifts();
    if (next == null) return [];
    this.liftEvents += 1;
    return [{ kind: "lifted", index: next }];
  };
  Model.prototype.beginDrag = function (index) {
    this.activeIndex = index;
    this.dragFinger = { x: this.lastPoint.x, y: this.lastPoint.y };
    this.dragBaseLift = this.lifts[index].value;
    this.pullUp = 0;
    this.pullRight = 0;
    this.isArmed = false;
    this.reportedGrab = false;
    this.phase = "dragging";
    this.phaseTime = 0;
    this.grabs += 1;
  };
  Model.prototype.applyDrag = function (point) {
    this.pullRight = point.x - this.dragFinger.x;
    this.pullUp = this.dragFinger.y - point.y;
    this.lastPoint = { x: point.x, y: point.y };
    if (this.activeIndex == null) return [];
    const i = this.activeIndex;
    const events = [];
    if (!this.reportedGrab) {
      this.reportedGrab = true;
      events.push({ kind: "grabbed", index: i });
    }
    const crossed = R.resist(this.pullUp) >= L.commitRise;
    if (crossed && !this.isArmed) {
      this.isArmed = true;
      events.push({ kind: "armed", index: i });
    } else if (!crossed) this.isArmed = false;
    return events;
  };
  Model.prototype.beginDismiss = function (finger) {
    this.phase = "dismissing";
    this.phaseTime = 0;
    this.dismissFinger = { x: finger.x, y: finger.y };
    this.pullUp = 0;
    this.pullRight = 0;
    this.flightFlip.snap(1);
    this.flightX.snap(L.stage.x);
    this.flightY.snap(L.stage.y);
  };
  Model.prototype.applyDismiss = function (point) {
    this.pullRight = point.x - this.dismissFinger.x;
    this.pullUp = this.dismissFinger.y - point.y;
    this.lastPoint = { x: point.x, y: point.y };
    return [];
  };
  Model.prototype.visualVelocity = function (finger) {
    return { x: finger.x * R.slope(this.pullRight), y: -finger.y * R.slope(this.pullUp) };
  };
  Model.prototype.currentFlightPose = function () {
    if (this.activeIndex != null) return this.pose(this.activeIndex);
    return { center: { x: 0, y: 0 }, rotation: 0, scale: 1, flip: 0 };
  };
  Model.prototype.aimFlight = function (presenting) {
    if (presenting) {
      this.flightTarget = { x: L.stage.x, y: L.stage.y };
      this.flightTargetRot = 0;
      this.flightTargetFlip = 1;
      this.flightTargetScale = L.presentedScale;
    } else if (this.activeIndex != null) {
      const i = this.activeIndex;
      const c = L.restCenter(i);
      this.flightTarget = { x: c.x, y: c.y };
      this.flightTargetRot = L.restRotation(i);
      this.flightTargetFlip = 0;
      this.flightTargetScale = 1;
    }
  };
  Model.prototype.beginFlight = function (presenting, velocity, announce) {
    if (announce == null) announce = true;
    const current = this.currentFlightPose();
    const k = presenting ? Model.presentStiffness : Model.returnStiffness;
    const z = presenting ? Model.presentDamping : Model.returnDamping;
    this.flightX = new Spring(current.center.x, velocity.x, k, z);
    this.flightY = new Spring(current.center.y, velocity.y, k, z);
    this.flightRot = new Spring(current.rotation, 0, Model.returnStiffness, Model.returnDamping);
    this.flightFlip = new Spring(current.flip, 0, Model.flipStiffness, Model.flipDamping);
    this.flightScale = new Spring(current.scale, 0, k, z);
    this.aimFlight(presenting);
    if (this.activeIndex != null) this.lifts[this.activeIndex].snap(0);
    this.phase = presenting ? "presenting" : "returning";
    this.phaseTime = 0;
    this.announceArrival = presenting && announce;
    this.reportedGrab = false;
    if (this.reduceMotion) {
      if (presenting) return this.snapPresented(announce);
      return this.snapHome();
    }
    return [];
  };
  Model.prototype.snapLifts = function () {
    for (let i = 0; i < L.count; i++) this.lifts[i].snap(this.liftTarget(i));
  };
  Model.prototype.snapPresented = function (announce) {
    this.flightX.snap(L.stage.x);
    this.flightY.snap(L.stage.y);
    this.flightRot.snap(0);
    this.flightFlip.snap(1);
    this.flightScale.snap(L.presentedScale);
    this.phase = "presented";
    this.phaseTime = 0;
    this.pullUp = 0;
    this.pullRight = 0;
    this.focusIndex = null;
    this.announceArrival = false;
    this.reportedGrab = false;
    if (!announce || this.activeIndex == null) return [];
    this.presentations += 1;
    return [{ kind: "presented", index: this.activeIndex }];
  };
  Model.prototype.snapHome = function () {
    const i = this.activeIndex;
    if (i != null) this.lifts[i].snap(0);
    this.flightFlip.snap(0);
    this.phase = "resting";
    this.phaseTime = 0;
    this.activeIndex = null;
    this.focusIndex = null;
    this.pullUp = 0;
    this.pullRight = 0;
    this.isArmed = false;
    this.announceArrival = false;
    this.reportedGrab = false;
    if (i == null) return [];
    this.restores += 1;
    return [{ kind: "restored", index: i }];
  };
  Model.prototype.pointerDown = function (point, timestamp) {
    if (!isFinite(point.x) || !isFinite(point.y)) return [];
    const t = timestamp == null ? this.time : timestamp;
    if (this.phase === "resting" || this.phase === "browsing") {
      this.anchor = { x: point.x, y: point.y };
      this.lastPoint = { x: point.x, y: point.y };
      this.pullUp = 0;
      this.pullRight = 0;
      this.isArmed = false;
      this.tracker.reset();
      this.tracker.add(point, t);
      this.phase = "browsing";
      this.phaseTime = 0;
      return this.retarget(point);
    }
    if (this.phase === "presented") {
      this.anchor = { x: point.x, y: point.y };
      this.lastPoint = { x: point.x, y: point.y };
      this.pullUp = 0;
      this.pullRight = 0;
      this.tracker.reset();
      this.tracker.add(point, t);
      return [];
    }
    return [];
  };
  Model.prototype.pointerMoved = function (point, timestamp) {
    if (!isFinite(point.x) || !isFinite(point.y)) return [];
    const t = timestamp == null ? this.time : timestamp;
    if (this.phase === "browsing") {
      this.tracker.add(point, t);
      const up = this.anchor.y - point.y;
      const right = point.x - this.anchor.x;
      if (this.focusIndex != null && up > L.grabSlop && up > Math.abs(right)) {
        this.beginDrag(this.focusIndex);
        return this.applyDrag(point);
      }
      const events = this.retarget(point);
      this.lastPoint = { x: point.x, y: point.y };
      return events;
    }
    if (this.phase === "dragging") {
      this.tracker.add(point, t);
      return this.applyDrag(point);
    }
    if (this.phase === "presented") {
      const down = point.y - this.anchor.y;
      const right = point.x - this.anchor.x;
      if (down > L.grabSlop && down > Math.abs(right)) {
        this.beginDismiss(this.lastPoint);
        this.tracker.add(point, t);
        return this.applyDismiss(point);
      }
      this.lastPoint = { x: point.x, y: point.y };
      return [];
    }
    if (this.phase === "dismissing") {
      this.tracker.add(point, t);
      return this.applyDismiss(point);
    }
    return [];
  };
  Model.prototype.pointerUp = function (point, timestamp) {
    const p = (isFinite(point.x) && isFinite(point.y)) ? point : this.lastPoint;
    const t = timestamp == null ? this.time : timestamp;
    this.tracker.add(p, t);
    if (this.phase === "browsing") {
      this.focusIndex = null;
      this.phase = "resting";
      this.phaseTime = 0;
      if (this.reduceMotion) this.snapLifts();
      return [];
    }
    if (this.phase === "dragging") {
      if (this.activeIndex == null) return [];
      const i = this.activeIndex;
      const v = this.tracker.velocity(t);
      const release = R.decide(this.pullUp, v.y);
      this.lastRelease = release;
      this.isArmed = false;
      if (release === "commitDrag" || release === "commitFlick") {
        this.commits += 1;
        return [{ kind: "committed", index: i }].concat(this.beginFlight(true, this.visualVelocity(v), true));
      }
      return this.beginFlight(false, this.visualVelocity(v), true);
    }
    if (this.phase === "presented") {
      if (len(p, this.anchor) < 12 && !L.presentedContains(p) && !L.presentedContains(this.anchor)) return this.dismiss();
      return [];
    }
    if (this.phase === "dismissing") {
      if (this.activeIndex == null) return [];
      const i = this.activeIndex;
      const v = this.tracker.velocity(t);
      const down = -this.pullUp;
      const release = R.decideDismiss(down, -v.y);
      this.lastRelease = release;
      if (release === "commitDrag" || release === "commitFlick") {
        return [{ kind: "dismissed", index: i }].concat(this.beginFlight(false, this.visualVelocity(v), true));
      }
      return this.beginFlight(true, this.visualVelocity(v), false);
    }
    return [];
  };
  Model.prototype.activate = function (index) {
    if (index < 0 || index >= L.count) return [];
    if (this.phase !== "resting") return [];
    this.focusIndex = null;
    this.activeIndex = index;
    this.pullUp = 0;
    this.pullRight = 0;
    this.isArmed = false;
    this.lastRelease = "commitDrag";
    this.commits += 1;
    const rest = L.restCenter(index);
    this.flightX = new Spring(rest.x, 0, Model.presentStiffness, Model.presentDamping);
    this.flightY = new Spring(rest.y, 0, Model.presentStiffness, Model.presentDamping);
    this.flightRot = new Spring(L.restRotation(index), 0, Model.returnStiffness, Model.returnDamping);
    this.flightFlip = new Spring(0, 0, Model.flipStiffness, Model.flipDamping);
    this.flightScale = new Spring(1, 0, Model.presentStiffness, Model.presentDamping);
    this.aimFlight(true);
    if (this.reduceMotion) {
      this.snapPresented(true);
      return [{ kind: "committed", index: index }, { kind: "presented", index: index }];
    }
    this.phase = "presenting";
    this.phaseTime = 0;
    this.announceArrival = true;
    return [{ kind: "committed", index: index }];
  };
  Model.prototype.dismiss = function () {
    if (this.activeIndex == null) return [];
    const i = this.activeIndex;
    if (this.phase === "presenting" || this.phase === "presented" || this.phase === "dismissing") {
      return [{ kind: "dismissed", index: i }].concat(this.beginFlight(false, { x: 0, y: 0 }, true));
    }
    return [];
  };
  Model.prototype.integrate = function (h) {
    if (this.reduceMotion) this.snapLifts();
    else {
      for (let i = 0; i < L.count; i++) this.lifts[i].step(this.liftTarget(i), h);
    }
    if (this.phase !== "presenting" && this.phase !== "returning") return;
    this.flightX.step(this.flightTarget.x, h);
    this.flightY.step(this.flightTarget.y, h);
    this.flightRot.step(this.flightTargetRot, h);
    this.flightFlip.step(this.flightTargetFlip, h);
    this.flightScale.step(this.flightTargetScale, h);
  };
  Model.prototype.flightSettled = function () {
    return this.flightX.isSettled(this.flightTarget.x, 0.4)
      && this.flightY.isSettled(this.flightTarget.y, 0.4)
      && this.flightRot.isSettled(this.flightTargetRot, 0.01)
      && this.flightFlip.isSettled(this.flightTargetFlip, 0.02)
      && this.flightScale.isSettled(this.flightTargetScale, 0.01);
  };
  Model.prototype.finishIfNeeded = function () {
    if (this.phase !== "presenting" && this.phase !== "returning") return [];
    const timedOut = this.phaseTime >= Model.flightCap;
    if (!timedOut && !this.flightSettled()) return [];
    if (this.phase === "presenting") return this.snapPresented(this.announceArrival);
    return this.snapHome();
  };
  Model.prototype.step = function (dt) {
    const total = isFinite(dt) ? Math.min(Math.max(dt, 0), Model.maxStep) : 0;
    if (!(total > 0)) return [];
    let left = total;
    const events = [];
    while (left > 1e-12) {
      const h = Math.min(left, Spring.maxFrame);
      this.time += h;
      this.phaseTime += h;
      this.integrate(h);
      const more = this.finishIfNeeded();
      for (let i = 0; i < more.length; i++) events.push(more[i]);
      left -= h;
    }
    return events;
  };

  function fmt(x) {
    if (!isFinite(x)) return "nan";
    const y = x === 0 ? 0 : x;
    return y.toFixed(6);
  }
  function eventName(e) { return e.kind + " " + e.index; }
  function canonicalTrace() {
    const lines = [];
    const add = function (s) { lines.push(s); };
    add("rubberScale " + fmt(R.scale));
    add("rubberLength " + fmt(R.length));
    add("hoverLift " + fmt(L.hoverLift));
    add("commitRise " + fmt(L.commitRise));
    add("flickSpeed " + fmt(L.flickSpeed));
    add("flickMin " + fmt(L.flickMin));
    add("grabSlop " + fmt(L.grabSlop));
    add("stickiness " + fmt(L.stickiness));
    add("dismissRise " + fmt(L.dismissRise));
    add("dismissFlick " + fmt(L.dismissFlick));
    add("presentedScale " + fmt(L.presentedScale));
    add("width " + fmt(L.width));
    add("height " + fmt(L.height));
    add("cardWidth " + fmt(L.cardWidth));
    add("cardHeight " + fmt(L.cardHeight));
    add("arcRadius " + fmt(L.arcRadius));
    add("halfSpan " + fmt(L.halfSpan));
    add("bottomMargin " + fmt(L.bottomMargin));
    add("stage " + fmt(L.stage.x) + " " + fmt(L.stage.y));
    const origin = L.origin();
    add("origin " + fmt(origin.x) + " " + fmt(origin.y));
    for (let i = 0; i < 5; i++) {
      const c = L.restCenter(i);
      add("rest " + i + " " + fmt(c.x) + " " + fmt(c.y) + " " + fmt(L.restRotation(i)));
    }
    [-400, -100, 0, 20, 100, 180, 300, 600, 1000].forEach(function (x) {
      add("resist " + fmt(x) + " " + fmt(R.resist(x)) + " " + fmt(R.slope(x)));
    });
    cards.forEach(function (card) {
      add("card " + card.index + " " + card.title + " " + card.kicker + " " + card.marks.length + " " + fmt(card.paper.r) + " " + fmt(card.paper.g) + " " + fmt(card.paper.b) + " " + fmt(card.ink.r) + " " + fmt(card.ink.g) + " " + fmt(card.ink.b));
      card.marks.forEach(function (mark) {
        const kind = mark.kind === "rect" ? "rect" : mark.kind;
        const rw = mark.kind === "ellipse" ? mark.rx : mark.width;
        const rh = mark.kind === "ellipse" ? mark.ry : mark.height;
        add("mark " + kind + " " + fmt(mark.cx) + " " + fmt(mark.cy) + " " + fmt(rw) + " " + fmt(rh) + " " + fmt(mark.rotation) + " " + fmt(mark.color.r) + " " + fmt(mark.color.g) + " " + fmt(mark.color.b) + " " + fmt(mark.alpha));
      });
    });
    function dump(m, tag) {
      const focus = m.focusIndex == null ? "-" : String(m.focusIndex);
      const active = m.activeIndex == null ? "-" : String(m.activeIndex);
      add("state " + tag + " " + m.phase + " " + focus + " " + active + " " + fmt(m.pullUp) + " " + fmt(m.pullRight) + " " + (m.isArmed ? 1 : 0) + " " + fmt(m.openness()));
      for (let i = 0; i < 5; i++) {
        const p = m.pose(i);
        add("pose " + tag + " " + i + " " + fmt(p.center.x) + " " + fmt(p.center.y) + " " + fmt(p.rotation) + " " + fmt(p.lift) + " " + fmt(p.scale) + " " + fmt(p.flip) + " " + fmt(p.opacity) + " " + p.z);
      }
    }
    function note(events, tag) {
      if (!events.length) add("events " + tag + " -");
      else add("events " + tag + " " + events.map(eventName).join(","));
    }
    function pump(m, seconds, tag) {
      let left = seconds;
      let bucket = [];
      let slice = 0;
      while (left > 1e-9) {
        const d = Math.min(1 / 60, left);
        const ev = m.step(d);
        for (let i = 0; i < ev.length; i++) bucket.push(ev[i]);
        left -= d;
        slice += 1;
        if (slice % 6 === 0) {
          note(bucket, tag + "." + slice);
          dump(m, tag + "." + slice);
          bucket = [];
        }
      }
      if (bucket.length) {
        note(bucket, tag + ".end");
        dump(m, tag + ".end");
      }
    }
    const m = new Model(false);
    dump(m, "start");
    const c0 = L.restCenter(0);
    note(m.pointerDown(c0, 0), "down0");
    dump(m, "down0");
    pump(m, 0.3, "hover0");
    for (let i = 1; i < 5; i++) {
      const c = L.restCenter(i);
      note(m.pointerMoved(c, 0.3 + i * 0.05), "slide" + i);
      dump(m, "slide" + i);
    }
    note(m.pointerUp(L.restCenter(4), 1), "upSlide");
    dump(m, "upSlide");
    pump(m, 0.4, "settle");
    const c2 = L.restCenter(2);
    note(m.pointerDown(c2, 2), "down2");
    pump(m, 0.4, "hover2");
    const dragged = { x: c2.x, y: c2.y - 180 };
    note(m.pointerMoved(dragged, 2.6), "drag");
    dump(m, "drag");
    note(m.pointerUp(dragged, 2.6), "release");
    dump(m, "release");
    pump(m, 1.2, "flight");
    note(m.dismiss(), "dismiss");
    dump(m, "dismiss");
    pump(m, 1.2, "home");
    const flick = new Model(false);
    const c1 = L.restCenter(1);
    const tip = { x: c1.x, y: c1.y - 40 };
    note(flick.pointerDown(c1, 0), "flickDown");
    note(flick.pointerMoved(tip, 0.03), "flickMove");
    note(flick.pointerUp(tip, 0.03), "flickUp");
    dump(flick, "flick");
    const early = new Model(false);
    note(early.pointerDown(c2, 0), "earlyDown");
    const short = { x: c2.x, y: c2.y - 36 };
    note(early.pointerMoved(short, 0.5), "earlyMove");
    note(early.pointerUp(short, 0.8), "earlyUp");
    dump(early, "early");
    const rm = new Model(true);
    note(rm.activate(3), "rmOpen");
    dump(rm, "rmOpen");
    note(rm.dismiss(), "rmClose");
    dump(rm, "rmClose");
    return lines.join("\n") + "\n";
  }

  return { layout: L, resistance: R, cards: cards, Model: Model, canonicalTrace: canonicalTrace, fmt: fmt };
});
