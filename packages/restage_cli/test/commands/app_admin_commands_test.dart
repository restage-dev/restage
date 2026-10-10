import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
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
    http.Response Function(Map<String, dynamic> body) respond,
  ) => RestageCli(
    stdout: out,
    stderr: err,
    credentialStore: store,
    httpClient: mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
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
    }),
  ).run([...args, '-C', tempDir.path]);

  test('orgs lists every membership with its role', () async {
    final code = await run(['orgs'], (_) => http.Response('[]', 200));

    expect(code, 0, reason: err.toString());
    expect(out.toString(), 'ID\tSLUG\tNAME\tROLE\n7\trestage\tRestage\t-\n');
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
}
