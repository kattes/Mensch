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

  // Sound-Quellen
  AudioSource? _tick, _pop, _boom, _knockSoft, _knockHard, _thud, _six, _goal,
      _impact;
  List<AudioSource> _fanfare = [];

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
    // Banden-Aufprall des rollenden Würfels: kurzer tiefer Plopp + Noise.
    _impact = await _load('impact', _synthMix([
      _synthTone(freq0: 180, freq1: 60, durSec: 0.08, vol: 0.32, wave: _Wave.sine),
      _synthNoise(durSec: 0.06, vol: 0.18, fc0: 1800, fc1: 300),
    ]));

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

  /// Banden-/Tisch-Aufprall des rollenden Würfels. [strength] 0..1 skaliert
  /// die Lautstärke. Rate-Limiting macht der Aufrufer.
  void impact(double strength) => _play(_impact,
      volume: (0.25 + strength * 0.55).clamp(0.0, 1.0),
      speed: 0.92 + _rnd.nextDouble() * 0.16);

  /// Tick beim Figurenschritt – leichte Tonhöhen-Variation für Lebendigkeit.
  void tick() => _play(_tick, speed: 0.96 + _rnd.nextDouble() * 0.08);

  void pop()  => _play(_pop);
  void boom() => _play(_boom);
  void thud() => _play(_thud);
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
  return _wrapWav(pcm);
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
