import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cbt_core/cbt_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const appVersion = '1.0.0';

/// Where the app keeps its database and backups.
String appDataDir() {
  final env = Platform.environment;
  if (Platform.isWindows) return p.join(env['APPDATA'] ?? env['USERPROFILE'] ?? '.', 'OfflineCBT');
  if (Platform.isMacOS) return p.join(env['HOME'] ?? '.', 'Library', 'Application Support', 'OfflineCBT');
  return p.join(env['HOME'] ?? '.', '.local', 'share', 'OfflineCBT');
}

/// Everything the screens need, created once at start-up.
class Services {
  Services(this.db, this.dataDir)
      : store = ExamStore(db),
        exams = ExamService(db),
        sync = SyncService(db);

  static late Services I;

  final CbtDb db;
  final String dataDir;
  final ExamStore store;
  final ExamService exams;
  final SyncService sync;

  LocalServer? server;
  DiscoveryAnnouncer? announcer;
  Timer? _backupTimer;
  String? serverError;

  // ── settings ───────────────────────────────────────────────────────
  String? get mode => db.setting('mode'); // 'server' | 'student'
  set mode(String? v) => db.setSetting('mode', v);

  String get workstation => db.setting('workstation') ?? Platform.localHostname;
  set workstation(String v) => db.setSetting('workstation', v.trim().isEmpty ? null : v.trim());

  String get serverName => db.setting('server_name') ?? 'Exam server';
  set serverName(String v) => db.setSetting('server_name', v.trim());

  int get serverPort => int.tryParse(db.setting('server_port') ?? '') ?? 47810;

  String? get portalUrl => db.setting('portal_url');
  String? get deviceKey => db.setting('device_key');
  void savePortal(String url, String key) {
    db.setSetting('portal_url', url.trim());
    db.setSetting('device_key', key.trim());
  }

  PortalClient? portal() {
    final u = portalUrl, k = deviceKey;
    if (u == null || u.isEmpty || k == null || k.isEmpty) return null;
    return PortalClient(baseUrl: u, deviceKey: k, appVersion: appVersion);
  }

  /// Invigilator password: needed to change mode or leave an exam screen on student computers.
  bool get hasInvigilatorPassword => db.setting('invigilator_pw') != null;
  void setInvigilatorPassword(String pw) => db.setSetting('invigilator_pw', _hash(pw));
  bool checkInvigilatorPassword(String pw) => !hasInvigilatorPassword || db.setting('invigilator_pw') == _hash(pw);
  String _hash(String s) => sha256.convert(utf8.encode('offline-cbt:$s')).toString();

  String get schoolName => (store.school()?['name'] as String?) ?? 'School';
  String? get schoolLogo => store.school()?['logo'] as String?;

  /// Alert sounds on the admin computer (submissions, students leaving the exam window).
  bool get adminSounds => db.setting('admin_sounds') != '0';
  set adminSounds(bool v) => db.setSetting('admin_sounds', v ? '1' : '0');

  // ── login mode & passwords ─────────────────────────────────────────
  /// 'both' = portal password or PIN, 'pin' = PIN only (no passwords downloaded).
  String get loginMode => exams.loginMode;
  set loginMode(String v) {
    exams.loginMode = v;
    if (v == 'pin') store.clearPasswordHashes();
  }

  // ── auto-sync & updates ────────────────────────────────────────────
  bool get autoSync => db.setting('auto_sync') != '0';
  set autoSync(bool v) => db.setSetting('auto_sync', v ? '1' : '0');
  Timer? _autoSyncTimer;
  bool syncing = false;
  String? lastAutoSync;

  /// Latest app version the portal advertises (null until checked).
  String? latestVersion;
  String? downloadUrl;
  bool get updateAvailable => latestVersion != null && _cmp(latestVersion!, appVersion) > 0;

