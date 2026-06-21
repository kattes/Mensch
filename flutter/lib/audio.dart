import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Game-SFX über die SoLoud-Engine (flutter_soloud). SoLoud hält EINEN
/// dauerhaft offenen Low-Latency-Audiostream offen und mischt alle Stimmen
/// in Software – im Gegensatz zu SoundPool, das auf TV-Boxen wie der Mi-Box
/// pro Play einen frischen AudioTrack aufbaut und vom Gerät den schnellen
/// Mixer-Pfad verweigert bekommt (`AUDIO_OUTPUT_FLAG_FAST denied`) → hohe
/// Latenz, kurze Sounds (Tick) gehen unter. Die Sounds werden weiterhin in
/// Dart als 16-bit-PCM-Mono-WAV synthetisiert und einmalig in die Engine
/// geladen; danach spielt jeder Aufruf eine eigene, sofort hörbare Stimme.
class GameAudio {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  // 48 kHz = native Rate moderner Android-Hardware → kein Resampling.
  static const int _sampleRate = 48000;

  final SoLoud _soloud = SoLoud.instance;

  bool soundOn = true;
  bool _ready = false;

  // Gesamt-Absenkung aller rollenden Würfelgeräusche (Klack/Thock/Tab):
  // −12 dB ≙ Amplitudenfaktor 0.25.
  static const double _diceGain = 0.25;

  // Stimme des zuletzt gespielten Klacks – wird vor dem nächsten gestoppt,
  // damit Kantenwechsel-Klacks sich nie überlagern (sonst Knattern).
  SoundHandle? _klackHandle;

  // Sound-Quellen
  AudioSource? _tick, _pop, _boom, _knockSoft, _knockHard, _thud, _six, _goal;
  List<AudioSource> _fanfare = [];
  // Varianten-Pools (dumpf → hell sortiert) für natürliche, nie identische
  // Würfelgeräusche: Kantenwechsel-Klack und Banden-/Tisch-Thock.
  final List<AudioSource> _klacks = [], _impacts = [];

  Future<void> init() async {
    if (_ready) return;
    try {
      await _soloud.init(sampleRate: _sampleRate);
    } catch (_) {
      return; // Audio nicht verfügbar – Spiel läuft stumm weiter
    }

    // Anders als bei SoundPool ist KEINE Varianten-Sammlung nötig: SoLoud
    // fasst gleiche Stimmen nicht zusammen und braucht kein Vorwärmen. Leichte
    // Tonhöhen-Variation kommt zur Laufzeit über setRelativePlaySpeed().
    _tick = await _load('tick', _synthTone(
        freq0: 760, freq1: 460, durSec: 0.075, vol: 0.40, wave: _Wave.square));
    _pop = await _load('pop', _synthTone(
        freq0: 300, freq1: 640, durSec: 0.13, vol: 0.35, wave: _Wave.sine));
    // Boom = sharp click vorne + tiefer Rumble + Rauschen-Tail. Ohne den Click
    // setzt der Hörer den Sound erst beim Rumble an (gefühlte Latenz).
    _boom = await _load('boom', _synthMix([
      _synthTone(freq0: 2200, freq1: 800, durSec: 0.025, vol: 0.55, wave: _Wave.square),
      _synthTone(freq0: 110,  freq1: 36,  durSec: 0.50,  vol: 0.50, wave: _Wave.sine),
      _synthNoise(durSec: 0.55, vol: 0.55, fc0: 1400, fc1: 110),
    ]));
    _knockSoft = await _load('knockSoft', _synthMix([
      _synthTone(freq0: 165, freq1: 65, durSec: 0.09, vol: 0.18, wave: _Wave.triangle),
      _synthNoise(durSec: 0.05, vol: 0.12, fc0: 2500, fc1: 500),
    ]));
    _knockHard = await _load('knockHard', _synthMix([
      _synthTone(freq0: 200, freq1: 60, durSec: 0.10, vol: 0.50, wave: _Wave.triangle),
      _synthNoise(durSec: 0.07, vol: 0.35, fc0: 2500, fc1: 400),
    ]));
    _thud = await _load('thud', _synthMix([
      _synthTone(freq0: 120, freq1: 55, durSec: 0.16, vol: 0.40, wave: _Wave.sine),
      _synthNoise(durSec: 0.08, vol: 0.20, fc0: 1400, fc1: 250),
    ]));
    _six = await _load('six', _synthTone(
        freq0: 1319, freq1: 1319, durSec: 0.22, vol: 0.30, wave: _Wave.sine));
    _goal = await _load('goal', _synthMix([
      _synthTone(freq0: 659, freq1: 659, durSec: 0.18, vol: 0.26, wave: _Wave.sine),
      _synthTone(freq0: 988, freq1: 988, durSec: 0.28, vol: 0.24, wave: _Wave.sine,
                 delaySec: 0.12),
    ]));
    // Kantenwechsel-Klack: im Hörlabor (sound_lab.dart) ausgewählter Klang –
    // tief, rund, dezent. Geräuschhafter Resonator (kein Ton/Xylophon). 6
    // Varianten mit winziger Streuung (keine Tonleiter); Helligkeit steigt
    // leicht mit der Härte (für _pickByStrength).
    for (var i = 0; i < 6; i++) {
      final b = i / 5.0;
      _klacks.add(await _load('klack$i', _synthKnock(
        freq: 185 + (i.isEven ? 6 : -5),
        bright: 0.02 + b * 0.10,
        seed: 101 + i * 7,
        durSec: 0.060,
        vol: 0.42,
        decay: 108,
        q: 1.15,
      )));
    }
    // Banden-/Tisch-Thock: tiefer abgeleitet (~145 Hz), gleicher runder
    // Charakter, damit klar vom Klack unterscheidbar.
    for (var i = 0; i < 6; i++) {
      final b = i / 5.0;
      _impacts.add(await _load('impact$i', _synthKnock(
        freq: 145 + (i.isEven ? 5 : -4),
        bright: 0.00 + b * 0.10,
        seed: 211 + i * 5,
        durSec: 0.072,
        vol: 0.50,
        decay: 100,
        q: 1.15,
      )));
    }

    _fanfare = [];
    for (final f in [523, 659, 784, 1047]) {
      _fanfare.add(await _load('fanfare$f', _synthTone(
          freq0: f.toDouble(), freq1: f.toDouble(),
          durSec: 0.30, vol: 0.30, wave: _Wave.triangle)));
    }
    _fanfare.add(await _load('fanfareEnd', _synthTone(
        freq0: 1047, freq1: 1047, durSec: 0.6, vol: 0.24, wave: _Wave.triangle)));

    _ready = true;
  }

