import 'dart:math';

import 'board.dart';

/// Spielertyp je Pool.
enum PlayerType { human, ki, off }

/// Phasenautomat des Spiels (entspricht JS-game.phase).
enum GamePhase { setup, roll, move, anim, over }

/// Ein Zug: Welche Figur, welcher Zugtyp, wohin?
class Move {
  /// Index 0..3 der Figur im Pool des aktiven Spielers.
  final int piece;

  /// 'out' = aus Homebase, 'board' = Laufweg, 'goal' = Zielfeld.
  final String type;

  /// Zielposition (0..39 Spielfeld, 40..43 Zielfeld, encoded wie JS).
  final int to;

  const Move(this.piece, this.type, this.to);
}

/// Zustand eines Spielers.
///
/// `pieces[i]` codiert die Figur:
///   -1     = Homebase
///   0..39  = Spielfeld (absolut)
///   40..43 = Zielfeld 0..3
class Player {
  PlayerType type;
  List<int> pieces = [-1, -1, -1, -1];
  bool finished = false;

  Player(this.type);
}

/// Zentrale Game-State-Klasse. Die Regeln wurden 1:1 aus game.js übertragen;
/// das UI hört bei jeder Änderung auf `version`, um neu zu zeichnen.
class GameState {
  final List<Player> players = [];

  /// Welche Palettenfarbe je Spielerplatz (Index in [palette]).
  List<int> colors = [0, 1, 2, 3];

  /// Welcher Spielertyp je Spielerplatz in der Setup-Phase.
  List<PlayerType> setupTypes = [
    PlayerType.human, PlayerType.ki, PlayerType.off, PlayerType.off
  ];

  int current = 0;
  int? dice;
  int rollsLeft = 1;
  GamePhase phase = GamePhase.setup;

  /// Aktuell mögliche Züge (nur in [GamePhase.move] gefüllt).
  List<Move> movable = [];

  /// Schlagzüge des aktuellen Wurfs (für die Strafregel).
  List<Move> captureList = [];

  /// Abschlussreihenfolge (Indizes der Spieler).
  List<int> ranking = [];

  /// Wird beim „Neues Spiel" erhöht – entwertet alte verzögerte Aktionen.
  int seq = 0;

  /// Ergebnis-Log (neueste Einträge zuerst, max. 30).
  final List<String> log = [];

  /// Inkrementiert bei jeder Mutation; UI lauscht darauf.
  int version = 0;

  void _bump() => version++;

  void addLog(String text) {
    log.insert(0, text);
    if (log.length > 30) log.removeLast();
    _bump();
  }

  bool isHuman(int p) => players[p].type == PlayerType.human;
  bool isKi(int p) => players[p].type == PlayerType.ki;

  bool ownPieceAt(int pIdx, int pos) =>
      players[pIdx].pieces.contains(pos);

  /// `(player, piece)` einer gegnerischen Figur auf [pos] oder null.
  ({int player, int piece})? opponentAt(int pos, int excludeIdx) {
    for (var q = 0; q < 4; q++) {
      if (q == excludeIdx) continue;
      final p = players[q];
      if (p.type == PlayerType.off) continue;
      final j = p.pieces.indexOf(pos);
      if (j >= 0) return (player: q, piece: j);
    }
    return null;
  }

  bool isCaptureMove(int pIdx, Move m) =>
      m.to < 40 && opponentAt(m.to, pIdx) != null;

  /// Im Zielfeld darf nicht übersprungen werden.
  bool goalPathFree(int pIdx, int fromG, int toG) {
    for (var g = fromG + 1; g <= toG; g++) {
      if (ownPieceAt(pIdx, 40 + g)) return false;
    }
    return true;
  }

