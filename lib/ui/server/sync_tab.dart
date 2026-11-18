import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';

/// Upload finished attempts to the portal.
class SyncTab extends StatefulWidget {
  const SyncTab({super.key});
  @override
  State<SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<SyncTab> {
  bool _busy = false;
  double? _progress;
  String? _last;

  Future<void> _sync() async {
    final s = Services.I;
    if (s.portal() == null) return toast(context, 'Connect to the portal first (Portal tab).', error: true);
    if (s.syncing) return toast(context, 'A sync is already running.');
    setState(() {
      _busy = true;
      _progress = 0;
      _last = null;
    });
    final res = await s.runSync(onProgress: (d, t) {
      if (mounted) setState(() => _progress = t == 0 ? null : d / t);
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _last = res?.toString();
    });
    if (res != null) toast(context, res.toString(), error: res.error != null);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final c = s.sync.counts();
    final total = c['submitted']!;
    final done = c['synced']! + c['conflict']! + c['rejected']!;
    final db = s.db.db;
    final problems = db.select('''SELECT a.*, s.firstname, s.lastname, s.admission_no, e.title FROM attempts a
        JOIN students s ON s.user_id = a.user_id JOIN exams e ON e.id = a.exam_id
        WHERE a.sync_status IN ('conflict','rejected','error') ORDER BY a.sync_status, s.lastname''');
    final log = db.select('SELECT * FROM sync_log ORDER BY id DESC LIMIT 15');

    return ListView(padding: const EdgeInsets.all(24), children: [
      const SectionTitle('Upload results to the portal'),
      Row(children: [
        Expanded(child: StatTile('Finished attempts', '$total', icon: Icons.assignment_turned_in)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Uploaded', '${c['synced']}', icon: Icons.cloud_done, color: okGreen)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Waiting to upload', '${c['pending']! + c['error']!}', icon: Icons.cloud_queue, color: warnAmber)),
        const SizedBox(width: 12),
        Expanded(child: StatTile('Need attention', '${c['conflict']! + c['rejected']!}', icon: Icons.report_problem, color: badRed)),
      ]),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(total == 0 ? 'Nothing to upload yet.' : 'Synchronisation progress: ${(done * 100 / total).toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _busy ? _progress : (total == 0 ? 0 : done / total), minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 16),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _sync,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload),
                label: Text(_busy ? 'Uploading…' : 'Sync now'),
              ),
              const SizedBox(width: 12),
              if (c['in_progress']! > 0) Text('${c['in_progress']} student(s) still writing — their attempts upload after they submit.',
                  style: const TextStyle(color: Colors.black54)),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.autoSync,
              onChanged: (v) => setState(() => s.autoSync = v),
              title: const Text('Upload automatically'),
              subtitle: Text('Every 5 minutes this computer tries to upload finished attempts, so results go up as soon as internet is back.'
                  '${s.lastAutoSync != null ? '\nLast automatic upload: ${s.lastAutoSync}' : ''}'),
            ),
            const Text('Safe to press more than once: the portal recognises attempts it already has and never creates duplicates. '
                'Only submitted attempts are uploaded. The portal marks them again with its own copy of the questions.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            if (_last != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_last!)),
          ]),
        ),
      ),
      if (problems.isNotEmpty) ...[
        const SizedBox(height: 24),
        const SectionTitle('Need attention'),
        Card(
          child: Column(children: [
            for (final p in problems)
              ListTile(
                leading: Icon(p['sync_status'] == 'conflict' ? Icons.call_split : (p['sync_status'] == 'error' ? Icons.refresh : Icons.block),
                    color: p['sync_status'] == 'error' ? warnAmber : badRed),
                title: Text('${p['lastname']} ${p['firstname']} (${p['admission_no']}) — ${p['title']}'),
                subtitle: Text(switch (p['sync_status']) {
                  'conflict' => 'Conflict: ${p['sync_message'] ?? 'the student already had an attempt online'}. Review it on the portal (Offline CBT page): keep the existing attempt or use this one.',
                  'rejected' => 'Rejected by the portal: ${p['sync_message'] ?? ''}',
                  _ => 'Upload failed, will retry: ${p['sync_message'] ?? ''}',
                }),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 24),
      const SectionTitle('Sync history'),
      Card(
        child: log.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('No sync yet.'))
            : Column(children: [
                for (final l in log)
                  ListTile(
                    dense: true,
                    leading: Icon(l['message'] == null ? Icons.check : Icons.error_outline, color: l['message'] == null ? okGreen : badRed),
                    title: Text(l['message'] as String? ??
                        'Sent ${l['sent']}: ${l['synced']} uploaded, ${l['conflicts']} conflict(s), ${l['rejected']} rejected, ${l['errors']} to retry'),
                    subtitle: Text('${DateTime.tryParse('${l['at']}')?.toLocal().toString().substring(0, 16) ?? l['at']}'),
                  ),
              ]),
      ),
    ]);
  }
}
