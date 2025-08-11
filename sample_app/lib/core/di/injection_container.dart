import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:sample_app/features/chat/chat.dart';
import 'package:sample_app/features/chat/data/datasources/chat_remote_data_source_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../network/api_service.dart';
import '../storage/local_storage_service.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/chat/domain/usecases/send_message_use_case.dart';
import '../../features/chat/domain/usecases/get_chat_history_use_case.dart';
import '../../features/chat/domain/usecases/save_message_use_case.dart';
import '../../features/chat/domain/usecases/clear_chat_history_use_case.dart';

final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  try {
    // Register AppConfig first as it's needed by other services
    sl.registerLazySingleton<AppConfig>(() => AppConfig());
    
    // Initialize AppConfig
    await sl<AppConfig>().init();
    
    // External dependencies
    final sharedPreferences = await SharedPreferences.getInstance();
    sl.registerLazySingleton<SharedPreferences>(() => sharedPreferences);
    
    // Logger
    final logger = Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        colors: true,
        printEmojis: true,
      ),
    );
    sl.registerLazySingleton<Logger>(() => logger);

    // HTTP client
    final dio = Dio(
      BaseOptions(
        baseUrl: sl.get<AppConfig>().deepSeekBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    )..interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: true,
          responseHeader: true,
          error: true,
          logPrint: (object) => logger.d(object),
        ),
      );
    
    sl.registerLazySingleton<Dio>(() => dio);

    // Core services
    sl.registerLazySingleton<LocalStorageService>(
      () => LocalStorageServiceImpl(sharedPreferences: sl()),
    );

    // API Service
    sl.registerLazySingleton<ApiService>(
      () => ApiService(
        dio: dio,
        logger: logger,
        apiKey: sl<AppConfig>().deepSeekApiKey,
        baseUrl: sl<AppConfig>().deepSeekBaseUrl,
      ),
    );

    // Initialize features
    await _initChatFeature();
    
    sl<Logger>().i('Dependency injection initialized successfully');
  } catch (e, stackTrace) {
    sl<Logger>().e(
      'Failed to initialize dependencies',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

Future<void> _initChatFeature() async {
  try {
    // Data Sources
    sl.registerLazySingleton<ChatLocalDataSource>(
      () => ChatLocalDataSourceImpl(localStorageService: sl()),
    );

    sl.registerLazySingleton<ChatRemoteDataSource>(
      () => ChatRemoteDataSourceImpl(
        apiService: sl(),
        dio: sl<Dio>(),
        logger: sl<Logger>(),
        deepSeekApiKey: sl<AppConfig>().deepSeekApiKey,
        yandexApiKey: sl<AppConfig>().yandexApiKey,
        yandexFolderId: sl<AppConfig>().yandexFolderId,
      ),
    );

    // Repository
    sl.registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImpl(
        remoteDataSource: sl(),
        localDataSource: sl(),
      ),
    );

    // Use Cases
    sl.registerLazySingleton(() => SendMessageUseCase(sl()));
    sl.registerLazySingleton(() => GetChatHistoryUseCase(sl()));
    sl.registerLazySingleton(() => SaveMessageUseCase(sl()));
    sl.registerLazySingleton(() => ClearChatHistoryUseCase(sl()));

    // BLoC
    sl.registerFactory(
      () => ChatBloc(
        sendMessageUseCase: sl(),
        getChatHistoryUseCase: sl(),
        clearChatHistoryUseCase: sl(),
      ),
    );
    
    sl<Logger>().d('Chat feature dependencies initialized');
  } catch (e, stackTrace) {
    sl<Logger>().e(
      'Failed to initialize chat feature dependencies',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

/// Helper function to register lazy singletons with dependencies and automatic disposal
void _registerLazySingletonWithDependencies<T extends Object>(
  T Function() factoryFunc, {
  List<Type> dependsOn = const [],
}) {
  sl.registerLazySingleton<T>(
    factoryFunc,
    dispose: (instance) {
      if (instance is Disposable) {
        instance.dispose();
      }
    },
  );
}

/// For services that need cleanup
abstract class Disposable {
  /// Dispose method to clean up resources
  void dispose();
}

/// Extension on GetIt to provide better type safety
extension GetItX on GetIt {
  /// Get an instance of type T
  T get<T extends Object>([String? instanceName]) => get<T>();
  
  /// Get an async instance of type T
  Future<T> getAsync<T extends Object>([String? instanceName]) => getAsync<T>();
  
  /// Register a lazy singleton with type safety
  void registerLazySingleton<T extends Object>(
    T Function() factoryFunc, {
    String? instanceName,
    DisposingFunc<T>? dispose,
  }) {
    registerLazySingleton<T>(
      factoryFunc,
      instanceName: instanceName,
      dispose: dispose,
    );
  }
}