  /// Liste aller legalen Züge des Spielers [pIdx] bei Augenzahl [w].
  List<Move> computeMoves(int pIdx, int w) {
    final p = players[pIdx];
    final start = startField[pIdx];
    final moves = <Move>[];

    for (var i = 0; i < 4; i++) {
      final pos = p.pieces[i];
      if (pos == -1) {
        // Aus der Homebase nur mit einer 6 und nur, wenn das Startfeld frei
        if (w == 6 && !ownPieceAt(pIdx, start)) {
          moves.add(Move(i, 'out', start));
        }
      } else if (pos < 40) {
        final rel = (pos - start + 40) % 40;
        final trel = rel + w;
        if (trel <= 39) {
          final t = (pos + w) % 40;
          if (!ownPieceAt(pIdx, t)) moves.add(Move(i, 'board', t));
        } else {
          final g = trel - 40;
          if (g <= 3 && goalPathFree(pIdx, -1, g)) {
            moves.add(Move(i, 'goal', 40 + g));
          }
        }
      } else {
        final g = pos - 40;
        final ng = g + w;
        if (ng <= 3 && goalPathFree(pIdx, g, ng)) {
          moves.add(Move(i, 'goal', 40 + ng));
        }
      }
    }

    // ---- Pflichtregeln ----
    final homeCount = p.pieces.where((x) => x == -1).length;
    if (homeCount > 0) {
      if (w == 6) {
        final outMoves = moves.where((m) => m.type == 'out').toList();
        if (outMoves.isNotEmpty) return outMoves;
      }
      final startPiece = p.pieces.indexOf(start);
      if (startPiece >= 0) {
        final clearing = moves.where((m) => m.piece == startPiece).toList();
        if (clearing.isNotEmpty) return clearing;
      }
    }
    return moves;
  }

  /// Hat der Spieler überhaupt bewegliche Figuren (3-Versuche-Regel)?
  bool hasMovablePotential(int pIdx) {
    final p = players[pIdx];
    if (p.pieces.any((x) => x >= 0 && x < 40)) return true;
    for (final pos in p.pieces) {
      if (pos >= 40) {
        final g = pos - 40;
        for (var w = 1; w <= 3; w++) {
          if (g + w <= 3 && goalPathFree(pIdx, g, g + w)) return true;
        }
      }
    }
    return false;
  }

  /// Aktive, noch nicht fertige Spielerindizes.
  List<int> activeUnfinished() {
    final res = <int>[];
    for (var q = 0; q < 4; q++) {
      final p = players[q];
      if (p.type != PlayerType.off && !p.finished) res.add(q);
    }
    return res;
  }

  /// Bedrohte Position (für die KI-Flucht-Heuristik).
  bool isDangerous(int pIdx, int abs) {
    for (var q = 0; q < 4; q++) {
      if (q == pIdx) continue;
      final op = players[q];
      if (op.type == PlayerType.off || op.finished) continue;
      for (final qp in op.pieces) {
        if (qp >= 0 && qp < 40) {
          final d = (abs - qp + 40) % 40;
          if (d >= 1 && d <= 6) {
            final qrel = (qp - startField[q] + 40) % 40;
            if (qrel + d <= 39) return true;
          }
        }
      }
      if (abs == startField[q] && op.pieces.any((x) => x == -1)) return true;
    }
    return false;
  }

  /// KI-Heuristik – Schlagen > Ziel > Rauskommen > Flucht.
  Move? aiPickMove(List<Move> moves, int pIdx) {
    final caps = moves.where((m) => isCaptureMove(pIdx, m)).toList();
    final pool = caps.isNotEmpty ? caps : moves;
    final rnd = Random();
    Move? best;
    double bestScore = double.negativeInfinity;
    for (final m in pool) {
      var s = 0.0;
      if (m.type == 'out')  s += 55;
      if (m.type == 'goal') s += 70 + (m.to - 40) * 2;
      if (m.to < 40) {
        if (opponentAt(m.to, pIdx) != null) s += 100;
        final from = players[pIdx].pieces[m.piece];
        if (from >= 0 && from < 40 && isDangerous(pIdx, from)) s += 25;
        if (isDangerous(pIdx, m.to)) s -= 30;
        final rel = (m.to - startField[pIdx] + 40) % 40;
        s += rel * 0.3;
      }
      s += rnd.nextDouble() * 2;
      if (s > bestScore) {
        bestScore = s;
        best = m;
      }
    }
    return best;
  }

