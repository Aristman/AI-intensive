import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WorkspaceScreen — трехпанельное окно:
/// - Левая панель: проводник (Desktop)
/// - Центральная панель: вкладки + редактор (пока простая текстовая область)
/// - Правая панель: каркас под будущий пайплайн (без логики агентов)
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  // Корневой путь проводника (Desktop)
  static const String _rootPath = 'D:/projects/ai_intensive/AI-intensive/';

  // Базовое состояние для вкладок и содержимого (MVP каркас)
  final List<String> _tabs = [];
  int _activeTab = -1;
  final Map<String, String> _content = {}; // path -> text
  final Map<String, String> _saved = {}; // path -> last saved text
  final Map<String, TextEditingController> _controllers = {}; // path -> controller
  final Map<String, FocusNode> _focusNodes = {}; // path -> focus node

  // Состояние дерева
  final Map<String, bool> _expanded = {}; // path -> expanded
  final Map<String, List<FileSystemEntity>> _children = {}; // cached listing
  bool _rootLoaded = false;

  Future<void> _openFile(String path) async {
    try {
      final file = File(path);
      final data = await file.readAsString();
      _content[path] = data;
      _saved[path] = data;
      // Инициализируем контроллер и FocusNode один раз на файл
      _controllers.putIfAbsent(path, () => TextEditingController(text: data));
      _focusNodes.putIfAbsent(path, () => FocusNode());
      final idx = _tabs.indexOf(path);
      setState(() {
        if (idx == -1) {
          _tabs.add(path);
          _activeTab = _tabs.length - 1;
        } else {
          _activeTab = idx;
        }
      });
      // Сфокусироваться на редакторе после открытия/активации вкладки
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodes[path]?.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть файл: $e')),
      );
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(index);
      // Не удаляем содержимое из кэша намеренно — на будущее
      if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      }
    });
  }

  Future<void> _ensureChildren(String dirPath) async {
    if (_children.containsKey(dirPath)) return;
    try {
      final dir = Directory(dirPath);
      final list = await dir.list().toList();
      // Сортировка: директории первыми, затем файлы; по имени
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      _children[dirPath] = list;
    } catch (e) {
      _children[dirPath] = const [];
    }
  }

  @override
  void initState() {
    super.initState();
    // Подготовим корневой список при первом отображении (лениво)
    _expanded[_rootPath] = true;
    _ensureChildren(_rootPath).then((_) {
      if (mounted) setState(() => _rootLoaded = true);
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
          child: _rootLoaded
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [_buildDirNode(_rootPath)],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildDirNode(String dirPath) {
    final name = dirPath == _rootPath
        ? dirPath
        : dirPath.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;
    final isExpanded = _expanded[dirPath] ?? false;
    final items = _children[dirPath] ?? const <FileSystemEntity>[];

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey(dirPath),
        title: Row(
          children: [
            const Icon(Icons.folder),
            const SizedBox(width: 8),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (v) async {
          setState(() => _expanded[dirPath] = v);
          if (v) {
            await _ensureChildren(dirPath);
            if (mounted) setState(() {});
          }
        },
        children: [
          if (!_children.containsKey(dirPath))
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            ...items.map((e) {
              if (e is Directory) {
                return _buildDirNode(e.path);
              } else if (e is File) {
                final fname = e.path.split(RegExp(r'[\\/]')).last;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(fname, overflow: TextOverflow.ellipsis),
                  onTap: () => _openFile(e.path),
                );
              } else {
                return const SizedBox.shrink();
              }
            }),
        ],
      ),
    );
  }

  Widget _buildCenterPane(BuildContext context) {
    final hasTabs = _tabs.isNotEmpty && _activeTab >= 0;
    final path = hasTabs ? _tabs[_activeTab] : '';
    // Получаем (или создаём) контроллер для текущего файла, не пересоздавая его на каждый build
    final controller = hasTabs
        ? (_controllers[path] ??= TextEditingController(text: _content[path] ?? ''))
        : null;
    final focusNode = hasTabs ? (_focusNodes[path] ??= FocusNode()) : null;
    final isDirty = hasTabs ? (_content[path] != _saved[path]) : false;

    final editor = Column(
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
                        onTap: () {
                          setState(() => _activeTab = i);
                          // Возвращаем фокус в редактор текущей вкладки
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final path = _tabs[i];
                            _focusNodes[path]?.requestFocus();
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            (() {
                              final tabPath = _tabs[i];
                              final fileName = tabPath.split(RegExp(r'[\\/]')).last;
                              final dirty = (_content[tabPath] != _saved[tabPath]);
                              return dirty ? '$fileName ●' : fileName;
                            })(),
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
        // Панель действий редактора
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: hasTabs ? () => _saveCurrent(path) : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Сохранить (Ctrl+S)'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: hasTabs ? () => _reloadCurrent(path) : null,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Перезагрузить'),
              ),
              const Spacer(),
              if (hasTabs)
                Text(
                  isDirty ? 'Несохранённые изменения' : 'Сохранено',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDirty ? Colors.orange.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        // Редактор (пока многострочное поле)
        Expanded(
          child: hasTabs
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    key: const ValueKey('workspace_editor'),
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (v) => setState(() => _content[path] = v),
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

    // Горячие клавиши: Ctrl+S (сохранить), Ctrl+W (закрыть вкладку), Ctrl+Tab (переключить)
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (hasTabs) _saveCurrent(path);
        },
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          if (hasTabs) _closeTab(_activeTab);
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
          if (_tabs.length > 1) setState(() => _activeTab = (_activeTab + 1) % _tabs.length);
        },
      },
      child: editor,
    );
  }

  Future<void> _saveCurrent(String path) async {
    try {
      final file = File(path);
      await file.writeAsString(_content[path] ?? '');
      setState(() {
        _saved[path] = _content[path] ?? '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл сохранён')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    }
  }

  Future<void> _reloadCurrent(String path) async {
    try {
      final file = File(path);
      final data = await file.readAsString();
      setState(() {
        _content[path] = data;
        _saved[path] = data;
        final c = _controllers[path];
        if (c != null && c.text != data) {
          // Обновляем текст контроллера без потери фокуса
          c.text = data;
          c.selection = TextSelection.collapsed(offset: data.length);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка перезагрузки: $e')),
      );
    }
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
