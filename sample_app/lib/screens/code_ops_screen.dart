import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:sample_app/agents/code_ops_builder_agent.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/widgets/safe_send_text_field.dart';
import 'package:sample_app/utils/json_utils.dart';

class CodeOpsScreen extends StatefulWidget {
  const CodeOpsScreen({super.key});

  @override
  State<CodeOpsScreen> createState() => _CodeOpsScreenState();
}

class _CodeOpsScreenState extends State<CodeOpsScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SettingsService _settingsService = SettingsService();

  late AppSettings _settings;
  bool _loadingSettings = true;
  late CodeOpsBuilderAgent _agent;

  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _isUsingMcp = false;
  Timer? _mcpIndicatorTimer;

  // Streaming state
  StreamSubscription<AgentEvent>? _streamSub;
  double? _pipelineProgress; // 0..1 when streaming
  final List<String> _eventLogs = [];
  bool _awaitTestsConfirm = false;
  String? _awaitAction; // 'create_tests' | 'run_tests'

  // Pending code to execute
  String? _pendingEntrypoint;
  // removed unused: _pendingLanguage, _pendingFiles, _awaitLangFor
  List<Map<String, String>>? _lastGeneratedFiles; // keep last code files from stream for deps resolution

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ignore: unused_element
  Widget _mcpStatusChip() {
    final mcpConfigured = _settings.useMcpServer && (_settings.mcpServerUrl?.trim().isNotEmpty ?? false);
    Color bg;
    Color border;
    Color fg;
    String label;
    if (_isUsingMcp) {
      bg = Colors.green.shade100;
      border = Colors.green.shade300;
      fg = Colors.green.shade700;
      label = 'MCP active';
    } else if (mcpConfigured) {
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
        ? 'MCP сервер: ${_settings.mcpServerUrl}'
        : 'MCP отключен (используется fallback-делегат)';
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Tooltip(
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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _openSettings() async {
    await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _settings,
          onSettingsChanged: (settings) {
            if (!mounted) return;
            setState(() {
              _settings = settings;
              // Агент всегда в reasoning режиме
              _agent.updateSettings(_settings.copyWith(reasoningMode: true));
            });
          },
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    _settings = await _settingsService.getSettings();
    // CodeOpsBuilderAgent всегда в reasoning режиме
    _agent = CodeOpsBuilderAgent(baseSettings: _settings.copyWith(reasoningMode: true));
    if (mounted) setState(() => _loadingSettings = false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _looksLikeCode(String text) {
    final t = text.trim();
    if (t.contains('```')) return true;
    if (t.split('\n').length > 3 && (t.contains(';') || t.contains('{') || t.contains('class '))) return true;
    return false;
  }

  // Removed unused helper methods: _classifyIntent, _requestCodeJson

  void _appendMessage(Message m) {
    setState(() => _messages.add(m));
    _scrollToBottom();
  }

  void _handleAgentEvent(AgentEvent e) {
    // Log line
    final stage = e.stage.name;
    final sev = e.severity.name;
    final line = '[$sev/$stage] ${e.message}';
    setState(() {
      if (e.progress != null) _pipelineProgress = e.progress;
      _eventLogs.add(line);
      if (_eventLogs.length > 200) {
        _eventLogs.removeRange(0, _eventLogs.length - 200);
      }
    });

    switch (e.stage) {
      case AgentStage.code_generated:
        final language = e.meta?['language']?.toString();
        final entrypoint = e.meta?['entrypoint']?.toString();
        final files = (e.meta?['files'] as List?)
            ?.map((m) => {
                  'path': m['path'].toString(),
                  'content': m['content'].toString(),
                })
            .cast<Map<String, String>>()
            .toList();
        setState(() {
          _pendingEntrypoint = entrypoint;
          _lastGeneratedFiles = files;
        });
        if (files != null && files.isNotEmpty) {
          final title = 'Код';
          if (files.length > 1) {
            _appendMessage(Message(text: '$title\n\nФайлов: ${files.length}\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
          } else {
            _appendMessage(Message(text: '$title\n\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
          }
          for (final f in files) {
            final payload = jsonEncode({
              'language': language ?? 'java',
              'path': f['path'],
              'content': f['content'],
            });
            final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
            _appendMessage(Message(text: card, isUser: false));
          }
        }
        break;
      case AgentStage.test_generated:
        final language = e.meta?['language']?.toString() ?? 'java';
        final tests = (e.meta?['tests'] as List?)
            ?.map((m) => {
                  'path': m['path'].toString(),
                  'content': m['content'].toString(),
                })
            .cast<Map<String, String>>()
            .toList();
        if (tests != null && tests.isNotEmpty) {
          _appendMessage(Message(text: 'Тесты сгенерированы: ${tests.length} (язык: $language)', isUser: false));
          for (final f in tests) {
            final payload = jsonEncode({
              'language': language,
              'path': f['path'],
              'content': f['content'],
            });
            final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
            _appendMessage(Message(text: card, isUser: false));
          }
        }
        break;
      case AgentStage.ask_create_tests:
        setState(() {
          _awaitTestsConfirm = true;
          _awaitAction = e.meta?['action']?.toString();
        });
        _appendMessage(Message(text: e.message, isUser: false));
        break;
      case AgentStage.pipeline_complete:
        if (e.message.trim().isNotEmpty) {
          _appendMessage(Message(text: e.message, isUser: false));
        }
        setState(() => _isLoading = false);
        break;
      case AgentStage.pipeline_error:
        _appendMessage(Message(text: e.message, isUser: false));
        setState(() => _isLoading = false);
        break;
      default:
        // other stages are just logged
        break;
    }
  }

  Future<void> _startStreaming(String userText) async {
    setState(() {
      _isLoading = true;
      _isUsingMcp = false;
      _pipelineProgress = 0.0;
      _eventLogs.clear();
      _awaitTestsConfirm = false;
    });

    await _streamSub?.cancel();
    final stream = _agent.start(AgentRequest(userText));
    if (stream == null) {
      // Fallback: non-streaming ask
      final resp = await _agent.ask(AgentRequest(userText));
      _appendMessage(Message(text: resp.text, isUser: false));
      setState(() => _isLoading = false);
      return;
    }
    _streamSub = stream.listen(
      _handleAgentEvent,
      onError: (e, st) {
        _appendMessage(Message(text: 'Ошибка пайплайна: $e', isUser: false));
        setState(() => _isLoading = false);
      },
      onDone: () {
        setState(() => _isLoading = false);
      },
      cancelOnError: false,
    );
  }

  Future<void> _confirmCreateTests(bool yes) async {
    setState(() {
      _awaitTestsConfirm = false;
      _isLoading = true;
      // MCP используется только при запуске тестов и если он включён и настроен
      final mcpConfigured = _settings.useMcpServer && (_settings.mcpServerUrl?.trim().isNotEmpty ?? false);
      _isUsingMcp = yes && (_awaitAction == 'run_tests') && mcpConfigured;
    });
    // Вторая фаза должна идти через стрим, чтобы видеть промежуточные этапы
    await _startStreaming(yes ? 'да' : 'нет');
  }

  Future<void> _sendMessage(String text) async {
    final userText = text.trim();
    if (userText.isEmpty || _isLoading) return;

    _mcpIndicatorTimer?.cancel();

    _appendMessage(Message(text: userText, isUser: true));
    _textController.clear();
    setState(() {
      _isLoading = true;
      _isUsingMcp = false;
    });

    try {
      // Если ждём подтверждение на тесты — обработаем да/нет
      if (_awaitTestsConfirm) {
        final t = userText.toLowerCase();
        final yes = t.startsWith('y') || t.startsWith('д') || t.contains('да') || t.contains('yes');
        await _confirmCreateTests(yes);
        return;
      }

      // Если пользователь прислал код напрямую — покажем карточку
      if (_looksLikeCode(userText)) {
        final payload = jsonEncode({
          'language': 'java',
          'path': 'Main.java',
          'content': userText,
        });
        final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
        _appendMessage(Message(text: card, isUser: false));
        setState(() => _isLoading = false);
        return;
      }

      // Запускаем потоковый пайплайн агента
      await _startStreaming(userText);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isUsingMcp = false;
      });
      _appendMessage(Message(text: 'Ошибка: $e', isUser: false));
    }
  }

  bool _isJson(String text) => tryExtractJsonMap(text) != null;

  bool _isCodeCard(String text) => text.startsWith('CODE_CARD::');

  Map<String, String>? _decodeCodeCard(String text) {
    try {
      final idx = 'CODE_CARD::'.length;
      final b64 = text.substring(idx).trim();
      final jsonStr = utf8.decode(base64Decode(b64));
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      return {
        'language': (m['language']?.toString() ?? '').trim(),
        'path': (m['path']?.toString() ?? 'Main.java').trim(),
        'content': m['content']?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  String _stripCodeFencesGlobal(String text) {
    final t = text.trim();
    if (!t.contains('```')) return t;
    final start = t.indexOf('```');
    if (start == -1) return t;
    final end = t.indexOf('```', start + 3);
    if (end == -1) return t;
    var inner = t.substring(start + 3, end);
    final firstNl = inner.indexOf('\n');
    if (firstNl > -1) {
      final firstLine = inner.substring(0, firstNl).trim();
      if (firstLine.isNotEmpty && firstLine.length < 20) {
        inner = inner.substring(firstNl + 1);
      }
    }
    return inner.trim();
  }

  // --- Helpers to infer FQCN and detect tests for Java files ---
  String? _inferPackageName(String code) {
    final pkgRe = RegExp(r'package\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;');
    final m = pkgRe.firstMatch(code);
    return m?.group(1);
  }

  String? _inferPublicClassName(String code) {
    final clsRe = RegExp(r'public\s+class\s+([A-Za-z_]\w*)');
    final m = clsRe.firstMatch(code);
    return m?.group(1);
  }

  String _basenameNoExt(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = [slash, back].where((i) => i >= 0).fold(-1, (a, b) => a > b ? a : b);
    final base = path.substring(cut + 1);
    return base.toLowerCase().endsWith('.java') ? base.substring(0, base.length - 5) : base;
  }

  String? _fqcnFromFile(Map<String, String> f) {
    final raw = f['content'] ?? '';
    final code = _stripCodeFencesGlobal(raw);
    final pkg = _inferPackageName(code);
    final cls = _inferPublicClassName(code) ?? _basenameNoExt(f['path'] ?? 'Main.java');
    if (pkg != null && pkg.isNotEmpty) return '$pkg.$cls';
    return cls;
  }

  bool _isTestContent(String code) {
    final t = code;
    return t.contains('org.junit') || t.contains('@Test');
  }

  bool _isTestFile(Map<String, String> f) {
    final path = (f['path'] ?? '').trim();
    final name = _basenameNoExt(path);
    if (name.endsWith('Test')) return true;
    final code = _stripCodeFencesGlobal(f['content'] ?? '');
    return _isTestContent(code);
  }

  Future<void> _runTestWithDeps(Map<String, String> testFile) async {
    if ((testFile['language'] ?? '').toLowerCase() != 'java') {
      _appendMessage(Message(text: 'Запуск тестов доступен только для Java. Файл: ${testFile['path']}', isUser: false));
      return;
    }
    setState(() {
      _isLoading = true;
      final mcpConfigured = _settings.useMcpServer && (_settings.mcpServerUrl?.trim().isNotEmpty ?? false);
      _isUsingMcp = mcpConfigured;
    });
    try {
      final testClean = _stripCodeFencesGlobal(testFile['content'] ?? '');
      final testFqcn = _fqcnFromFile(testFile);
      if (testFqcn == null || testFqcn.isEmpty) {
        throw StateError('Не удалось определить FQCN тестового класса');
      }

      // Собираем минимальные зависимости: тест + парный исходник <Name>.java
      final files = <Map<String, String>>[
        {
          'path': testFile['path'] ?? 'Test.java',
          'content': testClean,
        },
      ];

      // Поиск парного исходника
      Map<String, String>? srcFile;
      try {
        final code = testClean;
        final pkg = _inferPackageName(code);
        final testCls = _inferPublicClassName(code) ?? _basenameNoExt(testFile['path'] ?? 'Test.java');
        String? baseName;
        if (testCls.endsWith('Test')) {
          baseName = testCls.substring(0, testCls.length - 4);
        }
        if (baseName != null && baseName.isNotEmpty && _lastGeneratedFiles != null && _lastGeneratedFiles!.isNotEmpty) {
          final expectedRel = (pkg != null && pkg.isNotEmpty)
              ? '${pkg.replaceAll('.', '/')}/$baseName.java'
              : '$baseName.java';
          // 1) точное совпадение пути (или окончание пути)
          for (final f in _lastGeneratedFiles!) {
            final p = (f['path'] ?? '').trim();
            if (p == expectedRel || p.endsWith('/$expectedRel') || p.endsWith('\\$expectedRel')) {
              srcFile = f;
              break;
            }
          }
          // 2) по содержимому и имени класса
          if (srcFile == null) {
            for (final f in _lastGeneratedFiles!) {
              final content = _stripCodeFencesGlobal(f['content'] ?? '');
              final pkg2 = _inferPackageName(content);
              final cls2 = _inferPublicClassName(content) ?? _basenameNoExt(f['path'] ?? 'Main.java');
              if (cls2 == baseName && pkg2 == pkg) {
                srcFile = f;
                break;
              }
            }
          }
        }
      } catch (_) {
        // ignore deps resolution errors; we'll try to run just the test
      }

      if (srcFile != null) {
        files.add({
          'path': srcFile['path'] ?? 'Main.java',
          'content': _stripCodeFencesGlobal(srcFile['content'] ?? ''),
        });
      }

      final result = await _agent.callTool('docker_exec_java', {
        'files': files,
        'entrypoint': testFqcn,
        'timeout_ms': 20000,
      });

      final compile = result['compile'] as Map<String, dynamic>?;
      final run = result['run'] as Map<String, dynamic>?;
      final success = result['success'] == true;
      final compileExit = compile?['exitCode'];
      final runExit = run?['exitCode'];

      final buf = StringBuffer();
      buf.writeln('Результат JUnit (success=$success):');
      if (compile != null) {
        buf.writeln('- Compile exitCode: $compileExit');
        final cErr = (compile['stderr'] as String? ?? '').trim();
        if (cErr.isNotEmpty) {
          buf.writeln('- Compile stderr (фрагмент):');
          buf.writeln(cErr.length > 300 ? '${cErr.substring(0, 300)}...' : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? '${rOut.substring(0, 300)}...' : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? '${rErr.substring(0, 300)}...' : rErr);
        }
      }
      _appendMessage(Message(text: buf.toString(), isUser: false));
    } catch (e) {
      _appendMessage(Message(text: 'Ошибка запуска тестов в Docker: $e', isUser: false));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
    }
  }

  Future<void> _runCodeCard(Map<String, String> file) async {
    if ((file['language'] ?? '').toLowerCase() != 'java') {
      _appendMessage(Message(text: 'Запуск доступен только для Java. Файл: ${file['path']}', isUser: false));
      return;
    }
    setState(() {
      _isLoading = true;
      final mcpConfigured = _settings.useMcpServer && (_settings.mcpServerUrl?.trim().isNotEmpty ?? false);
      _isUsingMcp = mcpConfigured;
    });
    try {
      // Всегда отправляем только файл с текущей карточки
      final cleaned = _stripCodeFencesGlobal(file['content'] ?? '');
      final result = await _agent.callTool('docker_exec_java', {
        'code': cleaned,
        'filename': (file['path'] ?? 'Main.java'),
        'entrypoint': _fqcnFromFile(file) ?? _pendingEntrypoint,
        'timeout_ms': 15000,
      });

      final compile = result['compile'] as Map<String, dynamic>?;
      final run = result['run'] as Map<String, dynamic>?;
      final success = result['success'] == true;
      final compileExit = compile?['exitCode'];
      final runExit = run?['exitCode'];

      final buf = StringBuffer();
      buf.writeln('Результат выполнения Docker/Java (success=$success):');
      if (compile != null) {
        buf.writeln('- Compile exitCode: $compileExit');
        final cErr = (compile['stderr'] as String? ?? '').trim();
        if (cErr.isNotEmpty) {
          buf.writeln('- Compile stderr (фрагмент):');
          buf.writeln(cErr.length > 300 ? '${cErr.substring(0, 300)}...' : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? '${rOut.substring(0, 300)}...' : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? '${rErr.substring(0, 300)}...' : rErr);
        }
      }
      _appendMessage(Message(text: buf.toString(), isUser: false));
    } catch (e) {
      _appendMessage(Message(text: 'Ошибка выполнения кода в Docker: $e', isUser: false));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
    }
  }

  Widget _buildCodeCard(String text) {
    final file = _decodeCodeCard(text);
    if (file == null) return const SizedBox.shrink();
    final isJava = (file['language'] ?? '').toLowerCase() == 'java';
    final code = file['content'] ?? '';
    final path = file['path'] ?? 'Main.java';
    return Card(
      margin: const EdgeInsets.only(top: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Файл: $path',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: isJava && !_isLoading ? () => _runCodeCard(file) : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Запуск кода'),
                    ),
                    const SizedBox(width: 8),
                    if (isJava && _isTestFile(file))
                      TextButton.icon(
                        onPressed: !_isLoading ? () => _runTestWithDeps(file) : null,
                        icon: const Icon(Icons.science),
                        label: const Text('Запустить тест'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonView(String text) {
    try {
      final jsonData = tryExtractJsonMap(text);
      if (jsonData == null) return const SizedBox.shrink();
      final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonData);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 8.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'JSON Preview',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: prettyJson));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('JSON скопирован в буфер обмена')),
                          );
                        },
                        tooltip: 'Копировать JSON',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[900]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      prettyJson,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
        children: [
          // Панель действий CodeOps (ранее в AppBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () {
                    _agent.clearHistory();
                    setState(() {
                      _messages.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Контекст очищен')),
                    );
                  },
                  tooltip: 'Очистить контекст',
                ),
              ],
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pipelineProgress != null)
                    LinearProgressIndicator(value: _pipelineProgress),
                  if (_eventLogs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView(
                        shrinkWrap: true,
                        children: _eventLogs.take(20).map((l) => Text(l, style: const TextStyle(fontSize: 12))).toList(),
                      ),
                    ),
                  ],
                  if (_pipelineProgress == null && _eventLogs.isEmpty)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isJson = !message.isUser && _isJson(message.text);
                return Align(
                  alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isJson) _buildJsonView(message.text),
                        if (isJson) const SizedBox(height: 8),
                        if (_isCodeCard(message.text))
                          _buildCodeCard(message.text)
                        else
                          Text(
                            message.text,
                            style: TextStyle(
                              color: message.isUser
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: SafeSendTextField(
                    controller: _textController,
                    hintText: 'Введите сообщение...',
                    border: const OutlineInputBorder(),
                    filled: false,
                    onSend: (v) => _sendMessage(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(_textController.text),
                ),
              ],
            ),
          ),
          if (_awaitTestsConfirm)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => _confirmCreateTests(false),
                    child: const Text('Не создавать тесты'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _confirmCreateTests(true),
                    icon: const Icon(Icons.science),
                    label: const Text('Создать и запустить тесты'),
                  ),
                ],
              ),
            ),
        ],
      );
  }
}
