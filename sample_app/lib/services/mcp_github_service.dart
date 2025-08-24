import 'package:sample_app/services/mcp_client.dart';

/// Обёртка над MCP GitHub инструментами.
/// Делегирует вызовы в McpClient.toolsCall и приводит результат к удобным типам.
class McpGithubService {
  final McpApi _client;

  McpGithubService(this._client);

  /// Создать релиз в GitHub
  /// Возвращает объект релиза (Map)
  Future<Map<String, dynamic>> createRelease({
    required String owner,
    required String repo,
    required String tagName,
    String? name,
    String? body,
    bool? draft,
    bool? prerelease,
    String? targetCommitish,
  }) async {
    final resp = await _client.toolsCall('create_release', {
      'owner': owner,
      'repo': repo,
      'tag_name': tagName,
      if (name != null) 'name': name,
      if (body != null) 'body': body,
      if (draft != null) 'draft': draft,
      if (prerelease != null) 'prerelease': prerelease,
      if (targetCommitish != null) 'target_commitish': targetCommitish,
    });
    final result = (resp is Map && resp['result'] is Map)
        ? Map<String, dynamic>.from(resp['result'] as Map)
        : (resp is Map<String, dynamic> ? resp : <String, dynamic>{});
    return result;
  }

  /// Список PR для репозитория
  Future<List<Map<String, dynamic>>> listPullRequests({
    required String owner,
    required String repo,
    String? state, // open | closed | all
    int? perPage,
    int? page,
  }) async {
    final resp = await _client.toolsCall('list_pull_requests', {
      'owner': owner,
      'repo': repo,
      if (state != null) 'state': state,
      if (perPage != null) 'per_page': perPage,
      if (page != null) 'page': page,
    });
    final result = (resp is Map && resp['result'] is List)
        ? List<Map<String, dynamic>>.from(resp['result'] as List)
        : (resp is List ? List<Map<String, dynamic>>.from(resp) : <Map<String, dynamic>>[]);
    return result;
  }

  /// Получить PR по номеру
  Future<Map<String, dynamic>> getPullRequest({
    required String owner,
    required String repo,
    required int number,
  }) async {
    final resp = await _client.toolsCall('get_pull_request', {
      'owner': owner,
      'repo': repo,
      'number': number,
    });
    final result = (resp is Map && resp['result'] is Map)
        ? Map<String, dynamic>.from(resp['result'] as Map)
        : (resp is Map<String, dynamic> ? resp : <String, dynamic>{});
    return result;
  }

  /// Список файлов в PR
  Future<List<Map<String, dynamic>>> listPrFiles({
    required String owner,
    required String repo,
    required int number,
    int? perPage,
    int? page,
  }) async {
    final resp = await _client.toolsCall('list_pr_files', {
      'owner': owner,
      'repo': repo,
      'number': number,
      if (perPage != null) 'per_page': perPage,
      if (page != null) 'page': page,
    });
    final result = (resp is Map && resp['result'] is List)
        ? List<Map<String, dynamic>>.from(resp['result'] as List)
        : (resp is List ? List<Map<String, dynamic>>.from(resp) : <Map<String, dynamic>>[]);
    return result;
  }
}
