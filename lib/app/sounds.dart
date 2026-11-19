import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Short notification sounds, synthesised in the app (no audio files, no plugins).
/// On Windows they play through winmm's PlaySound; elsewhere a system sound is used.
enum Sfx {
  login, // two-note rise
  start, // three-note rise
  select, // soft tick when an answer is chosen
  warning, // 5 minutes left
  urgent, // 1 minute left
  tick, // each of the last 10 seconds
  timeUp,
  submitted,
  paused,
  resumed,
  offline,
  online,
  error,
  alert, // admin: something needs attention
}

class Sounds {
  Sounds._();

  /// Master switch (set from the exam server's "sounds on student computers" setting).
  static bool enabled = true;

  static const _rate = 22050;
  static final _cache = <Sfx, Pointer<Uint8>>{};

  static void play(Sfx s) {
    if (!enabled) return;
    try {
      if (Platform.isWindows) {
        _playWindows(s);
      } else {
        SystemSound.play(s == Sfx.select || s == Sfx.tick ? SystemSoundType.click : SystemSoundType.alert);
      }
    } catch (_) {
      // never let a sound problem disturb the exam
    }
  }

  // ── Windows: PlaySoundW(wav bytes, NULL, SND_MEMORY | SND_ASYNC | SND_NODEFAULT) ──
  static int Function(Pointer<Uint8>, Pointer<Void>, int)? _playSound;

  static void _playWindows(Sfx s) {
    _playSound ??= DynamicLibrary.open('winmm.dll')
        .lookupFunction<Int32 Function(Pointer<Uint8>, Pointer<Void>, Uint32), int Function(Pointer<Uint8>, Pointer<Void>, int)>('PlaySoundW');
    final ptr = _cache.putIfAbsent(s, () {
      final wav = _wav(_synth(s));
      final p = malloc<Uint8>(wav.length); // kept for the app's lifetime: PlaySound reads it asynchronously
      p.asTypedList(wav.length).setAll(0, wav);
      return p;
    });
    const sndAsync = 0x0001, sndNoDefault = 0x0002, sndMemory = 0x0004;
    _playSound!(ptr, nullptr, sndAsync | sndNoDefault | sndMemory);
  }

  // ── synthesis ───────────────────────────────────────────────────────────

  /// A note: frequency (Hz), start (s), length (s), loudness 0–1.
  static List<double> _synth(Sfx s) {
    final notes = switch (s) {
      Sfx.login => [(659.3, 0.0, 0.18, 0.5), (880.0, 0.10, 0.35, 0.5)],
      Sfx.start => [(523.3, 0.0, 0.2, 0.45), (659.3, 0.11, 0.2, 0.45), (784.0, 0.22, 0.45, 0.5)],
      Sfx.select => [(1318.5, 0.0, 0.05, 0.18)],
      Sfx.warning => [(880.0, 0.0, 0.25, 0.45), (880.0, 0.32, 0.4, 0.45)],
      Sfx.urgent => [(987.8, 0.0, 0.12, 0.5), (987.8, 0.18, 0.12, 0.5), (987.8, 0.36, 0.25, 0.55)],
      Sfx.tick => [(1046.5, 0.0, 0.06, 0.3)],
      Sfx.timeUp => [(784.0, 0.0, 0.25, 0.5), (659.3, 0.2, 0.25, 0.5), (523.3, 0.4, 0.6, 0.55)],
      Sfx.submitted => [(1046.5, 0.0, 0.5, 0.35), (1318.5, 0.08, 0.6, 0.35), (1568.0, 0.16, 0.8, 0.3)],
      Sfx.paused => [(659.3, 0.0, 0.22, 0.45), (440.0, 0.16, 0.45, 0.45)],
      Sfx.resumed => [(440.0, 0.0, 0.18, 0.45), (659.3, 0.12, 0.4, 0.45)],
      Sfx.offline => [(392.0, 0.0, 0.2, 0.4), (261.6, 0.14, 0.4, 0.4)],
      Sfx.online => [(523.3, 0.0, 0.14, 0.4), (784.0, 0.09, 0.3, 0.4)],
      Sfx.error => [(220.0, 0.0, 0.14, 0.4), (220.0, 0.2, 0.2, 0.4)],
      Sfx.alert => [(1174.7, 0.0, 0.18, 0.4), (880.0, 0.14, 0.18, 0.4), (1174.7, 0.28, 0.3, 0.4)],
    };
    final total = notes.map((n) => n.$2 + n.$3).reduce(math.max) + 0.05;
    final out = List<double>.filled((total * _rate).ceil(), 0);
    for (final (f, start, len, vol) in notes) {
      final s0 = (start * _rate).round(), n = (len * _rate).round();
      for (var i = 0; i < n && s0 + i < out.length; i++) {
        final t = i / _rate;
        // soft attack, exponential decay, a touch of the octave for a bell-like tone
        final attack = math.min(1.0, t / 0.008);
        final decay = math.exp(-t * (4.5 / len));
        final w = math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t) + 0.08 * math.sin(6 * math.pi * f * t);
        out[s0 + i] += vol * attack * decay * w / 1.33;
      }
    }
    return out;
  }

  /// 16-bit mono PCM WAV.
  static Uint8List _wav(List<double> samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// For testing: the WAV bytes of a sound.
  static Uint8List wavFor(Sfx s) => _wav(_synth(s));
}
