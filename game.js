'use strict';

/* =========================================================
   Mensch ärgere Dich nicht – Browser-Version
   Brettgeometrie übernommen aus dem Delphi-Projekt
   (FeldPositionen / ZielfeldPositionen aus Main.pas)
   ========================================================= */

// ---------- Brettgeometrie (12x12-Raster, wie im Delphi-Original) ----------
const FIELD_POS = [
  [1,5],[2,5],[3,5],[4,5],[5,5],      //  0– 4
  [5,4],[5,3],[5,2],[5,1],[6,1],      //  5– 9
  [7,1],[7,2],[7,3],[7,4],[7,5],      // 10–14
  [8,5],[9,5],[10,5],[11,5],[11,6],   // 15–19
  [11,7],[10,7],[9,7],[8,7],[7,7],    // 20–24
  [7,8],[7,9],[7,10],[7,11],[6,11],   // 25–29
  [5,11],[5,10],[5,9],[5,8],[5,7],    // 30–34
  [4,7],[3,7],[2,7],[1,7],[1,6]       // 35–39
];

const GOAL_POS = [
  [[2,6],[3,6],[4,6],[5,6]],          // oben links  (Einlauf von Feld 39)
  [[6,2],[6,3],[6,4],[6,5]],          // oben rechts (Einlauf von Feld 9)
  [[10,6],[9,6],[8,6],[7,6]],         // unten rechts(Einlauf von Feld 19)
  [[6,10],[6,9],[6,8],[6,7]]          // unten links (Einlauf von Feld 29)
];

const HOME_POS = [
  [[1.4,1.4],[2.6,1.4],[1.4,2.6],[2.6,2.6]],     // oben links
  [[9.4,1.4],[10.6,1.4],[9.4,2.6],[10.6,2.6]],   // oben rechts
  [[9.4,9.4],[10.6,9.4],[9.4,10.6],[10.6,10.6]], // unten rechts
  [[1.4,9.4],[2.6,9.4],[1.4,10.6],[2.6,10.6]]    // unten links
];

const START = [0, 10, 20, 30];

// ---------- Farbpalette ----------
// Jeder Spielerplatz (Ecke) kann eine beliebige Palettenfarbe erhalten –
// z. B. Schwarz statt Rot für Menschen mit Rot/Grün-Schwäche.
// Hell-/Dunkelvarianten werden automatisch aus der Grundfarbe berechnet.
const PALETTE = [
  { name: 'Rot',     hex: '#d62828' },
  { name: 'Grün',    hex: '#2e933c' },
  { name: 'Gelb',    hex: '#f2b705' },
  { name: 'Blau',    hex: '#1f6fd6' },
  { name: 'Schwarz', hex: '#2f2f2f' },
  { name: 'Violett', hex: '#8e44ad' },
  { name: 'Orange',  hex: '#e8740c' },
  { name: 'Türkis',  hex: '#0f9b8e' }
];

// Mischt zwei Hexfarben, t = Anteil der zweiten Farbe (0..1)
function mixHex(a, b, t) {
  const ah = parseInt(a.slice(1), 16), bh = parseInt(b.slice(1), 16);
  let out = '#';
  for (const sh of [16, 8, 0]) {
    const v = Math.round(((ah >> sh) & 255) * (1 - t) + ((bh >> sh) & 255) * t);
    out += v.toString(16).padStart(2, '0');
  }
  return out;
}

// Aktuelle Farbzuordnung: Palettenindex je Spielerplatz (0=oben links,
// 1=oben rechts, 2=unten rechts, 3=unten links)
const setupColors = [0, 1, 2, 3];
let NAMES = [], HEX = [], HEX_DARK = [], HEX_LIGHT = [];

function applyColors() {
  NAMES     = setupColors.map(i => PALETTE[i].name);
  HEX       = setupColors.map(i => PALETTE[i].hex);
  HEX_DARK  = setupColors.map(i => mixHex(PALETTE[i].hex, '#000000', 0.4));
  HEX_LIGHT = setupColors.map(i => mixHex(PALETTE[i].hex, '#ffffff', 0.78));
}
applyColors();

const PIPS = { 1:[4], 2:[2,6], 3:[2,4,6], 4:[0,2,6,8], 5:[0,2,4,6,8], 6:[0,2,3,5,6,8] };

// ---------- Spielzustand ----------
// Figurposition: -1 = Homebase, 0..39 = Spielfeld (absolut), 40..43 = Zielfeld 0..3
const game = {
  players: [],      // {type:'human'|'ki'|'off', pieces:[..4], finished:false}
  current: 0,
  dice: null,
  rollsLeft: 1,
  phase: 'setup',   // setup | roll | move | anim | over
  movable: [],
  captureList: [],  // Schlagzüge des aktuellen Wurfs (für die Strafregel)
  ranking: [],
  rolling: false,
  seq: 0            // entwertet alte Timer nach "Neues Spiel"
};

// ---------- DOM ----------
const canvas   = document.getElementById('board');
const ctx      = canvas.getContext('2d');
const diceEl   = document.getElementById('dice3d');
const cubeEl   = document.getElementById('cube');
const shadowEl = document.getElementById('diceShadow');
const glowEl   = document.getElementById('diceGlow');
const logEl   = document.getElementById('log');
const menuEl  = document.getElementById('menu');
const menuBtn = document.getElementById('menuBtn');

const logLines = [];

// =========================================================
//  Hilfsfunktionen
// =========================================================
function schedule(fn, ms) {
  const s = game.seq;
  setTimeout(() => { if (s === game.seq) fn(); }, ms);
}

function addLog(text) {
  logLines.unshift(text);
  if (logLines.length > 30) logLines.pop();
  logEl.innerHTML = logLines.map(l => `<div>${l}</div>`).join('');
}

function isHuman(pIdx) { return game.players[pIdx].type === 'human'; }
function isKI(pIdx)    { return game.players[pIdx].type === 'ki'; }

function ownPieceAt(pIdx, pos) {
  return game.players[pIdx].pieces.includes(pos);
}

function opponentAt(pos, excludeIdx) {
  for (let q = 0; q < 4; q++) {
    if (q === excludeIdx) continue;
    const p = game.players[q];
    if (p.type === 'off') continue;
    const j = p.pieces.indexOf(pos);
    if (j >= 0) return { player: q, piece: j };
  }
  return null;
}

function isCaptureMove(pIdx, m) {
  return m.to < 40 && !!opponentAt(m.to, pIdx);
}

// Im Zielfeld darf nicht übersprungen werden (klassische Regel)
function goalPathFree(pIdx, fromG, toG) {
  for (let g = fromG + 1; g <= toG; g++) {
    if (ownPieceAt(pIdx, 40 + g)) return false;
  }
  return true;
}

// =========================================================
//  Zugberechnung
// =========================================================
function computeMoves(pIdx, w) {
  const p = game.players[pIdx];
  const start = START[pIdx];
  const moves = [];

  for (let i = 0; i < 4; i++) {
    const pos = p.pieces[i];
    if (pos === -1) {
      // Aus der Homebase nur mit einer 6, Startfeld darf nicht von eigener Figur besetzt sein
      if (w === 6 && !ownPieceAt(pIdx, start)) {
        moves.push({ piece: i, type: 'out', to: start });
      }
    } else if (pos < 40) {
      const rel = (pos - start + 40) % 40;
      const trel = rel + w;
      if (trel <= 39) {
        const t = (pos + w) % 40;
        if (!ownPieceAt(pIdx, t)) moves.push({ piece: i, type: 'board', to: t });
      } else {
        const g = trel - 40;
        if (g <= 3 && goalPathFree(pIdx, -1, g)) {
          moves.push({ piece: i, type: 'goal', to: 40 + g });
        }
      }
    } else {
      const g = pos - 40;
      const ng = g + w;
      if (ng <= 3 && goalPathFree(pIdx, g, ng)) {
        moves.push({ piece: i, type: 'goal', to: 40 + ng });
      }
    }
  }

  // ---- Pflichtregeln ----
  const homeCount = p.pieces.filter(x => x === -1).length;
  if (homeCount > 0) {
    // Mit einer 6 muss eine Figur herausgebracht werden, wenn möglich
    if (w === 6) {
      const outMoves = moves.filter(m => m.type === 'out');
      if (outMoves.length) return outMoves;
    }
    // Das eigene Startfeld muss geräumt werden, solange Figuren in der Homebase warten
    const startPiece = p.pieces.indexOf(start);
    if (startPiece >= 0) {
      const clearing = moves.filter(m => m.piece === startPiece);
      if (clearing.length) return clearing;
    }
  }
  return moves;
}

