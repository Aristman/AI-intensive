import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/dart.dart' as dart_lang;
import 'package:highlight/languages/javascript.dart' as js_lang;
import 'package:highlight/languages/typescript.dart' as ts_lang;
import 'package:highlight/languages/json.dart' as json_lang;
import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:highlight/languages/markdown.dart' as md_lang;
import 'package:highlight/languages/kotlin.dart' as kt_lang;
import 'package:highlight/languages/java.dart' as java_lang;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

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
  static const String _prefsOpenTabsKey = 'workspace_open_tabs';
  static const String _prefsActiveTabKey = 'workspace_active_tab';
  static const String _prefsExpandedDirsKey = 'workspace_expanded_dirs';

  // Базовое состояние для вкладок и содержимого (MVP каркас)
  final List<String> _tabs = [];
  int _activeTab = -1;
  final Map<String, String> _content = {}; // path -> text
  final Map<String, String> _saved = {}; // path -> last saved text
  final Map<String, CodeController> _controllers = {}; // path -> controller
  final Map<String, FocusNode> _focusNodes = {}; // path -> focus node

  // Состояние дерева
  final Map<String, bool> _expanded = {}; // path -> expanded
  final Map<String, List<FileSystemEntity>> _children = {}; // cached listing
  bool _rootLoaded = false;
  final ScrollController _treeScroll = ScrollController();
  final Map<String, GlobalKey> _fileKeys = {}; // path -> key for ensureVisible

  // Правая панель — каркас ленты событий/сообщений
  final List<String> _pipelineLog = [];
  final TextEditingController _pipelineInput = TextEditingController();
  final ScrollController _pipelineScroll = ScrollController();

  Future<void> _openFile(String path, {bool requestFocus = true}) async {
    try {
      final file = File(path);
      final data = await file.readAsString();
      _content[path] = data;
      _saved[path] = data;
      // Инициализируем контроллер и FocusNode один раз на файл
      _controllers.putIfAbsent(path, () => CodeController(
            text: data,
            language: _languageForPath(path),
          ));
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
      // Сохранить состояние вкладок
      _persistState();
      // Сфокусироваться на редакторе после открытия/активации вкладки
      if (requestFocus) {
        // Авто‑раскрыть родителей файла в дереве, чтобы можно было проскроллить к нему
        await _expandParentsForPath(path);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodes[path]?.requestFocus();
          final key = _fileKeys[path];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть файл: $e')),
      );
    }
  }

  // Сохранение/восстановление состояния дерева (раскрытые папки)
  Future<void> _persistTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expanded = _expanded.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList(growable: false);
      await prefs.setStringList(_prefsExpandedDirsKey, expanded);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _restoreTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expanded = prefs.getStringList(_prefsExpandedDirsKey) ?? const <String>[];
      if (expanded.isEmpty) return;
      // Сортируем по глубине, чтобы сначала грузить родителей
      final sorted = [...expanded]
        ..sort((a, b) => _depth(a).compareTo(_depth(b)));
      for (final d in sorted) {
        _expanded[d] = true;
        await _ensureChildren(d);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    }
  }

  int _depth(String path) {
    final norm = path.replaceAll('\\', '/');
    return norm.split('/').where((e) => e.isNotEmpty).length;
  }

  // Автораскрытие родительских директорий для файла
  Future<void> _expandParentsForPath(String filePath) async {
    try {
      String root = p.normalize(_rootPath).replaceAll('\\', '/');
      String file = p.normalize(filePath).replaceAll('\\', '/');
      String parent = p.normalize(p.dirname(file)).replaceAll('\\', '/');
      if (!parent.startsWith(root)) return;
      final rootParts = p.split(root);
      final parentParts = p.split(parent);
      // Формируем последовательность директорий от root к parent
      for (int i = rootParts.length; i <= parentParts.length; i++) {
        final dir = p.joinAll(parentParts.sublist(0, i)).replaceAll('\\', '/');
        if (dir.isEmpty) continue;
        _expanded[dir] = true;
        await _ensureChildren(dir);
      }
      _persistTree();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    }
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final path = _tabs[index];
    final dirty = (_content[path] != _saved[path]);
    var allowClose = true;
    if (dirty) {
      allowClose = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Несохранённые изменения'),
              content: Text('Закрыть вкладку и потерять изменения в «${path.split(RegExp(r"[\\/]")).last}»?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!allowClose) return;
    setState(() {
      _tabs.removeAt(index);
      // Не удаляем содержимое из кэша намеренно — на будущее
      if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      }
    });
    _persistState();
    if (_activeTab >= 0) {
      // Центрирование и раскрытие активного файла после закрытия предыдущего
      final pathNow = _tabs[_activeTab];
      await _expandParentsForPath(pathNow);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _fileKeys[pathNow];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
      });
    }
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
      if (!mounted) return;
      setState(() => _rootLoaded = true);
      // Восстановим структуру дерева (раскрытые папки)
      _restoreTree();
    });
    // Восстановление состояния вкладок
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreState();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _pipelineInput.dispose();
    _pipelineScroll.dispose();
    _treeScroll.dispose();
    super.dispose();
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
                  controller: _treeScroll,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [_buildDirNode(_rootPath, 0)],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildDirNode(String dirPath, int depth) {
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
            SizedBox(width: (depth * 12).toDouble()),
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
          _persistTree();
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
                return _buildDirNode(e.path, depth + 1);
              } else if (e is File) {
                final fname = e.path.split(RegExp(r'[\\/]')).last;
                final bool isActive = _tabs.isNotEmpty && _activeTab >= 0 && _tabs[_activeTab] == e.path;
                final key = _fileKeys.putIfAbsent(e.path, () => GlobalKey());
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.only(left: ((depth + 1) * 12).toDouble(), right: 8),
                  key: key,
                  leading: Icon(Icons.insert_drive_file_outlined,
                      color: isActive ? Theme.of(context).colorScheme.primary : null),
                  selected: isActive,
                  selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                  title: Text(
                    fname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                    ),
                  ),
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

  // Определение языка подсветки по расширению файла
  dynamic _languageForPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.dart')) return dart_lang.dart;
    if (p.endsWith('.js')) return js_lang.javascript;
    if (p.endsWith('.ts')) return ts_lang.typescript;
    if (p.endsWith('.json')) return json_lang.json;
    if (p.endsWith('.yaml') || p.endsWith('.yml')) return yaml_lang.yaml;
    if (p.endsWith('.md')) return md_lang.markdown;
    if (p.endsWith('.kt')) return kt_lang.kotlin;
    if (p.endsWith('.java')) return java_lang.java;
    return null; // без подсветки
  }

  Widget _buildCenterPane(BuildContext context) {
    final hasTabs = _tabs.isNotEmpty && _activeTab >= 0;
    final path = hasTabs ? _tabs[_activeTab] : '';
    // Получаем (или создаём) контроллер для текущего файла, не пересоздавая его на каждый build
    final controller = hasTabs
        ? (_controllers[path] ??= CodeController(
              text: _content[path] ?? '',
              language: _languageForPath(path),
            ))
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
                        onTap: () => _activateTabByIndex(i),
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
                  child: CodeTheme(
                    data: CodeThemeData(styles: githubTheme),
                    child: CodeField(
                      key: const ValueKey('workspace_editor'),
                      controller: controller!,
                      focusNode: focusNode,
                      textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      expands: true,
                      onChanged: (v) => setState(() => _content[path] = v),
                    ),
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
          if (_tabs.length > 1) {
            final next = (_activeTab + 1) % _tabs.length;
            _activateTabByIndex(next);
          }
        },
      },
      child: editor,
    );
  }

  Future<void> _activateTabByIndex(int i) async {
    if (i < 0 || i >= _tabs.length) return;
    setState(() => _activeTab = i);
    _persistState();
    final path = _tabs[i];
    await _expandParentsForPath(path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[path]?.requestFocus();
      final key = _fileKeys[path];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        );
      }
    });
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
        // Лента сообщений/событий (локальная, без агентов)
        Expanded(
          child: _pipelineLog.isEmpty
              ? const Center(
                  child: Text('Лента пуста. Введите сообщение ниже и нажмите Отправить.'),
                )
              : ListView.builder(
                  controller: _pipelineScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _pipelineLog.length,
                  itemBuilder: (context, index) {
                    final msg = _pipelineLog[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Text(msg),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        // Ввод и кнопка отправки (локальная запись в ленту)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pipelineInput,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Сообщение',
                  ),
                  onSubmitted: (_) => _sendPipelineMessage(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _pipelineInput.text.trim().isEmpty ? null : _sendPipelineMessage,
                icon: const Icon(Icons.send),
                label: const Text('Отправить'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsOpenTabsKey, List<String>.from(_tabs));
      await prefs.setInt(_prefsActiveTabKey, _activeTab);
    } catch (_) {
      // ignore MVP storage errors
    }
  }

  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTabs = prefs.getStringList(_prefsOpenTabsKey) ?? const <String>[];
      final savedActive = prefs.getInt(_prefsActiveTabKey) ?? -1;
      for (final p in savedTabs) {
        if (await File(p).exists()) {
          await _openFile(p, requestFocus: false);
        }
      }
      if (savedActive >= 0 && savedActive < _tabs.length) {
        setState(() => _activeTab = savedActive);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final path = _tabs[_activeTab];
          _focusNodes[path]?.requestFocus();
        });
      }
    } catch (_) {
      // ignore MVP restore errors
    }
  }

  void _sendPipelineMessage() {
    final text = _pipelineInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _pipelineLog.add(text);
      _pipelineInput.clear();
    });
    // Прокрутить к концу после добавления
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pipelineScroll.hasClients) {
        _pipelineScroll.animateTo(
          _pipelineScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
