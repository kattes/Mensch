import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Hält die einmalig erzeugte Holzkachel (1024×1024, nahtlos). Wird in
/// main() vor runApp() generiert und im GameWidget als Hintergrund-Tile
/// gezeichnet.
ui.Image? cachedWood;

class _Knot {
  final double u, y, r;
  const _Knot(this.u, this.y, this.r);
}

class _Plank {
  final int x0, w;
  final double tone, freq, warpAmp, phase;
  final int ny;
  final _Knot? knot;
  const _Plank(
      this.x0, this.w, this.tone, this.freq, this.warpAmp, this.phase,
      this.ny, this.knot);
}

/// Prozeduraler dunkler Nussbaum, übernommen 1:1 aus makeWoodTexture()
/// in game.js: periodisches Wertrauschen + fBm verwirft Jahresringe,
/// Astknoten biegen die Ringe (Torus-Abstand → nahtlos), Planken mit
/// eigenem Ton/Frequenz, Fugen mit Lichtkante.
/// Erzeugt die Holztextur in [width]×[height] PHYSISCHEN Pixeln. Wird in
/// Bildschirmgröße erzeugt und im Painter 1:1 (ohne Kachelung) gezeichnet –
/// so gibt es keine Wiederholung und keine Tile-Naht, und die Maserung bleibt
/// pixelscharf. Die Planken laufen einfach über die ganze Breite.
Future<ui.Image> generateWoodTexture({int width = 1024, int height = 1024}) async {
  final W = width;
  final H = height;
  final data = Uint8List(W * H * 4);

  // Periodisches Wertrauschen (P×P) → nahtlose Kachel
  const P = 64;
  final lat = Float32List(P * P);
  final rnd = Random(7); // fester Seed → deterministische Maserung
  for (var i = 0; i < lat.length; i++) {
    lat[i] = rnd.nextDouble();
  }

  double noise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;
    final sx = xf * xf * (3 - 2 * xf);
    final sy = yf * yf * (3 - 2 * yf);
    final ix0 = ((xi % P) + P) % P;
    final iy0 = ((yi % P) + P) % P;
    final ix1 = (ix0 + 1) % P;
    final iy1 = (iy0 + 1) % P;
    final a = lat[iy0 * P + ix0];
    final b = lat[iy0 * P + ix1];
    final d = lat[iy1 * P + ix0];
    final e = lat[iy1 * P + ix1];
    return a + (b - a) * sx + (d - a) * sy + (a - b - d + e) * sx * sy;
  }

  double fbm(double x, double y) =>
      noise(x, y) * 0.55 +
      noise(x * 2.13, y * 2.13) * 0.28 +
      noise(x * 4.7, y * 4.7) * 0.17;

  // Drei Farbtöne: dunkler Nussbaum
  const dark  = [36.0, 22.0, 11.0];
  const mid   = [72.0, 45.0, 23.0];
  const lightC = [104.0, 69.0, 36.0];

  void colorAt(double k, List<double> out) {
    if (k < 0.6) {
      final s = k / 0.6;
      out[0] = dark[0] + (mid[0] - dark[0]) * s;
      out[1] = dark[1] + (mid[1] - dark[1]) * s;
      out[2] = dark[2] + (mid[2] - dark[2]) * s;
    } else {
      final s = min(1.0, (k - 0.6) / 0.4);
      out[0] = mid[0] + (lightC[0] - mid[0]) * s;
      out[1] = mid[1] + (lightC[1] - mid[1]) * s;
      out[2] = mid[2] + (lightC[2] - mid[2]) * s;
    }
  }

  // Planken einteilen
  final planks = <_Plank>[];
  var px0 = 0;
  while (px0 < W) {
    var w = (130 + rnd.nextDouble() * 100).round();
    if (W - (px0 + w) < 90) w = W - px0;
    planks.add(_Plank(
      px0,
      w,
      0.84 + rnd.nextDouble() * 0.32,
      0.014 + rnd.nextDouble() * 0.016,
      22 + rnd.nextDouble() * 38,
      rnd.nextDouble() * 100,
      4 + rnd.nextInt(5),
      rnd.nextDouble() < 0.7
          ? _Knot(
              0.25 + rnd.nextDouble() * 0.5,
              H * (0.25 + rnd.nextDouble() * 0.5),
              16 + rnd.nextDouble() * 22)
          : null,
    ));
    px0 += w;
  }

  final rgb = List<double>.filled(3, 0);
  for (final p in planks) {
    for (var x = p.x0; x < p.x0 + p.w; x++) {
      final u = (x - p.x0).toDouble();
      for (var y = 0; y < H; y++) {
        final yn = y / H * p.ny;
        final wob = fbm(u / 170 + p.phase, yn);
        var v = (u + p.warpAmp * wob) * p.freq + p.phase;
        var knotDark = 0.0;
        if (p.knot != null) {
          final dx = u - p.knot!.u * p.w;
          var dy = (y - p.knot!.y).abs();
          dy = min(dy, H - dy);            // Torus-Abstand → nahtlos
          final dist = sqrt(dx * dx + dy * dy * 0.35);
          v += 40 / (dist + 16);
          knotDark = max(0, 1 - dist / (p.knot!.r * 2)) * 0.55;
        }
        final t = v - v.floorToDouble();
        // asymmetrische Ringe: schmale dunkle Spätholz-Linie, breites Frühholz
        final band = t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82;
        // feine Faser + breite Längsstreifen
        final fine = (noise(u * 0.3, yn * 47) - 0.5) * 0.10;
        final streak = (noise(u * 0.08 + p.phase, yn * 2) - 0.5) * 0.18;
        var k = (0.24 + band * 0.70) * p.tone + fine + streak - knotDark;
        k = k.clamp(0.0, 1.0);
        colorAt(k, rgb);
        final o = (y * W + x) * 4;
        data[o]     = rgb[0].round();
        data[o + 1] = rgb[1].round();
        data[o + 2] = rgb[2].round();
        data[o + 3] = 255;
      }
    }
  }

  // Fugen mit Lichtkante: 2-Pixel-breite, fast schwarze rechte Kante
  // pro Planke, dazu ein dünner heller Streifen links.
  for (final p in planks) {
    for (var y = 0; y < H; y++) {
      // rechte Fuge (zwei Pixel)
      for (var dx = 0; dx < 2; dx++) {
        final x = p.x0 + p.w - 2 + dx;
        if (x < 0 || x >= W) continue;
        final o = (y * W + x) * 4;
        const a = 0.85;
        data[o]     = (data[o]     * (1 - a) + 4 * a).round();
        data[o + 1] = (data[o + 1] * (1 - a) + 2 * a).round();
        data[o + 2] = (data[o + 2] * (1 - a) + 1 * a).round();
      }
      // helle Lichtkante links
      final lo = (y * W + p.x0) * 4;
      const la = 0.06;
      data[lo]     = (data[lo]     * (1 - la) + 255 * la).round();
      data[lo + 1] = (data[lo + 1] * (1 - la) + 215 * la).round();
      data[lo + 2] = (data[lo + 2] * (1 - la) + 160 * la).round();
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      data, W, H, ui.PixelFormat.rgba8888, completer.complete);
  cachedWood = await completer.future;
  return cachedWood!;
}