// Hat der Spieler überhaupt bewegliche Figuren (für die 3-Versuche-Regel)?
function hasMovablePotential(pIdx) {
  const p = game.players[pIdx];
  if (p.pieces.some(x => x >= 0 && x < 40)) return true;
  for (const pos of p.pieces) {
    if (pos >= 40) {
      const g = pos - 40;
      for (let w = 1; w <= 3; w++) {
        if (g + w <= 3 && goalPathFree(pIdx, g, g + w)) return true;
      }
    }
  }
  return false;
}

// =========================================================
//  Spielablauf
// =========================================================
function startTurn() {
  game.phase = 'roll';
  game.dice = null;
  game.movable = [];
  game.captureList = [];
  game.rollsLeft = hasMovablePotential(game.current) ? 1 : 3;
  updateDiceCue();
  if (isKI(game.current)) schedule(kickRandom, 900);
}

// Statt Statustexten: Ein Leuchtring auf dem Tisch unter dem Würfel
// pulsiert in der Farbe des Spielers, der dran ist
function updateDiceCue() {
  diceEl.classList.remove('rollable');
  glowEl.classList.remove('on');
  if (game.phase === 'roll' && !game.rolling &&
      game.players.length && isHuman(game.current)) {
    glowEl.style.setProperty('--glow', HEX[game.current]);
    glowEl.classList.add('on');
    diceEl.classList.add('rollable');
  }
}

function resolveRoll(w) {
  game.dice = w;
  const c = game.current;
  const moves = computeMoves(c, w);
  game.captureList = moves.filter(m => isCaptureMove(c, m));

  if (moves.length) {
    game.phase = 'move';
    game.movable = moves;
    updateDiceCue();
    if (isKI(c)) {
      schedule(() => {
        const m = aiPickMove(moves, c);
        executeMove(m);
      }, 800);
    }
    return;
  }

  // Kein Zug möglich
  if (w === 6) {
    // Eine 6 erlaubt immer einen weiteren Wurf
    game.phase = 'roll';
    game.rollsLeft = 1;
    addLog(`${NAMES[c]} würfelt 6, kann aber nicht ziehen – nochmal!`);
    updateDiceCue();
    if (isKI(c)) schedule(kickRandom, 800);
    return;
  }

  game.rollsLeft--;
  if (game.rollsLeft > 0) {
    game.phase = 'roll';
    updateDiceCue();
    if (isKI(c)) schedule(kickRandom, 700);
  } else {
    addLog(`${NAMES[c]} kann nicht ziehen.`);
    game.phase = 'anim'; // Eingaben kurz sperren
    updateDiceCue();
    schedule(advancePlayer, 1000);
  }
}

function makePath(pIdx, m) {
  const pos = game.players[pIdx].pieces[m.piece];
  const path = [];
  if (m.type === 'out') {
    path.push(START[pIdx]);
  } else if (pos < 40) {
    const start = START[pIdx];
    const rel = (pos - start + 40) % 40;
    for (let s = 1; s <= game.dice; s++) {
      const r = rel + s;
      path.push(r <= 39 ? (start + r) % 40 : 40 + (r - 40));
    }
  } else {
    for (let g = pos - 40 + 1; g <= m.to - 40; g++) path.push(40 + g);
  }
  return path;
}

function executeMove(m) {
  const c = game.current;
  const path = makePath(c, m);
  game.phase = 'anim';
  game.movable = [];
  updateDiceCue();

  let idx = 0;
  const s = game.seq;
  const iv = setInterval(() => {
    if (s !== game.seq) { clearInterval(iv); return; }
    game.players[c].pieces[m.piece] = path[idx++];
    if (idx >= path.length) {
      clearInterval(iv);
      schedule(() => finalizeMove(m), 180);
    }
  }, 140);
}

function finalizeMove(m) {
  const c = game.current;
  const pos = game.players[c].pieces[m.piece];
  let hasCaptured = false;

  // Schlagen
  if (pos < 40) {
    const hit = opponentAt(pos, c);
    if (hit) {
      const [ex, ey] = FIELD_POS[pos];
      spawnExplosion(ex, ey, HEX[hit.player]);
      game.players[hit.player].pieces[hit.piece] = -1;
      addLog(`💥 ${NAMES[c]} schlägt ${NAMES[hit.player]} – Mensch ärgere Dich nicht!`);
      hasCaptured = true;
    }
  }

  // Strafregel: Schlagen war möglich, wurde aber verschmäht →
  // die säumige Figur fliegt selbst raus
  if (!hasCaptured && game.captureList.length) {
    const others = game.captureList.filter(cm => cm.piece !== m.piece);
    const pun = (others.length ? others[0] : game.captureList[0]).piece;
    const [px, py] = pieceXY(c, pun);
    spawnExplosion(px, py, HEX[c]);
    game.players[c].pieces[pun] = -1;
    addLog(`⚖️ Strafe! ${NAMES[c]} hätte schlagen können – die säumige Figur fliegt raus!`);
  }
  game.captureList = [];

  if (m.type === 'out') addLog(`${NAMES[c]} bringt eine Figur ins Spiel.`);
  if (m.type === 'goal') addLog(`${NAMES[c]} zieht ins Ziel.`);

  // Fertig?
  const p = game.players[c];
  if (!p.finished && p.pieces.every(x => x >= 40)) {
    p.finished = true;
    game.ranking.push(c);
    addLog(`🏁 ${NAMES[c]} hat alle Figuren im Ziel!`);
  }

  // Spielende, wenn höchstens ein aktiver Spieler übrig ist
  const remaining = activeUnfinished();
  if (remaining.length <= 1) {
    remaining.forEach(q => game.ranking.push(q));
    return gameOver();
  }

  if (!p.finished && game.dice === 6) {
    addLog(`${NAMES[c]} darf nochmal würfeln (6).`);
    startTurn(); // gleicher Spieler
  } else {
    advancePlayer();
  }
}

function activeUnfinished() {
  const res = [];
  for (let q = 0; q < 4; q++) {
    const p = game.players[q];
    if (p.type !== 'off' && !p.finished) res.push(q);
  }
  return res;
}

function advancePlayer() {
  let n = game.current;
  for (let k = 1; k <= 4; k++) {
    n = (game.current + k) % 4;
    const p = game.players[n];
    if (p.type !== 'off' && !p.finished) break;
  }
  game.current = n;
  startTurn();
}

function gameOver() {
  game.phase = 'over';
  game.rolling = false;
  updateDiceCue();
  const medals = ['🥇', '🥈', '🥉', '4.'];
  document.getElementById('ranking').innerHTML = game.ranking
    .map((q, i) => `${medals[i]} <span style="display:inline-block;width:.8em;height:.8em;border-radius:50%;background:${HEX[q]};border:2px solid rgba(255,255,255,.6)"></span> <strong>${NAMES[q]}</strong>${game.players[q].type === 'ki' ? ' (Computer)' : ''}`)
    .join('<br>');
  document.getElementById('gameover').classList.remove('hidden');
}

