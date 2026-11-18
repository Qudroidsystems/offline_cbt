import 'package:flutter/material.dart';

import '../app/services.dart';
import '../main.dart';
import 'common/theme.dart';

/// First run: is this the exam server (admin computer) or a student computer?
class ModeSelectPage extends StatefulWidget {
  const ModeSelectPage({super.key});
  @override
  State<ModeSelectPage> createState() => _ModeSelectPageState();
}

class _ModeSelectPageState extends State<ModeSelectPage> {
  final _name = TextEditingController(text: Services.I.workstation);
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _err;

  Future<void> _choose(String mode) async {
    final s = Services.I;
    if (!s.hasInvigilatorPassword) {
      if (_pw.text.length < 4) return setState(() => _err = 'Choose an invigilator password of at least 4 characters.');
      if (_pw.text != _pw2.text) return setState(() => _err = 'The two passwords do not match.');
      s.setInvigilatorPassword(_pw.text);
    }
    s.workstation = _name.text;
    if (mode == 'server') s.serverName = _name.text.isEmpty ? 'Exam server' : _name.text;
    s.mode = mode;
    if (mode == 'server') {
      s.store.ensurePracticeExam();
      await s.startServer();
      s.startAutoSync();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RootPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final needPw = !Services.I.hasInvigilatorPassword;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: teal),
              const SizedBox(height: 8),
              const Text('Offline CBT', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: navy)),
              const Text('Run CBT exams on your school Wi-Fi — no internet needed during the exam.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name of this computer', hintText: 'e.g. ICT Lab PC 05')),
                    if (needPw) ...[
                      const SizedBox(height: 14),
                      const Text('Invigilator password — needed to leave an exam screen or change this computer\'s role. Use the same one on every computer.',
                          style: TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Invigilator password'))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: _pw2, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat password'))),
                      ]),
                    ],
                    if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: badRed))),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _RoleCard(
                    icon: Icons.dns_rounded,
                    title: 'Exam server',
                    subtitle: 'The admin / invigilator computer. Downloads exams from the portal, runs the exam on the Wi-Fi and uploads results.',
                    onTap: () => _choose('server'),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _RoleCard(
                    icon: Icons.computer_rounded,
                    title: 'Student computer',
                    subtitle: 'Students log in here and write the exam. Connects to the exam server over Wi-Fi.',
                    onTap: () => _choose('student'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 40, color: teal),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: navy)),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Colors.black54, height: 1.4)),
              const SizedBox(height: 16),
              const Row(children: [Text('Use this computer for this', style: TextStyle(color: teal)), Icon(Icons.arrow_forward, color: teal, size: 18)]),
            ]),
          ),
        ),
      );
}
