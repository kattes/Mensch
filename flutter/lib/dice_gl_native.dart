import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'dice_canvas.dart';

/// Bindet den nativen OpenGL-ES-Würfel (Kotlin, `android/.../DiceGl.kt`) über
/// den MethodChannel `dice_gl` an und zeigt ihn als `Texture`. Der Würfel rollt
/// physikalisch über die ganze Würfelzone (Verhalten 1:1 aus game.js).
///
/// Auf Nicht-Android (Desktop-Entwicklung) gibt es das Plugin nicht → Fallback
/// auf den Skia-Canvas-Würfel [DiceCube].
class DiceGlNative extends StatefulWidget {
  final bool rolling;
  final double energy;

  /// Pixel pro Rasterzelle (cssU = boardSize/12) – bestimmt Würfelgröße und
  /// Physik-Skalierung wie in der Web-Version.
  final double unit;
  final ValueChanged<int>? onSettled;

  const DiceGlNative({
    super.key,
    required this.rolling,
    this.unit = 40,
    this.energy = 0.5,
    this.onSettled,
  });

  @override
  State<DiceGlNative> createState() => _DiceGlNativeState();
}

class _DiceGlNativeState extends State<DiceGlNative> {
  static const _channel = MethodChannel('dice_gl');
  int? _textureId;
  bool _useNative = false;
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    _useNative = defaultTargetPlatform == TargetPlatform.android;
    if (_useNative) _channel.setMethodCallHandler(_onCall);
  }

  Future<void> _initNative(double w, double h, double dpr) async {
    try {
      final id = await _channel.invokeMethod<int>('init', {
        'texW': (w * dpr).round(),
        'texH': (h * dpr).round(),
        'unit': widget.unit * dpr,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
    } catch (_) {
      if (mounted) setState(() => _useNative = false);
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'settled':
        widget.onSettled?.call(call.arguments as int);
        break;
      case 'bounce': // Banden-/Tischaufprall des rollenden Würfels
        GameAudio.instance.impact((call.arguments as num).toDouble());
        break;
      case 'edge': // Kantenwechsel beim Abrollen
        GameAudio.instance.klack((call.arguments as num).toDouble());
        break;
    }
    return null;
  }

  @override
  void didUpdateWidget(DiceGlNative old) {
    super.didUpdateWidget(old);
    if (_useNative && widget.rolling && !old.rolling) {
      _channel.invokeMethod('roll', {'energy': widget.energy});
    }
  }

  @override
  void dispose() {
    if (_useNative) {
      _channel.setMethodCallHandler(null);
      _channel.invokeMethod('dispose');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNative) {
      return DiceCube(
        rolling: widget.rolling,
        energy: widget.energy,
        onSettled: widget.onSettled,
      );
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(builder: (ctx, c) {
      if (!_initStarted && c.maxWidth.isFinite && c.maxWidth > 0 &&
          c.maxHeight.isFinite && c.maxHeight > 0) {
        _initStarted = true;
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _initNative(c.maxWidth, c.maxHeight, dpr));
      }
      if (_textureId == null) return const SizedBox.expand();
      // Textur hat exakt das Seitenverhältnis der Zone → füllt sie verzerrungsfrei.
      return SizedBox.expand(child: Texture(textureId: _textureId!));
    });
  }
}
