import 'dart:async';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import 'exams_tab.dart';
import 'live_tab.dart';
import 'portal_tab.dart';
import 'settings_tab.dart';
import 'students_tab.dart';
import 'sync_tab.dart';

/// Admin / invigilator computer.
class ServerHome extends StatefulWidget {
  const ServerHome({super.key});
  @override
  State<ServerHome> createState() => _ServerHomeState();
}

class _ServerHomeState extends State<ServerHome> {
  int _tab = 0;
  List<String> _ips = [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _tab = Services.I.portal() == null ? 4 : 0;
    _refreshIps();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _refreshIps());
  }

  Future<void> _refreshIps() async {
    final ips = await localIPv4();
    if (mounted) setState(() => _ips = ips);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final running = s.server?.running == true;
    final pages = [const LiveTab(), const ExamsTab(), const StudentsTab(), const SyncTab(), const PortalTab(), const SettingsTab()];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (s.schoolLogo != null)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: DataImage(s.schoolLogo, maxHeight: 30),
            )
          else
            const Icon(Icons.dns_rounded),
          const SizedBox(width: 10),
          Flexible(child: Text('${s.schoolName == 'School' ? 'Offline CBT' : s.schoolName} — ${s.serverName}', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: running ? okGreen : badRed, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  running
                      ? 'Exam server ON  •  students connect to ${_ips.isEmpty ? 'this computer' : _ips.map((ip) => '$ip:${s.server!.port}').join('  or  ')}'
                      : 'Exam server OFF',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(children: [
        NavigationRail(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: Text('Live exam')),
            NavigationRailDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: Text('Exams')),
            NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Students')),
            NavigationRailDestination(icon: Icon(Icons.cloud_upload_outlined), selectedIcon: Icon(Icons.cloud_upload), label: Text('Sync')),
            NavigationRailDestination(icon: Icon(Icons.link_outlined), selectedIcon: Icon(Icons.link), label: Text('Portal')),
            NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: pages[_tab]),
      ]),
    );
  }
}
