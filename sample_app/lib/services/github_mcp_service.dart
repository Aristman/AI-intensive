import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

/// Сервис для взаимодействия с Github MCP
class GithubMcpService {
  static const String _githubApiBaseUrl = 'https://api.github.com';
  static const String _envAssetPath = 'assets/.env';

  /// Загружает GITHUB_MCP_TOKEN из assets/.env
  Future<String?> _loadTokenFromAssets() async {
    try {
      final content = await rootBundle.loadString(_envAssetPath);
      // Парсим .env: строки вида KEY=VALUE, игнорируем комментарии и пустые строки
      final lines = const LineSplitter().convert(content);
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        var value = line.substring(eq + 1).trim();
        // Удаляем кавычки вокруг значения, если есть
        if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        if (key == 'GITHUB_MCP_TOKEN') {
          return value;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Не удалось загрузить assets/.env: $e');
      return null;
    }
  }

  /// Получение информации о репозитории
  Future<Map<String, dynamic>> getRepositoryInfo(String owner, String repo, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch repository info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching repository info: $e');
    }
  }

  /// Поиск репозиториев
  Future<List<Map<String, dynamic>>> searchRepositories(String query, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_githubApiBaseUrl/search/repositories?q=$query'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else {
        throw Exception('Failed to search repositories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching repositories: $e');
    }
  }

  /// Получение содержимого файла из репозитория
  Future<String> getFileContent(String owner, String repo, String path, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/contents/$path'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['content'] != null) {
          return utf8.decode(base64.decode(data['content']));
        }
        return '';
      } else {
        throw Exception('Failed to fetch file content: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching file content: $e');
    }
  }

  /// Получение списка коммитов
  Future<List<Map<String, dynamic>>> getCommits(String owner, String repo, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/commits'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to fetch commits: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching commits: $e');
    }
  }

  /// Создание issue в репозитории
  Future<Map<String, dynamic>> createIssue(
    String owner,
    String repo,
    String title,
    String body,
    String token,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_githubApiBaseUrl/repos/$owner/$repo/issues'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          if (body.isNotEmpty) 'body': body,
        }),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create issue: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating issue: $e');
    }
  }

  /// Создание issue с использованием токена из .env
  Future<Map<String, dynamic>> createIssueFromEnv(
    String owner,
    String repo,
    String title,
    String body,
  ) async {
    final token = await _loadTokenFromAssets();
    if (token == null || token.isEmpty) {
      throw Exception('GITHUB_MCP_TOKEN not found in assets/.env');
    }
    return createIssue(owner, repo, title, body, token);
  }

  /// Проверка валидности токена
  Future<bool> validateToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_githubApiBaseUrl/user'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Валидация токена из .env файла
  Future<bool> validateTokenFromEnv() async {
    final token = await _loadTokenFromAssets();
    if (token == null || token.isEmpty) return false;
    return await validateToken(token);
  }

  /// Анализ репозитория с использованием MCP
  Future<String> analyzeRepository(String owner, String repo, String token) async {
    try {
      // Получаем базовую информацию о репозитории
      final repoInfo = await getRepositoryInfo(owner, repo, token);
      
      // Получаем последние коммиты
      final commits = await getCommits(owner, repo, token);
      
      // Формируем анализ
      final analysis = '''
Анализ репозитория $owner/$repo:

📊 Основная информация:
- Название: ${repoInfo['name']}
- Описание: ${repoInfo['description'] ?? 'Нет описания'}
- Язык: ${repoInfo['language'] ?? 'Не определен'}
- Звезды: ${repoInfo['stargazers_count']}
- Форки: ${repoInfo['forks_count']}
- Просмотров: ${repoInfo['watchers_count']}

📝 Последняя активность:
- Последний коммит: ${commits.isNotEmpty ? commits[0]['commit']['message'] : 'Нет коммитов'}
- Всего коммитов: ${commits.length}

🔗 Ссылка: ${repoInfo['html_url']}
      ''';

      return analysis;
    } catch (e) {
      return 'Ошибка при анализе репозитория: $e';
    }
  }
}