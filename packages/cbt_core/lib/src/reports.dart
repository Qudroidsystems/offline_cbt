import 'db.dart';
import 'html_text.dart';

/// Results of one exam from this computer — for printing or Excel when the
/// upload to the portal has to wait. Scores are provisional (the portal re-marks).
class ResultsReport {
  ResultsReport._(this.exam, this.rows, this.school);
  final Map<String, Object?> exam;
  final List<Map<String, Object?>> rows;
  final String school;

  static ResultsReport build(CbtDb cdb, int examId, {String school = ''}) {
    final db = cdb.db;
    final exam = db.select('SELECT * FROM exams WHERE id = ?', [examId]).first;
    final rows = db.select('''
      SELECT s.admission_no, s.lastname, s.firstname, s.othername, s.class_name,
             a.status, a.local_score, a.local_total, a.submitted_at, a.submit_reason, a.workstation, a.focus_lost,
             a.sync_status, a.server_score,
             (SELECT COUNT(*) FROM answers x WHERE x.attempt_uuid = a.uuid AND TRIM(COALESCE(x.answer,'')) <> '') AS answered,
             se.done_online
      FROM student_exams se JOIN students s ON s.user_id = se.user_id
      LEFT JOIN attempts a ON a.user_id = se.user_id AND a.exam_id = se.exam_id
      WHERE se.exam_id = ?
      ORDER BY s.lastname, s.firstname''', [examId]).map((r) => Map<String, Object?>.from(r)).toList();
    return ResultsReport._(exam, rows, school);
  }

  static String _status(Map<String, Object?> r) {
    if (r['done_online'] == 1 && r['status'] == null) return 'Taken online';
    return switch (r['status']) {
      'submitted' => r['submit_reason'] == 'time_up' ? 'Submitted (time up)' : 'Submitted',
      'in_progress' => 'Still writing',
      _ => 'Absent',
    };
  }

  static String _num(Object? n) {
    if (n is! num) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  static String _pct(Object? s, Object? t) => (s is num && t is num && t > 0) ? (s * 100 / t).toStringAsFixed(1) : '';

  static String _sync(Object? s) => switch (s) {
        'synced' => 'Uploaded',
        'conflict' => 'Conflict',
        'rejected' => 'Rejected',
        'error' || 'pending' => 'Not uploaded',
        _ => '',
      };

  List<String> get header => const ['S/N', 'Admission no', 'Surname', 'First name', 'Other name', 'Class', 'Status', 'Answered',
        'Score', 'Total', '%', 'Left exam window', 'Computer', 'Submitted at', 'Upload'];

  List<List<String>> get table => [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}', '${rows[i]['admission_no'] ?? ''}', '${rows[i]['lastname'] ?? ''}', '${rows[i]['firstname'] ?? ''}',
            '${rows[i]['othername'] ?? ''}', '${rows[i]['class_name'] ?? ''}', _status(rows[i]),
            rows[i]['status'] == null ? '' : '${rows[i]['answered']}',
            _num(rows[i]['local_score']), _num(rows[i]['local_total']), _pct(rows[i]['local_score'], rows[i]['local_total']),
            rows[i]['status'] == null ? '' : '${rows[i]['focus_lost'] ?? 0}', '${rows[i]['workstation'] ?? ''}',
            '${rows[i]['submitted_at'] ?? ''}'.replaceFirst('T', ' ').split('.').first, _sync(rows[i]['sync_status']),
          ]
      ];

  /// CSV that Excel opens directly (UTF-8 with BOM so names with accents display correctly).
  String toCsv() {
    String cell(String v) => (v.contains(',') || v.contains('"') || v.contains('\n')) ? '"${v.replaceAll('"', '""')}"' : v;
    final b = StringBuffer('﻿');
    b.writeln('${cell(htmlToPlain(exam['title'] as String?))},${cell('${exam['class_name'] ?? ''}')},${cell('${exam['subject'] ?? ''}')}');
    b.writeln(header.map(cell).join(','));
    for (final r in table) {
      b.writeln(r.map(cell).join(','));
    }
    return b.toString();
  }

  /// Printable A4 page (open in a browser and print / save as PDF).
  String toHtml() {
    String e(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final done = rows.where((r) => r['status'] == 'submitted').toList();
    final scores = done.map((r) => (r['local_score'] as num?) ?? 0).toList();
    final avg = scores.isEmpty ? '' : (scores.reduce((a, b) => a + b) / scores.length).toStringAsFixed(1);
    final b = StringBuffer('''<!DOCTYPE html><html><head><meta charset="utf-8"><title>${e(htmlToPlain(exam['title'] as String?))} — results</title>
<style>@page{size:A4 landscape;margin:10mm}body{font-family:Arial,sans-serif;font-size:11px;color:#111}
h1{font-size:17px;margin:0;color:#1e3a5f}h2{font-size:13px;margin:2px 0 8px;font-weight:normal;color:#555}
table{border-collapse:collapse;width:100%}th{background:#1e3a5f;color:#fff;text-align:left;padding:4px}
td{border-bottom:1px solid #ddd;padding:3px 4px}tr:nth-child(even) td{background:#f7f9fb}.n{text-align:right}
.meta{margin:6px 0 10px}.note{color:#777;font-size:10px;margin-top:8px}@media print{button{display:none}}</style></head><body>
<button onclick="window.print()" style="float:right;padding:6px 14px">Print</button>
<h1>${e(school)}</h1><h2>${e(htmlToPlain(exam['title'] as String?))} — ${e('${exam['class_name'] ?? ''}')} — ${e('${exam['subject'] ?? ''}')}</h2>
<div class="meta">Students: ${rows.length} &nbsp;•&nbsp; Submitted: ${done.length} &nbsp;•&nbsp; Average score: $avg / ${_num(exam['total_marks'])}</div>
<table><thead><tr>${header.map((h) => '<th>${e(h)}</th>').join()}</tr></thead><tbody>''');
    for (final r in table) {
      b.write('<tr>${[for (var i = 0; i < r.length; i++) '<td${i >= 7 && i <= 11 ? ' class="n"' : ''}>${e(r[i])}</td>'].join()}</tr>');
    }
    b.write('</tbody></table><div class="note">Provisional scores from the offline exam server, generated ${e(DateTime.now().toString().split('.').first)}. '
        'Official results are on the school portal after upload.</div></body></html>');
    return b.toString();
  }
}
