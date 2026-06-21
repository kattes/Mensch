package com.kattes.mensch_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Audio läuft über die SoLoud-Engine (flutter_soloud) in Dart.
// Der 3D-Würfel rendert über ein eigenes natives GLES-2-Plugin (DiceGl), das
// direkt in eine Flutter-SurfaceTexture zeichnet – nötig, weil flame_3d/Impeller
// auf dem Fire TV (Vulkan 1.0) und flutter_angle auf 32-bit-TVs nicht laufen.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "dice_gl"
        )
        val dice = DiceGl(flutterEngine.renderer, channel)
        channel.setMethodCallHandler(dice)
    }
}