// =========================================================
//  Computergegner
// =========================================================
function isDangerous(pIdx, abs) {
  for (let q = 0; q < 4; q++) {
    if (q === pIdx) continue;
    const op = game.players[q];
    if (op.type === 'off' || op.finished) continue;
    for (const qp of op.pieces) {
      if (qp >= 0 && qp < 40) {
        const d = (abs - qp + 40) % 40;
        if (d >= 1 && d <= 6) {
          const qrel = (qp - START[q] + 40) % 40;
          if (qrel + d <= 39) return true; // Gegner kann das Feld erreichen
        }
      }
    }
    // Gegnerisches Startfeld ist riskant, wenn dort noch Figuren warten
    if (abs === START[q] && op.pieces.some(x => x === -1)) return true;
  }
  return false;
}

function aiPickMove(moves, pIdx) {
  // Wegen der Strafregel: Wenn geschlagen werden kann, wird geschlagen
  const caps = moves.filter(m => isCaptureMove(pIdx, m));
  const pool = caps.length ? caps : moves;

  let best = null, bestScore = -Infinity;
  for (const m of pool) {
    let s = 0;
    if (m.type === 'out')  s += 55;
    if (m.type === 'goal') s += 70 + (m.to - 40) * 2;
    if (m.to < 40) {
      if (opponentAt(m.to, pIdx)) s += 100;                  // Schlagen ist top
      const from = game.players[pIdx].pieces[m.piece];
      if (from >= 0 && from < 40 && isDangerous(pIdx, from)) s += 25; // Flucht
      if (isDangerous(pIdx, m.to)) s -= 30;                  // nicht ins Gefahrenfeld
      const rel = (m.to - START[pIdx] + 40) % 40;
      s += rel * 0.3;                                        // weiter vorn = besser
    }
    s += Math.random() * 2; // kleine Varianz
    if (s > bestScore) { bestScore = s; best = m; }
  }
  return best;
}

// =========================================================
//  Explosionspartikel
// =========================================================
const particles = [];

function spawnExplosion(xu, yu, hex) {
  for (let i = 0; i < 26; i++) {
    const a = Math.random() * Math.PI * 2;
    const sp = 1.2 + Math.random() * 3.2;
    particles.push({
      x: xu, y: yu,
      vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 0.6,
      age: 0, life: 0.5 + Math.random() * 0.4,
      r: 0.04 + Math.random() * 0.08,
      color: i % 3 === 0 ? '#ffb300' : hex
    });
  }
  // Druckwelle
  particles.push({ ring: true, x: xu, y: yu, age: 0, life: 0.45 });
}

function updateParticles(dt) {
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.age += dt;
    if (p.age >= p.life) { particles.splice(i, 1); continue; }
    if (!p.ring) {
      p.vy += 2.6 * dt; // leichte Schwerkraft
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
  }
}

function drawParticles(u) {
  for (const p of particles) {
    const k = p.age / p.life;
    if (p.ring) {
      ctx.strokeStyle = `rgba(255,170,0,${0.85 * (1 - k)})`;
      ctx.lineWidth = u * 0.09 * (1 - k) + 1;
      circle(p.x * u, p.y * u, (0.15 + k * 1.15) * u);
      ctx.stroke();
    } else {
      ctx.globalAlpha = 1 - k;
      ctx.fillStyle = p.color;
      circle(p.x * u, p.y * u, p.r * u * (1 - k * 0.5));
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}

// =========================================================
//  Quaternionen (für die natürliche Würfelrotation)
// =========================================================
function qMul(a, b) {
  return [
    a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3],
    a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2],
    a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1],
    a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0]
  ];
}

function qAxis(x, y, z, ang) {
  const s = Math.sin(ang / 2);
  return [Math.cos(ang / 2), x * s, y * s, z * s];
}

function qNorm(q) {
  const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1;
  return [q[0] / l, q[1] / l, q[2] / l, q[3] / l];
}

function qRotate(q, v) {
  const [w, x, y, z] = q, [vx, vy, vz] = v;
  const tx = 2 * (y * vz - z * vy);
  const ty = 2 * (z * vx - x * vz);
  const tz = 2 * (x * vy - y * vx);
  return [
    vx + w * tx + (y * tz - z * ty),
    vy + w * ty + (z * tx - x * tz),
    vz + w * tz + (x * ty - y * tx)
  ];
}

function qSlerp(a, b, t) {
  let dot = a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3];
  let bb = b;
  if (dot < 0) { bb = b.map(v => -v); dot = -dot; }
  if (dot > 0.9995) return qNorm(a.map((v, i) => v + (bb[i] - v) * t));
  const th = Math.acos(Math.min(1, dot)), s = Math.sin(th);
  const f1 = Math.sin((1 - t) * th) / s, f2 = Math.sin(t * th) / s;
  return [a[0]*f1 + bb[0]*f2, a[1]*f1 + bb[1]*f2, a[2]*f1 + bb[2]*f2, a[3]*f1 + bb[3]*f2];
}

function qToCss(q) {
  const [w, x, y, z] = q;
  const s = Math.hypot(x, y, z);
  if (s < 1e-9) return 'rotate3d(0,0,1,0rad)';
  const ang = 2 * Math.atan2(s, w);
  return `rotate3d(${x / s},${y / s},${z / s},${ang}rad)`;
}

// =========================================================
//  3D-Würfel – rollt nur auf der Holzfläche neben dem Brett.
//  Der Wert ergibt sich aus der tatsächlichen Endlage
//  (oben liegende Seite), nie umgekehrt.
// =========================================================

// Lage der sechs Seiten am Würfelkörper (gegenüberliegende ergeben 7)
const FACE_TF = {
  1: 'rotateY(0deg)',  6: 'rotateY(180deg)',
  2: 'rotateY(90deg)', 5: 'rotateY(-90deg)',
  3: 'rotateX(90deg)', 4: 'rotateX(-90deg)'
};

// Außennormale jeder Seite im Körper-Koordinatensystem
const FACE_NORMALS = {
  1: [0, 0, 1], 6: [0, 0, -1],
  2: [1, 0, 0], 5: [-1, 0, 0],
  3: [0, -1, 0], 4: [0, 1, 0]
};

const dice = {
  x: 0, y: 0,          // Mittelpunkt in Tisch-Pixeln
  vx: 0, vy: 0,        // Geschwindigkeit (px/s)
  z: 0, vz: 0,         // Sprunghöhe (px) für den Hüpf-Effekt
  wz: 0,               // Drall um die Hochachse (rad/s)
  q: qNorm(qMul(qAxis(1, 0, 0, -0.35), qAxis(0, 1, 0, 0.5))), // Orientierung
  qFrom: null, qTo: null, settleT: 0,
  state: 'idle',       // idle | tumble | settle
  value: null
};

// Layout: wird in layoutTable() gesetzt
let boardCss = 0;                                  // Kantenlänge Brett (CSS-px)
let diceZone = { x0: 0, y0: 0, x1: 0, y1: 0 };     // Würfelzone (Tisch-px)
let ds = 80;                                       // Würfelgröße (px)

function cssU() { return boardCss / 12; }

const faceEls = {}, ifaceEls = {};

function buildCube() {
  cubeEl.innerHTML = '';
  for (let v = 1; v <= 6; v++) {
    // Innerer Kern (geschlossen, ohne Rundung) – füllt die Ecklücken
    const fi = document.createElement('div');
    fi.className = 'iface';
    fi.style.transform =
      `${FACE_TF[v]} translateZ(calc(var(--ds, 80px) / 2 - var(--inset, 2px)))`;
    cubeEl.appendChild(fi);
    ifaceEls[v] = fi;

    // Außenfläche mit Augen
    const f = document.createElement('div');
    f.className = 'face';
    f.style.transform = `${FACE_TF[v]} translateZ(calc(var(--ds, 80px) / 2))`;
    for (let i = 0; i < 9; i++) {
      const sp = document.createElement('span');
      if (PIPS[v].includes(i)) sp.classList.add('on');
      f.appendChild(sp);
    }
    cubeEl.appendChild(f);
    faceEls[v] = f;
  }
}

