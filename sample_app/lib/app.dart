import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/config/app_config.dart';
import 'core/di/injection_container.dart';
import 'features/chat/chat.dart';
import 'models/app_settings.dart';
import 'screens/settings_screen.dart';
import 'services/settings_service.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late Future<AppSettings> _settingsFuture;
  final _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _settingsFuture = _settingsService.getSettings();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = GetIt.I<AppConfig>();
    
    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const AppSettings();
        
        return MaterialApp(
          title: 'AI Assistant',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          routes: {
            '/': (context) => ChatScreen(
                  model: appConfig.defaultModel,
                  systemPrompt: appConfig.defaultSystemPrompt,
                ),
            '/settings': (context) => SettingsScreen(
                  initialSettings: settings,
                  onSettingsChanged: (newSettings) async {
                    await _settingsService.saveSettings(newSettings);
                    if (mounted) {
                      setState(() {
                        _settingsFuture = Future.value(newSettings);
                      });
                    }
                  },
                ),
          },
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
