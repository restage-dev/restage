import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/api.dart'
    show encodeByteDataWire, decodeByteDataWire, SurfacePublicationUploadResult;
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as m;
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  m.DeliveryPublicationReferenceV1 pushedReference() =>
      m.DeliveryPublicationReferenceV1(
        surface: m.DeliverySurfaceReferenceV1(
          surfaceIdentity: m.PublishedSurfaceIdentityV1(
            target: m.TargetCoordinate(
              organizationId: m.OrganizationId(7),
              appId: m.ApplicationId(5),
              environmentTargetId: m.EnvironmentTargetId(12),
              namedEnvironmentId: m.NamedEnvironmentId(22),
              runtimePlane: m.RuntimePlane.sandbox,
            ),
            surfaceId: m.SurfaceId('opaque-stored-surface-id'),
          ),
          family: const m.DeliveryFamilySelectorV1.general(),
        ),
        publishedVersion: 3,
        payloadFormatVersion: 2,
        contentHash: m.CanonicalDigest('a' * 64),
      );

  http.Response pushWithReference(m.DeliveryPublicationReferenceV1 reference) {
    final wire =
        jsonDecode(
              publishSucceeded(
                'pro_upgrade',
                storedRevision: 3,
                activeRevision: 1,
                identityFrozen: true,
              ).body,
            )
            as Map<String, dynamic>;
    wire['deliveryPublicationBytes'] = encodeByteDataWire(
      reference.canonicalBytes,
    );
    return http.Response(jsonEncode(wire), 200);
  }

  /// A backend that accepts the push and answers coverage against a build
  /// registering [registered], or no build when it is null.
  http.Client backend({Map<String, int>? registered, List<String>? methods}) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods?.add(body['method'] as String);
        if (body['method'] == 'coverage') {
          expect(body['surfaceSlug'], 'pro_upgrade');
          expect(body['environmentSlug'], 'staging');
          return http.Response(
            jsonEncode(<String, Object?>{
              'requiredLibraries': [
                {'namespace': 'acme.widgets', 'minVersion': 2},
              ],
              'headVersion': registered == null ? null : 4,
              'registeredLibraries': [
                for (final entry in (registered ?? const {}).entries)
                  {'namespace': entry.key, 'capabilityVersion': entry.value},
              ],
            }),
            200,
          );
        }
        return publishSucceeded(
          'pro_upgrade',
          storedRevision: 3,
          activeRevision: 3,
        );
      });

  Future<int?> push(
    List<String> args, {
    required http.Client client,
    Command<int> Function()? buildCommand,
  }) {
    final command = SurfacePushCommand(
      stdout: out,
      stderr: err,
      interactive: const NonInteractive(),
      credentialStore: store,
      httpClient: client,
      buildCommand: buildCommand,
    );
    return (CommandRunner<int>(
      'restage',
      '',
    )..addCommand(command)).run(['push', ...args, '-C', app.path]);
  }

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_build_');
    home = await Directory.systemTemp.createTemp('surface_push_build_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
    await seedGeneratedPaywall(
      app,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test(
    'plain push reports inverse fit for the exact newly stored revision while the active pointer is frozen',
    () async {
      await seedGeneratedPaywall(app);
      final reference = pushedReference();
      final methods = <String>[];
      final client = mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods.add(body['method'] as String);
        if (body['method'] == 'publishPublication') {
          return pushWithReference(reference);
        }
        expect(request.url.path, '/deliveryPolicy');
        expect(body['method'], 'readFit');
        final fit = m.DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(
          decodeByteDataWire(
            body['requestBytes'],
            malformed: FormatException.new,
          ),
        );
        expect(fit.publication, reference);
        expect(fit.publication!.publishedVersion, 3);
        expect(fit.scope, isNull);
        expect(body['environmentTargetId'], 12);
        expect(body['organizationId'], 7);
        final result = m.DeliveryPolicyFitReadV1(
          request: fit,
          authorityDigest: m.CanonicalDigest('b' * 64),
          entries: [
            for (final key in ['named:welcome', 'default:paywall:welcome'])
              m.DeliveryPolicyFitEntryV1(
                scope: m.DeliveryPolicyScopeV1(
                  root: m.DeliveryRootIdentityV1.placement(
                    m.PlacementIdentityV1(
                      target: reference.surface.target,
                      key: m.PlacementKeyV1.parse(key),
                    ),
                  ),
                  family: const m.DeliveryFamilySelectorV1.none(),
                ),
                publication: reference,
                verdictCanonicalBytes: m.CanonicalJsonCodec.encode({
                  'accepted': true,
                  'failures': <Object>[],
                  'appBuildContractHash': 'sha256:${'c' * 64}',
                }),
              ),
          ],
        );
        return http.Response(
          jsonEncode(encodeByteDataWire(result.canonicalBytes)),
          200,
        );
      });
      expect(
        await push(['pro_upgrade'], client: client),
        0,
        reason: err.toString(),
      );
      expect(methods, ['publishPublication', 'readFit']);
      expect(out.toString(), contains('stored revision 3; active revision 1'));
      expect(out.toString(), contains('Placement fit for stored revision 3'));
      expect(out.toString(), contains('named:welcome'));
      expect(out.toString(), contains('default:paywall:welcome'));
      expect(out.toString(), contains('appBuildContractHash'));
    },
  );

  test(
    'old-server absent reference reports unavailable without a head lookup and keeps push success',
    () async {
      await seedGeneratedPaywall(app);
      final methods = <String>[];
      expect(await push(['pro_upgrade'], client: backend(methods: methods)), 0);
      expect(methods, ['publishPublication']);
      expect(
        out.toString(),
        contains('Placement fit report unavailable for stored revision 3'),
      );
    },
  );

  test(
    'push follows exact inverse fit continuations without changing immutable coordinates',
    () async {
      await seedGeneratedPaywall(app);
      final reference = pushedReference();
      final cursors = <String?>[];
      final client = mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'publishPublication') {
          return pushWithReference(reference);
        }
        expect(body['method'], 'readFit');
        final fit = m.DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(
          decodeByteDataWire(
            body['requestBytes'],
            malformed: FormatException.new,
          ),
        );
        expect(fit.publication, reference);
        expect(fit.pageSize, 200);
        cursors.add(fit.cursor);
        final first = cursors.length == 1;
        final result = m.DeliveryPolicyFitReadV1(
          request: fit,
          authorityDigest: m.CanonicalDigest('b' * 64),
          nextCursor: first ? 'opaque-fit-page-two' : null,
          entries: [
            m.DeliveryPolicyFitEntryV1(
              scope: m.DeliveryPolicyScopeV1(
                root: m.DeliveryRootIdentityV1.placement(
                  m.PlacementIdentityV1(
                    target: reference.surface.target,
                    key: m.PlacementKeyV1.named(
                      slug: first ? 'first' : 'second',
                    ),
                  ),
                ),
                family: const m.DeliveryFamilySelectorV1.none(),
              ),
              publication: reference,
              verdictCanonicalBytes: m.CanonicalJsonCodec.encode({
                'accepted': true,
              }),
            ),
          ],
        );
        return http.Response(
          jsonEncode(encodeByteDataWire(result.canonicalBytes)),
          200,
        );
      });
      expect(await push(['pro_upgrade'], client: client), 0);
      expect(cursors, [null, 'opaque-fit-page-two']);
      expect(out.toString(), contains('named:first'));
      expect(out.toString(), contains('named:second'));
    },
  );

  test(
    'authority changes between inverse pages mark the whole report unavailable and preserve push success',
    () async {
      await seedGeneratedPaywall(app);
      final reference = pushedReference();
      var reads = 0;
      final client = mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'publishPublication') {
          return pushWithReference(reference);
        }
        final fit = m.DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(
          decodeByteDataWire(
            body['requestBytes'],
            malformed: FormatException.new,
          ),
        );
        reads++;
        final result = m.DeliveryPolicyFitReadV1(
          request: fit,
          authorityDigest: m.CanonicalDigest((reads == 1 ? 'b' : 'c') * 64),
          nextCursor: reads == 1 ? 'opaque-fit-page-two' : null,
          entries: [
            m.DeliveryPolicyFitEntryV1(
              scope: m.DeliveryPolicyScopeV1(
                root: m.DeliveryRootIdentityV1.placement(
                  m.PlacementIdentityV1(
                    target: reference.surface.target,
                    key: m.PlacementKeyV1.named(slug: 'first'),
                  ),
                ),
                family: const m.DeliveryFamilySelectorV1.none(),
              ),
              publication: reference,
              verdictCanonicalBytes: m.CanonicalJsonCodec.encode({
                'accepted': true,
              }),
            ),
          ],
        );
        return http.Response(
          jsonEncode(encodeByteDataWire(result.canonicalBytes)),
          200,
        );
      });
      expect(await push(['pro_upgrade'], client: client), 0);
      expect(reads, 2);
      expect(out.toString(), contains('Placement fit report unavailable'));
      expect(
        out.toString(),
        isNot(contains('Placement fit for stored revision')),
      );
    },
  );

  test(
    'unavailable inverse read preserves the successful stored push',
    () async {
      await seedGeneratedPaywall(app);
      final methods = <String>[];
      final client = mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods.add(body['method'] as String);
        return body['method'] == 'publishPublication'
            ? pushWithReference(pushedReference())
            : http.Response('temporarily unavailable', 503);
      });
      expect(
        await push(['pro_upgrade'], client: client),
        0,
        reason: err.toString(),
      );
      expect(methods, ['publishPublication', 'readFit']);
      expect(out.toString(), contains('Pushed pro_upgrade'));
      expect(out.toString(), contains('Placement fit report unavailable'));
    },
  );

  test(
    'nullable additive publication reference decodes strictly and binds stored revision',
    () {
      final reference = pushedReference();
      final oldWire = jsonDecode(
        publishSucceeded('pro_upgrade', storedRevision: 3).body,
      );
      expect(
        SurfacePublicationUploadResult.fromWire(oldWire).deliveryPublication,
        isNull,
      );
      final result = SurfacePublicationUploadResult.fromWire(
        jsonDecode(pushWithReference(reference).body),
      );
      expect(result.deliveryPublication, reference);
      expect(
        SurfacePublicationUploadResult.fromWire(
          result.toJson(),
        ).deliveryPublication,
        reference,
      );
      final wrong = {...result.toJson(), 'storedPublishedRevision': 4};
      expect(
        () => SurfacePublicationUploadResult.fromWire(wrong),
        throwsFormatException,
      );
    },
  );

  test('a push says when the dashboard has no build for its widgets', () async {
    final code = await push(['pro_upgrade'], client: backend());

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      contains(
        'This surface uses widgets from your app (acme.widgets). The '
        'dashboard has no build of mobile for staging yet',
      ),
    );
  });

  test('a push whose widgets the build covers says nothing', () async {
    final code = await push([
      'pro_upgrade',
    ], client: backend(registered: const {'acme.widgets': 2}));

    expect(code, 0, reason: err.toString());
    expect(out.toString(), isNot(contains('widgets from your app')));
  });

  test('a surface built from the catalog alone never asks', () async {
    await seedGeneratedPaywall(app, slug: 'pro_upgrade');
    final methods = <String>[];
    final code = await push(['pro_upgrade'], client: backend(methods: methods));

    expect(code, 0, reason: err.toString());
    expect(methods, isNot(contains('coverage')));
    expect(out.toString(), isNot(contains('widgets from your app')));
  });

  test('--build pushes the build to the same environment first', () async {
    final seen = <List<String>>[];
    final code = await push(
      ['pro_upgrade', '--build'],
      client: backend(registered: const {'acme.widgets': 2}),
      buildCommand: () => _FakeBuildCommand(seen, exitCode: 0),
    );

    expect(code, 0, reason: err.toString());
    expect(seen, hasLength(1));
    expect(seen.single, containsAllInOrder(<String>['--env', 'staging']));
    expect(seen.single, containsAllInOrder(<String>['--app', 'mobile']));
    expect(out.toString(), contains('Pushing the build of mobile to staging'));
    expect(out.toString(), contains('Pushed pro_upgrade'));
  });

  test('a build that fails does not stop the surfaces', () async {
    final methods = <String>[];
    final code = await push(
      ['pro_upgrade', '--build'],
      client: backend(methods: methods),
      buildCommand: () => _FakeBuildCommand(<List<String>>[], exitCode: 1),
    );

    expect(code, 1);
    expect(methods, contains('publishPublication'));
    expect(methods, isNot(contains('coverage')));
    expect(out.toString(), contains('Pushed pro_upgrade'));
    expect(
      err.toString(),
      contains('The surfaces were pushed, but the build of mobile was not.'),
    );
    expect(err.toString(), contains('`restage build push --env staging`'));
  });

  test(
    'organization ID overrides config for the surface and its build',
    () async {
      File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
        'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
        'organization: configured-org\norganizationId: 99\nappId: 98\n'
        'environmentTargetId: 97\nnamedEnvironmentId: 96\n',
      );
      final seen = <List<String>>[];
      final code = await push(
        ['pro_upgrade', '--build', '--organization-id=7'],
        client: backend(registered: const {'acme.widgets': 2}),
        buildCommand: () => _FakeBuildCommand(seen, exitCode: 0),
      );

      expect(code, 0, reason: err.toString());
      expect(seen.single, contains('--organization-id=7'));
      expect(seen.single, isNot(contains('--organization')));
      expect(out.toString(), contains('Pushed pro_upgrade'));
    },
  );

  test('--flutter-root reaches the build step', () async {
    final seen = <List<String>>[];
    final code = await push(
      ['pro_upgrade', '--build', '--flutter-root', '/opt/flutter'],
      client: backend(registered: const {'acme.widgets': 2}),
      buildCommand: () => _FakeBuildCommand(seen, exitCode: 0),
    );

    expect(code, 0, reason: err.toString());
    expect(
      seen.single,
      containsAllInOrder(<String>['--flutter-root', '/opt/flutter']),
    );
  });
}

/// Stands in for `restage build`; its `push` records what it was asked.
final class _FakeBuildCommand extends Command<int> {
  _FakeBuildCommand(List<List<String>> seen, {required int exitCode}) {
    addSubcommand(_FakeBuildPushCommand(seen, exitCode: exitCode));
  }

  @override
  String get name => 'build';

  @override
  String get description => '';
}

final class _FakeBuildPushCommand extends Command<int> {
  _FakeBuildPushCommand(this._seen, {required int exitCode})
    : _exitCode = exitCode {
    argParser
      ..addOption('project')
      ..addOption('app')
      ..addOption('organization')
      ..addOption('organization-id')
      ..addOption('env')
      ..addOption('directory', abbr: 'C')
      ..addOption('flutter-root')
      ..addFlag('record-git', negatable: false);
  }

  final List<List<String>> _seen;
  final int _exitCode;

  @override
  String get name => 'push';

  @override
  String get description => '';

  @override
  Future<int> run() async {
    _seen.add(argResults!.arguments);
    return _exitCode;
  }
}