// Einfache Beleuchtung: Jede Seite wird nach ihrem Winkel zur Lichtquelle
// (oben links vorn) abgedunkelt – macht den Würfel plastisch.
const LIGHT = (() => {
  const l = [-0.35, -0.5, 0.79];
  const n = Math.hypot(l[0], l[1], l[2]);
  return [l[0] / n, l[1] / n, l[2] / n];
})();

function applyLighting() {
  if (GL) return; // WebGL beleuchtet selbst; CSS-Würfel ist nur Fallback
  for (let v = 1; v <= 6; v++) {
    const n = qRotate(dice.q, FACE_NORMALS[v]);
    const d = n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2];
    const b = (0.62 + 0.5 * Math.max(0, d)).toFixed(3);
    // Der minimale Blur glättet die Treppchen an den transformierten
    // Kanten (Anti-Aliasing), ohne die Augen sichtbar weichzuzeichnen
    faceEls[v].style.filter = `brightness(${b}) blur(0.3px)`;
    ifaceEls[v].style.filter = `brightness(${b}) blur(0.6px)`;
  }
}

// Welche Seite zeigt gerade nach oben (zum Betrachter)?
function topFace(q) {
  let best = 1, bestDot = -2;
  for (let v = 1; v <= 6; v++) {
    const n = qRotate(q, FACE_NORMALS[v]);
    if (n[2] > bestDot) { bestDot = n[2]; best = v; }
  }
  return best;
}

function clampDiceToZone() {
  const h = ds / 2 + 2;
  dice.x = Math.min(diceZone.x1 - h, Math.max(diceZone.x0 + h, dice.x));
  dice.y = Math.min(diceZone.y1 - h, Math.max(diceZone.y0 + h, dice.y));
}

function placeDiceInZone() {
  dice.x = (diceZone.x0 + diceZone.x1) / 2;
  dice.y = (diceZone.y0 + diceZone.y1) / 2;
  clampDiceToZone();
}

function kickDice(vx, vy) {
  if (game.phase !== 'roll' || game.rolling || dice.state !== 'idle') return;
  game.rolling = true;
  dice.vx = vx; dice.vy = vy;
  dice.vz = 2.4 * cssU();                       // kleiner Wurf nach oben
  dice.wz = (Math.random() * 2 - 1) * 4;        // etwas Drall
  dice.state = 'tumble';
  updateDiceCue();
}

// Stoß in Richtung eines zufälligen Punktes der Würfelzone
function kickRandom() {
  if (game.phase !== 'roll' || game.rolling || dice.state !== 'idle') return;
  const tx = diceZone.x0 + ds + Math.random() * (diceZone.x1 - diceZone.x0 - 2 * ds);
  const ty = diceZone.y0 + ds + Math.random() * (diceZone.y1 - diceZone.y0 - 2 * ds);
  let dx = tx - dice.x, dy = ty - dice.y;
  const len = Math.hypot(dx, dy) || 1;
  const sp = (6 + Math.random() * 4.5) * cssU();
  kickDice(dx / len * sp, dy / len * sp);
}

function settleDice() {
  dice.state = 'settle';
  dice.vx = 0; dice.vy = 0; dice.z = 0; dice.vz = 0;
  dice.settleT = 0;
  dice.value = topFace(dice.q);                 // Wert = tatsächliche Endlage!

  // Kleine Korrekturdrehung, damit die Seite exakt plan liegt (< 45°)
  const n = qRotate(dice.q, FACE_NORMALS[dice.value]);
  const cx = n[1], cy = -n[0];                  // n × (0,0,1)
  const s = Math.hypot(cx, cy);
  const ang = Math.atan2(s, n[2]);
  const A = s > 1e-6 ? qAxis(cx / s, cy / s, 0, ang) : [1, 0, 0, 0];
  dice.qFrom = dice.q;
  dice.qTo = qNorm(qMul(A, dice.q));
}

function updateDice(dt) {
  if (game.phase === 'setup' || !boardCss) return;
  const u = cssU();

  if (dice.state === 'tumble') {
    dice.x += dice.vx * dt;
    dice.y += dice.vy * dt;

    // Bande: Würfelzone (Tischfläche ohne Spielbrett)
    const h = ds / 2 + 2, R = 0.72;
    let bounced = false;
    if (dice.x < diceZone.x0 + h) { dice.x = diceZone.x0 + h; dice.vx =  Math.abs(dice.vx) * R; bounced = true; }
    if (dice.x > diceZone.x1 - h) { dice.x = diceZone.x1 - h; dice.vx = -Math.abs(dice.vx) * R; bounced = true; }
    if (dice.y < diceZone.y0 + h) { dice.y = diceZone.y0 + h; dice.vy =  Math.abs(dice.vy) * R; bounced = true; }
    if (dice.y > diceZone.y1 - h) { dice.y = diceZone.y1 - h; dice.vy = -Math.abs(dice.vy) * R; bounced = true; }

    const speed = Math.hypot(dice.vx, dice.vy);

    // Hüpfen: beim Anstoß und an der Bande springt der Würfel leicht auf
    if (bounced) dice.vz = Math.max(dice.vz, Math.min(2.2 * u, speed * 0.25));
    dice.z += dice.vz * dt;
    dice.vz -= 14 * u * dt;                     // "Schwerkraft"
    if (dice.z < 0) { dice.z = 0; dice.vz = -dice.vz * 0.42; if (Math.abs(dice.vz) < 0.3 * u) dice.vz = 0; }

    // Gleitreibung: lineare Abbremsung wirkt natürlicher als exponentiell
    const dec = 3.4 * u * dt;
    if (speed > dec) {
      const f = (speed - dec) / speed;
      dice.vx *= f; dice.vy *= f;
    } else { dice.vx = 0; dice.vy = 0; }

    // Natürliches Abrollen: Drehachse senkrecht zur Bewegungsrichtung
    if (speed > 1) {
      const ang = (speed / (ds / 2)) * dt;      // Abrollwinkel
      dice.q = qNorm(qMul(qAxis(-dice.vy / speed, dice.vx / speed, 0, ang), dice.q));
    }
    // Drall um die Hochachse
    if (Math.abs(dice.wz) > 0.05) {
      dice.q = qNorm(qMul(qAxis(0, 0, 1, dice.wz * dt), dice.q));
      dice.wz *= Math.exp(-1.8 * dt);
    }

    cubeEl.style.transform = qToCss(dice.q);
    applyLighting();

    if (speed < 0.5 * u && dice.z <= 0.01) settleDice();
  }
  else if (dice.state === 'settle') {
    // Sanfte Korrekturdrehung in die plane Endlage – kein Sprung
    dice.settleT += dt;
    const k = Math.min(1, dice.settleT / 0.32);
    const e = 1 - Math.pow(1 - k, 3);           // ease-out
    dice.q = qSlerp(dice.qFrom, dice.qTo, e);
    cubeEl.style.transform = qToCss(dice.q);
    applyLighting();
    if (k >= 1) {
      dice.q = dice.qTo;
      dice.state = 'idle';
      game.rolling = false;
      resolveRoll(dice.value);
    }
  }

  // Position und Sprunghöhe anwenden
  const scale = 1 + dice.z / (1.6 * ds);
  diceEl.style.transform =
    `translate(${dice.x - ds / 2}px, ${dice.y - ds / 2}px) scale(${scale})`;

  // Bodenschatten: bleibt auf dem Tisch, wird beim Hüpfen größer und blasser
  const sh = ds * 0.78;
  shadowEl.style.transform =
    `translate(${dice.x - ds / 2}px, ${dice.y - sh / 2 + ds * 0.10 + dice.z * 0.25}px) ` +
    `scale(${1 + dice.z / (2.5 * ds)})`;
  shadowEl.style.opacity = String(Math.max(0.3, 0.85 - dice.z / (2 * ds)));

  // Leuchtring zentriert unter dem Würfel
  glowEl.style.transform = `translate(${dice.x - ds}px, ${dice.y - ds}px)`;
}

// ---- Würfel anstupsen / schleudern ----
let diceDrag = null;

