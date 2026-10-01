// Ebru: marbling on a canvas, done the way the craft does it. Every drop of pigment is a polygon; a new drop
// pushes everything around it outward (area is conserved, so old drops become rings), and combs, needles and
// swirls slide the pigment along without mixing it. The maths is Jaffer & Lu's "Mathematical Marbling".
// All coordinates are CSS pixels; the canvas is drawn at a capped device pixel ratio. Points live in typed
// arrays and are rebuilt through one shared scratch buffer, so a running tray makes almost no garbage. The
// class only needs a 2D context, so it runs the same on an OffscreenCanvas in a worker (engine.js).

const TAU = Math.PI * 2;

export class Tray {
  constructor(canvas, { ground = '#111a27', pixelBudget = 3e6, maxDpr = 1.5, rim = true, vertexBudget = 26000, maxDrops = 64 } = {}) {
    this.vertexBudget = vertexBudget;
    this.maxDrops = maxDrops;
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.ground = ground;
    this.pixelBudget = pixelBudget;
    this.maxDpr = maxDpr;
    this.rim = rim;
    this.drops = [];      // { pts: number[], color, rimColor }
    this.blooms = [];     // growing drops
    this.needles = [];    // animated needle paths
    this.dirty = true;
    this.w = 0; this.h = 0;
  }

  // Match the canvas to its box (CSS pixels). Existing pigment keeps its coordinates.
  // `scale` draws a small logical tray onto a bigger canvas (a pattern keeps its grain on a large sheet).
  resize(w, h, scale = 1, deviceDpr = 1) {
    if (!w || !h) return;
    const dpr = Math.min(deviceDpr, this.maxDpr, Math.sqrt(this.pixelBudget / (w * h * scale * scale)));
    this.dpr = Math.max(0.75, dpr) * scale;
    this.w = w; this.h = h;
    this.canvas.width = Math.round(w * this.dpr);
    this.canvas.height = Math.round(h * this.dpr);
    this.dirty = true;
  }

  // Drop pigment instantly at full size.
  drop(x, y, r, color) {
    this._grow(x, y, 0, r);
    this.drops.push(makeDrop(x, y, r, color));
    this.dirty = true;
  }

  // Drop pigment that spreads over `ms`, the way it does on real size water.
  bloom(x, y, r, color, ms = 900) {
    const start = 0.6;
    this._grow(x, y, 0, start);
    const drop = makeDrop(x, y, start, color, r);
    drop.blooming = true;
    this.drops.push(drop);
    this.blooms.push({ x, y, r: start, target: r, t: 0, ms, drop });
    this.dirty = true;
  }

  // Everything outside the circle moves out so that the ring between old and new radius is freed.
  // `upTo` limits the push to that drop and the ones under it: a drop still spreading must not shove
  // pigment that landed on top of it later.
  _grow(cx, cy, r0, r1, upTo = null) {
    const dr2 = r1 * r1 - r0 * r0;
    if (dr2 <= 0) return;
    for (const d of this.drops) {
      const p = d.pts;
      for (let i = 0; i < p.length; i += 2) {
        const dx = p[i] - cx, dy = p[i + 1] - cy;
        const l2 = dx * dx + dy * dy;
        if (l2 < 1e-6) continue;
        const s = Math.sqrt(1 + dr2 / l2);
        p[i] = cx + dx * s; p[i + 1] = cy + dy * s;
      }
      if (d === upTo) break;
    }
  }

  // A comb: a family of parallel tines `spacing` apart. Each point is dragged along `dir` by the nearest tine.
  // With `alternate`, every other tine pulls the opposite way (gelgit, back and forth).
  comb(dirX, dirY, spacing, offset, alpha, lambda = 14, alternate = false) {
    if (!alpha) return;
    const len = Math.hypot(dirX, dirY) || 1;
    const mx = dirX / len, my = dirY / len, nx = -my, ny = mx;
    const period = alternate ? spacing * 2 : spacing;
    for (const d of this.drops) {
      const p = d.pts;
      for (let i = 0; i < p.length; i += 2) {
        const u = p[i] * nx + p[i + 1] * ny - offset;
        let m = ((u % period) + period) % period;
        let sign = 1, dist;
        if (alternate) {
          // tines at 0 (forward) and spacing (backward)
          const d0 = Math.min(m, period - m), d1 = Math.abs(m - spacing);
          if (d1 < d0) { sign = -1; dist = d1; } else dist = d0;
        } else dist = Math.min(m, period - m);
        const z = sign * alpha * lambda / (dist + lambda);
        p[i] += z * mx; p[i + 1] += z * my;
      }
    }
    this.dirty = true;
  }

