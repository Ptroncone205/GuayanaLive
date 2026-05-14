import 'dart:typed_data';

Future<List<Uint8List>> extractVideoFrames(String videoPath) async => const [];

Future<List<Uint8List>> extractVideoFramesForAttachment({
  required String? path,
  Uint8List? bytes,
  String mimeType = 'video/mp4',
}) async {
  if (path != null && path.isNotEmpty) {
    return extractVideoFrames(path);
  }
  return const [];
}