  Future<AudioSource> _load(String name, Uint8List wav) =>
      _soloud.loadMem(name, wav);

  static final _rnd = Random();

  void _play(AudioSource? src, {double volume = 1.0, double speed = 1.0}) {
    if (!soundOn || !_ready || src == null) return;
    try {
      final h = _soloud.play(src, volume: volume);
      if (speed != 1.0) _soloud.setRelativePlaySpeed(h, speed);
    } catch (_) {
      // einzelner Sound darf das Spiel nie stören
    }
  }

  /// Wählt aus einem dumpf→hell sortierten Pool nach Härte eine Variante,
  /// plus ±1 Zufallsversatz für Lebendigkeit (nie zweimal dieselbe).
  AudioSource? _pickByStrength(List<AudioSource> pool, double s) {
    if (pool.isEmpty) return null;
    final base = (s.clamp(0.0, 1.0) * (pool.length - 1)).round();
    final idx = (base + _rnd.nextInt(3) - 1).clamp(0, pool.length - 1);
    return pool[idx];
  }

  /// Banden-/Tisch-Aufprall des rollenden Würfels. [strength] 0..1 steuert
  /// Lautstärke, Klangfarbe (härter = heller) und Tonhöhe. Rate-Limiting macht
  /// der Aufrufer (natives Plugin).
  void impact(double strength) {
    final s = strength.clamp(0.0, 1.0);
    _play(_pickByStrength(_impacts, s),
        volume: ((0.30 + s * 0.60) * _diceGain).clamp(0.0, 1.0),
        speed: 0.86 + s * 0.05 + _rnd.nextDouble() * 0.08);
  }

  /// Tick beim Figurenschritt – leichte Tonhöhen-Variation für Lebendigkeit.
  void tick() => _play(_tick, speed: 0.96 + _rnd.nextDouble() * 0.08);

  /// Holz-Klack bei jedem Kantenwechsel. Variante nach Härte + Zufall, Tonhöhe
  /// steigt mit der Rollgeschwindigkeit [strength] (0..1). Monophon: stoppt
  /// zuerst das vorige Klack, damit sich keine zwei überlagern.
  void klack([double strength = 1.0]) {
    if (!soundOn || !_ready || _klacks.isEmpty) return;
    final s = strength.clamp(0.0, 1.0);
    try {
      final prev = _klackHandle;
      if (prev != null && _soloud.getIsValidVoiceHandle(prev)) {
        _soloud.stop(prev);
      }
      final src = _pickByStrength(_klacks, s)!;
      final h = _soloud.play(src,
          volume: ((0.42 + s * 0.55) * _diceGain).clamp(0.0, 1.0));
      // Nur winzige Tonhöhenvariation – keine hörbare „Tonleiter" beim Rollen.
      // Mitte ~0.95, wie im Hörlabor ausgewählt.
      _soloud.setRelativePlaySpeed(h, 0.93 + s * 0.05 + _rnd.nextDouble() * 0.06);
      _klackHandle = h;
    } catch (_) {
      // einzelner Sound darf das Spiel nie stören
    }
  }

