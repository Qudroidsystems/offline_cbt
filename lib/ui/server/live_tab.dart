import 'dart:async';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/sounds.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../student/login_page.dart';

/// What the invigilator watches during the exam.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key});
  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  Timer? _t;
  int? _examId;
  String _q = '';
  List<String> _ips = [];
  int? _lastSubmitted, _lastFocusLost;

  /// Soft alerts for the invigilator: someone submitted / left the exam window.
  void _alerts(List<Map<String, dynamic>> all) {
    final sub = all.where((r) => r['status'] == 'submitted').length;
    final fl = all.fold<int>(0, (n, r) => n + ((r['focus_lost'] as int?) ?? 0));
    if (_lastFocusLost != null && fl > _lastFocusLost!) {
      Sounds.play(Sfx.alert);
    } else if (_lastSubmitted != null && sub > _lastSubmitted!) {
      Sounds.play(Sfx.submitted);
    }
    _lastSubmitted = sub;
    _lastFocusLost = fl;
  }

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
    localIPv4().then((v) => mounted ? setState(() => _ips = v) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _toggleServer() async {
    final s = Services.I;
    if (s.server?.running == true) {
      final inProgress = s.exams.liveAttempts().where((a) => a['status'] == 'in_progress').length;
      if (inProgress > 0) {
        final ok = await _confirm('Stop the exam server?',
            '$inProgress student(s) are writing. Their computers keep their answers and send them when the server is back on. '
            'Their clocks keep running — use "Pause all" instead if everyone must stop.');
        if (!ok) return;
      }
      await s.stopServer();
    } else {
      await s.startServer();
      if (s.serverError != null && mounted) toast(context, s.serverError!, error: true);
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(String title, String body, {String ok = 'Continue', bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                style: danger ? FilledButton.styleFrom(backgroundColor: badRed) : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _pauseToggle() async {
    final ex = Services.I.exams;
    if (ex.anyPaused) {
      ex.resumeAll();
      toast(context, 'Exams resumed — every student got back the time the pause lasted.');
    } else {
      if (!await _confirm('Pause all exams?',
          'Every student\'s clock stops and their answers are locked until you press Resume. Use this for a power cut, noise or any interruption.',
          ok: 'Pause all')) {
        return;
      }
      ex.pauseAll();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final exams = s.db.db.select('SELECT id, title, class_name, is_open, paused_at FROM exams ORDER BY id < 0, title');
    final all = s.exams.liveAttempts();
    _alerts(all);
    var rows = _examId == null ? all : all.where((r) => r['exam_id'] == _examId).toList();
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      rows = rows.where((r) => '${r['lastname']} ${r['firstname']} ${r['admission_no']} ${r['workstation']}'.toLowerCase().contains(q)).toList();
    }
    final clients = s.server?.activeClients ?? const {};
    final inProgress = rows.where((r) => r['status'] == 'in_progress').length;
    final submitted = rows.where((r) => r['status'] == 'submitted').length;
    final openExams = exams.where((e) => e['is_open'] == 1).length;
    final paused = s.exams.anyPaused;

    return ListView(padding: const EdgeInsets.all(24), children: [
      SectionTitle('Live exam', trailing: Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: s.server?.running == true
              ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LoginPage(serverUrl: 'http://127.0.0.1:${s.server!.port}', allowBack: true)))
              : null,
          icon: const Icon(Icons.person),
          label: const Text('Student screen on this computer'),
        ),
        FilledButton.icon(
          onPressed: _pauseToggle,
          style: FilledButton.styleFrom(backgroundColor: paused ? okGreen : warnAmber),
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          label: Text(paused ? 'Resume all' : 'Pause all'),
        ),
        FilledButton.icon(
          onPressed: _toggleServer,
          style: FilledButton.styleFrom(backgroundColor: s.server?.running == true ? badRed : okGreen),
          icon: Icon(s.server?.running == true ? Icons.stop : Icons.play_arrow),
          label: Text(s.server?.running == true ? 'Stop exam server' : 'Start exam server'),
        ),
      ])),
      if (s.serverError != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.serverError!, style: const TextStyle(color: badRed))),
      if (paused)
        Card(
          color: const Color(0xFFFFF7ED),
          child: ListTile(
            leading: const Icon(Icons.pause_circle, color: warnAmber, size: 36),
            title: const Text('Exams are PAUSED', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Clocks are stopped and answers locked on every student computer. Press "Resume all" to continue.'),
            trailing: FilledButton(onPressed: _pauseToggle, child: const Text('Resume all')),
          ),
        ),
      if (s.updateAvailable)
        Card(
          color: const Color(0xFFEFF6FF),
          child: ListTile(
            leading: const Icon(Icons.system_update, color: navy),
            title: Text('Offline CBT ${s.latestVersion} is available (this computer has $appVersion).'),
            subtitle: Text(s.downloadUrl?.isNotEmpty == true ? 'Download: ${s.downloadUrl}' : 'Ask your portal administrator for the new installer.'),
          ),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: StatTile('Student computers connected', '${clients.length}', icon: Icons.computer)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Writing now', '$inProgress', icon: Icons.edit_note, color: warnAmber)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Submitted', '$submitted', icon: Icons.check_circle, color: okGreen)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Exams open', '$openExams of ${exams.length}', icon: Icons.lock_open)),
      ]),
      const SizedBox(height: 16),
      if (openExams == 0 && exams.isNotEmpty)
        const Card(
          color: Color(0xFFFFF7ED),
          child: Padding(padding: EdgeInsets.all(14), child: Text('No exam is open. Go to Exams and switch an exam on when students are seated. '
              'Tip: open the Practice test first so students can try the screen.')),
        ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<int?>(
                  value: _examId,
                  decoration: const InputDecoration(labelText: 'Exam'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All exams')),
                    for (final e in exams)
                      DropdownMenuItem<int?>(
                          value: e['id'] as int,
                          child: Text('${e['title']} (${e['class_name']})${e['paused_at'] != null ? ' — paused' : ''}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _examId = v),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Find student or computer', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No student has started yet.')))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 60,
                  columns: const [
                    DataColumn(label: Text('Student')),
                    DataColumn(label: Text('Exam')),
                    DataColumn(label: Text('Computer')),
                    DataColumn(label: Text('Answered')),
                    DataColumn(label: Text('Time left')),
                    DataColumn(label: Tooltip(message: 'Times the student left the exam window (Alt+Tab, Windows key…)', child: Text('Left window'))),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Score (provisional)')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [for (final r in rows) _row(r)],
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      _computers(),
      const SizedBox(height: 24),
      _hotspotHelp(),
    ]);
  }

  DataRow _row(Map<String, dynamic> r) {
    final inProg = r['status'] == 'in_progress';
    final rem = Duration(seconds: (r['remaining_seconds'] as int?) ?? 0);
    final lastSeen = DateTime.tryParse('${r['updated_at']}');
    final quiet = inProg && r['paused_at'] == null && lastSeen != null && DateTime.now().difference(lastSeen).inMinutes >= 3;
    final fl = (r['focus_lost'] as int?) ?? 0;
    return DataRow(cells: [
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        Avatar(photo: r['photo'] as String?, size: 36),
        const SizedBox(width: 10),
        Text('${r['lastname']} ${r['firstname']}\n${r['admission_no']}', style: const TextStyle(fontSize: 13)),
      ])),
      DataCell(Text('${r['title']}')),
      DataCell(Text('${r['workstation'] ?? ''}')),
      DataCell(Text('${r['answered']} / ${r['question_count']}')),
      DataCell(Text(inProg ? '${fmtDuration(rem)}${r['paused_at'] != null ? ' (paused)' : ''}' : '—',
          style: TextStyle(color: inProg && rem.inMinutes < 5 ? badRed : null, fontWeight: FontWeight.w600))),
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: fl == 0 ? const Color(0xFFDCFCE7) : (fl < 3 ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('$fl', style: TextStyle(fontWeight: FontWeight.w700, color: fl == 0 ? okGreen : (fl < 3 ? warnAmber : badRed))),
      )),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(inProg ? Icons.edit : Icons.check_circle, size: 16, color: inProg ? warnAmber : okGreen),
        const SizedBox(width: 4),
        Text(inProg ? (quiet ? 'Writing (no activity 3+ min)' : 'Writing') : (r['submit_reason'] == 'time_up' ? 'Submitted (time up)' : 'Submitted')),
      ])),
      DataCell(Text(r['status'] == 'submitted' ? fmtScore(r['local_score'] as num?, r['local_total'] as num?) : '—')),
      DataCell(PopupMenuButton<String>(
        onSelected: (v) => _action(v, r),
        itemBuilder: (_) => [
          if (inProg) const PopupMenuItem(value: 'ext5', child: Text('Add 5 minutes')),
          if (inProg) const PopupMenuItem(value: 'ext10', child: Text('Add 10 minutes')),
          if (!inProg) const PopupMenuItem(value: 'reopen', child: Text('Reopen (10 more minutes)')),
          const PopupMenuItem(value: 'reset', child: Text('Delete attempt (student starts again)')),
        ],
      )),
    ]);
  }

  /// Readiness check: every student computer that has contacted this server.
  Widget _computers() {
    final ws = Services.I.exams.workstations();
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Student computers (${ws.length})',
          trailing: TextButton(
              onPressed: () => setState(() => Services.I.exams.forgetWorkstations()), child: const Text('Clear list'))),
      Card(
        child: ws.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No student computer has connected yet. Open Offline CBT on each one and press Connect — '
                    'they appear here with their app version, so you can check every computer before the exam.'))
            : DataTable(columns: const [
                DataColumn(label: Text('Computer')),
                DataColumn(label: Text('Address')),
                DataColumn(label: Text('App version')),
                DataColumn(label: Text('Last seen')),
                DataColumn(label: Text('Student / exam')),
              ], rows: [
                for (final w in ws)
                  () {
                    final seen = DateTime.tryParse('${w['last_seen']}');
                    final online = seen != null && now.difference(seen).inSeconds < 60;
                    final v = '${w['app_version'] ?? '?'}';
                    return DataRow(cells: [
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, size: 10, color: online ? okGreen : Colors.grey),
                        const SizedBox(width: 8),
                        Text('${w['name']}'),
                      ])),
                      DataCell(Text('${w['ip'] ?? ''}')),
                      DataCell(Text(v == appVersion ? v : '$v  ⚠ server is $appVersion',
                          style: TextStyle(color: v == appVersion ? null : badRed))),
                      DataCell(Text(seen == null ? '—' : (online ? 'now' : '${now.difference(seen).inMinutes} min ago'))),
                      DataCell(Text(w['firstname'] == null ? '—' : '${w['lastname']} ${w['firstname']}${w['title'] != null ? ' • ${w['title']}' : ''}')),
                    ]);
                  }(),
              ]),
      ),
    ]);
  }

  Widget _hotspotHelp() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.wifi_tethering, color: teal),
        title: const Text('No Wi-Fi router? Use this computer as the hotspot'),
        subtitle: Text(_ips.isEmpty
            ? 'This computer is not on any network yet.'
            : 'This computer\'s addresses: ${_ips.join(', ')}'),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Click the button below (Windows Settings → Mobile hotspot).\n'
              '2. Under "Share over", choose Wi-Fi. Note the network name and password ("Properties" → Edit to change them).\n'
              '3. Turn Mobile hotspot ON. It works without internet: if Windows asks, share any connection.\n'
              '4. Connect every student computer to that Wi-Fi network, then open Offline CBT and press Connect.\n'
              'A Windows hotspot handles about 8 computers. For more, use a Wi-Fi router (it does not need internet).',
              style: TextStyle(height: 1.6)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Services.openPath('ms-settings:network-mobilehotspot'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Mobile hotspot settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _action(String v, Map<String, dynamic> r) async {
    final s = Services.I;
    final uuid = r['uuid'] as String;
    String? err;
    switch (v) {
      case 'ext5':
        s.exams.extendTime(uuid, 5);
      case 'ext10':
        s.exams.extendTime(uuid, 10);
      case 'reopen':
        err = s.exams.reopen(uuid, 10);
      case 'reset':
        if (!await _confirm('Delete this attempt?', '${r['lastname']} ${r['firstname']} loses all answers for this exam and can start again.',
            ok: 'Delete', danger: true)) {
          return;
        }
        err = s.exams.resetAttempt(uuid);
    }
    if (!mounted) return;
    if (err != null) toast(context, err, error: true);
    setState(() {});
  }
}
