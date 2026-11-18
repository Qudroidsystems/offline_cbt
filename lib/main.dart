import 'dart:io';

import 'package:cbt_core/cbt_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app/services.dart';
import 'ui/common/theme.dart';
import 'ui/mode_select_page.dart';
import 'ui/server/server_home.dart';
import 'ui/student/connect_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'Offline CBT', minimumSize: Size(1000, 680), center: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final dir = appDataDir();
  Directory(dir).createSync(recursive: true);
  final db = CbtDb.open(p.join(dir, 'offline_cbt.db'));
  Services.I = Services(db, dir);
  if (Services.I.mode == 'server') {
    Services.I.store.ensurePracticeExam();
    await Services.I.startServer();
    Services.I.startAutoSync();
  }

  runApp(const OfflineCbtApp());
}

class OfflineCbtApp extends StatelessWidget {
  const OfflineCbtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline CBT',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootPage(),
    );
  }
}

/// Sends the user to the right part of the app for this computer's role.
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (Services.I.mode) {
      'server' => const ServerHome(),
      'student' => const ConnectPage(),
      _ => const ModeSelectPage(),
    };
  }
}
