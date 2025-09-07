import 'package:flutter/material.dart';

/// WorkspaceScreen — трехпанельное окно:
/// - Левая панель: проводник (пока заглушка)
/// - Центральная панель: вкладки + редактор (пока простая текстовая область)
/// - Правая панель: каркас под будущий пайплайн (без логики агентов)
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  // Базовое состояние для вкладок и содержимого (MVP каркас)
  final List<String> _tabs = [];
  int _activeTab = -1;
  final Map<String, String> _content = {}; // path -> text

  void _openFilePlaceholder(String path) {
    // В MVP открываем фиктивные файлы, дальше будет чтение с диска
    if (!_content.containsKey(path)) {
      _content[path] = '// $path\n// Здесь будет содержимое файла после интеграции с ФС.';
    }
    final idx = _tabs.indexOf(path);
    setState(() {
      if (idx == -1) {
        _tabs.add(path);
        _activeTab = _tabs.length - 1;
      } else {
        _activeTab = idx;
      }
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      final closingPath = _tabs.removeAt(index);
      // Не удаляем содержимое из кэша намеренно — на будущее
      if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            // Левая панель — проводник (заглушка)
            SizedBox(
              width: 260,
              child: _buildLeftPane(context),
            ),
            const VerticalDivider(width: 1),
            // Центральная панель — вкладки + редактор
            Expanded(
              child: _buildCenterPane(context),
            ),
            const VerticalDivider(width: 1),
            // Правая панель — каркас под будущий пайплайн
            SizedBox(
              width: 300,
              child: _buildRightPane(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Text(
            'Файлы',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Временные элементы для демонстрации открытия вкладок
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('README.md'),
                onTap: () => _openFilePlaceholder('README.md'),
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('lib/main.dart'),
                onTap: () => _openFilePlaceholder('lib/main.dart'),
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('lib/screens/workspace_screen.dart'),
                onTap: () => _openFilePlaceholder('lib/screens/workspace_screen.dart'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterPane(BuildContext context) {
    final hasTabs = _tabs.isNotEmpty && _activeTab >= 0;
    final path = hasTabs ? _tabs[_activeTab] : '';
    final controller = TextEditingController(text: hasTabs ? _content[path] ?? '' : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Вкладки
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < _tabs.length; i++)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: i == _activeTab
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _activeTab = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            _tabs[i],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _closeTab(i),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.close, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Редактор (пока многострочное поле)
        Expanded(
          child: hasTabs
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    key: const ValueKey('workspace_editor'),
                    controller: controller,
                    onChanged: (v) => _content[path] = v,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: path,
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                )
              : const Center(
                  child: Text('Откройте файл из левой панели, чтобы начать работу'),
                ),
        ),
      ],
    );
  }

  Widget _buildRightPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Text(
            'Правая панель',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Здесь будет диалог/лог будущего пайплайна. На данном этапе интеграции нет.',
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            enabled: false,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Ввод (отключено)',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.send),
            label: const Text('Отправить'),
          ),
        ),
      ],
    );
  }
}
