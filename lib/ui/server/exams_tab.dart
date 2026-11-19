import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';

class ExamsTab extends StatefulWidget {
  const ExamsTab({super.key});
  @override
  State<ExamsTab> createState() => _ExamsTabState();
}

class _ExamsTabState extends State<ExamsTab> {
  // portal list
  bool _loading = false;
  String? _portalError;
  List<Map<String, dynamic>> _remote = [];
  List<Map<String, dynamic>> _sessions = [], _terms = [];
  int? _sessionId, _termId;
  final _search = TextEditingController();
  final _picked = <int>{};
  bool _downloading = false;

  List<Map<String, Object?>> _local() => Services.I.db.db.select('''
      SELECT e.*, (SELECT COUNT(*) FROM student_exams se WHERE se.exam_id = e.id) AS students,
             (SELECT COUNT(*) FROM attempts a WHERE a.exam_id = e.id) AS attempts,
             (SELECT COUNT(*) FROM attempts a WHERE a.exam_id = e.id AND a.status = 'submitted') AS submitted
      FROM exams e ORDER BY e.id < 0, e.title''').toList();

  Future<void> _loadRemote() async {
    final portal = Services.I.portal();
    if (portal == null) return setState(() => _portalError = 'Connect to the portal first (Portal tab).');
    setState(() {
      _loading = true;
      _portalError = null;
    });
    try {
      final r = await portal.exams(sessionId: _sessionId, termId: _termId, search: _search.text.trim());
      _remote = (r['exams'] as List).cast<Map<String, dynamic>>();
      _sessions = ((r['sessions'] as List?) ?? []).cast<Map<String, dynamic>>();
      _terms = ((r['terms'] as List?) ?? []).cast<Map<String, dynamic>>();
      _sessionId ??= (r['session'] as Map?)?['id'] as int?;
      _termId ??= (r['term'] as Map?)?['id'] as int?;
    } catch (e) {
      _portalError = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download() async {
    final portal = Services.I.portal();
    if (portal == null || _picked.isEmpty) return;
    setState(() => _downloading = true);
    try {
      final pkg = await portal.package(_picked.toList(), includePasswords: Services.I.loginMode != 'pin');
      final res = Services.I.store.importPackage(pkg);
      Services.I.server?.schoolName = Services.I.schoolName;
      Services.I.announcer?.school = Services.I.schoolName;
      Services.I.backup();
      if (!mounted) return;
      _picked.clear();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exams downloaded'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${res.examsSaved.length} exam(s) and ${res.students} student(s) saved on this computer.'),
            if (res.examsKept.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Already running here, so their questions were NOT changed:', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final k in res.examsKept) Text('• $k'),
            ],
            const SizedBox(height: 10),
            const Text('Open an exam (switch on the left) when students are ready to start.'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _downloading = false);
  }

  @override
  void initState() {
    super.initState();
    if (Services.I.portal() != null) _loadRemote();
  }

  @override
  Widget build(BuildContext context) {
    final local = _local();
    return ListView(padding: const EdgeInsets.all(24), children: [
      SectionTitle('Exams on this computer (${local.length})'),
      if (local.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No exams yet. Download them from the portal below while you have internet.')))
      else
        Card(
          child: Column(children: [
            for (final e in local) _localRow(e),
          ]),
        ),
      const SizedBox(height: 28),
      SectionTitle('Download from the portal', trailing: IconButton(onPressed: _loading ? null : _loadRemote, icon: const Icon(Icons.refresh), tooltip: 'Reload')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _sessionId,
                  decoration: const InputDecoration(labelText: 'Session'),
                  items: [for (final s in _sessions) DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}'))],
                  onChanged: (v) => setState(() => _sessionId = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _termId,
                  decoration: const InputDecoration(labelText: 'Term'),
                  items: [for (final t in _terms) DropdownMenuItem(value: t['id'] as int, child: Text('${t['name']}'))],
                  onChanged: (v) => setState(() => _termId = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Search exam, subject or class', prefixIcon: Icon(Icons.search)),
                  onSubmitted: (_) => _loadRemote(),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _loading ? null : _loadRemote, child: const Text('Show')),
            ]),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_portalError != null) Padding(padding: const EdgeInsets.all(8), child: Text(_portalError!, style: const TextStyle(color: badRed))),
            if (!_loading && _portalError == null && _remote.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No exams found for this term.')),
            if (_remote.isNotEmpty)
              Row(children: [
                Checkbox(
                  value: _picked.length == _remote.length ? true : (_picked.isEmpty ? false : null),
                  tristate: true,
                  onChanged: (_) => setState(() {
                    if (_picked.length == _remote.length) {
                      _picked.clear();
                    } else {
                      _picked.addAll(_remote.map((e) => e['id'] as int));
                    }
                  }),
                ),
                Text('Select all (${_remote.length})'),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _picked.isEmpty || _downloading ? null : _download,
                  icon: _downloading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  label: Text('Download ${_picked.length} exam(s)'),
                ),
              ]),
            for (final e in _remote)
              CheckboxListTile(
                value: _picked.contains(e['id']),
                onChanged: (v) => setState(() => v == true ? _picked.add(e['id'] as int) : _picked.remove(e['id'])),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${e['title']}'),
                subtitle: Text('${e['class_name'] ?? ''} • ${e['subject_name'] ?? ''} • ${e['questions_count'] ?? 0} questions • ${e['duration']} min'
                    '${e['is_published'] == true || e['is_published'] == 1 ? '' : ' • not published'}'),
                secondary: local.any((l) => l['id'] == e['id']) ? const Chip(label: Text('On this computer')) : null,
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _localRow(Map<String, Object?> e) {
    final open = e['is_open'] == 1;
    return ListTile(
      leading: Switch(
        value: open,
        onChanged: (v) => setState(() => Services.I.exams.setExamOpen(e['id'] as int, v)),
      ),
      title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${(e['id'] as int) < 0 ? 'Not recorded or uploaded — lets students learn the exam screen • ' : ''}'
          '${e['class_name']} • ${e['subject']} • ${e['question_count']} questions • ${e['duration']} min • '
          '${e['students']} students • ${e['submitted']}/${e['attempts']} submitted\n'
          '${open ? 'OPEN — students can start' : 'Closed — students cannot start yet'}'),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: 'Calculator on the student\'s exam screen',
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value: '${e['calculator'] ?? 'basic'}',
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(fontSize: 13, color: label),
              items: const [
                DropdownMenuItem(value: 'off', child: Text('Calculator: Off')),
                DropdownMenuItem(value: 'basic', child: Text('Calculator: Basic')),
                DropdownMenuItem(value: 'scientific', child: Text('Calculator: Scientific')),
              ],
              onChanged: (v) => setState(() => Services.I.exams.setCalculator(e['id'] as int, v ?? 'basic')),
            ),
          ),
        ),
        if ((e['id'] as int) > 0)
          Tooltip(
            message: 'Each student gets the questions and options in a different order',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Shuffle', style: TextStyle(fontSize: 12)),
              Switch(value: e['shuffle'] == 1, onChanged: (v) => setState(() => Services.I.exams.setShuffle(e['id'] as int, v))),
            ]),
          ),
        Tooltip(
          message: 'Show the score to the student after they submit',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Show score', style: TextStyle(fontSize: 12)),
            Switch(value: e['show_score'] == 1, onChanged: (v) => setState(() => Services.I.exams.setShowScore(e['id'] as int, v))),
          ]),
        ),
        IconButton(
          tooltip: 'Results report (Excel + printable)',
          icon: const Icon(Icons.summarize_outlined),
          onPressed: () async {
            final files = Services.I.exportResults(e['id'] as int);
            await Services.openPath(files[1]); // printable page in the browser
            if (mounted) toast(context, 'Saved ${files[0]} (Excel) and the printable page.');
          },
        ),
        if ((e['id'] as int) < 0)
          IconButton(
            tooltip: 'Clear all practice attempts',
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              final n = Services.I.exams.resetPractice();
              toast(context, 'Cleared $n practice attempt(s).');
              setState(() {});
            },
          )
        else
        IconButton(
          tooltip: 'Remove from this computer',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove exam?'),
                content: Text('Remove "${htmlToPlain(e['title'] as String?)}" and its attempts from this computer? Attempts must be uploaded first.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                ],
              ),
            );
            if (ok != true) return;
            final err = Services.I.store.deleteExam(e['id'] as int);
            if (!mounted) return;
            if (err != null) toast(context, err, error: true);
            setState(() {});
          },
        ),
      ]),
    );
  }
}
