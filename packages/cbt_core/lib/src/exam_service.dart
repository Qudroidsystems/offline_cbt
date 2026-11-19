import 'dart:math';

import 'package:uuid/uuid.dart';

import 'bcrypt.dart';
import 'db.dart';
import 'marker.dart';

class CbtError implements Exception {
  CbtError(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Exam rules on the server (admin PC). Every student computer talks to this
/// through the local HTTP server; the server's clock decides the time left.
class ExamService {
  ExamService(this.cdb, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final CbtDb cdb;
  final DateTime Function() _now;

  /// Answers saved up to this long after time is up still count (network delays).
  static const graceSeconds = 30;
  /// A student computer that lost Wi-Fi may deliver answers it saved *before*
  /// time ran out until this long after the deadline.
  static const lateDeliveryMinutes = 30;
  /// Student logins expire after this much inactivity.
  static const sessionHours = 12;
  /// Built-in practice exam (never uploaded).
  static const practiceExamId = -1;

  int get _nowMs => _now().millisecondsSinceEpoch;
  String get _nowIso => _now().toIso8601String();

  /// Sounds on student computers (login, warnings, time up…). Default on.
  bool get studentSounds => cdb.setting('student_sounds') != '0';
  set studentSounds(bool v) => cdb.setSetting('student_sounds', v ? '1' : '0');

  /// 'both' (portal password or PIN) or 'pin' (PIN only).
  String get loginMode => cdb.setting('login_mode') ?? 'both';
  set loginMode(String v) => cdb.setSetting('login_mode', v == 'pin' ? 'pin' : 'both');

  // ── login ────────────────────────────────────────────────────────────

  /// [secret] is the student's portal password or exam PIN.
  Map<String, dynamic> login(String admissionNo, String secret, String workstation) {
    final db = cdb.db;
    final rows = db.select('SELECT * FROM students WHERE admission_no = ? COLLATE NOCASE', [admissionNo.trim()]);
    if (rows.isEmpty) throw CbtError(401, 'unknown_student', 'Admission number not found on this exam server.');
    final s = rows.first;
    final pin = (s['pin'] as String?)?.trim();
    final okPin = pin != null && pin.isNotEmpty && pin.toUpperCase() == secret.trim().toUpperCase();
    final okPw = !okPin && loginMode != 'pin' && bcryptVerify(secret, s['password_hash'] as String?);
    if (!okPin && !okPw) {
      throw CbtError(401, 'bad_secret', loginMode == 'pin' ? 'Wrong PIN. Use the exam PIN on your slip.' : 'Wrong password or PIN.');
    }

    final token = _token();
    db.execute('INSERT INTO sessions(token, user_id, workstation, created_at, last_seen) VALUES (?,?,?,?,?)',
        [token, s['user_id'], workstation, _nowIso, _nowIso]);
    db.execute('UPDATE workstations SET user_id = ?, attempt_uuid = NULL WHERE name = ?', [s['user_id'], workstation]);
    cdb.log('login', '${s['lastname']} ${s['firstname']} (${s['admission_no']}) on $workstation');
    return {'token': token, 'student': _studentJson(s), 'exams': examsFor(s['user_id'] as int)};
  }

  int userFor(String? token) {
    if (token == null || token.isEmpty) throw CbtError(401, 'no_token', 'Please log in.');
    final r = cdb.db.select('SELECT user_id, last_seen FROM sessions WHERE token = ?', [token]);
    if (r.isEmpty) throw CbtError(401, 'bad_token', 'Your login has expired. Please log in again.');
    final last = DateTime.tryParse(r.first['last_seen'] as String? ?? '') ?? DateTime(2000);
    if (_now().difference(last).inHours >= sessionHours) throw CbtError(401, 'expired', 'Your login has expired. Please log in again.');
    cdb.db.execute('UPDATE sessions SET last_seen = ? WHERE token = ?', [_nowIso, token]);
    return r.first['user_id'] as int;
  }

  void logout(String token) {
    final r = cdb.db.select('SELECT workstation FROM sessions WHERE token = ?', [token]).firstOrNull;
    if (r != null) cdb.db.execute('UPDATE workstations SET user_id = NULL, attempt_uuid = NULL WHERE name = ?', [r['workstation']]);
    cdb.db.execute('DELETE FROM sessions WHERE token = ?', [token]);
  }

  /// Remember every student computer that talks to the server (readiness check).
  void touchWorkstation(String name, String ip, String? appVersion) {
    if (name.isEmpty) return;
    cdb.db.execute('''INSERT INTO workstations(name, ip, app_version, last_seen) VALUES (?,?,?,?)
        ON CONFLICT(name) DO UPDATE SET ip = excluded.ip, app_version = COALESCE(excluded.app_version, workstations.app_version),
        last_seen = excluded.last_seen''', [name, ip, appVersion, _nowIso]);
  }

  // ── exams for a student ──────────────────────────────────────────────

  List<Map<String, dynamic>> examsFor(int userId) {
    autoSubmitExpired();
    final rows = cdb.db.select('''
      SELECT e.id, e.title, e.subject, e.class_name, e.duration, e.question_count, e.is_open, e.paused_at, se.done_online,
             a.uuid, a.status, a.deadline, a.extra_seconds
      FROM student_exams se JOIN exams e ON e.id = se.exam_id
      LEFT JOIN attempts a ON a.exam_id = e.id AND a.user_id = se.user_id
      WHERE se.user_id = ? ORDER BY e.id < 0, e.title''', [userId]);
    return rows.map((r) {
      String state;
      if (r['status'] == 'submitted') {
        state = 'submitted';
      } else if (r['done_online'] == 1) {
        state = 'done_online';
      } else if (r['status'] == 'in_progress') {
        state = 'in_progress';
      } else if (r['is_open'] == 1) {
        state = 'available';
      } else {
        state = 'closed';
      }
      return {
        'id': r['id'], 'title': r['title'], 'subject': r['subject'], 'class_name': r['class_name'],
        'duration': r['duration'], 'question_count': r['question_count'], 'state': state,
        'practice': (r['id'] as int) < 0,
        'paused': r['paused_at'] != null,
        if (state == 'in_progress') 'remaining_seconds': _remaining(r['deadline'] as int, r['extra_seconds'] as int, r['paused_at'] as int?),
      };
    }).toList();
  }

  // ── start / resume ───────────────────────────────────────────────────

  Map<String, dynamic> start(int userId, int examId, String workstation) {
    final db = cdb.db;
    final ex = db.select('SELECT * FROM exams WHERE id = ?', [examId]);
    if (ex.isEmpty) throw CbtError(404, 'no_exam', 'Exam not found on this server.');
    final e = ex.first;
    final link = db.select('SELECT done_online FROM student_exams WHERE user_id = ? AND exam_id = ?', [userId, examId]);
    if (link.isEmpty) throw CbtError(403, 'not_eligible', 'You are not registered for this exam.');
    if (link.first['done_online'] == 1) throw CbtError(409, 'done_online', 'You already took this exam online.');

    autoSubmitExpired();
    var a = db.select('SELECT * FROM attempts WHERE exam_id = ? AND user_id = ?', [examId, userId]);
    if (a.isNotEmpty && a.first['status'] == 'submitted') {
      throw CbtError(409, 'submitted', 'You have already submitted this exam.');
    }
    if (a.isEmpty) {
      if (e['is_open'] != 1) throw CbtError(403, 'closed', 'This exam has not been opened by the invigilator yet.');
      if (e['paused_at'] != null) throw CbtError(403, 'paused', 'The invigilator has paused this exam. Please wait.');
      final uuid = const Uuid().v4();
      final deadline = _nowMs + (e['duration'] as int) * 60 * 1000;
      db.execute('''INSERT INTO attempts(uuid, exam_id, user_id, package_uuid, workstation, status, started_at, deadline, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)''', [uuid, examId, userId, e['package_uuid'], workstation, 'in_progress', _nowIso, deadline, _nowIso]);
      cdb.log('start', 'User $userId started exam $examId on $workstation');
      a = db.select('SELECT * FROM attempts WHERE uuid = ?', [uuid]);
    } else {
      // Resuming (maybe on another computer after a crash).
      db.execute('UPDATE attempts SET workstation = ?, updated_at = ? WHERE uuid = ?', [workstation, _nowIso, a.first['uuid']]);
      cdb.log('resume', 'User $userId resumed exam $examId on $workstation');
    }
    final at = a.first;
    db.execute('UPDATE workstations SET user_id = ?, attempt_uuid = ? WHERE name = ?', [userId, at['uuid'], workstation]);
    final saved = {
      for (final r in db.select('SELECT question_id, answer FROM answers WHERE attempt_uuid = ?', [at['uuid']]))
        '${r['question_id']}': r['answer']
    };
    return {
      'attempt_uuid': at['uuid'],
      'remaining_seconds': _remaining(at['deadline'] as int, at['extra_seconds'] as int, e['paused_at'] as int?),
      'paused': e['paused_at'] != null,
      'exam': {
        'id': e['id'], 'title': e['title'], 'subject': e['subject'], 'class_name': e['class_name'],
        'duration': e['duration'], 'total_marks': e['total_marks'], 'description': e['description'],
        'practice': examId < 0,
        'calculator': e['calculator'] ?? 'basic',   // off | basic | scientific
        'sounds': studentSounds,
      },
      'questions': _questionsForStudent(examId, at['uuid'] as String, shuffle: e['shuffle'] == 1),
      'answers': saved,
    };
  }

  /// Questions WITHOUT the correct answers. With [shuffle], every attempt gets
  /// its own (stable) order of questions and options, so neighbours differ.
  /// Marking is unaffected: answers are matched on the option's text.
  List<Map<String, dynamic>> _questionsForStudent(int examId, String attemptUuid, {bool shuffle = false}) {
    final db = cdb.db;
    final qs = db.select('SELECT id, type, text, marks, image FROM questions WHERE exam_id = ? ORDER BY ord, id', [examId]);
    final opts = <int, List<Map<String, dynamic>>>{};
    for (final o in db.select('SELECT o.id, o.question_id, o.label, o.text FROM options o JOIN questions q ON q.id = o.question_id WHERE q.exam_id = ? ORDER BY o.id', [examId])) {
      opts.putIfAbsent(o['question_id'] as int, () => []).add({'id': o['id'], 'label': o['label'], 'text': o['text']});
    }
    final rnd = Random(_seed(attemptUuid));
    final out = [
      for (final q in qs)
        {
          'id': q['id'], 'type': q['type'], 'text': q['text'], 'marks': q['marks'], 'image': q['image'],
          // short answers: students type, so never send the option (it IS the answer)
          'options': q['type'] == 'short_answer'
              ? const <Map<String, dynamic>>[]
              : (shuffle && q['type'] != 'true_false'
                  ? ([...?opts[q['id']]]..shuffle(rnd)).map((o) => {...o, 'label': null}).toList() // letters follow the new order
                  : (opts[q['id']] ?? const <Map<String, dynamic>>[])),
        }
    ];
    if (shuffle) out.shuffle(rnd);
    return out;
  }

  static int _seed(String s) {
    var h = 0x811c9dc5; // FNV-1a: same order every time this attempt is opened
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  // ── answers & submit ─────────────────────────────────────────────────

  /// Each answer: {question_id, answer, client_remaining_ms?}. client_remaining_ms is
  /// the time the student had left (by their computer's exam timer) when they
  /// answered — lets answers saved during a Wi-Fi outage still count.
  Map<String, dynamic> saveAnswers(int userId, String uuid, List<Map<String, dynamic>> answers) {
    final at = _attempt(userId, uuid);
    final rem = _remainingFor(at);
    if (at['status'] == 'submitted') {
      if (_lateDeliveryAllowed(at, rem)) {
        final n = cdb.transaction(() {
          final n = _store(at, answers, rem);
          _remark(uuid, at['exam_id'] as int);
          return n;
        });
        return {'saved': n, 'remaining_seconds': 0, 'status': 'submitted', 'paused': false};
      }
      throw CbtError(409, 'submitted', 'This exam has already been submitted.');
    }
    if (rem < -graceSeconds) {
      // Time ran out while this computer was away: keep what was answered in time, then close.
      final n = cdb.transaction(() {
        final n = _store(at, answers, rem);
        _finish(uuid, at['exam_id'] as int, 'time_up');
        return n;
      });
      return {'saved': n, 'remaining_seconds': 0, 'status': 'submitted', 'paused': false};
    }
    final accepted = _store(at, answers, rem);
    return {'saved': accepted, 'remaining_seconds': max(0, rem), 'status': 'in_progress', 'paused': _paused(at)};
  }

  Map<String, dynamic> submit(int userId, String uuid, List<Map<String, dynamic>> answers, {String reason = 'student'}) {
    final at = _attempt(userId, uuid);
    final rem = _remainingFor(at);
    if (at['status'] == 'submitted') {
      if (_lateDeliveryAllowed(at, rem) && answers.isNotEmpty) {
        cdb.transaction(() {
          _store(at, answers, rem);
          _remark(uuid, at['exam_id'] as int);
        });
      }
      return {'status': 'submitted', 'already': true, ..._scoreFor(uuid, at['exam_id'] as int)};
    }
    cdb.transaction(() {
      _store(at, answers, rem);
      _finish(uuid, at['exam_id'] as int, rem < -graceSeconds ? 'time_up' : reason);
    });
    cdb.log('submit', 'User $userId submitted exam ${at['exam_id']} ($reason)');
    return {'status': 'submitted', 'already': false, ..._scoreFor(uuid, at['exam_id'] as int)};
  }

  /// Heartbeat from the student computer: time left, paused, submitted?
  Map<String, dynamic> status(int userId, String uuid) {
    final at = _attempt(userId, uuid);
    return {
      'status': at['status'],
      'remaining_seconds': max(0, _remainingFor(at)),
      'paused': _paused(at),
    };
  }

  /// The student's computer reports that the exam window lost focus (Alt+Tab, Windows key…).
  int recordFocusLost(int userId, String uuid) {
    final at = _attempt(userId, uuid);
    if (at['status'] != 'in_progress') return at['focus_lost'] as int? ?? 0;
    cdb.db.execute('UPDATE attempts SET focus_lost = focus_lost + 1, updated_at = ? WHERE uuid = ?', [_nowIso, uuid]);
    cdb.log('focus', 'User $userId left the exam window (exam ${at['exam_id']}, ${at['workstation']})');
    return (at['focus_lost'] as int? ?? 0) + 1;
  }

  /// An attempt the server closed because time ran out can still receive the
  /// answers a disconnected computer saved in time — until it is uploaded.
  bool _lateDeliveryAllowed(Map<String, Object?> at, int rem) =>
      at['submit_reason'] == 'time_up' && at['sync_status'] != 'synced' && -rem <= lateDeliveryMinutes * 60;

  void _remark(String uuid, int examId) {
    final m = markLocal(uuid, examId);
    cdb.db.execute('UPDATE attempts SET local_score = ?, local_total = ?, updated_at = ? WHERE uuid = ?', [m.score, m.total, _nowIso, uuid]);
  }

  int _store(Map<String, Object?> at, List<Map<String, dynamic>> answers, int remainingNow) {
    final lateBy = -remainingNow; // seconds past the deadline
    if (lateBy > lateDeliveryMinutes * 60) {
      throw CbtError(409, 'time_up', 'Time is up for this exam.');
    }
    var n = 0;
    final stmt = cdb.db.prepare('''INSERT INTO answers(attempt_uuid, question_id, answer, updated_at) VALUES (?,?,?,?)
        ON CONFLICT(attempt_uuid, question_id) DO UPDATE SET answer = excluded.answer, updated_at = excluded.updated_at''');
    final valid = {
      for (final r in cdb.db.select('SELECT id FROM questions WHERE exam_id = ?', [at['exam_id']])) r['id'] as int
    };
    for (final a in answers) {
      final qid = (a['question_id'] as num?)?.toInt();
      if (qid == null || !valid.contains(qid)) continue;
      if (lateBy > graceSeconds) {
        // Past the deadline: only answers the student's own timer says were given in time.
        final crm = (a['client_remaining_ms'] as num?)?.toInt();
        if (crm == null || crm < -graceSeconds * 1000) continue;
      }
      final text = (a['answer'] as String?);
      stmt.execute([at['uuid'], qid, text == null ? null : (text.length > 1000 ? text.substring(0, 1000) : text), _nowIso]);
      n++;
    }
    stmt.close();
    cdb.db.execute('UPDATE attempts SET updated_at = ? WHERE uuid = ?', [_nowIso, at['uuid']]);
    return n;
  }

  void _finish(String uuid, int examId, String reason) {
    final m = markLocal(uuid, examId);
    cdb.db.execute('''UPDATE attempts SET status = 'submitted', submitted_at = ?, submit_reason = ?, local_score = ?, local_total = ?,
                      updated_at = ?, sync_status = CASE WHEN sync_status = 'synced' THEN sync_status ELSE 'pending' END WHERE uuid = ?''',
        [_nowIso, reason, m.score, m.total, _nowIso, uuid]);
  }

  MarkResult markLocal(String uuid, int examId) {
    final db = cdb.db;
    final qs = db.select('SELECT id, type, marks FROM questions WHERE exam_id = ?', [examId]);
    final opts = <int, List<MarkOption>>{};
    for (final o in db.select('SELECT o.question_id, o.text, o.is_correct FROM options o JOIN questions q ON q.id = o.question_id WHERE q.exam_id = ?', [examId])) {
      opts.putIfAbsent(o['question_id'] as int, () => []).add(MarkOption((o['text'] as String?) ?? '', o['is_correct'] == 1));
    }
    final ans = {for (final r in db.select('SELECT question_id, answer FROM answers WHERE attempt_uuid = ?', [uuid])) r['question_id'] as int: r['answer'] as String?};
    return markAttempt([
      for (final q in qs) MarkQuestion(q['id'] as int, (q['type'] as String?) ?? 'mcq', (q['marks'] as num?)?.toDouble() ?? 1, opts[q['id']] ?? const [])
    ], ans);
  }

  Map<String, dynamic> _scoreFor(String uuid, int examId) {
    final show = cdb.db.select('SELECT show_score FROM exams WHERE id = ?', [examId]).firstOrNull?['show_score'] == 1;
    if (!show) return {};
    final r = cdb.db.select('SELECT local_score, local_total FROM attempts WHERE uuid = ?', [uuid]).first;
    return {'score': r['local_score'], 'total_marks': r['local_total']};
  }

  /// Submits attempts whose time (plus grace) has run out. Paused exams wait. Called regularly.
  int autoSubmitExpired() {
    final cutoff = _nowMs - graceSeconds * 1000;
    final rows = cdb.db.select('''SELECT a.uuid, a.exam_id FROM attempts a JOIN exams e ON e.id = a.exam_id
        WHERE a.status = 'in_progress' AND e.paused_at IS NULL AND a.deadline + a.extra_seconds * 1000 < ?''', [cutoff]);
    for (final r in rows) {
      _finish(r['uuid'] as String, r['exam_id'] as int, 'time_up');
      cdb.log('submit', 'Attempt ${r['uuid']} auto-submitted (time up)');
    }
    return rows.length;
  }

  // ── invigilator (admin PC only, not exposed over the network) ────────

  void setExamOpen(int examId, bool open) {
    cdb.db.execute('UPDATE exams SET is_open = ? WHERE id = ?', [open ? 1 : 0, examId]);
    cdb.log('exam', 'Exam $examId ${open ? 'opened' : 'closed'}');
  }

  void setShowScore(int examId, bool show) => cdb.db.execute('UPDATE exams SET show_score = ? WHERE id = ?', [show ? 1 : 0, examId]);
  void setCalculator(int examId, String mode) => cdb.db.execute('UPDATE exams SET calculator = ? WHERE id = ?',
      [const {'off', 'basic', 'scientific'}.contains(mode) ? mode : 'basic', examId]);
  void setShuffle(int examId, bool on) => cdb.db.execute('UPDATE exams SET shuffle = ? WHERE id = ?', [on ? 1 : 0, examId]);

  /// Stop the clock for everyone writing this exam (power cut, fire drill…).
  void pauseExam(int examId) {
    cdb.db.execute('UPDATE exams SET paused_at = ? WHERE id = ? AND paused_at IS NULL', [_nowMs, examId]);
    cdb.log('pause', 'Exam $examId paused');
  }

  /// Restart the clock: everyone gets back exactly the time the pause lasted.
  void resumeExam(int examId) {
    cdb.transaction(() {
      final r = cdb.db.select('SELECT paused_at FROM exams WHERE id = ?', [examId]).firstOrNull;
      final at = r?['paused_at'] as int?;
      if (at == null) return;
      final secs = ((_nowMs - at) / 1000).round();
      cdb.db.execute("UPDATE attempts SET extra_seconds = extra_seconds + ? WHERE exam_id = ? AND status = 'in_progress'", [secs, examId]);
      cdb.db.execute('UPDATE exams SET paused_at = NULL WHERE id = ?', [examId]);
      cdb.log('pause', 'Exam $examId resumed after ${secs}s');
    });
  }

  /// Pause every exam that is open or has students writing.
  void pauseAll() {
    for (final r in cdb.db.select("SELECT DISTINCT e.id FROM exams e LEFT JOIN attempts a ON a.exam_id = e.id AND a.status = 'in_progress' WHERE e.is_open = 1 OR a.uuid IS NOT NULL")) {
      pauseExam(r['id'] as int);
    }
  }

  void resumeAll() {
    for (final r in cdb.db.select('SELECT id FROM exams WHERE paused_at IS NOT NULL')) {
      resumeExam(r['id'] as int);
    }
  }

  bool get anyPaused => cdb.db.select('SELECT 1 FROM exams WHERE paused_at IS NOT NULL LIMIT 1').isNotEmpty;

  void extendTime(String uuid, int minutes) {
    cdb.db.execute('UPDATE attempts SET extra_seconds = extra_seconds + ?, updated_at = ? WHERE uuid = ?', [minutes * 60, _nowIso, uuid]);
    cdb.log('extend', 'Attempt $uuid extended by $minutes min');
  }

  /// Reopen a submitted attempt (e.g. a student's computer submitted by mistake). Not after it is uploaded.
  String? reopen(String uuid, int extraMinutes) {
    final r = cdb.db.select('SELECT sync_status, status FROM attempts WHERE uuid = ?', [uuid]).firstOrNull;
    if (r == null) return 'Attempt not found.';
    if (r['sync_status'] == 'synced') return 'Already uploaded to the portal — it can no longer be changed here.';
    final deadline = _nowMs + extraMinutes * 60 * 1000;
    cdb.db.execute("UPDATE attempts SET status = 'in_progress', submitted_at = NULL, submit_reason = NULL, deadline = ?, extra_seconds = 0, updated_at = ? WHERE uuid = ?",
        [deadline, _nowIso, uuid]);
    cdb.log('reopen', 'Attempt $uuid reopened for $extraMinutes min');
    return null;
  }

  /// Delete an attempt so the student can start again. Not after upload.
  String? resetAttempt(String uuid) {
    final r = cdb.db.select('SELECT sync_status FROM attempts WHERE uuid = ?', [uuid]).firstOrNull;
    if (r == null) return 'Attempt not found.';
    if (r['sync_status'] == 'synced') return 'Already uploaded to the portal — reset it on the portal instead.';
    cdb.transaction(() {
      cdb.db.execute('DELETE FROM answers WHERE attempt_uuid = ?', [uuid]);
      cdb.db.execute('DELETE FROM attempts WHERE uuid = ?', [uuid]);
    });
    cdb.log('reset', 'Attempt $uuid deleted');
    return null;
  }

  /// Clear every practice-test attempt (so students can practise again).
  int resetPractice() {
    final n = cdb.db.select('SELECT COUNT(*) n FROM attempts WHERE exam_id < 0').first['n'] as int;
    cdb.transaction(() {
      cdb.db.execute('DELETE FROM answers WHERE attempt_uuid IN (SELECT uuid FROM attempts WHERE exam_id < 0)');
      cdb.db.execute('DELETE FROM attempts WHERE exam_id < 0');
    });
    return n;
  }

  /// Live view for the invigilator.
  List<Map<String, dynamic>> liveAttempts({int? examId}) {
    autoSubmitExpired();
    final rows = cdb.db.select('''
      SELECT a.uuid, a.exam_id, a.user_id, a.workstation, a.status, a.started_at, a.submitted_at, a.submit_reason,
             a.deadline, a.extra_seconds, a.updated_at, a.local_score, a.local_total, a.sync_status, a.sync_message,
             a.server_score, a.server_total, a.focus_lost, e.paused_at,
             s.firstname, s.lastname, s.admission_no, s.photo, e.title, e.question_count,
             (SELECT COUNT(*) FROM answers x WHERE x.attempt_uuid = a.uuid AND TRIM(COALESCE(x.answer,'')) <> '') AS answered
      FROM attempts a JOIN students s ON s.user_id = a.user_id JOIN exams e ON e.id = a.exam_id
      ${examId != null ? 'WHERE a.exam_id = ?' : ''}
      ORDER BY a.status = 'submitted', s.lastname, s.firstname''', [if (examId != null) examId]);
    return [
      for (final r in rows)
        {
          ...Map<String, dynamic>.from(r),
          'remaining_seconds': r['status'] == 'in_progress'
              ? max(0, _remaining(r['deadline'] as int, r['extra_seconds'] as int, r['paused_at'] as int?))
              : 0,
        }
    ];
  }

  /// Every student computer seen, with who is on it (readiness check).
  List<Map<String, dynamic>> workstations() => [
        for (final r in cdb.db.select('''SELECT w.*, s.firstname, s.lastname, a.status AS attempt_status, e.title
            FROM workstations w LEFT JOIN students s ON s.user_id = w.user_id
            LEFT JOIN attempts a ON a.uuid = w.attempt_uuid LEFT JOIN exams e ON e.id = a.exam_id
            ORDER BY w.name'''))
          Map<String, dynamic>.from(r)
      ];

  void forgetWorkstations() => cdb.db.execute('DELETE FROM workstations');

  // ── helpers ──────────────────────────────────────────────────────────

  Map<String, Object?> _attempt(int userId, String uuid) {
    final r = cdb.db.select('SELECT a.*, e.paused_at FROM attempts a JOIN exams e ON e.id = a.exam_id WHERE a.uuid = ?', [uuid]);
    if (r.isEmpty || r.first['user_id'] != userId) throw CbtError(404, 'no_attempt', 'Exam attempt not found.');
    return r.first;
  }

  bool _paused(Map<String, Object?> at) => at['paused_at'] != null && at['status'] == 'in_progress';

  int _remainingFor(Map<String, Object?> at) =>
      _remaining(at['deadline'] as int, at['extra_seconds'] as int, at['paused_at'] as int?);

  /// While paused, the clock is frozen at the moment of the pause.
  int _remaining(int deadline, int extraSeconds, [int? pausedAt]) =>
      ((deadline + extraSeconds * 1000 - (pausedAt ?? _nowMs)) / 1000).floor();

  Map<String, dynamic> _studentJson(Map<String, Object?> s) => {
        'user_id': s['user_id'],
        'admission_no': s['admission_no'],
        'name': [s['lastname'], s['firstname'], s['othername']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' '),
        'class_name': s['class_name'],
        'photo': s['photo'],
      };

  static final _rnd = Random.secure();
  String _token() => List.generate(32, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
