import 'dart:convert';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import 'theme.dart';

/// Question / option text: the portal stores simple HTML.
class HtmlText extends StatelessWidget {
  const HtmlText(this.html, {super.key, this.style});
  final String? html;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(TextSpan(style: base, children: [
      for (final r in parseSimpleHtml(html))
        TextSpan(
          text: r.text,
          style: TextStyle(
            fontWeight: r.bold ? FontWeight.bold : null,
            fontStyle: r.italic ? FontStyle.italic : null,
            decoration: r.underline ? TextDecoration.underline : null,
            fontSize: (r.sup || r.sub) ? (base.fontSize ?? 14) * 0.7 : null,
            fontFeatures: r.sup ? const [FontFeature.superscripts()] : r.sub ? const [FontFeature.subscripts()] : null,
          ),
        ),
    ]));
  }
}

/// Image from a "data:image/png;base64,..." string.
class DataImage extends StatelessWidget {
  const DataImage(this.data, {super.key, this.maxHeight = 260});
  final String? data;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || !d.contains(',')) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(d.substring(d.indexOf(',') + 1));
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, fit: BoxFit.contain)),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

String fmtDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String fmtScore(num? s, num? t) {
  if (s == null || t == null) return '—';
  String f(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  return '${f(s)} / ${f(t)}';
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? badRed : null,
    behavior: SnackBarBehavior.floating,
    width: 520,
  ));
}

/// Asks for the invigilator password. Returns true when correct (or none is set).
Future<bool> askInvigilatorPassword(BuildContext context, {String title = 'Invigilator password'}) async {
  if (!Services.I.hasInvigilatorPassword) return true;
  final ctrl = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password', errorText: err),
            onSubmitted: (_) {
              if (Services.I.checkInvigilatorPassword(ctrl.text)) {
                Navigator.pop(ctx, true);
              } else {
                set(() => err = 'Wrong password');
              }
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (Services.I.checkInvigilatorPassword(ctrl.text)) {
                Navigator.pop(ctx, true);
              } else {
                set(() => err = 'Wrong password');
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color, this.icon});
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: color ?? teal, size: 28), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color ?? navy)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: navy))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Round student photo (data URI) with an initial-less placeholder.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.photo, this.size = 40});
  final String? photo;
  final double size;
  @override
  Widget build(BuildContext context) {
    final d = photo;
    if (d != null && d.contains(',')) {
      try {
        return ClipOval(child: Image.memory(base64Decode(d.substring(d.indexOf(',') + 1)), width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _blank()));
      } catch (_) {}
    }
    return _blank();
  }

  Widget _blank() => CircleAvatar(radius: size / 2, backgroundColor: const Color(0xFFE2E8F0), child: Icon(Icons.person, size: size * 0.6, color: Colors.white));
}
