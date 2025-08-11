class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}

class ServerException implements Exception {
  final String message;
  final int? statusCode;

  ServerException(this.message, {this.statusCode});

  @override
  String toString() => 'ServerException: $message';
}

class CacheException implements Exception {
  final String message;

  CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

class ValidationException implements Exception {
  final String message;

  ValidationException(this.message);

  @override
  String toString() => 'ValidationException: $message';
}

class BadRequestException implements Exception {
  final String message;

  BadRequestException(this.message, [int? statusCode]);

  @override
  String toString() => 'BadRequestException: $message';
}

class UnauthorizedException implements Exception {
  final String message;

  UnauthorizedException(this.message, [int? statusCode]);

  @override
  String toString() => 'UnauthorizedException: $message';
}

class ForbiddenException implements Exception {
  final String message;

  ForbiddenException(this.message);

  @override
  String toString() => 'ForbiddenException: $message';
}

class NotFoundException implements Exception {
  final String message;
  final int? statusCode;

  NotFoundException(this.message, [this.statusCode]);

  @override
  String toString() => 'NotFoundException: $message';
}

class RateLimitExceededException implements Exception {
  final String message;

  RateLimitExceededException(this.message);

  @override
  String toString() => 'RateLimitExceededException: $message';
}

class CanceledException implements Exception {
  final String message;

  CanceledException(this.message);

  @override
  String toString() => 'CanceledException: $message';
}
