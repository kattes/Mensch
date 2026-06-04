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
  [[2,6],[3,6],[4,6],[5,6]],          // Rot   (Einlauf von Feld 39)
  [[6,2],[6,3],[6,4],[6,5]],          // Grün  (Einlauf von Feld 9)
  [[10,6],[9,6],[8,6],[7,6]],         // Gelb  (Einlauf von Feld 19)
  [[6,10],[6,9],[6,8],[6,7]]          // Blau  (Einlauf von Feld 29)
];

const HOME_POS = [
  [[1.4,1.4],[2.6,1.4],[1.4,2.6],[2.6,2.6]],     // Rot   oben links
  [[9.4,1.4],[10.6,1.4],[9.4,2.6],[10.6,2.6]],   // Grün  oben rechts
  [[9.4,9.4],[10.6,9.4],[9.4,10.6],[10.6,10.6]], // Gelb  unten rechts
  [[1.4,9.4],[2.6,9.4],[1.4,10.6],[2.6,10.6]]    // Blau  unten links
];

const START = [0, 10, 20, 30];
const NAMES = ['Rot', 'Grün', 'Gelb', 'Blau'];
const HEX      = ['#d62828', '#2e933c', '#f2b705', '#1f6fd6'];
const HEX_DARK = ['#8f1313', '#1c5c26', '#a87f02', '#114a92'];
const HEX_LIGHT= ['#f6cdcd', '#cdeacf', '#fbeec0', '#cce0f6'];

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
  ranking: [],
  rolling: false,
  seq: 0            // entwertet alte Timer nach "Neues Spiel"
};

// ---------- DOM ----------
const canvas    = document.getElementById('board');
const ctx       = canvas.getContext('2d');
const statusEl  = document.getElementById('status');
const diceEl    = document.getElementById('dice');
const diceLabel = document.getElementById('diceLabel');
const logEl     = document.getElementById('log');

const logLines = [];

// =========================================================
//  Hilfsfunktionen
// =========================================================
function schedule(fn, ms) {
  const s = game.seq;
  setTimeout(() => { if (s === game.seq) fn(); }, ms);
}

function nameSpan(pIdx) {
  return `<span class="dot" style="background:${HEX[pIdx]}"></span><strong>${NAMES[pIdx]}</strong>`;
}

function setStatus(html) { statusEl.innerHTML = html; }

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
  game.rollsLeft = hasMovablePotential(game.current) ? 1 : 3;
  renderDice(null);
  updateStatus();
  if (isKI(game.current)) schedule(rollDice, 900);
}

function updateStatus() {
  const c = game.current;
  if (game.phase === 'roll') {
    if (isKI(c)) {
      setStatus(`${nameSpan(c)} (Computer) würfelt …`);
      diceEl.classList.remove('rollable');
      diceLabel.textContent = ' ';
    } else {
      setStatus(`${nameSpan(c)} ist am Zug`);
      diceEl.classList.add('rollable');
      diceLabel.textContent = game.rollsLeft > 1
        ? `Würfeln! (noch ${game.rollsLeft} Versuche)` : 'Würfeln!';
    }
  } else if (game.phase === 'move') {
    diceEl.classList.remove('rollable');
    if (isKI(c)) {
      setStatus(`${nameSpan(c)} (Computer) überlegt …`);
      diceLabel.textContent = ' ';
    } else {
      setStatus(`${nameSpan(c)} – Figur anklicken`);
      diceLabel.textContent = `Gewürfelt: ${game.dice}`;
    }
  } else {
    diceEl.classList.remove('rollable');
    diceLabel.textContent = game.dice ? `Gewürfelt: ${game.dice}` : ' ';
  }
}

function rollDice() {
  if (game.phase !== 'roll' || game.rolling) return;
  game.rolling = true;
  diceEl.classList.remove('rollable');

  // kleine Würfelanimation
  let ticks = 0;
  const s = game.seq;
  const iv = setInterval(() => {
    if (s !== game.seq) { clearInterval(iv); return; }
    renderDice(1 + Math.floor(Math.random() * 6));
    if (++ticks >= 9) {
      clearInterval(iv);
      const w = 1 + Math.floor(Math.random() * 6);
      renderDice(w);
      game.rolling = false;
      resolveRoll(w);
    }
  }, 65);
}

