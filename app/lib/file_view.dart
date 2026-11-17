// Shows a downloaded file inside the app: PDFs and pictures are drawn here,
// other kinds (slides, Word, Excel) are handed to an app on the phone that
// can show them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

const _pictures = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

String fileKind(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (ext == 'pdf') return 'pdf';
  if (_pictures.contains(ext)) return 'picture';
  return 'other';
}

Future<void> _openOutside(BuildContext context, File f) async {
  final r = await OpenFilex.open(f.path);
  if (r.type != ResultType.done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.type == ResultType.noAppToOpen
            ? 'No app on this phone can open this file'
            : 'Could not open the file')));
  }
}

/// Opens a file that is already on the phone.
Future<void> openFile(BuildContext context, File f, {int page = 1}) async {
  if (fileKind(f.path) == 'other') return _openOutside(context, f);
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => FileViewScreen(file: f, page: page)));
}

class FileViewScreen extends StatefulWidget {
  const FileViewScreen({super.key, required this.file, this.page = 1});
  final File file;

  /// The page to open on (PDFs).
  final int page;

  @override
  State<FileViewScreen> createState() => _FileViewScreenState();
}

class _FileViewScreenState extends State<FileViewScreen> {
  PdfController? pdf;
  int page = 1;
  int pages = 0;
  String? error;

  File get file => widget.file;
  String get name => file.path.split('/').last;

  @override
  void initState() {
    super.initState();
    if (fileKind(file.path) == 'pdf') {
      page = widget.page < 1 ? 1 : widget.page;
      pdf = PdfController(
          document: PdfDocument.openFile(file.path), initialPage: page);
    }
  }

  @override
  void dispose() {
    pdf?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget failed(String why) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(why, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => _openOutside(context, file),
                  child: const Text('Open in another app')),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(name, style: t.textTheme.titleMedium),
        actions: [
          if (pages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('$page / $pages', style: t.textTheme.labelLarge),
              ),
            ),
          IconButton(
            tooltip: 'Share',
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Open in another app',
            onPressed: () => _openOutside(context, file),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: error != null
          ? failed(error!)
          : pdf != null
              ? PdfView(
                  controller: pdf!,
                  scrollDirection: Axis.vertical,
                  pageSnapping: false,
                  onDocumentLoaded: (d) => setState(() => pages = d.pagesCount),
                  onPageChanged: (p) => setState(() => page = p),
                  onDocumentError: (_) => setState(() => error =
                      'This PDF could not be shown here. It may be damaged '
                          'or locked with a password.'),
                )
              : InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: Image.file(file,
                        errorBuilder: (_, __, ___) =>
                            failed('This picture could not be shown.')),
                  ),
                ),
    );
  }
}
