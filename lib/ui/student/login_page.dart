import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'exam_list_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.serverUrl, this.allowBack = true});
  final String serverUrl;
  final bool allowBack;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _adm = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _err;
  String _school = '';
  String? _logo;

  @override
  void initState() {
    super.initState();
    _school = Services.I.db.setting('school_name_cache') ?? '';
    _logo = Services.I.db.setting('school_logo_cache');
    ServerClient(widget.serverUrl, workstation: Services.I.workstation, appVersion: appVersion).school().then((h) {
      // cached so the logo shows instantly next time
      Services.I.db.setSetting('school_name_cache', '${h['name']}');
      Services.I.db.setSetting('school_logo_cache', h['logo'] as String?);
      if (mounted) setState(() {
        _school = '${h['name']}';
        _logo = h['logo'] as String?;
      });
    }).catchError((_) {});
  }

  Future<void> _login() async {
    if (_adm.text.trim().isEmpty || _secret.text.isEmpty) return setState(() => _err = 'Enter your admission number and password or PIN.');
    setState(() {
      _busy = true;
      _err = null;
    });
    final client = ServerClient(widget.serverUrl, workstation: Services.I.workstation, appVersion: appVersion);
    try {
      final r = await client.login(_adm.text.trim(), _secret.text);
      if (!mounted) return;
      _secret.clear();
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamListPage(client: client, login: r)));
      _adm.clear();
    } on ServerError catch (e) {
      _err = e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: widget.allowBack, title: Text(_school.isEmpty ? 'Student login' : _school)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_logo != null) Center(child: DataImage(_logo, maxHeight: 96)) else const Icon(Icons.school_rounded, size: 48, color: teal),
                    const SizedBox(height: 8),
                    if (_school.isNotEmpty)
                      Text(_school, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const Text('CBT Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: navy)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _adm,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Admission number', prefixIcon: Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _secret,
                      obscureText: !_show,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Portal password or exam PIN',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
                      ),
                    ),
                    if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: badRed))),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Log in'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
