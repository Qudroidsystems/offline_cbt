import 'dart:convert';

import 'package:http/http.dart' as http;

class PortalError implements Exception {
  PortalError(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Talks to csskabba-portal: /api/offline-cbt/v1/...
class PortalClient {
  PortalClient({required String baseUrl, required this.deviceKey, this.appVersion = '1.0.0', http.Client? client})
      : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final String deviceKey;
  final String appVersion;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl/api/offline-cbt/v1/$path').replace(queryParameters: q);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $deviceKey',
        'X-Offline-Cbt-Version': appVersion,
      };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 60)}) async {
    http.Response r;
    try {
      r = await call().timeout(timeout);
    } catch (e) {
      throw PortalError('Cannot reach the portal. Check the internet connection. ($e)');
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 400 || body == null) {
      final msg = body?['message'] ?? 'Portal error ${r.statusCode}';
      throw PortalError('$msg', status: r.statusCode);
    }
    return body;
  }

  Future<Map<String, dynamic>> ping() => _send(() => _http.get(_u('ping'), headers: _headers), timeout: const Duration(seconds: 20));

  Future<Map<String, dynamic>> exams({int? sessionId, int? termId, String? search}) => _send(() => _http.get(
      _u('exams', {
        if (sessionId != null) 'session_id': '$sessionId',
        if (termId != null) 'term_id': '$termId',
        if (search != null && search.isNotEmpty) 'search': search,
      }),
      headers: _headers));

  /// [includePasswords] false = PIN-only login: no password hashes are downloaded.
  Future<Map<String, dynamic>> package(List<int> examIds, {bool includePasswords = true}) async {
    final b = await _send(() => _http.post(_u('package'), headers: _headers,
            body: jsonEncode({'exam_ids': examIds, 'include_passwords': includePasswords})),
        timeout: const Duration(minutes: 5));
    return b['package'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadAttempts(List<Map<String, dynamic>> attempts) =>
      _send(() => _http.post(_u('attempts'), headers: _headers, body: jsonEncode({'attempts': attempts})),
          timeout: const Duration(minutes: 3));

  Future<Map<String, dynamic>> attemptStatus(List<String> uuids) =>
      _send(() => _http.post(_u('attempts/status'), headers: _headers, body: jsonEncode({'attempt_uuids': uuids})));
}
