import 'dart:convert';
import 'package:http/http.dart' as http;
import '../error/exceptions.dart';

class NetworkUtils {
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Map<String, String> getHeaders(String? apiKey) {
    final headers = Map<String, String>.from(defaultHeaders);
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  static dynamic handleResponse(http.Response response) {
    switch (response.statusCode) {
      case 200:
      case 201:
        final responseJson = json.decode(response.body);
        return responseJson;
      case 400:
        throw BadRequestException('Bad Request', response.statusCode);
      case 401:
      case 403:
        throw UnauthorizedException('Unauthorized', response.statusCode);
      case 404:
        throw NotFoundException('Not Found', response.statusCode);
      case 500:
      default:
        throw ServerException('Server Error', statusCode: response.statusCode);
    }
  }

  static String getErrorMessage(dynamic error) {
    if (error is ServerException) {
      return error.message;
    } else if (error is FormatException) {
      return 'Invalid response format';
    } else if (error is Exception) {
      return 'Unexpected error occurred';
    } else {
      return 'Something went wrong';
    }
  }
}
