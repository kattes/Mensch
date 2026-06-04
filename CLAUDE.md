# Mensch ärgere Dich nicht

Browserbasierte Umsetzung des klassischen Brettspiels „Mensch ärgere Dich nicht" für 2–4 Spieler.
Jede Farbe kann als **Mensch**, **Computer** oder **Nicht dabei** konfiguriert werden — es können
also auch zwei Menschen ohne Computerbeteiligung gegeneinander spielen.

## Starten

Kein Build, kein Server, keine Abhängigkeiten — einfach `index.html` im Browser öffnen.

## Projektstruktur

| Datei / Ordner | Inhalt |
|---|---|
| `index.html` | Seitengerüst: Holztisch (Body), Canvas-Spielbrett, 3D-Würfel, Hamburger-Menü, Overlays für Spielerauswahl und Spielende |
| `style.css`  | Layout (Flexbox, responsive), Würfel-Optik mit CSS-Grid-Augen, Overlay-Dialoge |
| `game.js`    | Gesamte Spiellogik, Rendering und KI (Vanilla JS, keine Frameworks) |
| `Delphi/`    | Ursprüngliches, unvollendetes Delphi-Projekt (VCL). Diente als Vorlage für die Brettgeometrie. Wird nicht weiterentwickelt. |

## Architektur (`game.js`)

- **Brettgeometrie**: 12×12-Raster, übernommen aus dem Delphi-Original (`Main.pas`).
  `FIELD_POS` (40 Laufwegfelder), `GOAL_POS` (Zielfelder je Farbe), `HOME_POS` (Homebases in den Ecken).
- **Positionscodierung einer Figur**: `-1` = Homebase, `0–39` = Spielfeld (absolut), `40–43` = Zielfeld 0–3.
- **Spielerindex = Ecke**: 0 = oben links, 1 = oben rechts, 2 = unten rechts, 3 = unten links.
  Startfelder: `START = [0, 10, 20, 30]`. Die Farbe je Ecke ist im Setup frei aus `PALETTE`
  wählbar (8 Farben, u. a. Schwarz statt Rot bei Rot/Grün-Schwäche); `NAMES`/`HEX`/`HEX_DARK`/
  `HEX_LIGHT` werden in `applyColors()` daraus abgeleitet, Duplikate werden durch Farbtausch
  zwischen den Plätzen verhindert (`pickColor()`).
- **Zustand**: zentrales `game`-Objekt mit Phasenautomat
  `setup → roll → move → anim → (roll | nächster Spieler) → … → over`.
- **Rendering**: Canvas, dauerhafte `requestAnimationFrame`-Schleife; `draw(t)` zeichnet den
  kompletten Zustand jedes Frame (Highlight-Pulsieren über Zeitparameter `t`); `frame(t)`
  liefert zusätzlich `dt` für Partikel- und Würfelphysik.
- **Tisch-Layout**: Der Body ist ein Holztisch (CSS-Gradients). `layoutTable()` legt das
  Brett mit 20 px Einzug links (Querformat) bzw. oben (Hochformat); die restliche
  Holzfläche ist die Würfelzone (`diceZone`, Tisch-Pixel). Keine Statustexte — wer dran
  ist, zeigen das pulsierende Homebase-Feld und der Würfel-Glow in Spielerfarbe
  (`updateDiceCue()`). Hamburger-Menü (`#menuBtn`/`#menu`) für Neues Spiel, Protokoll
  (default eingeklappt) und später Sound.
- **3D-Würfel**: CSS-3D-Cube (`#dice3d`/`.cube` mit 6 Faces), bewegt sich nur in der
  `diceZone`, nie über dem Brett. Physik in `updateDice()`: Quaternion-Orientierung
  (`dice.q`), Drehachse beim Rollen senkrecht zur Bewegungsrichtung (natürliches
  Abrollen), lineare Gleitreibung, Hüpfen (`dice.z`/`vz`) bei Kick und Bandenkontakt.
  Anstupsen (Tap) oder Schleudern (Drag-Flick) startet den Wurf. **Der Wurfwert wird aus
  der tatsächlichen Endlage abgelesen** (`topFace()` = oben liegende Seite), dann dreht
  `settleDice()` per Slerp sanft in die plane Lage (< 45°, kein Sprung) und ruft
  `resolveRoll()` — Anzeige und Spielwert können daher nie voneinander abweichen.
- **Explosionen**: Partikelsystem (`particles`, `spawnExplosion()`) für geschlagene und
  bestrafte Figuren, gezeichnet in `drawParticles()`.
- **Timer-Sicherheit**: `game.seq` wird bei „Neues Spiel" erhöht; `schedule()` entwertet damit
  alte KI-/Animations-Timer. Neue verzögerte Aktionen immer über `schedule()` laufen lassen.
- **KI**: Heuristik in `aiPickMove()` — Schlagen > Ziel erreichen > Rauskommen > Flucht aus
  Gefahr; bedrohte Felder (`isDangerous()`) werden gemieden.

## Implementierte Regeln

- 6 nötig zum Rauskommen, danach erneut würfeln; nach jeder 6 ein weiterer Wurf
- 3 Würfelversuche, wenn keine Figur beweglich ist (alles in Homebase / Ziel blockiert)
- Pflicht: mit einer 6 rauskommen, wenn möglich; eigenes Startfeld räumen, solange Figuren in der Homebase warten
- Schlagen beim Landen auf gegnerischer Figur
- **Strafregel**: Wer schlagen könnte, es aber nicht tut, verliert die säumige Figur
  (sie wird in die Homebase zurückgeworfen; `game.captureList` in `resolveRoll()`,
  Vollzug in `finalizeMove()`). Mögliche Schlagfelder pulsieren rot als Warnung;
  die KI schlägt deshalb immer, wenn sie kann.
- Im Zielfeld darf nicht übersprungen werden
- Gewonnen hat, wer alle 4 Figuren im Ziel hat; das Spiel läuft bis zur vollständigen Rangliste

## Konventionen

- Sprache im Code, in Kommentaren und in der UI: **Deutsch**
- Vanilla JS/CSS/HTML, keine Frameworks oder Build-Tools einführen
- Regeländerungen (z. B. Schlagzwang als Option) gehören in `computeMoves()`
