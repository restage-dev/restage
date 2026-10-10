import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  /// A backend whose staging environment exists on both planes.
  http.Client backend({
    int? activeRevision,
    List<Map<String, dynamic>>? published,
    http.Response? refusal,
  }) {
    final discovery = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      published?.add(body);
      return refusal ??
          publishSucceeded(
            'pro_upgrade',
            storedRevision: 1,
            activeRevision: activeRevision,
          );
    });
    return MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] != 'resolveTarget') {
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..body = request.body;
        return discovery.send(copy).then(http.Response.fromStream);
      }
      return resolveTargetResponse(
        body,
        targets: [
          for (final (id, plane) in [(31, 'sandbox'), (32, 'live')])
            {
              'environmentTargetId': id,
              'namedEnvironmentId': 22,
              'environmentSlug': 'staging',
              'runtimePlane': plane,
            },
        ],
      );
    });
  }

  Future<int?> push(List<String> args, http.Client client) =>
      (CommandRunner<int>('restage', '')..addCommand(
            SurfacePushCommand(
              stdout: out,
              stderr: err,
              interactive: const NonInteractive(),
              credentialStore: store,
              httpClient: client,
            ),
          ))
          .run(['push', 'pro_upgrade', ...args, '-C', app.path]);

  void writeConfig({String? plane}) {
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
      '${plane == null ? '' : 'plane: $plane\n'}',
    );
  }

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_plane_');
    home = await Directory.systemTemp.createTemp('surface_push_plane_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    await seedGeneratedPaywall(app);
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test('selectors go to the server as given, once', () async {
    writeConfig();
    final published = <Map<String, dynamic>>[];
    final resolutions = <Map<String, dynamic>>[];
    final inner = backend(published: published);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] == 'resolveTarget') resolutions.add(body);
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..body = request.body;
      return inner.send(copy).then(http.Response.fromStream);
    });

    final code = await push([
      '--plane',
      'live',
      '--organization-id',
      '7',
    ], client);

    expect(code, 0, reason: err.toString());
    expect(resolutions, hasLength(1));
    expect(resolutions.single['organizationId'], 7);
    expect(resolutions.single['runtimePlane'], 'live');
    expect(published.last['environmentTargetId'], 32);
    expect(out.toString(), contains('pro_upgrade --plane live`'));
  });

  test(
    'the config plane picks the target and the hint needs no flag',
    () async {
      writeConfig(plane: 'live');
      final published = <Map<String, dynamic>>[];

      final code = await push([], backend(published: published));

      expect(code, 0, reason: err.toString());
      expect(published.single['environmentTargetId'], 32);
      expect(published.single['runtimePlane'], 'live');
      expect(
        out.toString(),
        contains(
          'Not live yet. Run `restage surface publish pro_upgrade` to publish '
          'it.',
        ),
      );
    },
  );

  test('--plane overrides the config and the hint repeats it', () async {
    writeConfig(plane: 'sandbox');
    final published = <Map<String, dynamic>>[];

    final code = await push(['--plane', 'live'], backend(published: published));

    expect(code, 0, reason: err.toString());
    expect(published.single['environmentTargetId'], 32);
    expect(
      out.toString(),
      contains(
        'Not live yet. Run `restage surface publish pro_upgrade --plane live` '
        'to publish it.',
      ),
    );
  });

  test('through the MCP server the hint names the publish tool', () async {
    writeConfig(plane: 'sandbox');

    final code = await runZoned(
      () => push(['--plane', 'live'], backend(published: [])),
      zoneValues: selectorSyntaxZoneValues(SelectorSyntax.mcp),
    );

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      contains(
        'Not live yet. Call restage_publish_surface with surfaceSlug: '
        'pro_upgrade, surfaceType: paywall, environmentSlug: staging, '
        'runtimePlane: live to publish it.',
      ),
    );
    expect(out.toString(), isNot(contains('restage surface publish')));
  });

  test('no plane on an environment with both planes asks for one', () async {
    writeConfig();

    final code = await push([], backend());

    expect(code, 1);
    expect(
      err.toString(),
      contains(
        "Environment 'staging' exists on both runtime planes. Pass "
        '--plane <sandbox|live>, or set `plane` in restage_config.yaml.',
      ),
    );
  });

  test('a push that is already live gives no publish hint', () async {
    writeConfig(plane: 'sandbox');

    final code = await push([], backend(activeRevision: 1));

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('active revision 1'));
    expect(out.toString(), isNot(contains('Not live yet')));
    expect(out.toString(), isNot(contains('Nothing is live')));
  });

  test('a role refusal names the role, not the sign-in', () async {
    writeConfig(plane: 'live');

    final code = await push(
      [],
      backend(
        refusal: http.Response(
          jsonEncode({
            'className': 'UnauthorizedException',
            'data': {
              '__className__': 'UnauthorizedException',
              'resource':
                  'hosted-billing-control-plane:productionSurfacePublish:'
                  'organization:7:2026-08',
              'reason': 'liveChangesNotAllowed',
            },
          }),
          400,
        ),
      ),
    );

    expect(code, 1);
    expect(
      err.toString(),
      contains(
        "This organization's plan does not allow changes to the live plane.",
      ),
    );
    expect(err.toString(), isNot(contains('restage login')));
  });
}
