import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// 3D-Würfel komplett über **Skia/Canvas** (CustomPainter), ohne GPU-Plugin.
///
/// Hintergrund: flame_3d (Flutter GPU/Impeller) läuft nicht auf dem Fire TV
/// Stick (Vulkan 1.0, kein Impeller), und flutter_angle ist auf den 32-bit-TVs
/// kaputt (ANGLE-Libs fehlen / glBufferData scheitert). Skia dagegen rendert
/// auf beiden Geräten einwandfrei (das ganze Brett läuft darüber).
///
/// Der Würfel wird als echter 3D-Körper geführt: 6 Flächen mit Mittelpunkt +
/// Kantenvektoren, per Quaternion gedreht, auf 2D projiziert; sichtbare
/// (vorderseitige) Flächen werden schattiert gefüllt und die Augen perspektivisch
/// daraufgesetzt. Die Physik (Taumeln + Einschwingen auf den gewürfelten Wert)
/// ist aus dem früheren GL-Würfel übernommen.
///
/// Schnittstelle identisch zu Dice3D/DiceGl.
class DiceCube extends StatefulWidget {
  final bool rolling;
  final double energy;
  final ValueChanged<int>? onSettled;

  const DiceCube({
    super.key,
    required this.rolling,
    this.energy = 0.5,
    this.onSettled,
  });

  @override
  State<DiceCube> createState() => _DiceCubeState();
}

class _DiceCubeState extends State<DiceCube>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  vm.Quaternion _q = vm.Quaternion.identity();
  vm.Vector3 _omega = vm.Vector3.zero();
  bool _tumbling = false;
  bool _settling = false;
  double _settleT = 0;
  double _tumbleLeft = 0;
  vm.Quaternion _settleFrom = vm.Quaternion.identity();
  vm.Quaternion _settleTo = vm.Quaternion.identity();
  int _settledValue = 1;

  // Konstante Kippung, damit man neben der Wertfläche zwei Nachbarflächen sieht.
  static final vm.Quaternion _tilt =
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.42) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -0.5);

  @override
  void initState() {
    super.initState();
    _q = _targetFor(_settledValue);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(DiceCube old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !old.rolling) _startRoll();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _startRoll() {
    final e = widget.energy.clamp(0.0, 1.0);
    final rnd = math.Random();
    final axis = vm.Vector3(
      rnd.nextDouble() * 2 - 1,
      rnd.nextDouble() * 2 - 1,
      rnd.nextDouble() * 2 - 1,
    );
    if (axis.length < 0.01) axis.setValues(1, 1, 0);
    axis.normalize();
    final speed = 12.0 + 22.0 * e;
    _omega = axis * speed;
    _tumbling = true;
    _settling = false;
    _tumbleLeft = 0.6 + 0.9 * e;
    _settledValue = 1 + rnd.nextInt(6);
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;

    if (_tumbling) {
      _integrate(dt);
      _tumbleLeft -= dt;
      _omega.scale(math.pow(0.35, dt).toDouble());
      if (_tumbleLeft <= 0) {
        _tumbling = false;
        _settling = true;
        _settleT = 0;
        _settleFrom = _q.clone()..normalize();
        _settleTo = _targetFor(_settledValue);
      }
    } else if (_settling) {
      _settleT += dt / 0.45;
      if (_settleT >= 1) {
        _settleT = 1;
        _settling = false;
        _q = _settleTo.clone();
        widget.onSettled?.call(_settledValue);
      } else {
        _q = _nlerp(_settleFrom, _settleTo, _easeOut(_settleT));
      }
    }

    setState(() {}); // Würfel jeden Frame neu zeichnen
  }

  void _integrate(double dt) {
    final len = _omega.length;
    if (len > 1e-5) {
      final dq = vm.Quaternion.axisAngle(_omega / len, len * dt);
      _q = dq * _q;
      _q.normalize();
    }
  }

  double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

  vm.Quaternion _nlerp(vm.Quaternion a, vm.Quaternion b, double t) {
    final dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    final bb = dot < 0
        ? vm.Quaternion(-b.x, -b.y, -b.z, -b.w)
        : vm.Quaternion(b.x, b.y, b.z, b.w);
    final q = vm.Quaternion(
      a.x + (bb.x - a.x) * t,
      a.y + (bb.y - a.y) * t,
      a.z + (bb.z - a.z) * t,
      a.w + (bb.w - a.w) * t,
    );
    q.normalize();
    return q;
  }

  /// Orientierung, die die Fläche mit [value] zur Kamera (+Z) dreht.
  vm.Quaternion _targetFor(int value) {
    switch (value) {
      case 3:
        return vm.Quaternion.identity();
      case 4:
        return vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi);
      case 2:
        return vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -math.pi / 2);
      case 5:
        return vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi / 2);
      case 1:
        return vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2);
      case 6:
        return vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2);
      default:
        return vm.Quaternion.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _CubePainter(_tilt * _q),
    );
  }
}