  // A sine shear across the whole tray (şal's wavy combing). Area preserving.
  wave(amplitude, wavelength, phase = 0, vertical = false) {
    const k = TAU / wavelength;
    for (const d of this.drops) {
      const p = d.pts;
      for (let i = 0; i < p.length; i += 2) {
        if (vertical) p[i + 1] += amplitude * Math.sin(p[i] * k + phase);
        else p[i] += amplitude * Math.sin(p[i + 1] * k + phase);
      }
    }
    this.dirty = true;
  }

  // A circular tine of radius R around (cx, cy): points near the circle turn with it (bülbül yuvası).
  swirl(cx, cy, R, alpha, lambda = 10) {
    for (const d of this.drops) {
      const p = d.pts;
      for (let i = 0; i < p.length; i += 2) {
        const dx = p[i] - cx, dy = p[i + 1] - cy;
        const r = Math.hypot(dx, dy);
        if (r < 0.5) continue;
        const z = alpha * lambda / (Math.abs(r - R) + lambda);
        const th = z / r, c = Math.cos(th), s = Math.sin(th);
        p[i] = cx + dx * c - dy * s; p[i + 1] = cy + dx * s + dy * c;
      }
    }
    this.dirty = true;
  }

  // A needle moved from (x0, y0) to (x1, y1): pigment next to it is carried along, falling off with distance.
  stylus(x0, y0, x1, y1, lambda = 16, strength = 1) {
    const sx = x1 - x0, sy = y1 - y0;
    const L2 = sx * sx + sy * sy;
    if (L2 < 0.01) return;
    const reach = lambda * 12, reach2 = (Math.sqrt(L2) + reach) ** 2;
    const mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    for (const d of this.drops) {
      const p = d.pts;
      for (let i = 0; i < p.length; i += 2) {
        const px = p[i], py = p[i + 1];
        if ((px - mx) ** 2 + (py - my) ** 2 > reach2) continue;
        let t = ((px - x0) * sx + (py - y0) * sy) / L2;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        const dist = Math.hypot(px - (x0 + sx * t), py - (y0 + sy * t));
        const f = strength * lambda / (dist + lambda);
        p[i] += sx * f; p[i + 1] += sy * f;
      }
    }
    this.dirty = true;
  }

  // Pull a needle along a path of points over `ms`.
  needle(path, ms = 1200, lambda = 16) {
    this.needles.push({ path, ms, lambda, t: 0, at: 0 });
  }

  get busy() { return this.blooms.length > 0 || this.needles.length > 0; }

  // Advance blooms and needles by `dt` ms. Returns true when something moved.
  step(dt) {
    let moved = false;
    for (const b of this.blooms) {
      b.t = Math.min(b.ms, b.t + dt);
      const k = 1 - Math.pow(1 - b.t / b.ms, 3);
      const r = Math.max(b.r, b.target * k);
      this._grow(b.x, b.y, b.r, r, b.drop);
      b.r = r; moved = true;
    }
    this.blooms = this.blooms.filter(b => { if (b.t < b.ms) return true; b.drop.blooming = false; return false; });
    for (const n of this.needles) {
      n.t = Math.min(n.ms, n.t + dt);
      const k = easeInOut(n.t / n.ms);
      const target = k * (n.path.length - 1);
      while (n.at < target) {
        const next = Math.min(target, Math.floor(n.at) + 1);
        const a = lerpPath(n.path, n.at), b = lerpPath(n.path, next);
        this.stylus(a[0], a[1], b[0], b[1], n.lambda);
        n.at = next; moved = true;
      }
    }
    this.needles = this.needles.filter(n => n.t < n.ms);
    if (moved) this.dirty = true;
    return moved;
  }

