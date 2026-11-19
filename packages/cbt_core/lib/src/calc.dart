import 'dart:math' as math;

class CalcError implements Exception {
  CalcError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calculator engine for the exam screen (basic and scientific).
///
/// Supports: + − × ÷ * / ^, brackets, unary minus, %, !, implicit
/// multiplication (2π, 3(4), 2sin30), π, e, Ans, and the functions
/// sin cos tan asin acos atan sinh cosh tanh log (base 10) ln √ ∛ abs exp.
/// Trigonometry uses degrees unless [radians] is true.
class Calculator {
  Calculator({this.radians = false});
  bool radians;
  double ans = 0;

  static const functions = {'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'log', 'ln', 'sqrt', '√', 'cbrt', '∛', 'abs', 'exp'};

  late List<String> _t;
  var _i = 0;

  double evaluate(String input) {
    _t = _tokenize(input);
    _i = 0;
    if (_t.isEmpty) throw CalcError('Empty');
    final v = _expr();
    if (_i < _t.length) {
      if (_t[_i] == ')') throw CalcError('Unmatched )');
      throw CalcError('Syntax error');
    }
    if (v.isNaN || v.isInfinite) throw CalcError('Math error');
    final r = _clean(v);
    ans = r;
    return r;
  }

  /// Rounds away floating-point noise: sin(180°) = 0, 0.1+0.2 = 0.3.
  static double _clean(double v) {
    if (v.abs() < 1e-12) return 0;
    final p = double.parse(v.toStringAsPrecision(14));
    return p;
  }

  static String format(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    if (v.abs() >= 1e15 || v.abs() < 1e-9) {
      final s = v.toStringAsExponential(9);
      final parts = s.split('e');
      final m = parts[0].replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      return '$m×10^${parts[1].replaceFirst('+', '')}';
    }
    var s = v.toStringAsPrecision(12);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  // ── tokenizer ─────────────────────────────────────────────────────────
  List<String> _tokenize(String s) {
    final out = <String>[];
    s = s.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-').replaceAll('–', '-').replaceAll(' ', '');
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        final m = RegExp(r'^(\d+\.?\d*|\.\d+)(E[+-]?\d+)?').firstMatch(s.substring(i));
        if (m == null) throw CalcError('Syntax error');
        out.add(m.group(0)!);
        i += m.group(0)!.length;
      } else if ('+-*/^()!%'.contains(c)) {
        out.add(c);
        i++;
      } else if (c == 'π' || c == '√' || c == '∛') {
        out.add(c);
        i++;
      } else {
        final m = RegExp(r'^[a-zA-Z]+').firstMatch(s.substring(i));
        if (m == null) throw CalcError('Syntax error');
        var w = m.group(0)!.toLowerCase();
        // longest known word first (e.g. "sinh" before "sin")
        String? hit;
        for (final f in [...functions, 'pi', 'ans', 'e']..sort((a, b) => b.length.compareTo(a.length))) {
          if (w.startsWith(f)) {
            hit = f;
            break;
          }
        }
        if (hit == null) throw CalcError('Unknown: $w');
        out.add(hit == 'pi' ? 'π' : hit);
        i += hit.length;
        w = w.substring(hit.length);
      }
    }
    return out;
  }

  // ── parser ────────────────────────────────────────────────────────────
  String? get _peek => _i < _t.length ? _t[_i] : null;

  bool _startsOperand(String? t) =>
      t != null && (RegExp(r'^[0-9.]').hasMatch(t) || t == '(' || t == 'π' || t == 'e' || t == 'ans' || functions.contains(t));

  double _expr() {
    var v = _term();
    while (_peek == '+' || _peek == '-') {
      final op = _t[_i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _unary();
    while (true) {
      final p = _peek;
      if (p == '*' || p == '/') {
        _i++;
        final r = _unary();
        if (p == '/' && r == 0) throw CalcError('Cannot divide by 0');
        v = p == '*' ? v * r : v / r;
      } else if (_startsOperand(p)) {
        v *= _unary(); // implicit multiplication: 2π, 3(4), 2sin30
      } else {
        return v;
      }
    }
  }

  double _unary() {
    if (_peek == '-') {
      _i++;
      return -_unary();
    }
    if (_peek == '+') {
      _i++;
      return _unary();
    }
    return _power();
  }

  double _power() {
    final base = _postfix();
    if (_peek == '^') {
      _i++;
      final exp = _unary(); // right-associative: 2^3^2 = 2^9
      final r = math.pow(base, exp).toDouble();
      if (r.isNaN) throw CalcError('Math error');
      return r;
    }
    return base;
  }

  double _postfix() {
    var v = _primary();
    while (_peek == '!' || _peek == '%') {
      if (_t[_i++] == '!') {
        if (v < 0 || v != v.roundToDouble() || v > 170) throw CalcError('Math error');
        var f = 1.0;
        for (var k = 2; k <= v; k++) {
          f *= k;
        }
        v = f;
      } else {
        v = v / 100;
      }
    }
    return v;
  }

  double _primary() {
    final t = _peek;
    if (t == null) throw CalcError('Incomplete');
    _i++;
    if (t == '(') {
      final v = _expr();
      if (_peek != ')') {
        if (_peek == null) return v; // allow a missing final ")"
        throw CalcError('Syntax error');
      }
      _i++;
      return v;
    }
    if (t == 'π') return math.pi;
    if (t == 'e') return math.e;
    if (t == 'ans') return ans;
    if (functions.contains(t)) return _fn(t, _unary());
    final n = double.tryParse(t.replaceAll('E', 'e'));
    if (n == null) throw CalcError('Syntax error');
    return n;
  }

  double _fn(String f, double x) {
    final toRad = radians ? 1.0 : math.pi / 180;
    final fromRad = radians ? 1.0 : 180 / math.pi;
    double r;
    switch (f) {
      case 'sin':
        r = math.sin(x * toRad);
      case 'cos':
        r = math.cos(x * toRad);
      case 'tan':
        final c = math.cos(x * toRad);
        if (c.abs() < 1e-12) throw CalcError('Math error');
        r = math.tan(x * toRad);
      case 'asin':
        if (x.abs() > 1) throw CalcError('Math error');
        r = math.asin(x) * fromRad;
      case 'acos':
        if (x.abs() > 1) throw CalcError('Math error');
        r = math.acos(x) * fromRad;
      case 'atan':
        r = math.atan(x) * fromRad;
      case 'sinh':
        r = (math.exp(x) - math.exp(-x)) / 2;
      case 'cosh':
        r = (math.exp(x) + math.exp(-x)) / 2;
      case 'tanh':
        r = (math.exp(2 * x) - 1) / (math.exp(2 * x) + 1);
      case 'log':
        if (x <= 0) throw CalcError('Math error');
        r = math.log(x) / math.ln10;
      case 'ln':
        if (x <= 0) throw CalcError('Math error');
        r = math.log(x);
      case 'sqrt' || '√':
        if (x < 0) throw CalcError('Math error');
        r = math.sqrt(x);
      case 'cbrt' || '∛':
        r = x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();
      case 'abs':
        r = x.abs();
      case 'exp':
        r = math.exp(x);
      default:
        throw CalcError('Unknown function');
    }
    return r;
  }
}
