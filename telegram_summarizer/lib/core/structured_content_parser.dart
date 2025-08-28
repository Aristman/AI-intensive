import 'dart:convert';

/// Результат парсинга/валидации structuredContent
class StructuredContentParseResult {
  final Map<String, dynamic>? data;
  final List<String> warnings;
  final List<String> errors;

  const StructuredContentParseResult({
    required this.data,
    this.warnings = const [],
    this.errors = const [],
  });

  bool get isValid => errors.isEmpty && data != null;
}

/// Простой парсер structuredContent.
/// MVP: допускает произвольные JSON-совместимые объекты.
/// Если вход — строка, пытается выполнить jsonDecode.
/// Если вход не Map<String, dynamic>, возвращает ошибку.
class StructuredContentParser {
  const StructuredContentParser();

  StructuredContentParseResult parse(dynamic raw) {
    try {
      final dynamic value = _ensureDecoded(raw);
      if (value is Map<String, dynamic>) {
        final warnings = <String>[];
        final errors = <String>[];
        if (!_isJsonEncodable(value)) {
          warnings.add('Найден(ы) неподдерживаемые типы. Будет выполнена попытка приведения к строкам.');
        }
        // Доп. мягкая проверка: если есть поле summary и оно не String — предупреждение
        if (value.containsKey('summary') && value['summary'] is! String) {
          warnings.add('Поле "summary" не является строкой.');
        }
        return StructuredContentParseResult(data: value, warnings: warnings, errors: errors);
      }
      return const StructuredContentParseResult(
        data: null,
        errors: ['structuredContent должен быть объектом JSON (Map)'],
      );
    } catch (e) {
      return StructuredContentParseResult(
        data: null,
        errors: ['Ошибка парсинга: $e'],
      );
    }
  }

  dynamic _ensureDecoded(dynamic raw) {
    if (raw is String) {
      return jsonDecode(raw);
    }
    return raw;
  }

  bool _isJsonEncodable(dynamic v) {
    try {
      jsonEncode(v);
      return true;
    } catch (_) {
      return false;
    }
  }
}
