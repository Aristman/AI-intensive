import 'package:http/http.dart' as http;

abstract class LlmUseCase {
  Future<String> complete({
    required List<Map<String, String>> messages,
    required String modelUri,
    required String iamToken,
    required String apiKey,
    required String folderId,
    double temperature = 0.2,
    int maxTokens = 128,
    http.Client? client,
  });
}
