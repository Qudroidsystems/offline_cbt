// Run with:  dart run test/run_all.dart
// (Plain Dart, no package:test, so it runs anywhere the core package builds.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cbt_core/cbt_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'fixtures.dart';

var _pass = 0, _fail = 0;
void check(bool ok, String what) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    stderr.writeln('  FAIL: $what');
  }
}

/// Waits until [cond] is true (polling), up to [max]. Network timings differ per OS:
/// e.g. on Windows a connection to a stopped server takes ~2 s to fail, on Linux it is instant.
Future<bool> waitFor(bool Function() cond, {Duration max = const Duration(seconds: 15)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < max) {
    if (cond()) return true;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return cond();
}

Future<void> expectError(FutureOr<void> Function() f, String code, String what) async {
  try {
    await f();
    check(false, '$what (no error thrown)');
  } on CbtError catch (e) {
    check(e.code == code, '$what (got ${e.code})');
  } on ServerError catch (e) {
    check(e.code == code, '$what (got ${e.code})');
  }
}

Future<void> main() async {
  await group('marker', markerTests);
  await group('question html', htmlTests);
  await group('exam flow', examFlowTests);
  await group('time limits', timeTests);
  await group('re-download keeps running exams frozen', freezeTests);
  await group('http server + student computer (with Wi-Fi drop)', httpTests);
  await group('sync to portal', syncTests);
  await group('shuffle per student', shuffleTests);
  await group('pause / resume', pauseTests);
  await group('practice test, PIN-only, photos, computers, focus, report', extrasTests);
  await group('upgrade an old database', migrationTests);
  stdout.writeln('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}

Future<void> group(String name, FutureOr<void> Function() body) async {
  stdout.writeln('• $name');
  await body();
}

// ── marker ───────────────────────────────────────────────────────────────
void markerTests() {
  // values from PHP: similar_text('photosynthesys','photosynthesis',$p) => 92.857...
  check((similarTextPercent('photosynthesys', 'photosynthesis') - 92.857).abs() < 0.01, 'similar_text matches PHP');
  check((similarTextPercent('World', 'Word') - 88.888).abs() < 0.01, 'similar_text World/Word = 88.89 like PHP');
  final qs = [
    MarkQuestion(1, 'mcq', 2, [MarkOption('Abuja', true), MarkOption('Lagos', false)]),
    MarkQuestion(2, 'true_false', 1, [MarkOption('True', false), MarkOption('False', true)]),
    MarkQuestion(3, 'short_answer', 3, [MarkOption('Photosynthesis', true)]),
  ];
  final m = markAttempt(qs, {1: 'Abuja', 2: 'True', 3: 'photosynthesys'});
  check(m.score == 5 && m.total == 6 && m.attempted == 3, 'score 5/6 (got ${m.score}/${m.total})');
  final blank = markAttempt(qs, {});
  check(blank.score == 0 && blank.total == 6 && blank.attempted == 0, 'blank attempt still counts every question in total');
}

// ── html ─────────────────────────────────────────────────────────────────
void htmlTests() {
  final r = parseSimpleHtml('<p>Find <b>x</b> if x<sup>2</sup> = 9 &amp; x &gt; 0</p><script>alert(1)</script><ul><li>one</li><li>two</li></ul>');
  final plain = r.map((e) => e.text).join();
  check(plain == 'Find x if x2 = 9 & x > 0\n• one\n• two', 'plain text: "$plain"');
  check(r.any((e) => e.bold && e.text == 'x') && r.any((e) => e.sup && e.text == '2'), 'bold & superscript kept');
  check(!plain.contains('alert'), 'scripts dropped');
  check(htmlToPlain('Abuja') == 'Abuja', 'plain options untouched');
}

// ── exam flow ────────────────────────────────────────────────────────────
Future<void> examFlowTests() async {
  final db = CbtDb.memory();
  final r = ExamStore(db).importPackage(samplePackage(hash: sampleHash));
  check(r.examsSaved.length == 1 && r.students == 3, 'package imported');
  final svc = ExamService(db);

  await expectError(() => svc.login('CSS/001', 'wrong', 'PC1'), 'bad_secret', 'wrong secret refused');
  await expectError(() => svc.login('NOPE', 'x', 'PC1'), 'unknown_student', 'unknown admission no refused');
  final byPin = svc.login('css/001', 'k7m2qx', 'PC1');
  check(byPin['token'] is String, 'login with PIN (case-insensitive)');
  final byPw = svc.login('CSS/001', 'student01', 'PC1');
  check(byPw['token'] is String, 'login with portal password (bcrypt \$2y\$)');
  final uid = svc.userFor(byPw['token'] as String);
  check(uid == 501, 'token resolves to student');

  final ex = (byPw['exams'] as List).first as Map;
  check(ex['state'] == 'closed', 'exam closed until invigilator opens it');
  await expectError(() => svc.start(uid, 10, 'PC1'), 'closed', 'cannot start closed exam');

  svc.setExamOpen(10, true);
  final st = svc.start(uid, 10, 'PC1');
  final qs = st['questions'] as List;
  check(qs.length == 3, 'questions delivered');
  check(!jsonEncode(st).contains('is_correct'), 'correct answers never sent to students');
  check(((qs.firstWhere((q) => q['id'] == 103) as Map)['options'] as List).isEmpty, 'short-answer solution not sent');
  check((st['remaining_seconds'] as int) > 29 * 60, 'timer = duration');

  final uuid = st['attempt_uuid'] as String;
  svc.saveAnswers(uid, uuid, [
    {'question_id': 101, 'answer': 'Abuja'},
    {'question_id': 999, 'answer': 'junk'}, // not in this exam: ignored
  ]);
  final again = svc.start(uid, 10, 'PC2'); // computer crashed, resume elsewhere
  check(again['attempt_uuid'] == uuid, 'resume returns same attempt');
  check((again['answers'] as Map)['101'] == 'Abuja', 'resume returns saved answers');

  final res = svc.submit(uid, uuid, [
    {'question_id': 102, 'answer': 'False'},
    {'question_id': 103, 'answer': 'Photosynthesis'},
  ]);
  check(res['score'] == 6.0 && res['total_marks'] == 6.0, 'submit marks 6/6 (got ${res['score']})');
  final dup = svc.submit(uid, uuid, []);
  check(dup['already'] == true, 'second submit is harmless');
  await expectError(() => svc.start(uid, 10, 'PC1'), 'submitted', 'cannot restart after submit');

  final bayo = svc.login('CSS/002', 'P3R9TT', 'PC3');
  check(((bayo['exams'] as List).first as Map)['state'] == 'done_online', 'student who took it online is shown done_online');
  await expectError(() => svc.start(502, 10, 'PC3'), 'done_online', 'cannot take again offline');

  // invigilator tools
  check(svc.reopen(uuid, 10) == null, 'reopen allowed before upload');
  check(svc.liveAttempts().first['status'] == 'in_progress', 'reopened attempt in progress');
  check(svc.resetAttempt(uuid) == null && svc.liveAttempts().isEmpty, 'reset deletes attempt');
}

// ── time limits ──────────────────────────────────────────────────────────
Future<void> timeTests() async {
  var now = DateTime(2026, 11, 18, 9, 0);
  final db = CbtDb.memory();
  ExamStore(db).importPackage(samplePackage());
  final svc = ExamService(db, clock: () => now);
  svc.setExamOpen(10, true);
  final st = svc.start(503, 10, 'PC1');
  final uuid = st['attempt_uuid'] as String;
  svc.saveAnswers(503, uuid, [{'question_id': 101, 'answer': 'Abuja'}]);

  now = now.add(const Duration(minutes: 20));
  svc.extendTime(uuid, 5);
  check(svc.status(503, uuid)['remaining_seconds'] == 15 * 60, 'extend time adds minutes');

  now = now.add(const Duration(minutes: 15, seconds: 20)); // 20s past deadline, within grace
  final s1 = svc.saveAnswers(503, uuid, [{'question_id': 102, 'answer': 'False'}]);
  check(s1['saved'] == 1, 'answers within 30s grace accepted');

  now = now.add(const Duration(minutes: 2)); // well past deadline
  check(svc.autoSubmitExpired() == 1, 'server auto-submits when time is up');
  // A computer that was offline delivers answers it saved in time, and one it "saved" after time was up.
  final late = svc.saveAnswers(503, uuid, [
    {'question_id': 103, 'answer': 'Photosynthesis', 'client_remaining_ms': 60000},
    {'question_id': 101, 'answer': 'Lagos', 'client_remaining_ms': -300000},
  ]);
  check(late['status'] == 'submitted' && late['saved'] == 1, 'late delivery: only in-time answers kept (saved ${late['saved']})');
  final row = db.db.select('SELECT local_score FROM attempts WHERE uuid = ?', [uuid]).first;
  check(row['local_score'] == 6.0, 're-marked after late delivery (6/6, got ${row['local_score']})');

  now = now.add(const Duration(minutes: 40));
  await expectError(() => svc.saveAnswers(503, uuid, [{'question_id': 101, 'answer': 'x', 'client_remaining_ms': 1000}]),
      'submitted', 'nothing accepted 30+ minutes after time up');
}

// ── freeze ───────────────────────────────────────────────────────────────
Future<void> freezeTests() async {
  final db = CbtDb.memory();
  final store = ExamStore(db);
  store.importPackage(samplePackage());
  final svc = ExamService(db);
  svc.setExamOpen(10, true);
  svc.start(501, 10, 'PC1');
  final r = store.importPackage(samplePackage(uuid: '22222222-2222-4222-8222-222222222222', q1Text: 'CHANGED ONLINE'));
  check(r.examsKept.length == 1 && r.examsSaved.isEmpty, 'running exam kept');
  final t = db.db.select('SELECT text FROM questions WHERE id = 101').first['text'];
  check(t == 'Capital of Nigeria?', 'questions not changed under students');
  check(db.db.select('SELECT is_open FROM exams WHERE id = 10').first['is_open'] == 1, 'still open');
}

// ── http + student computer ──────────────────────────────────────────────
Future<void> httpTests() async {
  final serverDb = CbtDb.memory();
  ExamStore(serverDb).importPackage(samplePackage(hash: sampleHash));
  final svc = ExamService(serverDb)..setExamOpen(10, true);
  var server = LocalServer(svc, serverName: 'ICT Lab', schoolName: 'CSS Kabba', schoolLogo: () => 'data:image/png;base64,AAAA');
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  final port = server.port;

  final clientDb = CbtDb.memory();
  final client = ServerClient('http://127.0.0.1:$port', workstation: 'PC-07');
  final hello = await client.hello();
  check(hello['school'] == 'CSS Kabba', 'hello');
  final school = await client.school();
  check(school['name'] == 'CSS Kabba' && school['logo'] == 'data:image/png;base64,AAAA', 'school logo for the login screen');
  await expectError(() => client.login('CSS/001', 'bad'), 'bad_secret', 'bad login over http');
  final login = await client.login('CSS/001', 'student01');
  check((login['student'] as Map)['name'] == 'Okafor Ada', 'login over http');
  check(server.activeClients.containsKey('PC-07'), 'server sees workstation');

  final start = await client.start(10);
  final session = ExamSession(cdb: clientDb, client: client, startData: start);
  session.setAnswer(101, 'Abuja');
  check(await waitFor(() => session.saveState == SaveState.saved), 'answer saved to server');
  check(serverDb.db.select("SELECT answer FROM answers WHERE question_id = 101").first['answer'] == 'Abuja', 'server has answer');

  // Wi-Fi drops: server unreachable
  await server.stop();
  session.setAnswer(102, 'False');
  check(await waitFor(() => session.saveState == SaveState.offline), 'goes offline, keeps working');
  check(clientDb.db.select('SELECT dirty FROM client_answers WHERE question_id = 102').first['dirty'] == 1, 'answer kept on student computer');

  // Student computer crashes & app restarts: a new session rebuilds unsent answers from SQLite.
  session.dispose();

  server = LocalServer(svc, serverName: 'ICT Lab', schoolName: 'CSS Kabba');
  await server.start(port: port, address: InternetAddress.loopbackIPv4);
  final resumed = await client.start(10);
  final session2 = ExamSession(cdb: clientDb, client: client, startData: resumed);
  check(session2.answers[102] == 'False' && session2.answers[101] == 'Abuja', 'answers restored after restart');
  check(await waitFor(() => serverDb.db.select("SELECT answer FROM answers WHERE question_id = 102").firstOrNull?['answer'] == 'False'),
      'unsent answer delivered when server is back');

  session2.setAnswer(103, 'photosynthesis');
  final ok = await session2.submit();
  check(ok && session2.submitted, 'submitted over http');
  check(session2.submitResult?['score'] == 6.0, 'score returned (${session2.submitResult?['score']})');
  session2.dispose();

  // Submit while server is down → remembered and completed later
  final c3 = ServerClient('http://127.0.0.1:$port', workstation: 'PC-08');
  await c3.login('CSS/003', 'ZZ4422');
  final s3 = ExamSession(cdb: clientDb, client: c3, startData: await c3.start(10));
  s3.setAnswer(101, 'Lagos');
  await server.stop();
  final ok3 = await s3.submit();
  check(!ok3 && s3.submittedLocally && !s3.submitted, 'submit while offline is kept');
  server = LocalServer(svc, serverName: 'ICT Lab', schoolName: 'CSS Kabba');
  await server.start(port: port, address: InternetAddress.loopbackIPv4);
  check(await waitFor(() => s3.submitted, max: const Duration(seconds: 25)), 'pending submit completes when server is back');
  check(serverDb.db.select("SELECT status FROM attempts WHERE user_id = 503").first['status'] == 'submitted', 'server recorded it');
  s3.dispose();

  // Submitted offline, then the student computer was restarted before the server came back.
  final c4 = ServerClient('http://127.0.0.1:$port', workstation: 'PC-09');
  await c4.login('CSS/001', 'K7M2QX');
  svc.resetAttempt(serverDb.db.select('SELECT uuid FROM attempts WHERE user_id = 501').first['uuid'] as String);
  final s4 = ExamSession(cdb: clientDb, client: c4, startData: await c4.start(10));
  await server.stop();
  s4.setAnswer(101, 'Abuja');
  await s4.submit();
  s4.dispose(); // app closed
  check(await flushPendingSubmissions(clientDb, 'PC-09') == 1, 'still waiting while server is down');
  server = LocalServer(svc, serverName: 'ICT Lab', schoolName: 'CSS Kabba');
  await server.start(port: port, address: InternetAddress.loopbackIPv4);
  check(await flushPendingSubmissions(clientDb, 'PC-09') == 0, 'sent after restart');
  final a4 = serverDb.db.select("SELECT status, local_score FROM attempts WHERE user_id = 501").first;
  check(a4['status'] == 'submitted' && a4['local_score'] == 2.0, 'server got the offline submission (score ${a4['local_score']})');
  await server.stop();
}

// ── sync ─────────────────────────────────────────────────────────────────
Future<void> syncTests() async {
  final db = CbtDb.memory();
  ExamStore(db).importPackage(samplePackage());
  final svc = ExamService(db)..setExamOpen(10, true);
  for (final u in [501, 503]) {
    final st = svc.start(u, 10, 'PC');
    svc.submit(u, st['attempt_uuid'] as String, [{'question_id': 101, 'answer': 'Abuja'}]);
  }

  // Fake portal: idempotent by UUID; user 503 already took the exam online (conflict);
  // the first request fails with a server error.
  final received = <String, Map<String, dynamic>>{};
  var calls = 0;
  String? auth;
  final portal = await io.serve((Request req) async {
    calls++;
    auth = req.headers['authorization'];
    if (calls == 1) return Response.internalServerError(body: jsonEncode({'message': 'boom'}));
    final b = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final results = <Map<String, dynamic>>[];
    for (final a in (b['attempts'] as List).cast<Map<String, dynamic>>()) {
      final u = a['attempt_uuid'] as String;
      final dup = received.containsKey(u);
      received[u] = a;
      final st = a['user_id'] == 503 ? 'conflict' : 'synced';
      results.add({'attempt_uuid': u, 'status': st, 'duplicate': dup, 'message': null, 'score': 2.0, 'total_marks': 6.0});
    }
    return Response.ok(jsonEncode({'success': true, 'results': results}), headers: {'content-type': 'application/json'});
  }, InternetAddress.loopbackIPv4, 0);

  final client = PortalClient(baseUrl: 'http://127.0.0.1:${portal.port}/', deviceKey: 'ocbt_test');
  final sync = SyncService(db);
  check(sync.pendingCount() == 2, '2 attempts waiting');

  final first = await sync.syncAll(client);
  check(first.error != null && sync.pendingCount() == 2, 'portal error: nothing lost, still pending');

  final second = await sync.syncAll(client);
  check(second.synced == 1 && second.conflicts == 1, 'uploaded 1, conflict 1 ($second)');
  check(auth == 'Bearer ocbt_test', 'device key sent');
  check(sync.pendingCount() == 0, 'nothing pending');
  final one = received.values.first;
  check((one['answers'] as List).length == 3, 'every question sent (blank ones too) so totals match online');
  check(one['package_uuid'] != null && one['started_at'] != null && one['submitted_at'] != null, 'attempt metadata sent');

  // Re-sync: nothing pending, nothing re-sent.
  final before = calls;
  final third = await sync.syncAll(client);
  check(third.sent == 0 && calls == before, 'syncing again sends nothing');

  // Force a re-send of an already-synced attempt (e.g. local DB restored from backup): portal treats as duplicate.
  db.db.execute("UPDATE attempts SET sync_status = 'pending' WHERE user_id = 501");
  await sync.syncAll(client);
  check(received.length == 2, 'portal never sees a new attempt for a repeated UUID');
  check(svc.resetAttempt(db.db.select('SELECT uuid FROM attempts WHERE user_id = 501').first['uuid'] as String) != null,
      'cannot reset an attempt once uploaded');
  await portal.close(force: true);
}

// ── shuffle ──────────────────────────────────────────────────────────────
Future<void> shuffleTests() async {
  final db = CbtDb.memory();
  final pkg = samplePackage();
  // a bigger exam so orders differ visibly
  final ex = (pkg['exams'] as List).first as Map<String, dynamic>;
  final qs = ex['questions'] as List;
  for (var i = 0; i < 12; i++) {
    qs.add({'id': 200 + i, 'text': 'Q$i', 'type': 'mcq', 'marks': 1, 'order': 10 + i, 'image': null, 'options': [
      {'id': 3000 + i * 4, 'label': 'A', 'text': 'w$i', 'is_correct': false},
      {'id': 3001 + i * 4, 'label': 'B', 'text': 'x$i', 'is_correct': false},
      {'id': 3002 + i * 4, 'label': 'C', 'text': 'y$i', 'is_correct': true},
      {'id': 3003 + i * 4, 'label': 'D', 'text': 'z$i', 'is_correct': false},
    ]});
  }
  ExamStore(db).importPackage(pkg);
  final svc = ExamService(db)..setExamOpen(10, true);
  final a = svc.start(501, 10, 'PC1'), b = svc.start(503, 10, 'PC2');
  List<int> order(Map m) => [for (final q in m['questions'] as List) (q as Map)['id'] as int];
  check(order(a).join() != order(b).join(), 'two students get different question orders');
  check(order(svc.start(501, 10, 'PC9')).join() == order(a).join(), 'same student keeps the same order on resume');
  final tf = (a['questions'] as List).firstWhere((q) => q['id'] == 102) as Map;
  check(((tf['options'] as List).first as Map)['text'] == 'True', 'True/False keeps its order');
  // marking uses text, so shuffled options still mark correctly
  final ans = [for (var i = 0; i < 12; i++) {'question_id': 200 + i, 'answer': 'y$i'}];
  final r = svc.submit(501, a['attempt_uuid'] as String, [...ans, {'question_id': 101, 'answer': 'Abuja'}]);
  check(r['score'] == 14.0, 'shuffled exam marks correctly (got ${r['score']})');
  svc.setShuffle(10, false);
  final c = ExamService(db);
  db.db.execute('DELETE FROM attempts WHERE user_id = 503');
  check(order(c.start(503, 10, 'PC2')).first == 101, 'shuffle can be switched off');
}

// ── pause ────────────────────────────────────────────────────────────────
Future<void> pauseTests() async {
  var now = DateTime(2026, 11, 18, 9, 0);
  final db = CbtDb.memory();
  ExamStore(db).importPackage(samplePackage());
  final svc = ExamService(db, clock: () => now)..setExamOpen(10, true);
  final st = svc.start(501, 10, 'PC1');
  final uuid = st['attempt_uuid'] as String;
  now = now.add(const Duration(minutes: 10));
  svc.pauseAll();
  check(svc.anyPaused, 'paused');
  now = now.add(const Duration(minutes: 45)); // long power cut: past the original deadline
  check(svc.autoSubmitExpired() == 0, 'not auto-submitted while paused');
  final s1 = svc.status(501, uuid);
  check(s1['paused'] == true && s1['remaining_seconds'] == 20 * 60, 'clock frozen at 20 min (got ${s1['remaining_seconds']})');
  await expectError(() => svc.start(503, 10, 'PC2'), 'paused', 'nobody can start while paused');
  svc.resumeAll();
  final s2 = svc.status(501, uuid);
  check(s2['paused'] == false && s2['remaining_seconds'] == 20 * 60, 'after resume still 20 min left (got ${s2['remaining_seconds']})');
  now = now.add(const Duration(minutes: 19));
  check(svc.autoSubmitExpired() == 0 && svc.status(501, uuid)['remaining_seconds'] == 60, 'clock runs again');

  // student computer learns about the pause from its heartbeat and locks answers
  final serverDb = CbtDb.memory();
  ExamStore(serverDb).importPackage(samplePackage());
  final svc2 = ExamService(serverDb)..setExamOpen(10, true);
  final server = LocalServer(svc2, serverName: 'S', schoolName: 'X');
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  final client = ServerClient('http://127.0.0.1:${server.port}', workstation: 'PC-P', appVersion: '1.0.0');
  await client.login('CSS/003', 'ZZ4422');
  final session = ExamSession(cdb: CbtDb.memory(), client: client, startData: await client.start(10));
  svc2.pauseExam(10);
  check(await waitFor(() => session.paused), 'student computer sees the pause');
  final frozen = session.remaining;
  session.setAnswer(101, 'Abuja');
  check(session.answers[101] == null, 'answers locked while paused');
  await Future.delayed(const Duration(seconds: 2));
  check(session.remaining == frozen, 'student timer frozen');
  svc2.resumeExam(10);
  check(await waitFor(() => !session.paused), 'student computer sees the resume');
  session.dispose();
  await server.stop();
}

// ── extras ───────────────────────────────────────────────────────────────
Future<void> extrasTests() async {
  final db = CbtDb.memory();
  final store = ExamStore(db);
  store.importPackage(samplePackage(hash: sampleHash));
  final svc = ExamService(db);

  // practice test
  final exams = svc.examsFor(501);
  check(exams.any((e) => e['id'] == -1 && e['practice'] == true), 'practice test listed for every student');
  svc.setExamOpen(-1, true);
  final p = svc.start(501, -1, 'PC1');
  svc.submit(501, p['attempt_uuid'] as String, [{'question_id': -101, 'answer': 'Mango'}, {'question_id': -103, 'answer': 'practice'}]);
  check(db.db.select('SELECT local_score FROM attempts WHERE exam_id = -1').first['local_score'] == 2.0, 'practice test is marked');
  check(SyncService(db).pendingCount() == 0, 'practice test is never uploaded');
  check(svc.resetPractice() == 1 && svc.examsFor(501).firstWhere((e) => e['id'] == -1)['state'] == 'available', 'practice can be reset');
  check(store.deleteExam(-1) != null, 'practice test cannot be deleted');

  // photos
  final login = svc.login('CSS/001', 'K7M2QX', 'PC1');
  check((login['student'] as Map)['photo'] == 'data:image/png;base64,iVBORw0KGgo=', 'photo sent at login');

  // PIN-only
  svc.loginMode = 'pin';
  await expectError(() => svc.login('CSS/001', 'student01', 'PC1'), 'bad_secret', 'password refused in PIN-only mode');
  check(svc.login('CSS/001', 'K7M2QX', 'PC1')['token'] != null, 'PIN still works');
  svc.loginMode = 'both';
  check(store.clearPasswordHashes() == 1, 'saved passwords removed');
  await expectError(() => svc.login('CSS/001', 'student01', 'PC1'), 'bad_secret', 'no password login after removal');

  // workstations + focus
  svc.setExamOpen(10, true);
  svc.touchWorkstation('PC-07', '192.168.1.7', '1.0.0');
  final st = svc.start(501, 10, 'PC-07');
  final uuid = st['attempt_uuid'] as String;
  final ws = svc.workstations().first;
  check(ws['name'] == 'PC-07' && ws['app_version'] == '1.0.0' && ws['firstname'] == 'Ada', 'computer list shows version and student');
  svc.recordFocusLost(501, uuid);
  check(svc.recordFocusLost(501, uuid) == 2, 'leaving the window is counted');
  check(svc.liveAttempts().first['focus_lost'] == 2, 'invigilator sees the count');
  svc.submit(501, uuid, [{'question_id': 101, 'answer': 'Abuja'}]);

  // report
  final rep = ResultsReport.build(db, 10, school: 'CSS Kabba');
  final csv = rep.toCsv();
  check(csv.contains('CSS/001') && csv.contains('Okafor') && csv.contains('Absent') && csv.contains('Taken online'), 'CSV has every student with status');
  check(rep.table.firstWhere((r) => r[1] == 'CSS/001')[8] == '2' && rep.table.firstWhere((r) => r[1] == 'CSS/001')[11] == '2', 'CSV score and window count');
  check(rep.toHtml().contains('<table>') && rep.toHtml().contains('Average score'), 'printable HTML report');
}

// ── migration ────────────────────────────────────────────────────────────
Future<void> migrationTests() async {
  final path = '${Directory.systemTemp.path}/ocbt_mig_${DateTime.now().microsecondsSinceEpoch}.db';
  final old = CbtDb.open(path);
  old.db.execute('PRAGMA user_version = 1');
  old.db.execute('ALTER TABLE exams DROP COLUMN shuffle');
  old.db.execute('ALTER TABLE exams DROP COLUMN paused_at');
  old.db.execute('ALTER TABLE attempts DROP COLUMN focus_lost');
  old.db.execute('ALTER TABLE students DROP COLUMN photo');
  old.db.execute('DROP TABLE workstations');
  old.close();
  final up = CbtDb.open(path);
  check(up.db.select('PRAGMA user_version').first.values.first == 2, 'upgraded to v2');
  ExamStore(up).importPackage(samplePackage());
  final svc = ExamService(up)..setExamOpen(10, true)..pauseExam(10);
  check(svc.anyPaused, 'new columns usable after upgrade');
  up.close();
  File(path).deleteSync();
}
