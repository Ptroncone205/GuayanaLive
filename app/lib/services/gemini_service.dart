import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemini/flutter_gemini.dart';

class GeminiService {
  /// La inicialización de Gemini debe hacerse en lib/main.dart.
  /// Si deseas manejar la clave en otro lugar, mueve la llamada a Gemini.init.

  Future<String> getChatResponse(String userMessage, {String? imagePath}) async {
    final promptText = userMessage.isNotEmpty
        ? userMessage
        : 'Analiza esta imagen y dame ideas para posts en Pinterest.';

    try {
      final Candidates? result;

      if (imagePath != null) {
        final imageFile = File(imagePath);
        final bytes = await imageFile.readAsBytes();

        result = await Gemini.instance.prompt(
          parts: [
            Part.text('Eres un asistente de chat para una red social tipo Pinterest. Responde en español de forma clara y amigable. Si el usuario envía una imagen, analízala y describe lo que ves, sugiere ideas relacionadas con Pinterest como inspiración para posts.'),
            Part.text(promptText),
            Part.bytes(bytes),
          ],
          model: 'gemini-1.5-flash',
          generationConfig: GenerationConfig(
            temperature: 0.8,
            maxOutputTokens: 500,
          ),
        );
      } else {
        result = await Gemini.instance.chat(
          [
            Content(
              parts: [Part.text('Eres un asistente de chat para una red social tipo Pinterest. Responde en español de forma clara y amigable. Si el usuario envía una imagen, analízala y describe lo que ves, sugiere ideas relacionadas con Pinterest como inspiración para posts.')],
              role: 'system',
            ),
            Content(
              parts: [Part.text(promptText)],
              role: 'user',
            ),
          ],
          modelName: 'gemini-1.5-pro',
          generationConfig: GenerationConfig(
            temperature: 0.8,
            maxOutputTokens: 500,
          ),
        );
      }

      final output = result?.output?.trim();
      if (output == null || output.isEmpty) {
        throw Exception('La respuesta de Gemini está vacía.');
      }

      return output;
    } catch (e, st) {
      // Log the error so podemos ver el motivo real en la consola de Flutter.
      debugPrint('Gemini service error: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }
}
