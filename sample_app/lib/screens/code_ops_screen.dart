import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:sample_app/agents/code_ops_agent.dart';
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
  late CodeOpsAgent _agent;

  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _isUsingMcp = false;
  Timer? _mcpIndicatorTimer;

  // Pending code to execute
  String? _pendingCode;
  String? _pendingLanguage;
  String? _pendingFilename;
  String? _pendingEntrypoint;
  List<Map<String, String>>? _pendingFiles; // for multi-file execution
  String? _awaitLangFor; // original user request awaiting language clarification

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

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
    // CodeOpsAgent всегда в reasoning режиме
    _agent = CodeOpsAgent(baseSettings: _settings.copyWith(reasoningMode: true));
    if (mounted) setState(() => _loadingSettings = false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
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

  Future<Map<String, dynamic>> _classifyIntent(String userText) async {
    const schema = '{"intent":"code_generate|other","language":"string?","filename":"string?","reason":"string"}';
    final res = await _agent.ask(
      'Классифицируй следующий запрос пользователя как code_generate или other. Ответь строго по схеме. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: schema,
    );
    final answer = res['answer'] as String? ?? '';
    try {
      final jsonMap = jsonDecode(answer) as Map<String, dynamic>;
      return jsonMap;
    } catch (_) {
      return {'intent': 'other', 'reason': 'failed_to_parse'};
    }
  }

  Future<Map<String, dynamic>?> _requestCodeJson(String userText, {String? language}) async {
    const codeSchema = '{"title":"string","description":"string","language":"string","entrypoint":"string?","files":"Array<{path:string,content:string}>"}';
    final langHint = (language != null && language.trim().isNotEmpty)
        ? 'Сгенерируй код на языке ${language.trim()}.'
        : 'Если язык явно не указан пользователем — задай уточняющий вопрос. Не возвращай итог, пока язык не подтверждён.';
    // Для Java явно требуем JUnit4, чтобы соответствовать текущей поддержке MCP docker_exec_java (junit-4.13.2 + hamcrest 1.3)
    const junitHint = 'Если язык Java — генерируй тесты строго на JUnit 4: используй импорты "import org.junit.Test;" и "import static org.junit.Assert.*;". Не используй JUnit 5 (org.junit.jupiter.*).';
    final res = await _agent.ask(
      '$langHint $junitHint Верни строго JSON по схеме. Если требуется несколько классов/файлов — каждый в отдельном файле с полными импортами. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: codeSchema,
    );
    final answer = res['answer'] as String? ?? '';
    final jsonMap = tryExtractJsonMap(answer);
    if (jsonMap == null) return null;
    // Back-compat: если пришёл одиночный файл полями filename+code, преобразуем
    if (!jsonMap.containsKey('files') && jsonMap.containsKey('code')) {
      final fname = (jsonMap['filename']?.toString().isNotEmpty ?? false) ? jsonMap['filename'].toString() : 'Main.java';
      final content = jsonMap['code']?.toString() ?? '';
      jsonMap['files'] = [
        {
          'path': fname,
          'content': content,
        }
      ];
    }
    return jsonMap;
  }

  void _appendMessage(Message m) {
    setState(() => _messages.add(m));
    _scrollToBottom();
  }

  Future<void> _handleRunPendingCode() async {
    if (_pendingFiles == null && _pendingCode == null) return;
    setState(() => _isLoading = true);
    try {
      String _stripCodeFences(String text) {
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

      Map<String, dynamic> result;
      _isUsingMcp = true;
      if (_pendingFiles != null && _pendingFiles!.isNotEmpty) {
        // Очистим code fences во всех файлах
        final files = _pendingFiles!
            .map((f) => {
                  'path': f['path'] ?? 'Main.java',
                  'content': _stripCodeFences(f['content'] ?? ''),
                })
            .toList();
        if ((_pendingLanguage ?? '').toLowerCase() != 'java') {
          _appendMessage(Message(text: 'Запуск доступен только для Java. Сгенерирован ${_pendingLanguage ?? 'код'}, запуск пропущен.', isUser: false));
          return;
        }
        result = await _agent.execJavaFilesInDocker(
          files: files,
          entrypoint: _pendingEntrypoint,
          timeoutMs: 20000,
        );
      } else {
        final cleanedCode = _stripCodeFences(_pendingCode!);
        final filename = _pendingFilename?.trim().isNotEmpty == true ? _pendingFilename!.trim() : 'Main.java';
        if ((_pendingLanguage ?? '').toLowerCase() != 'java') {
          _appendMessage(Message(text: 'Запуск доступен только для Java. Сгенерирован ${_pendingLanguage ?? 'код'}, запуск пропущен.', isUser: false));
          return;
        }
        result = await _agent.execJavaInDocker(
          code: cleanedCode,
          filename: filename,
          entrypoint: _pendingEntrypoint,
          timeoutMs: 15000,
        );
      }

      // Короткая сводка
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
          buf.writeln(cErr.length > 300 ? cErr.substring(0, 300) + '...'
                                        : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? rOut.substring(0, 300) + '...'
                                       : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? rErr.substring(0, 300) + '...'
                                       : rErr);
        }
      }
      _appendMessage(Message(text: buf.toString(), isUser: false));
      // Убрано: не показываем сырой JSON-ответ, чтобы не засорять интерфейс
    } catch (e) {
      _appendMessage(Message(text: 'Ошибка выполнения кода в Docker: $e', isUser: false));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Погасить MCP-индикатор через 5 сек
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
    }
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
      // Language answer flow
      if (_awaitLangFor != null) {
        final lang = userText;
        final codeJson = await _requestCodeJson(_awaitLangFor!, language: lang);
        _awaitLangFor = null;
        if (codeJson != null) {
          final title = codeJson['title']?.toString() ?? 'Код';
          final language = codeJson['language']?.toString();
          final entrypoint = codeJson['entrypoint']?.toString();
          final files = (codeJson['files'] as List?)?.map((e) => {
                'path': e['path'].toString(),
                'content': e['content'].toString(),
              }).cast<Map<String, String>>().toList();
          _pendingLanguage = language;
          _pendingEntrypoint = entrypoint;
          _pendingFiles = files;
          _pendingCode = (files != null && files.isNotEmpty) ? files.first['content'] : null;
          _pendingFilename = (files != null && files.isNotEmpty) ? files.first['path'] : null;
          if (files != null && files.isNotEmpty) {
            if (files.length > 1) {
              _appendMessage(Message(text: '$title\n\nФайлов: ${files.length}\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
            } else {
              _appendMessage(Message(text: '$title\n\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
            }
            for (final f in files) {
              final payload = jsonEncode({
                'language': 'java',
                'path': f['path'],
                'content': f['content'],
              });
              final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
              _appendMessage(Message(text: card, isUser: false));
            }
          }
        } else {
          _appendMessage(Message(text: 'Не удалось получить корректный JSON с кодом.', isUser: false));
        }
        setState(() => _isLoading = false);
        return;
      }

      // If user pasted code directly — отрисуем карточку кода с кнопкой запуска
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

      // Classify intent
      final intent = await _classifyIntent(userText);
      if ((intent['intent'] as String?) == 'code_generate') {
        // Если язык не определён — спросим у пользователя
        final intentLang = (intent['language'] as String?)?.trim();
        if (intentLang == null || intentLang.isEmpty) {
          _awaitLangFor = userText;
          _appendMessage(Message(text: 'На каком языке сгенерировать код? (Поддерживается запуск в Docker только для Java)', isUser: false));
          setState(() => _isLoading = false);
          return;
        }

        final codeJson = await _requestCodeJson(userText, language: intentLang);
        if (codeJson != null) {
          final title = codeJson['title']?.toString() ?? 'Код';
          final language = codeJson['language']?.toString();
          final entrypoint = codeJson['entrypoint']?.toString();
          final files = (codeJson['files'] as List?)?.map((e) => {
                'path': e['path'].toString(),
                'content': e['content'].toString(),
              }).cast<Map<String, String>>().toList();

          // Сохраним pending
          _pendingLanguage = language;
          _pendingFiles = files;
          _pendingCode = (files != null && files.isNotEmpty) ? files.first['content'] : null;
          _pendingFilename = (files != null && files.isNotEmpty) ? files.first['path'] : null;
          _pendingEntrypoint = entrypoint;

          // Show summary + files в виде карточек кода
          if (files != null && files.isNotEmpty) {
            if (files.length > 1) {
              _appendMessage(Message(text: '$title\n\nФайлов: ${files.length}\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
            } else {
              _appendMessage(Message(text: '$title\n\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
            }
            for (final f in files) {
              final payload = jsonEncode({
                'language': 'java',
                'path': f['path'],
                'content': f['content'],
              });
              final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
              _appendMessage(Message(text: card, isUser: false));
            }
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      // General conversation with CodeOpsAgent
      final res = await _agent.ask(userText);
      final answer = res['answer'] as String? ?? '';
      final used = res['mcp_used'] == true;

      setState(() {
        _isUsingMcp = used;
        _isLoading = false;
      });

      // Попробуем извлечь JSON с кодом (в т.ч. из ```json ... ```)
      final detected = tryExtractJsonMap(answer);
      if (detected != null && (detected.containsKey('files') || detected.containsKey('code'))) {
        // Приведём к многофайловому формату при необходимости
        final codeJson = Map<String, dynamic>.from(detected);
        if (!codeJson.containsKey('files') && codeJson.containsKey('code')) {
          final fname = (codeJson['filename']?.toString().isNotEmpty ?? false) ? codeJson['filename'].toString() : 'Main.java';
          final content = codeJson['code']?.toString() ?? '';
          codeJson['files'] = [
            {
              'path': fname,
              'content': content,
            }
          ];
        }

        // Сохраним pending
        _pendingLanguage = codeJson['language']?.toString();
        _pendingFiles = (codeJson['files'] as List?)?.map((e) => {
              'path': e['path'].toString(),
              'content': e['content'].toString(),
            }).cast<Map<String, String>>().toList();
        _pendingCode = (_pendingFiles != null && _pendingFiles!.isNotEmpty) ? _pendingFiles!.first['content'] : null;
        _pendingFilename = (_pendingFiles != null && _pendingFiles!.isNotEmpty) ? _pendingFiles!.first['path'] : null;
        _pendingEntrypoint = codeJson['entrypoint']?.toString();

        if (_pendingFiles != null && _pendingFiles!.isNotEmpty) {
          if (_pendingFiles!.length > 1) {
            _appendMessage(Message(text: 'Файлов: ${_pendingFiles!.length}\nЯзык: ${_pendingLanguage ?? '-'}\nEntrypoint: ${_pendingEntrypoint ?? '-'}', isUser: false));
          } else {
            _appendMessage(Message(text: 'Язык: ${_pendingLanguage ?? '-'}\nEntrypoint: ${_pendingEntrypoint ?? '-'}', isUser: false));
          }
          for (final f in _pendingFiles!) {
            final payload = jsonEncode({
              'language': 'java',
              'path': f['path'],
              'content': f['content'],
            });
            final card = 'CODE_CARD::${base64Encode(utf8.encode(payload))}';
            _appendMessage(Message(text: card, isUser: false));
          }
        }
      } else {
        _appendMessage(Message(text: answer, isUser: false));
      }

      if (used) {
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
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
    return m == null ? null : m.group(1);
  }

  String? _inferPublicClassName(String code) {
    final clsRe = RegExp(r'public\s+class\s+([A-Za-z_]\w*)');
    final m = clsRe.firstMatch(code);
    return m == null ? null : m.group(1);
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
      _isUsingMcp = true;
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
        if (baseName != null && baseName.isNotEmpty && _pendingFiles != null && _pendingFiles!.isNotEmpty) {
          final expectedRel = (pkg != null && pkg.isNotEmpty)
              ? '${pkg.replaceAll('.', '/')}/$baseName.java'
              : '$baseName.java';
          // 1) точное совпадение пути (или окончание пути)
          for (final f in _pendingFiles!) {
            final p = (f['path'] ?? '').trim();
            if (p == expectedRel || p.endsWith('/$expectedRel') || p.endsWith('\\$expectedRel')) {
              srcFile = f;
              break;
            }
          }
          // 2) по содержимому и имени класса
          if (srcFile == null) {
            for (final f in _pendingFiles!) {
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

      final result = await _agent.execJavaFilesInDocker(
        files: files,
        entrypoint: testFqcn,
        timeoutMs: 20000,
      );

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
          buf.writeln(cErr.length > 300 ? cErr.substring(0, 300) + '...' : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? rOut.substring(0, 300) + '...' : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? rErr.substring(0, 300) + '...' : rErr);
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
      _isUsingMcp = true;
    });
    try {
      // Всегда отправляем только файл с текущей карточки
      final cleaned = _stripCodeFencesGlobal(file['content'] ?? '');
      final result = await _agent.execJavaInDocker(
        code: cleaned,
        filename: (file['path'] ?? 'Main.java'),
        entrypoint: _fqcnFromFile(file) ?? _pendingEntrypoint,
        timeoutMs: 15000,
      );

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
          buf.writeln(cErr.length > 300 ? cErr.substring(0, 300) + '...' : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? rOut.substring(0, 300) + '...' : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? rErr.substring(0, 300) + '...' : rErr);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('CodeOps'),
            if (_isUsingMcp) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.integration_instructions,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'MCP',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Настройки',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              _agent.clearHistory();
              setState(() {
                _messages.clear();
                _pendingCode = null;
                _pendingLanguage = null;
                _pendingFilename = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Контекст очищен')),
              );
            },
            tooltip: 'Очистить контекст',
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
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
        ],
      ),
    );
  }
}
