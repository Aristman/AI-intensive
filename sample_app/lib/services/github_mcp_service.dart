import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/models/app_settings.dart';

/// Сервис для взаимодействия с Github MCP
class GithubMcpService {
  static const String _githubApiBaseUrl = 'https://api.github.com';
  
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