/// Eine Würfelfläche: Wert + Mittelpunkt + Kantenvektoren (je halbe Kante).
/// normal = right × up zeigt nach außen.
class _Face {
  final int value;
  final vm.Vector3 center;
  final vm.Vector3 right;
  final vm.Vector3 up;
  const _Face(this.value, this.center, this.right, this.up);
}

class _CubePainter extends CustomPainter {
  final vm.Quaternion rot;
  _CubePainter(this.rot);

  // Flächen so definiert, dass _targetFor(value) den jeweiligen Wert zur
  // Kamera (+Z) dreht. Gegenüberliegende Flächen summieren zu 7.
  static final List<_Face> _faces = [
    _Face(3, vm.Vector3(0, 0, 1), vm.Vector3(1, 0, 0), vm.Vector3(0, 1, 0)),
    _Face(4, vm.Vector3(0, 0, -1), vm.Vector3(-1, 0, 0), vm.Vector3(0, 1, 0)),
    _Face(2, vm.Vector3(1, 0, 0), vm.Vector3(0, 0, -1), vm.Vector3(0, 1, 0)),
    _Face(5, vm.Vector3(-1, 0, 0), vm.Vector3(0, 0, 1), vm.Vector3(0, 1, 0)),
    _Face(1, vm.Vector3(0, 1, 0), vm.Vector3(1, 0, 0), vm.Vector3(0, 0, -1)),
    _Face(6, vm.Vector3(0, -1, 0), vm.Vector3(1, 0, 0), vm.Vector3(0, 0, 1)),
  ];

  // Augenpositionen je Wert im Flächenraster (gx=rechts, gy=hoch, je -1..1).
  static const Map<int, List<List<double>>> _pips = {
    1: [[0, 0]],
    2: [[-1, 1], [1, -1]],
    3: [[-1, 1], [0, 0], [1, -1]],
    4: [[-1, 1], [1, 1], [-1, -1], [1, -1]],
    5: [[-1, 1], [1, 1], [0, 0], [-1, -1], [1, -1]],
    6: [[-1, 1], [1, 1], [-1, 0], [1, 0], [-1, -1], [1, -1]],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = math.min(size.width, size.height) * 0.30;
    const d = 5.0; // Kameradistanz für milde Perspektive

    final m = rot.asRotationMatrix();
    final light = vm.Vector3(0.32, 0.55, 0.78)..normalize();

    double depthFactor(vm.Vector3 p) => d / (d - p.z);
    Offset project(vm.Vector3 p) {
      final f = depthFactor(p);
      return Offset(cx + p.x * s * f, cy - p.y * s * f);
    }

    const faceBase = Color(0xFFF4F1EA);
    const pipColor = Color(0xFF18140F);

    for (final face in _faces) {
      final cen = m.transformed(face.center);
      final r = m.transformed(face.right);
      final u = m.transformed(face.up);
      final n = r.cross(u)..normalize();
      if (n.z <= 0.0) continue; // Rückseite – nicht zeichnen

      // Flächen-Viereck (CCW).
      final c0 = cen - r - u;
      final c1 = cen + r - u;
      final c2 = cen + r + u;
      final c3 = cen - r + u;
      final path = Path()
        ..moveTo(project(c0).dx, project(c0).dy)
        ..lineTo(project(c1).dx, project(c1).dy)
        ..lineTo(project(c2).dx, project(c2).dy)
        ..lineTo(project(c3).dx, project(c3).dy)
        ..close();

      final lambert = math.max(n.dot(light), 0.0);
      final bright = 0.62 + 0.38 * lambert;
      final faceColor = Color.fromARGB(
        255,
        (faceBase.red * bright).round().clamp(0, 255),
        (faceBase.green * bright).round().clamp(0, 255),
        (faceBase.blue * bright).round().clamp(0, 255),
      );

      canvas.drawPath(path, Paint()..color = faceColor);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x33000000),
      );

      // Augen perspektivisch auf die Fläche setzen.
      final pips = _pips[face.value]!;
      for (final p in pips) {
        final pt3 = cen + r * (p[0] * 0.6) + u * (p[1] * 0.6);
        final c = project(pt3);
        final pr = s * depthFactor(pt3) * 0.12;
        canvas.drawCircle(c, pr, Paint()..color = pipColor);
      }
    }
  }

  @override
  bool shouldRepaint(_CubePainter old) => true;
}