  // Keep edges short enough to stay smooth, drop points that bunch up, and forget pigment nobody can see.
  refine() {
    const W = this.w, H = this.h, M = 60;
    // Combing makes edges longer and longer; past the budget the tray trades smoothness for a steady frame.
    const load = Math.max(1, this.vertexCount() / this.vertexBudget);
    const near = 3.4 * load, far = 28 * load, tiny = 0.8 * load;
    for (const d of this.drops) {
      const p = d.pts, n = p.length;
      let out = need(n * 2 + 64), k = 0;
      for (let i = 0; i < n; i += 2) {
        const x = p[i], y = p[i + 1];
        if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
        const j = (i + 2) % n, x2 = p[j], y2 = p[j + 1];
        if (k + 40 > out.length) out = need(out.length * 2, out, k);
        if (!Number.isFinite(x2) || !Number.isFinite(y2)) { out[k++] = x; out[k++] = y; continue; }
        const inside = x > -M && x < W + M && y > -M && y < H + M;
        const dx = x2 - x, dy = y2 - y, seg = Math.sqrt(dx * dx + dy * dy);
        if (seg < tiny && k > 4 && !d.blooming) continue;
        out[k++] = x; out[k++] = y;
        const limit = inside ? near : far;
        if (seg > limit) {
          const m = Math.min(16, Math.ceil(seg / limit));
          for (let s = 1; s < m; s++) { out[k++] = x + dx * s / m; out[k++] = y + dy * s / m; }
        }
      }
      d.pts = out.slice(0, k);
    }
    // Culling: a drop with no point inside the view is either off to one side (invisible) or covers the
    // whole view, in which case everything under it is invisible.
    let coverFrom = -1;
    const keep = [];
    for (let di = 0; di < this.drops.length; di++) {
      const d = this.drops[di], p = d.pts;
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, anyInside = false;
      for (let i = 0; i < p.length; i += 2) {
        const x = p[i], y = p[i + 1];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (!anyInside && x > -M && x < W + M && y > -M && y < H + M) anyInside = true;
      }
      if (anyInside) { keep.push(d); continue; }
      const covers = minX < -M && maxX > W + M && minY < -M && maxY > H + M;
      if (covers) { coverFrom = keep.length; keep.push(d); }
    }
    this.drops = coverFrom > 0 ? keep.slice(coverFrom) : keep;
    if (coverFrom >= 0) {
      // The covering drop becomes the new ground: cheaper to paint, same picture.
      this.ground = this.drops[0].color;
      this.drops.shift();
    }
    // Hard ceiling: the oldest pigment, deepest under everything, goes first.
    let total = this.vertexCount();
    while (this.drops.length > 1 && (this.drops.length > this.maxDrops || total > this.vertexBudget * 1.5)) {
      const gone = this.drops.shift();
      total -= gone.pts.length / 2;
      if (gone.pts.length > 400) this.ground = gone.color;
    }
  }

  vertexCount() { let n = 0; for (const d of this.drops) n += d.pts.length; return n / 2; }

  render() {
    const { ctx, dpr } = this;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = this.ground;
    ctx.fillRect(0, 0, this.w, this.h);
    ctx.lineJoin = 'bevel';   // a 1px hairline: round joins cost more and look the same
    for (const d of this.drops) {
      const p = d.pts;
      if (p.length < 6) continue;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      for (let i = 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1]);
      ctx.closePath();
      ctx.fillStyle = d.color;
      ctx.fill();
      if (this.rim) {
        // Pigment gathers at the edge of a drop; a hairline of the darker tone reads as that.
        ctx.strokeStyle = d.rimColor;
        ctx.lineWidth = 1.1;
        ctx.stroke();
      }
    }
    this.dirty = false;
  }
}

function makeDrop(x, y, r, color, finalR = r) {
  const n = Math.max(48, Math.min(420, Math.round(TAU * finalR / 3.2)));
  const pts = new Float64Array(n * 2);
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU;
    pts[i * 2] = x + Math.cos(a) * r;
    pts[i * 2 + 1] = y + Math.sin(a) * r;
  }
  return { pts, color, rimColor: shade(color, -0.22) };
}

// One growing scratch buffer for refine(): each drop is rebuilt into it and copied out once.
let scratch = new Float64Array(1 << 15);
function need(size, keep = null, used = 0) {
  if (scratch.length < size) {
    const next = new Float64Array(Math.max(size, scratch.length * 2));
    if (keep) next.set(keep.subarray(0, used));
    scratch = next;
  }
  return scratch;
}