  static int _cmp(String a, String b) {
    final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList(), y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// One sync run, guarded so manual and automatic syncs never overlap.
  Future<SyncSummary?> runSync({void Function(int, int)? onProgress}) async {
    final portal = this.portal();
    if (portal == null || syncing) return null;
    syncing = true;
    try {
      backup();
      final r = await sync.syncAll(portal, onProgress: onProgress);
      try {
        await sync.refreshConflicts(portal);
      } catch (_) {}
      return r;
    } finally {
      syncing = false;
    }
  }

  /// Every 5 minutes: upload anything waiting as soon as the internet is back.
  void startAutoSync() {
    _autoSyncTimer ??= Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!autoSync || sync.pendingCount() == 0) return;
      final r = await runSync();
      if (r != null && r.error == null && r.sent > 0) lastAutoSync = '${DateTime.now().toString().substring(11, 16)} — $r';
    });
    checkForUpdate();
  }

  Future<void> checkForUpdate() async {
    try {
      final r = await portal()?.ping();
      if (r == null) return;
      latestVersion = r['latest_app_version'] as String?;
      downloadUrl = r['download_url'] as String?;
    } catch (_) {}
  }

  // ── reports ────────────────────────────────────────────────────────
  /// Writes the results of [examId] as CSV (Excel) and printable HTML; returns the files.
  List<String> exportResults(int examId) {
    final rep = ResultsReport.build(db, examId, school: schoolName);
    final dir = Directory(p.join(_documents(), 'Offline CBT Results'))..createSync(recursive: true);
    final name = '${htmlToPlain(rep.exam['title'] as String?)} ${rep.exam['class_name'] ?? ''}'
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final base = p.join(dir.path, name.isEmpty ? 'exam_$examId' : name);
    File('$base.csv').writeAsStringSync(rep.toCsv());
    File('$base.html').writeAsStringSync(rep.toHtml());
    return ['$base.csv', '$base.html'];
  }

  String _documents() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'] ?? dataDir;
    final docs = p.join(home, 'Documents');
    return Directory(docs).existsSync() ? docs : dataDir;
  }

  /// Open a file or folder with the computer's default program.
  static Future<void> openPath(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  // ── restore ────────────────────────────────────────────────────────
  List<File> backups() {
    final dir = Directory(p.join(dataDir, 'backups'));
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Replace the database with [backupFile]. The current data is backed up first.
  /// The app must be restarted afterwards (returns an error message or null).
  Future<String?> restore(File backupFile) async {
    final safety = backup(to: p.join(dataDir, 'backups', 'before_restore_${DateTime.now().millisecondsSinceEpoch}.db'));
    if (safety == null) return 'Could not back up the current data first, so nothing was changed.';
    await stopServer();
    final dbPath = p.join(dataDir, 'offline_cbt.db');
    db.close();
    for (final ext in ['-wal', '-shm']) {
      final f = File('$dbPath$ext');
      if (f.existsSync()) f.deleteSync();
    }
    backupFile.copySync(dbPath);
    return null;
  }

  // ── exam server (admin computer) ───────────────────────────────────
  Future<void> startServer() async {
    if (server?.running == true) return;
    serverError = null;
    final s = LocalServer(exams, serverName: serverName, schoolName: schoolName, version: appVersion,
        schoolLogo: () => store.school()?['logo'] as String?);
    try {
      await s.start(port: serverPort);
    } catch (e) {
      serverError = 'Could not start the exam server on port $serverPort: $e';
      return;
    }
    server = s;
    announcer = DiscoveryAnnouncer(httpPort: s.port, name: serverName, school: schoolName);
    try {
      await announcer!.start();
    } catch (_) {
      // Discovery is a convenience; students can still type the address.
    }
    _backupTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => backup());
  }

  Future<void> stopServer() async {
    announcer?.stop();
    announcer = null;
    await server?.stop();
    server = null;
  }

  /// Consistent copy of the database (safe while the server is running).
  String? backup({String? to}) {
    try {
      final dir = Directory(p.join(dataDir, 'backups'))..createSync(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
      final file = to ?? p.join(dir.path, 'offline_cbt_$stamp.db');
      if (File(file).existsSync()) File(file).deleteSync();
      db.db.execute('VACUUM INTO ?', [file]);
      // keep the 30 most recent automatic backups
      if (to == null) {
        final all = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final old in all.skip(30)) {
          old.deleteSync();
        }
      }
      return file;
    } catch (e) {
      db.log('backup', 'Backup failed: $e');
      return null;
    }
  }
}
