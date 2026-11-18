import 'db.dart';
import 'portal_client.dart';

class SyncSummary {
  int sent = 0, synced = 0, conflicts = 0, rejected = 0, errors = 0;
  String? error;
  @override
  String toString() => error ?? 'Sent $sent: $synced uploaded, $conflicts conflict(s), $rejected rejected, $errors to retry.';
}

/// Uploads finished attempts to the portal. Safe to run any number of times:
/// every attempt has a UUID and the portal ignores ones it already has.
class SyncService {
  SyncService(this.cdb);
  final CbtDb cdb;
  static const batchSize = 50;

  int pendingCount() => cdb.db.select("SELECT COUNT(*) n FROM attempts WHERE exam_id > 0 AND status = 'submitted' AND sync_status IN ('pending','error')").first['n'] as int;

  Map<String, int> counts() {
    final out = <String, int>{'in_progress': 0, 'submitted': 0, 'pending': 0, 'synced': 0, 'conflict': 0, 'rejected': 0, 'error': 0};
    for (final r in cdb.db.select("SELECT status, sync_status, COUNT(*) n FROM attempts WHERE exam_id > 0 GROUP BY status, sync_status")) {
      final n = r['n'] as int;
      if (r['status'] == 'in_progress') {
        out['in_progress'] = out['in_progress']! + n;
      } else {
        out['submitted'] = out['submitted']! + n;
        final k = r['sync_status'] as String;
        out[k] = (out[k] ?? 0) + n;
      }
    }
    return out;
  }

  /// Every submitted attempt not yet accepted by the portal, with an answer
  /// entry for EVERY question (blank if unanswered) so the portal's total
  /// marks match an online sitting.
  List<Map<String, dynamic>> _payloads(int limit) {
    final db = cdb.db;
    final rows = db.select('''SELECT * FROM attempts WHERE exam_id > 0 AND status = 'submitted' AND sync_status IN ('pending','error')
                              ORDER BY submitted_at LIMIT ?''', [limit]);
    return [
      for (final a in rows)
        {
          'attempt_uuid': a['uuid'],
          'package_uuid': a['package_uuid'],
          'exam_id': a['exam_id'],
          'user_id': a['user_id'],
          'started_at': _iso(a['started_at'] as String?),
          'submitted_at': _iso(a['submitted_at'] as String?),
          'duration_seconds': _dur(a['started_at'] as String?, a['submitted_at'] as String?),
          'workstation': a['workstation'],
          'focus_lost': a['focus_lost'] ?? 0,
          'answers': [
            for (final q in db.select('''SELECT q.id, x.answer FROM questions q
                                         LEFT JOIN answers x ON x.question_id = q.id AND x.attempt_uuid = ?
                                         WHERE q.exam_id = ? ORDER BY q.ord, q.id''', [a['uuid'], a['exam_id']]))
              {'question_id': q['id'], 'answer': q['answer'] ?? ''}
          ],
        }
    ];
  }

  Future<SyncSummary> syncAll(PortalClient portal, {void Function(int done, int total)? onProgress}) async {
    final sum = SyncSummary();
    final total = pendingCount();
    var done = 0;
    try {
      while (true) {
        final batch = _payloads(batchSize);
        if (batch.isEmpty) break;
        final res = await portal.uploadAttempts(batch);
        final results = (res['results'] as List).cast<Map<String, dynamic>>();
        cdb.transaction(() {
          for (final r in results) {
            final st = '${r['status']}';
            final mapped = switch (st) {
              'synced' || 'conflict_accepted' => 'synced',
              'conflict' || 'conflict_discarded' => 'conflict',
              'rejected' => 'rejected',
              _ => 'error',
            };
            switch (mapped) {
              case 'synced': sum.synced++;
              case 'conflict': sum.conflicts++;
              case 'rejected': sum.rejected++;
              default: sum.errors++;
            }
            cdb.db.execute('''UPDATE attempts SET sync_status = ?, sync_message = ?, server_score = ?, server_total = ?, synced_at = ?
                              WHERE uuid = ?''', [mapped, r['message'], r['score'], r['total_marks'], DateTime.now().toIso8601String(), r['attempt_uuid']]);
          }
        });
        sum.sent += batch.length;
        done += batch.length;
        onProgress?.call(done, total);
        // Errors stay 'error' and would be picked up again immediately: stop after one pass over them.
        if (results.every((r) => !['synced', 'conflict', 'rejected', 'conflict_accepted', 'conflict_discarded'].contains(r['status']))) break;
      }
    } on PortalError catch (e) {
      sum.error = e.message;
    }
    cdb.db.execute('INSERT INTO sync_log(at, sent, synced, conflicts, rejected, errors, message) VALUES (?,?,?,?,?,?,?)',
        [DateTime.now().toIso8601String(), sum.sent, sum.synced, sum.conflicts, sum.rejected, sum.errors, sum.error]);
    cdb.log('sync', sum.toString());
    return sum;
  }

  /// Re-checks conflicts with the portal (an admin may have accepted them there).
  Future<int> refreshConflicts(PortalClient portal) async {
    final uuids = [for (final r in cdb.db.select("SELECT uuid FROM attempts WHERE sync_status = 'conflict'")) r['uuid'] as String];
    if (uuids.isEmpty) return 0;
    final res = await portal.attemptStatus(uuids);
    var changed = 0;
    for (final r in (res['results'] as List).cast<Map<String, dynamic>>()) {
      if (r['status'] == 'conflict_accepted') {
        cdb.db.execute("UPDATE attempts SET sync_status = 'synced', sync_message = 'Accepted on the portal', server_score = ?, server_total = ? WHERE uuid = ?",
            [r['score'], r['total_marks'], r['attempt_uuid']]);
        changed++;
      }
    }
    return changed;
  }

  static String? _iso(String? local) => local == null ? null : DateTime.tryParse(local)?.toUtc().toIso8601String();
  static int? _dur(String? a, String? b) {
    final x = a == null ? null : DateTime.tryParse(a), y = b == null ? null : DateTime.tryParse(b);
    return (x == null || y == null) ? null : y.difference(x).inSeconds;
  }
}
