import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/theme.dart';

/// Floating calculator for the exam screen. [allowScientific] comes from the
/// exam's setting chosen by the admin (off / basic / scientific).
class CalculatorPanel extends StatefulWidget {
  const CalculatorPanel({super.key, required this.allowScientific, required this.onClose});
  final bool allowScientific;
  final VoidCallback onClose;
  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel> {
  final _calc = Calculator();
  String _expr = '';
  String? _result; // shown big after "="
  String? _error;
  bool _scientific = false;
  final _history = <String>[];
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _scientific = widget.allowScientific;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Live preview while typing (does not change Ans).
  String? get _preview {
    if (_expr.isEmpty || _result != null) return null;
    try {
      final c = Calculator(radians: _calc.radians)..ans = _calc.ans;
      final v = Calculator.format(c.evaluate(_expr));
      return v == _expr ? null : v;
    } catch (_) {
      return null;
    }
  }

  void _input(String s) => setState(() {
        _error = null;
        if (_result != null) {
          // continue from the answer with an operator, otherwise start fresh
          _expr = RegExp(r'^[+\-×÷^%!]').hasMatch(s) ? _result! : '';
          _result = null;
        }
        _expr += s;
      });

  void _key(String k) {
    switch (k) {
      case 'AC':
        setState(() {
          _expr = '';
          _result = null;
          _error = null;
        });
      case '⌫':
        setState(() {
          _result = null;
          _error = null;
          if (_expr.isEmpty) return;
          // remove a whole function name like "sin(" at once
          final m = RegExp(r'(asin|acos|atan|sinh|cosh|tanh|sin|cos|tan|log|ln|abs|Ans)\($|Ans$').firstMatch(_expr);
          _expr = m != null ? _expr.substring(0, m.start) : _expr.substring(0, _expr.length - 1);
        });
      case '=':
        _equals();
      case '±':
        setState(() {
          final base = _result ?? _expr;
          _result = null;
          _expr = base.isEmpty ? '-' : (base.startsWith('-(') && base.endsWith(')') ? base.substring(2, base.length - 1) : '-($base)');
        });
      case 'x²':
        _input('^2');
      case 'xʸ':
        _input('^');
      case 'eˣ':
        _input('e^(');
      case '10ˣ':
        _input('10^(');
      case '1/x':
        _input('1/(');
      case '√':
        _input('√(');
      case '∛':
        _input('∛(');
      case 'x!':
        _input('!');
      case 'DEG' || 'RAD':
        setState(() => _calc.radians = !_calc.radians);
      case 'sin' || 'cos' || 'tan' || 'asin' || 'acos' || 'atan' || 'log' || 'ln':
        _input('$k(');
      case 'sin⁻¹':
        _input('asin(');
      case 'cos⁻¹':
        _input('acos(');
      case 'tan⁻¹':
        _input('atan(');
      case 'Ans':
        _input('Ans');
      default:
        _input(k);
    }
  }

  void _equals() {
    if (_expr.isEmpty) return;
    try {
      final v = Calculator.format(_calc.evaluate(_expr));
      setState(() {
        _history.insert(0, '$_expr = $v');
        if (_history.length > 4) _history.removeLast();
        _result = v;
        _error = null;
      });
    } on CalcError catch (e) {
      setState(() => _error = e.message);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || e.character == '=') {
      _equals();
    } else if (k == LogicalKeyboardKey.backspace) {
      _key('⌫');
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (k == LogicalKeyboardKey.delete) {
      _key('AC');
    } else {
      final c = e.character;
      if (c == null || c.isEmpty) return KeyEventResult.handled;
      const map = {'*': '×', '/': '÷', '-': '−', 'x': '×'};
      if (RegExp(r'^[0-9.+\-*/^()%!x]$').hasMatch(c)) {
        _input(map[c] ?? c);
      } else if (_scientific) {
        const fn = {'s': 'sin(', 'c': 'cos(', 't': 'tan(', 'l': 'log(', 'n': 'ln(', 'p': 'π', 'e': 'e', 'r': '√('};
        if (fn.containsKey(c.toLowerCase())) _input(fn[c.toLowerCase()]!);
      }
    }
    return KeyEventResult.handled; // never let typing here choose exam answers
  }

  @override
  Widget build(BuildContext context) {
    final sci = _scientific;
    final preview = _preview;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Material(
          color: const Color(0xFF1C1C1E),
          elevation: 18,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            width: sci ? 560 : 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.drag_indicator, color: Colors.white38, size: 18),
                  const SizedBox(width: 4),
                  const Text('Calculator', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  if (widget.allowScientific)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Basic')),
                        ButtonSegment(value: true, label: Text('Scientific')),
                      ],
                      selected: {sci},
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2C2E),
                        foregroundColor: Colors.white70,
                        selectedBackgroundColor: const Color(0xFF636366),
                        selectedForegroundColor: Colors.white,
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onSelectionChanged: (v) => setState(() => _scientific = v.first),
                    ),
                  IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close_rounded, color: Colors.white70), tooltip: 'Close (Esc)'),
                ]),
                // display
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final h in _history.take(2).toList().reversed)
                      Text(h, style: const TextStyle(color: Colors.white30, fontSize: 13), overflow: TextOverflow.ellipsis),
                    if (sci)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_calc.radians ? 'RAD' : 'DEG', style: const TextStyle(color: warnAmber, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    Text(_result == null ? (_expr.isEmpty ? '0' : _expr) : _expr,
                        style: TextStyle(color: _result == null ? Colors.white : Colors.white54, fontSize: _result == null ? 30 : 18),
                        maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                    if (_result != null)
                      FittedBox(child: Text('= $_result', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300))),
                    if (_error != null) Text(_error!, style: const TextStyle(color: badRed, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (preview != null && _error == null)
                      Text(preview, style: const TextStyle(color: Colors.white38, fontSize: 16)),
                  ]),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (sci) ...[Expanded(flex: 3, child: _grid(_sciKeys, sci: true)), const SizedBox(width: 8)],
                  Expanded(flex: 4, child: _grid(_basicKeys)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static const _basicKeys = [
    ['AC', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['±', '0', '.', '='],
  ];

  static const _sciKeys = [
    ['(', ')', 'DEG'],
    ['sin', 'cos', 'tan'],
    ['sin⁻¹', 'cos⁻¹', 'tan⁻¹'],
    ['log', 'ln', 'x!'],
    ['x²', 'xʸ', '√'],
    ['10ˣ', 'eˣ', '∛'],
    ['π', 'e', 'Ans'],
  ];

  Widget _grid(List<List<String>> rows, {bool sci = false}) => Column(children: [
        for (final r in rows)
          Row(children: [
            for (final k in r) Expanded(child: _btn(k == 'DEG' && _calc.radians ? 'RAD' : k, sci: sci)),
          ]),
      ]);

  Widget _btn(String k, {bool sci = false}) {
    final isOp = '÷×−+='.contains(k) && k.length == 1;
    final isTop = k == 'AC' || k == '⌫' || k == '%' || k == '±';
    final bg = isOp ? warnAmber : (isTop ? const Color(0xFFA5A5A5) : (sci ? const Color(0xFF2C2C2E) : const Color(0xFF333333)));
    final fg = isTop ? Colors.black : Colors.white;
    return Padding(
      padding: const EdgeInsets.all(3.5),
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            _key(k == 'RAD' ? 'DEG' : k);
            _focus.requestFocus();
          },
          child: SizedBox(
            height: sci ? 38 : 48,
            child: Center(
              child: Text(k, style: TextStyle(color: fg, fontSize: sci ? 15 : (isOp ? 24 : 21), fontWeight: sci ? FontWeight.w500 : FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}
