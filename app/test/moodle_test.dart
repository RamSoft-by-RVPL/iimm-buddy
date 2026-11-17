import 'dart:convert';

import 'package:attendance_planner/moodle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('course contents', () {
    final raw = jsonEncode({
      'section': [
        {
          'title': 'General',
          'cmlist': ['1968', '3263', '9']
        },
        {'title': 'Empty', 'cmlist': []},
        {
          'title': 'Week One',
          'cmlist': ['3264', '3445']
        },
      ],
      'cm': [
        {
          'id': '1968',
          'name': 'Announcements',
          'module': 'forum',
          'visible': true,
          'uservisible': true,
          'url': 'https://m/mod/forum/view.php?id=1968'
        },
        {
          'id': '3263',
          'name': 'Course Outline',
          'module': 'resource',
          'visible': true,
          'uservisible': true,
          'url': 'https://m/mod/resource/view.php?id=3263'
        },
        {
          'id': '9',
          'name': 'Hidden',
          'module': 'resource',
          'visible': false,
          'url': 'x'
        },
        {
          'id': '3264',
          'name': 'Slides',
          'module': 'folder',
          'visible': true,
          'uservisible': false,
          'url': 'https://m/mod/folder/view.php?id=3264'
        },
        {
          'id': '3445',
          'name': 'Reading',
          'module': 'securepdf',
          'visible': true,
          'uservisible': true
        },
      ],
    });
    final s = parseState(raw);
    expect(s.map((x) => x.title).toList(), ['General', 'Week One']);
    expect(s[0].items.map((i) => i.name).toList(),
        ['Announcements', 'Course Outline']);
    expect(s[0].items[1].isFile, true);
    expect(s[1].items[0].isFolder, true);
    expect(s[1].items[0].open, false); // restricted
    expect(s[1].items[1].open, false); // no address to open
  });

  test('file links in a page', () {
    const html =
        '<a href="https://m.x/pluginfile.php/13/mod_folder/content/2/Week%201/Notes%20A.pdf?forcedownload=1">a</a>'
        '<img src="https://m.x/pluginfile.php/1/theme_moove/logo/1/logo.png">'
        '<a href="https://m.x/pluginfile.php/13/mod_folder/content/2/Week%201/Notes%20A.pdf?forcedownload=1">again</a>'
        '<a href="https://m.x/pluginfile.php/13/mod_folder/content/2/b.pptx">b</a>';
    final l = fileLinks(html, mustContain: 'mod_folder/content');
    expect(l.length, 2);
    expect(fileName(l[0]), 'Notes A.pdf');
    expect(fileName(l[1]), 'b.pptx');
  });
}
