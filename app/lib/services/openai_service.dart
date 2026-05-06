/// Archivo legado. Reemplaza el uso de este servicio por
/// `lib/services/gemini_service.dart`.
class OpenAIService {
  Future<String> getChatResponse(String userMessage, {String? imagePath}) async {
    throw UnimplementedError('Use GeminiService en lib/services/gemini_service.dart');
  }
}
