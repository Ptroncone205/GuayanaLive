import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

const List<int> _timeOffsetsMs = [400, 1500, 4500, 11000];

Future<List<Uint8List>> extractVideoFrames(String videoUrl) async {
  final out = <Uint8List>[];
  final video = html.VideoElement()
    ..src = videoUrl
    ..muted = true
    ..setAttribute('playsinline', 'true');
  video.style.display = 'none';
  html.document.body!.append(video);

  try {
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 30));
    final dur = video.duration;
    if (dur.isNaN || dur <= 0) return out;

    try {
      video.play();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final durationMs = (dur * 1000).round();

    for (final t in _timeOffsetsMs) {
      if (out.length >= 4) break;
      final safeEnd = durationMs > 1 ? durationMs - 1 : 1;
      final ms = t.clamp(0, safeEnd);
      video.currentTime = ms / 1000.0;
      await video.onSeeked.first.timeout(const Duration(seconds: 20));

      final vw = video.videoWidth;
      final vh = video.videoHeight;
      if (vw < 2 || vh < 2) continue;

      var tw = vw.toDouble();
      var th = vh.toDouble();
      const maxW = 720.0;
      if (tw > maxW) {
        th = th * maxW / tw;
        tw = maxW;
      }

      final twi = tw.round();
      final thi = th.round();
      final canvas = html.CanvasElement(width: twi, height: thi);
      final ctx = canvas.context2D;
      final sx = twi / vw;
      final sy = thi / vh;
      ctx
        ..save()
        ..scale(sx, sy)
        ..drawImage(video, 0, 0)
        ..restore();

      final dataUrl = canvas.toDataUrl('image/jpeg', 0.72);
      final comma = dataUrl.indexOf(',');
      if (comma > 0 && comma < dataUrl.length - 1) {
        out.add(Uint8List.fromList(base64Decode(dataUrl.substring(comma + 1))));
      }
    }
  } catch (e, st) {
    debugPrint('video_preview_frames_web: $e\n$st');
  } finally {
    video.remove();
    video.src = '';
    video.load();
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
  if (bytes != null && bytes.isNotEmpty) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      return await extractVideoFrames(url);
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }
  return const [];
}
