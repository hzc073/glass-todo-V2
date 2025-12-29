import 'download_stub.dart' if (dart.library.html) 'download_web.dart' as impl;
import 'dart:typed_data';

Future<bool> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'application/octet-stream',
}) {
  return impl.downloadTextFile(filename: filename, content: content, mimeType: mimeType);
}

Future<bool> downloadBytesFile({
  required String filename,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) {
  return impl.downloadBytesFile(filename: filename, bytes: bytes, mimeType: mimeType);
}
