import 'package:flutter/material.dart';

import 'board.dart';
import 'game.dart';

/// CustomPainter für das Brett – zeichnet Cornsilk-Hintergrund, Laufweg,
/// Felder, Pools und Spielfiguren in einem 12×12-Raster. Größe der
/// gezeichneten Fläche ist immer quadratisch (siehe layout in GameWidget).
class BoardPainter extends CustomPainter {
  final GameState state;
  final double pulseT;   // 0..1, für Highlight-Pulsieren
  final int dpadSetupIdx;  // 0..3 Pool, 4 Start, 5 Menü – nur Pool wird hier gezeichnet
  final int dpadMoveIdx;
  final bool dpadActive;
  final List<Particle> particles;

  BoardPainter({
    required this.state,
    required this.pulseT,
    required this.dpadSetupIdx,
    required this.dpadMoveIdx,
    required this.dpadActive,
    required this.particles,
  }) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 12; // ein Feldraster-Einheit
    final rField = u * 0.42;
    final rPiece = u * 0.34;

    // Hintergrund
    final bg = Paint()..color = const Color(0xFFFFF8DC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.width),
        const Radius.circular(10),
      ),
      bg,
    );

    // Verbindungslinien des Laufwegs
    final pathPaint = Paint()
      ..color = const Color(0xFFC9B98A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.10;
    final pathP = Path();
    pathP.moveTo(fieldPos[0][0] * u, fieldPos[0][1] * u);
    for (var i = 1; i < 40; i++) {
      pathP.lineTo(fieldPos[i][0] * u, fieldPos[i][1] * u);
    }
    pathP.close();
    canvas.drawPath(pathP, pathPaint);

    // Aktiver-Spieler-Hinterleuchtung (Pulsen hinter der Homebase)
    if (state.phase != GamePhase.setup &&
        state.phase != GamePhase.over &&
        state.players.isNotEmpty) {
      final c = state.current;
      final hp = homePos[c];
      final cx = (hp[0][0] + hp[3][0]) / 2 * u;
      final cy = (hp[0][1] + hp[3][1]) / 2 * u;
      final col = palette[state.colors[c]].hex.withOpacity(0.15 + 0.15 * pulseT);
      final paint = Paint()..color = col;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - u * 1.35, cy - u * 1.35, u * 2.7, u * 2.7),
          Radius.circular(u * 0.4),
        ),
        paint,
      );
    }

    // 40 Laufweg-Felder
    for (var i = 0; i < 40; i++) {
      final startIdx = startField.indexOf(i);
      final fill = Paint()
        ..color = startIdx >= 0
            ? lighten(palette[state.colors[startIdx]].hex)
            : Colors.white;
      final stroke = Paint()
        ..color = startIdx >= 0
            ? palette[state.colors[startIdx]].hex
            : const Color(0xFF333333)
        ..style = PaintingStyle.stroke
        ..strokeWidth = startIdx >= 0 ? u * 0.09 : u * 0.05;
      final pos = Offset(fieldPos[i][0] * u, fieldPos[i][1] * u);
      canvas.drawCircle(pos, rField, fill);
      canvas.drawCircle(pos, rField, stroke);
      if (startIdx >= 0) {
        _drawText(canvas, 'A', pos, u * 0.4,
            palette[state.colors[startIdx]].hex,
            bold: true);
      }
    }

    // Zielfelder + Homebases
    for (var q = 0; q < 4; q++) {
      final stroke = Paint()
        ..color = palette[state.colors[q]].hex
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.07;
      final fillGoal = Paint()..color = lighten(palette[state.colors[q]].hex);
      for (final g in goalPos[q]) {
        final p = Offset(g[0] * u, g[1] * u);
        canvas.drawCircle(p, rField * 0.88, fillGoal);
        canvas.drawCircle(p, rField * 0.88, stroke);
      }
      final fillHome = Paint()..color = Colors.white;
      for (final h in homePos[q]) {
        final p = Offset(h[0] * u, h[1] * u);
        canvas.drawCircle(p, rField * 0.92, fillHome);
        canvas.drawCircle(p, rField * 0.92, stroke);
      }
    }

    if (state.phase == GamePhase.setup) {
      _paintSetup(canvas, u, rPiece);
      _drawParticles(canvas, u);
      return;
    }

    // Figuren – aktiver Spieler zuletzt, damit er oben liegt
    if (state.players.isNotEmpty) {
      final order = [0, 1, 2, 3]
        ..sort((a, b) => (a == state.current ? 1 : 0)
                       - (b == state.current ? 1 : 0));
      // Welche Figur ist gerade per D-Pad fokussiert? (-1 wenn keine)
      final focusedPiece = (dpadActive &&
              state.phase == GamePhase.move &&
              state.isHuman(state.current) &&
              state.movable.isNotEmpty)
          ? state.movable[dpadMoveIdx.clamp(0, state.movable.length - 1)].piece
          : -1;

      for (final q in order) {
        final p = state.players[q];
        if (p.type == PlayerType.off) continue;
        for (var i = 0; i < 4; i++) {
          final xy = state.pieceXY(q, i);
          final isMovable = state.phase == GamePhase.move &&
              q == state.current &&
              state.isHuman(q) &&
              state.movable.any((m) => m.piece == i);
          final isFocused = isMovable && q == state.current && i == focusedPiece;
          _drawPiece(
            canvas,
            Offset(xy[0] * u, xy[1] * u),
            state.colors[q],
            rPiece,
            // Goldring nur für NICHT-fokussierte bewegliche Figuren –
            // sonst kollidiert er optisch mit dem weißen Fokusring.
            highlight: isMovable && !isFocused,
          );
        }
      }

      // Schlag-Felder rot warnen (Strafregel-Hinweis)
      if (state.phase == GamePhase.move &&
          state.isHuman(state.current)) {
        for (final m in state.captureList) {
          final c = fieldPos[m.to];
          final warn = Paint()
            ..color = Color.fromRGBO(220, 30, 30, 0.35 + 0.55 * pulseT)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.08;
          canvas.drawCircle(Offset(c[0] * u, c[1] * u), rField * 1.12, warn);
        }
      }

      // D-Pad-Fokus auf der gewählten beweglichen Figur: deutlich
      // prominenter als der dezente Goldring der anderen Movables.
      if (focusedPiece >= 0) {
        final p = state.pieceXY(state.current, focusedPiece);
        // Heller weißer Pulsring + kleiner gelber Glanz dahinter
        final outerGlow = Paint()
          ..color = Color.fromRGBO(255, 213, 79, 0.45 + 0.35 * pulseT)
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.24;
        canvas.drawCircle(
            Offset(p[0] * u, p[1] * u), rPiece * 1.55, outerGlow);
        final ring = Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.85 + 0.15 * pulseT)
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.16;
        canvas.drawCircle(
            Offset(p[0] * u, p[1] * u), rPiece * 1.45, ring);

        // Pfeil ▼ über der fokussierten Figur, in Spielerfarbe mit dunklem
        // Rand – auf dem hellen Brett deutlich sichtbarer als das frühere Weiß.
        final arrowSize = u * 0.55;
        final cx = p[0] * u;
        final ay = p[1] * u - rPiece * 1.75;
        final arrowPath = Path()
          ..moveTo(cx - arrowSize / 2, ay - arrowSize * 0.6)
          ..lineTo(cx + arrowSize / 2, ay - arrowSize * 0.6)
          ..lineTo(cx, ay)
          ..close();
        final arrowCol = palette[state.colors[state.current]].hex;
        canvas.drawPath(arrowPath, Paint()..color = arrowCol);
        canvas.drawPath(
          arrowPath,
          Paint()
            ..color = darken(arrowCol)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.045
            ..strokeJoin = StrokeJoin.round,
        );

        // Zielfeld dezent markieren
        final move = state.movable.firstWhere((m) => m.piece == focusedPiece);
        final t = move.to < 40
            ? fieldPos[move.to]
            : goalPos[state.current][move.to - 40];
        canvas.drawCircle(
          Offset(t[0] * u, t[1] * u),
          rField * 1.2,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.4 + 0.3 * pulseT)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.10,
        );
      }
    }

    _drawParticles(canvas, u);
  }

  void _drawParticles(Canvas canvas, double u) {
    for (final p in particles) {
      final k = p.age / p.life;
      if (p.ring) {
        final paint = Paint()
          ..color = Color.fromRGBO(255, 170, 0, 0.85 * (1 - k))
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.09 * (1 - k) + 1;
        canvas.drawCircle(
            Offset(p.x * u, p.y * u),
            (0.15 + k * 1.15) * u,
            paint);
      } else {
        final col = p.color;
        final paint = Paint()
          ..color = Color.fromRGBO(col.red, col.green, col.blue, 1 - k);
        canvas.drawCircle(
            Offset(p.x * u, p.y * u),
            p.r * u * (1 - k * 0.5),
            paint);
      }
    }
  }

  void _paintSetup(Canvas canvas, double u, double rPiece) {
    for (var q = 0; q < 4; q++) {
      if (state.setupTypes[q] == PlayerType.off) continue;
      for (final h in homePos[q]) {
        _drawPiece(canvas,
            Offset(h[0] * u, h[1] * u), state.colors[q], rPiece);
      }
      // Symbol mittig im Pool (Zentrum des 2×2-Figurenfeldes).
      final hp = homePos[q];
      final bx = (hp[0][0] + hp[3][0]) / 2 * u;
      final by = (hp[0][1] + hp[3][1]) / 2 * u;
      final bg = Paint()..color = Colors.white.withOpacity(0.85);
      canvas.drawCircle(Offset(bx, by), u * 0.42, bg);
      final emoji = state.setupTypes[q] == PlayerType.human ? '👤' : '🤖';
      _drawText(canvas, emoji, Offset(bx, by + u * 0.03),
          u * 0.5, Colors.black87);
    }

    // Fokus-Rahmen um den Pool, dessen Einstellungen gerade gelten. Wird auch
    // ohne aktives D-Pad gezeigt, damit beim Start der Default-Fokus (Rot)
    // sofort markiert ist. Farbe = Spielerfarbe (nicht Gelb).
    if (dpadSetupIdx >= 0 && dpadSetupIdx <= 3) {
      final q = dpadSetupIdx;
      final hp = homePos[q];
      final cx = (hp[0][0] + hp[3][0]) / 2 * u;
      final cy = (hp[0][1] + hp[3][1]) / 2 * u;
      final paint = Paint()
        ..color = palette[state.colors[q]].hex.withOpacity(0.6 + 0.35 * pulseT)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.11;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - u * 1.4, cy - u * 1.4, u * 2.8, u * 2.8),
          Radius.circular(u * 0.45),
        ),
        paint,
      );
    }
  }

  void _drawPiece(Canvas canvas, Offset center, int colorIdx, double r,
      {bool highlight = false}) {
    // Schatten
    final shadow = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(
        center + Offset(r * 0.12, r * 0.18), r, shadow);

    // Körper mit Radial-Gradient (weißer Lichtpunkt o.l.)
    final base = palette[colorIdx].hex;
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 1.05,
        colors: [Colors.white, base, darken(base)],
        stops: const [0.0, 0.25, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.15));
    canvas.drawCircle(center, r, body);
    final ring = Paint()
      ..color = darken(base)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14;
    canvas.drawCircle(center, r, ring);

    if (highlight) {
      // Dezenter Goldring (nicht pulsierend) für bewegliche, NICHT
      // fokussierte Figuren. So bleibt der weiße Fokusring optisch
      // ungestört dominanter.
      final hl = Paint()
        ..color = const Color(0x66FFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.10;
      canvas.drawCircle(center, r * 1.18, hl);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, double size,
      Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'sans-serif',
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.state.version != state.version ||
      old.pulseT != pulseT ||
      old.dpadSetupIdx != dpadSetupIdx ||
      old.dpadMoveIdx != dpadMoveIdx ||
      old.dpadActive != dpadActive;
}
