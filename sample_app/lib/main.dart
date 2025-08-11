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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Load environment variables
    await dotenv.load(fileName: "assets/.env");
    
    // Initialize dependency injection (this also initializes AppConfig)
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
  } catch (e, stackTrace) {
    logger.e(
      'Failed to initialize application',
      error: e,
      stackTrace: stackTrace,
    );
    
    // Show error UI if initialization fails
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Failed to initialize application: $e',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
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
