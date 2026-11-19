import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/services.dart';
import '../../app/sounds.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'calculator.dart';
import 'done_page.dart';

/// The exam itself: full screen, always on top, cannot be closed without the invigilator.
class ExamPage extends StatefulWidget {
  const ExamPage({super.key, required this.session, required this.student});
  final ExamSession session;
  final Map<String, dynamic> student;
  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WindowListener {
  ExamSession get s => widget.session;
  List<Map<String, dynamic>> get qs => s.questions;

  int _i = 0;
  final _flagged = <int>{};
  final _shortCtrls = <int, TextEditingController>{};
  Timer? _tick;
  StreamSubscription<void>? _sub;
  bool _finishing = false;
  bool _warned5 = false, _warned1 = false;
  int _lastTickSecond = -1;
  bool _wasPaused = false;
  SaveState _lastSave = SaveState.saved;
  final _focus = FocusNode();
  double _font = double.tryParse(Services.I.db.setting('font_scale') ?? '') ?? 1.0;
  final _openedAt = DateTime.now();
  bool _away = false;
  bool _calcOpen = false;
  Offset _calcPos = const Offset(-1, -1);
  late final Duration _total;

  String get _calcMode => '${s.exam['calculator'] ?? 'basic'}';

  @override
  void initState() {
    super.initState();
    Sounds.enabled = s.exam['sounds'] != false;
    final dur = Duration(minutes: (s.exam['duration'] as num?)?.toInt() ?? 0);
    _total = s.remaining > dur ? s.remaining : dur;
    _wasPaused = s.paused;
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    windowManager.setFullScreen(true);
    windowManager.setAlwaysOnTop(true);
    _sub = s.changes.listen((_) {
      if (!mounted) return;
      if (s.submitted && !_finishing) {
        _goDone(); // closed by the server (time up / invigilator)
        return;
      }
      if (s.paused != _wasPaused) {
        Sounds.play(s.paused ? Sfx.paused : Sfx.resumed);
        _wasPaused = s.paused;
      }
      if (s.saveState != _lastSave) {
        if (s.saveState == SaveState.offline) Sounds.play(Sfx.offline);
        if (_lastSave == SaveState.offline && s.saveState == SaveState.saved) Sounds.play(Sfx.online);
        _lastSave = s.saveState;
      }
      setState(() {});
    });
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
    if (s.submittedLocally) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goDone());
    } else {
      Sounds.play(Sfx.start);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final rem = s.remaining;
    if (!s.paused) {
      if (!_warned5 && rem.inSeconds <= 300 && rem.inSeconds > 60 && _total.inSeconds > 300) {
        _warned5 = true;
        Sounds.play(Sfx.warning);
        _banner('5 minutes left', warnAmber, Icons.hourglass_bottom_rounded);
      }
      if (!_warned1 && rem.inSeconds <= 60 && rem.inSeconds > 0) {
        _warned1 = true;
        Sounds.play(Sfx.urgent);
        _banner('1 minute left — your answers will be submitted automatically', badRed, Icons.timer_rounded);
      }
      if (rem.inSeconds <= 10 && rem.inSeconds > 0 && rem.inSeconds != _lastTickSecond) {
        _lastTickSecond = rem.inSeconds;
        Sounds.play(Sfx.tick);
      }
      if (s.timeUp && !_finishing) {
        Sounds.play(Sfx.timeUp);
        _finish(timeUp: true);
        return;
      }
    }
    setState(() {});
  }