  void pop()  => _play(_pop);
  void boom() => _play(_boom);
  // Abschließendes „Tab", wenn der Würfel liegen bleibt – 6 dB leiser als die
  // übrigen Würfelgeräusche (Faktor 0.5), zusätzlich die −12-dB-Gesamtabsenkung.
  void thud() => _play(_thud, volume: 0.5 * _diceGain);
  void six()  => _play(_six);
  void goal() => _play(_goal);

  void knock(double strength) => _play(
      strength > 0.25 ? _knockHard : _knockSoft,
      speed: 0.92 + _rnd.nextDouble() * 0.16);

  void fanfare() {
    if (!soundOn || !_ready) return;
    for (var i = 0; i < _fanfare.length; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () => _play(_fanfare[i]));
    }
  }

  void toggle() { soundOn = !soundOn; }

  // ---- Sound-Labor (Audition von Würfelgeräuschen) ----
  int _labSeq = 0;

  /// Erzeugt eine einzelne Knock-Variante aus expliziten Parametern und lädt
  /// sie in die Engine. Nur für den Labor-Modus (sound_lab.dart).
  Future<AudioSource?> makeKnock({
    required double freq,
    required double bright,
    required double decay,
    required double q,
    required double durSec,
    required double vol,
  }) async {
    if (!_ready) return null;
    try {
      return await _load('lab${_labSeq++}', _synthKnock(
        freq: freq, bright: bright, seed: 1000 + _labSeq,
        decay: decay, q: q, durSec: durSec, vol: vol,
      ));
    } catch (_) {
      return null;
    }
  }

  /// Spielt eine im Labor erzeugte Quelle (mit Lautstärke/Tempo).
  void playKnock(AudioSource? s, {double volume = 1.0, double speed = 1.0}) =>
      _play(s, volume: volume, speed: speed);

  void dispose() {
    if (_ready) _soloud.deinit();
  }
}

enum _Wave { sine, square, triangle }

Uint8List _synthTone({
  required double freq0,
  required double freq1,
  required double durSec,
  required double vol,
  required _Wave wave,
  double delaySec = 0,
}) {
  final samples = (GameAudio._sampleRate * (durSec + delaySec)).round();
  final pcm = Int16List(samples);
  final delaySamples = (delaySec * GameAudio._sampleRate).round();
  final logRatio = log(max(1.0, freq1) / max(1.0, freq0));
  for (var n = 0; n < samples; n++) {
    if (n < delaySamples) continue;
    final i = n - delaySamples;
    final t = i / GameAudio._sampleRate;
    final tNorm = t / durSec;
    if (tNorm >= 1) break;
    final f = freq0 * exp(logRatio * tNorm);
    final phase = 2 * pi * f * t;
    double s;
    switch (wave) {
      case _Wave.sine:     s = sin(phase); break;
      case _Wave.square:   s = sin(phase) >= 0 ? 1.0 : -1.0; break;
      case _Wave.triangle: s = 2 * (2 * ((phase / (2 * pi)) % 1) - 1).abs() - 1;
    }
    final env = vol * exp(-3.5 * tNorm);
    pcm[n] = (s * env * 32767).clamp(-32768, 32767).toInt();
  }
  _fadeOutTail(pcm);
  return _wrapWav(pcm);
}

/// Blendet die letzten Millisekunden linear auf 0 aus. Ohne das endet ein
/// Sound bei Restamplitude und der harte Sprung auf Stille erzeugt einen
/// Klick – bei schnell wiederholten Sounds (Würfel-Klack) ein knatternder
/// „Schatten" hinter jedem Ton.
void _fadeOutTail(Int16List pcm) {
  final fade = (GameAudio._sampleRate * 0.004).round();
  final m = min(fade, pcm.length);
  for (var k = 0; k < m; k++) {
    final idx = pcm.length - 1 - k;
    pcm[idx] = (pcm[idx] * (k / m)).round();
  }
}

