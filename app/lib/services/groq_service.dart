import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroqService {
  /// Límite aproximado del cuerpo JSON en Edge Functions; el base64 crece ~33%.
  static const int maxMediaBytes = 4 * 1024 * 1024;

  /// Por encima de esto, con fotogramas extra, el JSON suele superar el límite de la función: no enviamos el binario del video (solo fotogramas + transcripción vacía guiada).
  static const int maxVideoBytesForWhisper = 2 * 1024 * 1024;

  // Conversación persistente actual
  final List<Map<String, dynamic>> _chatHistory = [];

  // Limpiar memoria del chat
  void clearChat() {
    _chatHistory.clear();
  }

  /// [mediaMimeType] es obligatorio si envías bytes que no sean JPEG legacy
  /// (por ejemplo `image/png`, `video/mp4`, `audio/mpeg`).
  ///
  /// [mediaKind] refuerza el tipo en el servidor (`image` | `video` | `audio`) por si el
  /// MIME viene vacío o como `application/octet-stream`.
  ///
  /// [videoPreviewJpegFrames]: fotogramas JPEG del mismo video (visión); imprescindible para
  /// preguntas como "¿qué especie es?" cuando el audio no describe la escena.
  Future<String> getChatResponse(
    String userMessage, {
    Uint8List? imageBytes,
    Uint8List? mediaBytes,
    String? mediaMimeType,
    String? mediaKind,
    List<Uint8List>? videoPreviewJpegFrames,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final userPrompt =
        userMessage.isNotEmpty ? userMessage : 'Analiza este archivo.';

    final bytes = mediaBytes ?? imageBytes;
    String? mime = mediaMimeType?.trim().toLowerCase();
    if (bytes != null && bytes.isNotEmpty) {
      if (mime == null || mime.isEmpty) {
        mime = 'image/jpeg';
      }
    } else {
      if (videoPreviewJpegFrames != null &&
          videoPreviewJpegFrames.isNotEmpty) {
        if (mime == null || mime.isEmpty) {
          mime = 'video/mp4';
        }
      } else {
        mime = null;
      }
    }

    if (bytes != null && bytes.length > maxMediaBytes) {
      return 'El archivo pesa demasiado para enviarlo a la IA desde la app (máximo '
          'aproximadamente ${maxMediaBytes ~/ (1024 * 1024)} MB). Prueba con un '
          'video o audio más corto o de menor calidad.';
    }

    if (videoPreviewJpegFrames != null) {
      var frameBytes = 0;
      for (final f in videoPreviewJpegFrames) {
        frameBytes += f.length;
      }
      if (frameBytes > 2 * 1024 * 1024) {
        return 'Los fotogramas del video son demasiado grandes. Prueba con otra '
            'resolución o un clip más corto.';
      }
    }

    try {
      String? mediaBase64;
      if (bytes != null && bytes.isNotEmpty) {
        mediaBase64 = base64Encode(bytes);
      }

      // Guardar mensaje del usuario en memoria
      _chatHistory.add({
        'role': 'user',
        'content': userPrompt,
      });

      final previewB64 = videoPreviewJpegFrames
          ?.where((e) => e.isNotEmpty)
          .map(base64Encode)
          .toList();

      final body = <String, dynamic>{
        'prompt': userPrompt,
        'history': _chatHistory,
        if (mediaBase64 != null) ...{
          'mediaBase64': mediaBase64,
          'mediaMimeType': mime,
          if (mediaKind != null && mediaKind.trim().isNotEmpty)
            'mediaKind': mediaKind.trim().toLowerCase(),
        },
      };
      if (previewB64 != null && previewB64.isNotEmpty) {
        body['videoPreviewFramesBase64'] = previewB64;
        if (mediaBase64 == null &&
            mediaKind != null &&
            mediaKind.trim().toLowerCase() == 'video') {
          body['mediaMimeType'] = mime ?? 'video/mp4';
          body['mediaKind'] = 'video';
        }
      }

      // Llamar Edge Function
      final response = await Supabase.instance.client.functions.invoke(
        'ai_proxy',
        body: body,
      );

      final data = response.data;

      if (data == null) {
        throw Exception('La función no devolvió datos.');
      }

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final reply = data['reply'];

      if (reply == null) {
        throw Exception('La IA devolvió una respuesta vacía.');
      }

      final finalResponse = reply.toString().trim();

      // Guardar respuesta IA en memoria
      _chatHistory.add({
        'role': 'assistant',
        'content': finalResponse,
      });

      return finalResponse;
    } catch (e, st) {
      // Remover último user message si falla
      if (_chatHistory.isNotEmpty &&
          _chatHistory.last['role'] == 'user') {
        _chatHistory.removeLast();
      }

      debugPrint('AI ERROR: $e');
      debugPrint(st.toString());

      return 'Error al conectar con la IA: $e';
    }
  }

  // AUTOFILL PARA POSTS (solo imagen)
  Future<Map<String, dynamic>> getAutoFillData(
    Uint8List imageBytes,
  ) async {
    const prompt =
        'Devuelve ÚNICAMENTE un objeto JSON con dos campos: '
        '"titulo" (un título descriptivo corto) y '
        '"tags" (una lista de 3 a 5 palabras clave relevantes). '
        'Ejemplo: '
        '{"titulo":"Rana de cristal","tags":["rana","anfibio","selva"]}. '
        'No escribas nada fuera del JSON.';

    final aiResponse = await getChatResponse(
      prompt,
      mediaBytes: imageBytes,
      mediaMimeType: 'image/jpeg',
      mediaKind: 'image',
    );

    final cleanJson = aiResponse
        .replaceAll(RegExp(r'```json|```'), '')
        .trim();

    return jsonDecode(cleanJson) as Map<String, dynamic>;
  }
}
