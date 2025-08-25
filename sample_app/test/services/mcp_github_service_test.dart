import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/services/mcp_github_service.dart';

class MockMcpApi extends Mock implements McpApi {}

void main() {
  group('McpGithubService', () {
    late MockMcpApi mock;
    late McpGithubService service;

    setUp(() {
      mock = MockMcpApi();
      service = McpGithubService(mock);
    });

    test('createRelease returns release map (wrapped in result)', () async {
      when(() => mock.toolsCall('create_release', {
            'owner': 'o',
            'repo': 'r',
            'tag_name': 'v1.0.0',
            'name': 'Release 1',
            'body': 'notes',
            'draft': false,
            'prerelease': false,
            'target_commitish': 'main',
          })).thenAnswer((_) async => {
            'result': {'id': 123, 'tag_name': 'v1.0.0'}
          });

      final res = await service.createRelease(
        owner: 'o',
        repo: 'r',
        tagName: 'v1.0.0',
        name: 'Release 1',
        body: 'notes',
        draft: false,
        prerelease: false,
        targetCommitish: 'main',
      );

      expect(res['tag_name'], 'v1.0.0');
    });

    test('createRelease accepts top-level map response', () async {
      when(() => mock.toolsCall('create_release', {
            'owner': 'o',
            'repo': 'r',
            'tag_name': 'v1',
          })).thenAnswer((_) async => {'id': 1, 'tag_name': 'v1'});

      final res = await service.createRelease(owner: 'o', repo: 'r', tagName: 'v1');
      expect(res['tag_name'], 'v1');
    });

    test('listPullRequests returns list (wrapped in result)', () async {
      when(() => mock.toolsCall('list_pull_requests', {
            'owner': 'o',
            'repo': 'r',
            'state': 'open',
            'per_page': 2,
            'page': 1,
          })).thenAnswer((_) async => {
            'result': [
              {'number': 1},
              {'number': 2},
            ]
          });

      final list = await service.listPullRequests(
        owner: 'o',
        repo: 'r',
        state: 'open',
        perPage: 2,
        page: 1,
      );
      expect(list, isA<List>());
      expect(list.length, 2);
      expect(list[0]['number'], 1);
    });

    test('listPullRequests accepts top-level list response', () async {
      when(() => mock.toolsCall('list_pull_requests', {
            'owner': 'o',
            'repo': 'r',
          })).thenAnswer((_) async => [
            {'number': 10}
          ]);

      final list = await service.listPullRequests(owner: 'o', repo: 'r');
      expect(list.length, 1);
      expect(list.first['number'], 10);
    });

    test('getPullRequest returns map', () async {
      when(() => mock.toolsCall('get_pull_request', {
            'owner': 'o',
            'repo': 'r',
            'number': 5,
          })).thenAnswer((_) async => {
            'result': {'number': 5, 'state': 'open'}
          });

      final pr = await service.getPullRequest(owner: 'o', repo: 'r', number: 5);
      expect(pr['number'], 5);
      expect(pr['state'], 'open');
    });

    test('listPrFiles returns list', () async {
      when(() => mock.toolsCall('list_pr_files', {
            'owner': 'o',
            'repo': 'r',
            'number': 5,
            'per_page': 100,
            'page': 2,
          })).thenAnswer((_) async => {
            'result': [
              {'filename': 'a.dart'},
              {'filename': 'b.dart'},
            ]
          });

      final files = await service.listPrFiles(
        owner: 'o',
        repo: 'r',
        number: 5,
        perPage: 100,
        page: 2,
      );
      expect(files.length, 2);
      expect(files.first['filename'], 'a.dart');
    });

    test('propagates errors from client', () async {
      when(() => mock.toolsCall('get_pull_request', any())).thenThrow(Exception('boom'));

      expect(
        () => service.getPullRequest(owner: 'o', repo: 'r', number: 1),
        throwsA(isA<Exception>()),
      );
    });
  });
}
