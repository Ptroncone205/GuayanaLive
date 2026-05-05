import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class OpenAIService {
  /// Reemplaza este valor con tu clave de API de OpenAI.
  /// Si deseas manejar la clave en otro lugar, puedes pasarla
  /// al constructor desde tu propia configuración.
  static const String _apiKey = '<TU_API_KEY_AQUI>';

  final String apiKey;

  OpenAIService({String? apiKey}) : apiKey = apiKey ?? _apiKey;

  Future<String> getChatResponse(String userMessage, {String? imagePath}) async {
    if (apiKey.isEmpty || apiKey == '<TU_API_KEY_AQUI>') {
      throw Exception('La clave de OpenAI no está configurada. Actualiza lib/services/openai_service.dart.');
    }

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': 'Eres un asistente de chat para una red social tipo Pinterest. Responde en español de forma clara y amigable. Si el usuario envía una imagen, analízala y describe lo que ves, sugiere ideas relacionadas con Pinterest como inspiración para posts.',
      },
    ];

    if (imagePath != null) {
      // Convertir imagen a base64
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      messages.add({
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': userMessage.isNotEmpty ? userMessage : 'Analiza esta imagen y dame ideas para posts en Pinterest.',
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            },
          },
        ],
      });
    } else {
      messages.add({
        'role': 'user',
        'content': userMessage,
      });
    }

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(
        {
          'model': 'gpt-4o', // Modelo con visión
          'messages': messages,
          'temperature': 0.8,
          'max_tokens': 500,
        },
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI API error: ${response.statusCode} ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;

    if (choices == null || choices.isEmpty) {
      throw Exception('Respuesta vacía de OpenAI.');
    }

    final firstChoice = choices.first as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;

    if (content == null) {
      throw Exception('No se pudo leer la respuesta de OpenAI.');
    }

    return content.trim();
  }
}
