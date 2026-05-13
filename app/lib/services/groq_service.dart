import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroqService {
  // Conversación persistente actual
  final List<Map<String, dynamic>> _chatHistory = [];

  // Limpiar memoria del chat
  void clearChat() {
    _chatHistory.clear();
  }

  Future<String> getChatResponse(
    String userMessage, {
    Uint8List? imageBytes,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final userPrompt =
        userMessage.isNotEmpty ? userMessage : 'Analiza esta imagen.';

    try {
      String? imageBase64;

      // Convertir imagen a base64 si existe
      if (imageBytes != null && imageBytes.isNotEmpty) {
        imageBase64 = base64Encode(imageBytes);
      }

      // Guardar mensaje del usuario en memoria
      _chatHistory.add({
        'role': 'user',
        'content': userPrompt,
      });

      // Llamar Edge Function
      final response = await Supabase.instance.client.functions.invoke(
        'ai_proxy',
        body: {
          'prompt': userPrompt,
          'imageBase64': imageBase64,
          'history': _chatHistory,
        },
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

  // AUTOFILL PARA POSTS
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
      imageBytes: imageBytes,
    );

    final cleanJson = aiResponse
        .replaceAll(RegExp(r'```json|```'), '')
        .trim();

    return jsonDecode(cleanJson);
  }
}