diceEl.addEventListener('pointerdown', e => {
  if (game.phase !== 'roll' || game.rolling || !isHuman(game.current)) return;
  e.preventDefault();
  try { diceEl.setPointerCapture(e.pointerId); } catch (_) { /* synthetische Events */ }
  diceDrag = { x: e.clientX, y: e.clientY, t: performance.now(), vx: 0, vy: 0, moved: false };
});

diceEl.addEventListener('pointermove', e => {
  if (!diceDrag) return;
  const now = performance.now();
  const dt = Math.max(8, now - diceDrag.t) / 1000;
  const dx = e.clientX - diceDrag.x;
  const dy = e.clientY - diceDrag.y;
  if (Math.hypot(dx, dy) > 5) diceDrag.moved = true;
  // Würfel folgt dem Finger (innerhalb der Zone)
  dice.x += dx; dice.y += dy;
  clampDiceToZone();
  diceDrag.vx = 0.6 * diceDrag.vx + 0.4 * (dx / dt);
  diceDrag.vy = 0.6 * diceDrag.vy + 0.4 * (dy / dt);
  diceDrag.x = e.clientX; diceDrag.y = e.clientY; diceDrag.t = now;
});

function endDiceDrag() {
  if (!diceDrag) return;
  const d = diceDrag;
  diceDrag = null;
  const u = cssU();
  if (!d.moved) { kickRandom(); return; }       // Anstupsen
  const sp = Math.hypot(d.vx, d.vy);
  if (sp < 2.5 * u) { kickRandom(); return; }   // zu schwacher Wurf
  const cl = Math.min(13 * u, Math.max(5 * u, sp)) / sp;
  kickDice(d.vx * cl, d.vy * cl);               // Schleudern
}

diceEl.addEventListener('pointerup', endDiceDrag);
diceEl.addEventListener('pointercancel', () => { diceDrag = null; });

document.addEventListener('keydown', e => {
  if (e.code === 'Space' && game.phase === 'roll' && !game.rolling &&
      game.players.length && isHuman(game.current)) {
    e.preventDefault();
    kickRandom();
  }
});

// =========================================================
//  WebGL-Würfel (three.js): echte Rounded-Box-Geometrie mit
//  Licht und Antialiasing. Die Physik (dice.q, x/y/z) bleibt
//  unverändert – hier wird nur gerendert. Ohne WebGL bleibt
//  der CSS-Cube als Fallback aktiv.
// =========================================================
let GL = null;

// Abgerundete Box: stark unterteilte BoxGeometry, deren Vertices auf
// den Rounded-Box-Körper projiziert werden (Kern + Radius r).
function roundedBoxGeometry(size, radiusFrac, segs) {
  const r = size * radiusFrac;
  const h = size / 2 - r;
  const geo = new THREE.BoxGeometry(size, size, size, segs, segs, segs);
  const pos = geo.attributes.position, nor = geo.attributes.normal;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
    const cx = Math.max(-h, Math.min(h, x));
    const cy = Math.max(-h, Math.min(h, y));
    const cz = Math.max(-h, Math.min(h, z));
    let dx = x - cx, dy = y - cy, dz = z - cz;
    const l = Math.hypot(dx, dy, dz) || 1;
    dx /= l; dy /= l; dz /= l;
    pos.setXYZ(i, cx + dx * r, cy + dy * r, cz + dz * r);
    nor.setXYZ(i, dx, dy, dz);
  }
  return geo;
}

