# Mensch ärgere Dich nicht – APK für Fire TV & Google TV

Dünner Android-WebView-Wrapper um das Web-Spiel aus dem Projekt-Root.
Aussehen und Spiellogik sind 1:1 das gleiche – zusätzlich ist die
komplette Steuerung per D-Pad nutzbar.

## Voraussetzungen

- **Android Studio** (empfohlen) – bringt JDK und Gradle automatisch mit.
- *Oder* JDK 17 + Gradle 8.5+ im PATH und das Android SDK über
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` erreichbar (SDK Platform 34, Build-Tools 34).

## Bauen

### Android Studio
1. „Open" → diesen `apk/`-Ordner wählen.
2. Beim ersten Öffnen synct Gradle automatisch. Falls noch keine
   Wrapper-Dateien existieren: `File → Sync Project with Gradle Files`.
3. „Run" oder Menü „Build → Build APK(s)".

### Kommandozeile

```bash
# Einmalig im apk-Ordner: Gradle-Wrapper anlegen (falls nicht vorhanden)
gradle wrapper --gradle-version 8.5

# Debug-APK bauen
./gradlew assembleDebug          # Linux/macOS
gradlew.bat assembleDebug        # Windows
```

Die fertige APK liegt anschließend unter
`apk/app/build/outputs/apk/debug/app-debug.apk`.

## Asset-Sync

`app/build.gradle` enthält den Task `syncWebAssets`, der vor jedem Build
`index.html`, `game.js`, `style.css`, `favicon.svg` und `lib/**` aus dem
**Projekt-Root** (eine Ebene oberhalb von `apk/`) in
`app/src/main/assets/` kopiert. Die Web-Dateien bleiben damit die Single
Source of Truth – Änderungen am Spiel wirken sich automatisch auf die
nächste APK aus. Das Verzeichnis `app/src/main/assets/` ist deshalb in
`.gitignore` aufgeführt.

Manuell ausführen lässt sich der Sync mit:

```bash
./gradlew syncWebAssets
```

## Installation auf Fire TV / Google TV (Sideload)

1. Auf dem TV-Gerät den Entwicklermodus aktivieren und **ADB-Debugging
   einschalten** (Einstellungen → Mein Fire TV → Entwickleroptionen bzw.
   Einstellungen → System → Info → 7× auf Android-TV-OS-Build tippen).
2. IP-Adresse des Geräts notieren.
3. Vom Entwicklungsrechner verbinden und installieren:

```bash
adb connect <TV-IP>:5555
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Das Spiel erscheint danach im **Apps**-Bereich des TV-Launchers (Leanback)
mit dem 320×180-Banner aus `res/drawable/banner.xml`.

## Steuerung mit der Fernbedienung

| Aktion | Taste |
|---|---|
| Fokus bewegen | D-Pad ◀ ▲ ▼ ▶ |
| Aktion (kurz) | OK / Enter / D-Pad Center |
| Farbpalette öffnen | OK lang (≥ 0,5 s) auf einem Pool |
| Würfeln | OK im Würfel-Modus |
| Zug ausführen | OK auf hervorgehobener Figur |
| Menü schließen / Zurück | Zurück-Taste |
| App verlassen | Zurück-Taste (wenn nichts mehr offen ist) |

Der Setup-Fokus springt räumlich: die vier Pools bilden ein Quadrat,
**Rechts** wechselt von den rechten Pools auf den Start-Button, **Oben**
führt von den oberen Pools (oder vom Start-Button) zum Hamburger-Menü
oben rechts. Die aktive Figur in der Spielphase wird zusätzlich zur
gelben Standard-Markierung hell umrandet.

## Architektur (Kurzfassung)

- `MainActivity` (Java, ca. 90 Zeilen) erzeugt einen Fullscreen-WebView,
  konfiguriert JavaScript / DOM Storage / Web Audio Autoplay und lädt
  `file:///android_asset/index.html`.
- Die **Zurück-Taste** wird zuerst per `evaluateJavascript` an die
  JS-Funktion `dpadBack()` (in `game.js`) durchgereicht – damit
  schließt sie zuerst Farbpalette/Menü und beendet erst danach die App.
- Das D-Pad wird vom WebView automatisch als
  `KeyboardEvent` mit `key="ArrowUp"` etc. an JavaScript geliefert; die
  Navigationslogik (Fokus-Modell, Long-Press-Timer) sitzt komplett in
  `game.js`. Es gibt **keinen** JavaScript-Bridge-Code in der App.
