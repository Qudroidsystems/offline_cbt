import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'exam_service.dart';

/// HTTP API the student computers use over Wi-Fi.
///
///   GET  /api/hello                         server name, school, version
///   GET  /api/school                        school name + logo (data URI)
///   POST /api/login {admission_no, secret, workstation}
///   GET  /api/me/exams                      (Bearer token)
///   POST /api/exams/<id>/start
///   PUT  /api/attempts/<uuid>/answers       {answers: [{question_id, answer, client_remaining_ms}]}
///   POST /api/attempts/<uuid>/submit        {answers: [...], reason}
///   GET  /api/attempts/<uuid>                heartbeat: time left, paused, submitted
///   POST /api/attempts/<uuid>/focus-lost     student left the exam window
///   POST /api/logout
class LocalServer {
  LocalServer(this.exams, {required this.serverName, required this.schoolName, this.version = '1.0.0', this.schoolLogo});

  final ExamService exams;
  String serverName;
  String schoolName;
  final String version;
  /// Returns the school logo as a data URI (from the latest exam package).
  final String? Function()? schoolLogo;

  HttpServer? _http;
  Timer? _ticker;
  final _clients = <String, DateTime>{}; // workstation -> last request
  int get port => _http?.port ?? 0;
  bool get running => _http != null;

  /// Workstations seen in the last 2 minutes.
  Map<String, DateTime> get activeClients {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    _clients.removeWhere((_, t) => t.isBefore(cutoff));
    return Map.unmodifiable(_clients);
  }

  Future<void> start({int port = 47810, InternetAddress? address}) async {
    if (_http != null) return;
    final handler = const Pipeline().addMiddleware(_errors()).addMiddleware(_track()).addHandler(_router().call);
    _http = await io.serve(handler, address ?? InternetAddress.anyIPv4, port, shared: false);
    _http!.autoCompress = true;
    // Close attempts whose time is up even if nobody is calling in.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        exams.autoSubmitExpired();
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    await _http?.close(force: true);
    _http = null;
  }

  Router _router() {
    final r = Router();

    r.get('/api/hello', (Request req) => _json({
          'app': 'offline_cbt', 'server_name': serverName, 'school': schoolName, 'version': version,
          'server_time': DateTime.now().toIso8601String(),
        }));

    // School name + logo for the student login screens (logo sent once, not with every hello).
    r.get('/api/school', (Request req) => _json({'name': schoolName, 'logo': schoolLogo?.call(), 'sounds': exams.studentSounds}));

    r.post('/api/login', (Request req) async {
      final b = await _body(req);
      final res = exams.login('${b['admission_no'] ?? ''}', '${b['secret'] ?? ''}', _ws(req, b));
      return _json(res);
    });

    r.post('/api/logout', (Request req) {
      final t = _token(req);
      if (t != null) exams.logout(t);
      return _json({'ok': true});
    });

    r.get('/api/me/exams', (Request req) {
      final uid = exams.userFor(_token(req));
      return _json({'exams': exams.examsFor(uid)});
    });

    r.post('/api/exams/<id|[0-9]+>/start', (Request req, String id) async {
      final uid = exams.userFor(_token(req));
      final b = await _body(req);
      return _json(exams.start(uid, int.parse(id), _ws(req, b)));
    });

    r.put('/api/attempts/<uuid>/answers', (Request req, String uuid) async {
      final uid = exams.userFor(_token(req));
      final b = await _body(req);
      return _json(exams.saveAnswers(uid, uuid, _answers(b)));
    });

    r.post('/api/attempts/<uuid>/submit', (Request req, String uuid) async {
      final uid = exams.userFor(_token(req));
      final b = await _body(req);
      final reason = b['reason'] == 'time_up' ? 'time_up' : 'student';
      return _json(exams.submit(uid, uuid, _answers(b), reason: reason));
    });

    r.get('/api/attempts/<uuid>', (Request req, String uuid) {
      final uid = exams.userFor(_token(req));
      return _json(exams.status(uid, uuid));
    });

    r.post('/api/attempts/<uuid>/focus-lost', (Request req, String uuid) {
      final uid = exams.userFor(_token(req));
      return _json({'count': exams.recordFocusLost(uid, uuid)});
    });

    r.all('/<ignored|.*>', (Request req) => _json({'message': 'Not found'}, status: 404));
    return r;
  }

  // ── plumbing ─────────────────────────────────────────────────────────

  Middleware _errors() => (inner) => (req) async {
        try {
          return await inner(req);
        } on CbtError catch (e) {
          return _json({'code': e.code, 'message': e.message}, status: e.status);
        } on FormatException catch (_) {
          return _json({'code': 'bad_request', 'message': 'Bad request.'}, status: 400);
        } catch (e) {
          stderr.writeln('offline_cbt server error: $e');
          return _json({'code': 'server_error', 'message': 'Server error: $e'}, status: 500);
        }
      };

  Middleware _track() => (inner) => (req) {
        final ws = req.headers['x-workstation'];
        if (ws != null && ws.isNotEmpty) {
          final now = DateTime.now();
          final last = _clients[ws];
          _clients[ws] = now;
          // Readiness list: name, IP, app version (written at most every 10 s per computer).
          if (last == null || now.difference(last).inSeconds >= 10) {
            final ip = (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '';
            try {
              exams.touchWorkstation(ws.length > 100 ? ws.substring(0, 100) : ws, ip, req.headers['x-app-version']);
            } catch (_) {}
          }
        }
        return inner(req);
      };

  static Response _json(Object body, {int status = 200}) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});

  static Future<Map<String, dynamic>> _body(Request req) async {
    final s = await req.readAsString();
    if (s.trim().isEmpty) return {};
    final d = jsonDecode(s);
    if (d is! Map<String, dynamic>) throw const FormatException('expected object');
    return d;
  }

  static List<Map<String, dynamic>> _answers(Map<String, dynamic> b) =>
      ((b['answers'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  static String? _token(Request req) {
    final h = req.headers['authorization'];
    if (h == null || !h.toLowerCase().startsWith('bearer ')) return null;
    return h.substring(7).trim();
  }

  static String _ws(Request req, Map<String, dynamic> b) {
    final w = (b['workstation'] ?? req.headers['x-workstation'] ?? '').toString().trim();
    final ip = (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '';
    final name = w.isEmpty ? ip : w;
    return name.length > 100 ? name.substring(0, 100) : name;
  }
}
