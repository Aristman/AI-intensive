import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/screens/github_agent_screen.dart';

void main() {
  group('buildGithubAgentExtraPrompt', () {
    test('includes owner/repo in context line', () {
      final prompt = buildGithubAgentExtraPrompt(owner: 'aristman', repo: 'AI-intensive');
      expect(prompt, contains('Текущий контекст репозитория: aristman/AI-intensive.'));
    });

    test('lists GitHub MCP tools including releases and PR', () {
      final prompt = buildGithubAgentExtraPrompt(owner: 'o', repo: 'r');
      // Base tools
      expect(prompt, contains('get_repo'));
      expect(prompt, contains('search_repos'));
      expect(prompt, contains('create_issue'));
      // New tools
      expect(prompt, contains('create_release'));
      expect(prompt, contains('list_pull_requests'));
      expect(prompt, contains('get_pull_request'));
      expect(prompt, contains('list_pr_files'));
    });

    test('no repo context line when owner/repo empty', () {
      final prompt = buildGithubAgentExtraPrompt(owner: '', repo: '');
      expect(prompt.contains('Текущий контекст репозитория:'), isFalse);
    });
  });
}
