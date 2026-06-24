@Timeout(Duration(seconds: 90))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

/// Drives the real `bin/restage_mcp.dart` entrypoint over stdio, end to end.
///
/// Each case spawns the binary as a subprocess (exactly as an MCP host would),
/// performs the `initialize` handshake, lists tools, and calls
/// `restage_list_paywalls`, asserting the framed JSON-RPC responses.
void main() {
  /// Spawns the binary with [env] merged onto the parent environment, connects
  /// an MCP client over its stdio, and completes the initialize handshake.
  Future<({Process process, ServerConnection connection})> startServer(
    Map<String, String> env,
  ) async {
    final process = await Process.start('dart', [
      'run',
      'bin/restage_mcp.dart',
    ], environment: env);
    final client = MCPClient(
      Implementation(name: 'smoke client', version: '0.1.0'),
    );
    final connection = client.connectServer(
      stdioChannel(input: process.stdout, output: process.stdin),
    );
    addTearDown(() async {
      await client.shutdown();
      process.kill();
    });
    final init = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(init.capabilities.tools, isNotNull);
    connection.notifyInitialized();
    return (process: process, connection: connection);
  }

  /// Writes a device-code credential at the standard location under [configDir]
  /// (an `XDG_CONFIG_HOME`), pointed at [endpoint].
  void writeCredential(String configDir, String endpoint) {
    final file = File('$configDir/restage/credentials');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'endpoint': endpoint,
        'kind': 'authKey',
        'authToken': 'keyId:key',
      }),
    );
  }

  test(
    'initialize -> tools/list -> tools/call against a real backend',
    () async {
      // A stand-in backend on loopback that answers the paywall RPC.
      String? seenAuth;
      String? seenPath;
      final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => backend.close(force: true));
      unawaited(() async {
        await for (final request in backend) {
          seenAuth = request.headers.value('authorization');
          seenPath = request.uri.path;
          await request.drain<void>();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode([
                {
                  'surfaceType': 'paywall',
                  'slug': 'pro',
                  'name': 'Pro',
                  'draftUpdatedAt': '2026-06-01T00:00:00.000Z',
                  'publishedVersionByEnvironment': {'production': 3},
                  '__className__': 'SurfaceSummary',
                },
              ]),
            );
          await request.response.close();
        }
      }());

      final configDir = Directory.systemTemp.createTempSync(
        'restage_mcp_smoke',
      );
      addTearDown(() => configDir.deleteSync(recursive: true));
      writeCredential(configDir.path, 'http://127.0.0.1:${backend.port}/');

      final server = await startServer({'XDG_CONFIG_HOME': configDir.path});

      final tools = await server.connection.listTools(ListToolsRequest());
      final toolNames = tools.tools.map((t) => t.name);
      expect(
        toolNames,
        containsAll([
          // Identity / auth
          'restage_login',
          'restage_whoami',
          'restage_logout',
          // Paywalls
          'restage_list_paywalls',
          'restage_get_paywall',
          'restage_publish_paywall',
          'restage_get_published_version',
          // Discovery
          'restage_list_organizations',
          'restage_list_projects',
          'restage_list_apps',
          'restage_list_environments',
          // Products / store
          'restage_list_products',
          'restage_import_products',
          'restage_list_product_slots',
          'restage_upsert_product_slot',
          'restage_list_store_connections',
          // App configuration
          'restage_get_app_config',
          'restage_update_app_config',
          // API keys (list + revoke only)
          'restage_list_api_keys',
          'restage_revoke_api_key',
        ]),
        reason: 'the full launch tool surface is advertised',
      );
      // Minting issues a one-time plaintext secret — excluded by design.
      expect(toolNames, isNot(contains('restage_mint_api_key')));

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isNot(true));
      final paywalls = result.structuredContent!['paywalls']! as List<dynamic>;
      expect((paywalls.single as Map)['slug'], 'pro');

      // The real wire hit the surface RPC (paywalls list via the surface
      // substrate) with the device-code auth header.
      expect(seenPath, '/surface');
      expect(seenAuth, 'Basic ${base64Encode(utf8.encode('keyId:key'))}');
    },
  );

  test('tools/call restage_list_organizations over the real bin', () async {
    String? seenPath;
    final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => backend.close(force: true));
    unawaited(() async {
      await for (final request in backend) {
        seenPath = request.uri.path;
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode([
              {
                'organizationId': 7,
                'slug': 'acme',
                'name': 'Acme',
                'role': 'admin',
                '__className__': 'OrganizationMembershipView',
              },
            ]),
          );
        await request.response.close();
      }
    }());

    final configDir = Directory.systemTemp.createTempSync('restage_mcp_smoke');
    addTearDown(() => configDir.deleteSync(recursive: true));
    writeCredential(configDir.path, 'http://127.0.0.1:${backend.port}/');

    final server = await startServer({'XDG_CONFIG_HOME': configDir.path});

    final result = await server.connection.callTool(
      CallToolRequest(name: 'restage_list_organizations', arguments: {}),
    );

    expect(result.isError, isNot(true));
    final orgs = result.structuredContent!['organizations']! as List<dynamic>;
    expect((orgs.single as Map)['slug'], 'acme');
    expect(seenPath, '/organization');
  });

  test(
    'tools/call returns a clean not-signed-in error with no credential',
    () async {
      final configDir = Directory.systemTemp.createTempSync(
        'restage_mcp_smoke',
      );
      addTearDown(() => configDir.deleteSync(recursive: true));

      final server = await startServer({'XDG_CONFIG_HOME': configDir.path});

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, contains('restage login'));
    },
  );
}
