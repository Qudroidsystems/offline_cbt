import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'exam_page.dart';

class ExamListPage extends StatefulWidget {
  const ExamListPage({super.key, required this.client, required this.login});
  final ServerClient client;
  final Map<String, dynamic> login;
  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<ExamListPage> {
  late List<Map<String, dynamic>> _exams = (widget.login['exams'] as List).cast<Map<String, dynamic>>();
  bool _busy = false;
  String? _err;

  Map<String, dynamic> get _student => widget.login['student'] as Map<String, dynamic>;

  Future<void> _refresh() async {
    try {
      final e = await widget.client.exams();
      if (mounted) setState(() {
        _exams = e;
        _err = null;
      });
    } on ServerError catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  Future<void> _open(Map<String, dynamic> e) async {
    final resuming = e['state'] == 'in_progress';
    if (!resuming) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${e['title']}'),
          content: Text('${e['question_count']} questions • ${e['duration']} minutes.\n\n'
              'The timer starts as soon as you begin and keeps running even if you leave. '
              'Your answers are saved automatically.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start exam')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final data = await widget.client.start(e['id'] as int);
      if (!mounted) return;
      final session = ExamSession(cdb: Services.I.db, client: widget.client, startData: data, studentJson: _student);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamPage(session: session, student: _student)));
      await _refresh();
    } on ServerError catch (err) {
      if (mounted) toast(context, err.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _logout() async {
    await widget.client.logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _logout();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('${_student['name']}  •  ${_student['admission_no']}  •  ${_student['class_name'] ?? ''}'),
          actions: [
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            TextButton.icon(onPressed: _logout, icon: const Icon(Icons.logout, color: Colors.white), label: const Text('Log out', style: TextStyle(color: Colors.white))),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(28), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Avatar(photo: _student['photo'] as String?, size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_student['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: navy)),
                    Text('${_student['admission_no']} • ${_student['class_name'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 4),
                    const Text('Not you? Log out now and tell the invigilator.', style: TextStyle(fontSize: 12, color: badRed)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Your exams', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: navy)),
          const SizedBox(height: 12),
          if (_err != null) Text(_err!, style: const TextStyle(color: badRed)),
          if (_busy) const LinearProgressIndicator(),
          if (_exams.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No exams for you on this server.'))),
          for (final e in _exams)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Icon(_icon(e['state'] as String), color: _color(e['state'] as String), size: 32),
                  title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e['subject'] ?? ''} • ${e['question_count']} questions • ${e['duration']} min\n${_label(e)}'),
                  isThreeLine: true,
                  trailing: switch (e['state']) {
                    'available' => FilledButton(onPressed: _busy ? null : () => _open(e), child: const Text('Start')),
                    'in_progress' => FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: warnAmber),
                        onPressed: _busy ? null : () => _open(e),
                        child: const Text('Continue')),
                    _ => null,
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }

  String _label(Map<String, dynamic> e) => switch (e['state']) {
        'available' => e['practice'] == true ? 'Practice — not recorded. Try the exam screen here.' : (e['paused'] == true ? 'Paused by the invigilator' : 'Ready to start'),
        'in_progress' => 'In progress — ${fmtDuration(Duration(seconds: (e['remaining_seconds'] as int?) ?? 0))} left',
        'submitted' => 'Submitted ✓',
        'done_online' => 'Already taken online',
        _ => 'Not open yet — wait for the invigilator',
      };

  IconData _icon(String s) => switch (s) {
        'available' => Icons.play_circle,
        'in_progress' => Icons.timelapse,
        'submitted' || 'done_online' => Icons.check_circle,
        _ => Icons.lock_clock,
      };

  Color _color(String s) => switch (s) {
        'available' => teal,
        'in_progress' => warnAmber,
        'submitted' || 'done_online' => okGreen,
        _ => Colors.grey,
      };
}
