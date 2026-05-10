import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Place non-sensitive configuration values here.
///
/// For production, override this value with a dart define:
///   flutter run --dart-define=GROQ_API_KEY=your_key_here
/// or configure your CI/CD environment accordingly.
String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
