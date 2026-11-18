import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';

/// Connect this computer to csskabba-portal with a device key.
class PortalTab extends StatefulWidget {
  const PortalTab({super.key});
  @override
  State<PortalTab> createState() => _PortalTabState();
}

class _PortalTabState extends State<PortalTab> {
  final _url = TextEditingController(text: Services.I.portalUrl ?? 'https://');
  final _key = TextEditingController(text: Services.I.deviceKey ?? '');
  bool _busy = false;
  String? _status;
  bool _ok = false;

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    Services.I.savePortal(_url.text, _key.text);
    try {
      final r = await Services.I.portal()!.ping();
      _ok = true;
      _status = 'Connected to ${r['school']} as "${(r['device'] as Map)['name']}".';
      Services.I.latestVersion = r['latest_app_version'] as String?;
      Services.I.downloadUrl = r['download_url'] as String?;
      if (Services.I.updateAvailable) {
        _status = '$_status\nOffline CBT ${Services.I.latestVersion} is available (you have $appVersion)'
            '${Services.I.downloadUrl?.isNotEmpty == true ? ': ${Services.I.downloadUrl}' : '.'}';
      }
    } catch (e) {
      _ok = false;
      _status = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SectionTitle('Connect to the school portal'),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('On the portal go to Exams Management → Offline CBT, create a device key for this computer and paste it here. '
                  'Internet is only needed to download exams and to upload results.',
                  style: TextStyle(color: Colors.black54, height: 1.4)),
              const SizedBox(height: 16),
              TextField(controller: _url, decoration: const InputDecoration(labelText: 'Portal address', hintText: 'https://portal.yourschool.ng')),
              const SizedBox(height: 12),
              TextField(controller: _key, decoration: const InputDecoration(labelText: 'Device key', hintText: 'ocbt_…')),
              const SizedBox(height: 16),
              Row(children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
                  label: const Text('Save & test connection'),
                ),
              ]),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(children: [
                    Icon(_ok ? Icons.check_circle : Icons.error, color: _ok ? okGreen : badRed),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status!, style: TextStyle(color: _ok ? okGreen : badRed))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
