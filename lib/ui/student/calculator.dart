import 'package:flutter/material.dart';

import '../common/theme.dart';

/// Basic calculator (like a simple desk calculator: works left to right).
Future<void> showCalculator(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const Dialog(child: SizedBox(width: 320, child: _Calc())));

class _Calc extends StatefulWidget {
  const _Calc();
  @override
  State<_Calc> createState() => _CalcState();
}

class _CalcState extends State<_Calc> {
  String _display = '0';
  double? _acc;
  String? _op;
  bool _fresh = true;
  String _history = '';

  String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(12);
    if (s.contains('.') && !s.contains('e')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  double get _cur => double.tryParse(_display) ?? 0;

  void _digit(String d) => setState(() {
        if (_fresh || _display == '0' || _display == 'Error') {
          _display = d == '.' ? '0.' : d;
          _fresh = false;
        } else if (!(d == '.' && _display.contains('.')) && _display.length < 16) {
          _display += d;
        }
      });

  double _apply(double a, String op, double b) => switch (op) {
        '+' => a + b,
        '−' => a - b,
        '×' => a * b,
        '÷' => b == 0 ? double.nan : a / b,
        _ => b,
      };

  void _operator(String op) => setState(() {
        if (_acc != null && _op != null && !_fresh) {
          _acc = _apply(_acc!, _op!, _cur);
          _display = _fmt(_acc!);
        } else {
          _acc = _cur;
        }
        _op = op;
        _history = '${_fmt(_acc!)} $op';
        _fresh = true;
      });

  void _equals() => setState(() {
        if (_acc == null || _op == null) return;
        final r = _apply(_acc!, _op!, _cur);
        _history = '${_fmt(_acc!)} $_op ${_display} =';
        _display = _fmt(r);
        _acc = null;
        _op = null;
        _fresh = true;
      });

  void _special(String k) => setState(() {
        switch (k) {
          case 'C':
            _display = '0';
            _acc = null;
            _op = null;
            _history = '';
            _fresh = true;
          case '⌫':
            _display = _display.length <= 1 || _fresh ? '0' : _display.substring(0, _display.length - 1);
          case '√':
            _display = _fmt(_cur < 0 ? double.nan : _sqrt(_cur));
            _fresh = true;
          case '%':
            _display = _fmt(_acc != null ? _acc! * _cur / 100 : _cur / 100);
            _fresh = true;
          case '±':
            _display = _fmt(-_cur);
        }
      });

  static double _sqrt(double v) {
    if (v == 0) return 0;
    var x = v;
    for (var i = 0; i < 60; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  Widget _key(String label, {Color? bg, Color fg = navy, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(height: 52, child: Center(child: Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: fg)))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['±', '0', '.', '='],
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('Calculator', style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
          const Spacer(),
          TextButton(onPressed: () => _special('√'), child: const Text('√')),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_history, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            FittedBox(child: Text(_display, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 8),
        for (final r in rows)
          Row(children: [
            for (final k in r)
              Expanded(
                child: _key(
                  k,
                  bg: k == '=' ? teal : ('÷×−+'.contains(k) ? const Color(0xFFE6F4F1) : null),
                  fg: k == '=' ? Colors.white : navy,
                  onTap: () {
                    if (RegExp(r'^[0-9.]$').hasMatch(k)) {
                      _digit(k);
                    } else if ('÷×−+'.contains(k)) {
                      _operator(k);
                    } else if (k == '=') {
                      _equals();
                    } else {
                      _special(k);
                    }
                  },
                ),
              ),
          ]),
      ]),
    );
  }
}
