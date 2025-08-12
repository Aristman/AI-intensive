import 'package:flutter/material.dart';
import 'package:sample_app/features/chat/presentation/pages/chat_screen.dart';
import 'package:sample_app/features/requirements_agent/presentation/pages/requirements_agent_screen.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:get_it/get_it.dart';
import 'package:sample_app/core/config/app_config.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) {
            final appConfig = GetIt.I<AppConfig>();
            // Загружаем сохранённые настройки, чтобы получить jsonSchema (если выбран JSON)
            return FutureBuilder<AppSettings>(
              future: SettingsService().getSettings(),
              builder: (context, snapshot) {
                final appSettings = snapshot.data ?? const AppSettings();
                final model = appConfig.defaultModel;
                final systemPrompt = appConfig.defaultSystemPrompt;
                final jsonSchema = appSettings.responseFormat == ResponseFormat.json
                    ? appSettings.customJsonSchema
                    : null;

                return ChatScreen(
                  model: model,
                  systemPrompt: systemPrompt,
                  jsonSchema: jsonSchema,
                );
              },
            );
          },
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) {
            return FutureBuilder<AppSettings>(
              future: SettingsService().getSettings(),
              builder: (context, snapshot) {
                final appSettings = snapshot.data ?? const AppSettings();
                return SettingsScreen(
                  initialSettings: appSettings,
                  onSettingsChanged: (newSettings) async {
                    // Сохраняем обновлённые настройки
                    await SettingsService().saveSettings(newSettings);
                  },
                );
              },
            );
          },
        );
      case '/requirements-agent':
        return MaterialPageRoute(
          builder: (_) => const RequirementsAgentScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
