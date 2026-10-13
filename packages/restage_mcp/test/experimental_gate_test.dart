import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/experimental_gate.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

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

  test(
    'a default server exposes experiments and keeps low-level tools gated',
    () async {
      final names = await toolNames(environment: const {});

      for (final name in experimentalToolNames) {
        expect(
          names,
          isNot(contains(name)),
          reason: '$name requires the low-level tool opt-in.',
        );
      }
      expect(
        names,
        containsAll([
          'restage_list_surfaces',
          'restage_experiment_apply',
          'restage_rebuild_serving_records',
        ]),
      );
    },
  );

  test('opting in lists every experimental tool', () async {
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