  /// Pfad einer Figur bei einem Zug (für die Schritt-Animation).
  List<int> makePath(int pIdx, Move m) {
    final pos = players[pIdx].pieces[m.piece];
    final path = <int>[];
    if (m.type == 'out') {
      path.add(startField[pIdx]);
    } else if (pos < 40) {
      final start = startField[pIdx];
      final rel = (pos - start + 40) % 40;
      for (var step = 1; step <= dice!; step++) {
        final r = rel + step;
        path.add(r <= 39 ? (start + r) % 40 : 40 + (r - 40));
      }
    } else {
      for (var g = pos - 40 + 1; g <= m.to - 40; g++) path.add(40 + g);
    }
    return path;
  }

  /// Auf welcher (x,y)-Position liegt eine Figur gerade?
  List<num> pieceXY(int pIdx, int i) {
    final pos = players[pIdx].pieces[i];
    if (pos == -1) {
      var slot = 0;
      for (var j = 0; j < i; j++) {
        if (players[pIdx].pieces[j] == -1) slot++;
      }
      return homePos[pIdx][slot];
    }
    if (pos < 40) return fieldPos[pos];
    return goalPos[pIdx][pos - 40];
  }

  /// Setup-Validierung – Rückgabe ist null, wenn alles ok.
  String? setupValid() {
    final act = [0, 1, 2, 3]
        .where((s) => setupTypes[s] != PlayerType.off)
        .toList();
    if (act.length < 2) return 'min-players';
    final cols = act.map((s) => colors[s]).toSet();
    if (cols.length != act.length) return 'duplicate-color';
    return null;
  }

  /// Setzt einen frischen Spielzustand für den gewählten Setup auf.
  void startGame() {
    if (setupValid() != null) return;
    seq++;
    players
      ..clear()
      ..addAll(setupTypes.map((t) => Player(t)));
    ranking.clear();
    captureList.clear();
    log.clear();
    current = setupTypes.indexWhere((t) => t != PlayerType.off);
    phase = GamePhase.roll;
    rollsLeft = 1;
    dice = null;
    movable.clear();
    _bump();
  }

  /// Beginnt einen neuen Zug – Rolls-Left je nach beweglicher Lage.
  void startTurn() {
    phase = GamePhase.roll;
    dice = null;
    movable.clear();
    captureList.clear();
    rollsLeft = hasMovablePotential(current) ? 1 : 3;
    _bump();
  }

  /// Wertet einen Wurf [w] aus und entscheidet, was als nächstes passiert.
  /// Gibt die Klasse des Folgeereignisses zurück (vom UI als Trigger genutzt).
  RollOutcome resolveRoll(int w) {
    dice = w;
    final c = current;
    final moves = computeMoves(c, w);
    captureList = moves.where((m) => isCaptureMove(c, m)).toList();

    if (moves.isNotEmpty) {
      phase = GamePhase.move;
      movable = moves;
      _bump();
      return RollOutcome.canMove;
    }

    // Kein Zug möglich
    if (w == 6) {
      phase = GamePhase.roll;
      rollsLeft = 1;
      _bump();
      return RollOutcome.sixNoMove;
    }
    rollsLeft--;
    if (rollsLeft > 0) {
      phase = GamePhase.roll;
      _bump();
      return RollOutcome.retry;
    }
    phase = GamePhase.anim;
    _bump();
    return RollOutcome.pass;
  }

