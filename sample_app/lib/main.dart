import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/error/exceptions.dart';
import 'core/di/injection_container.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    colors: true,
    printEmojis: true,
  ),
);

class EnvErrorScreen extends StatelessWidget {
  final String errorMessage;

  const EnvErrorScreen({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Configuration Error'),
          backgroundColor: Colors.red,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configuration Error',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 24),
              const Text(
                'How to fix:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. Create a .env file in the root of your project'),
              const Text('2. Add the required environment variables (see ENV_SETUP.md)'),
              const Text('3. Restart the application'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Try to restart the app
                  runApp(const MyApp());
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize AppConfig first to check environment variables
    final appConfig = AppConfig();
    await appConfig.init();
    
    // Initialize dependency injection
    await configureDependencies();
    
    // Get SharedPreferences instance from the service locator
    final prefs = sl<SharedPreferences>();
    
    logger.i('Application started successfully');
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(prefs),
          ),
        ],
        child: const MyApp(),
      ),
    );
  } on Exception catch (e) {
    // Handle configuration errors with a user-friendly screen
    logger.e('Configuration error: $e');
    runApp(EnvErrorScreen(errorMessage: e.toString()));
  } catch (e, stackTrace) {
    logger.e(
      'Failed to initialize application',
      error: e,
      stackTrace: stackTrace,
    );
    
    // Show error UI for other initialization failures
    runApp(EnvErrorScreen(
      errorMessage: 'An unexpected error occurred during startup: $e',
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
