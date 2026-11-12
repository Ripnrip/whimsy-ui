// RippleToHide core, shared by the canvas page, the parity check and the GIF capture.
// Constants and the displacement match RippleRules / RippleWave in RippleToHideCore.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.RippleToHideCore = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const RULES = {
    wavelength: 44,
    speed: 240,
    spatialDecay: 150,
    timeDamping: 0.48,
    frontSoftness: 20,
    duration: 0.9,
    amplitude: 14,
    swapFraction: 0.5,
    reduceMotionDuration: 0.28,
  };

  function clamp01(x) {
    return Math.min(1, Math.max(0, x));
  }

  function smoothstep(a, b, x) {
    if (a === b) return x < a ? 0 : 1;
    const t = clamp01((x - a) / (b - a));
    return t * t * (3 - 2 * t);
  }

  function gate(d, t, rules) {
    if (!(t > 0) || !Number.isFinite(d) || !Number.isFinite(t)) return 0;
    const front = rules.speed * t;
    return 1 - smoothstep(front - rules.frontSoftness, front, Math.max(d, 0));
  }

  function displacement(d, t, rules) {
    rules = rules || RULES;
    if (!(t > 0) || !Number.isFinite(d) || !Number.isFinite(t)) return 0;
    d = Math.max(d, 0);
    const k = 2 * Math.PI / rules.wavelength;
    const front = rules.speed * t;
    const wave = Math.sin(k * d - k * rules.speed * t);
    const g = 1 - smoothstep(front - rules.frontSoftness, front, d);
    return wave * g * Math.exp(-t / rules.timeDamping) * Math.exp(-d / rules.spatialDecay);
  }

  function samplePosition(position, tap, time, amplitude, rules) {
    if (![position.x, position.y, tap.x, tap.y, time, amplitude].every(Number.isFinite)) {
      return Number.isFinite(position.x) && Number.isFinite(position.y) ? { x: position.x, y: position.y } : { x: 0, y: 0 };
    }
    const vx = position.x - tap.x;
    const vy = position.y - tap.y;
    const d = Math.hypot(vx, vy);
    if (d < 1e-3) return { x: position.x, y: position.y };
    const offset = displacement(d, time, rules) * amplitude;
    return { x: position.x - vx * (offset / d), y: position.y - vy * (offset / d) };
  }

  function mask(balance) {
    let out = "";
    for (const ch of balance) {
      const code = ch.codePointAt(0);
      out += ch.length === 1 && code >= 48 && code <= 57 ? "•" : ch;
    }
    return out;
  }

  function passRadius(tap, bounds, reach) {
    const corners = [
      [bounds.minX, bounds.minY],
      [bounds.maxX, bounds.minY],
      [bounds.minX, bounds.maxY],
      [bounds.maxX, bounds.maxY],
    ];
    let farthest = 0;
    for (const [x, y] of corners) {
      farthest = Math.max(farthest, Math.hypot(tap.x - x, tap.y - y));
    }
    if (!Number.isFinite(farthest)) return 0;
    if (!(reach > 0) || !Number.isFinite(reach)) return Math.max(farthest, 0);
    return Math.min(Math.max(farthest, 0), reach * 0.92);
  }

  function activeDuration(model) {
    return model.reduceMotion ? model.rules.reduceMotionDuration : model.rules.duration;
  }

  function isAnimating(model) {
    return model.phase === "hiding" || model.phase === "revealing";
  }

  function shaderTime(model) {
    if (!isAnimating(model) || model.reduceMotion) return 0;
    if (model.phase === "revealing") return Math.max(model.rules.duration - model.elapsed, 0);
    return model.elapsed;
  }

  function shaderAmplitude(model) {
    if (!isAnimating(model) || model.reduceMotion) return 0;
    return model.rules.amplitude;
  }

  function maskAmount(model) {
    if (model.phase === "shown") return 0;
    if (model.phase === "hidden") return 1;
    const duration = activeDuration(model);
    if (model.phase === "hiding") {
      if (model.reduceMotion) return clamp01(model.elapsed / duration);
      return model.showsMask ? 1 : 0;
    }
    if (model.reduceMotion) return 1 - clamp01(model.elapsed / duration);
    return model.showsMask ? 1 : 0;
  }

  function createModel(options) {
    options = options || {};
    return {
      rules: options.rules || RULES,
      reduceMotion: !!options.reduceMotion,
      phase: "shown",
      elapsed: 0,
      tap: { x: 0, y: 0 },
      passRadius: 0,
      showsMask: false,
      hapticFired: false,
    };
  }

  function hapticElapsed(model) {
    if (!(model.passRadius > 0) || !Number.isFinite(model.passRadius)) return null;
    if (model.phase === "revealing") {
      const when = model.rules.duration - model.passRadius / model.rules.speed;
      if (!(when > 0) || when > activeDuration(model)) return null;
      return when;
    }
    const when = model.passRadius / model.rules.speed;
    if (!(when > 0) || when > activeDuration(model)) return null;
    return when;
  }

  function begin(model, hiding, point, radius) {
    model.phase = hiding ? "hiding" : "revealing";
    model.elapsed = 0;
    model.tap = Number.isFinite(point.x) && Number.isFinite(point.y) ? { x: point.x, y: point.y } : { x: 0, y: 0 };
    model.passRadius = Number.isFinite(radius) ? Math.max(radius, 0) : 0;
    model.hapticFired = false;
    model.showsMask = !hiding;
    return [hiding ? "beganHiding" : "beganRevealing"];
  }

  function toggle(model, point, radius) {
    if (model.phase === "shown") return begin(model, true, point, radius);
    if (model.phase === "hidden") return begin(model, false, point, radius);
    return [];
  }

  function advance(model, dt) {
    if (!isAnimating(model) || !(dt > 0) || !Number.isFinite(dt)) return [];
    const before = model.elapsed;
    const duration = activeDuration(model);
    model.elapsed = Math.min(duration, before + dt);
    const moments = [];
    const when = hapticElapsed(model);
    if (!model.reduceMotion && !model.hapticFired && when !== null && when > before && when <= model.elapsed) {
      moments.push({ time: when, order: 0, event: "haptic" });
    }
    const half = duration * model.rules.swapFraction;
    if (before < half && model.elapsed >= half) {
      if (model.phase === "hiding" && !model.showsMask) moments.push({ time: half, order: 1, event: "swappedToMask" });
      else if (model.phase === "revealing" && model.showsMask) moments.push({ time: half, order: 1, event: "swappedToDigits" });
    }
    if (model.elapsed >= duration) {
      moments.push({ time: duration, order: 2, event: model.phase === "hiding" ? "settledHidden" : "settledShown" });
    }
    moments.sort((a, b) => a.time - b.time || a.order - b.order);
    const events = [];
    for (const moment of moments) {
      if (moment.event === "haptic") model.hapticFired = true;
      else if (moment.event === "swappedToMask") model.showsMask = true;
      else if (moment.event === "swappedToDigits") model.showsMask = false;
      else if (moment.event === "settledHidden") {
        model.phase = "hidden";
        model.showsMask = true;
        model.elapsed = 0;
        model.hapticFired = false;
      } else if (moment.event === "settledShown") {
        model.phase = "shown";
        model.showsMask = false;
        model.elapsed = 0;
        model.hapticFired = false;
      }
      events.push(moment.event);
    }
    return events;
  }

  function snapshot(model, events) {
    return {
      events: events,
      phase: model.phase,
      elapsed: model.elapsed,
      shaderTime: shaderTime(model),
      shaderAmplitude: shaderAmplitude(model),
      showsMask: model.showsMask,
      maskAmount: maskAmount(model),
    };
  }

  function trace(reduceMotion) {
    const model = createModel({ reduceMotion: reduceMotion });
    const tap = { x: 140, y: 80 };
    const log = [];
    log.push(snapshot(model, toggle(model, tap, 72)));
    for (let i = 0; i < 20; i++) log.push(snapshot(model, advance(model, 0.05)));
    log.push(snapshot(model, toggle(model, tap, 72)));
    for (let i = 0; i < 20; i++) log.push(snapshot(model, advance(model, 0.05)));
    return log;
  }

  return {
    RULES: RULES,
    gate: gate,
    displacement: displacement,
    samplePosition: samplePosition,
    mask: mask,
    passRadius: passRadius,
    createModel: createModel,
    toggle: toggle,
    advance: advance,
    shaderTime: shaderTime,
    shaderAmplitude: shaderAmplitude,
    maskAmount: maskAmount,
    trace: trace,
  };
});
