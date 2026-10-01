// The water's engine: the tray, its frame loop, the pattern book's sheets and the snapshots the page asks for.
// It runs in a worker on OffscreenCanvases (ebru-worker.js), so marbling never competes with scrolling; where a
// browser cannot hand a canvas to a worker, site.js runs this same engine on the page instead.
import { Tray, patterns, rng } from './ebru.js';

const raf = typeof requestAnimationFrame === 'function' ? f => requestAnimationFrame(f) : f => setTimeout(() => f(performance.now()), 16);

export function createEngine(post) {
  let tray = null, live = true, looping = false, last = 0, frameNo = 0;
  let combHero = 0, combStage = 0;          // scroll since the last frame, applied once per frame
  let finder = null, fctx = null, view = null;
  const work = [];                           // ms of work per frame, for the bench

  const kick = () => {
    if (looping || !tray) return;
    looping = true; last = performance.now();
    raf(frame);
  };

  function frame(now) {
    const t0 = performance.now();
    const dt = Math.min(48, now - last); last = now;
    if (combHero) { tray.comb(0, -1, 74, 12, combHero * 0.12, 11); combHero = 0; }        // the hero: tines pull the pigment up
    if (combStage) { tray.comb(1, 0, 64, 17, combStage * 0.045, 10, true); combStage = 0; } // the stage: a slow gelgit
    const moved = tray.step(dt);
    if ((moved || tray.dirty) && live) {
      // Rebuilding edges every other frame is plenty; the frame in between only draws.
      if (!moved || ++frameNo % 2 === 0) tray.refine();
      tray.render();
      drawFinder();
    }
    work.push(performance.now() - t0);
    if (work.length > 600) work.splice(0, 300);
    // Hidden water waits: nothing runs until it is on screen again.
    if (live && (tray.busy || tray.dirty)) raf(frame);
    else looping = false;
  }

  // The Mirror's viewfinder looks at the water just under the panel.
  function drawFinder() {
    if (!fctx || !view) return;
    const d = tray.dpr, [x, y, w, h] = view;
    fctx.drawImage(tray.canvas, x * d, y * d, w * d, h * d, 0, 0, finder.width, finder.height);
  }

  async function snapshot(id, [x, y, w, h], [ow, oh]) {
    const d = tray.dpr;
    const c = typeof OffscreenCanvas === 'function' ? new OffscreenCanvas(ow, oh) : Object.assign(document.createElement('canvas'), { width: ow, height: oh });
    c.getContext('2d').drawImage(tray.canvas, x * d, y * d, w * d, h * d, 0, 0, ow, oh);
    const bitmap = await createImageBitmap(c);
    post({ type: 'snapshot', id, bitmap }, [bitmap]);
  }

  // A sheet of the pattern book: a small logical tray drawn onto its bigger canvas, once.
  function swatch({ canvas, w, h, dpr, pattern, colors, seed }) {
    const small = new Tray(canvas, { ground: colors[3], pixelBudget: 1.6e6, maxDpr: 2, maxDrops: 420, vertexBudget: 80000 });
    const k = Math.max(1, w / 240);
    small.resize(w / k, h / k, k, dpr);
    patterns[pattern](small, colors, rng(seed));
    small.refine(); small.render();
  }

  const handle = msg => {
    switch (msg.type) {
      case 'init':
        tray = new Tray(msg.canvas, { ground: msg.ground });
        tray.resize(msg.w, msg.h, 1, msg.dpr);
        break;
      case 'resize': tray.resize(msg.w, msg.h, 1, msg.dpr); tray.refine(); tray.render(); drawFinder(); break;
      case 'seed': {
        const r = rng(7), { w, h } = tray;
        for (let i = 0; i < 24; i++) tray.drop(r() * w, r() * h, 30 + r() * Math.max(w, h) * 0.09, msg.tones[i % msg.tones.length]);
        tray.comb(1, 0, 90, 20, 30, 16, true);   // a few quiet ribbons, combed before you arrive
        tray.wave(14, 260, 1.3);
        tray.refine(); tray.render();
        break;
      }
      case 'drop': tray.drop(msg.x, msg.y, msg.r, msg.color); kick(); break;
      case 'bloom': tray.bloom(msg.x, msg.y, msg.r, msg.color, msg.ms); kick(); break;
      case 'stylus': tray.stylus(msg.x0, msg.y0, msg.x1, msg.y1, msg.lambda); kick(); break;
      case 'needle':
        if (msg.instant) { for (let i = 1; i < msg.path.length; i++) tray.stylus(...msg.path[i - 1], ...msg.path[i], msg.lambda); tray.refine(); tray.render(); }
        else { tray.needle(msg.path, msg.ms, msg.lambda); kick(); }
        break;
      case 'comb': if (msg.hero) combHero += msg.dy; else combStage += msg.dy; kick(); break;
      case 'live': live = msg.on; if (live) { tray.dirty = true; kick(); } break;
      case 'finder': finder = msg.canvas; fctx = finder.getContext('2d'); break;
      case 'finderView': view = msg.rect; if (view) drawFinder(); break;
      case 'snapshot': snapshot(msg.id, msg.rect, msg.out); break;
      case 'swatch': swatch(msg); break;
      case 'stats': {
        const s = [...work].sort((a, b) => a - b), q = p => +(s[Math.floor(p * (s.length - 1))] || 0).toFixed(2);
        post({ type: 'stats', id: msg.id, stats: { frames: s.length, p50: q(.5), p90: q(.9), p99: q(.99), max: q(1), verts: tray.vertexCount(), drops: tray.drops.length } });
        if (msg.reset) work.length = 0;
        break;
      }
    }
  };
  return { handle };
}
