"""The second-screen page (served by webscreen.py). Self-contained: no external files, works offline."""

PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b0d12">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Sporterlay</title>
<style>
:root {
  --bg: #0b0d12; --panel: #161a23; --panel2: #1d222d; --line: rgba(255,255,255,.08);
  --text: #fff; --label: #a9aeb9; --dim: #6b7180;
  --hr: #ff6060; --green: #50c35a; --amber: #ffcd3c; --red: #f0321e; --blue: #5ac8fa;
  --gap: clamp(6px, 1.6vmin, 14px);
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text); }
body {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; font-weight: 600;
  font-variant-numeric: tabular-nums; -webkit-tap-highlight-color: transparent; user-select: none;
  padding: max(var(--gap), env(safe-area-inset-top)) max(var(--gap), env(safe-area-inset-right))
           max(var(--gap), env(safe-area-inset-bottom)) max(var(--gap), env(safe-area-inset-left));
  overflow: hidden;
}
#app { height: 100%; display: grid; gap: var(--gap);
  grid-template-columns: 1fr; grid-template-rows: auto auto auto auto minmax(0, 1fr);
  grid-template-areas: "top" "power" "workout" "metrics" "profile"; }
#app.noworkout { grid-template-rows: auto auto 1fr; grid-template-areas: "top" "power" "metrics"; }
@media (orientation: landscape) {
  #app { grid-template-columns: 1fr 1.15fr; grid-template-rows: auto auto minmax(0, 1fr);
    grid-template-areas: "top top" "power workout" "metrics profile"; }
  #app.noworkout { grid-template-columns: 1fr 1fr; grid-template-rows: auto 1fr;
    grid-template-areas: "top top" "power metrics"; }
}
.panel { background: var(--panel); border-radius: 14px; padding: var(--gap); min-width: 0; min-height: 0; }
.label { color: var(--label); font-size: clamp(10px, 1.9vmin, 15px); letter-spacing: .06em; text-transform: uppercase; }
.unit { color: var(--label); font-size: .42em; margin-left: .12em; }

/* top row */
#top { grid-area: top; display: flex; align-items: center; gap: 8px; min-width: 0; }
#status { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  color: var(--label); font-size: clamp(12px, 2.4vmin, 18px); }
#music { color: #1ed760; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 45%;
  font-size: clamp(12px, 2.4vmin, 18px); }
.btn { background: var(--panel2); color: var(--label); border: 0; border-radius: 999px; padding: 6px 12px;
  font: inherit; font-size: clamp(11px, 2vmin, 15px); cursor: pointer; flex: none; }
.btn.on { color: var(--text); background: #2b3240; }
#dot { width: 10px; height: 10px; border-radius: 50%; background: var(--green); flex: none; }
#dot.off { background: var(--red); }

/* power */
#power { grid-area: power; display: flex; align-items: stretch; gap: var(--gap); }
#powerMain { flex: 1; display: flex; flex-direction: column; justify-content: center; min-width: 0; }
#powerVal { font-size: clamp(64px, 19vmin, 200px); font-weight: 800; line-height: .95; letter-spacing: -.02em; }
#powerSub { display: flex; gap: 1.2em; }
#wbal { width: clamp(46px, 9vmin, 80px); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; }
#batt { position: relative; width: 62%; height: clamp(50px, 11vmin, 110px); border: 2px solid rgba(255,255,255,.7); border-radius: 6px; }
#batt::before { content: ""; position: absolute; top: -7px; left: 32%; width: 36%; height: 5px; background: rgba(255,255,255,.7); border-radius: 2px; }
#battFill { position: absolute; left: 3px; right: 3px; bottom: 3px; border-radius: 3px; background: var(--green); height: 0; }
#wbalPct { font-size: clamp(14px, 3vmin, 24px); }

/* workout */
#workout { grid-area: workout; display: flex; flex-direction: column; gap: calc(var(--gap) * .7); }
#wHead { display: flex; align-items: center; gap: var(--gap); }
#target { border-radius: 12px; padding: .1em .35em; font-size: clamp(34px, 9vmin, 92px); font-weight: 800; line-height: 1.1;
  min-width: 2.6em; text-align: center; background: #808080; }
#target.free { font-size: clamp(18px, 4.5vmin, 40px); padding: .5em .6em; }
#left { margin-left: auto; text-align: right; }
#leftVal { font-size: clamp(34px, 9vmin, 92px); font-weight: 800; line-height: 1; }
#wLabel { font-size: clamp(16px, 3.6vmin, 30px); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#wLabel.msg { color: var(--amber); white-space: normal; display: -webkit-box; -webkit-line-clamp: 4;
  -webkit-box-orient: vertical; font-size: clamp(14px, 3vmin, 24px); }
