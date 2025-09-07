import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';

/// CodeAuditAgent: офлайн-аналитика проекта по папке с кодом.
/// Возвращает JSON-структуру с summary, files и project_suggestions.
class CodeAuditAgent with AuthPolicyMixin implements IAgent {
  /// Ограничение по количеству файлов — null означает безлимит.
  final int? maxFiles;
  final Set<String> includeExtensions;
  final Set<String> ignoreDirs;

  /// Грубая оценка лимита токенов на один чанк анализа.
  /// Будем использовать оценку 1 токен ≈ 4 байта исходника.
  /// По умолчанию 6000 токенов → ~24 КБ на чанк.
  final int maxTokensPerChunk;

  AppSettings? _settings;

  CodeAuditAgent({
    AppSettings? initialSettings,
    this.maxFiles,
    Set<String>? includeExtensions,
    Set<String>? ignoreDirs,
    this.maxTokensPerChunk = 6000,
  })  : includeExtensions = includeExtensions ?? {
          '.dart', '.js', '.ts', '.java', '.kt', '.kts', '.yaml', '.yml', '.json', '.gradle'
        },
        ignoreDirs = ignoreDirs ?? {
          '.git', 'build', '.dart_tool', '.idea', '.gradle', 'node_modules', 'ios/Pods', 'android/.gradle'
        } {
    _settings = initialSettings;
  }

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: true,
        reasoning: false,
        tools: {},
        systemPrompt: null,
        responseRules: [
          'Формировать итог строго в JSON-формате результата аудита',
        ],
      );

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {}

  // Синхронный запрос: запускает полный аудит и возвращает JSON текстом
  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    final path = (req.context?['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) {
      return const AgentResponse(text: '{"summary":"Путь к проекту не задан","files":[],"project_suggestions":[]}', isFinal: true);
    }
    final result = await _auditProject(path);
    final jsonText = const JsonEncoder.withIndent('  ').convert(result);
    return AgentResponse(text: jsonText, isFinal: true, meta: {
      'result': result,
    });
  }

  // Стриминговый запуск: эмитит стадии и финальный результат
  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    final controller = StreamController<AgentEvent>();
    () async {
      final runId = 'audit_${DateTime.now().millisecondsSinceEpoch}';
      try {
        await ensureAuthorized(req, action: 'code_audit', requiredRole: AgentRoles.guest);
        final path = (req.context?['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          controller.add(AgentEvent(
            id: 'audit_err_empty_path',
            runId: runId,
            stage: AgentStage.pipeline_error,
            severity: AgentSeverity.error,
            message: 'Путь к проекту не задан',
          ));
          await controller.close();
          return;
        }
        controller.add(AgentEvent(
          id: 'audit_start',
          runId: runId,
          stage: AgentStage.analysis_started,
          severity: AgentSeverity.info,
          message: 'Старт аудита проекта',
          meta: {'path': path, 'maxFiles': maxFiles},
        ));

        // Индексация
        controller.add(AgentEvent(
          id: 'audit_indexing',
          runId: runId,
          stage: AgentStage.intent_classified,
          severity: AgentSeverity.info,
          message: 'Индексация файлов...',
        ));
        final files = _collectFiles(path, limit: maxFiles);

        // Разбиение на чанки по оценке токенов
        final chunks = _chunkFilesByTokens(files, maxTokensPerChunk: maxTokensPerChunk);

        final merged = <Map<String, dynamic>>[];
        final projectSuggestions = <String>{};
        final types = _detectProjectTypes(path);

        for (var i = 0; i < chunks.length; i++) {
          final chunk = chunks[i];
          controller.add(AgentEvent(
            id: 'audit_chunk_${i + 1}',
            runId: runId,
            stage: AgentStage.code_generation_started,
            severity: AgentSeverity.info,
            message: 'Анализ чанка ${i + 1}/${chunks.length}...',
            progress: (i) / chunks.length,
            meta: {'files': chunk.length},
          ));

          final partial = _analyzeFiles(path, chunk);
          merged.addAll(List<Map<String, dynamic>>.from(partial['files'] as List));
          projectSuggestions.addAll(((partial['project_suggestions'] as List?)?.cast<String>() ?? const []));
        }

        final summary = _buildSummary(merged.length, types, _DepsAnalysis(projectLevelSuggestions: projectSuggestions));
        final result = {
          'summary': summary,
          'files': merged,
          'project_suggestions': projectSuggestions.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        };

        final jsonText = const JsonEncoder.withIndent('  ').convert(result);

        controller.add(AgentEvent(
          id: 'audit_result',
          runId: runId,
          stage: AgentStage.analysis_result,
          severity: AgentSeverity.info,
          message: 'Аудит завершён',
          meta: {
            'result': result,
            'jsonText': jsonText,
          },
        ));

        controller.add(AgentEvent(
          id: 'audit_done',
          runId: runId,
          stage: AgentStage.pipeline_complete,
          severity: AgentSeverity.info,
          message: 'Пайплайн завершён',
          meta: {
            'result': result,
            'jsonText': jsonText,
          },
        ));
      } catch (e) {
        controller.add(AgentEvent(
          id: 'audit_exception',
          runId: 'audit_unknown',
          stage: AgentStage.pipeline_error,
          severity: AgentSeverity.error,
          message: 'Ошибка аудита: $e',
        ));
      } finally {
        await controller.close();
      }
    }();
    return controller.stream;
  }

  // ===== Реализация аудита =====

  Future<Map<String, dynamic>> _auditProject(String rootPath) async {
    final files = _collectFiles(rootPath, limit: maxFiles);
    // В offline-режиме даже при ask() применяем ту же логику склейки чанков.
    final chunks = _chunkFilesByTokens(files, maxTokensPerChunk: maxTokensPerChunk);
    final merged = <Map<String, dynamic>>[];
    final projectSuggestions = <String>{};
    final types = _detectProjectTypes(rootPath);
    for (final chunk in chunks) {
      final partial = _analyzeFiles(rootPath, chunk);
      merged.addAll(List<Map<String, dynamic>>.from(partial['files'] as List));
      projectSuggestions.addAll(((partial['project_suggestions'] as List?)?.cast<String>() ?? const []));
    }
    final summary = _buildSummary(merged.length, types, _DepsAnalysis(projectLevelSuggestions: projectSuggestions));
    return {
      'summary': summary,
      'files': merged,
      'project_suggestions': projectSuggestions.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    };
  }

  List<File> _collectFiles(String rootPath, {required int? limit}) {
    final collected = <File>[];
    final root = Directory(rootPath);
    if (!root.existsSync()) return collected;

    final ignoreLower = ignoreDirs.map((e) => e.replaceAll('\\', '/').toLowerCase()).toSet();

    final lister = root.listSync(recursive: true, followLinks: false);
    for (final entity in lister) {
      if (limit != null && collected.length >= limit) break;
      if (entity is File) {
        final relPath = p.relative(entity.path, from: rootPath).replaceAll('\\', '/');
        // Игнор директорий
        final parts = p.split(relPath).map((s) => s.toLowerCase()).toList();
        if (parts.any((seg) => ignoreLower.contains(seg))) {
          continue;
        }
        final ext = p.extension(relPath).toLowerCase();
        if (!includeExtensions.contains(ext)) continue;
        // Ограничим размер файлов (например, 1 МБ)
        final stat = entity.statSync();
        if (stat.size > 1024 * 1024) continue;
        collected.add(entity);
      }
    }
    return collected;
  }

  /// Разбивает массив файлов на чанки по оценке токенов.
  /// Оценка: tokens ≈ bytes / 4. Чанк ограничен maxTokensPerChunk.
  List<List<File>> _chunkFilesByTokens(List<File> files, {required int maxTokensPerChunk}) {
    final chunks = <List<File>>[];
    var current = <File>[];
    var currentTokens = 0;
    for (final f in files) {
      final sizeBytes = f.existsSync() ? f.statSync().size : 0;
      final estTokens = (sizeBytes / 4).ceil();
      if (current.isNotEmpty && currentTokens + estTokens > maxTokensPerChunk) {
        chunks.add(current);
        current = <File>[];
        currentTokens = 0;
      }
      current.add(f);
      currentTokens += estTokens;
    }
    if (current.isNotEmpty) chunks.add(current);
    if (chunks.isEmpty) chunks.add(<File>[]);
    return chunks;
  }

  Map<String, dynamic> _analyzeFiles(String rootPath, List<File> files) {
    final results = <Map<String, dynamic>>[];
    final projectSuggestions = <String>{};

    // Определение типа проекта по файлам-маркерам
    final typeMarkers = _detectProjectTypes(rootPath);

    for (final f in files) {
      final rel = p.relative(f.path, from: rootPath).replaceAll('\\', '/');
      final content = _readFileSafe(f);
      final suggestions = <String>[];
      final problems = <String>[];

      // Эвристики: правильность (очевидные синтаксические маркеры)
      if (content.trim().isEmpty) {
        problems.add('Файл пустой');
      }

      if (rel.endsWith('.dart')) {
        if (content.contains('print(')) {
          suggestions.add('Рассмотрите замену print() на логирование через dev.log или logger');
        }
      }

      if (rel.endsWith('.js') || rel.endsWith('.ts')) {
        if (content.contains('var ')) {
          suggestions.add('Избегайте var в пользу let/const для улучшения читаемости и безопасности');
        }
      }

      // Эвристики читаемости
      final longLines = _countLongLines(content, threshold: 120);
      if (longLines > 0) {
        suggestions.add('Найдено $longLines строк(и) длиной >120 символов — стоит отформатировать код');
      }

      // Безопасность: простая проверка на секреты
      if (_looksLikeSecret(content)) {
        problems.add('Похоже на вкрапления секретов/токенов — вынесите в .env/секреты');
      }

      results.add({
        'file': rel,
        if (suggestions.isNotEmpty) 'suggestions': suggestions,
        if (problems.isNotEmpty) 'problems': problems,
      });
    }

    // Анализ зависимостей
    final deps = _analyzeDependencies(rootPath);
    projectSuggestions.addAll(deps.projectLevelSuggestions);

    // Общий summary
    final summary = _buildSummary(files.length, typeMarkers, deps);

    return {
      'summary': summary,
      'files': results,
      'project_suggestions': projectSuggestions.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    };
  }

  String _readFileSafe(File f) {
    try {
      return f.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  int _countLongLines(String content, {required int threshold}) {
    var n = 0;
    for (final line in content.split(RegExp(r'\r?\n'))) {
      if (line.length > threshold) n++;
    }
    return n;
  }

  bool _looksLikeSecret(String content) {
    final patterns = <RegExp>[
      RegExp(r'api[_-]?key\s*[:=]\s*[A-Za-z0-9_\-]{16,}', caseSensitive: false),
      RegExp(r'token\s*[:=]\s*[A-Za-z0-9_\-]{16,}', caseSensitive: false),
      RegExp(r'AIza[0-9A-Za-z\-_]{35}'), // Google API key
    ];
    for (final re in patterns) {
      if (re.hasMatch(content)) return true;
    }
    return false;
  }

  Set<String> _detectProjectTypes(String rootPath) {
    final markers = <String>{};
    if (File(p.join(rootPath, 'pubspec.yaml')).existsSync()) markers.add('Dart/Flutter');
    if (File(p.join(rootPath, 'package.json')).existsSync()) markers.add('Node.js');
    if (File(p.join(rootPath, 'build.gradle')).existsSync() || File(p.join(rootPath, 'build.gradle.kts')).existsSync()) markers.add('Kotlin/Java (Gradle)');
    if (File(p.join(rootPath, 'pom.xml')).existsSync()) markers.add('Java (Maven)');
    return markers;
  }

  _DepsAnalysis _analyzeDependencies(String rootPath) {
    final suggestions = <String>{};

    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      suggestions.add('Проверьте версии зависимостей в pubspec.yaml; используйте ^ и избегайте жёстких пинов без необходимости');
    }

    final packageJson = File(p.join(rootPath, 'package.json'));
    if (packageJson.existsSync()) {
      suggestions.add('Проверьте package.json на устаревшие зависимости; подумайте о включении lockfile аудитора');
    }

    final gradle = File(p.join(rootPath, 'build.gradle'));
    final gradleKts = File(p.join(rootPath, 'build.gradle.kts'));
    if (gradle.existsSync() || gradleKts.existsSync()) {
      suggestions.add('Проверьте версии Gradle/AGP; избегайте конфликтов версий плагинов и библиотек');
    }

    return _DepsAnalysis(projectLevelSuggestions: suggestions);
  }

  String _buildSummary(int filesCount, Set<String> types, _DepsAnalysis deps) {
    final b = StringBuffer();
    // Выводим общее количество проанализированных файлов без упоминания лимитов.
    b.writeln('Проанализировано файлов: $filesCount.');
    if (types.isNotEmpty) {
      b.writeln('Определены типы проекта: ${types.join(', ')}.');
    } else {
      b.writeln('Тип проекта не определён по маркерам.');
    }
    if (deps.projectLevelSuggestions.isNotEmpty) {
      b.writeln('Рекомендации по зависимостям: ${deps.projectLevelSuggestions.length}.');
    }
    return b.toString().trim();
  }
}

class _DepsAnalysis {
  final Set<String> projectLevelSuggestions;
  _DepsAnalysis({required this.projectLevelSuggestions});
}
