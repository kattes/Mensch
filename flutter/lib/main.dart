import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_widget.dart';
import 'i18n.dart' as i18n;
import 'sound_lab.dart';
import 'wood.dart';

/// true zeigt statt des Spiels das Würfel-Sound-Hörlabor (Entwicklungs-Tool
/// zum Auswählen/Feinabstimmen des Würfelklangs, siehe sound_lab.dart).
const bool kSoundLab = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sprache aus den System-Locales bestimmen (Fallback Englisch).
  i18n.detectLocale(PlatformDispatcher.instance.locales);
  // Fullscreen ohne System-UI – passt für Fire TV / Google TV.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Querformat fest (TV ist immer landscape).
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Holztextur einmalig in BILDSCHIRMGRÖSSE erzeugen (physische Pixel) und
  // später 1:1 ohne Kachelung zeichnen → keine Tile-Naht / Wiederholung,
  // pixelscharf. Größe auf 2048 gedeckelt, damit die Erzeugung bezahlbar bleibt.
  final ps = PlatformDispatcher.instance.views.first.physicalSize;
  var pw = ps.width.round();
  var ph = ps.height.round();
  if (pw <= 0 || ph <= 0) {
    pw = 1920;
    ph = 1080;
  }
  await generateWoodTexture(
      width: pw.clamp(640, 2048), height: ph.clamp(360, 2048));
  runApp(const MenschApp());
}

class MenschApp extends StatelessWidget {
  const MenschApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isRtl = i18n.isRtl;
    return MaterialApp(
      title: i18n.t('title'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD62828),
          brightness: Brightness.dark,
          surface: const Color(0xFF3D2814),
        ),
        scaffoldBackgroundColor: const Color(0xFF3D2814),
      ),
      home: Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: kSoundLab ? const SoundLab() : const GameWidget(),
      ),
    );
  }
}