// Augen-Textur einer Würfelseite (mit Mulden-Optik)
function pipTexture(v) {
  const S = 256;
  const c = document.createElement('canvas');
  c.width = S; c.height = S;
  const g = c.getContext('2d');
  const bg = g.createRadialGradient(S * 0.35, S * 0.3, S * 0.1, S * 0.5, S * 0.5, S * 0.85);
  bg.addColorStop(0, '#ffffff');
  bg.addColorStop(1, '#e9e7dc');
  g.fillStyle = bg;
  g.fillRect(0, 0, S, S);
  const pad = S * 0.16, cell = (S - 2 * pad) / 3, R = S * 0.066;
  for (const i of PIPS[v]) {
    const cx = pad + (i % 3 + 0.5) * cell;
    const cy = pad + (Math.floor(i / 3) + 0.5) * cell;
    // Schattenkante oben links der Mulde
    g.strokeStyle = 'rgba(0,0,0,0.30)';
    g.lineWidth = S * 0.012;
    g.beginPath(); g.arc(cx - R * 0.04, cy - R * 0.04, R * 1.04, Math.PI * 0.95, Math.PI * 1.75); g.stroke();
    // Lichtkante unten rechts
    g.strokeStyle = 'rgba(255,255,255,0.7)';
    g.beginPath(); g.arc(cx + R * 0.04, cy + R * 0.04, R * 1.04, Math.PI * 0.05, Math.PI * 0.65); g.stroke();
    // Mulde selbst
    const grad = g.createRadialGradient(cx - R * 0.3, cy - R * 0.3, R * 0.05, cx, cy, R);
    grad.addColorStop(0, '#000000');
    grad.addColorStop(0.7, '#181818');
    grad.addColorStop(1, '#383838');
    g.fillStyle = grad;
    g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.fill();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.encoding = THREE.sRGBEncoding;
  tex.anisotropy = 4;
  return tex;
}

function initGL() {
  if (typeof THREE === 'undefined') return;
  try {
    const renderer = new THREE.WebGLRenderer({
      canvas: document.getElementById('gl'),
      alpha: true, antialias: true
    });
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    renderer.outputEncoding = THREE.sRGBEncoding;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(30, 1, 50, 6000);

    scene.add(new THREE.AmbientLight(0xfff6e8, 0.55));
    const sun = new THREE.DirectionalLight(0xfff2dd, 1.05);
    sun.position.set(-350, 500, 790); // wie LIGHT, y in three nach oben
    scene.add(sun);
    const fill = new THREE.DirectionalLight(0xcfe2ff, 0.25);
    fill.position.set(400, -250, 500);
    scene.add(fill);

    // Material-Reihenfolge der BoxGeometry: +x,-x,+y,-y,+z,-z
    // Körpernormalen (three-Frame, y gespiegelt): 2:+x 5:-x 3:+y 4:-y 1:+z 6:-z
    const mats = [2, 5, 3, 4, 1, 6].map(v => new THREE.MeshStandardMaterial({
      map: pipTexture(v), roughness: 0.30, metalness: 0.04
    }));
    const mesh = new THREE.Mesh(roundedBoxGeometry(1, 0.13, 8), mats);
    mesh.visible = false;
    scene.add(mesh);

    GL = { renderer, scene, camera, mesh };
    cubeEl.style.display = 'none'; // CSS-Würfel nur noch als Fallback
    resizeGL();
  } catch (e) {
    GL = null; // CSS-Fallback bleibt aktiv
  }
}

function resizeGL() {
  if (!GL) return;
  const W = window.innerWidth, H = window.innerHeight;
  // updateStyle=true: setzt auch style.width/height – ein Canvas ist ein
  // replaced element und wird von CSS inset:0 NICHT gestreckt (wichtig
  // bei Windows-Skalierung / devicePixelRatio > 1)
  GL.renderer.setSize(W, H);
  GL.camera.aspect = W / H;
  // Abstand so, dass 1 Welteinheit = 1 CSS-Pixel auf der Tischebene
  GL.camera.position.set(0, 0, (H / 2) / Math.tan(GL.camera.fov / 2 * Math.PI / 180));
  GL.camera.updateProjectionMatrix();
}

function renderGL() {
  if (!GL) return;
  const show = game.phase !== 'setup' && !diceEl.classList.contains('hidden');
  GL.mesh.visible = show;
  if (show) {
    const W = window.innerWidth, H = window.innerHeight;
    GL.mesh.position.set(dice.x - W / 2, H / 2 - dice.y, dice.z);
    // Spiegelung Bildschirm-Frame (y nach unten) -> three-Frame (y nach oben):
    // q = (w,x,y,z) -> (w,-x,y,-z)
    GL.mesh.quaternion.set(-dice.q[1], dice.q[2], -dice.q[3], dice.q[0]);
    GL.mesh.scale.setScalar(ds);
  }
  GL.renderer.render(GL.scene, GL.camera);
}

// =========================================================
//  Prozedurale Holztextur: dunkles Walnussholz mit Planken,
//  welliger Maserung, Farbbändern, Astknoten und Fugen.
//  Die Kachel ist nahtlos (ganzzahlige Wellenperioden).
// =========================================================
function makeWoodTexture() {
  const W = 1024, H = 1024;
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const g = c.getContext('2d');
  const img = g.createImageData(W, H);
  const data = img.data;

  // Periodisches Wertrauschen (Gitter P x P) → nahtlose Kachel
  const P = 64;
  const lat = new Float32Array(P * P);
  for (let i = 0; i < lat.length; i++) lat[i] = Math.random();
  const noise = (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    const sx = xf * xf * (3 - 2 * xf), sy = yf * yf * (3 - 2 * yf);
    const ix0 = ((xi % P) + P) % P, iy0 = ((yi % P) + P) % P;
    const ix1 = (ix0 + 1) % P, iy1 = (iy0 + 1) % P;
    const a = lat[iy0 * P + ix0], b = lat[iy0 * P + ix1];
    const d = lat[iy1 * P + ix0], e = lat[iy1 * P + ix1];
    return a + (b - a) * sx + (d - a) * sy + (a - b - d + e) * sx * sy;
  };
  const fbm = (x, y) =>
    noise(x, y) * 0.55 + noise(x * 2.13, y * 2.13) * 0.28 + noise(x * 4.7, y * 4.7) * 0.17;

  // Drei Farbtöne: dunkler Nussbaum
  const DARK = [36, 22, 11], MID = [72, 45, 23], LIGHT = [104, 69, 36];
  const lerp3 = (k) => {
    // k 0..1 → dunkel..hell über Mittelton
    let r, gg, bb;
    if (k < 0.6) {
      const s = k / 0.6;
      r = DARK[0] + (MID[0] - DARK[0]) * s;
      gg = DARK[1] + (MID[1] - DARK[1]) * s;
      bb = DARK[2] + (MID[2] - DARK[2]) * s;
    } else {
      const s = Math.min(1, (k - 0.6) / 0.4);
      r = MID[0] + (LIGHT[0] - MID[0]) * s;
      gg = MID[1] + (LIGHT[1] - MID[1]) * s;
      bb = MID[2] + (LIGHT[2] - MID[2]) * s;
    }
    return [r, gg, bb];
  };

  // Planken einteilen
  const planks = [];
  let px0 = 0;
  while (px0 < W) {
    // WICHTIG: ganzzahlig – x0/w gehen in den Pixel-Index des ImageData
    let w = Math.round(130 + Math.random() * 100);
    if (W - (px0 + w) < 90) w = W - px0;
    planks.push({
      x0: px0, w,
      tone: 0.84 + Math.random() * 0.32,            // Grundhelligkeit
      freq: 0.014 + Math.random() * 0.016,          // breite Jahresringe (~33-70px)
      warpAmp: 22 + Math.random() * 38,             // Verwerfung in PIXELN (vor freq)
      phase: Math.random() * 100,
      ny: 4 + Math.floor(Math.random() * 5),        // ganzzahlige y-Perioden → nahtlos
      knot: Math.random() < 0.7
        ? { u: 0.25 + Math.random() * 0.5, y: H * (0.25 + Math.random() * 0.5),
            r: 16 + Math.random() * 22 }
        : null
    });
    px0 += w;
  }

  for (const p of planks) {
    for (let x = p.x0; x < p.x0 + p.w; x++) {
      const u = x - p.x0;
      for (let y = 0; y < H; y++) {
        const yn = y / H * p.ny; // periodische Rausch-Koordinate
        // Jahresringe: Position wird erst in Pixeln verworfen (sanfte,
        // großflächige Wellen), dann in Ringe umgerechnet – so bleibt
        // die Verwerfung immer kleiner als die Ringbreite
        const wob = fbm(u / 170 + p.phase, yn);
        let v = (u + p.warpAmp * wob) * p.freq + p.phase;
        // Astknoten: biegt die Ringe um sich herum und dunkelt ab
        let knotDark = 0;
        if (p.knot) {
          const dx = u - p.knot.u * p.w;
          let dy = Math.abs(y - p.knot.y);
          dy = Math.min(dy, H - dy); // Torus-Abstand → nahtlos
          const dist = Math.sqrt(dx * dx + dy * dy * 0.35);
          v += 40 / (dist + 16);
          knotDark = Math.max(0, 1 - dist / (p.knot.r * 2)) * 0.55;
        }
        const t = v - Math.floor(v);
        // asymmetrische Ringe: schmale dunkle Spätholz-Linie, breites Frühholz
        const band = t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82;
        // feine Faser (länglich in Plankenrichtung) + breite Längsstreifen
        const fine = (noise(u * 0.3, yn * 47) - 0.5) * 0.10;
        const streak = (noise(u * 0.08 + p.phase, yn * 2) - 0.5) * 0.18;
        let k = (0.24 + band * 0.70) * p.tone + fine + streak - knotDark;
        k = Math.max(0, Math.min(1, k));
        const [r, gg, bb] = lerp3(k);
        const o = (y * W + x) * 4;
        data[o] = r; data[o + 1] = gg; data[o + 2] = bb; data[o + 3] = 255;
      }
    }
  }
  g.putImageData(img, 0, 0);

  // Fugen mit Lichtkante
  for (const p of planks) {
    g.fillStyle = 'rgba(4,2,1,0.85)';
    g.fillRect(p.x0 + p.w - 2, 0, 2, H);
    g.fillStyle = 'rgba(255,215,160,0.06)';
    g.fillRect(p.x0, 0, 1.5, H);
  }
  return c.toDataURL('image/png');
}

function applyWood() {
  document.body.style.backgroundImage =
    // sanfter Lichtschein oben links + Vignette, darunter die Holzkachel
    'radial-gradient(ellipse 120% 90% at 35% 15%, rgba(255,230,180,.07), transparent 65%),' +
    'radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 50%, rgba(0,0,0,.38) 100%),' +
    `url(${makeWoodTexture()})`;
  document.body.style.backgroundRepeat = 'no-repeat, no-repeat, repeat';
}

// =========================================================
//  Tisch-Layout: Brett links (quer) bzw. oben (hochkant),
//  20px Einzug; Rest der Holzfläche = Würfelzone
// =========================================================
function layoutTable() {
  const W = window.innerWidth, H = window.innerHeight;
  const M = 20, GAP = 18;
  const landscape = W >= H;
  const minDice = Math.max(140, Math.min(W, H) * 0.30);

  let S;
  if (landscape) S = Math.min(H - 2 * M, W - 2 * M - minDice);
  else           S = Math.min(W - 2 * M, H - 2 * M - minDice);
  S = Math.max(160, S);
  boardCss = S;

  const dpr = window.devicePixelRatio || 1;
  canvas.style.left = M + 'px';
  canvas.style.top = M + 'px';
  canvas.style.width = S + 'px';
  canvas.style.height = S + 'px';
  canvas.width = Math.round(S * dpr);
  canvas.height = Math.round(S * dpr);

  ds = S / 12 * 1.35;
  // global setzen, damit auch Schatten und Leuchtring (Geschwister) sie sehen
  document.documentElement.style.setProperty('--ds', ds + 'px');
  // 45% des Eckradius (16% von ds): Kern-Ecken bleiben sicher innerhalb
  // der Rundung der Außenflächen, auch unter Perspektive
  document.documentElement.style.setProperty('--inset', Math.max(2, ds * 0.16 * 0.45) + 'px');

  if (landscape) diceZone = { x0: M + S + GAP, y0: M, x1: W - M, y1: H - M };
  else           diceZone = { x0: M, y0: M + S + GAP, x1: W - M, y1: H - M };

  // Spielaufbau-Anzeige (Anleitung + Start) füllt die Würfelzone
  const sz = document.getElementById('setupZone');
  sz.style.left = diceZone.x0 + 'px';
  sz.style.top = diceZone.y0 + 'px';
  sz.style.width = (diceZone.x1 - diceZone.x0) + 'px';
  sz.style.height = (diceZone.y1 - diceZone.y0) + 'px';
  if (typeof closePalette === 'function' && game.phase === 'setup') closePalette();

  // Menü-Knopf in die Ecke der Würfelzone legen
  menuBtn.style.right = '20px';
  menuEl.style.right = '20px';
  if (landscape) {
    menuBtn.style.top = '20px';  menuBtn.style.bottom = '';
    menuEl.style.top = '76px';   menuEl.style.bottom = '';
  } else {
    menuBtn.style.top = '';      menuBtn.style.bottom = '20px';
    menuEl.style.top = '';       menuEl.style.bottom = '76px';
  }

  clampDiceToZone();
  resizeGL();
}

function unit() { return canvas.width / 12; }

function circle(x, y, r) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
}

