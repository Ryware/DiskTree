/* Headroom landing page: interactive treemap demo in the hero.
   Sample data generated on the fly; squarified layout on a canvas; hover, click to zoom,
   and a "Clean safe items" action that relayouts the disk without the regenerable data. */
(function () {
  var host = document.getElementById('demo');
  if (!host) return;
  var canvas = host.querySelector('canvas');
  var tip = host.querySelector('.demo-tip');
  var crumbs = host.querySelector('.demo-crumbs');
  var statFiles = host.querySelector('[data-stat=files]');
  var statUsed = host.querySelector('[data-stat=used]');
  var statFree = host.querySelector('[data-stat=free]');
  var statSafe = host.querySelector('[data-stat=safe]');
  var statState = host.querySelector('[data-stat=state]');
  var cleanBtn = host.querySelector('.demo-clean');
  var ringArc = host.querySelector('.demo-ring .arc');
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var ctx = canvas.getContext('2d');

  /* ---------- sample data ---------- */
  var seed = 7;
  function rnd() { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; }
  var GB = 1e9, MB = 1e6;
  var TOTAL = 494.4 * GB;
  var words = {
    dev: ['Headroom', 'comic-studio', 'platform-api', 'ocr-pipeline', 'langfuse-fork', 'treescan', 'k8s-manifests', 'design-system', 'infra', 'mobile-app'],
    media: ['IMG_4021.heic', 'Trip to Lisbon', 'Screen Recording', 'Keynote 2025', 'Wedding', 'Drone footage', 'Podcast raw', 'Timelapse', 'B-roll', 'Family'],
    app: ['Xcode', 'Final Cut Pro', 'Docker', 'Chrome', 'Slack', 'Figma', 'Logic Pro', 'Parallels', 'Zoom', 'VS Code'],
    cache: ['com.apple.dt.Xcode', 'Homebrew', 'pip', 'Google', 'JetBrains', 'ms-playwright', 'CloudKit', 'Spotify', 'Adobe', 'com.docker.docker'],
    doc: ['Invoices', 'Specs', 'Contracts', 'Scans', 'Books', 'Archive', 'Presentations', 'Receipts', 'Research', 'Notes']
  };
  function pick(list, i) { return list[(i + Math.floor(rnd() * list.length)) % list.length]; }
  function files(n, bytes, kind) {
    var out = [], left = bytes;
    for (var i = 0; i < n; i++) {
      var share = i === n - 1 ? left : Math.max(1, Math.round(left * (0.18 + rnd() * 0.32)));
      left -= share;
      out.push({ name: pick(words[kind], i) + (kind === 'media' ? ['.mov', '.heic', '.mp4', '.raw'][i % 4] : ''), size: share, kind: kind, leaf: true });
    }
    return out;
  }
  function folder(name, bytes, kind, depth, safe) {
    var node = { name: name, size: bytes, kind: kind, safe: !!safe, children: [] };
    var n = depth > 0 ? 3 + Math.floor(rnd() * 5) : 2 + Math.floor(rnd() * 4);
    var left = bytes;
    for (var i = 0; i < n; i++) {
      var share = i === n - 1 ? left : Math.max(1, Math.round(left * (0.12 + rnd() * 0.4)));
      left -= share;
      var child;
      if (depth > 0 && rnd() < 0.65) child = folder(pick(words[kind], i + depth * 3), share, kind, depth - 1, safe);
      else { child = { name: pick(words[kind], i) , size: share, kind: kind, leaf: true, safe: !!safe }; }
      node.children.push(child);
    }
    return node;
  }
  function build() {
    seed = 7;
    var home = { name: 'Users / you', kind: 'doc', children: [
      folder('Pictures', 83.2 * GB, 'media', 2),
      folder('Virtual Machines', 71.4 * GB, 'app', 1),
      folder('Movies', 61.0 * GB, 'media', 2),
      folder('Library / Developer / Xcode / DerivedData', 38.3 * GB, 'cache', 1, true),
      folder('Downloads', 24.6 * GB, 'doc', 2),
      folder('Documents', 18.1 * GB, 'doc', 2),
      folder('Music', 14.2 * GB, 'media', 1),
      folder('Library / Caches', 12.4 * GB, 'cache', 2, true),
      folder('Projects / node_modules', 9.1 * GB, 'dev', 2, true),
      folder('.npm, .cache, Homebrew', 7.2 * GB, 'cache', 1, true),
      folder('.Trash', 5.9 * GB, 'doc', 1, true)
    ]};
    var root = { name: 'Macintosh HD', kind: 'doc', children: [
      home,
      folder('Applications', 42.3 * GB, 'app', 2),
      folder('System', 22.5 * GB, 'app', 1),
      folder('Library', 15.3 * GB, 'cache', 1),
      folder('private / var', 4.8 * GB, 'cache', 1, true)
    ]};
    var count = 0;
    (function total(n, parent) {
      n.parent = parent;
      if (n.leaf) { count += 1; return n.size; }
      var s = 0; n.children.forEach(function (c) { s += total(c, n); });
      n.size = s; return s;
    })(root, null);
    root.files = count;
    return root;
  }
  var root = build();
  var USED = root.size;
  var FILES = 1256000;

  /* ---------- squarified layout ---------- */
  function squarify(items, x, y, w, h, out) {
    if (!items.length) return;
    var total = 0; items.forEach(function (n) { total += n.size; });
    if (total <= 0) return;
    var scale = (w * h) / total;
    var i = 0;
    while (i < items.length) {
      var vertical = w >= h; /* lay a row along the shorter side */
      var side = vertical ? h : w;
      var row = [], rowArea = 0, best = Infinity, j = i;
      while (j < items.length) {
        var a = items[j].size * scale;
        var cand = rowArea + a;
        var mx = 0, mn = Infinity;
        for (var k = i; k <= j; k++) { var ak = items[k].size * scale; if (ak > mx) mx = ak; if (ak < mn) mn = ak; }
        var worst = Math.max((side * side * mx) / (cand * cand), (cand * cand) / (side * side * mn));
        if (worst > best) break;
        best = worst; rowArea = cand; row.push(items[j]); j++;
      }
      var thick = rowArea / side;
      var off = 0;
      row.forEach(function (n) {
        var len = (n.size * scale) / thick;
        if (vertical) out.push([n, x, y + off, thick, len]); else out.push([n, x + off, y, len, thick]);
        off += len;
      });
      if (vertical) { x += thick; w -= thick; } else { y += thick; h -= thick; }
      i = j;
    }
  }
  var PAD = 2, HEAD = 20;
  var groups = [];
  function layout(node, x, y, w, h, depth, out, level) {
    node.r = { x: x, y: y, w: w, h: h };
    if (node.leaf || depth === 0 || w < 14 || h < 14) { out.push(node); return; }
    var kids = node.children.filter(function (c) { return !c.gone; }).slice().sort(function (a, b) { return b.size - a.size; });
    var cells = [];
    var ix = x + PAD, iy = y + PAD, iw = w - PAD * 2, ih = h - PAD * 2;
    if (level === 1 && w > 60 && h > HEAD + 24) { groups.push(node); iy += HEAD; ih -= HEAD; }
    squarify(kids, ix, iy, Math.max(0, iw), Math.max(0, ih), cells);
    cells.forEach(function (c) { layout(c[0], c[1], c[2], c[3], c[4], depth - 1, out, level + 1); });
  }

  /* ---------- state ---------- */
  var W = 0, H = 0, dpr = 1;
  var view = root;           /* zoom root */
  var cells = [];            /* visible leaves */
  var hover = null;
  var t0 = 0;                /* scan animation start */
  var scanDur = reduce ? 0 : 2600;
  var scanned = 0;           /* 0..1 */
  var transitions = null;    /* {from:Map,to:Map,start,dur} */
  var cleaned = false;
  var colors = {};

  function readColors() {
    var cs = getComputedStyle(document.documentElement);
    colors = {
      fg: cs.getPropertyValue('--fg').trim(), fg2: cs.getPropertyValue('--fg-2').trim(), fg3: cs.getPropertyValue('--fg-3').trim(),
      line: cs.getPropertyValue('--line').trim(), accent: cs.getPropertyValue('--accent').trim(), safe: cs.getPropertyValue('--safe').trim(),
      dark: cs.getPropertyValue('--mode').trim() === 'dark'
    };
  }
  /* category colors, muted so the accent and the safe green still lead */
  var palette = {
    dark:  { media: '#4a5fa8', app: '#5a4f8f', doc: '#8a6b3d', dev: '#2f7f85', cache: '#8a4b6a', safe: '#3f9d6a' },
    light: { media: '#8fa3e6', app: '#a79bdf', doc: '#dcb784', dev: '#7fc3c8', cache: '#d59ab6', safe: '#7fcf9f' }
  };
  function fillFor(n, hot) {
    if (hot) return colors.accent;
    var pal = colors.dark ? palette.dark : palette.light;
    return n.safe ? pal.safe : pal[n.kind] || pal.doc;
  }
  function labelColor(n, hot) {
    if (hot) return '#fff';
    return colors.dark ? 'rgba(255,255,255,.92)' : 'rgba(20,20,40,.85)';
  }

  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = host.clientWidth; H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    relayout(false);
  }
  function relayout(animate) {
    var before = {};
    if (animate && !reduce) cells.forEach(function (c) { before[c.name + '|' + c.size] = c.r; });
    var next = [];
    groups = [];
    layout(view, 0, 0, W, H, 4, next, 0);
    if (animate && !reduce) {
      transitions = { start: performance.now(), dur: 650, from: {} };
      next.forEach(function (c) { var k = c.name + '|' + c.size; if (before[k]) transitions.from[k] = before[k]; });
    }
    cells = next;
    crumbsRender();
  }

  /* ---------- drawing ---------- */
  function ease(p) { return 1 - Math.pow(1 - p, 3); }
  function draw(now) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    var n = cells.length;
    var prog = scanDur ? Math.min(1, (now - t0) / scanDur) : 1;
    scanned = prog;
    var tp = transitions ? Math.min(1, (now - transitions.start) / transitions.dur) : 1;
    ctx.textBaseline = 'middle';
    if (prog >= 1 || reduce) {
      ctx.font = '600 12px Geist, system-ui, sans-serif';
      groups.forEach(function (g) {
        var r = g.r;
        ctx.globalAlpha = 1;
        ctx.strokeStyle = colors.line; ctx.lineWidth = 1;
        roundRect(r.x + 1.5, r.y + 1.5, r.w - 3, r.h - 3, 6); ctx.stroke();
        ctx.fillStyle = colors.fg;
        var label = g.name, max = r.w - 16 - ctx.measureText(fmt(g.size)).width - 22;
        while (ctx.measureText(label).width > max && label.length > 3) label = label.slice(0, -2);
        if (label !== g.name) label = label.slice(0, -1) + '…';
        ctx.fillText(label, r.x + 9, r.y + 12);
        var lw = ctx.measureText(label).width;
        ctx.fillStyle = colors.fg3; ctx.font = '400 11px "Geist Mono", ui-monospace, monospace';
        ctx.fillText(fmt(g.size), r.x + 9 + lw + 10, r.y + 12);
        ctx.font = '600 12px Geist, system-ui, sans-serif';
      });
    }
    ctx.font = '500 12px Geist, system-ui, sans-serif';
    for (var i = 0; i < n; i++) {
      var c = cells[i], r = c.r;
      var x = r.x, y = r.y, w = r.w, h = r.h;
      if (transitions) {
        var f = transitions.from[c.name + '|' + c.size];
        if (f) { var e = ease(tp); x = f.x + (r.x - f.x) * e; y = f.y + (r.y - f.y) * e; w = f.w + (r.w - f.w) * e; h = f.h + (r.h - f.h) * e; }
      }
      var local = 1;
      if (prog < 1) {
        var start = i / n; /* cells appear in layout order */
        local = Math.min(1, Math.max(0, (prog - start) / 0.18));
        if (local <= 0) continue;
        local = ease(local);
      }
      var cx = x + w / 2, cy = y + h / 2;
      var ww = w * (0.6 + 0.4 * local), hh = h * (0.6 + 0.4 * local);
      ctx.globalAlpha = local;
      ctx.fillStyle = fillFor(c, c === hover);
      roundRect(cx - ww / 2 + 1, cy - hh / 2 + 1, Math.max(0, ww - 2), Math.max(0, hh - 2), 3);
      ctx.fill();
      if (w > 72 && h > 22 && local > 0.9) {
        ctx.fillStyle = labelColor(c, c === hover);
        ctx.globalAlpha = c === hover ? 1 : 0.9;
        var label = c.name, max = w - 14;
        while (ctx.measureText(label).width > max && label.length > 3) label = label.slice(0, -2);
        if (label !== c.name) label = label.slice(0, -1) + '…';
        ctx.fillText(label, x + 8, y + 12);
        if (h > 40) { ctx.font = '400 11px "Geist Mono", ui-monospace, monospace'; ctx.globalAlpha *= 0.75; ctx.fillText(fmt(c.size), x + 8, y + 28); ctx.font = '500 12px Geist, system-ui, sans-serif'; }
      }
    }
    ctx.globalAlpha = 1;
    if (transitions && tp >= 1) transitions = null;
    if (prog < 1) {
      statFiles.textContent = Math.round(FILES * ease(prog)).toLocaleString('en-US');
      statState.textContent = 'Scanning Macintosh HD';
    } else if (!cleaned && statState.textContent !== 'Scan complete, 20.4 s') {
      statFiles.textContent = FILES.toLocaleString('en-US');
      statState.textContent = 'Scan complete, 20.4 s';
      host.classList.add('scanned');
    }
    if (prog < 1 || transitions || hover) requestAnimationFrame(draw);
    else requestAnimationFrame(idle);
  }
  function idle() { /* nothing to animate; wait for input */ }
  function kick() { requestAnimationFrame(draw); }
  function roundRect(x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h); ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y); ctx.closePath();
  }
  function fmt(b) { return b >= GB ? (b / GB).toFixed(b >= 10 * GB ? 1 : 2) + ' GB' : (b / MB).toFixed(0) + ' MB'; }
  function pathOf(n) { var p = []; for (var x = n; x; x = x.parent) p.unshift(x.name); return p.join(' / '); }

  /* ---------- stats ---------- */
  var safeTotal = 0;
  (function sum(n) { if (n.safe && (n.leaf || !n.parent || !n.parent.safe)) { safeTotal += n.size; return; } if (n.children) n.children.forEach(sum); })(root);
  var used = USED, free = TOTAL - USED;
  function stats(animate) {
    var target = { used: used, free: free, safe: cleaned ? 0 : safeTotal };
    if (!animate || reduce) { apply(target); return; }
    var from = { used: parseFloat(statUsed.dataset.v || used), free: parseFloat(statFree.dataset.v || free), safe: parseFloat(statSafe.dataset.v || safeTotal) };
    var s0 = performance.now();
    (function step(now) {
      var p = ease(Math.min(1, (now - s0) / 900));
      apply({ used: from.used + (target.used - from.used) * p, free: from.free + (target.free - from.free) * p, safe: from.safe + (target.safe - from.safe) * p });
      if (p < 1) requestAnimationFrame(step);
    })(s0);
  }
  function apply(v) {
    statUsed.textContent = fmt(v.used); statUsed.dataset.v = v.used;
    statFree.textContent = fmt(v.free); statFree.dataset.v = v.free;
    statSafe.textContent = fmt(v.safe); statSafe.dataset.v = v.safe;
    if (ringArc) { var C = 56.55; ringArc.style.strokeDashoffset = C - C * (v.free / TOTAL); }
  }

  /* ---------- breadcrumbs / zoom ---------- */
  function crumbsRender() {
    var chain = []; for (var x = view; x; x = x.parent) chain.unshift(x);
    crumbs.innerHTML = '';
    chain.forEach(function (n, i) {
      var b = document.createElement('button'); b.type = 'button'; b.textContent = n.name; b.disabled = i === chain.length - 1;
      b.addEventListener('click', function () { zoom(n); });
      crumbs.appendChild(b);
      if (i < chain.length - 1) { var s = document.createElement('span'); s.textContent = '›'; crumbs.appendChild(s); }
    });
  }
  function zoom(node) { if (node === view) return; view = node; hover = null; tip.hidden = true; relayout(true); kick(); }

  /* ---------- input ---------- */
  function hit(ev) {
    var b = canvas.getBoundingClientRect();
    var px = ev.clientX - b.left, py = ev.clientY - b.top;
    for (var i = cells.length - 1; i >= 0; i--) { var r = cells[i].r; if (px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) return cells[i]; }
    return null;
  }
  canvas.addEventListener('mousemove', function (ev) {
    if (scanned < 1) return;
    var c = hit(ev);
    if (c !== hover) { hover = c; kick(); }
    if (c) {
      tip.hidden = false;
      tip.innerHTML = '<b>' + esc(c.name) + '</b><span>' + esc(pathOf(c.parent || c)) + '</span><em>' + fmt(c.size) + '</em>' +
        (c.safe ? '<i class="v safe">Safe to delete</i>' : (c.kind === 'app' ? '<i class="v never">Never</i>' : c.kind === 'doc' ? '<i class="v caution">Check first</i>' : '<i class="v usually">Usually safe</i>'));
      var b = host.getBoundingClientRect();
      var tx = ev.clientX - b.left + 14, ty = ev.clientY - b.top + 14;
      if (tx + 260 > b.width) tx = ev.clientX - b.left - 274;
      tip.style.transform = 'translate(' + tx + 'px,' + ty + 'px)';
    } else tip.hidden = true;
  });
  canvas.addEventListener('mouseleave', function () { hover = null; tip.hidden = true; kick(); });
  canvas.addEventListener('click', function (ev) {
    if (scanned < 1) return;
    var c = hit(ev); if (!c) return;
    /* zoom to the child of the current view that contains the cell */
    var target = c; while (target.parent && target.parent !== view) target = target.parent;
    if (target === view || target.leaf) return;
    zoom(target);
  });
  function esc(s) { return s.replace(/[&<>]/g, function (m) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[m]; }); }

  /* ---------- clean ---------- */
  cleanBtn.addEventListener('click', function () {
    if (scanned < 1) return;
    if (!cleaned) {
      (function mark(n) { if (n.safe) { n.gone = true; return; } if (n.children) n.children.forEach(mark); })(root);
      (function recount(n) { if (n.leaf) return n.gone ? 0 : n.size; var s = 0; n.children.forEach(function (c) { s += c.gone ? 0 : recount(c); }); n.size = s; return s; })(root);
      used = root.size; free = TOTAL - used; cleaned = true;
      statState.textContent = 'Moved ' + fmt(safeTotal) + ' to the Trash';
      cleanBtn.textContent = 'Reset demo';
      host.classList.add('cleaned');
    } else {
      root = build(); view = root; used = USED; free = TOTAL - USED; cleaned = false;
      statState.textContent = 'Scan complete, 20.4 s';
      cleanBtn.textContent = 'Clean safe items';
      host.classList.remove('cleaned');
    }
    if (view !== root && view.gone) view = root;
    relayout(true); stats(true); kick();
  });

  /* ---------- theme changes ---------- */
  new MutationObserver(function () { readColors(); kick(); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () { readColors(); kick(); });

  /* ---------- go ---------- */
  readColors();
  resize();
  apply({ used: used, free: free, safe: safeTotal });
  window.addEventListener('resize', function () { resize(); kick(); });
  var started = false;
  function start() { if (started) return; started = true; t0 = performance.now(); kick(); }
  if ('IntersectionObserver' in window && !reduce) {
    var io = new IntersectionObserver(function (en) { if (en[0].isIntersecting) { start(); io.disconnect(); } }, { threshold: 0.25 });
    io.observe(host);
    setTimeout(start, 1500); /* in case it is already in view and the observer is slow */
  } else start();
})();