#wExtra { color: var(--label); font-size: clamp(12px, 2.4vmin, 18px); min-height: 1.2em; }
#bar { height: clamp(6px, 1.2vmin, 10px); background: rgba(255,255,255,.12); border-radius: 99px; overflow: hidden; }
#barFill { height: 100%; width: 0; border-radius: 99px; }
#wFoot { display: flex; justify-content: space-between; gap: 1em; font-size: clamp(12px, 2.4vmin, 18px); }
#next { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#wState { color: var(--amber); white-space: nowrap; }
#done { font-size: clamp(22px, 5vmin, 44px); text-align: center; padding: .4em 0; }

/* metrics */
#metrics { grid-area: metrics; display: grid; gap: var(--gap); grid-template-columns: repeat(3, 1fr); grid-auto-rows: 1fr; min-height: 0; }
.metric { display: flex; flex-direction: column; justify-content: center; align-items: center; padding: calc(var(--gap) * 1.2) 4px;
  container-type: inline-size; }
.metric .v { font-size: clamp(20px, min(26cqw, 9vmin), 84px); font-weight: 800; line-height: 1.05; white-space: nowrap; }
#hr .v { color: var(--hr); }
#gear .v.gear { color: var(--amber); } #gear .v.erg { color: var(--label); } #gear .v.iso, #gear .v.torque { color: var(--blue); }

/* profile */
#profile { grid-area: profile; padding: calc(var(--gap) * .6); display: flex; flex-direction: column; }
#prof { width: 100%; flex: 1 1 0; min-height: 70px; max-height: 340px; display: block; margin: auto 0; }
#remaining { display: flex; justify-content: space-between; color: var(--label); font-size: clamp(11px, 2.2vmin, 16px); margin-top: 4px; }

/* offline + card overlays */
.cover { position: fixed; inset: 0; display: none; align-items: center; justify-content: center; padding: 16px;
  background: rgba(5,6,9,.82); backdrop-filter: blur(4px); z-index: 5; }
.cover.show { display: flex; }
#offline .box { text-align: center; color: var(--label); font-size: clamp(16px, 3.4vmin, 26px); }
#card .box { background: var(--panel); border-radius: 16px; padding: clamp(14px, 3vmin, 28px); width: min(760px, 100%); max-height: 100%; overflow: auto; }
#cTitle { font-size: clamp(18px, 4vmin, 30px); }
#cSub { color: var(--label); font-size: clamp(12px, 2.4vmin, 17px); margin: 4px 0 14px; }
#cStats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px 8px; }
@media (max-width: 480px) { #cStats { grid-template-columns: repeat(2, 1fr); } }
#cStats .v { font-size: clamp(22px, 5vmin, 40px); font-weight: 800; }
#cZones { display: flex; height: 12px; border-radius: 99px; overflow: hidden; margin: 16px 0 8px; background: rgba(255,255,255,.1); }
#cZoneLegend { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px 10px; font-size: clamp(11px, 2.2vmin, 15px); }
#cZoneLegend span::before { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; background: var(--c); }
#cFoot { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 6px 16px; margin-top: 14px; font-size: clamp(12px, 2.4vmin, 17px); }
#cNote { color: var(--amber); } #cStatus.ok { color: var(--green); }
#cClose { margin-top: 14px; width: 100%; }
#tip { position: fixed; left: 50%; bottom: 12px; transform: translateX(-50%); background: var(--panel2); color: var(--label);
  border-radius: 12px; padding: 8px 14px; font-size: 13px; display: none; z-index: 4; max-width: calc(100% - 24px); }