  /// Wendet das Ergebnis eines Zuges an (Schlagen, Strafregel, Ranking,
  /// Sieg-Check). Liefert eine Liste von Ereignissen, die das UI für
  /// Sound + Partikel benutzt.
  List<MoveEvent> finalizeMove(Move m) {
    final c = current;
    final events = <MoveEvent>[];
    final pos = players[c].pieces[m.piece];
    var hasCaptured = false;

    // Schlagen
    if (pos < 40) {
      final hit = opponentAt(pos, c);
      if (hit != null) {
        events.add(MoveEvent.capture(pos, hit.player));
        players[hit.player].pieces[hit.piece] = -1;
        hasCaptured = true;
      }
    }

    // Strafregel
    if (!hasCaptured && captureList.isNotEmpty) {
      final others = captureList.where((cm) => cm.piece != m.piece).toList();
      final pun = (others.isNotEmpty ? others[0] : captureList[0]).piece;
      final coords = pieceXY(c, pun);
      events.add(MoveEvent.penalty(coords[0].toDouble(), coords[1].toDouble()));
      players[c].pieces[pun] = -1;
    }
    captureList.clear();

    if (m.type == 'out')  events.add(MoveEvent.bringOut());
    if (m.type == 'goal') events.add(MoveEvent.goal());

    // Fertig?
    final p = players[c];
    if (!p.finished && p.pieces.every((x) => x >= 40)) {
      p.finished = true;
      ranking.add(c);
      events.add(MoveEvent.finished());
    }

    // Spielende
    final remaining = activeUnfinished();
    if (remaining.length <= 1) {
      for (final q in remaining) ranking.add(q);
      phase = GamePhase.over;
      events.add(MoveEvent.gameOver());
    }

    _bump();
    return events;
  }

  /// Schaltet auf den nächsten aktiven Spieler weiter.
  void advancePlayer() {
    var n = current;
    for (var k = 1; k <= 4; k++) {
      n = (current + k) % 4;
      final p = players[n];
      if (p.type != PlayerType.off && !p.finished) break;
    }
    current = n;
    startTurn();
  }

  /// Schaltet einen Pool-Typ im Setup durch (Mensch → KI → Off).
  void cycleType(int seat) {
    const order = [PlayerType.human, PlayerType.ki, PlayerType.off];
    setupTypes[seat] = order[(order.indexOf(setupTypes[seat]) + 1) % 3];
    _bump();
  }

  void setColor(int seat, int colorIdx) {
    colors[seat] = colorIdx;
    _bump();
  }

  void showSetup() {
    seq++;
    phase = GamePhase.setup;
    ranking.clear();
    captureList.clear();
    log.clear();
    players.clear();
    _bump();
  }

  /// Friert ein laufendes Spiel ein und zeigt die Startseite, OHNE den
  /// Zustand (Figuren, aktueller Spieler, Rangliste) zu verwerfen – „Weiter-
  /// spielen" setzt darauf wieder auf. seq++ entwertet laufende KI-/Anim-Timer.
  void pauseToSetup() {
    seq++;
    phase = GamePhase.setup;
    _bump();
  }
}

/// Auswertung eines einzelnen Würfelwurfs.
enum RollOutcome {
  canMove,    // Es gibt Züge – Spieler/KI wählt
  sixNoMove,  // 6, aber kein Zug – nochmal würfeln
  retry,      // Noch Würfe übrig (3-Versuche-Regel)
  pass,       // Aussetzen
}

/// Ereignisse aus finalizeMove – das UI bindet sie an Sound und Partikel.
sealed class MoveEvent {
  const MoveEvent();
  factory MoveEvent.capture(int field, int player) = CaptureEvent;
  factory MoveEvent.penalty(double x, double y) = PenaltyEvent;
  factory MoveEvent.bringOut() = BringOutEvent;
  factory MoveEvent.goal() = GoalEvent;
  factory MoveEvent.finished() = FinishedEvent;
  factory MoveEvent.gameOver() = GameOverEvent;
}

class CaptureEvent extends MoveEvent {
  final int field;
  final int player;
  const CaptureEvent(this.field, this.player);
}

class PenaltyEvent extends MoveEvent {
  final double x;
  final double y;
  const PenaltyEvent(this.x, this.y);
}

class BringOutEvent extends MoveEvent { const BringOutEvent(); }
class GoalEvent extends MoveEvent { const GoalEvent(); }
class FinishedEvent extends MoveEvent { const FinishedEvent(); }
class GameOverEvent extends MoveEvent { const GameOverEvent(); }
