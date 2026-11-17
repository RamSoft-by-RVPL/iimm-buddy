// Search inside the notes saved on the phone.
//
// Each downloaded file gets a plain-text copy (its "index") the first time
// it is needed: PDFs page by page, PowerPoint slide by slide, Word and text
// files as they are. Searching then only reads those small text files.
// Everything happens on the phone.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Pages (or slides) are separated by this in an index file.
const pageBreak = '\f';

const _textKinds = {'txt', 'md', 'csv', 'r', 'py', 'sql', 'json', 'tex'};

String _ext(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// True for a kind of file whose text can be read.
bool canIndex(String path) =>
    const {'pdf', 'pptx', 'docx'}.contains(_ext(path)) ||
    _textKinds.contains(_ext(path));

String _xmlText(String xml, String tag) =>
    RegExp('<$tag(?: [^>]*)?>([^<]*)</$tag>')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .join(' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");

/// The text of a slide deck, one entry per slide.
List<String> pptxText(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final slides = <int, String>{};
  for (final f in zip.files) {
    final m = RegExp(r'^ppt/slides/slide(\d+)\.xml$').firstMatch(f.name);
    if (m == null) continue;
    slides[int.parse(m.group(1)!)] = _xmlText(
        utf8.decode(f.content as List<int>, allowMalformed: true), 'a:t');
  }
  return [for (final n in slides.keys.toList()..sort()) slides[n]!];
}

/// The text of a Word document.
String docxText(List<int> bytes) {
  final f = ZipDecoder().decodeBytes(bytes).findFile('word/document.xml');
  if (f == null) return '';
  return utf8
      .decode(f.content as List<int>, allowMalformed: true)
      .split('</w:p>')
      .map((p) => _xmlText(p, 'w:t'))
      .where((p) => p.trim().isNotEmpty)
      .join('\n');
}

/// The readable text of one file, pages joined by [pageBreak]. Runs in a
/// separate isolate because big PDFs take a while.
String extractText(String path) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() > 60 * 1024 * 1024) return '';
  try {
    switch (_ext(path)) {
      case 'pdf':
        final doc = PdfDocument(inputBytes: file.readAsBytesSync());
        try {
          final reader = PdfTextExtractor(doc);
          final pages = <String>[];
          for (var i = 0; i < doc.pages.count && i < 400; i++) {
            pages.add(reader.extractText(startPageIndex: i, endPageIndex: i));
          }
          return pages.join(pageBreak);
        } finally {
          doc.dispose();
        }
      case 'pptx':
        return pptxText(file.readAsBytesSync()).join(pageBreak);
      case 'docx':
        return docxText(file.readAsBytesSync());
      default:
        if (!_textKinds.contains(_ext(path))) return '';
        final bytes = file.readAsBytesSync();
        return utf8.decode(
            bytes.length > 400000 ? bytes.sublist(0, 400000) : bytes,
            allowMalformed: true);
    }
  } catch (_) {
    return ''; // damaged or password-protected: nothing to search
  }
}

class NoteHit {
  NoteHit(this.path, this.page, this.snippet);

  /// The saved file (not the index).
  final String path;

  /// Page or slide, starting at 1; 0 when the file has no pages.
  final int page;
  final String snippet;

  String get fileName => path.split('/').last;

  /// The course and item folders the file sits in ("12", "3456").
  List<String> get folders {
    final parts = path.split('/');
    return parts.length < 3
        ? ['', '']
        : parts.sublist(parts.length - 3, parts.length - 1);
  }
}

/// Finds [query] in index text. One hit per page, with some words around it.
List<(int, String)> findIn(String text, String query, {int limit = 3}) {
  final out = <(int, String)>[];
  final q = query.toLowerCase();
  final pages = text.split(pageBreak);
  for (var p = 0; p < pages.length && out.length < limit; p++) {
    final flat = pages[p].replaceAll(RegExp(r'\s+'), ' ');
    final i = flat.toLowerCase().indexOf(q);
    if (i < 0) continue;
    final from = i - 40 < 0 ? 0 : i - 40;
    final to =
        i + q.length + 60 > flat.length ? flat.length : i + q.length + 60;
    out.add((
      pages.length == 1 ? 0 : p + 1,
      '${from > 0 ? '…' : ''}${flat.substring(from, to).trim()}${to < flat.length ? '…' : ''}'
    ));
  }
  return out;
}

/// (index root, query) -> hits. Runs in a separate isolate.
List<List<String>> _search((String, String, String) job) {
  final (indexRoot, filesRoot, query) = job;
  final root = Directory(indexRoot);
  if (!root.existsSync()) return [];
  final out = <List<String>>[];
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.txt')) continue;
    final rel = f.path.substring(indexRoot.length, f.path.length - 4);
    for (final (page, snippet) in findIn(f.readAsStringSync(), query)) {
      out.add(['$filesRoot$rel', '$page', snippet]);
      if (out.length >= 60) return out;
    }
  }
  return out;
}

class NotesIndex {
  String? _files;
  String? _index;

  Future<void> _roots() async {
    if (_files != null) return;
    final docs = (await getApplicationDocumentsDirectory()).path;
    _files = '$docs/moodle';
    _index = '$docs/moodle_index';
  }

  File _indexOf(File f) =>
      File('$_index${f.path.substring(_files!.length)}.txt');

  /// Saved files whose text can be searched, and how many are indexed.
  Future<(List<File>, int)> _state() async {
    await _roots();
    final dir = Directory(_files!);
    if (!dir.existsSync()) return (<File>[], 0);
    final all = [
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (canIndex(f.path) && !f.path.endsWith('.part')) f
    ];
    return (all, all.where((f) => _indexOf(f).existsSync()).length);
  }

  /// Reads the text of every saved file that has not been read yet.
  /// [onProgress] gets (done, total). Returns how many files are searchable.
  Future<int> build({void Function(int, int)? onProgress}) async {
    final (all, _) = await _state();
    var done = 0;
    for (final f in all) {
      final target = _indexOf(f);
      if (!target.existsSync()) {
        final text = await compute(extractText, f.path);
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(text);
      }
      onProgress?.call(++done, all.length);
    }
    return all.length;
  }

  Future<List<NoteHit>> search(String query) async {
    await _roots();
    final rows = await compute(_search, (_index!, _files!, query));
    return [for (final r in rows) NoteHit(r[0], int.parse(r[1]), r[2])];
  }

  Future<void> clear() async {
    await _roots();
    final d = Directory(_index!);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