  void _banner(String text, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      width: 560,
      duration: const Duration(seconds: 5),
      backgroundColor: color,
      content: Row(children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
      ]),
    ));
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

  // ── window: leaving the exam, closing ─────────────────────────────────

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
    Sounds.play(Sfx.error);
    _banner('You left the exam window. This is recorded and shown to the invigilator '
        '(${s.focusLostCount} time${s.focusLostCount == 1 ? '' : 's'}).', badRed, Icons.warning_amber_rounded);
  }

  @override
  void onWindowClose() async {
    if (await askInvigilatorPassword(context, title: 'Exam in progress — invigilator password to close')) {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  // ── actions ───────────────────────────────────────────────────────────

  void _setFont(double v) {
    setState(() => _font = v.clamp(0.8, 1.6));
    Services.I.db.setSetting('font_scale', _font.toStringAsFixed(2));
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
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => DonePage(session: s, student: widget.student),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  Future<void> _confirmSubmit() async {
    final unanswered = [for (var k = 0; k < qs.length; k++) if ((s.answers[qs[k]['id']] ?? '').trim().isEmpty) k + 1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(unanswered.isEmpty ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: unanswered.isEmpty ? okGreen : warnAmber, size: 44),
        title: const Text('Submit your exam?', textAlign: TextAlign.center),
        content: SizedBox(
          width: 420,
          child: Text(
            unanswered.isEmpty
                ? 'You have answered all ${qs.length} questions.\nYou cannot change your answers after submitting.'
                : 'You have not answered ${unanswered.length} question${unanswered.length == 1 ? '' : 's'}: '
                    '${unanswered.take(30).join(', ')}${unanswered.length > 30 ? '…' : ''}.\n\nYou cannot change your answers after submitting.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: label2, height: 1.45),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep working')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: okGreen), onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  void _go(int i) => setState(() => _i = i.clamp(0, qs.length - 1));

  void _choose(int qid, String value) {
    if (s.paused) return;
    Sounds.play(Sfx.select);
    setState(() => s.setAnswer(qid, value));
  }

  TextEditingController _ctrl(int qid) => _shortCtrls.putIfAbsent(qid, () => TextEditingController(text: s.answers[qid] ?? ''));

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
    final opts = (q['options'] as List).cast<Map<String, dynamic>>();
    final lbl = e.logicalKey.keyLabel.toUpperCase();
    if (lbl.length == 1 && opts.isNotEmpty) {
      final idx = lbl.codeUnitAt(0) - 65;
      if (idx >= 0 && idx < opts.length) {
        _choose(q['id'] as int, (opts[idx]['text'] as String?)?.trim() ?? '');
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ── layout ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: groupBg,
          body: LayoutBuilder(builder: (context, box) {
            if (_calcPos.dx < 0) _calcPos = Offset(math.max(16, box.maxWidth - 340 - (_calcMode == 'scientific' ? 240 : 0) - 330), 90);
            return Stack(children: [
              Column(children: [
                _topBar(),
                Expanded(
                  child: Row(children: [
                    Expanded(child: _questionArea()),
                    _sidePanel(),
                  ]),
                ),
              ]),
              if (_calcOpen)
                Positioned(
                  left: _calcPos.dx.clamp(0, math.max(0.0, box.maxWidth - 340)),
                  top: _calcPos.dy.clamp(0, math.max(0.0, box.maxHeight - 120)),
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(() => _calcPos += d.delta),
                    child: CalculatorPanel(
                      allowScientific: _calcMode == 'scientific',
                      onClose: () {
                        setState(() => _calcOpen = false);
                        _focus.requestFocus();
                      },
                    ),
                  ),
                ),
              if (s.paused) _pausedOverlay(),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _topBar() {
    final rem = s.remaining;
    final tc = s.paused ? label2 : timeColor(rem, _total);
    final answered = s.answeredCount;
    return Container(
      decoration: const BoxDecoration(color: Color(0xF7FBFBFD), border: Border(bottom: BorderSide(color: separator, width: 0.5))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(children: [
        Row(children: [
          SchoolBrand.cached(subtitle: '${s.exam['title']}', size: 46),
          const SizedBox(width: 24),
          const Spacer(),
          _SaveStatus(state: s.saveState),
          const SizedBox(width: 14),
          _toolButton(Icons.text_decrease_rounded, 'Smaller text', () => _setFont(_font - 0.1)),
          _toolButton(Icons.text_increase_rounded, 'Bigger text', () => _setFont(_font + 0.1)),
          if (_calcMode != 'off')
            _toolButton(Icons.calculate_rounded, 'Calculator', () => setState(() => _calcOpen = !_calcOpen), active: _calcOpen),
          const SizedBox(width: 12),
          // compact timer pill (the big ring is in the side panel)
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: tc.withAlpha(26), borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Icon(s.paused ? Icons.pause_rounded : Icons.timer_outlined, size: 18, color: tc),
              const SizedBox(width: 6),
              Text(fmtDuration(rem),
                  style: TextStyle(color: tc, fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: okGreen),
            onPressed: _finishing ? null : _confirmSubmit,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Submit'),
          ),
        ]),
        const SizedBox(height: 10),
        // overall progress
        Row(children: [
          Text('$answered of ${qs.length} answered', style: const TextStyle(fontSize: 12, color: label2, fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: qs.isEmpty ? 0 : answered / qs.length, minHeight: 5, color: appleBlue),
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ]),
    );
  }

  Widget _toolButton(IconData icon, String tip, VoidCallback onTap, {bool active = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Tooltip(
          message: tip,
          child: Material(
            color: active ? appleBlue : fill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, size: 20, color: active ? Colors.white : label)),
            ),
          ),
        ),
      );

  Widget _questionArea() {
    final q = qs[_i];
    final qid = q['id'] as int;
    final type = q['type'] as String? ?? 'mcq';
    final opts = (q['options'] as List).cast<Map<String, dynamic>>();
    final ans = s.answers[qid] ?? '';
    final marks = (q['marks'] as num?) ?? 1;
    final flagged = _flagged.contains(qid);
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('Question ${_i + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: appleBlue)),
                  Text('  of ${qs.length}', style: const TextStyle(fontSize: 15, color: label2)),
                  const SizedBox(width: 12),
                  Pill('$marks mark${marks == 1 ? '' : 's'}', color: label2),
                  if (type == 'short_answer') ...[const SizedBox(width: 8), const Pill('Type your answer', color: appleBlue)],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => flagged ? _flagged.remove(qid) : _flagged.add(qid)),
                    style: TextButton.styleFrom(foregroundColor: flagged ? warnAmber : label2),
                    icon: Icon(flagged ? Icons.flag_rounded : Icons.outlined_flag_rounded),
                    label: Text(flagged ? 'Flagged for review' : 'Flag for review'),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: appleShadow),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    HtmlText(q['text'] as String?, style: TextStyle(fontSize: 21 * _font, height: 1.5, color: label, fontWeight: FontWeight.w500)),
                    if (q['image'] != null)
                      Padding(padding: const EdgeInsets.only(top: 18), child: DataImage(q['image'] as String?, maxHeight: 320 * _font)),
                  ]),
                ),
                const SizedBox(height: 18),
                if (type == 'short_answer')
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: appleShadow),
                    child: TextField(
                      key: ValueKey('sa$qid'),
                      controller: _ctrl(qid),
                      enabled: !s.paused,
                      maxLength: 255,
                      style: TextStyle(fontSize: 19 * _font),
                      decoration: const InputDecoration(hintText: 'Type your answer here'),
                      onChanged: (v) => s.setAnswer(qid, v),
                    ),
                  )
                else
                  for (var k = 0; k < opts.length; k++) _option(qid, k, opts[k], ans),
              ]),
            ),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: const BoxDecoration(color: Color(0xF7FBFBFD), border: Border(top: BorderSide(color: separator, width: 0.5))),
        child: Row(children: [
          OutlinedButton.icon(onPressed: _i == 0 ? null : () => _go(_i - 1), icon: const Icon(Icons.chevron_left_rounded), label: const Text('Previous')),
          const Spacer(),
          const Text('A–D to choose  •  ← → to move', style: TextStyle(color: label2, fontSize: 12)),
          const Spacer(),
          if (_i < qs.length - 1)
            FilledButton.icon(onPressed: () => _go(_i + 1), icon: const Icon(Icons.chevron_right_rounded), label: const Text('Next'))
          else
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: okGreen),
                onPressed: _finishing ? null : _confirmSubmit,
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Review & submit')),
        ]),
      ),
    ]);
  }

  Widget _option(int qid, int k, Map<String, dynamic> o, String ans) {
    final text = ((o['text'] as String?) ?? '').trim();
    final selected = ans == text && text.isNotEmpty;
    final letter = (o['label'] as String?)?.trim().isNotEmpty == true ? o['label'] as String : String.fromCharCode(65 + k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? appleBlue : Colors.transparent, width: 2),
          boxShadow: selected ? const [] : appleShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _choose(qid, text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: selected ? appleBlue : const Color(0xFFF2F2F7), shape: BoxShape.circle),
                  child: Text(letter, style: TextStyle(color: selected ? Colors.white : label, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                const SizedBox(width: 16),
                Expanded(child: HtmlText(text, style: TextStyle(fontSize: 18 * _font, color: label, height: 1.4))),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: selected ? 1 : 0,
                  child: const Icon(Icons.check_circle_rounded, color: appleBlue, size: 26),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidePanel() {
    final st = widget.student;
    return Container(
      width: 320,
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: separator, width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        Center(child: TimerRing(remaining: s.remaining, total: _total, paused: s.paused, size: 150)),
        const SizedBox(height: 18),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF7F7FA), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Avatar(photo: st['photo'] as String?, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${st['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis),
                Text('${st['admission_no']} • ${s.exam['subject'] ?? ''}', style: const TextStyle(color: label2, fontSize: 12), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text('QUESTIONS', style: TextStyle(fontWeight: FontWeight.w700, color: label2, fontSize: 12, letterSpacing: 1)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: qs.length,
            itemBuilder: (_, k) {
              final qid = qs[k]['id'] as int;
              final answered = (s.answers[qid] ?? '').trim().isNotEmpty;
              final flagged = _flagged.contains(qid);
              final current = k == _i;
              return InkWell(
                onTap: () => _go(k),
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: answered ? appleBlue : const Color(0xFFF2F2F7),
                    shape: BoxShape.circle,
                    border: Border.all(color: current ? label : (flagged ? warnAmber : Colors.transparent), width: current || flagged ? 2.5 : 0),
                  ),
                  child: Text('${k + 1}', style: TextStyle(color: answered ? Colors.white : label, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            _Legend(color: appleBlue, text: 'Answered'),
            _Legend(color: Color(0xFFF2F2F7), text: 'Not answered'),
            _Legend(color: Colors.white, border: warnAmber, text: 'Flagged'),
          ]),
        ),
      ]),
    );
  }

  Widget _pausedOverlay() => Positioned.fill(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: const Color(0x66F2F2F7),
              alignment: Alignment.center,
              child: Container(
                width: 460,
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: appleShadow),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(color: Color(0x1FFF9500), shape: BoxShape.circle),
                    child: const Icon(Icons.pause_rounded, color: warnAmber, size: 44),
                  ),
                  const SizedBox(height: 18),
                  const Text('Exam paused', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('The invigilator has paused the exam.\nYour time is stopped and your answers are safe.',
                      textAlign: TextAlign.center, style: TextStyle(color: label2, height: 1.5, fontSize: 15)),
                  const SizedBox(height: 18),
                  Pill('${fmtDuration(s.remaining)} left when you continue', color: label2, icon: Icons.timer_outlined),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text, this.border});
  final Color color;
  final Color? border;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: border ?? color, width: 2))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: label2)),
      ]);
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state});
  final SaveState state;
  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (state) {
      SaveState.saved => (Icons.check_circle_rounded, 'All answers saved', okGreen),
      SaveState.saving => (Icons.sync_rounded, 'Saving…', label2),
      SaveState.offline => (Icons.wifi_off_rounded, 'Offline — answers kept on this computer', warnAmber),
    };
    return Pill(text, color: color, icon: icon);
  }
}
