import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/experimental_gate.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// The experimental tools call routes production does not serve yet. An MCP
/// client's only inventory of what it may call is the tool list, so a default
/// server must not list them.
void main() {
  const experimentalToolNames = <String>[
    'restage_apply_canonical_mutation',
    'restage_activate_experiment',
  ];

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_gate');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<Set<String>> toolNames({
    required Map<String, String> environment,
  }) async {
    final connection = await connectServer(
      store: FileCredentialStore('${tempDir.path}/credentials'),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      experimentActivationApi: ExperimentActivationApi(
        transport: (bytes) async => bytes,
      ),
      environment: environment,
    );
    final tools = await connection.listTools(ListToolsRequest());
    return {for (final tool in tools.tools) tool.name};
  }

  test('a default server lists neither experimental tool', () async {
    final names = await toolNames(environment: const {});

    for (final name in experimentalToolNames) {
      expect(
        names,
        isNot(contains(name)),
        reason:
            '$name calls a route production does not serve yet, so a '
            'default server must not advertise it.',
      );
    }
    // Control: the ordinary tools are listed, so the assertions above are
    // reading a real tool list rather than an empty one.
    expect(names, contains('restage_list_surfaces'));
  });

  test('opting in lists both experimental tools', () async {
    final names = await toolNames(
      environment: const {experimentalOptInVariable: '1'},
    );

    for (final name in experimentalToolNames) {
      expect(names, contains(name));
    }
  });

  group('experimentalToolsEnabled', () {
    test('is off when unset and on for the documented spellings', () {
      expect(experimentalToolsEnabled(const {}), isFalse);
      expect(
        experimentalToolsEnabled(const {experimentalOptInVariable: 'false'}),
        isFalse,
      );
      for (final value in ['1', 'true', 'YES']) {
        expect(
          experimentalToolsEnabled({experimentalOptInVariable: value}),
          isTrue,
        );
      }
    });
  });
}
