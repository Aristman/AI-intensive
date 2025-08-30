import 'package:flutter/material.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/screens/screens.dart';

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

  @override
  void initState() {
    super.initState();
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
  }

  Widget _mcpStatusChip() {
    final s = _settings;
    final mcpConfigured = s != null && s.useMcpServer && (s.mcpServerUrl?.trim().isNotEmpty ?? false);
    Color bg;
    Color border;
    Color fg;
    String label;
    if (mcpConfigured) {
      bg = Colors.blue.shade50;
      border = Colors.blue.shade200;
      fg = Colors.blue.shade700;
      label = 'MCP ready';
    } else {
      bg = Colors.grey.shade200;
      border = Colors.grey.shade300;
      fg = Colors.grey.shade700;
      label = 'MCP off';
    }
    final tooltip = mcpConfigured
        ? 'MCP сервер: ${s.mcpServerUrl}'
        : 'MCP отключен (используется fallback-делегат)';
    return Tooltip(
      message: tooltip,
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
            Icon(
              Icons.integration_instructions,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
            ),
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
          },
        ),
      ),
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
          ],
        ),
        actions: [
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
