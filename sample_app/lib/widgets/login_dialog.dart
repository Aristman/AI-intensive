import 'package:flutter/material.dart';

class LoginResult {
  final String token;
  final String login;
  const LoginResult({required this.token, required this.login});
}

/// Диалог мок-логина. Возвращает LoginResult при успешном входе или null при гостевом входе/отмене.
/// Использование:
///   final res = await showLoginDialog(context);
///   if (res != null) auth.setCredentials(token: res.token, login: res.login);
Future<LoginResult?> showLoginDialog(BuildContext context) {
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  return showDialog<LoginResult?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Вход'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: loginCtrl,
              decoration: const InputDecoration(labelText: 'Логин'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(labelText: 'Пароль'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Гостевой вход
              Navigator.of(ctx).pop(null);
            },
            child: const Text('Зайти гостем'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(null);
            },
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final login = loginCtrl.text.trim().isEmpty ? 'user' : loginCtrl.text.trim();
              final token = 'mock_${DateTime.now().millisecondsSinceEpoch}_$login';
              Navigator.of(ctx).pop(LoginResult(token: token, login: login));
            },
            child: const Text('Войти'),
          ),
        ],
      );
    },
  );
}
