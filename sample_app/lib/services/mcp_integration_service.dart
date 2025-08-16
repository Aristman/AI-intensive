import 'dart:developer';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/github_mcp_service.dart';

/// Сервис для интеграции MCP провайдеров в процесс общения с LLM
class McpIntegrationService {
  final GithubMcpService _githubMcpService = GithubMcpService();

  /// Анализирует запрос пользователя и обогащает его данными из MCP провайдеров
  Future<Map<String, dynamic>> enrichContext(
    String userQuery,
    AppSettings settings,
  ) async {
    final enrichedContext = <String, dynamic>{
      'original_query': userQuery,
      'mcp_data': <String, dynamic>{},
      'mcp_used': false,
    };

    // Проверяем, включен ли GitHub MCP
    if (settings.isGithubMcpEnabled) {
      // Получаем токен из .env файла
      final token = dotenv.env['GITHUB_MCP_TOKEN'];
      if (token?.isNotEmpty == true) {
        try {
          final githubData = await _processGithubQuery(userQuery, token!);
          if (githubData.isNotEmpty) {
            enrichedContext['mcp_data']['github'] = githubData;
            enrichedContext['mcp_used'] = true;
          }
        } catch (e) {
          // Если произошла ошибка при работе с GitHub MCP, продолжаем без него
          log('Ошибка при обработке GitHub MCP: $e');
        }
      }
    }

    return enrichedContext;
  }

  /// Обрабатывает запрос, связанный с GitHub
  Future<Map<String, dynamic>> _processGithubQuery(String query, String token) async {
    final githubData = <String, dynamic>{};
    final lowerQuery = query.toLowerCase();

    // Паттерны для распознавания GitHub-запросов
    final repoPattern = RegExp(r'github\.com/([^/]+)/([^/\s]+)');
    final ownerRepoPattern = RegExp(r'([^\s/]+)/([^\s/]+)');

    // Поиск упоминания репозитория в формате github.com/owner/repo
    final repoMatch = repoPattern.firstMatch(query);
    if (repoMatch != null) {
      final owner = repoMatch.group(1);
      final repo = repoMatch.group(2);
      if (owner != null && repo != null) {
        try {
          final repoInfo = await _githubMcpService.getRepositoryInfo(owner, repo, token);
          githubData['repository'] = repoInfo;
          
          // Если запрос содержит слова, связанные с анализом, получаем дополнительную информацию
          if (_containsAnalysisKeywords(lowerQuery)) {
            final analysis = await _githubMcpService.analyzeRepository(owner, repo, token);
            githubData['analysis'] = analysis;
          }
        } catch (e) {
          log('Ошибка при получении информации о репозитории: $e');
        }
      }
    } else {
      // Поиск упоминания репозитория в формате owner/repo
      final ownerRepoMatch = ownerRepoPattern.firstMatch(query);
      if (ownerRepoMatch != null) {
        final owner = ownerRepoMatch.group(1);
        final repo = ownerRepoMatch.group(2);
        if (owner != null && repo != null && !_isCommonWord(owner) && !_isCommonWord(repo)) {
          try {
            final repoInfo = await _githubMcpService.getRepositoryInfo(owner, repo, token);
            githubData['repository'] = repoInfo;
          } catch (e) {
            log('Ошибка при получении информации о репозитории: $e');
          }
        }
      }
    }

    // Поиск репозиториев, если запрос содержит ключевые слова для поиска
    if (_containsSearchKeywords(lowerQuery)) {
      try {
        final searchTerms = _extractSearchTerms(query);
        if (searchTerms.isNotEmpty) {
          final searchResults = await _githubMcpService.searchRepositories(searchTerms, token);
          githubData['search_results'] = searchResults.take(5).toList(); // Ограничиваем результат
        }
      } catch (e) {
        log('Ошибка при поиске репозиториев: $e');
      }
    }

    return githubData;
  }

  /// Проверяет, содержит ли запрос ключевые слова для анализа
  bool _containsAnalysisKeywords(String query) {
    final keywords = [
      'анализ', 'анализировать', 'разбор', 'информация', 'о репозитории',
      'о проекте', 'статистика', 'стата', 'activity', 'коммиты', 'commits'
    ];
    return keywords.any((keyword) => query.contains(keyword));
  }

