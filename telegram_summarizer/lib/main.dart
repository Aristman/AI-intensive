import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/ui/chat_screen.dart';
import 'package:telegram_summarizer/data/llm/yandex_gpt_usecase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env', mergeWith: const {});

  final settings = SettingsState();
  await settings.load();

  final llm = YandexGptUseCase();
  final chat = ChatState(llm);
  await chat.load();

  runApp(MyApp(settings: settings, chat: chat));
}

class MyApp extends StatelessWidget {
  final SettingsState settings;
  final ChatState chat;
  const MyApp({super.key, required this.settings, required this.chat});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsState>.value(value: settings),
        ChangeNotifierProvider<ChatState>.value(value: chat),
      ],
      child: MaterialApp(
        title: 'Telegram Summarizer',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const ChatScreen(),
      ),
    );
  }
}