Uint8List _synthNoise({
  required double durSec,
  required double vol,
  required double fc0,
  required double fc1,
}) {
  final samples = (GameAudio._sampleRate * durSec).round();
  final pcm = Int16List(samples);
  final rnd = Random(42);
  double lp = 0;
  final logRatio = log(max(40.0, fc1) / max(40.0, fc0));
  for (var n = 0; n < samples; n++) {
    final t = n / GameAudio._sampleRate;
    final tNorm = t / durSec;
    if (tNorm >= 1) break;
    final raw = (rnd.nextDouble() * 2 - 1);
    final fc = fc0 * exp(logRatio * tNorm);
    final alpha = (2 * pi * fc) /
        (2 * pi * fc + GameAudio._sampleRate.toDouble());
    lp += alpha * (raw - lp);
    final env = vol * exp(-2.8 * tNorm);
    pcm[n] = (lp * env * 32767).clamp(-32768, 32767).toInt();
  }
  _fadeOutTail(pcm);
  return _wrapWav(pcm);
}

/// Holz-„Knock" als RAUSCH-angeregter Resonator (kein gestimmter Ton, sonst
/// klingt es wie ein Xylophon). Ein kurzer Rauschimpuls regt einen Bandpass
/// niedriger Güte an → ein geräuschhaftes „Tock" mit Holz-Charakter statt
/// klarer Tonhöhe. [freq] bestimmt grob die Größe (tief=dumpf), [bright] hebt
/// Mittenlage und Güte (härter=schärfer), [seed] macht jede Variante einzigartig.
Uint8List _synthKnock({
  required double freq,
  required double bright,
  required int seed,
  double durSec = 0.05,
  double vol = 0.5,
  double decay = 120, // höher = trockener/kürzer (weniger Nachklingen)
  double q = 1.0, // niedriger = breiter/trockener (weniger Resonanz-Schwanz)
}) {
  final sr = GameAudio._sampleRate.toDouble();
  final samples = (sr * durSec).round();
  final buf = Float64List(samples);
  final rnd = Random(seed);

  // Bandpass-Resonator (RBJ-Biquad). Güte [q] und [decay] steuern, wie trocken
  // der Knock klingt.
  final fc = (freq * (1.25 + 0.6 * bright)).clamp(110.0, sr / 2.2);
  final w0 = 2 * pi * fc / sr;
  final alpha = sin(w0) / (2 * q);
  final a0 = 1 + alpha;
  final b0 = alpha / a0, b2 = -alpha / a0;
  final a1 = (-2 * cos(w0)) / a0, a2 = (1 - alpha) / a0;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  final excite = (sr * 0.005).round(); // 5 ms Anregungs-Rauschen
  for (var n = 0; n < samples; n++) {
    final x = n < excite ? (rnd.nextDouble() * 2 - 1) : 0.0;
    final y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    buf[n] = y * exp(-decay * (n / sr));
  }

  var peak = 1e-6;
  for (final v in buf) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final g = vol / peak;
  final pcm = Int16List(samples);
  for (var n = 0; n < samples; n++) {
    pcm[n] = (buf[n] * g * 32767).clamp(-32768, 32767).toInt();
  }
  _fadeOutTail(pcm);
  return _wrapWav(pcm);
}

Uint8List _synthMix(List<Uint8List> wavs) {
  final pcms = wavs.map(_unwrapPcm).toList();
  final maxLen = pcms.map((p) => p.length).reduce(max);
  final out = Int16List(maxLen);
  for (var i = 0; i < maxLen; i++) {
    var sum = 0;
    for (final p in pcms) {
      if (i < p.length) sum += p[i];
    }
    out[i] = sum.clamp(-32768, 32767);
  }
  return _wrapWav(out);
}

Int16List _unwrapPcm(Uint8List wav) {
  final data = wav.sublist(44);
  return Int16List.view(data.buffer, data.offsetInBytes, data.length ~/ 2);
}

Uint8List _wrapWav(Int16List pcm) {
  final byteLen = pcm.length * 2;
  final b = BytesBuilder();
  void putStr(String s) => b.add(s.codeUnits);
  void putU32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF,
                              (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void putU16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);

  putStr('RIFF');
  putU32(36 + byteLen);
  putStr('WAVE');
  putStr('fmt ');
  putU32(16);
  putU16(1);
  putU16(1);
  putU32(GameAudio._sampleRate);
  putU32(GameAudio._sampleRate * 2);
  putU16(2);
  putU16(16);
  putStr('data');
  putU32(byteLen);
  b.add(Uint8List.view(pcm.buffer, pcm.offsetInBytes, byteLen));
  return b.toBytes();
}
