import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart'
    show encodeByteDataWire;
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryMeasurementMutationReviewV1, CanonicalDigest;
import 'package:restage_shared/rfw_formats.dart' as rfw_formats;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Encode a small, ordinary, uninstrumented RFW library for publish tests.
Uint8List ordinaryRfwBlob() => rfw_formats.encodeLibraryBlob(
  rfw_formats.parseLibraryFile('''
import restage.core;
widget Preview = Text(text: "ordinary");
'''),
);

/// Create a Git repository at [root] on `main` that ignores the machine's
/// identity, signing key, hooks and background maintenance. The configuration
/// is written directly because every spawn from a large test runner is costly.
Future<void> initTestGitRepository(Directory root) async {
  await _gitOrFail(root, ['init', '-b', 'main', '.']);
  File(p.join(root.path, '.git', 'config')).writeAsStringSync(
    '[user]\n'
    '\tname = Receipt Test\n'
    '\temail = receipts@example.test\n'
    '[commit]\n'
    '\tgpgsign = false\n'
    '[core]\n'
    '\thooksPath = .git/hooks\n'
    // Maintenance a commit starts in the background can write during teardown.
    '[gc]\n'
    '\tauto = 0\n'
    '[maintenance]\n'
    '\tauto = false\n',
    mode: FileMode.append,
  );
}

/// A committed Git repository built once and copied into each test's root,
/// so a suite pays for `git init`, `add` and `commit` once.
final class TestGitTemplate {
  TestGitTemplate._(this._source, this.commit);

  /// Build a repository whose first commit, titled [message], holds what
  /// [seed] writes.
  static Future<TestGitTemplate> create(
    Future<void> Function(Directory root) seed, {
    String message = 'first',
  }) async {
    final source = await Directory.systemTemp.createTemp('git_template_');
    await initTestGitRepository(source);
    await seed(source);
    await _gitOrFail(source, ['add', '-A']);
    await _gitOrFail(source, ['commit', '-m', message]);
    final head = await _gitOrFail(source, ['rev-parse', 'HEAD']);
    return TestGitTemplate._(source, (head.stdout as String).trim());
  }

  final Directory _source;

  /// The template's single commit.
  final String commit;

  /// Copy the repository into the empty directory [root].
  Future<void> copyTo(Directory root) async {
    await for (final entity in _source.list(recursive: true)) {
      final target = p.join(
        root.path,
        p.relative(entity.path, from: _source.path),
      );
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
    // Copied files carry new stat data; refresh so the index sees them clean.
    await _gitOrFail(root, ['update-index', '-q', '--refresh']);
  }

  /// Remove the template.
  Future<void> delete() => _source.delete(recursive: true);
}

Future<ProcessResult> _gitOrFail(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

/// Writes a test credential directly to [store], avoiding the unnecessary
/// `chmod` process started by [FileCredentialStore.write].
Future<void> seedCredential(
  FileCredentialStore store, {
  String endpoint = 'http://localhost:8080/',
  String authToken = 'kid:secret',
}) async {
  final credential = Credential(
    endpoint: endpoint,
    kind: CredentialKind.authKey,
    authToken: authToken,
  );
  final file = File(store.path);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(credential.toJson()));
}

/// Write a `restage_config.yaml` to [dir]. [defaultEnvironment] is
/// omitted when null.
Future<void> seedRestageConfig(
  Directory dir,
  String project,
  String app, {
  String? defaultEnvironment,
  String? organization,
  String? endpoint,
  String? plane,
}) async {
  final buffer = StringBuffer()
    ..writeln('project: $project')
    ..writeln('app: $app');
  if (defaultEnvironment != null) {
    buffer.writeln('defaultEnvironment: $defaultEnvironment');
  }
  if (organization != null) {
    buffer.writeln('organization: $organization');
  }
  if (endpoint != null) {
    buffer.writeln('endpoint: $endpoint');
  }
  if (plane != null) {
    buffer.writeln('plane: $plane');
  }
  await File(
    p.join(dir.path, 'restage_config.yaml'),
  ).writeAsString(buffer.toString());
}

/// Write [bytes] to `<dir>/assets/paywalls/<name>.rfw`, plus the capability
/// manifest sidecar the codegen emits alongside it (so the publish path's
/// derived-floor read resolves). [minClient] is the derived built-in floor the
/// sidecar records (default a non-baseline value so a test asserting it proves
/// the floor came from the sidecar, not a hardcoded default).
Future<void> seedRfw(
  Directory dir,
  String name,
  List<int> bytes, {
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const [],
}) async {
  final target = File(p.join(dir.path, 'assets', 'paywalls', '$name.rfw'));
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes);
  await seedCapabilitySidecar(
    target.path,
    minClient: minClient,
    requiredLibraries: requiredLibraries,
  );
}

