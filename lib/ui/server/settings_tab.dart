import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../../app/services.dart';
import '../../app/sounds.dart';
import '../../main.dart';
import '../common/theme.dart';
import '../common/widgets.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _name = TextEditingController(text: Services.I.serverName);
  final _pw = TextEditingController();

  Future<void> _restore() async {
    final s = Services.I;
    final files = s.backups();
    final picked = await showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Restore which backup?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Everything on this computer goes back to that moment. The current data is backed up first.',
                style: TextStyle(color: Colors.black54)),
          ),
          SizedBox(
            width: 480,
            height: 360,
            child: ListView(children: [
              for (final f in files)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(p.basename(f.path)),
                  subtitle: Text('${f.lastModifiedSync().toString().split('.').first} • ${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ]),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (!await askInvigilatorPassword(context, title: 'Invigilator password to restore')) return;
    final err = await s.restore(picked);
    if (!mounted) return;
    if (err != null) return toast(context, err, error: true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup restored'),
        content: const Text('Offline CBT will now close. Open it again to continue with the restored data.'),
        actions: [FilledButton(onPressed: () => windowManager.destroy(), child: const Text('Close app'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final backups = Directory(p.join(s.dataDir, 'backups'));
    final count = backups.existsSync() ? backups.listSync().whereType<File>().length : 0;
    final events = s.db.db.select('SELECT * FROM events ORDER BY id DESC LIMIT 40');
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SectionTitle('Settings'),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Exam server name (shown to student computers)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: _name)),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      s.serverName = _name.text.isEmpty ? 'Exam server' : _name.text;
                      s.server?.serverName = s.serverName;
                      s.announcer?.name = s.serverName;
                      toast(context, 'Saved');
                    },
                    child: const Text('Save'),
                  ),
                ]),
                const SizedBox(height: 20),
                const Text('Change invigilator password', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'New password'))),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      if (_pw.text.length < 4) return toast(context, 'At least 4 characters', error: true);
                      if (!await askInvigilatorPassword(context, title: 'Current invigilator password')) return;
                      s.setInvigilatorPassword(_pw.text);
                      _pw.clear();
                      if (context.mounted) toast(context, 'Password changed. Set the same one on student computers.');
                    },
                    child: const Text('Change'),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Sounds', style: TextStyle(fontWeight: FontWeight.w600)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.exams.studentSounds,
                  onChanged: (v) => setState(() => s.exams.studentSounds = v),
                  title: const Text('Sounds on student computers'),
                  subtitle: const Text('Login, exam start, 5-minute and 1-minute warnings, last-10-seconds countdown, time up, submitted, pause/resume, Wi-Fi lost/back.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.adminSounds,
                  onChanged: (v) => setState(() {
                    s.adminSounds = v;
                    Sounds.enabled = v;
                  }),
                  title: const Text('Alert sounds on this computer'),
                  subtitle: const Text('When a student submits, or leaves the exam window.'),
                ),
                const Divider(height: 28),
                const Text('How students log in', style: TextStyle(fontWeight: FontWeight.w600)),
                RadioListTile<String>(
                  value: 'both',
                  groupValue: s.loginMode,
                  onChanged: (v) => setState(() => s.loginMode = v!),
                  title: const Text('Portal password or exam PIN'),
                  subtitle: const Text('Students\' password hashes are downloaded with the exams (they cannot be read back as passwords).'),
                ),
                RadioListTile<String>(
                  value: 'pin',
                  groupValue: s.loginMode,
                  onChanged: (v) async {
                    if (!await askInvigilatorPassword(context)) return;
                    setState(() => s.loginMode = v!);
                    if (context.mounted) toast(context, 'PIN only. Saved passwords were removed from this computer and will not be downloaded again.');
                  },
                  title: const Text('Exam PIN only (most secure)'),
                  subtitle: const Text('No passwords are kept on this computer. Print PIN slips from the portal.'),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (!await askInvigilatorPassword(context)) return;
                      final n = s.store.clearPasswordHashes();
                      if (context.mounted) toast(context, 'Removed $n saved password(s). Students can still use PINs; download the exams again to restore passwords.');
                    },
                    icon: const Icon(Icons.no_encryption_gmailerrorred_outlined),
                    label: const Text('Remove saved passwords now'),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Good practice after the exams are uploaded.', style: TextStyle(fontSize: 12, color: Colors.black54))),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Backups', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('A copy of all exams and answers is saved every 10 minutes while the server runs, and before every sync. '
                    '$count backup(s) in ${backups.path}', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      final f = s.backup();
                      toast(context, f == null ? 'Backup failed' : 'Saved $f', error: f == null);
                      setState(() {});
                    },
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Back up now'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: count == 0 ? null : _restore,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('Restore a backup…'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(onPressed: () => Services.openPath(backups.path), child: const Text('Open folder')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Computer role', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('This computer is the EXAM SERVER. Change it only if exams here are all uploaded.', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton(
                    onPressed: () async {
                      final pending = s.sync.counts();
                      if (pending['in_progress']! + pending['pending']! + pending['error']! > 0) {
                        return toast(context, 'Some attempts are still running or not uploaded. Sync first.', error: true);
                      }
                      if (!await askInvigilatorPassword(context)) return;
                      await s.stopServer();
                      s.mode = null;
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RootPage()), (_) => false);
                    },
                    child: const Text('Change role'),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Activity log'),
          Card(
            child: Column(children: [
              for (final e in events)
                ListTile(
                  dense: true,
                  title: Text('${e['message']}'),
                  subtitle: Text('${e['kind']} • ${'${e['at']}'.replaceFirst('T', ' ').split('.').first}'),
                ),
              if (events.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing yet.')),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Data folder: ${s.dataDir}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
          const Text('Offline CBT $appVersion', style: TextStyle(fontSize: 12, color: navy)),
        ]),
      ),
    ]);
  }
}
