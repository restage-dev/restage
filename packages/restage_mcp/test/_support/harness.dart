import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/restage_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Wires a [RestageMcpServer] to an [MCPClient] over an in-memory channel pair,
/// completes the initialize handshake, and returns the [ServerConnection].
///
/// Shared by the tool test suites. Mirrors the dart_mcp team's in-process test
/// pattern. The login injectables ([sleep] / [openBrowser] / [loginEndpoint] /
/// [now]) drive the device-code flow against a fake backend without real delays
/// or a real browser.
Future<ServerConnection> connectServer({
  required FileCredentialStore store,
  required http.Client httpClient,
  Future<void> Function(Duration)? sleep,
  Future<void> Function(String)? openBrowser,
  Uri? loginEndpoint,
  DateTime Function()? now,
}) async {
  final clientController = StreamController<String>();
  final serverController = StreamController<String>();
  final clientChannel = StreamChannel<String>.withCloseGuarantee(
    serverController.stream,
    clientController.sink,
  );
  final serverChannel = StreamChannel<String>.withCloseGuarantee(
    clientController.stream,
    serverController.sink,
  );

  final client = MCPClient(
    Implementation(name: 'test client', version: '0.1.0'),
  );
  RestageMcpServer.fromStreamChannel(
    serverChannel,
    credentialStore: store,
    httpClient: httpClient,
    sleep: sleep,
    openBrowser: openBrowser,
    loginEndpoint: loginEndpoint,
    now: now,
  );
  final connection = client.connectServer(clientChannel);
  addTearDown(client.shutdown);

  final init = await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  expect(init.capabilities.tools, isNotNull, reason: 'server advertises tools');
  connection.notifyInitialized();
  return connection;
}