/// Write the capability sidecar (`<stem>.capability.json`) next to the compiled
/// blob at [rfwPath] — mirrors what the codegen emits: the derived built-in
/// floor + required libraries plus the blob's content hash. The blob must
/// already exist at [rfwPath] (the hash is computed from it). Pass
/// [blobSha256Override] to write a deliberately-wrong hash (the stale-sidecar
/// case).
Future<void> seedCapabilitySidecar(
  String rfwPath, {
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const [],
  String? blobSha256Override,
}) async {
  final blob = await File(rfwPath).readAsBytes();
  final sidecar = File(
    p.join(
      p.dirname(rfwPath),
      '${p.basenameWithoutExtension(rfwPath)}.capability.json',
    ),
  );
  await sidecar.writeAsString(
    jsonEncode(
      CapabilitySidecar(
        blobSha256: blobSha256Override ?? CapabilitySidecar.hashBlob(blob),
        manifest: CapabilityManifest(
          builtInFloor: minClient,
          requiredLibraries: requiredLibraries,
        ),
      ).toJson(),
    ),
  );
}

/// The checkout this test is running inside, found by walking up from the
/// current working directory (the package dir under `dart test`) to the
/// nearest `.git`.
///
/// The walk STOPS there, and that bound is the point of this function. An
/// earlier version searched for a fixture directory instead and simply kept
/// walking when it was missing — so in a git worktree it climbed out of the
/// checkout entirely and found the fixture in whatever other checkout happened
/// to sit above it. Tests then passed locally against a tree that was not the
/// tree under test, and failed in CI, which has only one checkout and no
/// neighbour to borrow from. A fixture this can no longer reach must fail
/// loudly rather than resolve somewhere else.
///
/// `.git` is a directory in a clone and a file in a worktree; both count.
Directory locateCheckoutRoot() {
  var dir = Directory.current;
  while (true) {
    final marker = p.join(dir.path, '.git');
    if (Directory(marker).existsSync() || File(marker).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate the checkout root (no .git) above '
        '${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Directory holding the example app's committed surface bundles, inside THIS
/// checkout.
Directory locateExampleBundles() {
  final root = locateCheckoutRoot();
  final bundles = Directory(
    p.join(
      root.path,
      'apps',
      'examples',
      'assets',
      'restage',
      'bundles',
      'lib',
    ),
  );
  if (!bundles.existsSync()) {
    throw StateError(
      'Example bundles are missing from this checkout: ${bundles.path}',
    );
  }
  return bundles;
}

/// Write every entry of the bundle at [bundlePath] into [root], each at its
/// own logical delivery path, and return them by logical path.
///
/// The bundle is the tracked artifact, so its bytes are the same bytes the
/// generator emitted — which is what makes the content hashes inside a flow
/// document agree with the screen blobs seeded beside it.
Future<Map<String, Uint8List>> _unpackBundle(
  Directory root,
  String bundlePath,
) async {
  final bundle = RestageBundleCodec.decode(
    await File(bundlePath).readAsBytes(),
  );
  final written = <String, Uint8List>{};
  for (final entry in bundle.entries) {
    final destination = File(p.join(root.path, entry.logicalPath));
    await destination.parent.create(recursive: true);
    final bytes = entry.bytes;
    await destination.writeAsBytes(bytes);
    written[entry.logicalPath] = bytes;
  }
  return written;
}

/// Unpack the example app's real `<slug>` flow document and every screen it
/// references into [dir], each at its own logical delivery path.
///
/// Returns the resolved flow JSON path. Every artifact is the committed one,
/// so the content hashes agree with the flow document and the capability
/// sidecars carry the requirements the real screens declare.
///
/// Read from the tracked `.rsbundle`s rather than a loose asset tree: the
/// bundles ARE the shipped artifact, and a loose mirror of them is a second
/// copy that can rot or be deleted while the tests that depend on it keep
/// passing against another checkout.
Future<String> seedSurfaceFlow(
  Directory dir, {
  String type = 'onboarding',
  String slug = 'first_run',
}) async {
  final bundles = locateExampleBundles();
  final flowEntries = await _unpackBundle(
    dir,
    p.join(bundles.path, type, 'flows', '$slug.rsbundle'),
  );
  final flowPath = 'assets/$type/flows/$slug.flow.json';
  final doc = FlowDocumentCodec.decodeJson(utf8.decode(flowEntries[flowPath]!));
  for (final artifact in doc.screenArtifacts.values) {
    await _unpackBundle(
      dir,
      p.join(
        bundles.path,
        type,
        'screens',
        '${p.basenameWithoutExtension(artifact.path)}.rsbundle',
      ),
    );
  }
  return p.join(dir.path, flowPath);
}

// seedPaywallFlow and seedPaywallBlob lived here and are gone. Both read the
// same deleted loose asset tree as the old seed above, both had no callers,
// and neither could have run — so they were not dormant helpers waiting to be
// useful, they were two more ways to resolve a fixture outside this checkout.
// The paywall bundles they wanted are tracked
// (apps/examples/assets/restage/bundles/lib/paywalls/), so rebuilding either
// on top of _unpackBundle is small if a test ever needs one.

/// Build an [http.Client] that returns the same response for every
/// request, computed by [handler]. Useful when the test only cares
/// about a single round-trip.
///
/// Target-aware commands perform two read-only discovery calls before their
/// operation. The shared default keeps pre-target command fixtures focused on
/// the operation they exercise; discovery-specific tests opt out.
http.Client mockHttpClient(
  http.Response Function(http.Request request) handler, {
  bool withDefaultTargetDiscovery = true,
  bool withDefaultSurfaceReview = true,
}) => MockClient((request) async {
  if (withDefaultTargetDiscovery) {
    final discovery = _defaultTargetDiscoveryResponse(request);
    if (discovery != null) return discovery;
  }
  if (withDefaultSurfaceReview) {
    final review = _defaultSurfaceReviewResponse(request);
    if (review != null) return review;
  }
  return handler(request);
});

/// One scripted response per HTTP call. The Nth request to the
/// [http.Client] returns the response produced by `steps[N]`. Asserts
/// (via `test`'s `fail`) on overrun, so tests catch unexpected backend
/// chatter.
typedef ScriptStep = http.Response Function(http.Request request);

/// Script step for the exact-App discovery now required before target lookup.
http.Response activeAppDiscoveryResponse(
  http.Request request, {
  int appId = 5,
  String appSlug = 'mobile',
  String? projectSlug,
}) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listApps');
  if (projectSlug != null) expect(body['projectSlug'], projectSlug);
  return http.Response(
    jsonEncode([
      {'id': appId, 'slug': appSlug, 'name': appSlug},
    ]),
    200,
  );
}

/// Build an [http.Client] that drives [steps] one response per operation call.
/// Target discovery is supplied by default and does not consume a step.
http.Client scriptedHttpClient(
  List<ScriptStep> steps, {
  bool withDefaultTargetDiscovery = true,
  bool withDefaultSurfaceReview = true,
}) {
  var index = 0;
  return MockClient((request) async {
    if (withDefaultTargetDiscovery) {
      final discovery = _defaultTargetDiscoveryResponse(request);
      if (discovery != null) return discovery;
    }
    if (withDefaultSurfaceReview) {
      final review = _defaultSurfaceReviewResponse(request);
      if (review != null) return review;
    }
    if (index >= steps.length) {
      fail('Unexpected backend call ${index + 1}: ${request.url}');
    }
    final step = steps[index];
    final response = step(request);
    index++;
    return response;
  });
}

/// Ordinary fixtures have no measurement sources to lose. Warning tests supply
/// their own complete review and disable this default response.
http.Response? _defaultSurfaceReviewResponse(http.Request request) {
  if (request.url.pathSegments.last != 'surface') return null;
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  if (body['method'] != 'reviewDeliveryImpact') return null;
  final review = DeliveryMeasurementMutationReviewV1(
    operation: body['operation'] as String,
    reviews: const [],
    dependencyDigest: CanonicalDigest('a' * 64),
  );
  return http.Response(
    jsonEncode(encodeByteDataWire(review.canonicalBytes)),
    200,
  );
}

/// The targets the default fake backend exposes.
const defaultEnvironmentTargets = <Map<String, dynamic>>[
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
  {
    'environmentTargetId': 13,
    'namedEnvironmentId': 23,
    'environmentSlug': 'production',
    'runtimePlane': 'live',
  },
];

const _defaultAppIds = <String, int>{
  'mobile': 5,
  'a': 8,
  'default': 9,
  'config-app': 6,
  'flag-app': 7,
};

/// The server's answer to `environment.resolveTarget` over [targets]: the
/// one target the selectors in [body] name, or the typed refusal.
http.Response resolveTargetResponse(
  Map<String, dynamic> body, {
  List<Map<String, dynamic>> targets = defaultEnvironmentTargets,
  int organizationId = 7,
  String organizationSlug = 'restage',
  int? appId,
}) {
  final environment = body['environmentSlug'] as String?;
  final plane = body['runtimePlane'] as String?;
  final targetId = body['environmentTargetId'] as int?;
  Map<String, dynamic>? target;
  if (environment != null) {
    final named = [
      for (final candidate in targets)
        if (candidate['environmentSlug'] == environment) candidate,
    ];
    final matches = [
      for (final candidate in named)
        if ((plane == null || candidate['runtimePlane'] == plane) &&
            (targetId == null || candidate['environmentTargetId'] == targetId))
          candidate,
    ];
    if (matches.length != 1) {
      final reason = matches.length > 1
          ? 'environmentOnBothPlanes'
          : named.isNotEmpty && plane != null && targetId == null
          ? 'noTargetOnPlane'
          : 'environmentNotFound';
      return typedErrorResponse('TargetSelectionRefusedException', {
        'reason': reason,
        'environmentSlug': environment,
        if (matches.length > 1) 'candidates': {'items': matches},
      });
    }
    target = matches.single;
  }
  final appSlug = body['appSlug'] as String;
  return http.Response(
    jsonEncode({
      'organizationId': organizationId,
      'organizationSlug': organizationSlug,
      'projectSlug': body['projectSlug'],
      'appId': appId ?? _defaultAppIds[appSlug] ?? 5,
      'appSlug': appSlug,
      'target': ?target,
    }),
    200,
  );
}

/// A script step returning one admitted scope with [target] for target-aware
/// command tests. [inspect] sees the scope read request first.
ScriptStep scopeTargetStep(
  Map<String, dynamic> target, {
  int organizationId = 7,
  String organizationSlug = 'restage',
  int appId = 5,
  void Function(Map<String, dynamic> body)? inspect,
}) => (request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'read');
  inspect?.call(body);
  return http.Response(
    jsonEncode({
      'organizationId': organizationId,
      'session': {
        'memberships': [
          {
            'organizationId': organizationId,
            'slug': organizationSlug,
            'name': organizationSlug,
            'role': 'owner',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        for (final project in ['p', 'demo', 'alpha', 'default'])
          {'id': 1, 'slug': project, 'name': project},
      ],
      'apps': [
        for (final app in ['a', 'mobile', 'default'])
          {'id': appId, 'projectId': 1, 'slug': app, 'name': app},
      ],
      'environments': [
        {
          'id': target['environmentTargetId'],
          'appId': appId,
          'namedEnvironmentId': target['namedEnvironmentId'],
          'slug': target['environmentSlug'],
        },
      ],
      'environmentTargets': [target],
      'surfaces': <Object>[],
    }),
    200,
  );
};

/// A typed backend exception response.
http.Response typedErrorResponse(
  String className,
  Map<String, dynamic> fields, {
  int status = 400,
}) => http.Response(
  jsonEncode({
    'className': className,
    'data': {'__className__': className, ...fields},
  }),
  status,
);

http.Response? _defaultTargetDiscoveryResponse(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  switch (body['method']) {
    case 'read':
      if (request.url.path != '/scope') return null;
      return http.Response(
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
            for (final project in [
              'demo',
              'alpha',
              'p',
              'other',
              'default',
              'config-proj',
              'flag-proj',
            ])
              {'id': 1, 'slug': project, 'name': project},
          ],
          'apps': [
            for (final app in _defaultAppIds.entries)
              {
                'id': app.value,
                'projectId': 1,
                'slug': app.key,
                'name': app.key,
              },
          ],
          'environments': [
            for (final appId in _defaultAppIds.values)
              for (final target in defaultEnvironmentTargets)
                {
                  'id': target['environmentTargetId'],
                  'appId': appId,
                  'namedEnvironmentId': target['namedEnvironmentId'],
                  'slug': target['environmentSlug'],
                },
          ],
          'environmentTargets': defaultEnvironmentTargets,
          'surfaces': <Object>[],
          'apiKeys': <Object>[],
        }),
        200,
      );
    case 'listMine':
      return http.Response(
        jsonEncode([
          {'organizationId': 7, 'slug': 'restage', 'name': 'Restage'},
        ]),
        200,
      );
    case 'listApps':
      return http.Response(
        jsonEncode([
          {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
          {'id': 8, 'slug': 'a', 'name': 'A'},
          {'id': 9, 'slug': 'default', 'name': 'Default'},
          {'id': 6, 'slug': 'config-app', 'name': 'Config App'},
          {'id': 7, 'slug': 'flag-app', 'name': 'Flag App'},
        ]),
        200,
      );
    case 'listEnvironmentTargets':
      final plane = body['runtimePlane'] as String?;
      return http.Response(
        jsonEncode([
          for (final target in defaultEnvironmentTargets)
            if (plane == null || target['runtimePlane'] == plane) target,
        ]),
        200,
      );
    case 'resolveTarget':
      return resolveTargetResponse(body);
  }
  return null;
}

/// The publish response the backend returns for [slug].
///
/// One definition of the `SurfaceContractFamilyReference` wire shape, so a
/// change to it does not have to be chased through every publish test.
http.Response publishSucceeded(
  String slug, {
  String surfaceType = 'paywall',
  String sourceKind = 'paywall',
  int storedRevision = 1,
  int? activeRevision = 1,
  bool identityFrozen = false,
}) => http.Response(
  jsonEncode({
    'family': {
      '__className__': 'SurfaceContractFamilyReference',
      'surfaceType': surfaceType,
      'surfaceSlug': slug,
      'sourceKind': sourceKind,
    },
    'storedPublishedRevision': storedRevision,
    'activePublishedRevision': activeRevision,
    'identityFrozen': identityFrozen,
  }),
  200,
);

/// The publication slug one scripted publish request carried.
String publishedSlugOf(http.Request request) =>
    SurfacePublicationUploadRequestV1Codec.decodeJson(
      ((jsonDecode(request.body) as Map<String, dynamic>)['upload']
              as Map<String, dynamic>)['canonicalJson']
          as String,
    ).publication.slug;