function lerpPath(path, t) {
  const i = Math.min(path.length - 2, Math.floor(t)), f = t - i;
  const a = path[i], b = path[i + 1];
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
}

function easeInOut(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }

// Darken (k < 0) or lighten (k > 0) a #rrggbb colour, returned as an rgba() hairline.
export function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16);
  let r = n >> 16, g = (n >> 8) & 255, b = n & 255;
  if (k < 0) { r *= 1 + k; g *= 1 + k; b *= 1 + k; }
  else { r += (255 - r) * k; g += (255 - g) * k; b += (255 - b) * k; }
  return `rgba(${r | 0},${g | 0},${b | 0},0.6)`;
}

// A small seeded random generator, so a swatch looks the same every visit.
export function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// The named patterns of the pattern book. Each paints a finished sheet on a small tray.
export const patterns = {
  battal(tray, c, rand) {
    const { w, h } = tray;
    for (let i = 0; i < 46; i++) tray.drop(rand() * w, rand() * h, 6 + rand() * 14, c[i % c.length]);
  },
  somaki(tray, c, rand) {
    patterns.battal(tray, c, rand);
    const { w, h } = tray;
    for (let i = 0; i < 120; i++) tray.drop(rand() * w, rand() * h, 1 + rand() * 2.4, c[(i + 1) % c.length]);
  },
  gelgit(tray, c, rand) {
    const { w, h } = tray;
    for (let y = 8; y < h + 12; y += 16) for (let x = 6; x < w + 12; x += 14) tray.drop(x + rand() * 6, y + rand() * 6, 6 + rand() * 3, c[(Math.floor(x / 14) + Math.floor(y / 16)) % c.length]);
    tray.comb(0, 1, 11, 3, 26, 5, true);
  },
  tarakli(tray, c, rand) {
    patterns.gelgit(tray, c, rand);
    tray.comb(1, 0, 7, 2, 10, 3);
  },
  sal(tray, c, rand) {
    patterns.gelgit(tray, c, rand);
    tray.wave(9, 34, rand() * 6);
    tray.comb(1, 0, 9, 1, 8, 3, true);
  },
  bulbul(tray, c, rand) {
    patterns.gelgit(tray, c, rand);
    const { w, h } = tray;
    for (let y = 22; y < h; y += 44) for (let x = 24; x < w; x += 48) tray.swirl(x + (y / 44 % 2) * 24, y, 12, 40, 9);
  },
  hatip(tray, c, rand) {
    patterns.battal(tray, [c[c.length - 1]], rand);
    const { w, h } = tray;
    const spots = [];
    for (let y = 24; y < h; y += 46) for (let x = 26; x < w; x += 50) spots.push([x + (y / 46 % 2) * 25, y]);
    for (const [x, y] of spots) { tray.drop(x, y, 13, c[0]); tray.drop(x, y, 8, c[1]); tray.drop(x, y, 4, c[2] || c[0]); }
    for (const [x, y] of spots) tray.stylus(x, y - 14, x, y + 12, 5, 1);
  },
  // kumlu: sand, a fine scatter of the lightest colour over a quiet battal
  kumlu(tray, c, rand) {
    patterns.battal(tray, c.slice(0, -1), rand);
    const { w, h } = tray;
    for (let i = 0; i < 260; i++) tray.drop(rand() * w, rand() * h, 0.6 + rand() * 1.1, c[c.length - 1]);
  },
  // lale: rings dropped in a row and pulled into tulips by one stroke of the needle each
  lale(tray, c, rand) {
    patterns.battal(tray, [c[c.length - 1], c[c.length - 2]], rand);
    const { w, h } = tray;
    for (let x = 30; x < w; x += 58) for (let y = 34; y < h; y += 70) {
      const cx = x + (y / 70 % 2) * 29;
      tray.drop(cx, y, 15, c[0]); tray.drop(cx, y, 10, c[1]); tray.drop(cx, y, 5, c[0]);
      tray.stylus(cx, y - 18, cx, y + 20, 6, 1);
    }
  },
  neftli(tray, c, rand) {
    patterns.battal(tray, c.slice(0, -1), rand);
    const { w, h } = tray;
    for (let i = 0; i < 70; i++) tray.drop(rand() * w, rand() * h, 0.8 + rand() * 1.8, c[c.length - 1]);
    tray.comb(1, 0.3, 30, 0, 6, 8);
  },
};
