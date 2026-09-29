import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves [content] as a file: desktop shows a save dialog, mobile opens the
/// share sheet with a temporary file. Returns a description of where it went.
Future<String?> saveText({
  required String fileName,
  required String content,
  String? dialogTitle,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString(content);
    await Share.shareXFiles([XFile(f.path)], subject: fileName);
    return fileName;
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: utf8.encode(content),
  );
  if (path != null && !File(path).existsSync()) {
    // Some platforms return a path without writing (older file_picker behavior).
    await File(path).writeAsString(content);
  }
  return path;
}

/// Lets the user pick a text file and returns its content (null if cancelled).
Future<String?> pickTextFile({List<String>? extensions}) async {
  final r = await FilePicker.platform.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  if (f.bytes != null) return utf8.decode(f.bytes!, allowMalformed: true);
  if (f.path != null) return File(f.path!).readAsString();
  return null;
}
