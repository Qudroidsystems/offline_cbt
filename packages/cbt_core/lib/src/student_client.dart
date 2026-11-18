import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'db.dart';

class ServerError implements Exception {
  ServerError(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  /// True when the server could not be reached at all (Wi-Fi/server down).
  bool get offline => status == null;
  @override
  String toString() => message;
}

/// HTTP client for the exam server on the admin computer.
class ServerClient {
  ServerClient(String baseUrl, {required this.workstation, this.appVersion = '1.0.0', http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();
  final String baseUrl;
  final String workstation;
  final String appVersion;
  final http.Client _http;
  String? token;

  Map<String, String> get _h => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Workstation': workstation,
        'X-App-Version': appVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _do(Future<http.Response> f, {Duration timeout = const Duration(seconds: 8)}) async {
    http.Response r;
    try {
      r = await f.timeout(timeout);
    } catch (e) {
      throw ServerError('Cannot reach the exam server.');
    }
    Map<String, dynamic> b;
    try {
      b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ServerError('Unexpected reply from the exam server.', status: r.statusCode);
    }
    if (r.statusCode >= 400) throw ServerError('${b['message'] ?? 'Error ${r.statusCode}'}', status: r.statusCode, code: b['code'] as String?);
    return b;
  }

  Uri _u(String p) => Uri.parse('$baseUrl$p');

  Future<Map<String, dynamic>> hello() => _do(_http.get(_u('/api/hello'), headers: _h), timeout: const Duration(seconds: 3));

  Future<Map<String, dynamic>> school() => _do(_http.get(_u('/api/school'), headers: _h), timeout: const Duration(seconds: 8));

  Future<Map<String, dynamic>> login(String admissionNo, String secret) async {
    final b = await _do(_http.post(_u('/api/login'), headers: _h,
        body: jsonEncode({'admission_no': admissionNo, 'secret': secret, 'workstation': workstation})), timeout: const Duration(seconds: 15));
    token = b['token'] as String;
    return b;
  }

  Future<void> logout() async {
    try {
      await _do(_http.post(_u('/api/logout'), headers: _h));
    } catch (_) {}
    token = null;
  }

  Future<List<Map<String, dynamic>>> exams() async =>
      ((await _do(_http.get(_u('/api/me/exams'), headers: _h)))['exams'] as List).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> start(int examId) =>
      _do(_http.post(_u('/api/exams/$examId/start'), headers: _h, body: jsonEncode({'workstation': workstation})), timeout: const Duration(seconds: 30));

  Future<Map<String, dynamic>> save(String uuid, List<Map<String, dynamic>> answers) =>
      _do(_http.put(_u('/api/attempts/$uuid/answers'), headers: _h, body: jsonEncode({'answers': answers})));

  Future<Map<String, dynamic>> status(String uuid) => _do(_http.get(_u('/api/attempts/$uuid'), headers: _h), timeout: const Duration(seconds: 5));

  Future<void> focusLost(String uuid) async {
    try {
      await _do(_http.post(_u('/api/attempts/$uuid/focus-lost'), headers: _h), timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> submit(String uuid, List<Map<String, dynamic>> answers, {bool timeUp = false}) =>
      _do(_http.post(_u('/api/attempts/$uuid/submit'), headers: _h,
          body: jsonEncode({'answers': answers, 'reason': timeUp ? 'time_up' : 'student'})), timeout: const Duration(seconds: 20));
}

enum SaveState { saved, saving, offline }

/// One student's exam on a student computer.
///
/// Every answer is written to this computer's SQLite file immediately, then
/// sent to the server. If Wi-Fi drops, the student keeps going: the timer
/// runs from this computer's own clock and answers are re-sent when the
/// server is reachable again. Submitting while offline is remembered and
/// completed as soon as the server answers.
class ExamSession {
  ExamSession({required this.cdb, required this.client, required this.startData, this.studentJson})
      : uuid = startData['attempt_uuid'] as String,
        questions = (startData['questions'] as List).cast<Map<String, dynamic>>() {
    final remaining = (startData['remaining_seconds'] as num).toInt();
    _deadline = _clock.elapsed + Duration(seconds: remaining);
    if (startData['paused'] == true) {
      paused = true;
      _frozen = Duration(seconds: remaining);
    }
    _restoreAndPersist();
    // Heartbeat: learn about pause/resume/extra time even when the student is not answering.
    _heartbeat = Timer.periodic(const Duration(seconds: 6), (_) => _beat());
  }

  Future<void> _beat() async {
    if (submitted || _pushing || _disposed) return;
    try {
      final r = await client.status(uuid);
      _syncTime(r);
      if (saveState == SaveState.offline && _dirty.isEmpty) saveState = SaveState.saved;
      if (r['status'] == 'submitted' && !submitted) {
        // Closed by the server (time up or the invigilator). Deliver anything unsent, then finish.
        if (_dirty.isNotEmpty) await submit(timeUp: true);
        submitted = true;
      }
      _emit();
    } on ServerError catch (e) {
      if (e.offline && saveState != SaveState.offline) {
        saveState = SaveState.offline;
        _emit();
      }
    }
  }

  /// Call when the exam window loses focus (Alt+Tab, Windows key…).
  void reportFocusLost() {
    if (submitted || submittedLocally) return;
    focusLostCount++;
    client.focusLost(uuid);
    _emit();
  }

  final CbtDb cdb;
  final ServerClient client;
  final Map<String, dynamic> startData;
  final Map<String, dynamic>? studentJson;
  final String uuid;
  final List<Map<String, dynamic>> questions;

  /// Monotonic: changing the computer's clock does not change the exam time.
  final Stopwatch _clock = Stopwatch()..start();
  late Duration _deadline;

  /// The invigilator paused the exam: the clock is frozen and answers are locked.
  bool paused = false;
  Duration _frozen = Duration.zero;
  int focusLostCount = 0;
  Timer? _heartbeat;
  Timer? _submitRetry;
  bool _disposed = false;

  void _emit() {
    if (!_disposed) _changes.add(null);
  }

  final answers = <int, String>{};
  final _dirty = <int, int>{}; // question_id -> client_remaining_ms when answered
  SaveState saveState = SaveState.saved;
  bool submitted = false;
  bool submittedLocally = false;
  Map<String, dynamic>? submitResult;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Timer? _pushTimer;
  bool _pushing = false;

  Map<String, dynamic> get exam => startData['exam'] as Map<String, dynamic>;
  Duration get remaining {
    if (paused) return _frozen;
    final r = _deadline - _clock.elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  bool get timeUp => remaining == Duration.zero;
  int get answeredCount => answers.values.where((v) => v.trim().isNotEmpty).length;

  void _restoreAndPersist() {
    final db = cdb.db;
    // Server copy first, then anything this computer saved that the server never got.
    (startData['answers'] as Map?)?.forEach((k, v) {
      if (v != null) answers[int.parse('$k')] = '$v';
    });
    for (final r in db.select('SELECT question_id, answer, dirty FROM client_answers WHERE attempt_uuid = ?', [uuid])) {
      if (r['dirty'] == 1) {
        answers[r['question_id'] as int] = (r['answer'] as String?) ?? '';
        _dirty[r['question_id'] as int] = remaining.inMilliseconds;
      }
    }
    db.execute('''INSERT INTO client_attempts(uuid, server, exam_json, student_json, deadline_local, status, updated_at)
                  VALUES (?,?,?,?,?,?,?) ON CONFLICT(uuid) DO UPDATE SET server = excluded.server, exam_json = excluded.exam_json,
                  deadline_local = excluded.deadline_local, updated_at = excluded.updated_at''',
        [uuid, client.baseUrl, jsonEncode(startData), jsonEncode({...?studentJson, 'token': client.token}), DateTime.now().add(remaining).millisecondsSinceEpoch,
          'in_progress', DateTime.now().toIso8601String()]);
    final row = db.select('SELECT submitted_locally FROM client_attempts WHERE uuid = ?', [uuid]).first;
    submittedLocally = row['submitted_locally'] == 1;
    if (_dirty.isNotEmpty) _schedulePush(Duration.zero);
  }

  /// Record an answer (call on every change).
  void setAnswer(int questionId, String value) {
    if (submitted || submittedLocally || paused) return;
    answers[questionId] = value;
    _dirty[questionId] = remaining.inMilliseconds;
    cdb.db.execute('''INSERT INTO client_answers(attempt_uuid, question_id, answer, dirty, updated_at) VALUES (?,?,?,1,?)
                      ON CONFLICT(attempt_uuid, question_id) DO UPDATE SET answer = excluded.answer, dirty = 1, updated_at = excluded.updated_at''',
        [uuid, questionId, value, DateTime.now().toIso8601String()]);
    saveState = SaveState.saving;
    _emit();
    _schedulePush(const Duration(milliseconds: 600));
  }

  void _schedulePush(Duration d) {
    if (_disposed) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(d, _push);
  }

  List<Map<String, dynamic>> _dirtyPayload() => [
        for (final e in _dirty.entries) {'question_id': e.key, 'answer': answers[e.key] ?? '', 'client_remaining_ms': e.value}
      ];

  Future<void> _push() async {
    if (_pushing || _dirty.isEmpty || submitted) return;
    _pushing = true;
    final sent = Map<int, int>.from(_dirty);
    try {
      final r = await client.save(uuid, _dirtyPayload());
      _markClean(sent);
      _syncTime(r);
      saveState = _dirty.isEmpty ? SaveState.saved : SaveState.saving;
      if (r['status'] == 'submitted') {
        submitted = true;
        submitResult = r;
      }
    } on ServerError catch (e) {
      if (e.offline) {
        saveState = SaveState.offline;
        _schedulePush(const Duration(seconds: 5)); // keep trying
      } else if (e.code == 'submitted' || e.code == 'time_up') {
        submitted = true;
      } else {
        saveState = SaveState.offline;
        _schedulePush(const Duration(seconds: 10));
      }
    } finally {
      _pushing = false;
      _emit();
      if (_dirty.isNotEmpty && saveState != SaveState.offline && !submitted) _schedulePush(const Duration(milliseconds: 300));
    }
  }

  void _markClean(Map<int, int> sent) {
    for (final e in sent.entries) {
      if (_dirty[e.key] == e.value) {
        _dirty.remove(e.key);
        cdb.db.execute('UPDATE client_answers SET dirty = 0 WHERE attempt_uuid = ? AND question_id = ?', [uuid, e.key]);
      }
    }
  }

  void _syncTime(Map<String, dynamic> r) {
    final rem = r['remaining_seconds'];
    if (rem is! num) return;
    // Server is the authority (extra time, pause, resume).
    if (r['paused'] == true) {
      paused = true;
      _frozen = Duration(seconds: rem.toInt());
    } else {
      paused = false;
      _deadline = _clock.elapsed + Duration(seconds: rem.toInt());
    }
  }

  /// Submit. Returns true when the server confirmed; false when it is
  /// unreachable — the submission is then kept and retried automatically.
  Future<bool> submit({bool timeUp = false}) async {
    if (submitted) return true;
    submittedLocally = true;
    cdb.db.execute('UPDATE client_attempts SET submitted_locally = 1, updated_at = ? WHERE uuid = ?', [DateTime.now().toIso8601String(), uuid]);
    _emit();
    final all = [
      for (final q in questions)
        {'question_id': q['id'], 'answer': answers[q['id']] ?? '', 'client_remaining_ms': _dirty[q['id']] ?? remaining.inMilliseconds}
    ];
    try {
      submitResult = await client.submit(uuid, all, timeUp: timeUp);
      submitted = true;
      _heartbeat?.cancel();
      _dirty.clear();
      cdb.db.execute("UPDATE client_answers SET dirty = 0 WHERE attempt_uuid = ?", [uuid]);
      cdb.db.execute("UPDATE client_attempts SET status = 'submitted' WHERE uuid = ?", [uuid]);
      saveState = SaveState.saved;
      _emit();
      return true;
    } on ServerError catch (e) {
      if (!e.offline && (e.code == 'submitted')) {
        submitted = true;
        _emit();
        return true;
      }
      saveState = SaveState.offline;
      _emit();
      _submitRetry?.cancel();
      if (!_disposed) _submitRetry = Timer(const Duration(seconds: 5), () => submit(timeUp: timeUp));
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _submitRetry?.cancel();
    _pushTimer?.cancel();
    _changes.close();
  }
}

/// Sends exams that were submitted on this computer while the server was
/// unreachable — including after the app or computer was restarted.
/// Returns how many are still waiting.
Future<int> flushPendingSubmissions(CbtDb cdb, String workstation) async {
  final rows = cdb.db.select("SELECT * FROM client_attempts WHERE submitted_locally = 1 AND status = 'in_progress'");
  var left = 0;
  for (final r in rows) {
    final uuid = r['uuid'] as String;
    Map<String, dynamic> start, student;
    try {
      start = jsonDecode(r['exam_json'] as String) as Map<String, dynamic>;
      student = jsonDecode((r['student_json'] as String?) ?? '{}') as Map<String, dynamic>? ?? {};
    } catch (_) {
      cdb.db.execute("UPDATE client_attempts SET status = 'abandoned' WHERE uuid = ?", [uuid]);
      continue;
    }
    final client = ServerClient(r['server'] as String, workstation: workstation)..token = student['token'] as String?;
    final saved = {
      for (final a in cdb.db.select('SELECT question_id, answer FROM client_answers WHERE attempt_uuid = ?', [uuid])) a['question_id'] as int: a['answer'] as String?
    };
    final answers = [
      for (final q in (start['questions'] as List).cast<Map<String, dynamic>>())
        {'question_id': q['id'], 'answer': saved[q['id']] ?? '', 'client_remaining_ms': 0}
    ];
    try {
      await client.submit(uuid, answers);
      cdb.db.execute("UPDATE client_attempts SET status = 'submitted' WHERE uuid = ?", [uuid]);
      cdb.db.execute('UPDATE client_answers SET dirty = 0 WHERE attempt_uuid = ?', [uuid]);
    } on ServerError catch (e) {
      if (e.offline) {
        left++;
      } else if (e.code == 'submitted') {
        cdb.db.execute("UPDATE client_attempts SET status = 'submitted' WHERE uuid = ?", [uuid]);
      } else {
        // e.g. login expired: the server already closed this attempt itself when time ran out.
        cdb.db.execute("UPDATE client_attempts SET status = 'abandoned' WHERE uuid = ?", [uuid]);
      }
    }
  }
  return left;
}