function resolveRoll(w) {
  game.dice = w;
  const c = game.current;
  const moves = computeMoves(c, w);

  if (moves.length) {
    game.phase = 'move';
    game.movable = moves;
    updateStatus();
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
    updateStatus();
    if (isKI(c)) schedule(rollDice, 800);
    return;
  }

  game.rollsLeft--;
  if (game.rollsLeft > 0) {
    game.phase = 'roll';
    updateStatus();
    if (isKI(c)) schedule(rollDice, 700);
  } else {
    setStatus(`${nameSpan(c)} kann nicht ziehen`);
    addLog(`${NAMES[c]} kann nicht ziehen.`);
    game.phase = 'anim'; // Eingaben kurz sperren
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
  updateStatus();

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

  // Schlagen
  if (pos < 40) {
    const hit = opponentAt(pos, c);
    if (hit) {
      game.players[hit.player].pieces[hit.piece] = -1;
      addLog(`💥 ${NAMES[c]} schlägt ${NAMES[hit.player]} – Mensch ärgere Dich nicht!`);
    }
  }
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
  updateStatus();
  setStatus('Spiel beendet!');
  const medals = ['🥇', '🥈', '🥉', '4.'];
  document.getElementById('ranking').innerHTML = game.ranking
    .map((q, i) => `${medals[i]} <span class="dot" style="display:inline-block;width:.8em;height:.8em;border-radius:50%;background:${HEX[q]};border:2px solid rgba(255,255,255,.6)"></span> <strong>${NAMES[q]}</strong>${game.players[q].type === 'ki' ? ' (Computer)' : ''}`)
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
  let best = null, bestScore = -Infinity;
  for (const m of moves) {
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
//  Zeichnen
// =========================================================
function resizeCanvas() {
  const wrap = document.getElementById('boardwrap');
  const size = Math.max(200, Math.min(wrap.clientWidth, wrap.clientHeight));
  const dpr = window.devicePixelRatio || 1;
  canvas.style.width = size + 'px';
  canvas.style.height = size + 'px';
  canvas.width = Math.round(size * dpr);
  canvas.height = Math.round(size * dpr);
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

  if (!game.players.length) return;

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
}

function frame(t) {
  draw(t);
  requestAnimationFrame(frame);
}

// =========================================================
//  Eingabe
// =========================================================
function renderDice(v) {
  diceEl.innerHTML = '';
  for (let i = 0; i < 9; i++) {
    const sp = document.createElement('span');
    if (v && PIPS[v].includes(i)) sp.classList.add('on');
    diceEl.appendChild(sp);
  }
}

diceEl.addEventListener('click', () => {
  if (game.phase === 'roll' && isHuman(game.current)) rollDice();
});

document.addEventListener('keydown', e => {
  if (e.code === 'Space' && game.phase === 'roll' && isHuman(game.current)) {
    e.preventDefault();
    rollDice();
  }
});

canvas.addEventListener('pointerdown', e => {
  if (game.phase !== 'move' || !isHuman(game.current)) return;
  const rect = canvas.getBoundingClientRect();
  const dpr = canvas.width / rect.width;
  const mx = (e.clientX - rect.left) * dpr;
  const my = (e.clientY - rect.top) * dpr;
  const u = unit();

  for (const m of game.movable) {
    // Klick auf die Figur …
    const [px, py] = pieceXY(game.current, m.piece);
    if (Math.hypot(mx - px * u, my - py * u) < u * 0.55) return executeMove(m);
    // … oder auf das Zielfeld des Zuges
    const tpos = m.to < 40 ? FIELD_POS[m.to] : GOAL_POS[game.current][m.to - 40];
    if (Math.hypot(mx - tpos[0] * u, my - tpos[1] * u) < u * 0.55) return executeMove(m);
  }
});

window.addEventListener('resize', resizeCanvas);

// =========================================================
//  Setup / Neues Spiel
// =========================================================
function buildSetup() {
  const rows = document.getElementById('playerRows');
  rows.innerHTML = '';
  const defaults = ['human', 'ki', 'off', 'off'];
  for (let q = 0; q < 4; q++) {
    const row = document.createElement('div');
    row.className = 'player-row';
    row.innerHTML = `
      <div class="swatch" style="background:${HEX[q]}"></div>
      <div class="pname">${NAMES[q]}</div>
      <select id="ptype${q}">
        <option value="human">Mensch</option>
        <option value="ki">Computer</option>
        <option value="off">Nicht dabei</option>
      </select>`;
    rows.appendChild(row);
    row.querySelector('select').value = defaults[q];
  }
}

function startGame() {
  const types = [];
  for (let q = 0; q < 4; q++) types.push(document.getElementById('ptype' + q).value);
  const active = types.filter(t => t !== 'off').length;
  const hint = document.getElementById('setupHint');
  if (active < 2) {
    hint.textContent = 'Es müssen mindestens 2 Spieler mitspielen!';
    return;
  }
  hint.textContent = ' ';

  game.seq++;
  game.players = types.map(t => ({ type: t, pieces: [-1, -1, -1, -1], finished: false }));
  game.ranking = [];
  game.rolling = false;
  logLines.length = 0;
  logEl.innerHTML = '';
  document.getElementById('setup').classList.add('hidden');
  document.getElementById('gameover').classList.add('hidden');

  game.current = types.findIndex(t => t !== 'off');
  addLog('Neues Spiel gestartet. Viel Glück!');
  startTurn();
}

function showSetup() {
  game.seq++;
  game.phase = 'setup';
  document.getElementById('gameover').classList.add('hidden');
  document.getElementById('setup').classList.remove('hidden');
}

document.getElementById('btnStart').addEventListener('click', startGame);
document.getElementById('btnNew').addEventListener('click', showSetup);
document.getElementById('btnAgain').addEventListener('click', showSetup);

// ---------- Los geht's ----------
buildSetup();
resizeCanvas();
renderDice(null);
requestAnimationFrame(frame);
