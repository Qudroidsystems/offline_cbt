import 'package:flutter/material.dart';

import '../main.dart';
import 'common/theme.dart';

/// Launch animation: app icon, "Offline CBT", then "Qudroid Systems" letter by letter.
/// About 3 seconds; a click or key press skips it.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _left = false;

  static const _brand = 'Qudroid Systems';

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_go);
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) => const RootPage(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Value of the animation between [from] and [to] (0–1 of the whole), eased.
  double _seg(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, __) {
        _go();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: _go,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [brandNavy, Color(0xFF134E5E), brandTeal]),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final icon = _seg(0.0, 0.30, Curves.elasticOut);
                final iconFade = _seg(0.0, 0.12);
                final title = _seg(0.20, 0.42);
                final line = _seg(0.40, 0.55);
                final shimmer = _seg(0.72, 0.95, Curves.easeInOut);
                final out = 1 - _seg(0.92, 1.0, Curves.easeIn);
                return Opacity(
                  opacity: out,
                  child: Stack(children: [
                    // soft glow behind the icon
                    Center(
                      child: Transform.translate(
                        offset: const Offset(0, -70),
                        child: Container(
                          width: 320 * iconFade,
                          height: 320 * iconFade,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(colors: [Color(0x335EEAD4), Color(0x005EEAD4)]),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Opacity(
                          opacity: iconFade,
                          child: Transform.scale(
                            scale: 0.5 + 0.5 * icon,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset('assets/app_icon.png', width: 128, height: 128, filterQuality: FilterQuality.high),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Opacity(
                          opacity: title,
                          child: Transform.translate(
                            offset: Offset(0, 24 * (1 - title)),
                            child: const Text('Offline CBT',
                                style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // divider line that grows from the centre
                        Container(width: 220 * line, height: 2, color: const Color(0xFF5EEAD4)),
                        const SizedBox(height: 16),
                        Opacity(
                          opacity: line,
                          child: const Text('POWERED BY', style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 4)),
                        ),
                        const SizedBox(height: 6),
                        ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) => LinearGradient(
                            colors: const [Colors.white, Color(0xFFFDE68A), Colors.white],
                            stops: [
                              (shimmer - 0.2).clamp(0.0, 1.0),
                              shimmer,
                              (shimmer + 0.2).clamp(0.0, 1.0),
                            ],
                          ).createShader(r),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (var i = 0; i < _brand.length; i++) _letter(i),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Each letter of "Qudroid Systems" drops in, one after another.
  Widget _letter(int i) {
    final start = 0.48 + i * 0.016;
    final v = _seg(start, start + 0.12, Curves.easeOutBack);
    return Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -18 * (1 - v)),
        child: Text(_brand[i], style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ),
    );
  }
}
