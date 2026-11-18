import 'dart:convert';

/// Dart copy of the portal's App\Services\OfflineCbt\CbtMarker, so the admin
/// sees provisional scores offline. The portal re-marks every attempt on sync
/// and its score is the official one.
class MarkResult {
  MarkResult(this.score, this.total, this.attempted);
  final double score;
  final double total;
  final int attempted;
}

class MarkQuestion {
  MarkQuestion(this.id, this.type, this.marks, this.options);
  final int id;
  final String type; // mcq | true_false | short_answer
  final double marks;
  final List<MarkOption> options;
}

class MarkOption {
  MarkOption(this.text, this.isCorrect);
  final String text;
  final bool isCorrect;
}

/// Same rules as the portal: every question in the exam counts towards the
/// total; options match on exact text; short answers match case-insensitively
/// or with ≥80% similarity (PHP similar_text).
MarkResult markAttempt(List<MarkQuestion> questions, Map<int, String?> answers) {
  var total = 0.0, score = 0.0;
  var attempted = 0;
  for (final q in questions) {
    total += q.marks;
    final a = (answers[q.id] ?? '').trim();
    if (a.isEmpty) continue;
    attempted++;
    if (q.type == 'short_answer') {
      final correct = q.options.where((o) => o.isCorrect).firstOrNull;
      if (correct == null) continue;
      final x = a.toLowerCase(), y = correct.text.trim().toLowerCase();
      if (x == y || similarTextPercent(x, y) >= 80) score += q.marks;
    } else {
      final sel = q.options.where((o) => o.text.trim() == a).firstOrNull;
      if (sel != null && sel.isCorrect) score += q.marks;
    }
  }
  return MarkResult(score, total, attempted);
}

/// PHP similar_text() percentage (Oliver's algorithm), on UTF-8 bytes like PHP.
double similarTextPercent(String a, String b) {
  final s1 = utf8.encode(a), s2 = utf8.encode(b);
  if (s1.isEmpty && s2.isEmpty) return 0;
  int sim(int p1, int e1, int p2, int e2) {
    var max = 0, pos1 = 0, pos2 = 0;
    for (var i = p1; i < e1; i++) {
      for (var j = p2; j < e2; j++) {
        var k = 0;
        while (i + k < e1 && j + k < e2 && s1[i + k] == s2[j + k]) {
          k++;
        }
        if (k > max) {
          max = k;
          pos1 = i;
          pos2 = j;
        }
      }
    }
    if (max == 0) return 0;
    return max + sim(p1, pos1, p2, pos2) + sim(pos1 + max, e1, pos2 + max, e2);
  }

  final s = sim(0, s1.length, 0, s2.length);
  return s * 2 * 100 / (s1.length + s2.length);
}
