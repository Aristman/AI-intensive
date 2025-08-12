import 'package:flutter/material.dart';

import 'app_router.dart';
import 'models/app_settings.dart';
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
    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        return MaterialApp(
          title: 'AI Assistant',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              elevation: 2,
            ),
          ),
          onGenerateRoute: AppRouter.generateRoute,
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
