import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class GroqService {
  final String _apiKey = groqApiKey;
  final String _url = 'https://api.groq.com/openai/v1/chat/completions';

  // --- AQUÍ ESTÁ LA MAGIA DE LA MEMORIA ---
  // Esta lista guardará toda la conversación actual
  final List<Map<String, dynamic>> _chatHistory = [];

  // Método extra por si algún día quieres poner un botón de "Limpiar Chat"
  void clearChat() {
    _chatHistory.clear();
  }
  // ----------------------------------------

  Future<String> getChatResponse(String userMessage, {Uint8List? imageBytes}) async {
    if (_apiKey.isEmpty) {
      throw Exception('La clave de Groq no está configurada. Usa GROQ_API_KEY.');
    }

    final userPrompt = userMessage.isNotEmpty ? userMessage : 'Analiza esta imagen.';

    const systemInstruction =
        'Eres un asistente de IA para GuayanaLive, una red social visual tipo Pinterest enfocada en la región Guayana, Venezuela. '
        'Responde en español o ingles depende de cual lenguaje use el usuario de forma directa y precisa. '
        'No agregues información innecesaria ni explicaciones largas. '
        'Atiende exactamente lo que pide el usuario. '
        'Si hay una imagen, identifícala si es una especie de flora o fauna de la región.';

    final List<Map<String, dynamic>> currentUserContent = [
      {
        'type': 'text',
        'text': userPrompt,
      },
    ];

    if (imageBytes != null && imageBytes.isNotEmpty) {
      try {
        final base64Image = base64Encode(imageBytes);
        currentUserContent.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,$base64Image',
          },
        });
      } catch (e) {
        debugPrint('Error al convertir imagen a Base64: $e');
      }
    }

    // 1. GUARDAMOS LO QUE EL USUARIO ACABA DE DECIR EN LA MEMORIA
    _chatHistory.add({
      'role': 'user',
      'content': currentUserContent,
    });

    // 2. ARMAMOS EL PAQUETE CON LA INSTRUCCIÓN DEL SISTEMA + TODO EL HISTORIAL
    // Los tres puntos (...) "expanden" la lista de la memoria aquí dentro.
    final List<Map<String, dynamic>> messagesToSend = [
      {
        'role': 'system',
        'content': systemInstruction,
      },
      ..._chatHistory, 
    ];

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'meta-llama/llama-4-scout-17b-16e-instruct',
          'messages': messagesToSend, // Mandamos el paquete completo
          'temperature': 0.3,
          'max_tokens': 900,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final botResponse = data['choices']?[0]?['message']?['content'];
        
        if (botResponse == null) {
          throw Exception('Respuesta inválida de Groq.');
        }

        final finalResponse = botResponse.trim();

        // 3. GUARDAMOS LO QUE LA IA RESPONDIÓ EN LA MEMORIA PARA LA PRÓXIMA
        _chatHistory.add({
          'role': 'assistant',
          'content': finalResponse, // El asistente responde en texto simple
        });

        return finalResponse;
      }

      // Si Groq da error, borramos el último mensaje nuestro de la memoria 
      // para que no se tranque si intentamos reenviarlo.
      _chatHistory.removeLast();
      
      final errorData = jsonDecode(response.body);
      final errorMessage = errorData['error']?['message'] ?? response.body;
      throw Exception('Error de Groq (${response.statusCode}): $errorMessage');
    } catch (e, st) {
      // Manejo de errores de red (quitar el mensaje fallido)
      if (_chatHistory.isNotEmpty && _chatHistory.last['role'] == 'user') {
        _chatHistory.removeLast();
      }
      debugPrint('Groq service error: $e');
      debugPrint(st.toString());
      return 'Error al conectar con la IA: $e';
    }
  }
}