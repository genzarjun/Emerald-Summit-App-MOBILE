#!/usr/bin/env python3
"""Build a 3D, draggable view of the graphify code graph.

  python3 .claude/skills/checkup/scripts/graph3d.py      -> graphify-out/graph3d.html

Reads graphify-out/graph.json. Run it after `graphify update .`.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
SRC = ROOT / "graphify-out" / "graph.json"
OUT = ROOT / "graphify-out" / "graph3d.html"
LIB = "https://cdn.jsdelivr.net/npm/3d-force-graph@1.80.0/dist/3d-force-graph.min.js"

g = json.loads(SRC.read_text())
links_in = g.get("links") or g.get("edges")
degree = {}
for e in links_in:
    for end in (e["source"], e["target"]):
        degree[end] = degree.get(end, 0) + 1

nodes = [{
    "id": n["id"],
    "label": n.get("label", n["id"]),
    "file": n.get("source_file") or "",
    "loc": n.get("source_location") or "",
    "c": n.get("community", -1),
    "cn": n.get("community_name") or "",
    "d": degree.get(n["id"], 0),
} for n in g["nodes"]]
ids = {n["id"] for n in nodes}
links = [{"source": e["source"], "target": e["target"], "r": e.get("relation", "")}
         for e in links_in if e["source"] in ids and e["target"] in ids]

data = json.dumps({"nodes": nodes, "links": links,
                   "commit": (g.get("built_at_commit") or "")[:8]}).replace("</", "<\\/")

HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Emerald Summit code map</title>
<style>
  :root { --bg:#08080f; --panel:rgba(18,18,30,.88); --line:rgba(255,255,255,.12);
          --text:#e8e8f0; --muted:#9a9ab0; --accent:#7ee0c3; }
  * { box-sizing:border-box; }
  html, body { margin:0; height:100%; background:var(--bg); color:var(--text);
               font:13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; overflow:hidden; }
  #graph { position:fixed; inset:0; }
  .panel { position:fixed; background:var(--panel); border:1px solid var(--line); border-radius:10px;
           padding:12px 14px; backdrop-filter:blur(8px); }
  #controls { top:16px; left:16px; width:300px; max-width:calc(100vw - 32px); }
  #controls h1 { font-size:14px; margin:0 0 2px; font-weight:600; }
  #controls .sub { color:var(--muted); margin-bottom:10px; }
  input[type=search] { width:100%; padding:7px 9px; border-radius:7px; border:1px solid var(--line);
                       background:rgba(255,255,255,.06); color:var(--text); font:inherit; }
  label { display:flex; gap:8px; align-items:center; margin-top:8px; color:var(--muted); cursor:pointer; }
  #results { margin-top:6px; max-height:180px; overflow:auto; }
  #results div, #info .conn { padding:3px 4px; border-radius:5px; cursor:pointer; }
  #results div:hover, #info .conn:hover { background:rgba(255,255,255,.08); }
  #info { top:16px; right:16px; width:340px; max-width:calc(100vw - 32px); max-height:calc(100vh - 32px);
          overflow:auto; display:none; }
  #info h2 { font-size:15px; margin:0 0 4px; word-break:break-word; }
  #info .meta { color:var(--muted); margin-bottom:10px; word-break:break-all; }
  #info .rel { color:var(--accent); font-size:11px; margin-right:6px; }
  #info .close { float:right; cursor:pointer; color:var(--muted); font-size:16px; line-height:1; }
  #hint { left:16px; bottom:16px; color:var(--muted); padding:8px 12px; }
  .dot { display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:6px; }
  @media (max-width:640px) { #info { top:auto; bottom:16px; left:16px; right:16px; width:auto; max-height:45vh; }
                             #hint { display:none; } }
</style>
</head>
<body>
<div id="graph"></div>

<div id="controls" class="panel">
  <h1>Emerald Summit code map</h1>
  <div class="sub" id="stats"></div>
  <input type="search" id="q" placeholder="Find a class, screen or file">
  <div id="results"></div>
  <label><input type="checkbox" id="hideExt" checked> Hide outside packages (Flutter, dart:, pub)</label>
  <label><input type="checkbox" id="hideNoise" checked> Hide unnamed nodes</label>
  <label><input type="checkbox" id="spin"> Slowly rotate</label>
</div>

<div id="info" class="panel"></div>
<div id="hint" class="panel">Drag the background to rotate. Scroll to zoom. Drag a dot to move it. Click a dot for details.</div>

<script id="data" type="application/json">__DATA__</script>
<script src="__LIB__"></script>
<script>
const RAW = JSON.parse(document.getElementById('data').textContent);
const PALETTE = ['#ff7eb6','#7ee0c3','#ffd166','#6ec6ff','#b69cff','#ff9f68','#9be564',
                 '#ff6b6b','#5ad1e6','#f5a3ff','#c9e265','#ffb3c7','#8fb8ff','#ffc078'];
const color = (c) => c < 0 ? '#8a8aa0' : PALETTE[c % PALETTE.length];
const byId = new Map(RAW.nodes.map(n => [n.id, n]));
const neighbors = new Map(RAW.nodes.map(n => [n.id, []]));
RAW.links.forEach(l => {
  neighbors.get(l.source)?.push({ id: l.target, r: l.r, dir: 'out' });
  neighbors.get(l.target)?.push({ id: l.source, r: l.r, dir: 'in' });
});

const isExternal = (n) => !n.file;
const isNoise = (n) => /^[_\\s]*$/.test(n.label);

function visibleData() {
  const hideExt = document.getElementById('hideExt').checked;
  const hideNoise = document.getElementById('hideNoise').checked;
  const keep = new Set(RAW.nodes.filter(n => !(hideExt && isExternal(n)) && !(hideNoise && isNoise(n))).map(n => n.id));
  return {
    nodes: RAW.nodes.filter(n => keep.has(n.id)).map(n => ({ ...n })),
    links: RAW.links.filter(l => keep.has(l.source) && keep.has(l.target)).map(l => ({ ...l })),
  };
}

let highlight = new Set();
const Graph = ForceGraph3D()(document.getElementById('graph'))
  .backgroundColor('#08080f')
  .showNavInfo(false)
  .nodeId('id')
  .nodeLabel(n => `<div style="padding:4px 6px;background:rgba(0,0,0,.75);border-radius:5px">${esc(n.label)}` +
                  (n.file ? `<br><span style="color:#9a9ab0">${esc(n.file)}</span>` : '') + `</div>`)
  .nodeRelSize(2.6)
  .nodeVal(n => 1 + Math.sqrt(n.d))
  .nodeColor(n => highlight.size && !highlight.has(n.id) ? 'rgba(120,120,140,0.25)' : color(n.c))
  .nodeOpacity(0.95)
  .nodeResolution(10)
  .linkColor(l => {
    const s = typeof l.source === 'object' ? l.source : byId.get(l.source);
    return highlight.size && !(highlight.has(s.id) && highlight.has((l.target.id ?? l.target)))
      ? 'rgba(120,120,140,0.06)' : color(s.c);
  })
  .linkOpacity(0.45)
  .linkWidth(0)
  .linkDirectionalParticles(l => highlight.size && highlight.has(l.source.id) && highlight.has(l.target.id) ? 2 : 0)
  .linkDirectionalParticleWidth(1.6)
  .onNodeClick(focusNode)
  .onBackgroundClick(clearFocus)
  .onNodeDragEnd(n => { n.fx = n.x; n.fy = n.y; n.fz = n.z; });  // a dragged dot stays where you drop it

// Each group gets an anchor point spread over a sphere, and a gentle force
// pulls its nodes there, so groups form separate stars instead of one ball.
const groupIds = [...new Set(RAW.nodes.map(n => n.c))];
const groupSize = new Map(groupIds.map(c => [c, RAW.nodes.filter(n => n.c === c).length]));
const anchors = new Map();
groupIds.sort((a, b) => groupSize.get(b) - groupSize.get(a)).forEach((c, i) => {
  const k = groupIds.length, y = 1 - (2 * (i + 0.5)) / k, rad = Math.sqrt(1 - y * y);
  const theta = i * Math.PI * (3 - Math.sqrt(5));            // golden-angle spiral
  const R = 260 + 40 * Math.cbrt(k);
  anchors.set(c, { x: R * rad * Math.cos(theta), y: R * y, z: R * rad * Math.sin(theta) });
});
let simNodes = [];
function groupForce(alpha) {
  for (const n of simNodes) {
    const a = anchors.get(n.c); if (!a) continue;
    n.vx += (a.x - n.x) * 0.06 * alpha; n.vy += (a.y - n.y) * 0.06 * alpha; n.vz += (a.z - n.z) * 0.06 * alpha;
  }
}
groupForce.initialize = (ns) => { simNodes = ns; };
const sameGroup = (l) => (l.source.c ?? byId.get(l.source)?.c) === (l.target.c ?? byId.get(l.target)?.c);
Graph.d3Force('group', groupForce);
Graph.d3Force('charge').strength(-22).distanceMax(140);
Graph.d3Force('link').distance(l => sameGroup(l) ? 16 : 60).strength(l => sameGroup(l) ? 0.5 : 0.003);
// Lay the graph out before the first frame (works even in a background tab),
// then keep a short live phase so dragging a dot still moves its neighbors.
Graph.warmupTicks(220).cooldownTicks(80);
let fitted = false;
function fit() {
  if (fitted) return;
  fitted = true;
  // Frame the whole sphere of groups from outside it.
  const ns = Graph.graphData().nodes;
  const mid = (k) => (Math.min(...ns.map(n => n[k] || 0)) + Math.max(...ns.map(n => n[k] || 0))) / 2;
  const c = { x: mid('x'), y: mid('y'), z: mid('z') };
  const r = Math.max(1, ...ns.map(n => Math.hypot((n.x || 0) - c.x, (n.y || 0) - c.y, (n.z || 0) - c.z)));
  const fov = (Graph.camera().fov || 40) * Math.PI / 180;
  const dist = (r / Math.tan(fov / 2)) * 1.15;
  Graph.cameraPosition({ x: c.x, y: c.y, z: c.z + dist }, c, 0);
}
Graph.onEngineStop(fit);
Graph.graphData(visibleData());
setTimeout(fit, 300);

function esc(s) { return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function stats() {
  const d = Graph.graphData();
  const files = new Set(d.nodes.map(n => n.file).filter(Boolean)).size;
  document.getElementById('stats').textContent =
    `${d.nodes.length} nodes, ${d.links.length} links, ${files} files` + (RAW.commit ? `. Built at ${RAW.commit}` : '');
}

function focusNode(n) {
  const live = Graph.graphData().nodes.find(x => x.id === n.id) || n;
  highlight = new Set([live.id, ...neighbors.get(live.id).map(x => x.id)]);
  document.getElementById('results').innerHTML = '';
  refresh();
  const dist = 260, r = 1 + dist / Math.hypot(live.x || 1, live.y || 1, live.z || 1);
  Graph.cameraPosition({ x: (live.x || 0) * r, y: (live.y || 0) * r, z: (live.z || 0) * r }, live, 900);
  const shown = new Set(Graph.graphData().nodes.map(x => x.id));
  const conns = neighbors.get(live.id)
    .filter(x => shown.has(x.id))
    .sort((a, b) => byId.get(b.id).d - byId.get(a.id).d);
  const info = document.getElementById('info');
  info.style.display = 'block';
  info.innerHTML = `<span class="close" title="Close">×</span>
    <h2><span class="dot" style="background:${color(live.c)}"></span>${esc(live.label)}</h2>
    <div class="meta">${live.file ? esc(live.file) + (live.loc ? ' ' + esc(live.loc) : '') : 'Outside package'}
      ${live.cn ? '<br>Group: ' + esc(live.cn) : ''}<br>${conns.length} connections</div>` +
    conns.slice(0, 80).map(x => `<div class="conn" data-id="${esc(x.id)}"><span class="rel">${x.dir === 'out' ? '→' : '←'} ${esc(x.r)}</span>${esc(byId.get(x.id).label)}</div>`).join('') +
    (conns.length > 80 ? `<div class="meta">and ${conns.length - 80} more</div>` : '');
  info.querySelector('.close').onclick = clearFocus;
  info.querySelectorAll('.conn').forEach(el => el.onclick = () => {
    const target = Graph.graphData().nodes.find(x => x.id === el.dataset.id);
    if (target) focusNode(target);
  });
}

function clearFocus() {
  highlight = new Set();
  document.getElementById('info').style.display = 'none';
  refresh();
}

function refresh() {
  Graph.nodeColor(Graph.nodeColor()).linkColor(Graph.linkColor())
       .linkDirectionalParticles(Graph.linkDirectionalParticles());
}

document.getElementById('q').addEventListener('input', (e) => {
  const q = e.target.value.trim().toLowerCase();
  const box = document.getElementById('results');
  if (q.length < 2) { box.innerHTML = ''; return; }
  const hits = Graph.graphData().nodes
    .filter(n => n.label.toLowerCase().includes(q) || n.file.toLowerCase().includes(q))
    .sort((a, b) => b.d - a.d).slice(0, 12);
  box.innerHTML = hits.length
    ? hits.map(n => `<div data-id="${esc(n.id)}"><span class="dot" style="background:${color(n.c)}"></span>${esc(n.label)}</div>`).join('')
    : '<div style="color:#9a9ab0;cursor:default">No match</div>';
  box.querySelectorAll('[data-id]').forEach(el => el.onclick = () =>
    focusNode(Graph.graphData().nodes.find(n => n.id === el.dataset.id)));
});

['hideExt', 'hideNoise'].forEach(id => document.getElementById(id).addEventListener('change', () => {
  clearFocus(); fitted = false; Graph.graphData(visibleData()); stats(); setTimeout(fit, 300);
}));

let spinTimer = null;
document.getElementById('spin').addEventListener('change', (e) => {
  clearInterval(spinTimer);
  if (!e.target.checked) return;
  let angle = 0;
  const { x, z } = Graph.cameraPosition();
  const dist = Math.hypot(x, z) || 600;
  spinTimer = setInterval(() => {
    angle += Math.PI / 900;
    Graph.cameraPosition({ x: dist * Math.sin(angle), z: dist * Math.cos(angle) });
  }, 16);
});

stats();
window.addEventListener('resize', () => Graph.width(innerWidth).height(innerHeight));
</script>
</body>
</html>
"""

OUT.write_text(HTML.replace("__DATA__", data).replace("__LIB__", LIB))
print(f"wrote {OUT.relative_to(ROOT)}: {len(nodes)} nodes, {len(links)} links")
