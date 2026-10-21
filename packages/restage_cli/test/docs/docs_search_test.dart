import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:test/test.dart';

Map<String, Object?> _section(
  String page,
  String title,
  List<String> headings,
  String? anchor,
  String markdown,
) => {
  'page': page,
  'title': title,
  'headings': headings,
  'anchor': anchor,
  'url': 'https://docs.restage.dev$page${anchor == null ? '' : '#$anchor'}',
  'markdownUrl': 'https://docs.restage.dev$page.md',
  'markdown': markdown,
  'hash': '0000000000000000',
};

final _index = jsonEncode({
  'version': 1,
  'origin': 'https://docs.restage.dev',
  'pages': [
    {
      'path': '/delivery/hosted-delivery',
      'title': 'Hosted delivery',
      'description': 'Fetch the live version of each screen.',
      'group': 'Deliver',
      'url': 'https://docs.restage.dev/delivery/hosted-delivery',
      'markdownUrl': 'https://docs.restage.dev/delivery/hosted-delivery.md',
    },
  ],
  'chunks': [
    _section(
      '/delivery/hosted-delivery',
      'Hosted delivery',
      [],
      null,
      'With hosted delivery, a mount fetches the published version.',
    ),
    _section(
      '/delivery/hosted-delivery',
      'Hosted delivery',
      ['Fallbacks by mount API'],
      'fallbacks-by-mount-api',
      '## Fallbacks by mount API\n\n| Mount | Fallback |\n| --- | --- |\n'
          '| `RestagePaywall(id: ...)` | Only if bundled |\n\n'
          'Each mount decides what shows when the server cannot answer.\n\n'
          '```dart\nRestage.configure();\n```',
    ),
    _section(
      '/flows/overview',
      'Flows overview',
      ['Mount the flow'],
      'mount-the-flow',
      '## Mount the flow\n\nMount the generated flow where onboarding starts.',
    ),
  ],
});

http.Client _client({Map<String, String> pages = const {}}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path == '/docs-index.json') return http.Response(_index, 200);
      final page = pages[path];
      return page == null
          ? http.Response('not found', 404)
          : http.Response(page, 200);
    });

void main() {
  group('searchDocs', () {
    final index = DocsIndex.parse(_index);

    test('ranks a heading match above body matches', () {
      final hits = searchDocs(index, 'mount fallback');
      expect(hits.first.section.anchor, 'fallbacks-by-mount-api');
      expect(
        hits.map((h) => h.section.page),
        isNot(contains('/flows/overview')),
      );
    });

    test('needs every query word', () {
      expect(searchDocs(index, 'flow onboarding'), hasLength(1));
      expect(searchDocs(index, 'flow paywall'), isEmpty);
    });

    test('matches code, and snippets keep word spacing and inline code', () {
      final hit = searchDocs(index, 'RestagePaywall').single;
      expect(
        hit.snippet,
        contains('`RestagePaywall(id: ...)`, Only if bundled.'),
      );
      expect(hit.snippet, isNot(contains('---')));
      expect(searchDocs(index, 'configure'), hasLength(1));
    });

    test('puts a page first when the query names it', () {
      final hits = searchDocs(index, 'hosted delivery');
      expect(hits.first.section.anchor, isNull);
      expect(hits.first.section.page, '/delivery/hosted-delivery');
    });

    test('limits results', () {
      expect(searchDocs(index, 'mount', limit: 1), hasLength(1));
    });
  });

  group('docsPathOf', () {
    test('normalizes paths, .md paths and URLs', () {
      expect(docsPathOf('delivery/hosted-delivery.md'), (
        '/delivery/hosted-delivery',
        null,
      ));
      expect(docsPathOf('https://docs.restage.dev/tools/cli#sign-in'), (
        '/tools/cli',
        'sign-in',
      ));
      expect(docsPathOf('/'), ('/', null));
      expect(docsPathOf('index.md'), ('/', null));
      expect(docsPathOf('/quickstart/'), ('/quickstart', null));
    });

    test('refuses other sites', () {
      expect(
        () => docsPathOf('https://example.com/x'),
        throwsA(isA<DocsException>()),
      );
    });
  });

  group('DocsClient.read', () {
    test('fetches the page Markdown', () async {
      final docs = DocsClient(
        httpClient: _client(pages: {'/quickstart.md': '# Quickstart\n'}),
      );
      expect(await docs.read('/quickstart'), '# Quickstart\n');
    });

    test('reads one section by anchor from the index', () async {
      final docs = DocsClient(httpClient: _client());
      expect(
        await docs.read('/flows/overview#mount-the-flow'),
        startsWith('## Mount the flow'),
      );
    });

    test('names a missing page', () async {
      final docs = DocsClient(httpClient: _client());
      await expectLater(
        docs.read('/nope'),
        throwsA(
          isA<DocsException>().having(
            (e) => e.message,
            'message',
            contains('/nope'),
          ),
        ),
      );
    });

    test('honors the docs origin variable', () async {
      final requested = <Uri>[];
      final docs = DocsClient.fromEnvironment(
        {docsOriginVariable: 'https://preview.example.dev/'},
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('# Page', 200);
        }),
      );
      await docs.read('/quickstart');
      expect(
        requested.single.toString(),
        'https://preview.example.dev/quickstart.md',
      );
    });
  });

  group('restage docs', () {
    Future<(int, String, String)> run(List<String> args) async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final code = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        hasTerminal: () => false,
        environment: const {},
        httpClient: _client(
          pages: {'/flows/overview.md': '# Flows overview\n'},
        ),
      ).run(args);
      return (code, stdout.toString(), stderr.toString());
    }

    test('search prints titles, URLs and snippets', () async {
      final (code, out, _) = await run(['docs', 'search', 'mount', 'flow']);
      expect(code, 0);
      expect(out, contains('Flows overview › Mount the flow'));
      expect(
        out,
        contains('https://docs.restage.dev/flows/overview#mount-the-flow'),
      );
    });

    test('search --json returns structured results', () async {
      final (code, out, _) = await run([
        'docs',
        'search',
        '--json',
        'fallback',
      ]);
      expect(code, 0);
      final json = jsonDecode(out) as Map<String, Object?>;
      expect(
        (json['results']! as List).first,
        containsPair('section', 'Fallbacks by mount API'),
      );
    });

    test('read prints Markdown', () async {
      final (code, out, _) = await run(['docs', 'read', 'flows/overview']);
      expect(code, 0);
      expect(out.trim(), '# Flows overview');
    });

    test('help names the docs origin variable', () async {
      final (_, out, _) = await run(['docs', 'search', '--help']);
      expect(out, contains('Set RESTAGE_DOCS_URL'));
    });

    test('an unreachable docs site names the docs origin variable', () async {
      final stderr = StringBuffer();
      final code = await RestageCli(
        stdout: StringBuffer(),
        stderr: stderr,
        hasTerminal: () => false,
        environment: const {},
        httpClient: MockClient(
          (request) async => throw http.ClientException('lookup failed'),
        ),
      ).run(['docs', 'read', '/quickstart']);
      expect(code, 1);
      expect(stderr.toString(), contains('https://docs.restage.dev'));
      expect(stderr.toString(), contains('set RESTAGE_DOCS_URL'));
    });

    test('read reports a missing page', () async {
      final (code, _, err) = await run(['docs', 'read', '/nope']);
      expect(code, 1);
      expect(err, contains('No docs page at /nope'));
    });
  });
}
