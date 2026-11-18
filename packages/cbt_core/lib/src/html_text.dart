/// Turns the simple HTML used in portal questions (bold, italic, underline,
/// sup/sub, line breaks, paragraphs, lists, entities) into styled runs.
/// Anything else (unknown tags, scripts) is dropped safely.
class HtmlRun {
  HtmlRun(this.text, {this.bold = false, this.italic = false, this.underline = false, this.sup = false, this.sub = false});
  final String text;
  final bool bold, italic, underline, sup, sub;
}

List<HtmlRun> parseSimpleHtml(String? html) {
  final src = (html ?? '').replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '');
  final runs = <HtmlRun>[];
  var b = 0, i = 0, u = 0, sup = 0, sub = 0;
  final tag = RegExp(r'<\s*(/?)\s*([a-zA-Z0-9]+)[^>]*?(/?)\s*>');
  var pos = 0;

  void add(String t) {
    if (t.isEmpty) return;
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return;
    runs.add(HtmlRun(_entities(t), bold: b > 0, italic: i > 0, underline: u > 0, sup: sup > 0, sub: sub > 0));
  }

  void newline() {
    if (runs.isEmpty || runs.last.text.endsWith('\n')) return;
    runs.add(HtmlRun('\n'));
  }

  for (final m in tag.allMatches(src)) {
    add(src.substring(pos, m.start));
    pos = m.end;
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    final d = closing ? -1 : 1;
    switch (name) {
      case 'b' || 'strong': b = (b + d).clamp(0, 99);
      case 'i' || 'em': i = (i + d).clamp(0, 99);
      case 'u': u = (u + d).clamp(0, 99);
      case 'sup': sup = (sup + d).clamp(0, 99);
      case 'sub': sub = (sub + d).clamp(0, 99);
      case 'br': runs.add(HtmlRun('\n'));
      case 'p' || 'div' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'tr' || 'ul' || 'ol': newline();
      case 'li':
        if (!closing) {
          newline();
          runs.add(HtmlRun('• '));
        }
      case 'td' || 'th':
        if (closing) runs.add(HtmlRun('   '));
    }
  }
  add(src.substring(pos));
  // trim leading/trailing whitespace runs
  while (runs.isNotEmpty && runs.first.text.trim().isEmpty) {
    runs.removeAt(0);
  }
  while (runs.isNotEmpty && runs.last.text.trim().isEmpty) {
    runs.removeLast();
  }
  return runs;
}

/// Plain text version (for lists, logs).
String htmlToPlain(String? html) => parseSimpleHtml(html).map((r) => r.text).join().trim();

String _entities(String s) => s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 63);
      if (e.startsWith('#')) return String.fromCharCode(int.tryParse(e.substring(1)) ?? 63);
      return const {
            'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'times': '×', 'divide': '÷',
            'deg': '°', 'plusmn': '±', 'frac12': '½', 'frac14': '¼', 'frac34': '¾', 'pi': 'π', 'le': '≤', 'ge': '≥',
            'ne': '≠', 'naira': '₦', 'hellip': '…', 'ndash': '–', 'mdash': '—', 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“',
            'sup2': '²', 'sup3': '³', 'radic': '√', 'infin': '∞', 'alpha': 'α', 'beta': 'β', 'theta': 'θ', 'sigma': 'σ',
          }[e] ??
          m.group(0)!;
    });
