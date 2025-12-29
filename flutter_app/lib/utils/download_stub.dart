import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'application/octet-stream',
}) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return downloadBytesFile(filename: filename, bytes: bytes, mimeType: mimeType);
}

Future<bool> downloadBytesFile({
  required String filename,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final savedPath = await FilePicker.platform.saveFile(
        fileName: filename,
        bytes: bytes,
      );
      return savedPath != null;
    }

    final savedPath = await FilePicker.platform.saveFile(fileName: filename);
    if (savedPath == null || savedPath.trim().isEmpty) return false;

    await File(savedPath).writeAsBytes(bytes, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
