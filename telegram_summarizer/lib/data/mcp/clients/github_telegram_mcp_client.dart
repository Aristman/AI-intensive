import 'package:telegram_summarizer/data/mcp/mcp_client.dart';

/// Специализированный MCP‑клиент для сервера из каталога mcp_server/ (GitHub + Telegram + Docker Java).
///
/// Использует протокол JSON‑RPC 2.0 (initialize, tools/list, tools/call) поверх WebSocket/HTTP.
/// Совместим с текущим SimpleAgent, т.к. наследуется от базового McpClient.
class GithubTelegramMcpClient extends McpClient {
  /// Локальный сервер (по умолчанию порт 3001, как в mcp_server/README.md)
  GithubTelegramMcpClient.local({int port = 3001, WebSocketConnector? connector})
      : super(url: 'ws://localhost:$port', connector: connector);

  /// Любой URL (ws/wss/http/https). HTTP автоматически будет использован как HTTP JSON‑RPC transport.
  GithubTelegramMcpClient.fromUrl(String url, {WebSocketConnector? connector})
      : super(url: url, connector: connector);

  // ---- GitHub tools ----
  Future<Map<String, dynamic>> getRepo({required String owner, required String repo}) {
    return callTool('get_repo', {
      'owner': owner,
      'repo': repo,
    });
  }

  Future<Map<String, dynamic>> searchRepos({required String query}) {
    return callTool('search_repos', {
      'query': query,
    });
  }

  Future<Map<String, dynamic>> createIssue({
    required String owner,
    required String repo,
    required String title,
    String? body,
  }) {
    final Map<String, dynamic> args = {
      'owner': owner,
      'repo': repo,
      'title': title,
    };
    if (body != null) args['body'] = body;
    return callTool('create_issue', args);
  }

  Future<Map<String, dynamic>> createRelease({
    required String owner,
    required String repo,
    required String tagName,
    String? name,
    String? body,
    bool? draft,
    bool? prerelease,
    String? targetCommitish,
  }) {
    final Map<String, dynamic> args = {
      'owner': owner,
      'repo': repo,
      'tag_name': tagName,
    };
    if (name != null) args['name'] = name;
    if (body != null) args['body'] = body;
    if (draft != null) args['draft'] = draft;
    if (prerelease != null) args['prerelease'] = prerelease;
    if (targetCommitish != null) args['target_commitish'] = targetCommitish;
    return callTool('create_release', args);
  }

  Future<Map<String, dynamic>> listPullRequests({
    required String owner,
    required String repo,
    String? state,
    int? perPage,
    int? page,
  }) {
    final Map<String, dynamic> args = {
      'owner': owner,
      'repo': repo,
    };
    if (state != null) args['state'] = state;
    if (perPage != null) args['per_page'] = perPage;
    if (page != null) args['page'] = page;
    return callTool('list_pull_requests', args);
  }

  Future<Map<String, dynamic>> getPullRequest({
    required String owner,
    required String repo,
    required int number,
  }) {
    return callTool('get_pull_request', <String, dynamic>{
      'owner': owner,
      'repo': repo,
      'number': number,
    });
  }

  Future<Map<String, dynamic>> listPrFiles({
    required String owner,
    required String repo,
    required int number,
    int? perPage,
    int? page,
  }) {
    final Map<String, dynamic> args = {
      'owner': owner,
      'repo': repo,
      'number': number,
    };
    if (perPage != null) args['per_page'] = perPage;
    if (page != null) args['page'] = page;
    return callTool('list_pr_files', args);
  }

  // ---- Telegram tools ----
  Future<Map<String, dynamic>> tgSendMessage({
    String? chatId,
    required String text,
    String? parseMode,
    bool? disableWebPagePreview,
  }) {
    final Map<String, dynamic> args = {
      'text': text,
    };
    if (chatId != null) args['chat_id'] = chatId;
    if (parseMode != null) args['parse_mode'] = parseMode;
    if (disableWebPagePreview != null) args['disable_web_page_preview'] = disableWebPagePreview;
    return callTool('tg_send_message', args);
  }

  Future<Map<String, dynamic>> tgSendPhoto({
    String? chatId,
    required String photo,
    String? caption,
    String? parseMode,
  }) {
    final Map<String, dynamic> args = {
      'photo': photo,
    };
    if (chatId != null) args['chat_id'] = chatId;
    if (caption != null) args['caption'] = caption;
    if (parseMode != null) args['parse_mode'] = parseMode;
    return callTool('tg_send_photo', args);
  }

  Future<Map<String, dynamic>> tgGetUpdates({
    int? offset,
    int? timeout,
    List<String>? allowedUpdates,
  }) {
    final args = <String, dynamic>{};
    if (offset != null) args['offset'] = offset;
    if (timeout != null) args['timeout'] = timeout;
    if (allowedUpdates != null) args['allowed_updates'] = allowedUpdates;
    return callTool('tg_get_updates', args);
  }

  // ---- Composite tool ----
  Future<Map<String, dynamic>> createIssueAndNotify({
    required String owner,
    required String repo,
    required String title,
    String? body,
    String? chatId,
    String? messageTemplate,
  }) {
    final args = {
      'owner': owner,
      'repo': repo,
      'title': title,
    };
    if (body != null) args['body'] = body;
    if (chatId != null) args['chat_id'] = chatId;
    if (messageTemplate != null) args['message_template'] = messageTemplate;
    return callTool('create_issue_and_notify', args);
  }

  // ---- Docker Java ----
  Future<Map<String, dynamic>> dockerStartJava({
    String? containerName,
    String? image,
    int? port,
    String? extraArgs,
  }) {
    final args = <String, dynamic>{};
    if (containerName != null) args['container_name'] = containerName;
    if (image != null) args['image'] = image;
    if (port != null) args['port'] = port;
    if (extraArgs != null) args['extra_args'] = extraArgs;
    return callTool('docker_start_java', args);
  }
}
