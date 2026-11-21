// Teachers' institute email addresses, from the directory the admin
// publishes (taken from the institute's Outlook address book), and matching
// them to the names the attendance site and timetable use
// ("Prof.J.Rambabu", "Prof. Rofin T.M.", "Prof. X (Guest Faculty)").

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cookie_bridge/cookie_bridge.dart' show composeEmail;

import 'crony_ui.dart';

/// Name as the directory has it, and the address.
class Teacher {
  Teacher(this.name, this.email);
  final String name;
  final String email;
}

/// Set from the saved directory when the app starts and after each fetch.
var teacherDirectory = <Teacher>[];

List<Teacher> decodeTeachers(String? raw) {
  try {
    return [
      for (final t in (jsonDecode(raw ?? '') as Map)['teachers'] as List)
        if ('${t['email']}'.contains('@'))
          Teacher('${t['name']}', '${t['email']}')
    ];
  } catch (_) {
    return [];
  }
}

/// The words of a name that tell people apart: no titles, no notes in
/// brackets, no initials.
List<String> nameWords(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)'), ' ')
    .replaceAll(RegExp(r'\b(prof|dr|mr|ms|mrs)\b\.?'), ' ')
    .split(RegExp(r'[^a-z]+'))
    .where((w) => w.length >= 3)
    .toList();

/// The teacher in [list] that [name] means, or null. Needs every word of a
/// one- or two-word name to match, and two words of a longer one, and
/// picks the best match only when it is clear.
Teacher? findTeacher(String name, List<Teacher> list) {
  final words = nameWords(name).toSet();
  if (words.isEmpty) return null;
  Teacher? best;
  var top = 0, second = 0;
  for (final t in list) {
    final score = nameWords(t.name).toSet().intersection(words).length;
    if (score > top) {
      second = top;
      top = score;
      best = t;
    } else if (score > second) {
      second = score;
    }
  }
  final need = words.length >= 2 ? 2 : 1;
  return top >= need && top > second ? best : null;
}

/// The people in a faculty field: "Prof. A, Prof. B (Guest Faculty)".
List<String> splitTeachers(String faculty) => [
      for (final p in faculty.split(RegExp(r',|;| and ')))
        if (p.trim().isNotEmpty) p.trim()
    ];

/// "Prof. Rofin T.M." → "Prof. Rofin T.M.", tidied for a greeting.
String greetingName(String name) {
  final n = name.replaceAll(RegExp(r'\(.*?\)'), '').trim();
  final bare =
      n.replaceFirst(RegExp(r'^(prof|dr)\.?\s*', caseSensitive: false), '');
  return 'Prof. ${bare.replaceFirst(RegExp(r'^\.\s*'), '')}';
}

/// One row per teacher, with an Email button for those in the directory.
class TeacherRows extends StatelessWidget {
  const TeacherRows({super.key, required this.faculty, this.course = ''});
  final String faculty;
  final String course;

  @override
  Widget build(BuildContext context) {
    final names = splitTeachers(faculty);
    if (names.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, n) in names.indexed)
        Builder(builder: (context) {
          final t = findTeacher(n, teacherDirectory);
          return InfoRow(
            i == 0 ? 'Faculty' : '',
            Text(t?.name ?? n.replaceAll(RegExp(r'\s*\(.*?\)'), '')),
            action: t == null
                ? null
                : TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('Email'),
                    onPressed: () async {
                      try {
                        await composeEmail(
                            t.email,
                            course.isEmpty ? '' : course,
                            'Dear ${greetingName(t.name)},\n\n');
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'No email app. The address is ${t.email}')));
                      }
                    },
                  ),
          );
        }),
    ]);
  }
}