#tip.show { display: block; }
</style>
</head>
<body>
<div id="app" class="noworkout">
  <div id="top">
    <div id="dot" class="off" title="connection"></div>
    <div id="status">Connecting…</div>
    <div id="music"></div>
    <button class="btn" id="sound" title="Play the interval beeps on this device">🔇 Beeps</button>
    <button class="btn" id="fs" title="Full screen">⛶</button>
  </div>

  <div id="power" class="panel">
    <div id="powerMain">
      <div class="label" id="powerLabel">Power</div>
      <div id="powerVal">--<span class="unit">W</span></div>
      <div id="powerSub" class="label"><span id="avg"></span><span id="wkg"></span></div>
    </div>
    <div id="wbal"><div id="batt"><div id="battFill"></div></div><div id="wbalPct">--</div><div class="label">W′</div></div>
  </div>

  <div id="workout" class="panel" style="display:none">
    <div id="wActive">
      <div id="wHead">
        <div id="target">--</div>
        <div id="left"><div id="leftVal">--</div><div class="label">Interval left</div></div>
      </div>
      <div id="wLabel"></div>
      <div id="wExtra"></div>
      <div id="bar"><div id="barFill"></div></div>
      <div id="wFoot"><span id="next"></span><span id="wState"></span></div>
    </div>
    <div id="done" style="display:none">Workout complete</div>
  </div>

  <div id="metrics">
    <div class="panel metric" id="hr"><div class="v">--</div><div class="label">Heart rate</div></div>
    <div class="panel metric" id="cad"><div class="v">--</div><div class="label">Cadence</div></div>
    <div class="panel metric" id="spd"><div class="v">--</div><div class="label">Speed</div></div>
    <div class="panel metric" id="time"><div class="v">0:00</div><div class="label">Time</div></div>
    <div class="panel metric" id="dist"><div class="v">0.0</div><div class="label">Distance</div></div>
    <div class="panel metric" id="gear"><div class="v gear">--</div><div class="label">Gear</div></div>
  </div>

  <div id="profile" class="panel" style="display:none">
    <canvas id="prof"></canvas>
    <div id="remaining"><span id="woName"></span><span id="remain"></span></div>
  </div>
</div>

<div id="offline" class="cover show"><div class="box">Waiting for Sporterlay…<br><small>Is it running, with the second screen on?</small></div></div>
<div id="card" class="cover"><div class="box">
  <div id="cTitle"></div><div id="cSub"></div>
  <div id="cStats"></div>
  <div id="cZones"></div><div id="cZoneLegend"></div>
  <div id="cFoot"><span id="cTarget"></span><span id="cNote"></span><span id="cStatus"></span></div>
  <button class="btn" id="cClose">Close</button>
</div></div>
<div id="tip"></div>

