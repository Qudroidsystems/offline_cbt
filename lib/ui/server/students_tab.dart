import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../common/widgets.dart';

class StudentsTab extends StatefulWidget {
  const StudentsTab({super.key});
  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  String _q = '';
  String? _cls;

  @override
  Widget build(BuildContext context) {
    final db = Services.I.db.db;
    final classes = [for (final r in db.select('SELECT DISTINCT class_name FROM students ORDER BY class_name')) '${r['class_name']}'];
    final like = '%$_q%';
    final rows = db.select('''
      SELECT s.*, (SELECT COUNT(*) FROM student_exams se WHERE se.user_id = s.user_id) AS exams,
             (SELECT COUNT(*) FROM attempts a WHERE a.user_id = s.user_id AND a.status = 'submitted') AS done
      FROM students s
      WHERE (s.lastname LIKE ? OR s.firstname LIKE ? OR s.admission_no LIKE ?) ${_cls != null ? 'AND s.class_name = ?' : ''}
      ORDER BY s.class_name, s.lastname, s.firstname LIMIT 1000''', [like, like, like, if (_cls != null) _cls]);

    return ListView(padding: const EdgeInsets.all(24), children: [
      SectionTitle('Students on this computer (${rows.length})'),
      Row(children: [
        SizedBox(
          width: 320,
          child: TextField(
            decoration: const InputDecoration(labelText: 'Search name or admission number', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String?>(
            value: _cls,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('All classes')), for (final c in classes) DropdownMenuItem<String?>(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _cls = v),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      const Text('Students log in with their admission number and either their portal password or the PIN printed from the portal (Offline CBT → Print slips).',
          style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 12),
      Card(
        child: DataTable(columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Admission no')),
          DataColumn(label: Text('Class')),
          DataColumn(label: Text('Can log in with')),
          DataColumn(label: Text('Exams')),
        ], rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('${r['lastname']} ${r['firstname']} ${r['othername'] ?? ''}'.trim())),
              DataCell(Text('${r['admission_no']}')),
              DataCell(Text('${r['class_name']}')),
              DataCell(Text([
                if ((r['password_hash'] as String?)?.isNotEmpty == true) 'password',
                if ((r['pin'] as String?)?.isNotEmpty == true) 'PIN',
              ].join(' or ').ifEmpty('— no password or PIN —'))),
              DataCell(Text('${r['done']} done of ${r['exams']}')),
            ]),
        ]),
      ),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
