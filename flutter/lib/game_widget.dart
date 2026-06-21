import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'audio.dart';
import 'board.dart';
import 'board_painter.dart';
import 'dice_gl_native.dart';
import 'game.dart';
import 'i18n.dart';
import 'wood.dart';

/// Räumlicher Nachbar-Graph für die Setup-Phase (siehe game.js).
/// 0=P0(o.l.) 1=P1(o.r.) 2=P2(u.r.) 3=P3(u.l.) 4=Start 5=Menü
/// (kein `const`, weil LogicalKeyboardKey '==' überschreibt.)
class GameWidget extends StatefulWidget {
  const GameWidget({super.key});
  @override
  State<GameWidget> createState() => _GameWidgetState();
}

class _GameWidgetState extends State<GameWidget>
    with TickerProviderStateMixin {
  final GameState state = GameState();
  final FocusNode focusNode = FocusNode();
  late final Ticker _ticker;

  // Pulsanimation 0..1 (Sinus für Highlights)
  double pulseT = 0;

  // Zuletzt berechnete Brettkantenlänge (für die Würfel-Einheit cssU=boardSize/12).
  double _boardSize = 0;

  // D-Pad-Zustand
  int dpadSetupIdx = 0;
  int dpadPaletteIdx = 0;
  int dpadMoveIdx = 0;
  bool dpadActive = false;
  bool paletteOpen = false;

  // Ein laufendes Spiel wurde per Zurück-Taste pausiert und liegt eingefroren
  // im Hintergrund – auf der Startseite erscheint dann „Weiterspielen".
  bool _paused = false;

  // Seiten-Buttons der Startseite (D-Pad-Fokusindizes 4..6):
  static const int _btnStart = 4;   // Spiel starten
  static const int _btnSound = 5;   // Sound an/aus
  static const int _btnResume = 6;  // Weiterspielen (nur wenn pausiert)

  // Enter-Eingabe: misst Press-Down/Up-Zeitpunkte für zwei Gesten:
  //   * Kurz <500 ms → _enterShort (Aktion in der jeweiligen Phase)
  //   * Lang ≥500 ms → _enterLong (Palette im Setup)
  // In der Roll-Phase ist die Press-Dauer zusätzlich die Würfel-Energie.
  DateTime? enterDownAt;
  Timer? enterTimer;
  bool _longPressFired = false;
  bool _charging = false;
  double _chargeFraction = 0;
  static const _maxChargeMs = 800; // länger drücken bringt nichts mehr

  // Würfel-Zustand
  int diceValue = 1;
  bool diceRolling = false;
  double diceEnergy = 0.5; // 0..1, Anteil der Maximalkraft
  Timer? diceTimer;

  // Toast „X ist am Zug" – wird beim Spielerwechsel kurz eingeblendet,
  // statt eines 3D-Glow um den Würfel (dessen Position aus dem 3D-Mesh
  // schwer pixelgenau auf 2D zu projizieren war).
  String? _toastMessage;
  Timer? _toastTimer;
  int _lastToastPlayer = -1;

  // Partikel-System (Funken + Druckwelle bei Schlag / Strafe)
  final List<Particle> particles = [];
  Duration _lastTick = Duration.zero;

  // Laufende Figur-Bewegung – an den Vsync-Ticker gekoppelt (_onTick zieht die
  // Schritte nach), damit Modell-Update, Repaint und Tick-Sound im SELBEN Frame
  // entstehen. So ist der Bild/Ton-Versatz konstant (eine Audiopuffer-Länge)
  // statt frameweise zu schwanken wie bei einem freilaufenden Timer.
  static const int _stepMs = 140;
  Move? _animMove;
  int _animPlayer = 0;
  List<int> _animPath = const [];
  int _animSeq = 0;
  Duration _animStart = Duration.zero;
  bool _animStarted = false;
  int _animShown = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    focusNode.requestFocus();
    GameAudio.instance.init();
  }

  @override
  void dispose() {
    _ticker.dispose();
    focusNode.dispose();
    enterTimer?.cancel();
    diceTimer?.cancel();
    _toastTimer?.cancel();
    _aiChargeTimer?.cancel();
    GameAudio.instance.dispose();
    super.dispose();
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
  }

  /// Vergleicht den aktuellen Spieler mit dem zuletzt durch einen Toast
  /// angekündigten – fällt eine Veränderung auf, blenden wir den neuen
  /// Spielernamen kurz ein. Wird in [build] aufgerufen, damit jeder
  /// Spielerwechsel verlässlich erkannt wird.
  void _maybeShowTurnToast() {
    if (state.phase == GamePhase.setup || state.phase == GamePhase.over) {
      _lastToastPlayer = -1;
      return;
    }
    if (state.players.isEmpty) return;
    final cur = state.current;
    if (cur != _lastToastPlayer) {
      _lastToastPlayer = cur;
      // Erst nach dem aktuellen Frame zeigen, sonst gibt's setState-im-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showToast(t('turnToast', {'a': _name(cur)}));
      });
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0, 0.05);
    _lastTick = elapsed;
    _advanceMove(elapsed); // fällige Figur-Schritte + Ticks für diesen Frame
    _updateParticles(dt.toDouble());
    setState(() {
      pulseT = 0.5 + 0.5 * sin(t * 2.6);
      // Mensch-Charge updaten – falls die KI-Animation aktiv ist, fasst
      // der Ticker `_chargeFraction` NICHT an (das macht der KI-Timer selbst).
      if (_charging && enterDownAt != null) {
        _chargeFraction =
            (DateTime.now().difference(enterDownAt!).inMilliseconds /
                    _maxChargeMs)
                .clamp(0.0, 1.0)
                .toDouble();
      } else if (_aiChargeTimer == null) {
        _chargeFraction = 0;
      }
    });
  }

  void _updateParticles(double dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.age += dt;
      if (p.age >= p.life) {
        particles.removeAt(i);
        continue;
      }
      if (!p.ring) {
        p.vy += 2.6 * dt;        // Schwerkraft
        p.x  += p.vx * dt;
        p.y  += p.vy * dt;
      }
    }
  }

  /// Explosion auf Brett-Koordinaten (xu, yu) mit Spielerfarbe [hex].
  void _spawnExplosion(double xu, double yu, Color hex) {
    final rnd = Random();
    for (var i = 0; i < 26; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final sp = 1.2 + rnd.nextDouble() * 3.2;
      particles.add(Particle(
        x: xu, y: yu,
        vx: cos(a) * sp,
        vy: sin(a) * sp - 0.6,
        life: 0.5 + rnd.nextDouble() * 0.4,
        r: 0.04 + rnd.nextDouble() * 0.08,
        color: i % 3 == 0 ? const Color(0xFFFFB300) : hex,
      ));
    }
    // Druckwelle als Ring
    particles.add(Particle(
      x: xu, y: yu, vx: 0, vy: 0,
      life: 0.45, r: 0,
      color: const Color(0xFFFFAA00),
      ring: true,
    ));
  }

  // ------ Tastatur / D-Pad ------
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final k = event.logicalKey;
      // Android-Zurück (goBack) läuft AUSSCHLIESSLICH über PopScope (siehe
      // build) – hier nur Tastatur-Esc für die Desktop-Entwicklung. Würde
      // goBack auch hier behandelt, gäbe es ein Doppel-Handling (kurz Pause,
      // dann beendet PopScope die App).
      if (k == LogicalKeyboardKey.escape) {
        if (_handleBack()) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      }
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.space) {
        _enterDown();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        setState(() => dpadActive = true);
        _arrow(k);
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.space) {
        _enterUp();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _arrow(LogicalKeyboardKey key) {
    if (paletteOpen) {
      _paletteArrow(key);
      return;
    }
    if (state.phase == GamePhase.setup) {
      _setupArrow(key);
    } else if (state.phase == GamePhase.move &&
        state.isHuman(state.current)) {
      _moveArrow(key);
    }
  }

  // D-Pad-Navigation auf der Startseite: Pools 0-3 (oben l/r, unten r/l) plus
  // die Seiten-Buttons (_sideButtons) als vertikale Liste rechts daneben.
  void _setupArrow(LogicalKeyboardKey key) {
    final sb = _sideButtons;
    final sidePos = sb.indexOf(dpadSetupIdx);
    if (sidePos >= 0) {
      // Auf einem Seiten-Button
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => dpadSetupIdx = sb[(sidePos + 1) % sb.length]);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => dpadSetupIdx = sb[(sidePos - 1 + sb.length) % sb.length]);
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() => dpadSetupIdx = 1); // zurück zu den Pools (oben rechts)
      }
      return;
    }
    // Auf einem Pool (0-3)
    int? next;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (dpadSetupIdx == 0) next = 1;
      else if (dpadSetupIdx == 3) next = 2;
      else next = sb.first; // von 1/2 (rechte Spalte) in die Seitenleiste
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (dpadSetupIdx == 1) next = 0;
      else if (dpadSetupIdx == 2) next = 3;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (dpadSetupIdx == 0) next = 3;
      else if (dpadSetupIdx == 1) next = 2;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (dpadSetupIdx == 3) next = 0;
      else if (dpadSetupIdx == 2) next = 1;
    }
    if (next != null) setState(() => dpadSetupIdx = next!);
  }

  void _moveArrow(LogicalKeyboardKey key) {
    if (state.movable.isEmpty) return;
    final n = state.movable.length;
    setState(() {
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        dpadMoveIdx = (dpadMoveIdx + 1) % n;
      } else {
        dpadMoveIdx = (dpadMoveIdx - 1 + n) % n;
      }
    });
  }

  void _paletteArrow(LogicalKeyboardKey key) {
    var n = dpadPaletteIdx;
    if (key == LogicalKeyboardKey.arrowLeft && n % 4 > 0) n--;
    else if (key == LogicalKeyboardKey.arrowRight && n % 4 < 3) n++;
    else if (key == LogicalKeyboardKey.arrowUp && n >= 4) n -= 4;
    else if (key == LogicalKeyboardKey.arrowDown && n < 4) n += 4;
    if (n != dpadPaletteIdx && n >= 0 && n < palette.length) {
      setState(() => dpadPaletteIdx = n);
    }
  }

  bool get _isRollContext =>
      state.phase == GamePhase.roll &&
      !diceRolling &&
      state.players.isNotEmpty &&
      state.isHuman(state.current);

  void _enterDown() {
    final now = DateTime.now();
    enterDownAt = now;
    _longPressFired = false;
    if (_isRollContext) {
      setState(() {
        _charging = true;
        _chargeFraction = 0;
      });
    } else if (state.phase == GamePhase.setup && !paletteOpen) {
      enterTimer?.cancel();
      enterTimer = Timer(const Duration(milliseconds: 500), () {
        enterTimer = null;
        _longPressFired = true;
        _enterLong();
      });
    }
  }

  void _enterUp() {
    if (enterDownAt == null) return;
    final downAt = enterDownAt!;
    final dur = DateTime.now().difference(downAt).inMilliseconds;
    enterDownAt = null;
    enterTimer?.cancel();
    enterTimer = null;

    // Ladevorgang abgeschlossen → Würfel mit Energie werfen
    if (_charging) {
      setState(() {
        _charging = false;
        _chargeFraction = 0;
      });
      _rollDiceWithCharge(dur);
      return;
    }

    // Lang-Druck-Aktion ist schon im Timer-Callback gefeuert, kein Short.
    if (_longPressFired) {
      _longPressFired = false;
      return;
    }
    _enterShort();
  }

  // Reihenfolge der Seiten-Buttons (oben→unten): Weiterspielen (nur pausiert),
  // Spiel starten, Sound. Bestimmt zugleich die D-Pad-Navigation.
  List<int> get _sideButtons =>
      [if (_paused) _btnResume, _btnStart, _btnSound];

  void _toggleSound() {
    GameAudio.instance.toggle();
    setState(() {});
  }

  /// Laufendes Spiel einfrieren und zur Startseite zurückkehren. Der
  /// Spielzustand (Figuren, aktueller Spieler) bleibt für „Weiterspielen"
  /// erhalten; laufende KI-/Animationstimer werden über seq entwertet.
  void _pauseGame() {
    state.pauseToSetup();
    setState(() {
      _paused = true;
      diceRolling = false;
      dpadActive = true;
      dpadSetupIdx = _btnResume; // Fokus direkt auf „Weiterspielen"
    });
  }

  void _resumeGame() {
    if (!_paused) return;
    setState(() => _paused = false);
    _nextTurnSetup(); // Runde des aktuellen Spielers neu starten
  }

  /// Aktion eines Seiten-Buttons (per OK oder Touch).
  void _activateSideButton(int idx) {
    if (idx == _btnStart) {
      _startGame();
    } else if (idx == _btnSound) {
      _toggleSound();
    } else if (idx == _btnResume) {
      _resumeGame();
    }
  }

  void _enterShort() {
    if (paletteOpen) {
      state.setColor(dpadSetupIdx, dpadPaletteIdx);
      setState(() => paletteOpen = false);
      return;
    }
    if (state.phase == GamePhase.setup) {
      if (dpadSetupIdx >= 0 && dpadSetupIdx <= 3) {
        state.cycleType(dpadSetupIdx);
      } else {
        _activateSideButton(dpadSetupIdx);
      }
      setState(() {});
      return;
    }
    // Roll-Phase wird über Hold-to-charge gehandhabt (Press-Down lädt,
    // Release wirft). Hier kein zusätzlicher Short-Press-Trigger.
    if (state.phase == GamePhase.move &&
        state.isHuman(state.current) &&
        state.movable.isNotEmpty) {
      final m = state.movable[
          dpadMoveIdx.clamp(0, state.movable.length - 1)];
      _executeMove(m);
      return;
    }
    if (state.phase == GamePhase.over) {
      setState(() {
        _paused = false;
        dpadSetupIdx = 0; // Fokus zurück auf die Pools
      });
      state.showSetup();
      setState(() {});
    }
  }

  void _enterLong() {
    if (state.phase == GamePhase.setup &&
        dpadSetupIdx >= 0 &&
        dpadSetupIdx <= 3 &&
        state.setupTypes[dpadSetupIdx] != PlayerType.off) {
      setState(() {
        dpadPaletteIdx = state.colors[dpadSetupIdx];
        paletteOpen = true;
      });
    }
  }

  bool _handleBack() {
    if (paletteOpen) {
      setState(() => paletteOpen = false);
      return true;
    }
    // Im laufenden Spiel → pausieren und zur Startseite (mit „Weiterspielen").
    if (state.phase == GamePhase.roll ||
        state.phase == GamePhase.move ||
        state.phase == GamePhase.anim) {
      _pauseGame();
      return true;
    }
    // Nach Spielende → zurück zur Startseite (frisch, nichts fortzusetzen).
    if (state.phase == GamePhase.over) {
      setState(() {
        _paused = false;
        dpadSetupIdx = 0; // Fokus zurück auf die Pools
      });
      state.showSetup();
      setState(() {});
      return true;
    }
    return false;
  }

  // ------ Spielablauf ------
  void _startGame() {
    if (state.setupValid() != null) return;
    state.startGame();
    state.addLog(t('newGame'));
    setState(() {
      dpadMoveIdx = 0;
      _paused = false; // ein evtl. pausiertes Spiel wird verworfen
    });
    _nextTurnSetup();
  }

  void _nextTurnSetup() {
    state.startTurn();
    setState(() {});
    if (state.isKi(state.current)) {
      Future.delayed(const Duration(milliseconds: 400), _aiRollDice);
    }
  }

  /// Würfeln mit gemessener Press-Dauer: Energie 0.2..1.0 entscheidet
  /// über Tumble-Dauer (Mindestwurf bleibt sichtbar) und über die Drehzahl
  /// des 3D-Würfels (siehe Dice3D.energy).
  void _rollDiceWithCharge(int holdMs) {
    final energy = (holdMs / _maxChargeMs).clamp(0.2, 1.0).toDouble();
    diceEnergy = energy;
    _rollDice();
  }

  void _rollDice() {
    if (diceRolling) return;
    // Anschubs-Sound; die Augenzahl bestimmt der Würfel selbst aus
    // seiner Endlage (siehe Dice3D.onSettled).
    GameAudio.instance.knock(0.2 + diceEnergy * 0.6);
    setState(() {
      diceRolling = true;
    });
  }

  Timer? _aiChargeTimer;

  /// KI-Wurf mit gefakter Lade-Animation der Powerbar, damit der Spieler
  /// optisches Feedback bekommt, dass der Computer gerade auflädt. Lädt
  /// in ~600 ms auf eine zufällige Energie 0.4..1.0 und ruft dann den
  /// regulären [_rollDice] auf.
  void _aiRollDice() {
    if (diceRolling) return;
    _aiChargeTimer?.cancel();
    final s = state.seq;
    final energy = 0.4 + Random().nextDouble() * 0.6;
    const totalMs = 600;
    final start = DateTime.now();
    _aiChargeTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (s != state.seq || !mounted) { t.cancel(); return; }
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final p = (elapsed / totalMs).clamp(0.0, 1.0);
      setState(() => _chargeFraction = p * energy);
      if (p >= 1.0) {
        t.cancel();
        _aiChargeTimer = null;
        setState(() => _chargeFraction = 0);
        diceEnergy = energy;
        _rollDice();
      }
    });
  }

  /// Wird vom Dice3D-Widget aufgerufen, sobald die Physik den Würfel
  /// liegen hat lassen. [value] ist die tatsächlich abgelesene
  /// Augenzahl – Anzeige und Spielwert können dadurch nie auseinanderlaufen.
  void _onDiceSettled(int value) {
    if (!diceRolling) return;
    setState(() {
      diceValue = value;
      diceRolling = false;
    });
    GameAudio.instance.thud();
    if (value == 6) GameAudio.instance.six();
    _onRollResolved(value);
  }

  void _onRollResolved(int w) {
    final outcome = state.resolveRoll(w);
    switch (outcome) {
      case RollOutcome.canMove:
        setState(() {
          dpadMoveIdx = 0;
        });
        if (state.isKi(state.current)) {
          Future.delayed(const Duration(milliseconds: 700), () {
            final m = state.aiPickMove(state.movable, state.current);
            if (m != null) _executeMove(m);
          });
        }
        break;
      case RollOutcome.sixNoMove:
        state.addLog(t('sixNoMove', {'a': _name(state.current)}));
        setState(() {});
        if (state.isKi(state.current)) {
          Future.delayed(const Duration(milliseconds: 400), _aiRollDice);
        }
        break;
      case RollOutcome.retry:
        setState(() {});
        if (state.isKi(state.current)) {
          Future.delayed(const Duration(milliseconds: 300), _aiRollDice);
        }
        break;
      case RollOutcome.pass:
        state.addLog(t('cannotMove', {'a': _name(state.current)}));
        setState(() {});
        Future.delayed(const Duration(milliseconds: 1000), () {
          state.advancePlayer();
          setState(() {});
          _nextTurnSetup();
        });
        break;
    }
  }

  void _executeMove(Move m) {
    final c = state.current;
    state.phase = GamePhase.anim;
    state.movable = [];

    // Bewegung an den Vsync-Ticker übergeben – _advanceMove() in _onTick zieht
    // ab dem nächsten Frame die fälligen Schritte nach und spielt den Tick im
    // selben Frame, in dem die Figur das Feld erreicht.
    _animMove = m;
    _animPlayer = c;
    _animPath = state.makePath(c, m);
    _animSeq = state.seq;
    _animStarted = false;
    _animShown = -1;
    setState(() {});
  }

  /// Wird jeden Frame aus [_onTick] aufgerufen. Bestimmt aus der seit
  /// Bewegungsstart verstrichenen Ticker-Zeit, welcher Schritt jetzt fällig
  /// ist, schreibt die Figur dorthin und spielt pro erreichtem Feld einen
  /// Tick – alles im selben Frame, daher fester Bild/Ton-Versatz.
  void _advanceMove(Duration elapsed) {
    final mv = _animMove;
    if (mv == null) return;
    if (_animSeq != state.seq) { _animMove = null; return; } // neues Spiel
    if (!_animStarted) { _animStart = elapsed; _animStarted = true; }

    // Schritt j wird bei (j+1)*_stepMs sichtbar (140 ms Anlauf wie bisher).
    final e = (elapsed - _animStart).inMilliseconds;
    final k = (e ~/ _stepMs) - 1;
    if (k > _animShown) {
      final target = k.clamp(0, _animPath.length - 1);
      // Bei einem Frame-Hänger mehrere Felder nachholen – ein Tick je Feld.
      for (var j = _animShown + 1; j <= target; j++) {
        state.players[_animPlayer].pieces[mv.piece] = _animPath[j];
        GameAudio.instance.tick();
      }
      _animShown = target;
    }
    if (_animShown >= _animPath.length - 1) {
      _animMove = null; // Bewegung fertig
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || _animSeq != state.seq) return;
        _onMoveDone(mv);
      });
    }
  }

  void _onMoveDone(Move m) {
    final c = state.current;
    final events = state.finalizeMove(m);
    for (final e in events) {
      if (e is CaptureEvent) {
        final coords = fieldPos[e.field];
        _spawnExplosion(coords[0].toDouble(), coords[1].toDouble(),
            palette[state.colors[e.player]].hex);
        GameAudio.instance.boom();
        state.addLog(t('capture',
            {'a': _name(c), 'b': _name(e.player)}));
      } else if (e is PenaltyEvent) {
        _spawnExplosion(e.x, e.y, palette[state.colors[c]].hex);
        GameAudio.instance.boom();
        state.addLog(t('penalty', {'a': _name(c)}));
      } else if (e is BringOutEvent) {
        GameAudio.instance.pop();
        state.addLog(t('bringOut', {'a': _name(c)}));
      } else if (e is GoalEvent) {
        GameAudio.instance.goal();
        state.addLog(t('goal', {'a': _name(c)}));
      } else if (e is FinishedEvent) {
        GameAudio.instance.fanfare();
        state.addLog(t('finished', {'a': _name(c)}));
      }
    }
    setState(() {});
    if (state.phase == GamePhase.over) return;

    final p = state.players[c];
    if (!p.finished && state.dice == 6) {
      state.addLog(t('rollAgain', {'a': _name(c)}));
      state.startTurn();
      setState(() {});
      if (state.isKi(c)) {
        Future.delayed(const Duration(milliseconds: 400), _aiRollDice);
      }
    } else {
      state.advancePlayer();
      _nextTurnSetup();
    }
  }

  String _name(int p) =>
      t('color${palette[state.colors[p]].key[0].toUpperCase()}'
          '${palette[state.colors[p]].key.substring(1)}');

  // ------ Rendering ------
  @override
  Widget build(BuildContext context) {
    _maybeShowTurnToast();
    // canPop IMMER false: PopScope poppt nie selbst (das vermied ein Race, bei
    // dem das Pausieren canPop auf true kippt und Android danach doch beendet).
    // Stattdessen entscheidet _handleBack(): abgefangen → bleiben; sonst (nur
    // auf der Startseite) verlassen wir die App explizit per SystemNavigator.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_handleBack()) SystemNavigator.pop();
      },
      child: Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF3D2814),
        body: SafeArea(
          child: LayoutBuilder(builder: (ctx, c) {
            final boardSize = min(c.maxHeight, c.maxWidth - 280) - 24;
            _boardSize = boardSize.toDouble();
            return Stack(children: [
              // Holztisch über die gesamte Fläche; mit Vignette + Lichtschein
              Positioned.fill(
                child: CustomPaint(
                  painter: _WoodBackgroundPainter(),
                ),
              ),
              Positioned(
                left: 12,
                top: (c.maxHeight - boardSize) / 2,
                width: boardSize,
                height: boardSize,
                child: CustomPaint(
                  painter: BoardPainter(
                    state: state,
                    pulseT: pulseT,
                    dpadSetupIdx: dpadSetupIdx,
                    dpadMoveIdx: dpadMoveIdx,
                    dpadActive: dpadActive,
                    particles: particles,
                  ),
                  size: Size(boardSize, boardSize),
                ),
              ),
              // In der Spielphase: Würfel-Bereich erstreckt sich über
              // den ganzen Tisch rechts des Spielbretts – kein Padding,
              // damit der Würfel den vollen sichtbaren Tisch nutzt und
              // keine Plankenlinie zwischen Würfel-Rand und Brett-Rand
              // als "Streifen" sichtbar wird.
              if (state.phase != GamePhase.setup)
                Positioned(
                  left: 12 + boardSize + 12,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _diceWidget(),
                ),
              // Setup-Phase: Anweisung und „Spiel starten"-Knopf im
              // engen Seitenpanel.
              if (state.phase == GamePhase.setup)
                Positioned(
                  left: boardSize + 36,
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: _sidePanel(),
                ),
              // Power-Bar am rechten Rand. Sichtbar wenn ein Wurf ansteht
              // (Roll-Phase und Würfel ruht), während Mensch hält oder
              // KI auflädt. Während die Würfelphysik läuft, ist der Balken
              // ausgeblendet, damit der Würfel nicht hinter ihm „verschwindet"
              // wenn er bis ans rechte Tisch-Ende rollt.
              if (state.players.isNotEmpty &&
                  (state.phase == GamePhase.roll ||
                      _charging ||
                      _aiChargeTimer != null) &&
                  !diceRolling)
                Positioned(
                  right: 16,
                  top: c.maxHeight * 0.15,
                  bottom: c.maxHeight * 0.15,
                  width: 18,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PowerBarPainter(
                        progress: _chargeFraction,
                        playerColor:
                            palette[state.colors[state.current]].hex,
                      ),
                    ),
                  ),
                ),
              // Toast „X ist am Zug" – mittig auf der rechten Tischplatte
              // (deckt sich mit dem Würfel-Bereich, links durch das Brett,
              // rechts durch den Bildschirmrand begrenzt).
              if (_toastMessage != null)
                Positioned(
                  left: 12 + boardSize + 12,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xD0000000),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _toastMessage!,
                          style: TextStyle(
                            color: state.players.isNotEmpty
                                ? palette[state.colors[state.current]].hex
                                : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (state.phase == GamePhase.over) _gameOverOverlay(),
              if (paletteOpen) _paletteOverlay(),
            ]);
          }),
        ),
      ),
    ));
  }

  Widget _sidePanel() {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: state.phase == GamePhase.setup
          ? _setupSide()
          : _playSide(),
    );
  }

  Widget _setupSide() {
    final invalid = state.setupValid();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(t('titleHtml'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              color: Color(0xFFFFEEC4),
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Color(0xFFFFCD64), blurRadius: 16),
                Shadow(color: Color(0xFFFFB43C), blurRadius: 32),
              ],
            )),
        const SizedBox(height: 20),
        Text(
          t('instrLong'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFFFFEEC4), fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 24),
        // Feste Seiten-Buttons (D-Pad-navigierbar + Touch). „Weiterspielen"
        // nur, wenn ein Spiel pausiert im Hintergrund liegt.
        if (_paused) _sideButton(_btnResume, t('btnResume')),
        _sideButton(_btnStart, t('btnStart'),
            primary: true, disabled: invalid != null),
        _sideButton(
            _btnSound,
            GameAudio.instance.soundOn
                ? t('menuSoundOn')
                : t('menuSoundOff')),
        if (invalid != null) ...[
          const SizedBox(height: 8),
          Text(
            invalid == 'min-players' ? t('errMinPlayers') : t('errColors'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFC4B4), fontSize: 14),
          ),
        ],
      ],
    );
  }

  /// Ein fester Seiten-Button auf der Startseite. [primary] = großer grüner
  /// Aktions-Button (Spiel starten); fokussiert (D-Pad) → gelber Rahmen.
  Widget _sideButton(int idx, String label,
      {bool primary = false, bool disabled = false}) {
    final focused = dpadSetupIdx == idx && dpadActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () {
          setState(() => dpadSetupIdx = idx);
          if (!disabled) _activateSideButton(idx);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: primary
                ? (disabled ? const Color(0xFF5A554C) : const Color(0xFF2E933C))
                : const Color(0xFF383F46),
            borderRadius: BorderRadius.circular(12),
            boxShadow: focused
                ? const [BoxShadow(color: Color(0xFFFFD54F), blurRadius: 18)]
                : null,
            border: focused
                ? Border.all(color: const Color(0xFFFFD54F), width: 3)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Text(label,
              style: TextStyle(
                  fontSize: primary ? 22 : 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    );
  }

  // Spielphase: der ganze Tisch (rechte Spalte) gehört dem Würfel.
  // Keine Status-Texte oder Log-Liste – wie in der HTML-Version.
  Widget _playSide() {
    return _diceWidget();
  }

  String _statusText() {
    if (state.phase == GamePhase.roll) {
      return state.isHuman(state.current)
          ? t('statusRollHuman')
          : t('statusRollKi', {'a': _name(state.current)});
    }
    if (state.phase == GamePhase.move) {
      return state.isHuman(state.current)
          ? t('statusMoveHuman')
          : t('statusMoveKi', {'a': _name(state.current)});
    }
    return '';
  }

  Widget _diceWidget() {
    return SizedBox.expand(
      child: DiceGlNative(
        rolling: diceRolling,
        energy: diceEnergy,
        unit: _boardSize / 12,
        onSettled: _onDiceSettled,
      ),
    );
  }

  Widget _gameOverOverlay() {
    final medals = ['🥇', '🥈', '🥉', '4.'];
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF383F46),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('gameOver'),
                  style: const TextStyle(
                      fontSize: 24,
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...List.generate(state.ranking.length, (i) {
                final q = state.ranking[i];
                final isAi = state.players[q].type == PlayerType.ki;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(medals[i], style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette[state.colors[q]].hex,
                            border: Border.all(color: Colors.white70, width: 2),
                          )),
                      const SizedBox(width: 10),
                      Text('${_name(q)}${isAi ? " (${t('computer')})" : ""}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E933C),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFFFFD54F), blurRadius: 12)
                  ],
                ),
                child: Text('OK → ${t('btnAgain')}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paletteOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xE6160F08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x40FFDCA0)),
        ),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: List.generate(palette.length, (i) {
            final selected = i == dpadPaletteIdx;
            return Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette[i].hex,
                border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 3 : 2),
                boxShadow: selected
                    ? const [BoxShadow(color: Colors.white, blurRadius: 12)]
                    : null,
              ),
            );
          }),
        ),
      ),
    );
  }

}

