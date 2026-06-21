import 'dart:ui';

/// 40 Laufweg-Felder als 12×12-Raster (Originalgeometrie aus dem Delphi-
/// Projekt, übernommen aus game.js).
const List<List<num>> fieldPos = [
  [1, 5],  [2, 5],  [3, 5],  [4, 5],  [5, 5],   //  0–4
  [5, 4],  [5, 3],  [5, 2],  [5, 1],  [6, 1],   //  5–9
  [7, 1],  [7, 2],  [7, 3],  [7, 4],  [7, 5],   // 10–14
  [8, 5],  [9, 5],  [10, 5], [11, 5], [11, 6],  // 15–19
  [11, 7], [10, 7], [9, 7],  [8, 7],  [7, 7],   // 20–24
  [7, 8],  [7, 9],  [7, 10], [7, 11], [6, 11],  // 25–29
  [5, 11], [5, 10], [5, 9],  [5, 8],  [5, 7],   // 30–34
  [4, 7],  [3, 7],  [2, 7],  [1, 7],  [1, 6],   // 35–39
];

/// Zielfelder je Spielerecke (Einlauf vom letzten Feld vor Start).
const List<List<List<num>>> goalPos = [
  [[2, 6],  [3, 6],  [4, 6],  [5, 6]],   // 0 = oben links  (von 39)
  [[6, 2],  [6, 3],  [6, 4],  [6, 5]],   // 1 = oben rechts (von 9)
  [[10, 6], [9, 6],  [8, 6],  [7, 6]],   // 2 = unten rechts(von 19)
  [[6, 10], [6, 9],  [6, 8],  [6, 7]],   // 3 = unten links (von 29)
];

/// Homebases (Wartepositionen vor dem Spiel).
const List<List<List<num>>> homePos = [
  [[1.4, 1.4], [2.6, 1.4], [1.4, 2.6], [2.6, 2.6]],
  [[9.4, 1.4], [10.6, 1.4], [9.4, 2.6], [10.6, 2.6]],
  [[9.4, 9.4], [10.6, 9.4], [9.4, 10.6], [10.6, 10.6]],
  [[1.4, 9.4], [2.6, 9.4], [1.4, 10.6], [2.6, 10.6]],
];

/// Startfeld je Spielerecke (0=o.l., 1=o.r., 2=u.r., 3=u.l.).
const List<int> startField = [0, 10, 20, 30];

/// Mögliche Augen-Positionen 0..8 in einem 3×3-Raster (für Würfel-Augen).
const Map<int, List<int>> dicePips = {
  1: [4],
  2: [2, 6],
  3: [2, 4, 6],
  4: [0, 2, 6, 8],
  5: [0, 2, 4, 6, 8],
  6: [0, 2, 3, 5, 6, 8],
};

/// Eine Palettenfarbe mit lokalisierbarem Schlüsselnamen.
class PaletteColor {
  final String key;
  final Color hex;
  const PaletteColor(this.key, this.hex);
}

/// Acht Palettenfarben; Hell-/Dunkelvarianten werden zur Laufzeit gemischt.
const List<PaletteColor> palette = [
  PaletteColor('red',       Color(0xFFD62828)),
  PaletteColor('green',     Color(0xFF2E933C)),
  PaletteColor('yellow',    Color(0xFFF2B705)),
  PaletteColor('blue',      Color(0xFF1F6FD6)),
  PaletteColor('black',     Color(0xFF2F2F2F)),
  PaletteColor('violet',    Color(0xFF8E44AD)),
  PaletteColor('orange',    Color(0xFFE8740C)),
  PaletteColor('turquoise', Color(0xFF0F9B8E)),
];

/// Mischt zwei Farben linear; [t]=0 → [a], [t]=1 → [b].
Color mixColor(Color a, Color b, double t) {
  int lerp(int x, int y) => (x + (y - x) * t).round();
  return Color.fromARGB(
    255,
    lerp(a.red, b.red),
    lerp(a.green, b.green),
    lerp(a.blue, b.blue),
  );
}

Color darken(Color c, [double t = 0.4]) =>
    mixColor(c, const Color(0xFF000000), t);

Color lighten(Color c, [double t = 0.78]) =>
    mixColor(c, const Color(0xFFFFFFFF), t);

/// Einzelne Funken-Partikel (Funke oder Druckwellen-Ring) für die
/// Schlag-Explosion. Koordinaten in Brett-Feldraster-Einheiten.
class Particle {
  double x, y;
  double vx, vy;
  double age = 0;
  final double life;
  final double r;
  final Color color;
  final bool ring;
  Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.life,
    required this.r,
    required this.color,
    this.ring = false,
  });
}
