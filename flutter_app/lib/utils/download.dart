import 'download_stub.dart' if (dart.library.html) 'download_web.dart' as impl;

Future<bool> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'application/octet-stream',
}) {
  return impl.downloadTextFile(filename: filename, content: content, mimeType: mimeType);
}