/// Vertikale „Powerbar" am rechten Bildschirmrand.
/// * Unterer Block: kurzer Farbabschnitt in der aktuellen Spielerfarbe –
///   ersetzt den früheren 3D-Glow um den Würfel.
/// * Darüber: Lade-Fortschritt (gelb→rot), füllt sich beim Halten der
///   Würfeltaste. Ersetzt den alten Power-Ring, der pixelgenau dem
///   Würfel folgen sollte (was via 3D→2D-Projektion nie stabil war).
class _PowerBarPainter extends CustomPainter {
  final double progress;
  final Color playerColor;
  _PowerBarPainter({required this.progress, required this.playerColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Hintergrund (durchscheinend dunkel)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(w * 0.4)),
      Paint()..color = const Color(0x40000000),
    );
    // Spielerfarben-Sockel unten (10 % der Höhe)
    final colorBandH = h * 0.10;
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        0, h - colorBandH, w, h,
        bottomLeft: Radius.circular(w * 0.4),
        bottomRight: Radius.circular(w * 0.4),
      ),
      Paint()..color = playerColor,
    );
    // Lade-Fortschritt (über dem Sockel, von unten nach oben)
    if (progress > 0) {
      final fillH = (h - colorBandH) * progress.clamp(0.0, 1.0);
      final fillColor = Color.lerp(
        const Color(0xFFFFD54F),
        const Color(0xFFE53935),
        progress.clamp(0.0, 1.0),
      )!;
      canvas.drawRect(
        Rect.fromLTWH(0, h - colorBandH - fillH, w, fillH),
        Paint()..color = fillColor,
      );
      if (progress >= 1.0) {
        // Bei Vollausschlag dezenter weißer Glanz oben.
        canvas.drawRect(
          Rect.fromLTWH(0, h - colorBandH - fillH, w, w * 0.4),
          Paint()..color = const Color(0x40FFFFFF),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PowerBarPainter old) =>
      old.progress != progress || old.playerColor != playerColor;
}

/// Holzhintergrund: gekachelte Maserung + Lichtschein o.l. + Vignette.
class _WoodBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wood = cachedWood;
    if (wood == null) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFF3D2814));
      return;
    }
    // Die Textur ist in Bildschirmgröße erzeugt → einmal über die ganze Fläche
    // zeichnen (keine Kachelung, keine Naht). Image-Pixel = physische Pixel →
    // pixelscharf. Die Planken laufen durchgehend über die Breite.
    canvas.drawImageRect(
      wood,
      Rect.fromLTWH(0, 0, wood.width.toDouble(), wood.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
    // Lichtschein o.l. (warm)
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.35, size.height * 0.15),
        size.shortestSide * 0.9,
        [const Color(0x12FFE6B4), const Color(0x00000000)],
        const [0, 0.65],
      );
    canvas.drawRect(Offset.zero & size, glow);
    // Vignette
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.5),
        size.longestSide * 0.65,
        [const Color(0x00000000), const Color(0x60000000)],
        const [0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(_WoodBackgroundPainter old) => false;
}

// (Der Würfel steckt in dice_canvas.dart::DiceCube – 3D über Skia/CustomPainter.)
