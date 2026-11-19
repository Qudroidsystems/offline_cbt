import 'package:sqlite3/sqlite3.dart';

/// Opens (and creates/upgrades) the offline CBT SQLite database.
///
/// The same schema is used on every computer: the admin/server PC fills the
/// exam tables; student PCs only use the `client_*` tables (their own copy of
/// answers, so nothing is lost if Wi-Fi or the server drops).
class CbtDb {
  CbtDb._(this.db);
  final Database db;

  static const schemaVersion = 3;

  factory CbtDb.open(String path) => CbtDb._(sqlite3.open(path))..migrate();
  factory CbtDb.memory() => CbtDb._(sqlite3.openInMemory())..migrate();

  void migrate() {
    db.execute('PRAGMA journal_mode = WAL');      // survives power cuts, concurrent readers
    db.execute('PRAGMA synchronous = FULL');
    db.execute('PRAGMA foreign_keys = ON');
    final v = db.select('PRAGMA user_version').first.values.first as int;
    if (v < 1) {
      db.execute('''
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);

        -- ── server (admin PC) ─────────────────────────────────────────
        CREATE TABLE IF NOT EXISTS packages (
          package_uuid TEXT PRIMARY KEY, checksum TEXT, downloaded_at TEXT,
          school_json TEXT, session_json TEXT, term_json TEXT);
        CREATE TABLE IF NOT EXISTS exams (
          id INTEGER PRIMARY KEY, package_uuid TEXT, title TEXT, description TEXT,
          duration INTEGER, start_time TEXT, end_time TEXT, term_id INTEGER, session_id INTEGER,
          subject TEXT, class_name TEXT, total_marks REAL, question_count INTEGER,
          is_open INTEGER NOT NULL DEFAULT 0, show_score INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS questions (
          id INTEGER PRIMARY KEY, exam_id INTEGER NOT NULL, ord INTEGER, type TEXT, text TEXT,
          marks REAL, image TEXT);
        CREATE INDEX IF NOT EXISTS ix_q_exam ON questions(exam_id);
        CREATE TABLE IF NOT EXISTS options (
          id INTEGER PRIMARY KEY, question_id INTEGER NOT NULL, label TEXT, text TEXT, is_correct INTEGER);
        CREATE INDEX IF NOT EXISTS ix_o_q ON options(question_id);
        CREATE TABLE IF NOT EXISTS students (
          user_id INTEGER PRIMARY KEY, student_id INTEGER, admission_no TEXT, firstname TEXT,
          lastname TEXT, othername TEXT, class_name TEXT, password_hash TEXT, pin TEXT);
        CREATE INDEX IF NOT EXISTS ix_s_adm ON students(admission_no COLLATE NOCASE);
        CREATE TABLE IF NOT EXISTS student_exams (
          user_id INTEGER NOT NULL, exam_id INTEGER NOT NULL, done_online INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (user_id, exam_id));
        CREATE TABLE IF NOT EXISTS attempts (
          uuid TEXT PRIMARY KEY, exam_id INTEGER NOT NULL, user_id INTEGER NOT NULL, package_uuid TEXT,
          workstation TEXT, status TEXT NOT NULL,                -- in_progress | submitted
          started_at TEXT NOT NULL, deadline INTEGER NOT NULL,   -- deadline: epoch ms
          submitted_at TEXT, submit_reason TEXT,                 -- student | time_up | admin
          extra_seconds INTEGER NOT NULL DEFAULT 0, updated_at TEXT,
          local_score REAL, local_total REAL,
          sync_status TEXT NOT NULL DEFAULT 'pending',           -- pending|synced|conflict|rejected|error
          sync_message TEXT, server_score REAL, server_total REAL, synced_at TEXT,
          UNIQUE (exam_id, user_id));
        CREATE TABLE IF NOT EXISTS answers (
          attempt_uuid TEXT NOT NULL, question_id INTEGER NOT NULL, answer TEXT, updated_at TEXT,
          PRIMARY KEY (attempt_uuid, question_id));
        CREATE TABLE IF NOT EXISTS sessions (
          token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, workstation TEXT,
          created_at TEXT, last_seen TEXT);
        CREATE TABLE IF NOT EXISTS sync_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, sent INTEGER, synced INTEGER,
          conflicts INTEGER, rejected INTEGER, errors INTEGER, message TEXT);
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, kind TEXT, message TEXT);

        -- ── student PC: local copy so answers survive Wi-Fi/server loss ──
        CREATE TABLE IF NOT EXISTS client_attempts (
          uuid TEXT PRIMARY KEY, server TEXT, exam_json TEXT, student_json TEXT,
          deadline_local INTEGER, status TEXT, submitted_locally INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT);
        CREATE TABLE IF NOT EXISTS client_answers (
          attempt_uuid TEXT NOT NULL, question_id INTEGER NOT NULL, answer TEXT,
          dirty INTEGER NOT NULL DEFAULT 1, updated_at TEXT,
          PRIMARY KEY (attempt_uuid, question_id));
      ''');
      db.execute('PRAGMA user_version = 1');
    }
    if (v < 2) {
      // v2: shuffling, pause, leaving-the-exam-window count, photos, computers list
      _addColumn('exams', 'shuffle INTEGER NOT NULL DEFAULT 1');
      _addColumn('exams', 'paused_at INTEGER');            // epoch ms while paused
      _addColumn('attempts', 'focus_lost INTEGER NOT NULL DEFAULT 0');
      _addColumn('students', 'photo TEXT');               // data URI thumbnail
      db.execute('''
        CREATE TABLE IF NOT EXISTS workstations (
          name TEXT PRIMARY KEY, ip TEXT, app_version TEXT, last_seen TEXT,
          user_id INTEGER, attempt_uuid TEXT);
      ''');
      db.execute('PRAGMA user_version = 2');
    }
    if (v < 3) {
      // v3: per-exam calculator: 'off' | 'basic' | 'scientific'
      _addColumn('exams', "calculator TEXT NOT NULL DEFAULT 'basic'");
      db.execute('PRAGMA user_version = 3');
    }
  }

  void _addColumn(String table, String def) {
    final name = def.split(' ').first;
    final cols = db.select('PRAGMA table_info($table)').map((r) => r['name']).toSet();
    if (!cols.contains(name)) db.execute('ALTER TABLE $table ADD COLUMN $def');
  }

  String? setting(String key) {
    final r = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setSetting(String key, String? value) {
    if (value == null) {
      db.execute('DELETE FROM settings WHERE key = ?', [key]);
    } else {
      db.execute('INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', [key, value]);
    }
  }

  void log(String kind, String message) {
    db.execute('INSERT INTO events(at, kind, message) VALUES(?, ?, ?)', [DateTime.now().toIso8601String(), kind, message]);
  }

  T transaction<T>(T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.close();
}
