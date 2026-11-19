import 'dart:convert';

import 'db.dart';

/// Saves an exam package downloaded from the portal into the local database.
class PackageImportResult {
  PackageImportResult(this.examsSaved, this.examsKept, this.students);
  final List<String> examsSaved;
  /// Exams that already have attempts on this computer: their questions stay
  /// frozen (not replaced) so running exams are never changed underneath students.
  final List<String> examsKept;
  final int students;
}

class ExamStore {
  ExamStore(this.cdb);
  final CbtDb cdb;

  PackageImportResult importPackage(Map<String, dynamic> pkg, {bool replaceStarted = false}) {
    final db = cdb.db;
    final uuid = pkg['package_uuid'] as String;
    final saved = <String>[], kept = <String>[];

    cdb.transaction(() {
      db.execute(
          'INSERT OR REPLACE INTO packages(package_uuid, checksum, downloaded_at, school_json, session_json, term_json) VALUES (?,?,?,?,?,?)',
          [uuid, pkg['checksum'], DateTime.now().toIso8601String(), jsonEncode(pkg['school']), jsonEncode(pkg['session']), jsonEncode(pkg['term'])]);

      for (final e in (pkg['exams'] as List).cast<Map<String, dynamic>>()) {
        final id = e['id'] as int;
        final started = db.select('SELECT 1 FROM attempts WHERE exam_id = ? LIMIT 1', [id]).isNotEmpty;
        final label = '${e['title']} (${e['class']?['name'] ?? ''})';
        if (started && !replaceStarted) {
          kept.add(label);
          continue;
        }
        final wasOpen = db.select('SELECT is_open, show_score FROM exams WHERE id = ?', [id]);
        db.execute('DELETE FROM options WHERE question_id IN (SELECT id FROM questions WHERE exam_id = ?)', [id]);
        db.execute('DELETE FROM questions WHERE exam_id = ?', [id]);
        db.execute('''INSERT OR REPLACE INTO exams(id, package_uuid, title, description, duration, start_time, end_time,
                      term_id, session_id, subject, class_name, total_marks, question_count, is_open, show_score)
                      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', [
          id, uuid, e['title'], e['description'], e['duration'], e['start_time'], e['end_time'], e['term_id'],
          e['session_id'], e['subject']?['name'], e['class']?['name'], (e['total_marks'] as num?)?.toDouble(),
          e['question_count'],
          wasOpen.isEmpty ? 0 : wasOpen.first['is_open'],
          wasOpen.isEmpty ? 1 : wasOpen.first['show_score'],
        ]);
        final qs = db.prepare('INSERT OR REPLACE INTO questions(id, exam_id, ord, type, text, marks, image) VALUES (?,?,?,?,?,?,?)');
        final os = db.prepare('INSERT OR REPLACE INTO options(id, question_id, label, text, is_correct) VALUES (?,?,?,?,?)');
        var i = 0;
        for (final q in (e['questions'] as List).cast<Map<String, dynamic>>()) {
          qs.execute([q['id'], id, i++, q['type'], q['text'], (q['marks'] as num?)?.toDouble() ?? 1.0, q['image']]);
          for (final o in (q['options'] as List).cast<Map<String, dynamic>>()) {
            os.execute([o['id'], q['id'], o['label'], o['text'], (o['is_correct'] == true) ? 1 : 0]);
          }
        }
        qs.close();
        os.close();
        saved.add(label);
      }

      final ss = db.prepare('''INSERT INTO students(user_id, student_id, admission_no, firstname, lastname, othername, class_name, password_hash, pin, photo)
          VALUES (?,?,?,?,?,?,?,?,?,?)
          ON CONFLICT(user_id) DO UPDATE SET student_id=excluded.student_id, admission_no=excluded.admission_no,
            firstname=excluded.firstname, lastname=excluded.lastname, othername=excluded.othername,
            class_name=excluded.class_name, password_hash=excluded.password_hash, pin=excluded.pin,
            photo=COALESCE(excluded.photo, students.photo)''');
      final se = db.prepare('INSERT INTO student_exams(user_id, exam_id, done_online) VALUES (?,?,?) ON CONFLICT(user_id, exam_id) DO UPDATE SET done_online = excluded.done_online');
      for (final s in (pkg['students'] as List).cast<Map<String, dynamic>>()) {
        ss.execute([s['user_id'], s['student_id'], s['admission_no'], s['firstname'], s['lastname'], s['othername'],
          s['class_name'], s['password_hash'], s['pin'], s['photo']]);
        final done = ((s['done_online'] as List?) ?? const []).cast<int>().toSet();
        for (final ex in ((s['exam_ids'] as List?) ?? const []).cast<int>()) {
          se.execute([s['user_id'], ex, done.contains(ex) ? 1 : 0]);
        }
      }
      ss.close();
      se.close();
    });

    ensurePracticeExam();
    cdb.log('package', 'Downloaded ${saved.length} exam(s), ${(pkg['students'] as List).length} student(s)'
        '${kept.isNotEmpty ? '; kept ${kept.length} running exam(s) unchanged' : ''}.');
    return PackageImportResult(saved, kept, (pkg['students'] as List).length);
  }

  /// A short practice test every student can take to learn the exam screen.
  /// It is never uploaded to the portal. Opened/closed like any exam.
  void ensurePracticeExam() {
    final db = cdb.db;
    cdb.transaction(() {
      if (db.select('SELECT 1 FROM exams WHERE id = -1').isEmpty) {
        db.execute('''INSERT INTO exams(id, package_uuid, title, description, duration, subject, class_name, total_marks, question_count, is_open, show_score, shuffle, calculator)
                      VALUES (-1, NULL, 'Practice test (not recorded)', 'Try the exam screen before the real exam.', 10, 'Practice', 'All classes', 3, 3, 0, 1, 0, 'scientific')''');
        const qs = [
          [-101, 'mcq', 'Which of these is a <b>fruit</b>?', [['Mango', 1], ['Chair', 0], ['Pencil', 0], ['Shoe', 0]]],
          [-102, 'true_false', 'You can change an answer until you press <b>Submit</b>.', [['True', 1], ['False', 0]]],
          [-103, 'short_answer', 'Type the word <i>practice</i> in the box.', [['practice', 1]]],
        ];
        var oid = -1001;
        for (var i = 0; i < qs.length; i++) {
          final q = qs[i];
          db.execute('INSERT INTO questions(id, exam_id, ord, type, text, marks, image) VALUES (?,?,?,?,?,1,NULL)', [q[0], -1, i, q[1], q[2]]);
          for (final o in q[3] as List) {
            db.execute('INSERT INTO options(id, question_id, label, text, is_correct) VALUES (?,?,NULL,?,?)', [oid--, q[0], (o as List)[0], o[1]]);
          }
        }
      }
      db.execute('INSERT OR IGNORE INTO student_exams(user_id, exam_id, done_online) SELECT user_id, -1, 0 FROM students');
    });
  }

  /// Remove the copied portal passwords (students can then only use PINs).
  int clearPasswordHashes() {
    final n = cdb.db.select("SELECT COUNT(*) n FROM students WHERE password_hash IS NOT NULL AND password_hash <> ''").first['n'] as int;
    cdb.db.execute('UPDATE students SET password_hash = NULL');
    cdb.log('security', 'Removed $n saved portal password(s) from this computer');
    return n;
  }

  /// School info from the most recent package.
  Map<String, dynamic>? school() {
    final r = cdb.db.select('SELECT school_json FROM packages ORDER BY downloaded_at DESC LIMIT 1');
    return r.isEmpty ? null : jsonDecode(r.first['school_json'] as String) as Map<String, dynamic>?;
  }

  /// Remove an exam from this computer (only when every attempt is synced or there are none).
  String? deleteExam(int examId) {
    if (examId < 0) return 'The practice test cannot be removed. Close it instead.';
    final db = cdb.db;
    final unsynced = db.select("SELECT COUNT(*) n FROM attempts WHERE exam_id = ? AND sync_status NOT IN ('synced','conflict','rejected')", [examId]).first['n'] as int;
    if (unsynced > 0) return '$unsynced attempt(s) for this exam have not been uploaded yet. Sync first.';
    cdb.transaction(() {
      db.execute('DELETE FROM answers WHERE attempt_uuid IN (SELECT uuid FROM attempts WHERE exam_id = ?)', [examId]);
      db.execute('DELETE FROM attempts WHERE exam_id = ?', [examId]);
      db.execute('DELETE FROM options WHERE question_id IN (SELECT id FROM questions WHERE exam_id = ?)', [examId]);
      db.execute('DELETE FROM questions WHERE exam_id = ?', [examId]);
      db.execute('DELETE FROM student_exams WHERE exam_id = ?', [examId]);
      db.execute('DELETE FROM exams WHERE id = ?', [examId]);
    });
    return null;
  }
}
