/// Defines the format of the response from the chat API
enum ResponseFormat {
  /// Plain text response
  text,
  
  /// JSON formatted response
  json,
}

extension ResponseFormatExtension on ResponseFormat {
  /// Returns the string representation of the enum
  String get name => toString().split('.').last;
}
