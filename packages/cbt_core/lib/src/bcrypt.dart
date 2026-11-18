// Pure-Dart bcrypt verification (follows jBCrypt). Used by the local server
// to check students' portal passwords offline. Laravel stores "$2y$" hashes,
// which are the same algorithm as "$2a$"/"$2b$".
import 'dart:convert';
import 'dart:typed_data';

import 'blowfish_tables.dart';

const _alphabet = './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
final _index = () {
  final m = List<int>.filled(128, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    m[_alphabet.codeUnitAt(i)] = i;
  }
  return m;
}();

Uint8List _decode(String s, int maxBytes) {
  final out = <int>[];
  var i = 0;
  int c(int pos) {
    final cu = s.codeUnitAt(pos);
    final v = cu < 128 ? _index[cu] : -1;
    if (v < 0) throw const FormatException('bad bcrypt base64');
    return v;
  }

  while (i < s.length - 1 && out.length < maxBytes) {
    final c1 = c(i++), c2 = c(i++);
    out.add(((c1 << 2) | ((c2 & 0x30) >> 4)) & 0xff);
    if (out.length >= maxBytes || i >= s.length) break;
    final c3 = c(i++);
    out.add((((c2 & 0x0f) << 4) | ((c3 & 0x3c) >> 2)) & 0xff);
    if (out.length >= maxBytes || i >= s.length) break;
    final c4 = c(i++);
    out.add((((c3 & 0x03) << 6) | c4) & 0xff);
  }
  return Uint8List.fromList(out);
}

String _encode(List<int> d, int len) {
  final sb = StringBuffer();
  var off = 0;
  while (off < len) {
    var c1 = d[off++] & 0xff;
    sb.write(_alphabet[(c1 >> 2) & 0x3f]);
    c1 = (c1 & 0x03) << 4;
    if (off >= len) {
      sb.write(_alphabet[c1 & 0x3f]);
      break;
    }
    var c2 = d[off++] & 0xff;
    c1 |= (c2 >> 4) & 0x0f;
    sb.write(_alphabet[c1 & 0x3f]);
    c1 = (c2 & 0x0f) << 2;
    if (off >= len) {
      sb.write(_alphabet[c1 & 0x3f]);
      break;
    }
    c2 = d[off++] & 0xff;
    c1 |= (c2 >> 6) & 0x03;
    sb.write(_alphabet[c1 & 0x3f]);
    sb.write(_alphabet[c2 & 0x3f]);
  }
  return sb.toString();
}

class _Blowfish {
  final p = Uint32List.fromList(blowfishP);
  final s = Uint32List.fromList(blowfishS);

  int _f(int x) =>
      ((((s[(x >> 24) & 0xff] + s[0x100 | ((x >> 16) & 0xff)]) & 0xffffffff) ^ s[0x200 | ((x >> 8) & 0xff)]) +
          s[0x300 | (x & 0xff)]) &
      0xffffffff;

  void encipher(Uint32List lr, int off) {
    var l = lr[off], r = lr[off + 1];
    l ^= p[0];
    for (var i = 1; i <= 16; i += 2) {
      r ^= _f(l) ^ p[i];
      l ^= _f(r) ^ p[i + 1];
    }
    lr[off] = r ^ p[17];
    lr[off + 1] = l;
  }

  static int _streamWord(List<int> data, List<int> offp) {
    var word = 0;
    var off = offp[0];
    for (var i = 0; i < 4; i++) {
      word = ((word << 8) | (data[off] & 0xff)) & 0xffffffff;
      off = (off + 1) % data.length;
    }
    offp[0] = off;
    return word;
  }

  void key(List<int> key) {
    final koff = [0];
    final lr = Uint32List(2);
    for (var i = 0; i < 18; i++) {
      p[i] ^= _streamWord(key, koff);
    }
    for (var i = 0; i < 18; i += 2) {
      encipher(lr, 0);
      p[i] = lr[0];
      p[i + 1] = lr[1];
    }
    for (var i = 0; i < 1024; i += 2) {
      encipher(lr, 0);
      s[i] = lr[0];
      s[i + 1] = lr[1];
    }
  }

  void eksKey(List<int> salt, List<int> key) {
    final koff = [0], soff = [0];
    final lr = Uint32List(2);
    for (var i = 0; i < 18; i++) {
      p[i] ^= _streamWord(key, koff);
    }
    for (var i = 0; i < 18; i += 2) {
      lr[0] ^= _streamWord(salt, soff);
      lr[1] ^= _streamWord(salt, soff);
      encipher(lr, 0);
      p[i] = lr[0];
      p[i + 1] = lr[1];
    }
    for (var i = 0; i < 1024; i += 2) {
      lr[0] ^= _streamWord(salt, soff);
      lr[1] ^= _streamWord(salt, soff);
      encipher(lr, 0);
      s[i] = lr[0];
      s[i + 1] = lr[1];
    }
  }
}

const _ctext = [0x4f727068, 0x65616e42, 0x65686f6c, 0x64657253, 0x63727944, 0x6f756274]; // "OrpheanBeholderScryDoubt"

String _hash(String password, String setting) {
  // setting: $2y$10$ + 22 salt chars
  final m = RegExp(r'^\$2([abxy])\$(\d\d)\$([./A-Za-z0-9]{22})').firstMatch(setting);
  if (m == null) throw const FormatException('not a bcrypt hash');
  final minor = m.group(1)!;
  final rounds = int.parse(m.group(2)!);
  if (rounds < 4 || rounds > 31) throw const FormatException('bad cost');
  final salt = _decode(m.group(3)!, 16);

  List<int> pw = [...utf8.encode(password), 0];
  if (pw.length > 72) pw = pw.sublist(0, 72);

  final bf = _Blowfish()..eksKey(salt, pw);
  final n = 1 << rounds;
  for (var i = 0; i < n; i++) {
    bf.key(pw);
    bf.key(salt);
  }
  final cdata = Uint32List.fromList(_ctext);
  for (var i = 0; i < 64; i++) {
    for (var j = 0; j < 3; j++) {
      bf.encipher(cdata, j << 1);
    }
  }
  final out = <int>[];
  for (final w in cdata) {
    out..add((w >> 24) & 0xff)..add((w >> 16) & 0xff)..add((w >> 8) & 0xff)..add(w & 0xff);
  }
  return '\$2$minor\$${m.group(2)}\$${_encode(salt, 16)}${_encode(out, 23)}';
}

/// True when [password] matches the bcrypt [hash] (e.g. Laravel's "$2y$10$...").
bool bcryptVerify(String password, String? hash) {
  if (hash == null || hash.length != 60) return false;
  try {
    final h = _hash(password, hash);
    // constant-time compare
    var diff = 0;
    for (var i = 0; i < 60; i++) {
      diff |= h.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  } catch (_) {
    return false;
  }
}

/// Exposed for tests: hash [password] with the salt/cost of [setting].
String bcryptHashWithSetting(String password, String setting) => _hash(password, setting);
