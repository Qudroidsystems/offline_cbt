// Sample exam package shaped exactly like the portal's PackageBuilder output.
Map<String, dynamic> samplePackage({String uuid = '11111111-1111-4111-8111-111111111111', String q1Text = 'Capital of Nigeria?', String? hash}) => {
      'format': 1,
      'package_uuid': uuid,
      'generated_at': '2026-11-18T08:00:00+01:00',
      'checksum': 'abc',
      'school': {'name': 'CSS Kabba', 'address': 'Kabba', 'logo': null},
      'session': {'id': 5, 'name': '2026/2027'},
      'term': {'id': 1, 'name': 'First Term'},
      'exams': [
        {
          'id': 10, 'title': 'Social Studies Exam', 'description': 'Answer all', 'duration': 30,
          'start_time': '2026-11-18T09:00:00+01:00', 'end_time': '2026-11-18T12:00:00+01:00',
          'term_id': 1, 'session_id': 5, 'is_published': true,
          'subject': {'id': 3, 'name': 'Social Studies'}, 'class': {'id': 7, 'name': 'JSS 1 A'},
          'total_marks': 6.0, 'question_count': 3,
          'questions': [
            {'id': 101, 'text': q1Text, 'type': 'mcq', 'marks': 2, 'order': 1, 'image': null, 'options': [
              {'id': 1001, 'label': 'A', 'text': 'Abuja', 'is_correct': true},
              {'id': 1002, 'label': 'B', 'text': 'Lagos', 'is_correct': false},
            ]},
            {'id': 102, 'text': 'The sun rises in the west.', 'type': 'true_false', 'marks': 1, 'order': 2, 'image': null, 'options': [
              {'id': 1003, 'label': 'A', 'text': 'True', 'is_correct': false},
              {'id': 1004, 'label': 'B', 'text': 'False', 'is_correct': true},
            ]},
            {'id': 103, 'text': 'Process plants use to make food?', 'type': 'short_answer', 'marks': 3, 'order': 3, 'image': null, 'options': [
              {'id': 1005, 'label': null, 'text': 'Photosynthesis', 'is_correct': true},
            ]},
          ],
        },
      ],
      'students': [
        {'user_id': 501, 'student_id': 901, 'admission_no': 'CSS/001', 'firstname': 'Ada', 'lastname': 'Okafor', 'othername': '',
          'class_name': 'JSS 1 A', 'exam_ids': [10], 'done_online': [], 'password_hash': hash, 'pin': 'K7M2QX', 'photo': 'data:image/png;base64,iVBORw0KGgo='},
        {'user_id': 502, 'student_id': 902, 'admission_no': 'CSS/002', 'firstname': 'Bayo', 'lastname': 'Adeyemi', 'othername': '',
          'class_name': 'JSS 1 A', 'exam_ids': [10], 'done_online': [10], 'password_hash': null, 'pin': 'P3R9TT'},
        {'user_id': 503, 'student_id': 903, 'admission_no': 'CSS/003', 'firstname': 'Chi', 'lastname': 'Eze', 'othername': '',
          'class_name': 'JSS 1 A', 'exam_ids': [10], 'done_online': [], 'password_hash': null, 'pin': 'ZZ4422'},
      ],
    };

// Laravel-style hash of "student01" (cost 4, made with Python bcrypt, $2b$ -> $2y$).
const sampleHash = r'$2y$04$0eOWSl8YDvY8HHE1mGE4vecQZ/S27J7ZShqY9gEAbngZQJMBj62C.';
