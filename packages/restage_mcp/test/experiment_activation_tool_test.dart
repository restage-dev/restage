import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/experiment_activation_tool.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  test('declares one activation tool with one exact canonical-byte input', () {
    expect(experimentActivationTool.name, 'restage_activate_experiment');
    expect(experimentActivationTool.inputSchema.required, [
      'canonicalCommandBase64',
    ]);
    expect(experimentActivationTool.inputSchema.additionalProperties, isFalse);
  });

  test(
    'registers the activation tool only when an authority is injected',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'activation-mcp-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final connection = await connectServer(
        store: FileCredentialStore('${directory.path}/credentials'),
        httpClient: MockClient((_) async => http.Response('[]', 200)),
        experimentActivationApi: ExperimentActivationApi(
          transport: (bytes) async => bytes,
        ),
      );

      final tools = await connection.listTools(ListToolsRequest());
      expect(
        tools.tools.map((tool) => tool.name),
        contains('restage_activate_experiment'),
      );
    },
  );

  test('does not register the activation tool without an authority', () async {
    final directory = await Directory.systemTemp.createTemp('activation-mcp-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = await connectServer(
      store: FileCredentialStore('${directory.path}/credentials'),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

    final tools = await connection.listTools(ListToolsRequest());
    expect(
      tools.tools.map((tool) => tool.name),
      isNot(contains('restage_activate_experiment')),
    );
  });
}
