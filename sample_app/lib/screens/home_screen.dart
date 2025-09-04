import 'package:flutter/material.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/screens/screens.dart';
import 'package:sample_app/services/auth_service.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/widgets/login_dialog.dart';

class HomeScreen extends StatefulWidget {
  final int? initialIndex;
  const HomeScreen({super.key, this.initialIndex});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _settingsService = SettingsService();
  AppSettings? _settings;
  bool _loading = true;
  int _version = 0; // bump to recreate child pages after settings change
  final AuthService _auth = AuthService();

  // MCP runtime state
  bool _mcpChecking = false;
  bool _mcpReady = false;
  String? _mcpError;
  List<String> _mcpTools = const [];

  @override
  void initState() {
    super.initState();
    // Восстанавливаем сохранённые креды
    _auth.load();
    if (widget.initialIndex != null) {
      final idx = widget.initialIndex!;
      final maxIdx = Screen.values.length - 1;
      _index = idx < 0
          ? 0
          : (idx > maxIdx ? maxIdx : idx);
    }
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _settingsService.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
    // Refresh MCP status once settings are loaded (fire-and-forget)
    _refreshMcpStatus();
  }

  Future<void> _refreshMcpStatus() async {
    final s = _settings;
    if (s == null || !s.useMcpServer || (s.mcpServerUrl?.trim().isNotEmpty != true)) {
      if (!mounted) return;
      setState(() {
        _mcpChecking = false;
        _mcpReady = false;
        _mcpError = null;
        _mcpTools = const [];
      });
      return;
    }
    setState(() {
      _mcpChecking = true;
      _mcpError = null;
      _mcpTools = const [];
      _mcpReady = false;
    });
    final client = McpClient();
    try {
      await client.connect(s.mcpServerUrl!.trim());
      await client.initialize(timeout: const Duration(seconds: 4));
      final list = await client.toolsList(timeout: const Duration(seconds: 6));
      // ожидаем { tools: [ { name, description? }, ... ] }
      final tools = <String>[];
      final arr = list['tools'];
      if (arr is List) {
        for (final t in arr) {
          if (t is Map && t['name'] is String) tools.add(t['name'] as String);
        }
      }
          if (!mounted) return;
      setState(() {
        _mcpChecking = false;
        _mcpReady = true;
        _mcpTools = tools;
        _mcpError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mcpChecking = false;
        _mcpReady = false;
        _mcpError = e.toString();
        _mcpTools = const [];
      });
    } finally {
      await client.close();
    }
  }

  Widget _mcpStatusChip() {
    final s = _settings;
    final configured = s != null && s.useMcpServer && (s.mcpServerUrl?.trim().isNotEmpty ?? false);
    Color bg;
    Color border;
    Color fg;
    String label;
    String tooltip;
    if (!configured) {
      bg = Colors.grey.shade200;
      border = Colors.grey.shade300;
      fg = Colors.grey.shade700;
      label = 'MCP off';
      tooltip = 'MCP отключен (используется fallback-делегат)';
    } else if (_mcpChecking) {
      bg = Colors.amber.shade50;
      border = Colors.amber.shade200;
      fg = Colors.amber.shade700;
      label = 'MCP checking';
      tooltip = 'Проверка MCP по адресу: ${s.mcpServerUrl}';
    } else if (_mcpReady) {
      bg = Colors.blue.shade50;
      border = Colors.blue.shade200;
      fg = Colors.blue.shade700;
      label = 'MCP ready';
      final toolsStr = _mcpTools.isEmpty ? 'нет доступных инструментов' : _mcpTools.join(', ');
      tooltip = 'MCP: ${s.mcpServerUrl}\nИнструменты: $toolsStr';
    } else {
      bg = Colors.red.shade50;
      border = Colors.red.shade200;
      fg = Colors.red.shade700;
      label = 'MCP error';
      tooltip = 'Ошибка MCP: ${_mcpError ?? 'неизвестно'}';
    }
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.integration_instructions, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _networkChip() {
    final s = _settings;
    final text = s == null
        ? '-'
        : switch (s.selectedNetwork) {
            NeuralNetwork.deepseek => 'DeepSeek',
            NeuralNetwork.yandexgpt => 'YandexGPT',
            NeuralNetwork.tinylama => 'TinyLlama',
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.memory, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    if (_settings == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _settings!,
          onSettingsChanged: (ns) {
            if (!mounted) return;
            setState(() {
              _settings = ns;
              _version++; // recreate child pages to re-read settings
            });
            // Re-check MCP on settings change (fire-and-forget)
            _refreshMcpStatus();
          },
        ),
      ),
    );
  }

  Future<void> _handleAuthButton() async {
    final res = await showLoginDialog(context);
    if (res != null) {
      _auth.setCredentials(token: res.token, login: res.login);
    } else {
      _auth.clear();
    }
  }

  Widget _userLabel() {
    return AnimatedBuilder(
      animation: _auth,
      builder: (context, _) {
        final text = _auth.isLoggedIn
            ? 'Пользователь — ${_auth.login ?? '-'}'
            : 'Пользователь — Гость';
        return Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = Screen.values.map((s) => screenFactories[s]!(_version)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(Screen.values[_index].label),
            const SizedBox(width: 8),
            _mcpStatusChip(),
            const SizedBox(width: 12),
            _userLabel(),
          ],
        ),
        actions: [
          // Глобальная кнопка Войти/Выйти
          AnimatedBuilder(
            animation: _auth,
            builder: (context, _) {
              final loggedIn = _auth.isLoggedIn;
              return IconButton(
                icon: Icon(loggedIn ? Icons.logout : Icons.login),
                tooltip: loggedIn ? 'Выйти' : 'Войти',
                onPressed: _handleAuthButton,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _networkChip(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: _openSettings,
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _index,
              children: pages,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: Screen.values
            .map((s) => NavigationDestination(
                  icon: s.icon,
                  selectedIcon: s.selectedIcon,
                  label: s.label,
                ))
            .toList(),
      ),
    );
  }
}
