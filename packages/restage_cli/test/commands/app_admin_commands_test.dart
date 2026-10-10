import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/config/config_target_check.dart'
    show noOrganizationSentence;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_admin_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'staging',
    );
    out = StringBuffer();
    err = StringBuffer();
    calls = [];
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Run the CLI against a backend answering discovery, then [respond].
  Future<int> run(
    List<String> args,
    http.Response Function(Map<String, dynamic> body) respond, {
    http.Response? scopeResponse,
  }) => RestageCli(
    stdout: out,
    stderr: err,
    credentialStore: store,
    httpClient: mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (scopeResponse != null && body['method'] == 'read') {
        calls.add(body);
        return scopeResponse;
      }
      if (body['method'] == 'listProjects') {
        return http.Response(
          jsonEncode([
            {'slug': 'alpha', 'name': 'Alpha'},
          ]),
          200,
        );
      }
      calls.add(body);
      return respond(body);
    }, withDefaultTargetDiscovery: scopeResponse == null),
  ).run([...args, '-C', tempDir.path]);

  test('orgs lists every membership with its role', () async {
    final code = await run(['orgs'], (_) => http.Response('[]', 200));

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      'ID\tSLUG\tNAME\tROLE\n7\trestage\tRestage\towner\n',
    );
  });

  test('orgs says where to create one when the account has none', () async {
    final code = await RestageCli(
      stdout: out,
      stderr: err,
      credentialStore: store,
      // A signed-in account in no organization reads a session-only scope.
      httpClient: mockHttpClient(
        (_) => http.Response(
          jsonEncode({
            'session': {
              'memberships': <Object>[],
              'workspaceExperiences': <Object>[],
            },
          }),
          200,
        ),
        withDefaultTargetDiscovery: false,
      ),
    ).run(['orgs', '-C', tempDir.path]);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), '$noOrganizationSentence\n');
  });

  test('app-config show and set read and change the app', () async {
    final app = {
      'id': 5,
      'slug': 'mobile',
      'name': 'Mobile',
      'iosBundleId': 'com.acme.ios',
    };
    var code = await run(['app-config', 'show'], (_) => http.Response('', 200));
    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('slug: mobile'));

    out.clear();
    code = await run([
      'app-config',
      'set',
      '--web-domain',
      '',
      '--json',
    ], (_) => http.Response(jsonEncode(app), 200));
    expect(code, 0, reason: err.toString());
    final update = calls.singleWhere(
      (call) => call['method'] == 'updateAppConfiguration',
    );
    expect(update['webDomain'], '');
    expect(update.containsKey('iosBundleId'), isFalse);
    expect(update['organizationId'], 7);
    expect(jsonDecode(out.toString()), app);
  });

  test('org rename and app rename send the new name, never a slug', () async {
    var code = await run([
      'org',
      'rename',
      'Acme Labs',
    ], (_) => http.Response('null', 200));
    expect(code, 0, reason: err.toString());
    final org = calls.singleWhere((call) => call['method'] == 'rename');
    expect(org['organizationId'], 7);
    expect(org['name'], 'Acme Labs');
    expect(org.containsKey('slug'), isFalse);

    code = await run(
      ['app', 'rename', 'Lumen', '--json'],
      (_) => http.Response(
        jsonEncode({'id': 5, 'slug': 'mobile', 'name': 'Lumen'}),
        200,
      ),
    );
    expect(code, 0, reason: err.toString());
    final app = calls.singleWhere((call) => call['method'] == 'renameApp');
    expect(app['projectSlug'], 'alpha');
    expect(app['appSlug'], 'mobile');
    expect(app['name'], 'Lumen');
  });

  test('app-config set with nothing to change is refused locally', () async {
    final code = await run(['app-config', 'set'], (_) {
      fail('no backend call expected');
    });

    expect(code, 1);
    expect(err.toString(), contains('Nothing to change.'));
  });

  test('products list and import pass the store', () async {
    final rows = [
      {
        'store': 'appStore',
        'storeProductId': 'pro_month',
        'displayName': 'Pro',
        'priceMicros': 9990000,
        'currency': 'USD',
        'productSlotId': 3,
      },
    ];
    var code = await run([
      'products',
      'list',
      '--store',
      'appStore',
    ], (_) => http.Response(jsonEncode(rows), 200));
    expect(code, 0, reason: err.toString());
    expect(calls.last['store'], 'appStore');
    expect(
      out.toString(),
      contains('appStore\tpro_month\tPro\t9990000\tUSD\t3'),
    );

    code = await run(['products', 'import'], (_) => http.Response('[]', 200));
    expect(code, 1);
    expect(err.toString(), contains('Required: --store'));

    code = await run([
      'products',
      'import',
      '--store',
      'playStore',
    ], (_) => http.Response('[]', 200));
    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'importProducts');
    expect(calls.last['store'], 'playStore');
  });

  test('slots set replaces the whole mapping and `none` unmaps', () async {
    final code = await run(
      [
        'slots',
        'set',
        'pro',
        '--entitlement',
        'premium',
        '--ios-product-id',
        'pro_month',
        '--android-product-id',
        'none',
      ],
      (_) => http.Response(
        jsonEncode({'id': 3, 'name': 'pro', 'entitlement': 'premium'}),
        200,
      ),
    );

    expect(code, 0, reason: err.toString());
    final upsert = calls.single;
    expect(upsert['method'], 'upsert');
    expect(upsert['iosProductId'], 'pro_month');
    expect(upsert.containsKey('androidProductId'), isFalse);
    expect(out.toString(), 'id: 3\nname: pro\nentitlement: premium\n');
  });

  test('slots set without every store is refused locally', () async {
    final code = await run([
      'slots',
      'set',
      'pro',
      '--entitlement',
      'premium',
    ], (_) => fail('no backend call expected'));

    expect(code, 1);
    expect(err.toString(), contains('pass `none` to unmap a store'));
  });

  test('stores list never prints a credential', () async {
    final code = await run(
      ['stores', 'list'],
      (_) => http.Response(
        jsonEncode([
          {
            'store': 'appStore',
            'status': 'verified',
            'storeAppIdentifier': 'com.acme',
            'credentialFingerprint': 'a1b2',
            'lastVerifiedAt': '2026-09-01T00:00:00.000Z',
          },
        ]),
        200,
      ),
    );

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('appStore\tverified\tcom.acme\ta1b2'));
  });

  test('keys list resolves the exact target and revoke takes an id', () async {
    var code = await run(
      ['keys', 'list'],
      (_) => http.Response(
        jsonEncode([
          {'id': 12, 'kind': 'publishable', 'keyPrefix': 'rs_pk_ab'},
        ]),
        200,
      ),
    );
    expect(code, 0, reason: err.toString());
    final list = calls.singleWhere((call) => call['method'] == 'listKeys');
    expect(list['environmentTargetId'], 12);
    expect(list['runtimePlane'], 'sandbox');
    expect(out.toString(), contains('12\tpublishable\trs_pk_ab'));

    out.clear();
    code = await run(['keys', 'revoke', '12'], (_) => http.Response('', 200));
    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'revokeKey');
    expect(calls.last['apiKeyId'], 12);
    expect(out.toString(), 'Revoked key 12.\n');

    code = await run(['keys', 'revoke', 'x'], (_) => fail('no call'));
    expect(code, 1);
  });

  test('keys resolve finds the target a key belongs to without sending '
      'it', () async {
    const key = 'rs_pk_sandbox_staging_6326f3aa99bb00cc';
    final scopeResponse = http.Response(
      jsonEncode({
        'organizationId': 7,
        'session': {
          'memberships': [
            {
              'organizationId': 7,
              'slug': 'restage',
              'name': 'Restage',
              'role': 'owner',
            },
          ],
          'workspaceExperiences': <Object>[],
        },
        'projects': [
          {'id': 1, 'slug': 'alpha', 'name': 'Alpha'},
        ],
        'apps': [
          {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
        ],
        'environments': [
          {'id': 11, 'appId': 5, 'namedEnvironmentId': 21, 'slug': 'dev'},
          {'id': 12, 'appId': 5, 'namedEnvironmentId': 22, 'slug': 'staging'},
        ],
        'environmentTargets': [
          {
            'environmentTargetId': 11,
            'namedEnvironmentId': 21,
            'environmentSlug': 'dev',
            'runtimePlane': 'sandbox',
          },
          {
            'environmentTargetId': 12,
            'namedEnvironmentId': 22,
            'environmentSlug': 'staging',
            'runtimePlane': 'sandbox',
          },
        ],
        'surfaces': <Object>[],
        'apiKeys': [
          {
            'id': 40,
            'environmentId': 12,
            'kind': 'publishable',
            'keyPrefix': 'rs_pk_sandbox_staging_6326f3...',
            'revokedAt': null,
          },
          {
            'id': 41,
            'environmentId': 11,
            'kind': 'publishable',
            'keyPrefix': 'rs_pk_sandbox_dev_0a0a0a...',
            'revokedAt': null,
          },
        ],
      }),
      200,
    );
    final code = await run(
      ['keys', 'resolve', key],
      (_) => fail('key resolution uses the admitted scope only'),
      scopeResponse: scopeResponse,
    );

    expect(code, 0, reason: err.toString());
    for (final call in calls) {
      expect(jsonEncode(call), isNot(contains('aa99bb00cc')));
    }
    expect(calls, hasLength(1));
    expect(calls.single['method'], 'read');
    expect(
      out.toString(),
      contains(
        'restage\talpha\tmobile\tstaging\tsandbox\t12\t'
        'rs_pk_sandbox_staging_6326f3...',
      ),
    );
    expect(out.toString(), isNot(contains('rs_pk_sandbox_dev')));
    expect(out.toString(), isNot(contains('aa99bb00cc')));

    out.clear();
    err.clear();
    final missing = await run(
      ['keys', 'resolve', 'rs_pk_sandbox_prod_ffffff'],
      (_) => fail('key resolution uses the admitted scope only'),
      scopeResponse: scopeResponse,
    );
    expect(missing, 1);
    expect(err.toString(), contains('No active API key in restage matches'));
    expect(err.toString(), isNot(contains('ffffff')));
  });

  test('a role refusal reads with the shared sentence', () async {
    final code = await run(
      ['products', 'import', '--store', 'appStore'],
      (_) => http.Response(
        jsonEncode({
          'className': 'UnauthorizedException',
          'data': {
            '__className__': 'UnauthorizedException',
            'resource': 'product',
          },
        }),
        403,
      ),
    );

    expect(code, 1);
    expect(
      err.toString(),
      contains('Your role in this organization does not allow this.'),
    );
  });

  group('app delete', () {
    http.Response typed(String className, Map<String, Object?> data) =>
        http.Response(
          jsonEncode({
            'className': className,
            'data': {'__className__': className, ...data},
          }),
          400,
        );

    test('deletes the app, naming it by its exact name', () async {
      final code = await run([
        'app',
        'delete',
        '--name',
        'Welcome Tour',
      ], (_) => http.Response('null', 200));

      expect(code, 0, reason: err.toString());
      final call = calls.singleWhere((c) => c['method'] == 'deleteApp');
      expect(call['endpoint'] ?? 'app', 'app');
      expect(call['projectSlug'], 'alpha');
      expect(call['appSlug'], 'mobile');
      expect(call['confirmationName'], 'Welcome Tour');
      expect(out.toString(), 'Deleted app mobile.\n');
    });

    test('a delete without --name is refused before any call', () async {
      final code = await run(['app', 'delete'], (_) => fail('no call'));

      expect(code, 1);
      expect(err.toString(), contains('--name'));
    });

    test('a refusal names what still uses the app, with counts', () async {
      final code = await run(
        ['app', 'delete', '--name', 'Welcome Tour'],
        (_) => typed('AppDeleteRefusedException', {
          'appName': 'Welcome Tour',
          'projectName': 'Fitness',
          'holds': [
            {'kind': 'servingSurface', 'count': 2},
            {'kind': 'activeApiKey', 'count': 1},
            {'kind': 'runningExperiment', 'count': 3},
            {'kind': 'deliveryRule', 'count': 1},
            {'kind': 'lastAppInProject', 'count': 1},
          ],
        }),
      );

      expect(code, 1);
      expect(
        err.toString(),
        'Welcome Tour is still in use\n'
        '  2 surfaces serving\n'
        '  1 active API key\n'
        '  3 running experiments\n'
        '  1 delivery rule\n'
        '  The only app in Fitness\n',
      );
    });

    test('a name that is not the app\'s reads with the app\'s name', () async {
      final code = await run(
        ['app', 'delete', '--name', 'Welcome'],
        (_) => typed('AppDeleteNameMismatchException', {
          'appName': 'Welcome Tour',
        }),
      );

      expect(code, 1);
      expect(
        err.toString(),
        "--name doesn't match the app's name, Welcome Tour.\n",
      );
    });
  });
}