  /// Проверяет, содержит ли запрос ключевые слова для поиска
  bool _containsSearchKeywords(String query) {
    final keywords = [
      'найти', 'поиск', 'ищи', 'search', 'репозиторий', 'repository',
      'проект', 'project'
    ];
    return keywords.any((keyword) => query.contains(keyword));
  }

  /// Извлекает поисковые запросы из текста
  String _extractSearchTerms(String query) {
    // Удаляем общие слова и оставляем только существительные для поиска
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    final filteredWords = words.where((word) => 
      word.length > 2 && 
      !_isCommonWord(word) &&
      !word.contains('github') &&
      !word.contains('репозиторий') &&
      !word.contains('найти') &&
      !word.contains('поиск')
    ).toList();
    
    return filteredWords.join(' ');
  }

  /// Проверяет, является ли слово общеупотребительным
  bool _isCommonWord(String word) {
    final commonWords = [
      'что', 'как', 'где', 'когда', 'почему', 'зачем', 'кто', 'чей',
      'это', 'тот', 'тот', 'эта', 'этот', 'эти', 'тех', 'тех', 'тем',
      'для', 'на', 'в', 'с', 'по', 'о', 'об', 'от', 'до', 'у', 'из',
      'и', 'а', 'но', 'или', 'если', 'что', 'когда', 'где', 'как',
      'can', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'up', 'about', 'into', 'through',
      'during', 'before', 'after', 'above', 'below', 'between', 'among'
    ];
    return commonWords.contains(word.toLowerCase());
  }

  /// Формирует системный промпт с учетом MCP данных
  String buildEnrichedSystemPrompt(String originalSystemPrompt, Map<String, dynamic> enrichedContext) {
    final mcpData = enrichedContext['mcp_data'] as Map<String, dynamic>;
    
    if (mcpData.isEmpty) {
      return originalSystemPrompt;
    }

    final StringBuffer enrichedPrompt = StringBuffer();
    enrichedPrompt.writeln(originalSystemPrompt);
    enrichedPrompt.writeln();
    enrichedPrompt.writeln('=== ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ ИЗ MCP ===');
    enrichedPrompt.writeln();

    if (mcpData.containsKey('github')) {
      final githubData = mcpData['github'] as Map<String, dynamic>;
      enrichedPrompt.writeln('**GitHub Data:**');
      
      if (githubData.containsKey('repository')) {
        final repo = githubData['repository'] as Map<String, dynamic>;
        enrichedPrompt.writeln('Repository: ${repo['full_name']}');
        if (repo['description'] != null) {
          enrichedPrompt.writeln('Description: ${repo['description']}');
        }
        enrichedPrompt.writeln('Language: ${repo['language'] ?? 'Not specified'}');
        enrichedPrompt.writeln('Stars: ${repo['stargazers_count'] ?? 0}');
        enrichedPrompt.writeln('Forks: ${repo['forks_count'] ?? 0}');
        enrichedPrompt.writeln();
      }
      
      if (githubData.containsKey('analysis')) {
        enrichedPrompt.writeln('Repository Analysis:');
        enrichedPrompt.writeln(githubData['analysis']);
        enrichedPrompt.writeln();
      }
      
      if (githubData.containsKey('search_results')) {
        final searchResults = githubData['search_results'] as List;
        enrichedPrompt.writeln('Search Results:');
        for (int i = 0; i < searchResults.length && i < 3; i++) {
          final result = searchResults[i] as Map<String, dynamic>;
          enrichedPrompt.writeln('${i + 1}. ${result['full_name']} - ${result['description'] ?? 'No description'}');
        }
        enrichedPrompt.writeln();
      }
    }

    enrichedPrompt.writeln('=== КОНЕЦ ДОПОЛНИТЕЛЬНОЙ ИНФОРМАЦИИ ===');
    enrichedPrompt.writeln();
    enrichedPrompt.writeln('Используй эту информацию для предоставления более точного и контекстуального ответа. '
                          'Если пользователь спрашивает о конкретном репозитории, учитывай предоставленные данные.');

    return enrichedPrompt.toString();
  }
}