/* Menu bar cell: the ring drains as the disk fills, a notification arrives, one click cleans. */
(function () {
  var cell = document.getElementById('mbdemo');
  if (!cell) return;
  var sec = cell.closest('.mbsec');
  function phase(n) { if (sec) sec.setAttribute('data-on', n); }
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var item = cell.querySelector('.mb-item');
  var arc = cell.querySelector('.mb-ring .arc');
  var freeEls = cell.querySelectorAll('[data-mb=free],[data-mb=free2]');
  var note = cell.querySelector('.mb-note');
  var clean = cell.querySelector('.mb-clean');
  var replay = cell.querySelector('.mb-replay');
  var status = cell.querySelector('[data-mb=status]');
  var line = cell.querySelector('.spark-line'), up = cell.querySelector('.spark-up'), fill = cell.querySelector('.spark-fill');
  var TOTAL = 494, WARN = 40, CRIT = 16, START = 120, LOW = 14, AFTER = 52;
  var C = 53.4;
  var drops = [120, 108, 96, 82, 64, 41, 14];
  var svg = cell.querySelector('.mb-spark');
  var SW = 300, SH = 90;
  function Y(v) { return SH - 8 - (v / 130) * (SH - 16); }
  function pathOf(vals, x0, x1) {
    var n = vals.length, d = '';
    vals.forEach(function (v, i) { d += (i ? ' L' : 'M') + (x0 + (x1 - x0) * i / (n - 1)).toFixed(1) + ' ' + Y(v).toFixed(1); });
    return d;
  }
  function buildPaths() {
    SW = svg.clientWidth || 300; SH = svg.clientHeight || 90;
    svg.setAttribute('viewBox', '0 0 ' + SW + ' ' + SH);
    var x0 = 16, xMid = SW * 0.78, x1 = SW - 16;
    var dropPath = pathOf(drops, x0, xMid);
    line.setAttribute('d', dropPath);
    up.setAttribute('d', 'M' + xMid.toFixed(1) + ' ' + Y(14).toFixed(1) + ' L' + x1.toFixed(1) + ' ' + Y(AFTER).toFixed(1));
    fill.setAttribute('d', dropPath + ' L' + xMid.toFixed(1) + ' ' + SH + ' L' + x0 + ' ' + SH + ' Z');
  }
  buildPaths();
  window.addEventListener('resize', buildPaths);

  function setFree(v) {
    freeEls.forEach(function (e) { e.textContent = Math.round(v) + ' GB'; });
    arc.style.strokeDashoffset = C - C * (v / TOTAL);
    item.classList.toggle('warn', v < WARN && v >= CRIT);
    item.classList.toggle('crit', v < CRIT);
  }
  function ease(p) { return 1 - Math.pow(1 - p, 3); }
  function tween(from, to, dur, onStep, done) {
    if (reduce) { onStep(to, 1); if (done) done(); return; }
    var t0 = performance.now();
    (function step(now) {
      var p = Math.min(1, (now - t0) / dur), e = ease(p);
      onStep(from + (to - from) * e, e);
      if (p < 1) requestAnimationFrame(step); else if (done) done();
    })(t0);
  }
  var running = false, timers = [];
  var visible = false, autoTimer = null;
  function later(fn, ms) { if (reduce) { fn(); } else timers.push(setTimeout(fn, ms)); }
  function reset() {
    timers.forEach(clearTimeout); timers = []; clearTimeout(autoTimer);
    note.hidden = true; note.classList.remove('in');
    replay.hidden = true;
    line.style.strokeDashoffset = 1; up.style.strokeDashoffset = 1; up.style.opacity = 0; fill.style.opacity = 0;
    status.textContent = 'Free space, last 7 days';
    phase(0);
    setFree(START);
  }
  function play() {
    if (running) return; running = true;
    reset();
    phase(1);
    fill.style.opacity = '';
    tween(START, LOW, 3200, function (v, e) { setFree(v); line.style.strokeDashoffset = 1 - e; }, function () {
      status.textContent = 'Below ' + CRIT + ' GB: a local notification, no cloud';
      phase(2);
      later(function () { note.hidden = false; requestAnimationFrame(function () { note.classList.add('in'); }); }, 250);
      running = false;
      /* if nobody clicks Clean, do it for them after a pause, then loop */
      autoTimer = setTimeout(function () { if (visible && !running && !note.hidden) doClean(true); }, 4200);
    });
  }
  function doClean(auto) {
    if (running) return; running = true; clearTimeout(autoTimer);
    note.classList.remove('in');
    later(function () { note.hidden = true; }, 500);
    status.textContent = 'Moving 38.3 GB of safe items to the Trash';
    phase(3);
    up.style.opacity = 1;
    tween(LOW, AFTER, 1100, function (v, e) { setFree(v); up.style.strokeDashoffset = 1 - e; }, function () {
      status.textContent = 'Done. ' + AFTER + ' GB free.';
      replay.hidden = false; running = false;
      autoTimer = setTimeout(function () { if (visible && !running) play(); }, auto ? 3500 : 6000);
    });
  }
  clean.addEventListener('click', function () { doClean(false); });
  replay.addEventListener('click', play);
  reset();
  if ('IntersectionObserver' in window && !reduce) {
    var io = new IntersectionObserver(function (en) {
      visible = en[0].isIntersecting;
      if (visible) { if (!running) { clearTimeout(autoTimer); autoTimer = setTimeout(play, 400); } }
      else { clearTimeout(autoTimer); }
    }, { threshold: 0.45 });
    io.observe(cell);
  } else play();
})();