function pieceXY(pIdx, i) {
  const pos = game.players[pIdx].pieces[i];
  if (pos === -1) {
    let slot = 0;
    for (let j = 0; j < i; j++) if (game.players[pIdx].pieces[j] === -1) slot++;
    return HOME_POS[pIdx][slot];
  }
  if (pos < 40) return FIELD_POS[pos];
  return GOAL_POS[pIdx][pos - 40];
}

function drawPiece(x, y, pIdx, r, highlight, t) {
  // Schatten
  ctx.fillStyle = 'rgba(0,0,0,.25)';
  circle(x + r * 0.12, y + r * 0.18, r);
  ctx.fill();

  // Körper mit leichtem 3D-Effekt
  const grad = ctx.createRadialGradient(x - r * 0.35, y - r * 0.35, r * 0.15, x, y, r * 1.15);
  grad.addColorStop(0, '#ffffff');
  grad.addColorStop(0.25, HEX[pIdx]);
  grad.addColorStop(1, HEX_DARK[pIdx]);
  ctx.fillStyle = grad;
  circle(x, y, r);
  ctx.fill();
  ctx.lineWidth = Math.max(1.5, r * 0.14);
  ctx.strokeStyle = HEX_DARK[pIdx];
  ctx.stroke();

  if (highlight) {
    const pulse = 0.5 + 0.5 * Math.sin(t / 180);
    ctx.lineWidth = r * (0.18 + 0.12 * pulse);
    ctx.strokeStyle = `rgba(255,215,0,${0.55 + 0.45 * pulse})`;
    circle(x, y, r * 1.22);
    ctx.stroke();
  }
}

function draw(t) {
  const u = unit();
  const W = canvas.width;

  // Hintergrund (helles Gelb wie im Original)
  ctx.fillStyle = '#fff8dc';
  ctx.fillRect(0, 0, W, W);

  // Verbindungslinien des Laufwegs
  ctx.strokeStyle = '#c9b98a';
  ctx.lineWidth = u * 0.10;
  ctx.beginPath();
  ctx.moveTo(FIELD_POS[0][0] * u, FIELD_POS[0][1] * u);
  for (let i = 1; i < 40; i++) ctx.lineTo(FIELD_POS[i][0] * u, FIELD_POS[i][1] * u);
  ctx.closePath();
  ctx.stroke();

  const rField = u * 0.42;
  const rPiece = u * 0.34;

  // Markierung für den aktiven Spieler hinter dessen Homebase
  if (game.phase !== 'setup' && game.phase !== 'over' && game.players.length) {
    const c = game.current;
    const hp = HOME_POS[c];
    const cx = (hp[0][0] + hp[3][0]) / 2 * u;
    const cy = (hp[0][1] + hp[3][1]) / 2 * u;
    const pulse = 0.5 + 0.5 * Math.sin(t / 350);
    ctx.fillStyle = HEX[c] + Math.round(38 + 40 * pulse).toString(16).padStart(2, '0');
    ctx.beginPath();
    ctx.roundRect(cx - u * 1.35, cy - u * 1.35, u * 2.7, u * 2.7, u * 0.4);
    ctx.fill();
  }

  // 40 Laufwegfelder
  for (let i = 0; i < 40; i++) {
    const startIdx = START.indexOf(i);
    ctx.fillStyle = startIdx >= 0 ? HEX_LIGHT[startIdx] : '#ffffff';
    ctx.strokeStyle = startIdx >= 0 ? HEX[startIdx] : '#333';
    ctx.lineWidth = startIdx >= 0 ? u * 0.09 : u * 0.05;
    circle(FIELD_POS[i][0] * u, FIELD_POS[i][1] * u, rField);
    ctx.fill();
    ctx.stroke();
    if (startIdx >= 0) {
      ctx.fillStyle = HEX[startIdx];
      ctx.font = `bold ${u * 0.4}px "Segoe UI", sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('A', FIELD_POS[i][0] * u, FIELD_POS[i][1] * u + u * 0.02);
    }
  }

  // Zielfelder und Homebases
  for (let q = 0; q < 4; q++) {
    ctx.strokeStyle = HEX[q];
    ctx.lineWidth = u * 0.07;
    for (const [gx, gy] of GOAL_POS[q]) {
      ctx.fillStyle = HEX_LIGHT[q];
      circle(gx * u, gy * u, rField * 0.88);
      ctx.fill();
      ctx.stroke();
    }
    for (const [hx, hy] of HOME_POS[q]) {
      ctx.fillStyle = '#ffffff';
      circle(hx * u, hy * u, rField * 0.92);
      ctx.fill();
      ctx.stroke();
    }
  }

  // Spielaufbau: Pools zeigen 4 Figuren in der gewählten Farbe plus
  // Typ-Symbol; "Nicht dabei" = leere Homebase. Kein Spielgeschehen.
  if (game.phase === 'setup') {
    const BADGE = { human: '👤', ki: '🤖' };
    const BADGE_POS = [[2, 3.55], [10, 3.55], [10, 8.45], [2, 8.45]];
    for (let q = 0; q < 4; q++) {
      if (setupTypes[q] === 'off') continue;
      for (const [hx, hy] of HOME_POS[q]) drawPiece(hx * u, hy * u, q, rPiece, false, t);
      const [bx, by] = BADGE_POS[q];
      ctx.fillStyle = 'rgba(255,255,255,.85)';
      circle(bx * u, by * u, u * 0.42);
      ctx.fill();
      ctx.font = `${u * 0.5}px "Segoe UI Emoji", "Segoe UI", sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(BADGE[setupTypes[q]], bx * u, by * u + u * 0.03);
    }
    drawParticles(u);
    return;
  }

  if (game.players.length) {
    // Figuren zeichnen (aktueller Spieler zuletzt, damit er oben liegt)
    const order = [0, 1, 2, 3].sort((a, b) => (a === game.current) - (b === game.current));
    for (const q of order) {
      const p = game.players[q];
      if (p.type === 'off') continue;
      for (let i = 0; i < 4; i++) {
        const [x, y] = pieceXY(q, i);
        const hl = game.phase === 'move' && q === game.current && isHuman(q) &&
                   game.movable.some(m => m.piece === i);
        drawPiece(x * u, y * u, q, rPiece, hl, t);
      }
    }

    // Mögliche Schlagfelder rot markieren (Strafregel-Warnung)
    if (game.phase === 'move' && isHuman(game.current)) {
      for (const m of game.captureList) {
        const [tx, ty] = FIELD_POS[m.to];
        const pulse = 0.5 + 0.5 * Math.sin(t / 150);
        ctx.lineWidth = u * 0.08;
        ctx.strokeStyle = `rgba(220,30,30,${0.35 + 0.55 * pulse})`;
        circle(tx * u, ty * u, rField * 1.12);
        ctx.stroke();
      }
    }
  }

  drawParticles(u);
}

