import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:video_thumbnail/video_thumbnail.dart';

const List<int> _timeOffsetsMs = [400, 1500, 4500, 11000];

Future<List<Uint8List>> extractVideoFrames(String videoPath) async {
  final out = <Uint8List>[];
  for (final t in _timeOffsetsMs) {
    if (out.length >= 4) break;
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        timeMs: t,
        quality: 58,
      );
      if (data != null && data.isNotEmpty) {
        out.add(data);
      }
    } catch (e, st) {
      debugPrint('video_thumbnail: $e\n$st');
    }
  }
  return out;
}

Future<List<Uint8List>> extractVideoFramesForAttachment({
  required String? path,
  Uint8List? bytes,
  String mimeType = 'video/mp4',
}) async {
  if (path != null && path.isNotEmpty) {
    return extractVideoFrames(path);
  }
  if (bytes == null || bytes.isEmpty) return const [];

  final ext = mimeType.contains('webm')
      ? 'webm'
      : mimeType.contains('quicktime')
          ? 'mov'
          : 'mp4';
  final dir = await Directory.systemTemp.createTemp('glvf_');
  final file = File('${dir.path}/clip.$ext');
  try {
    await file.writeAsBytes(bytes, flush: true);
    return await extractVideoFrames(file.path);
  } catch (e, st) {
    debugPrint('extractVideoFramesForAttachment io: $e\n$st');
    return const [];
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
