import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lets student computers find the exam server on the Wi-Fi without typing
/// an IP address: the server broadcasts a small UDP message every 2 seconds.
class DiscoveryAnnouncer {
  DiscoveryAnnouncer({required this.httpPort, required this.name, required this.school});
  static const udpPort = 47811;
  final int httpPort;
  String name;
  String school;
  RawDatagramSocket? _sock;
  Timer? _timer;

  Future<void> start() async {
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _sock!.broadcastEnabled = true;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _announce());
    _announce();
  }

  Future<void> _announce() async {
    final msg = utf8.encode(jsonEncode({'app': 'offline_cbt', 'name': name, 'school': school, 'port': httpPort}));
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          final p = a.address.split('.');
          if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255')); // /24 broadcast
        }
      }
    } catch (_) {}
    for (final t in targets) {
      try {
        _sock?.send(msg, t, udpPort);
      } catch (_) {}
    }
  }

  void stop() {
    _timer?.cancel();
    _sock?.close();
    _sock = null;
  }
}

class FoundServer {
  FoundServer(this.address, this.port, this.name, this.school);
  final String address;
  final int port;
  final String name;
  final String school;
  String get baseUrl => 'http://$address:$port';
  @override
  bool operator ==(Object o) => o is FoundServer && o.address == address && o.port == port;
  @override
  int get hashCode => Object.hash(address, port);
}

/// Listens for announcements. Returns a stream of servers as they are found.
class DiscoveryListener {
  RawDatagramSocket? _sock;
  final _ctrl = StreamController<FoundServer>.broadcast();
  Stream<FoundServer> get servers => _ctrl.stream;

  Future<void> start() async {
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, DiscoveryAnnouncer.udpPort, reuseAddress: true);
    _sock!.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = _sock?.receive();
      if (d == null) return;
      try {
        final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
        if (m['app'] != 'offline_cbt') return;
        _ctrl.add(FoundServer(d.address.address, (m['port'] as num).toInt(), '${m['name']}', '${m['school']}'));
      } catch (_) {}
    });
  }

  void stop() {
    _sock?.close();
    _sock = null;
  }
}

/// IPv4 addresses of this computer (to show "students connect to 192.168.x.x").
Future<List<String>> localIPv4() async {
  final out = <String>[];
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) out.add(a.address);
      }
    }
  } catch (_) {}
  return out;
}
