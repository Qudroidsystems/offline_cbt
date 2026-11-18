import 'dart:async';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../common/widgets.dart';

class DonePage extends StatefulWidget {
  const DonePage({super.key, required this.session, required this.student});
  final ExamSession session;
  final Map<String, dynamic> student;
  @override
  State<DonePage> createState() => _DonePageState();
}

class _DonePageState extends State<DonePage> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    // keep the session alive until confirmed; it retries on its own
    if (widget.session.submitted) widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final confirmed = s.submitted;
    final r = s.submitResult;
    return PopScope(
      canPop: confirmed,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(confirmed ? Icons.check_circle_rounded : Icons.cloud_sync_rounded, size: 72, color: confirmed ? okGreen : warnAmber),
                  const SizedBox(height: 16),
                  Text(confirmed ? 'Exam submitted' : 'Submitting…',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy)),
                  const SizedBox(height: 8),
                  Text('${widget.student['name']} • ${s.exam['title']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 20),
                  if (confirmed && r?['score'] != null) ...[
                    const Text('Your score', style: TextStyle(color: Colors.black54)),
                    Text(fmtScore(r!['score'] as num?, r['total_marks'] as num?), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: teal)),
                    const Text('Provisional — the final result is confirmed by the school portal.', style: TextStyle(fontSize: 12, color: Colors.black45)),
                  ] else if (confirmed)
                    const Text('Your answers have been received.', textAlign: TextAlign.center)
                  else
                    const Text('The exam server cannot be reached right now. Your answers are safely stored on this computer and will be sent automatically.\n\n'
                        'Please do NOT switch off this computer. Tell the invigilator.',
                        textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
                  const SizedBox(height: 28),
                  if (confirmed)
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Finish'))
                  else
                    const LinearProgressIndicator(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