<script>
"use strict";
const ZONES = [[0.60, "#808080"], [0.76, "#3287ff"], [0.90, "#50c35a"], [1.05, "#ffcd3c"], [1.19, "#ff6e32"], [99, "#f0321e"]];
const FREE = "#6e6e78";
const zoneColor = f => f == null ? FREE : (ZONES.find(z => f < z[0]) || ZONES[5])[1];
const $ = id => document.getElementById(id);
const fmt = s => { s = Math.round(s || 0); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(x).padStart(2, "0")}` : `${m}:${String(x).padStart(2, "0")}`; };
const val = (v, d = "--") => v == null ? d : v;
const setV = (id, html) => { const e = $(id).querySelector(".v"); if (e.innerHTML !== html) e.innerHTML = html; };
const store = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
                set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} } };

let wo = null, trace = [], last = null, lastMsg = 0, cardClosed = null;

// ---- connection ---------------------------------------------------------------------
function connect() {
  const es = new EventSource("/events");
  es.addEventListener("workout", e => { wo = JSON.parse(e.data); trace = wo ? wo.trace.slice() : []; lastMsg = Date.now(); drawProfile(); });
  es.addEventListener("state", e => {
    lastMsg = Date.now();
    $("offline").classList.remove("show"); $("dot").classList.remove("off");
    render(JSON.parse(e.data));
  });
}
setInterval(() => {
  const off = Date.now() - lastMsg > 3000;
  $("offline").classList.toggle("show", off);
  $("dot").classList.toggle("off", off);
}, 500);
connect();

// ---- rendering ----------------------------------------------------------------------
function render(s) {
  last = s;
  $("status").textContent = s.status || (s.connected ? "" : "Trainer not connected");
  $("music").textContent = s.music || "";
  const pv = `${val(s.power)}<span class="unit">W</span>`;
  if ($("powerVal").innerHTML !== pv) $("powerVal").innerHTML = pv;
  $("powerLabel").textContent = s.power_avg_s > 1 ? `Power (${s.power_avg_s}s)` : "Power";
  $("avg").textContent = s.avg_power != null ? `avg ${s.avg_power} W` : "";
  $("wkg").textContent = s.wkg != null ? `${s.wkg.toFixed(1)} W/kg` : "";
  // W′ battery
  $("wbal").style.display = s.show_wbal ? "" : "none";
  if (s.wbal != null) {
    const f = Math.max(0, Math.min(1, s.wbal));
    const col = f > .5 ? "var(--green)" : f > .25 ? "var(--amber)" : "var(--red)";
    const blink = f < .15 && Math.floor(Date.now() / 500) % 2;
    $("battFill").style.height = `calc(${f * 100}% - 6px)`;
    $("battFill").style.background = blink ? "rgba(255,255,255,.25)" : col;
    $("wbalPct").textContent = Math.max(0, Math.round(s.wbal * 100));
  } else { $("battFill").style.height = "0"; $("wbalPct").textContent = "--"; }
  setV("hr", `${val(s.hr)}<span class="unit">bpm</span>`);
  setV("cad", `${val(s.cadence)}<span class="unit">rpm</span>`);
  // the step's target cadence in the label, the value green within 5 rpm (as on the HUD)
  const ct = s.cadence_target;
  $("cad").querySelector(".label").textContent = ct == null ? "Cadence" : `Cadence → ${ct}`;
  $("cad").querySelector(".v").style.color = ct == null || s.cadence == null ? ""
    : Math.abs(s.cadence - ct) <= 5 ? "var(--green)" : "var(--amber)";
  setV("spd", `${s.speed == null ? "--" : s.speed.toFixed(1)}<span class="unit">km/h</span>`);
  setV("time", fmt(s.time));
  setV("dist", `${s.distance.toFixed(1)}<span class="unit">km</span>`);
  const g = $("gear").querySelector(".v");
  g.className = "v " + s.mode;
  g.textContent = s.mode === "iso" ? s.iso_rpm : s.mode === "torque" ? s.torque : s.gear;
  $("gear").querySelector(".label").textContent =
    s.mode === "iso" ? "Iso rpm" : s.mode === "torque" ? "Torque Nm" : s.mode === "erg" ? "ERG" : "Gear";

  const w = s.workout;
  $("app").classList.toggle("noworkout", !w);
  $("workout").style.display = w ? "" : "none";
  $("profile").style.display = w ? "" : "none";
  if (w) {
    $("wActive").style.display = w.finished ? "none" : "";
    $("done").style.display = w.finished ? "" : "none";
    if (!w.finished) {
      const col = zoneColor(w.frac);
      const t = $("target");
      t.style.background = col;
      t.classList.toggle("free", w.target == null);
      t.innerHTML = w.target == null ? (w.label || "Free ride").toUpperCase() : `${w.target}<span class="unit" style="color:#fff">W</span>`;
      $("leftVal").textContent = fmt(w.left);
      $("wLabel").textContent = w.message || w.label;
      $("wLabel").classList.toggle("msg", !!w.message);
      $("wExtra").textContent = (w.message ? w.label + "   " : "") + (w.extra || `${w.index + 1} / ${w.count}`);
      $("barFill").style.width = `${w.seg_duration ? 100 * w.into / w.seg_duration : 100}%`;
      $("barFill").style.background = col;
      $("next").textContent = w.next ? `NEXT  ${w.next}` : "";
      $("wState").textContent = w.state || "";
    }
    $("woName").textContent = w.name;
    $("remain").textContent = `${fmt(w.remaining)} left`;
    if (w.trace_point && (!trace.length || w.trace_point[0] > trace[trace.length - 1][0])) trace.push(w.trace_point);
    drawProfile();
  }
  renderCard(s.card);
  cue(s.cue);
}

// ---- workout profile (same drawing as the HUD) -------------------------------------------
const cv = $("prof");
function drawProfile() {
  if (!wo || !last || !last.workout) return;
  const dpr = window.devicePixelRatio || 1, W = cv.clientWidth, H = cv.clientHeight;
  if (!W || !H) return;
  if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) { cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); }
  const c = cv.getContext("2d");
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  c.clearRect(0, 0, W, H);
  const top = 10, gh = H - top, total = wo.duration || 1;
  const peak = Math.max(1, ...wo.segments.map(s => Math.max(s[1] || 0, s[2] || 0)));
  const ymax = Math.max(1.3, peak * 1.08);
  const px = t => W * t / total, py = f => top + gh - gh * Math.min(f, ymax) / ymax;
  let t0 = 0;
  for (const [d, a, b] of wo.segments) {
    const xa = px(t0), xb = px(t0 + d), gap = xb - xa > 1.5 ? .5 : 0;
    if (a == null) { c.fillStyle = FREE; c.fillRect(xa, py(.5), Math.max(xb - xa - gap, .5), top + gh - py(.5)); }
    else {
      // ramps: thin slices for the zone gradient, merged into one shape per colour (no seams)
      const n = Math.abs(a - b) > 1e-6 ? Math.max(1, Math.floor((xb - xa) / 3)) : 1;
      let k0 = 0;
      for (let k = 0; k < n; k++) {
        const col = zoneColor(a + (b - a) * (k + .5) / n);
        if (k < n - 1 && zoneColor(a + (b - a) * (k + 1.5) / n) === col) continue;
        const fa = k0 / n, fb = (k + 1) / n, pa = a + (b - a) * fa, pb = a + (b - a) * fb;
        const x1 = xa + (xb - xa) * fa, x2 = xa + (xb - xa) * fb + (k === n - 1 ? -gap : .6);
        c.fillStyle = col;
        c.beginPath(); c.moveTo(x1, top + gh); c.lineTo(x1, py(pa)); c.lineTo(x2, py(pb)); c.lineTo(x2, top + gh); c.fill();
        k0 = k + 1;
      }
    }
    t0 += d;
  }
  c.setLineDash([4, 4]); c.strokeStyle = "rgba(255,255,255,.3)"; c.lineWidth = 1;
  c.beginPath(); c.moveTo(0, py(1)); c.lineTo(W, py(1)); c.stroke();
  if (wo.plan.length > 1) {
    c.strokeStyle = "rgba(90,200,250,.85)"; c.lineWidth = 1.5; c.beginPath();
    wo.plan.forEach(([t, f], i) => { const x = px(t), y = top + gh - gh * Math.max(0, f); i ? c.lineTo(x, y) : c.moveTo(x, y); });
    c.stroke();
  }
  c.setLineDash([]);
  const xpos = px(last.workout.elapsed);
  c.fillStyle = "rgba(0,0,0,.45)"; c.fillRect(0, top, xpos, gh);
  if (trace.length > 1) {
    c.strokeStyle = "rgba(255,255,255,.9)"; c.lineWidth = 1.6; c.beginPath();
    trace.forEach(([t, w], i) => { const x = px(t), y = py(w / wo.ftp); i ? c.lineTo(x, y) : c.moveTo(x, y); });
    c.stroke();
  }
  c.strokeStyle = "#fff"; c.lineWidth = 2; c.beginPath(); c.moveTo(xpos, top - 2); c.lineTo(xpos, top + gh); c.stroke();
  c.fillStyle = "#fff"; c.beginPath(); c.moveTo(xpos - 5, 0); c.lineTo(xpos + 5, 0); c.lineTo(xpos, top - 1); c.fill();
}
new ResizeObserver(drawProfile).observe(cv);

// ---- end-of-ride card --------------------------------------------------------------------
function renderCard(card) {
  const key = card ? `${card.start}` : null;
  const show = !!card && cardClosed !== key;
  $("card").classList.toggle("show", show);
  if (!show) return;
  const d = new Date(card.start * 1000);
  $("cTitle").textContent = card.name ? `Ride done · ${card.name}` : "Ride done";
  $("cSub").textContent = `${d.toLocaleString([], { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}  ·  ${fmt(card.moving_s)}  ·  ${card.distance_km.toFixed(1)} km`;
  const wb = card.wbal_min == null ? "--" : Math.max(0, Math.round(card.wbal_min * 100));
  const stats = [["Norm. power", `${card.np}<span class="unit">W</span>`], ["Avg power", `${card.avg_power}<span class="unit">W</span>`],
    ["Intensity", card.intensity.toFixed(2)], ["Load (TSS)", card.tss], ["Energy", `${card.kj}<span class="unit">kJ</span>`],
    ["HR avg / max", card.avg_hr ? `${card.avg_hr}/${card.max_hr}` : "--"], ["Cadence", card.avg_cadence ? `${card.avg_cadence}<span class="unit">rpm</span>` : "--"],
    ["Lowest W′", `${wb}<span class="unit">%</span>`]];
  const html = stats.map(([l, v]) => `<div><div class="v">${v}</div><div class="label">${l}</div></div>`).join("");
  if ($("cStats").innerHTML !== html) $("cStats").innerHTML = html;
  const total = card.zones.reduce((a, b) => a + b, 0) || 1;
  $("cZones").innerHTML = card.zones.map((z, i) => `<div style="width:${100 * z / total}%;background:${ZONES[i][1]}"></div>`).join("");
  $("cZoneLegend").innerHTML = card.zones.map((z, i) => `<span style="--c:${ZONES[i][1]}">Z${i + 1}  ${fmt(z)}</span>`).join("");
  $("cTarget").textContent = card.on_target != null ? `On target ${Math.round(card.on_target * 100)} %` : "";
  $("cNote").textContent = card.note || "";
  $("cStatus").textContent = card.status;
  $("cStatus").className = card.status.startsWith("Uploaded") ? "ok" : "";
}
$("cClose").onclick = () => { if (last && last.card) cardClosed = `${last.card.start}`; renderCard(last && last.card); };

// ---- beeps on this device (needs one tap: browsers block sound until then) ---------------------
const TONES = { tick: [[880, .12]], up: [[1320, .45]], down: [[660, .45]],
  finish: [[880, .15], [0, .05], [1100, .15], [0, .05], [1320, .4]], heads_up: [[660, .08], [0, .07], [660, .08]] };
let audio = null, lastCue = null;
function play(name) {
  if (!audio || !TONES[name]) return;
  let t = audio.currentTime + .02;
  for (const [f, d] of TONES[name]) {
    if (f > 0) {
      const o = audio.createOscillator(), g = audio.createGain();
      o.frequency.value = f; o.connect(g); g.connect(audio.destination);
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(.45, t + .01);
      g.gain.setValueAtTime(.45, t + d - .01); g.gain.linearRampToValueAtTime(0, t + d);
      o.start(t); o.stop(t + d);
    }
    t += d;
  }
}
function cue(c) {
  if (!c) return;
  const [seq, name] = c;
  if (lastCue !== null && seq !== lastCue && name) play(name);
  lastCue = seq;
}
function setSound(on) {
  if (on && !audio) { const AC = window.AudioContext || window.webkitAudioContext; audio = AC ? new AC() : null; }
  if (audio) on ? audio.resume() : audio.suspend();
  $("sound").textContent = on ? "🔊 Beeps" : "🔇 Beeps";
  $("sound").classList.toggle("on", on);
  store.set("beeps", on ? "1" : "0");
}
$("sound").onclick = () => setSound(!(audio && audio.state === "running"));

// ---- full screen and keeping the screen on ------------------------------------------------
$("fs").onclick = () => {
  const el = document.documentElement;
  if (document.fullscreenElement) document.exitFullscreen();
  else if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
};
if (!window.isSecureContext || !("wakeLock" in navigator)) {
  if (store.get("tipDone") !== "1") {
    $("tip").textContent = "Tip: raise this device's screen timeout so it stays on while you ride. Tap to hide.";
    $("tip").classList.add("show");
    $("tip").onclick = () => { $("tip").classList.remove("show"); store.set("tipDone", "1"); };
  }
} else {
  const lock = () => navigator.wakeLock.request("screen").catch(() => {});
  lock();
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") lock(); });
}
</script>
</body>
</html>
"""
