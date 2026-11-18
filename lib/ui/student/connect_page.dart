import 'dart:async';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../main.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'login_page.dart';

/// Student computer: find the exam server on the Wi-Fi.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _listener = DiscoveryListener();
  final _found = <FoundServer>{};
  StreamSubscription<FoundServer>? _sub;
  final _manual = TextEditingController(text: Services.I.db.setting('last_server_manual') ?? '');
  bool _trying = false;
  String? _err;
  int _pendingSubmits = 0;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
    _flushPending();
  }

  Future<void> _startDiscovery() async {
    try {
      await _listener.start();
      _sub = _listener.servers.listen((s) {
        if (mounted && _found.add(s)) setState(() {});
      });
    } catch (_) {
      // Port busy or blocked by firewall: manual address still works.
    }
  }

  /// Submissions made while the server was unreachable (even before a restart).
  Future<void> _flushPending() async {
    final left = await flushPendingSubmissions(Services.I.db, Services.I.workstation);
    if (mounted) setState(() => _pendingSubmits = left);
    if (left > 0) Timer(const Duration(seconds: 10), () => mounted ? _flushPending() : null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _listener.stop();
    super.dispose();
  }

  Future<void> _connect(String baseUrl) async {
    setState(() {
      _trying = true;
      _err = null;
    });
    try {
      final hello = await ServerClient(baseUrl, workstation: Services.I.workstation, appVersion: appVersion).hello();
      if (hello['app'] != 'offline_cbt') throw ServerError('That is not an Offline CBT server.');
      if (hello['version'] != appVersion && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Different app versions'),
            content: Text('The exam server runs Offline CBT ${hello['version']} but this computer has $appVersion. '
                'Install the same version on every computer to avoid problems.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect anyway')),
            ],
          ),
        );
        if (go != true) throw ServerError('Not connected.');
      }
      Services.I.db.setSetting('last_server', baseUrl);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginPage(serverUrl: baseUrl)));
    } catch (e) {
      _err = 'Could not connect: $e';
    }
    if (mounted) setState(() => _trying = false);
  }

  String _normalise(String s) {
    var v = s.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http')) v = 'http://$v';
    final u = Uri.tryParse(v);
    if (u != null && !u.hasPort) v = '${u.scheme}://${u.host}:47810';
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final last = Services.I.db.setting('last_server');
    return Scaffold(
      appBar: AppBar(
        title: Text('Offline CBT — ${Services.I.workstation}'),
        actions: [
          IconButton(
            tooltip: 'Computer settings (invigilator)',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              if (!await askInvigilatorPassword(context)) return;
              if (context.mounted) await _settings(context);
              setState(() {});
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.wifi_find_rounded, size: 52, color: teal),
              const SizedBox(height: 8),
              const Text('Connect to the exam server', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: navy)),
              const Text('Make sure this computer is on the same Wi-Fi as the invigilator\'s computer.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              if (_pendingSubmits > 0)
                Card(
                  color: const Color(0xFFFFF7ED),
                  margin: const EdgeInsets.only(top: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('$_pendingSubmits submitted exam(s) on this computer are waiting for the server. Do not switch off this computer; they will be sent automatically.'),
                  ),
                ),
              const SizedBox(height: 24),
              Card(
                child: Column(children: [
                  ListTile(
                    title: const Text('Exam servers found on this network', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: _found.isEmpty ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  ),
                  if (_found.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Searching… (or type the address below)')),
                  for (final s in _found)
                    ListTile(
                      leading: const Icon(Icons.dns, color: teal),
                      title: Text(s.name),
                      subtitle: Text('${s.school} • ${s.address}'),
                      trailing: FilledButton(onPressed: _trying ? null : () => _connect(s.baseUrl), child: const Text('Connect')),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        decoration: const InputDecoration(labelText: 'Server address', hintText: 'e.g. 192.168.1.20'),
                        onSubmitted: (_) {
                          Services.I.db.setSetting('last_server_manual', _manual.text.trim());
                          _connect(_normalise(_manual.text));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _trying
                          ? null
                          : () {
                              Services.I.db.setSetting('last_server_manual', _manual.text.trim());
                              _connect(_normalise(_manual.text));
                            },
                      child: const Text('Connect'),
                    ),
                  ]),
                ),
              ),
              if (last != null)
                TextButton(onPressed: _trying ? null : () => _connect(last), child: Text('Reconnect to $last')),
              if (_trying) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: badRed), textAlign: TextAlign.center)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _settings(BuildContext context) async {
    final name = TextEditingController(text: Services.I.workstation);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This computer'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Computer name (shown to the invigilator)')),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Services.I.mode = null;
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RootPage()), (_) => false);
            },
            child: const Text('Change role'),
          ),
          FilledButton(
            onPressed: () {
              Services.I.workstation = name.text;
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