let lastT = 0;
function frame(t) {
  const dt = Math.min(0.05, (t - lastT) / 1000 || 0.016);
  lastT = t;
  updateParticles(dt);
  updateDice(dt);
  renderGL();
  draw(t);
  requestAnimationFrame(frame);
}

// =========================================================
//  Eingabe auf dem Brett
// =========================================================
canvas.addEventListener('pointerdown', e => {
  const rect = canvas.getBoundingClientRect();
  const dpr = canvas.width / rect.width;
  const mx = (e.clientX - rect.left) * dpr;
  const my = (e.clientY - rect.top) * dpr;
  const u = unit();

  // ---- Spielaufbau: Klicks auf die Pools ----
  if (game.phase === 'setup') {
    const ux = mx / u, uy = my / u;
    const POOL_RECTS = [
      [0.6, 0.6, 3.4, 4.0], [8.6, 0.6, 11.4, 4.0],
      [8.6, 8.0, 11.4, 11.4], [0.6, 8.0, 3.4, 11.4]
    ];
    for (let q = 0; q < 4; q++) {
      const [x0, y0, x1, y1] = POOL_RECTS[q];
      if (ux >= x0 && ux <= x1 && uy >= y0 && uy <= y1) {
        // Figur getroffen → Farbwahl; sonst → Typ durchschalten
        if (setupTypes[q] !== 'off') {
          for (const [hx, hy] of HOME_POS[q]) {
            if (Math.hypot(ux - hx, uy - hy) < 0.52) { openPalette(q); return; }
          }
        }
        closePalette();
        cycleType(q);
        return;
      }
    }
    closePalette();
    return;
  }

  if (game.phase !== 'move' || !isHuman(game.current)) return;

  for (const m of game.movable) {
    // Klick auf die Figur …
    const [px, py] = pieceXY(game.current, m.piece);
    if (Math.hypot(mx - px * u, my - py * u) < u * 0.55) return executeMove(m);
    // … oder auf das Zielfeld des Zuges
    const tpos = m.to < 40 ? FIELD_POS[m.to] : GOAL_POS[game.current][m.to - 40];
    if (Math.hypot(mx - tpos[0] * u, my - tpos[1] * u) < u * 0.55) return executeMove(m);
  }
});

window.addEventListener('resize', layoutTable);

// =========================================================
//  Hamburger-Menü
// =========================================================
menuBtn.addEventListener('click', e => {
  e.stopPropagation();
  menuEl.classList.toggle('hidden');
});

document.addEventListener('pointerdown', e => {
  if (!menuEl.classList.contains('hidden') &&
      !menuEl.contains(e.target) && e.target !== menuBtn && !menuBtn.contains(e.target)) {
    menuEl.classList.add('hidden');
  }
  // Farb-Popup schließen bei Klick daneben (Canvas regelt sich selbst)
  if (paletteSeat >= 0 && !palettePopEl.contains(e.target) && e.target !== canvas) {
    closePalette();
  }
});

document.getElementById('mNew').addEventListener('click', () => {
  menuEl.classList.add('hidden');
  showSetup();
});

document.getElementById('mLog').addEventListener('click', () => {
  const open = logEl.classList.toggle('open');
  document.getElementById('mLog').textContent =
    open ? '📜 Protokoll ausblenden' : '📜 Protokoll anzeigen';
});

// =========================================================
//  Setup / Neues Spiel
//  Konfiguration direkt am Brett: Figur antippen = Farbe wählen
//  (Popup am Pool), Pool antippen = Mensch/Computer/Nicht dabei
//  durchschalten. Start über den zentralen Button auf dem Holz.
// =========================================================
const setupTypes = ['human', 'ki', 'off', 'off']; // Typ je Spielerplatz
let paletteSeat = -1;                             // Pool, dessen Palette offen ist

const setupZoneEl = document.getElementById('setupZone');
const palettePopEl = document.getElementById('palettePop');
const btnStartEl = document.getElementById('btnStart');
const setupHintEl = document.getElementById('setupHint');

function buildPalettePop() {
  palettePopEl.innerHTML = '';
  PALETTE.forEach((c, ci) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'colorbtn';
    b.style.background = c.hex;
    b.title = c.name;
    b.addEventListener('click', e => {
      e.stopPropagation();
      if (paletteSeat >= 0) {
        setupColors[paletteSeat] = ci;
        applyColors();
        refreshStart();
      }
      closePalette();
    });
    palettePopEl.appendChild(b);
  });
}

function openPalette(seat) {
  paletteSeat = seat;
  // aktuelle Farbe markieren
  Array.prototype.forEach.call(palettePopEl.children, (b, ci) =>
    b.classList.toggle('sel', setupColors[seat] === ci));
  palettePopEl.classList.remove('hidden');
  // Neben dem Pool platzieren, zur Brettmitte hin
  const u = boardCss / 12, M = 20;
  const pw = palettePopEl.offsetWidth, ph = palettePopEl.offsetHeight;
  const left = (seat === 0 || seat === 3) ? M + 3.5 * u : M + 8.5 * u - pw;
  const top = (seat === 0 || seat === 1) ? M + 0.9 * u : M + 11.1 * u - ph;
  palettePopEl.style.left = left + 'px';
  palettePopEl.style.top = top + 'px';
}

function closePalette() {
  paletteSeat = -1;
  palettePopEl.classList.add('hidden');
}

function cycleType(seat) {
  const order = ['human', 'ki', 'off'];
  setupTypes[seat] = order[(order.indexOf(setupTypes[seat]) + 1) % 3];
  if (setupTypes[seat] === 'off' && paletteSeat === seat) closePalette();
  refreshStart();
}

// Start nur, wenn mind. 2 Spieler aktiv sind und alle Farben verschieden
function setupValid() {
  const act = [0, 1, 2, 3].filter(s => setupTypes[s] !== 'off');
  if (act.length < 2) return 'Mindestens 2 Spieler auswählen!';
  const cols = act.map(s => setupColors[s]);
  if (new Set(cols).size !== cols.length) return 'Alle Spielerfarben müssen unterschiedlich sein!';
  return null;
}

function refreshStart() {
  const err = setupValid();
  btnStartEl.disabled = !!err;
  setupHintEl.textContent = err || ' ';
}

function startGame() {
  if (setupValid()) return;
  const types = setupTypes.slice();
  closePalette();
  setupZoneEl.classList.add('hidden');

  game.seq++;
  game.players = types.map(t => ({ type: t, pieces: [-1, -1, -1, -1], finished: false }));
  game.ranking = [];
  game.rolling = false;
  game.captureList = [];
  particles.length = 0;
  logLines.length = 0;
  logEl.innerHTML = '';
  document.getElementById('gameover').classList.add('hidden');

  // Würfel zurücksetzen und in die Zone legen
  dice.state = 'idle';
  dice.vx = 0; dice.vy = 0; dice.z = 0; dice.vz = 0;
  placeDiceInZone();
  diceEl.classList.remove('hidden');
  shadowEl.classList.remove('hidden');
  glowEl.classList.remove('hidden');

  game.current = types.findIndex(t => t !== 'off');
  addLog('Neues Spiel gestartet. Viel Glück!');
  startTurn();
}

function showSetup() {
  game.seq++;
  game.phase = 'setup';
  game.rolling = false;
  diceEl.classList.add('hidden');
  shadowEl.classList.add('hidden');
  glowEl.classList.add('hidden');
  document.getElementById('gameover').classList.add('hidden');
  setupZoneEl.classList.remove('hidden');
  refreshStart();
}

document.getElementById('btnStart').addEventListener('click', startGame);
document.getElementById('btnAgain').addEventListener('click', showSetup);

// ---------- Los geht's ----------
applyWood();
buildPalettePop();
buildCube();
initGL();
layoutTable();
placeDiceInZone();
cubeEl.style.transform = qToCss(dice.q);
applyLighting();
refreshStart();
requestAnimationFrame(frame);
