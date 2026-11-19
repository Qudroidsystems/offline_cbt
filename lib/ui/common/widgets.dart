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

/// School logo + name (from the exam server's package).
class SchoolBrand extends StatelessWidget {
  const SchoolBrand({super.key, this.name, this.logo, this.subtitle, this.size = 40, this.center = false, this.nameStyle});
  final String? name;
  final String? logo;
  final String? subtitle;
  final double size;
  final bool center;
  final TextStyle? nameStyle;

  /// What a student computer last received from its exam server.
  factory SchoolBrand.cached({String? subtitle, double size = 40, bool center = false, TextStyle? nameStyle}) => SchoolBrand(
        name: Services.I.db.setting('school_name_cache'),
        logo: Services.I.db.setting('school_logo_cache'),
        subtitle: subtitle,
        size: size,
        center: center,
        nameStyle: nameStyle,
      );

  @override
  Widget build(BuildContext context) {
    final hasLogo = logo != null && logo!.contains(',');
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (name != null && name!.isNotEmpty)
          Text(name!, textAlign: center ? TextAlign.center : TextAlign.start, overflow: TextOverflow.ellipsis, maxLines: 2,
              style: nameStyle ?? TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: label, height: 1.15)),
        if (subtitle != null) Text(subtitle!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size * 0.3, color: label2)),
      ],
    );
    final img = hasLogo
        ? ClipRRect(borderRadius: BorderRadius.circular(size * 0.22), child: DataImage(logo, maxHeight: size))
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: const Color(0x1A007AFF), borderRadius: BorderRadius.circular(size * 0.22)),
            child: Icon(Icons.school_rounded, color: appleBlue, size: size * 0.6),
          );
    if (center) return Column(mainAxisSize: MainAxisSize.min, children: [img, SizedBox(height: size * 0.25), text]);
    return Row(mainAxisSize: MainAxisSize.min, children: [img, SizedBox(width: size * 0.3), Flexible(child: text)]);
  }
}

/// Colour for the time left: green, then orange under 25 %, red under 10 % or the last 2 minutes.
Color timeColor(Duration remaining, Duration total) {
  final frac = total.inSeconds <= 0 ? 0.0 : remaining.inSeconds / total.inSeconds;
  if (remaining.inSeconds <= 120 || frac <= 0.10) return badRed;
  if (frac <= 0.25) return warnAmber;
  return okGreen;
}

/// Countdown ring: empties as time passes, changes colour, pulses in the last minute.
class TimerRing extends StatefulWidget {
  const TimerRing({super.key, required this.remaining, required this.total, this.paused = false, this.size = 150});
  final Duration remaining;
  final Duration total;
  final bool paused;
  final double size;
  @override
  State<TimerRing> createState() => _TimerRingState();
}

class _TimerRingState extends State<TimerRing> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final frac = w.total.inSeconds <= 0 ? 0.0 : (w.remaining.inSeconds / w.total.inSeconds).clamp(0.0, 1.0);
    final color = w.paused ? label2 : timeColor(w.remaining, w.total);
    final lastMinute = !w.paused && w.remaining.inSeconds <= 60;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final glow = lastMinute ? 0.25 + 0.35 * _pulse.value : 0.0;
        return Container(
          width: w.size,
          height: w.size,
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
            if (glow > 0) BoxShadow(color: badRed.withAlpha((glow * 255).round()), blurRadius: 24, spreadRadius: 2),
          ]),
          child: CustomPaint(
            painter: _RingPainter(frac, color),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (w.paused) Icon(Icons.pause_rounded, color: label2, size: w.size * 0.16),
                Text(fmtDuration(w.remaining),
                    style: TextStyle(
                        fontSize: w.size * (w.remaining.inHours > 0 ? 0.17 : 0.21),
                        fontWeight: FontWeight.w700,
                        color: w.paused ? label2 : (color == okGreen ? label : color),
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: -0.5)),
                Text(w.paused ? 'PAUSED' : 'TIME LEFT',
                    style: TextStyle(fontSize: w.size * 0.075, color: label2, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color);
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(rect, 0, 6.2832, false, Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    if (frac > 0) {
      canvas.drawArc(rect, -1.5708, 6.2832 * frac, false, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.frac != frac || old.color != color;
}

/// Small rounded label (Apple-style "pill").
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = appleBlue, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
