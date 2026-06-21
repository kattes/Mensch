import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio.dart';

/// Eine Würfelgeräusch-Variante mit allen Syntheseparametern.
class KnockSpec {
  final String label;
  final double freq, bright, decay, q, durSec, vol;
  const KnockSpec(this.label,
      {required this.freq,
      required this.bright,
      required this.decay,
      required this.q,
      this.durSec = 0.04,
      this.vol = 0.44});
}

/// Hör-Labor zum Auswählen des Würfelklangs. Per D-Pad (◀ ▶ oder Ziffern)
/// Variante wählen, OK = erneut abspielen. Jede Auswahl spielt eine kurze
/// „Auslauf"-Sequenz (mehrere Klacks abnehmender Stärke + Schluss-Tab), damit
/// der Klang so beurteilt wird, wie er im Spiel klingt.
///
/// ITERATION 3 (Feinschliff): 10 enge Abstufungen um „tiefer + runder"
/// (freq 195, bright 0.06, decay 125, q 1.05). #1 = aktuelle Wahl.
const List<KnockSpec> kLabSpecs = [
  KnockSpec('1 Basis (Wahl)',        freq: 195, bright: 0.06, decay: 125, q: 1.05, durSec: 0.055, vol: 0.42),
  KnockSpec('2 Hauch tiefer',        freq: 185, bright: 0.05, decay: 125, q: 1.05, durSec: 0.055, vol: 0.42),
  KnockSpec('3 Hauch höher',         freq: 205, bright: 0.07, decay: 125, q: 1.05, durSec: 0.055, vol: 0.42),
  KnockSpec('4 noch runder',         freq: 195, bright: 0.05, decay: 108, q: 1.15, durSec: 0.060, vol: 0.42),
  KnockSpec('5 Hauch trockener',     freq: 195, bright: 0.07, decay: 145, q: 0.95, durSec: 0.050, vol: 0.42),
  KnockSpec('6 tiefer + runder',     freq: 185, bright: 0.04, decay: 108, q: 1.15, durSec: 0.060, vol: 0.42),
  KnockSpec('7 etwas lauter',        freq: 195, bright: 0.06, decay: 125, q: 1.05, durSec: 0.055, vol: 0.48),
  KnockSpec('8 etwas leiser',        freq: 195, bright: 0.06, decay: 125, q: 1.05, durSec: 0.055, vol: 0.37),
  KnockSpec('9 tiefer·mehr Körper',  freq: 188, bright: 0.05, decay: 116, q: 1.10, durSec: 0.058, vol: 0.42),
  KnockSpec('10 Hauch heller',       freq: 198, bright: 0.10, decay: 125, q: 1.05, durSec: 0.055, vol: 0.42),
];

class SoundLab extends StatefulWidget {
  const SoundLab({super.key});
  @override
  State<SoundLab> createState() => _SoundLabState();
}

class _SoundLabState extends State<SoundLab> {
  final FocusNode _focus = FocusNode();
  final List<AudioSource?> _sources = [];
  int _index = 0;
  bool _loading = true;
  Timer? _seq;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _load();
  }

  Future<void> _load() async {
    await GameAudio.instance.init();
    for (final s in kLabSpecs) {
      _sources.add(await GameAudio.instance.makeKnock(
        freq: s.freq, bright: s.bright, decay: s.decay,
        q: s.q, durSec: s.durSec, vol: s.vol,
      ));
    }
    if (mounted) setState(() => _loading = false);
    _playDemo();
  }

  // Kurze Auslauf-Sequenz wie ein zur Ruhe kommender Würfel.
  void _playDemo() {
    _seq?.cancel();
    final src = _index < _sources.length ? _sources[_index] : null;
    if (src == null) return;
    const strengths = [0.85, 0.7, 0.55, 0.42, 0.33, 0.27];
    var i = 0;
    void step() {
      if (!mounted || i >= strengths.length) return;
      final st = strengths[i];
      GameAudio.instance.playKnock(src,
          volume: (0.42 + st * 0.55).clamp(0.0, 1.0),
          speed: 0.92 + st * 0.06 + (i.isEven ? 0.03 : -0.02));
      i++;
      // Abstände werden zum Ende hin größer (Würfel rollt aus).
      _seq = Timer(Duration(milliseconds: 95 + i * 14), step);
    }
    step();
  }

  void _move(int d) {
    setState(() => _index = (_index + d) % kLabSpecs.length);
    if (_index < 0) _index += kLabSpecs.length;
    _playDemo();
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown) {
      _move(1); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp) {
      _move(-1); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.numpadEnter) {
      _playDemo(); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _seq?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = kLabSpecs[_index];
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF241712),
        body: Center(
          child: _loading
              ? const Text('lade Klänge…',
                  style: TextStyle(color: Colors.white70, fontSize: 24))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔊 Würfel-Sound-Labor · Iteration 3',
                        style: TextStyle(color: Color(0xFFFFD54F), fontSize: 26,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Text('${_index + 1} / ${kLabSpecs.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 64,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(spec.label,
                        style: const TextStyle(color: Colors.white, fontSize: 30)),
                    const SizedBox(height: 10),
                    Text('freq ${spec.freq.toInt()} · bright ${spec.bright} · '
                        'decay ${spec.decay.toInt()} · q ${spec.q} · '
                        'dur ${(spec.durSec * 1000).toInt()}ms · vol ${spec.vol}',
                        style: const TextStyle(color: Colors.white54, fontSize: 16)),
                    const SizedBox(height: 32),
                    const Text('◀ ▶ Variante wählen   ·   OK = erneut abspielen',
                        style: TextStyle(color: Colors.white70, fontSize: 18)),
                  ],
                ),
        ),
      ),
    );
  }
}
