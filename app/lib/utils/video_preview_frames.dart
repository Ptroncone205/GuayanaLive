import 'dart:typed_data';

import 'video_preview_frames_stub.dart'
    if (dart.library.html) 'video_preview_frames_web.dart'
    if (dart.library.io) 'video_preview_frames_io.dart' as impl;

/// Extrae unos pocos JPEG del video para enviarlos al modelo de visión (Groq no ve el video completo).
class VideoPreviewFrames {
  VideoPreviewFrames._();

  /// [mimeType] ayuda a guardar el archivo temporal en io cuando solo hay [bytes].
  static Future<List<Uint8List>> extractForAttachment({
    required String? path,
    Uint8List? bytes,
    String mimeType = 'video/mp4',
  }) =>
      impl.extractVideoFramesForAttachment(
        path: path,
        bytes: bytes,
        mimeType: mimeType,
      );
}
