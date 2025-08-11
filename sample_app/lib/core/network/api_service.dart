import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../error/exceptions.dart';
import '../utils/constants.dart';

class ApiService {
  final Dio _dio;
  final String baseUrl;
  String? _apiKey;
  final Logger _logger;

  final Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  ApiService({
    required Dio dio,
    required Logger logger,
    String? apiKey,
    this.baseUrl = AppConstants.baseUrl,
  })  : _dio = dio,
        _logger = logger,
        _apiKey = apiKey {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: _defaultHeaders,
    );

    if (_apiKey != null) {
      _addAuthInterceptor();
    }
  }

  void _addAuthInterceptor() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_apiKey != null) {
            options.headers['Authorization'] = 'Bearer $_apiKey';
          }
          return handler.next(options);
        },
      ),
    );
  }

  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    try {
      _logger.d('GET $endpoint');
      
      final response = await _dio.get<dynamic>(
        endpoint,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          extra: {'requireAuth': requireAuth},
        ),
      );
      
      return response.data;
    } on DioException catch (e) {
      _handleDioError(e, 'GET', endpoint);
    } catch (e, stackTrace) {
      _logger.e('Unexpected error in GET $endpoint', 
                error: e, 
                stackTrace: stackTrace);
      throw ServerException('An unexpected error occurred');
    }
  }

  Future<dynamic> post(
    String endpoint, {
    dynamic body,
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    try {
      _logger.d('POST $endpoint');
      
      final response = await _dio.post<dynamic>(
        endpoint,
        data: body,
        options: Options(
          headers: headers,
          extra: {'requireAuth': requireAuth},
        ),
      );
      
      return response.data;
    } on DioException catch (e) {
      _handleDioError(e, 'POST', endpoint);
    } catch (e, stackTrace) {
      _logger.e('Unexpected error in POST $endpoint', 
                error: e, 
                stackTrace: stackTrace);
      throw ServerException('An unexpected error occurred');
    }
  }

  void setApiKey(String? key) {
    _apiKey = key;
    if (key != null) {
      _addAuthInterceptor();
    }
  }

  /// Handles Dio-specific errors and throws appropriate exceptions
  Never _handleDioError(DioException error, String method, String endpoint) {
    _logger.e(
      'Error in $method $endpoint',
      error: error,
      stackTrace: error.stackTrace,
    );

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        throw ServerException('Connection timeout. Please check your internet connection.');
      
      case DioExceptionType.badCertificate:
        throw ServerException('Invalid certificate. Please try again later.');
      
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        
        String message = 'An error occurred';
        if (data is Map) {
          message = data['error']?['message'] ??
                   data['message'] ??
                   data['error']?.toString() ??
                   message;
        } else if (data is String) {
          message = data;
        }
        
        switch (statusCode) {
          case 400:
            throw BadRequestException(message);
          case 401:
            throw UnauthorizedException(message);
          case 403:
            throw ForbiddenException(message);
          case 404:
            throw NotFoundException(message);
          case 429:
            throw RateLimitExceededException(message);
          case 500:
          case 501:
          case 502:
          case 503:
            throw ServerException('Server error: $message', statusCode: statusCode);
          default:
            throw ServerException('HTTP error $statusCode: $message', statusCode: statusCode);
        }
      
      case DioExceptionType.cancel:
        throw CanceledException('Request was cancelled');
      
      case DioExceptionType.connectionError:
        throw ServerException('Connection error. Please check your internet connection.');
      
      case DioExceptionType.unknown:
        if (error.error?.toString().contains('SocketException') == true) {
          throw ServerException('No internet connection. Please check your network settings.');
        }
        throw ServerException(error.message ?? 'An unknown error occurred');
    }
  }
}
