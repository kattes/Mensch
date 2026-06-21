# Mensch ärgere Dich nicht – Flutter-Version (Fire TV & Google TV)

Eigenständige, native Android-App, parallel zur Web-Variante (`../index.html`)
und zum WebView-Wrapper (`../apk/`). Spielregeln und Visuals sind aus dem
JS-Original übernommen, aber alles ist nativ in Flutter implementiert:

- **Rendering**: Skia über Flutter-Canvas – kein WebView, kein Flackern.
- **Audio**: Eigene MethodChannel-Brücke zu Androids `SoundPool` (siehe
  `android/.../SoundChannel.kt`), kurze SFX werden einmalig in Dart als
  WAV-Bytes synthetisiert und in den Pool geladen → ~30 ms Latenz.
- **Steuerung**: D-Pad / Tastatur. Pfeile bewegen den Fokus, OK kurz =
  Spielertyp wechseln / würfeln / Zug, OK lang (≥ 500 ms) im Setup =
  Farbpalette öffnen, Zurück = Palette/Menü schließen.

## Bauen

Voraussetzungen: Flutter SDK ≥ 3.41, Android SDK Platform 34+ und ein
JDK 17. Der Build wurde mit Gradle 8.x und Flutter 3.41 verifiziert.

```bash
cd flutter
flutter pub get
flutter build apk --debug           # ./build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release         # signiert mit Debug-Key (genug für Sideload)
```

Hinweis: Die `--debug`-APK ist ~138 MB (Flutter-Engine inklusive, mehrere
ABIs). `--release` mit Code-Shrinking liegt typischerweise bei 25–40 MB
pro ABI; mit `--split-per-abi` werden separate, schlankere APKs erzeugt.

## Sideload auf Fire TV / Google TV

```bash
adb connect 192.168.1.76:5555         # Fire TV
adb connect 192.168.1.63:5555         # Xiaomi Google TV
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.kattes.mensch_flutter/.MainActivity
```

Auf dem Leanback-Launcher erscheint die App mit dem 320×180-Banner aus
`android/app/src/main/res/drawable/banner.xml` (übernommen aus `../apk/`).

## Projektstruktur

```
flutter/
├── lib/
│   ├── main.dart             # App-Entry, Theme, Fullscreen-Setup
│   ├── game.dart             # Spielzustand, Regeln (1:1 aus game.js)
│   ├── board.dart            # Geometrie, Farbpalette, Hilfsfunktionen
│   ├── board_painter.dart    # CustomPainter fürs Brett
│   ├── game_widget.dart      # Haupt-UI, D-Pad-Logik, Animationen
│   └── audio.dart            # SoundPool-Brücke + Dart-Synthese
└── android/app/src/main/
    ├── kotlin/.../MainActivity.kt    # FlutterActivity + Sound-Channel
    ├── kotlin/.../SoundChannel.kt    # SoundPool-Wrapper
    ├── res/drawable/banner.xml       # TV-Launcher-Banner
    ├── res/mipmap-anydpi-v26/
    │   └── ic_launcher.xml           # Adaptive Icon (rote Spielfigur)
    └── AndroidManifest.xml           # LEANBACK_LAUNCHER, isGame, landscape
```

## Was (noch) anders ist als die Web-Version

- **Würfel**: in Flutter zunächst 2D mit Augen-Pattern + kurzem
  Sequenz-Roll, kein 3D-Modell.
- **Holztisch**: schlichter Dunkelbraun-Hintergrund statt prozeduraler
  Maserung (kann später als ImageBitmap nachgereicht werden).
- **Sprachen**: aktuell nur Deutsch. Die TRANSLATIONS-Map aus game.js
  ließe sich 1:1 nach Dart portieren.
- **Partikel-Explosionen** beim Schlagen sind noch nicht umgesetzt.

Diese Punkte sind als Pflastersteine markiert; die Spielmechanik selbst
(40 Felder, 4 Pools, Schlagen, Strafregel, 3-Versuche-Regel, KI-Heuristik)
läuft komplett.
