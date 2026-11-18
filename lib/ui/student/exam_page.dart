import 'dart:async';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'calculator.dart';
import 'done_page.dart';

/// The exam itself: full screen, cannot be closed without the invigilator.
class ExamPage extends StatefulWidget {
  const ExamPage({super.key, required this.session, required this.student});
  final ExamSession session;
  final Map<String, dynamic> student;
  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WindowListener {
  ExamSession get s => widget.session;
  int _i = 0;
  final _flagged = <int>{};
  final _shortCtrls = <int, TextEditingController>{};
  Timer? _tick;
  StreamSubscription<void>? _sub;
  bool _finishing = false;
  bool _warned5 = false, _warned1 = false;
  final _focus = FocusNode();
  double _font = double.tryParse(Services.I.db.setting('font_scale') ?? '') ?? 1.0;
  final _openedAt = DateTime.now();
  bool _away = false;

  List<Map<String, dynamic>> get qs => s.questions;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    windowManager.setFullScreen(true);
    windowManager.setAlwaysOnTop(true);
    _sub = s.changes.listen((_) {
      if (!mounted) return;
      if (s.submitted && !_finishing) {
        _goDone(); // the server closed it (time up / invigilator)
      } else {
        setState(() {});
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (s.submittedLocally) WidgetsBinding.instance.addPostFrameCallback((_) => _goDone());
  }

  void _onTick() {
    if (!mounted) return;
    final rem = s.remaining;
    if (!_warned5 && rem.inSeconds <= 300 && rem.inSeconds > 60) {
      _warned5 = true;
      toast(context, '5 minutes left');
    }
    if (!_warned1 && rem.inSeconds <= 60) {
      _warned1 = true;
      toast(context, '1 minute left — your answers will be submitted automatically');
    }
    if (s.timeUp && !_finishing && !s.paused) {
      _finish(timeUp: true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    windowManager.removeListener(this);
    windowManager.setAlwaysOnTop(false);
    windowManager.setFullScreen(false);
    windowManager.setPreventClose(false);
    for (final c in _shortCtrls.values) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  /// Student left the exam window (Alt+Tab, Windows key, another program): recorded for the invigilator.
  @override
  void onWindowBlur() {
    if (_finishing || s.submitted || DateTime.now().difference(_openedAt).inSeconds < 5) return;
    _away = true;
    s.reportFocusLost();
    windowManager.focus();
  }

  @override
  void onWindowFocus() {
    if (!_away || !mounted) return;
    _away = false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: badRed,
      behavior: SnackBarBehavior.floating,
      width: 620,
      duration: const Duration(seconds: 6),
      content: Text('You left the exam window. This is recorded and shown to the invigilator '
          '(${s.focusLostCount} time${s.focusLostCount == 1 ? '' : 's'}).'),
    ));
  }

  void _setFont(double v) {
    setState(() => _font = v.clamp(0.8, 1.6));
    Services.I.db.setSetting('font_scale', _font.toStringAsFixed(2));
  }

  @override
  void onWindowClose() async {
    if (await askInvigilatorPassword(context, title: 'Exam in progress — invigilator password to close')) {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  Future<void> _finish({bool timeUp = false}) async {
    if (_finishing) return;
    _finishing = true;
    await s.submit(timeUp: timeUp);
    _goDone();
  }

  void _goDone() {
    if (!mounted) return;
    _finishing = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DonePage(session: s, student: widget.student)));
  }

  Future<void> _confirmSubmit() async {
    final unanswered = [for (var k = 0; k < qs.length; k++) if ((s.answers[qs[k]['id']] ?? '').trim().isEmpty) k + 1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit your exam?'),
        content: Text(unanswered.isEmpty
            ? 'You have answered all ${qs.length} questions. You cannot change your answers after submitting.'
            : 'You have NOT answered ${unanswered.length} question(s): ${unanswered.take(30).join(', ')}${unanswered.length > 30 ? '…' : ''}.\n\n'
                'You cannot change your answers after submitting.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  void _go(int i) => setState(() => _i = i.clamp(0, qs.length - 1));

  TextEditingController _ctrl(int qid) =>
      _shortCtrls.putIfAbsent(qid, () => TextEditingController(text: s.answers[qid] ?? ''));

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return KeyEventResult.ignored;
    final q = qs[_i];
    if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.keyN) {
      _go(_i + 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft || e.logicalKey == LogicalKeyboardKey.keyP) {
      _go(_i - 1);
      return KeyEventResult.handled;
    }
    // A, B, C, D … picks an option
    final opts = (q['options'] as List).cast<Map<String, dynamic>>();
    final label = e.logicalKey.keyLabel.toUpperCase();
    if (label.length == 1 && opts.isNotEmpty) {
      final idx = label.codeUnitAt(0) - 65;
      if (idx >= 0 && idx < opts.length) {
        setState(() => s.setAnswer(q['id'] as int, (opts[idx]['text'] as String?)?.trim() ?? ''));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final rem = s.remaining;
    final low = rem.inMinutes < 5;
    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 68,
            title: Row(children: [
              Avatar(photo: widget.student['photo'] as String?, size: 44),
              const SizedBox(width: 12),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.exam['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  Text('${widget.student['name']} • ${widget.student['admission_no']} • ${s.exam['subject'] ?? ''}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            actions: [
              IconButton(tooltip: 'Smaller text', onPressed: () => _setFont(_font - 0.1), icon: const Icon(Icons.text_decrease, color: Colors.white)),
              IconButton(tooltip: 'Bigger text', onPressed: () => _setFont(_font + 0.1), icon: const Icon(Icons.text_increase, color: Colors.white)),
              IconButton(tooltip: 'Calculator', onPressed: () => showCalculator(context), icon: const Icon(Icons.calculate_outlined, color: Colors.white)),
              const SizedBox(width: 12),
              _SaveChip(state: s.saveState),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: low ? badRed : Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.timer_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(fmtDuration(rem), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: okGreen),
                onPressed: _finishing ? null : _confirmSubmit,
                icon: const Icon(Icons.send),
                label: const Text('Submit'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Stack(children: [
            Row(children: [
              Expanded(child: _question()),
              Container(width: 300, color: Colors.white, child: _navigator()),
            ]),
            if (s.paused)
              Positioned.fill(
                child: Container(
                  color: const Color(0xEE0F172A),
                  alignment: Alignment.center,
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.pause_circle_filled, color: Colors.white, size: 96),
                    SizedBox(height: 16),
                    Text('Exam paused by the invigilator', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8),
                    Text('Your time is stopped and your answers are safe. Please wait quietly.',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _question() {
    final q = qs[_i];
    final qid = q['id'] as int;
    final type = q['type'] as String? ?? 'mcq';
    final opts = (q['options'] as List).cast<Map<String, dynamic>>();
    final ans = s.answers[qid] ?? '';
    final marks = (q['marks'] as num?) ?? 1;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(32), children: [
          Row(children: [
            Text('Question ${_i + 1} of ${qs.length}', style: const TextStyle(color: teal, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 12),
            Chip(label: Text('$marks mark${marks == 1 ? '' : 's'}'), visualDensity: VisualDensity.compact),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _flagged.contains(qid) ? _flagged.remove(qid) : _flagged.add(qid)),
              icon: Icon(_flagged.contains(qid) ? Icons.flag : Icons.outlined_flag, color: warnAmber),
              label: Text(_flagged.contains(qid) ? 'Flagged for review' : 'Flag for review'),
            ),
          ]),
          const SizedBox(height: 16),
          HtmlText(q['text'] as String?, style: TextStyle(fontSize: 20 * _font, height: 1.5, color: Colors.black87)),
          if (q['image'] != null) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerLeft, child: DataImage(q['image'] as String?, maxHeight: 320 * _font))),
          const SizedBox(height: 28),
          if (type == 'short_answer')
            TextField(
              key: ValueKey('sa$qid'),
              controller: _ctrl(qid),
              maxLength: 255,
              enabled: !s.paused,
              style: TextStyle(fontSize: 18 * _font),
              decoration: const InputDecoration(labelText: 'Type your answer', border: OutlineInputBorder()),
              onChanged: (v) => s.setAnswer(qid, v),
            )
          else
            for (var k = 0; k < opts.length; k++) _option(qid, k, opts[k], ans),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
        child: Row(children: [
          OutlinedButton.icon(onPressed: _i == 0 ? null : () => _go(_i - 1), icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
          const Spacer(),
          Text('${s.answeredCount} of ${qs.length} answered', style: const TextStyle(color: Colors.black54)),
          const Spacer(),
          if (_i < qs.length - 1)
            FilledButton.icon(onPressed: () => _go(_i + 1), icon: const Icon(Icons.chevron_right), label: const Text('Next'))
          else
            FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: okGreen), onPressed: _finishing ? null : _confirmSubmit, icon: const Icon(Icons.send), label: const Text('Review & submit')),
        ]),
      ),
    ]);
  }

  Widget _option(int qid, int k, Map<String, dynamic> o, String ans) {
    final text = ((o['text'] as String?) ?? '').trim();
    final selected = ans == text && text.isNotEmpty;
    final label = (o['label'] as String?)?.trim().isNotEmpty == true ? o['label'] as String : String.fromCharCode(65 + k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? const Color(0xFFE6F4F1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => s.setAnswer(qid, text)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? teal : const Color(0xFFE2E8F0), width: selected ? 2 : 1),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: selected ? teal : const Color(0xFFF1F5F9),
                child: Text(label, style: TextStyle(color: selected ? Colors.white : navy, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(child: HtmlText(text, style: TextStyle(fontSize: 17 * _font, color: Colors.black87))),
              if (selected) const Icon(Icons.check_circle, color: teal),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _navigator() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text('Questions', style: TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 16)),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: qs.length,
          itemBuilder: (_, k) {
            final qid = qs[k]['id'] as int;
            final answered = (s.answers[qid] ?? '').trim().isNotEmpty;
            final flagged = _flagged.contains(qid);
            final current = k == _i;
            return InkWell(
              onTap: () => _go(k),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: answered ? teal : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: current ? navy : (flagged ? warnAmber : const Color(0xFFCBD5E1)), width: current || flagged ? 3 : 1),
                ),
                child: Text('${k + 1}', style: TextStyle(color: answered ? Colors.white : navy, fontWeight: FontWeight.w700)),
              ),
            );
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 6, children: [
          _Legend(color: teal, text: 'Answered'),
          _Legend(color: Colors.white, border: Color(0xFFCBD5E1), text: 'Not answered'),
          _Legend(color: Colors.white, border: warnAmber, text: 'Flagged'),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text('Tip: press A, B, C, D to choose and ← → to move.', style: TextStyle(fontSize: 12, color: Colors.black45)),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text, this.border});
  final Color color;
  final Color? border;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3), border: Border.all(color: border ?? color, width: 2))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}

class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.state});
  final SaveState state;
  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (state) {
      SaveState.saved => (Icons.cloud_done, 'All answers saved', okGreen),
      SaveState.saving => (Icons.sync, 'Saving…', Colors.white70),
      SaveState.offline => (Icons.wifi_off, 'Server unreachable — answers kept on this computer', warnAmber),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(color: color, fontSize: 13)),
    ]);
  }
}
